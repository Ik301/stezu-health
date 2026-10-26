"""Health export store for POST /sync (D-048): Apple Health samples and Stezu's own records.

A separate SQLite file (STEZU_HEALTH_DB), WAL mode, mode 0600. Samples are keyed by their
HealthKit UUID and never change once stored. Records are keyed by (kind, id), and the newest
updated_at wins. A deleted sample keeps its row as a tombstone, so replaying an older batch
cannot bring it back. Hermes reads the views read-only. Nothing here calls a model.
"""

from __future__ import annotations

import json
import math
import os
import re
import sqlite3
import threading
import zlib
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

MAX_ITEMS = 5000
WORKOUT = "HKWorkoutTypeIdentifier"
KIND = re.compile(r"[a-z][a-z0-9_]{0,39}")
LOCAL = "%Y-%m-%dT%H:%M:%S"
Q = "HKQuantityTypeIdentifier"

SCHEMA = """
CREATE TABLE IF NOT EXISTS samples (uuid TEXT PRIMARY KEY, type TEXT, start_ts TEXT, end_ts TEXT,
  start_local TEXT, end_local TEXT, utc_offset TEXT, value NUMERIC, unit TEXT, source_name TEXT,
  source_bundle TEXT, metadata_json TEXT, received_at TEXT NOT NULL, deleted_at TEXT);
CREATE INDEX IF NOT EXISTS samples_type_start ON samples (type, start_ts);
CREATE TABLE IF NOT EXISTS records (kind TEXT NOT NULL, id TEXT NOT NULL, updated_at TEXT NOT NULL,
  deleted INTEGER NOT NULL, payload_json TEXT, received_at TEXT NOT NULL, PRIMARY KEY (kind, id));
CREATE TABLE IF NOT EXISTS batches (batch_id TEXT PRIMARY KEY, device_id TEXT NOT NULL,
  received_at TEXT NOT NULL, counts_json TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""

DATE = "'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'"
LB_KG = 0.45359237


def jnum(path: str, src: str = "payload_json") -> str:
    """A JSON number at path, else NULL: a missing, null or non-number field is absent, never 0."""
    return f"CASE WHEN json_type({src}, '{path}') IN ('integer', 'real') THEN json_extract({src}, '{path}') END"


def jtext(*paths: str, src: str = "payload_json") -> str:
    """The first JSON string found at one of paths (the name, then its aliases), else NULL."""
    found = [f"CASE WHEN json_type({src}, '{p}') = 'text' THEN json_extract({src}, '{p}') END" for p in paths]
    return found[0] if len(found) == 1 else f"coalesce({', '.join(found)})"


def jbool(*paths: str) -> str:
    """1 for JSON true, 0 for false, NULL when missing, null or not a boolean."""
    found = [f"CASE json_type(payload_json, '{p}') WHEN 'true' THEN 1 WHEN 'false' THEN 0 END" for p in paths]
    return found[0] if len(found) == 1 else f"coalesce({', '.join(found)})"


def day_of(ts: str) -> str:
    """The payload's own day key, else the date of a timestamp the phone stamped in its own zone."""
    return (f"coalesce(CASE WHEN p_day GLOB {DATE} THEN p_day END,"
            f" CASE WHEN {ts} GLOB {DATE} || 'T*' THEN substr({ts}, 1, 10) END)")


def live(kind: str, *columns: str) -> str:
    """Live records of one kind with payload fields pulled out (tombstones excluded)."""
    return (f"(SELECT id, updated_at, payload_json, {jtext('$.day')} AS p_day, {', '.join(columns)}"
            f" FROM records WHERE kind = '{kind}' AND deleted = 0)")


def range_total(field: str, bound: str) -> str:
    """A meal's items summed like FoodRange.total: NULL when there are no items or any item lacks it."""
    v = f"CASE WHEN i.type = 'object' THEN {jnum(f'$.{field}.{bound}', 'i.value')} END"
    return (f"(SELECT CASE WHEN count(*) > 0 AND count(v) = count(*) THEN sum(v) END FROM (SELECT {v} AS v"
            f" FROM json_each(CASE WHEN json_type(payload_json, '$.items') = 'array' THEN payload_json END,"
            f" '$.items') i))")


def jbetween(path: str, lo: float, hi: float) -> str:
    """A JSON number at path within [lo, hi], else NULL. CoreLocation marks an invalid accuracy or
    speed with a negative value, and a latitude or longitude outside its range is not a place."""
    return f"CASE WHEN {jnum(path)} BETWEEN {lo} AND {hi} THEN {jnum(path)} END"


def jtime(path: str) -> str:
    """An ISO 8601 timestamp string at path, else NULL. A year before 1970 or after 2999 is
    CLVisit's distantPast or distantFuture (an unknown arrival or departure), so it is NULL too."""
    t = jtext(path)
    return f"CASE WHEN {t} GLOB {DATE} || 'T*' AND substr({t}, 1, 4) BETWEEN '1970' AND '2999' THEN {t} END"


# Where a visit or location record says it was (S-032); synthetic in tests, never in the repo.
PLACE = (f"{jbetween('$.latitude', -90, 90)} AS latitude", f"{jbetween('$.longitude', -180, 180)} AS longitude",
         f"{jbetween('$.horizontal_accuracy_m', 0, 1e9)} AS horizontal_accuracy_m")

# A finished session's sets, read from its exercises[].sets[] (objects only, so odd payloads never fail).
SESSION_SETS = ("FROM json_each(CASE WHEN json_type(payload_json, '$.exercises') = 'array' THEN payload_json END,"
                " '$.exercises') e, json_each(coalesce(CASE WHEN e.type = 'object' THEN CASE WHEN"
                " json_type(e.value, '$.sets') = 'array' THEN e.value END END, '{}'), '$.sets') x"
                " WHERE x.type = 'object'")
REPS = f"CASE WHEN x.type = 'object' THEN {jnum('$.reps', 'x.value')} END"
HAS_EXERCISES = "json_type(payload_json, '$.exercises') = 'array'"
POUNDS = f"CASE WHEN {jnum('$.pounds')} > 0 THEN {jnum('$.pounds')} END"  # bodyweight is NULL, never 0

DAILY = {"heart_rate_daily": ["HeartRate"], "resting_hr": ["RestingHeartRate"],
         "hrv": ["HeartRateVariabilitySDNN"], "spo2": ["OxygenSaturation"],
         "respiratory_rate": ["RespiratoryRate"],
         "temperature": ["BodyTemperature", "AppleSleepingWristTemperature", "BasalBodyTemperature"]}
STAGES = {"asleep": "IN (1, 3, 4, 5)", "core": "= 3", "deep": "= 4", "rem": "= 5",
          "unspecified": "= 1", "awake": "= 2", "in_bed": "= 0"}
VIEWS = {
    "live_samples": "SELECT *, substr(start_local, 1, 10) AS day FROM samples"
                    " WHERE deleted_at IS NULL AND start_ts IS NOT NULL",
    "daily_quantity": "SELECT day, type, unit, count(*) AS n, min(value) AS min_value,"
                      " avg(value) AS mean_value, max(value) AS max_value, sum(value) AS sum_value,"
                      " count(DISTINCT source_bundle) AS sources FROM live_samples"
                      " WHERE value IS NOT NULL GROUP BY day, type, unit",
    "steps_by_source": "SELECT day, source_name, source_bundle, sum(value) AS steps, count(*) AS n"
                       f" FROM live_samples WHERE type = '{Q}StepCount'"
                       " GROUP BY day, source_bundle, source_name",
    "daily_steps": "SELECT day, max(steps) AS steps, sum(steps) AS steps_raw_sum, count(*) AS source_count,"
                   " source_name AS top_source, source_bundle AS top_bundle FROM steps_by_source GROUP BY day",
    "sleep_by_source": "SELECT date(end_local, '+6 hours') AS night, source_name, source_bundle, "
                       + ", ".join(f"sum(CASE WHEN value {cond} THEN m END) AS {stage}_min"
                                   for stage, cond in STAGES.items())
                       + ", min(start_local) AS bedtime, max(end_local) AS wake_time, count(*) AS n FROM"
                       " (SELECT *, (julianday(end_ts) - julianday(start_ts)) * 1440.0 AS m FROM live_samples"
                       " WHERE type = 'HKCategoryTypeIdentifierSleepAnalysis')"
                       " GROUP BY night, source_bundle, source_name",
    "sleep_nights": "SELECT night, max(asleep_min) AS asleep_min, core_min, deep_min, rem_min, unspecified_min,"
                    " awake_min, in_bed_min, bedtime, wake_time, source_name, source_bundle,"
                    " count(*) AS source_count FROM sleep_by_source GROUP BY night",
    "body_mass": "SELECT uuid, start_local AS measured_at, day, value, unit, CASE unit WHEN 'kg' THEN value"
                 " WHEN 'lb' THEN value * 0.45359237 WHEN 'g' THEN value / 1000.0 END AS kg, source_name,"
                 " source_bundle, ifnull(source_bundle, '') = 'com.ik301.stezuhealth' AS stezu_weighin"
                 f" FROM live_samples WHERE type = '{Q}BodyMass'",
    "workouts": "SELECT uuid, day, start_local, end_local,"
                " json_extract(metadata_json, '$.activity_type') AS activity_type,"
                " json_extract(metadata_json, '$.activity_name') AS activity_name,"
                " json_extract(metadata_json, '$.duration_s') / 60.0 AS duration_min,"
                " json_extract(metadata_json, '$.total_energy_kcal') AS energy_kcal,"
                " json_extract(metadata_json, '$.total_distance_m') AS distance_m, source_name, source_bundle"
                f" FROM live_samples WHERE type = '{WORKOUT}'",
    "stezu_records": "SELECT kind, id, updated_at, payload_json, received_at FROM records WHERE deleted = 0",
    "stezu_sets": f"SELECT id, session_id, template_key, exercise_key, exercise_name, pounds, reps, logged_at,"
                  f" {day_of('logged_at')} AS day, set_kind AS kind, updated_at FROM "
                  + live("set", f"{jtext('$.session_id')} AS session_id", f"{jtext('$.template_key')} AS template_key",
                         f"{jtext('$.exercise_key')} AS exercise_key",
                         f"{jtext('$.exercise_name', '$.name')} AS exercise_name", f"{POUNDS} AS pounds",
                         f"{jnum('$.reps')} AS reps", f"{jtext('$.logged_at')} AS logged_at",
                         f"{jtext('$.kind')} AS set_kind"),
    "stezu_sessions": f"SELECT id, started_at, ended_at, {day_of('started_at')} AS day, template_key, template_name,"
                      " (julianday(ended_at) - julianday(started_at)) * 1440.0 AS duration_min,"
                      f" CASE WHEN {HAS_EXERCISES} THEN json_array_length(payload_json, '$.exercises') END"
                      f" AS n_exercises, CASE WHEN {HAS_EXERCISES} THEN (SELECT count(*) {SESSION_SETS})"
                      " ELSE (SELECT nullif(count(*), 0) FROM stezu_sets t WHERE t.session_id = s.id) END AS n_sets,"
                      f" CASE WHEN {HAS_EXERCISES} THEN (SELECT sum({REPS}) {SESSION_SETS})"
                      " ELSE (SELECT sum(t.reps) FROM stezu_sets t WHERE t.session_id = s.id) END AS total_reps,"
                      " in_health, updated_at FROM "
                      + live("workout_session", f"{jtext('$.started_at', '$.start')} AS started_at",
                             f"{jtext('$.ended_at', '$.end', '$.finished_at')} AS ended_at",
                             f"{jtext('$.template_key')} AS template_key",
                             f"{jtext('$.template_name', '$.template')} AS template_name",
                             f"{jbool('$.in_health', '$.inHealth')} AS in_health") + " s",
    "stezu_weighins": f"SELECT id, measured_at, {day_of('measured_at')} AS day, pounds, pounds * {LB_KG} AS kg,"
                      " in_health, updated_at FROM "
                      + live("weigh_in", f"{jtext('$.measured_at')} AS measured_at", f"{POUNDS} AS pounds",
                             f"{jbool('$.in_health', '$.inHealth')} AS in_health"),
    "stezu_meals": f"SELECT id, eaten_at, {day_of('eaten_at')} AS day, status, edited, in_health, n_items,"
                   " kcal_low, kcal_high, protein_g_low, protein_g_high, items, updated_at FROM "
                   + live("meal", f"{jtext('$.eaten_at')} AS eaten_at", f"{jtext('$.status')} AS status",
                          f"{jbool('$.edited')} AS edited", f"{jbool('$.in_health')} AS in_health",
                          "CASE WHEN json_type(payload_json, '$.items') = 'array'"
                          " THEN json_array_length(payload_json, '$.items') END AS n_items",
                          *(f"{range_total(f, b)} AS {f}_{b}" for f in ("kcal", "protein_g") for b in ("low", "high")),
                          "(SELECT group_concat(n, '; ') FROM (SELECT CASE WHEN i.type = 'object' THEN"
                          f" {jtext('$.name', src='i.value')} END AS n FROM json_each(CASE WHEN"
                          " json_type(payload_json, '$.items') = 'array' THEN payload_json END, '$.items') i))"
                          " AS items"),
    "stezu_visits": f"SELECT id, arrived_at, departed_at, {day_of('coalesce(arrived_at, departed_at)')} AS day,"
                    " latitude, longitude, horizontal_accuracy_m, CASE WHEN julianday(departed_at) >="
                    " julianday(arrived_at) THEN (julianday(departed_at) - julianday(arrived_at)) * 1440.0 END"
                    " AS duration_min, updated_at FROM "
                    + live("visit", f"{jtime('$.arrived_at')} AS arrived_at",
                           f"{jtime('$.departed_at')} AS departed_at", *PLACE),
    "stezu_locations": f"SELECT id, at, {day_of('at')} AS day, latitude, longitude, horizontal_accuracy_m, speed_mps,"
                       " updated_at FROM "
                       + live("location", f"{jtime('$.at')} AS at", *PLACE,
                              f"{jbetween('$.speed_mps', 0, 1e6)} AS speed_mps"),
    # A day with no visit and no fix has no row; a count with nothing recorded is NULL, never 0.
    "places_daily": "SELECT day, nullif(sum(kind = 'visit'), 0) AS visits,"
                    " nullif(sum(kind = 'location'), 0) AS location_fixes FROM (SELECT day, 'visit' AS kind"
                    " FROM stezu_visits UNION ALL SELECT day, 'location' FROM stezu_locations)"
                    " WHERE day IS NOT NULL GROUP BY day",
} | {name: "SELECT day, type, unit, n, min_value, mean_value, max_value, sources FROM daily_quantity"
           " WHERE type IN (" + ", ".join(f"'{Q}{t}'" for t in types) + ")" for name, types in DAILY.items()}


class TooLarge(Exception):
    pass


def utc(dt: datetime) -> str:
    """Fixed-width UTC text, so string order is time order."""
    return dt.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def parse_ts(value: Any) -> datetime:
    if not isinstance(value, str):
        raise ValueError("timestamps must be ISO 8601 strings")
    dt = datetime.fromisoformat(value)
    if dt.tzinfo is None:
        raise ValueError(f"timestamp {value!r} needs a UTC offset")
    return dt


def text(obj: dict[str, Any], key: str, limit: int, required: bool = True) -> str | None:
    value = obj.get(key)
    if value is None and not required:
        return None
    if not isinstance(value, str) or not 0 < len(value) <= limit:
        raise ValueError(f"{key} must be a string of 1 to {limit} characters")
    return value


def gunzip(data: bytes, limit: int) -> bytes:
    inflater = zlib.decompressobj(wbits=31)
    try:
        out = inflater.decompress(data, limit + 1)
    except zlib.error as exc:
        raise ValueError(f"bad gzip body: {exc}") from None
    if len(out) > limit:
        raise TooLarge("decompressed body too large")
    return out


class HealthDB:
    def __init__(self, path: Path, tz: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.close(os.open(path, os.O_CREAT | os.O_WRONLY, 0o600))
        os.chmod(path, 0o600)
        self.tz = ZoneInfo(tz)
        self._db = sqlite3.connect(str(path), check_same_thread=False)
        self._lock = threading.Lock()
        with self._lock, self._db as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("PRAGMA synchronous=NORMAL")
            db.executescript(SCHEMA + "".join(f"DROP VIEW IF EXISTS {v};" for v in VIEWS))
            for name, sql in VIEWS.items():
                db.execute(f"CREATE VIEW {name} AS {sql}")
            stored = db.execute("SELECT value FROM meta WHERE key = 'tz'").fetchone()
            if stored is None or stored[0] != tz:  # day keys follow the configured zone
                rows = db.execute("SELECT uuid, start_ts, end_ts FROM samples WHERE start_ts IS NOT NULL")
                db.executemany("UPDATE samples SET start_local = ?, end_local = ? WHERE uuid = ?",
                               [(self.local(parse_ts(s)), self.local(parse_ts(e)), u) for u, s, e in rows.fetchall()])
                db.execute("INSERT OR REPLACE INTO meta VALUES ('tz', ?)", (tz,))

    def local(self, dt: datetime) -> str:
        return dt.astimezone(self.tz).strftime(LOCAL)

    def sample(self, s: Any, now: str) -> tuple[Any, ...]:
        if not isinstance(s, dict):
            raise ValueError("must be an object")
        uuid, kind = str(text(s, "uuid", 64)).upper(), str(text(s, "type", 120))
        if not kind.startswith("HK"):
            raise ValueError("type must be a HealthKit identifier")
        start, end = parse_ts(s.get("start")), parse_ts(s.get("end"))
        if end < start:
            raise ValueError("end is before start")
        value, meta = s.get("value"), s.get("metadata")
        if value is None and kind != WORKOUT:
            raise ValueError("value is required")
        if value is not None and (isinstance(value, bool) or not isinstance(value, int | float)
                                  or not math.isfinite(value)):
            raise ValueError("value must be a finite number")
        if meta is not None and not isinstance(meta, dict):
            raise ValueError("metadata must be an object")
        return (uuid, kind, utc(start), utc(end), self.local(start), self.local(end), start.isoformat()[-6:],
                value, text(s, "unit", 40, False), text(s, "source_name", 200, False),
                text(s, "source_bundle", 200, False), None if meta is None else json.dumps(meta), now)

    @staticmethod
    def record(r: Any, now: str) -> tuple[Any, ...]:
        if not isinstance(r, dict):
            raise ValueError("must be an object")
        kind, rid = str(text(r, "kind", 40)), text(r, "id", 128)
        deleted, payload = r.get("deleted", False), r.get("payload")
        if not KIND.fullmatch(kind):
            raise ValueError("kind must be lowercase letters, digits and _")
        if not isinstance(deleted, bool):
            raise ValueError("deleted must be true or false")
        if not isinstance(payload, dict) and not (deleted and payload is None):
            raise ValueError("payload must be an object (or null when deleted)")
        return (kind, rid, utc(parse_ts(r.get("updated_at"))), int(deleted),
                None if payload is None else json.dumps(payload), now)

    @staticmethod
    def deletion(d: Any, now: str) -> tuple[Any, ...]:
        if not isinstance(d, dict):
            raise ValueError("must be an object")
        return (str(text(d, "uuid", 64)).upper(), text(d, "type", 120, False))

    def ingest(self, body: dict[str, Any]) -> dict[str, Any]:
        device, batch = text(body, "device_id", 128), text(body, "batch_id", 128)
        lists = {k: [] if body.get(k) is None else body[k] for k in ("samples", "deleted", "records")}
        if not all(isinstance(v, list) for v in lists.values()):
            raise ValueError("samples, deleted and records must be arrays")
        if sum(map(len, lists.values())) > MAX_ITEMS:
            raise TooLarge(f"at most {MAX_ITEMS} items per batch")
        now, errors = utc(datetime.now(UTC)), []
        valid: dict[str, list[tuple[Any, ...]]] = {}
        for name, check in (("samples", self.sample), ("deleted", self.deletion), ("records", self.record)):
            valid[name] = []
            for i, item in enumerate(lists[name]):
                try:
                    valid[name].append(check(item, now))
                except (ValueError, TypeError) as exc:
                    errors.append(f"{name}[{i}]: {exc}")
        with self._lock, self._db as db:
            start = db.total_changes
            db.executemany("INSERT INTO samples VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)"
                           " ON CONFLICT (uuid) DO NOTHING", valid["samples"])
            db.executemany("INSERT INTO records VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT (kind, id) DO UPDATE SET"
                           " updated_at = excluded.updated_at, deleted = excluded.deleted, payload_json ="
                           " excluded.payload_json, received_at = excluded.received_at"
                           " WHERE excluded.updated_at > records.updated_at", valid["records"])
            accepted = db.total_changes - start
            db.executemany("UPDATE samples SET deleted_at = ? WHERE uuid = ? AND deleted_at IS NULL",
                           [(now, u) for u, _ in valid["deleted"]])
            db.executemany("INSERT INTO samples (uuid, type, received_at, deleted_at) VALUES (?, ?, ?, ?)"
                           " ON CONFLICT (uuid) DO NOTHING", [(u, t, now, now) for u, t in valid["deleted"]])
            deleted = db.total_changes - start - accepted
            counts = {"accepted": accepted, "duplicates": sum(map(len, valid.values())) - accepted - deleted,
                      "deleted": deleted, "rejected": len(errors)}
            db.execute("INSERT INTO batches VALUES (?, ?, ?, ?) ON CONFLICT (batch_id) DO UPDATE SET"
                       " device_id = excluded.device_id, received_at = excluded.received_at,"
                       " counts_json = excluded.counts_json", (batch, device, now, json.dumps(counts)))
        return counts | {"errors": errors[:20], "server_time": now}

    def status(self) -> dict[str, Any]:
        with self._lock:
            types = self._db.execute(
                "SELECT type, count(*) - count(deleted_at), count(deleted_at), min(CASE WHEN deleted_at IS NULL"
                " THEN start_ts END), max(CASE WHEN deleted_at IS NULL THEN start_ts END)"
                " FROM samples GROUP BY type ORDER BY type").fetchall()
            kinds = self._db.execute("SELECT kind, total(deleted = 0), total(deleted), max(updated_at)"
                                     " FROM records GROUP BY kind ORDER BY kind").fetchall()
            devices = self._db.execute("SELECT device_id, max(received_at), batch_id, count(*) FROM batches"
                                       " GROUP BY device_id ORDER BY device_id").fetchall()
        return {
            "server_time": utc(datetime.now(UTC)),
            "samples_total": sum(t[1] for t in types),
            "records_total": int(sum(k[1] for k in kinds)),
            "types": [{"type": t, "count": n, "deleted": d, "first_start": a, "last_start": b}
                      for t, n, d, a, b in types],
            "kinds": [{"kind": k, "count": int(n), "deleted": int(d), "last_updated_at": u}
                      for k, n, d, u in kinds],
            "devices": [{"device_id": d, "last_batch_at": t, "last_batch_id": b, "batches": n}
                        for d, t, b, n in devices],
        }
