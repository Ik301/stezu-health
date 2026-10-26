"""POST /sync and GET /sync/status: idempotency, deletion, records, limits and the Hermes views.

Every value here is synthetic. Day keys use America/New_York (EDT, UTC-04:00, in October).
"""

from __future__ import annotations

import gzip
import json
import sqlite3
import stat
import time

import pytest

from stezu_server.health import MAX_ITEMS, HealthDB

Q = "HKQuantityTypeIdentifier"
SLEEP = "HKCategoryTypeIdentifierSleepAnalysis"
PHONE, WATCH, STEZU = "com.example.phone", "com.example.watch", "com.ik301.stezuhealth"


def sample(uuid, kind, start, end=None, value=1.0, unit="count", bundle=PHONE, **extra):
    return {"uuid": uuid, "type": kind, "start": start, "end": end or start, "value": value, "unit": unit,
            "source_name": bundle.rsplit(".", 1)[-1].title(), "source_bundle": bundle} | extra


def batch(batch_id="b-1", samples=(), deleted=(), records=()):
    return {"device_id": "device-test", "batch_id": batch_id, "samples": list(samples),
            "deleted": list(deleted), "records": list(records)}


def db_rows(settings, sql):
    with sqlite3.connect(settings.db_path.with_name("health.db")) as db:
        db.row_factory = sqlite3.Row
        return [dict(r) for r in db.execute(sql)]


STEPS = [
    sample("S-1", f"{Q}StepCount", "2026-10-21T08:00:00-04:00", "2026-10-21T09:00:00-04:00", 4000),
    sample("S-2", f"{Q}StepCount", "2026-10-21T18:00:00-04:00", "2026-10-21T19:00:00-04:00", 1000),
    sample("S-3", f"{Q}StepCount", "2026-10-21T08:00:00-04:00", "2026-10-21T19:00:00-04:00", 4500, bundle=WATCH),
    # 01:30 UTC on the 22nd is 21:30 on the 21st in New York.
    sample("S-4", f"{Q}StepCount", "2026-10-22T01:30:00Z", "2026-10-22T01:45:00Z", 300),
]


def test_sync_needs_token(make_client):
    client = make_client()
    client.headers.pop("Authorization")
    assert client.post("/sync", json=batch()).status_code == 401
    assert client.get("/sync/status").status_code == 401
    assert client.get("/sync/status", headers={"Authorization": "Bearer nope"}).status_code == 401


def test_replaying_a_batch_changes_nothing(make_client, settings):
    client = make_client()
    rec = {"kind": "set", "id": "set-1", "updated_at": "2026-10-21T10:00:00-04:00", "deleted": False,
           "payload": {"exercise": "Bench Press", "reps": 8}}
    first = client.post("/sync", json=batch(samples=STEPS, records=[rec])).json()
    assert (first["accepted"], first["duplicates"], first["deleted"], first["rejected"]) == (5, 0, 0, 0)
    assert first["server_time"].endswith("Z")
    before = db_rows(settings, "SELECT * FROM samples ORDER BY uuid")
    again = client.post("/sync", json=batch(samples=STEPS, records=[rec])).json()
    assert (again["accepted"], again["duplicates"], again["deleted"]) == (0, 5, 0)
    assert db_rows(settings, "SELECT * FROM samples ORDER BY uuid") == before
    assert before[0]["start_ts"] == "2026-10-21T12:00:00.000Z" and before[0]["utc_offset"] == "-04:00"
    status = client.get("/sync/status").json()
    assert status["samples_total"] == 4 and status["records_total"] == 1
    assert status["types"] == [{"type": f"{Q}StepCount", "count": 4, "deleted": 0,
                                "first_start": "2026-10-21T12:00:00.000Z",
                                "last_start": "2026-10-22T01:30:00.000Z"}]
    assert status["kinds"][0] | {"last_updated_at": None} == {"kind": "set", "count": 1, "deleted": 0,
                                                               "last_updated_at": None}
    assert [(d["device_id"], d["batches"], d["last_batch_id"]) for d in status["devices"]] == [
        ("device-test", 1, "b-1")]


def test_deleted_samples_stay_deleted_when_an_old_batch_is_replayed(make_client, settings):
    client = make_client()
    client.post("/sync", json=batch(samples=STEPS))
    gone = client.post("/sync", json=batch("b-2", deleted=[{"uuid": "s-1", "type": f"{Q}StepCount"},
                                                            {"uuid": "NEVER-SEEN", "type": f"{Q}HeartRate"}])).json()
    assert (gone["deleted"], gone["duplicates"]) == (2, 0)
    replay = client.post("/sync", json=batch(samples=STEPS + [sample("NEVER-SEEN", f"{Q}HeartRate",
                                                                       "2026-10-21T08:00:00-04:00")])).json()
    assert (replay["accepted"], replay["duplicates"]) == (0, 5)
    assert client.post("/sync", json=batch("b-2", deleted=[{"uuid": "S-1"}])).json()["duplicates"] == 1
    live = db_rows(settings, "SELECT uuid FROM live_samples ORDER BY uuid")
    assert [r["uuid"] for r in live] == ["S-2", "S-3", "S-4"]
    types = {t["type"]: t for t in client.get("/sync/status").json()["types"]}
    assert (types[f"{Q}StepCount"]["count"], types[f"{Q}StepCount"]["deleted"]) == (3, 1)
    assert types[f"{Q}HeartRate"] | {} == {"type": f"{Q}HeartRate", "count": 0, "deleted": 1,
                                           "first_start": None, "last_start": None}


def test_records_keep_the_newest_version_and_tombstones(make_client, settings):
    client = make_client()

    def rec(updated, deleted=False, reps=8):
        return {"kind": "meal", "id": "meal-1", "updated_at": updated, "deleted": deleted,
                "payload": None if deleted else {"name": "Oatmeal", "kcal": {"low": 250, "high": 350}, "reps": reps}}

    assert client.post("/sync", json=batch(records=[rec("2026-10-21T12:00:00Z")])).json()["accepted"] == 1
    older = client.post("/sync", json=batch("b-2", records=[rec("2026-10-21T07:00:00-04:00", reps=1)])).json()
    assert (older["accepted"], older["duplicates"]) == (0, 1)  # 11:00Z is older than 12:00Z
    newer = client.post("/sync", json=batch("b-3", records=[rec("2026-10-21T09:00:00-04:00", reps=10)])).json()
    assert newer["accepted"] == 1
    assert json.loads(db_rows(settings, "SELECT payload_json FROM records")[0]["payload_json"])["reps"] == 10
    client.post("/sync", json=batch("b-4", records=[rec("2026-10-21T14:00:00Z", deleted=True)]))
    assert db_rows(settings, "SELECT * FROM stezu_records") == []
    kinds = client.get("/sync/status").json()["kinds"]
    assert (kinds[0]["count"], kinds[0]["deleted"]) == (0, 1)


def test_bad_items_are_rejected_without_sinking_the_batch(make_client):
    client = make_client()
    bad = [sample("B-1", f"{Q}HeartRate", "2026-10-21T08:00:00"),  # no offset
           sample("B-2", f"{Q}HeartRate", "2026-10-21T08:00:00Z", value="72"),
           sample("B-3", f"{Q}HeartRate", "2026-10-21T08:00:00Z", value=None),
           sample("B-4", f"{Q}HeartRate", "2026-10-21T09:00:00Z", "2026-10-21T08:00:00Z")]
    body = client.post("/sync", json=batch(samples=STEPS[:1] + bad, records=[{"kind": "Meal", "id": "x"}])).json()
    assert (body["accepted"], body["rejected"]) == (1, 5)
    assert body["errors"][0].startswith("samples[1]:")
    workout = sample("W-1", "HKWorkoutTypeIdentifier", "2026-10-21T17:00:00-04:00", "2026-10-21T18:00:00-04:00",
                     value=None, unit=None, metadata={"activity_type": 50, "duration_s": 3600})
    assert client.post("/sync", json=batch("b-2", samples=[workout])).json()["accepted"] == 1
    assert client.post("/sync", json={"batch_id": "b"}).status_code == 400
    assert client.post("/sync", json=[1]).status_code == 400
    assert client.post("/sync", content=b"not json").status_code == 400
    assert client.post("/sync", json=batch() | {"samples": {}}).status_code == 400


def test_batch_limit_and_speed(make_client, settings):
    client = make_client()
    items = [sample(f"HR-{i:05d}", f"{Q}HeartRate", f"2026-10-{1 + i // 1440:02d}T{i // 60 % 24:02d}:{i % 60:02d}:00-04:00",
                    value=60 + i % 40, unit="count/min", metadata={"HKMetadataKeyHeartRateMotionContext": 1})
             for i in range(MAX_ITEMS)]
    assert client.post("/sync", json=batch(samples=items + [items[0]])).status_code == 413
    started = time.monotonic()
    body = client.post("/sync", json=batch(samples=items)).json()
    assert body["accepted"] == MAX_ITEMS
    assert time.monotonic() - started < 5.0
    assert client.post("/sync", json=batch(samples=items)).json()["duplicates"] == MAX_ITEMS


def test_gzip_body(make_client):
    client = make_client()
    raw = gzip.compress(json.dumps(batch(samples=STEPS)).encode())
    headers = {"Content-Encoding": "gzip", "Content-Type": "application/json"}
    assert client.post("/sync", content=raw, headers=headers).json()["accepted"] == 4
    assert client.post("/sync", content=b"\x1f\x8bnope", headers=headers).status_code == 400


def test_views_merge_sources_without_double_counting(make_client, settings):
    stage = {"in_bed": 0, "core": 3, "deep": 4, "rem": 5, "awake": 2}
    sleep = [  # one night, waking 2026-10-22; a segment ending before midnight still belongs to it
        sample("Z-1", SLEEP, "2026-10-21T23:00:00-04:00", "2026-10-21T23:30:00-04:00", stage["core"], None, WATCH),
        sample("Z-2", SLEEP, "2026-10-21T23:30:00-04:00", "2026-10-22T01:00:00-04:00", stage["deep"], None, WATCH),
        sample("Z-3", SLEEP, "2026-10-22T01:00:00-04:00", "2026-10-22T01:10:00-04:00", stage["awake"], None, WATCH),
        sample("Z-4", SLEEP, "2026-10-22T01:10:00-04:00", "2026-10-22T06:40:00-04:00", stage["rem"], None, WATCH),
        sample("Z-5", SLEEP, "2026-10-21T22:45:00-04:00", "2026-10-22T07:00:00-04:00", stage["in_bed"], None, PHONE),
    ]
    other = [
        sample("M-1", f"{Q}BodyMass", "2026-10-21T07:00:00-04:00", value=180.0, unit="lb", bundle=STEZU),
        sample("M-2", f"{Q}BodyMass", "2026-10-21T07:05:00-04:00", value=70.0, unit="kg", bundle=WATCH),
        sample("H-1", f"{Q}HeartRate", "2026-10-21T08:00:00-04:00", value=60, unit="count/min", bundle=WATCH),
        sample("H-2", f"{Q}HeartRate", "2026-10-21T12:00:00-04:00", value=90, unit="count/min", bundle=WATCH),
        sample("H-3", f"{Q}HeartRate", "2026-10-21T23:59:00-04:00", value=75, unit="count/min", bundle=WATCH),
        sample("R-1", f"{Q}RestingHeartRate", "2026-10-21T06:00:00-04:00", value=55, unit="count/min"),
    ]
    make_client().post("/sync", json=batch(samples=STEPS + sleep + other))
    # Health merges overlapping sources by priority; the raw sum (9,800) double counts the morning.
    steps = db_rows(settings, "SELECT * FROM daily_steps ORDER BY day")
    assert steps == [{"day": "2026-10-21", "steps": 5300, "steps_raw_sum": 9800, "source_count": 2,
                      "top_source": "Phone", "top_bundle": PHONE}]
    night = db_rows(settings, "SELECT * FROM sleep_nights")[0]
    assert night["night"] == "2026-10-22" and night["source_bundle"] == WATCH and night["source_count"] == 2
    assert [round(night[k]) for k in ("asleep_min", "core_min", "deep_min", "rem_min", "awake_min")] == [
        450, 30, 90, 330, 10]
    assert night["unspecified_min"] is None and night["in_bed_min"] is None  # absent, not zero
    mass = db_rows(settings, "SELECT uuid, round(kg, 2) AS kg, stezu_weighin FROM body_mass ORDER BY uuid")
    assert mass == [{"uuid": "M-1", "kg": 81.65, "stezu_weighin": 1}, {"uuid": "M-2", "kg": 70.0, "stezu_weighin": 0}]
    hr = db_rows(settings, "SELECT day, n, min_value, mean_value, max_value FROM heart_rate_daily")
    assert hr == [{"day": "2026-10-21", "n": 3, "min_value": 60, "mean_value": 75.0, "max_value": 90}]
    assert db_rows(settings, "SELECT day, mean_value FROM resting_hr") == [{"day": "2026-10-21", "mean_value": 55.0}]
    for empty in ("hrv", "spo2", "respiratory_rate", "temperature", "workouts"):
        assert db_rows(settings, f"SELECT * FROM {empty}") == []


def test_database_file_is_private_wal_and_follows_the_time_zone(tmp_path):
    path = tmp_path / "data" / "health.db"
    store = HealthDB(path, "America/New_York")
    store.ingest(batch(samples=STEPS[3:]))
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    with sqlite3.connect(path) as db:
        assert db.execute("PRAGMA journal_mode").fetchone()[0] == "wal"
        assert db.execute("SELECT day FROM live_samples").fetchone()[0] == "2026-10-21"
    HealthDB(path, "UTC")
    with sqlite3.connect(path) as db:
        assert db.execute("SELECT day FROM live_samples").fetchone()[0] == "2026-10-22"


@pytest.mark.parametrize("bad", ["Not/A_Zone"])
def test_unknown_time_zone_fails_at_start(tmp_path, bad):
    with pytest.raises(Exception):
        HealthDB(tmp_path / "h.db", bad)
