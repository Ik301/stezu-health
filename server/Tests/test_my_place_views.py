"""Isaac's own places (D-140): `my_place` records at /sync and the views that name visits by them
(stezu_my_places, stezu_visits_named, place_time_daily).

Every name and coordinate here is synthetic. At latitude 0, 0.001 degrees is 111.2 m.
"""

from __future__ import annotations

import math
import sqlite3

import pytest

from stezu_server.health import HealthDB

VIEWS = ("stezu_my_places", "stezu_visits_named", "place_time_daily")
T0 = "2026-10-21T08:00:00.000-04:00"


def rec(kind, rid, payload, at=T0, deleted=False):
    return {"kind": kind, "id": rid, "updated_at": at, "deleted": deleted, "payload": payload}


def place(pid, name, lat, lon, radius_m, note=None, created_at="2026-10-20T12:00:00.000-04:00", at=T0):
    return rec("my_place", pid, {"id": pid, "name": name, "note": note, "latitude": lat, "longitude": lon,
                                 "radius_m": radius_m, "created_at": created_at}, at=at)


def visit(vid, lat, lon, arrived="2026-10-21T09:00:00.000-04:00", departed=None):
    return rec("visit", vid, {"id": vid, "arrived_at": arrived, "departed_at": departed, "latitude": lat,
                              "longitude": lon, "horizontal_accuracy_m": 20.0, "day": arrived[:10]})


@pytest.fixture
def db(tmp_path):
    path = tmp_path / "health.db"
    store = HealthDB(path, "America/New_York")
    batches = iter(range(10_000))

    def send(*records):
        return store.ingest({"device_id": "device-test", "batch_id": f"b-{next(batches)}",
                             "records": list(records)})

    def ingest(*records):
        counts = send(*records)
        assert counts["rejected"] == 0, counts["errors"]
        return counts

    def rows(view, key="id"):
        with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as ro:
            ro.row_factory = sqlite3.Row
            return {r[key]: dict(r) for r in ro.execute(f"SELECT * FROM {view} ORDER BY {key}")}

    def named():
        return {k: r["my_place_name"] for k, r in rows("stezu_visits_named").items()}

    return send, ingest, rows, named


CAMPUS = place("p-campus", "Campus", 0.0, 0.0, 1000)
LIBRARY = place("p-library", "Library", 0.0, 0.001, 50)  # inside Campus, 111 m east of its centre
GYM = place("p-gym", "Gym", 0.01, 0.0, 100)  # 1.1 km north, outside Campus


def test_visit_takes_the_smallest_enclosing_place_or_null(db):
    _, ingest, rows, named = db
    ingest(CAMPUS, LIBRARY, GYM,
           visit("v-library", 0.0, 0.0012),  # 22 m from Library, 133 m from Campus: both, Library wins
           visit("v-campus", 0.0, -0.002),  # 222 m from Campus only
           visit("v-gym", 0.0105, 0.0),  # 56 m from Gym
           visit("v-gym-edge-in", 0.01089, 0.0),  # 99.0 m: inside a 100 m circle
           visit("v-gym-edge-out", 0.01091, 0.0),  # 101.2 m: outside it, and 1.2 km from Campus
           visit("v-far", 0.05, 0.05),
           rec("visit", "v-no-coords", {"arrived_at": "2026-10-21T09:00:00.000-04:00"}))
    assert named() == {"v-campus": "Campus", "v-far": None, "v-gym": "Gym", "v-gym-edge-in": "Gym",
                       "v-gym-edge-out": None, "v-library": "Library", "v-no-coords": None}
    row = rows("stezu_visits_named")["v-library"]
    assert row["my_place_id"] == "p-library"
    # Every stezu_visits column is kept, in order, before the two place columns.
    assert list(row) == [*rows("stezu_visits")["v-library"], "my_place_id", "my_place_name"]
    assert rows("stezu_visits_named")["v-far"]["my_place_id"] is None


def test_distance_shrinks_east_west_with_latitude(db):
    _, ingest, _, named = db
    # At 60 degrees a degree of longitude is half as long: 0.001 is 55.6 m, not 111 m.
    ingest(place("p-north", "North", 60.0, 0.0, 60),
           visit("v-in", 60.0, 0.001), visit("v-out", 60.0, 0.0011))
    assert named() == {"v-in": "North", "v-out": None}
    expected = 6371000 * 2 * math.asin(math.sin(math.radians(0.001) / 2) * math.cos(math.radians(60)))
    assert expected == pytest.approx(55.6, abs=0.1)


def test_deleted_place_stops_matching(db):
    _, ingest, rows, named = db
    ingest(CAMPUS, LIBRARY, visit("v-library", 0.0, 0.0012))
    assert named() == {"v-library": "Library"}
    counts = ingest(rec("my_place", "p-library", None, at="2026-10-21T09:00:00.000-04:00", deleted=True))
    assert counts["accepted"] == 1
    assert named() == {"v-library": "Campus"}  # the next smallest circle that holds it
    assert set(rows("stezu_my_places")) == {"p-campus"}
    ingest(rec("my_place", "p-campus", None, at="2026-10-21T09:00:00.000-04:00", deleted=True))
    assert named() == {"v-library": None}
    assert ingest(LIBRARY)["duplicates"] == 1  # replaying the older version cannot bring it back
    assert named() == {"v-library": None}


def test_newer_edit_moves_or_resizes_the_match(db):
    _, ingest, rows, named = db
    ingest(CAMPUS, GYM, visit("v-campus", 0.0, -0.002), visit("v-gym", 0.0105, 0.0), visit("v-far", 0.05, 0.05))
    assert named() == {"v-campus": "Campus", "v-far": None, "v-gym": "Gym"}
    later = "2026-10-21T10:00:00.000-04:00"
    ingest(place("p-gym", "Gym", 0.05, 0.05, 100, at=later),  # moved
           place("p-campus", "Campus", 0.0, 0.0, 100, at=later))  # shrunk below 222 m
    assert named() == {"v-campus": None, "v-far": "Gym", "v-gym": None}
    ingest(place("p-campus", "Main campus", 0.0, 0.0, 300, at="2026-10-21T11:00:00.000-04:00"))  # renamed, grown
    assert named() == {"v-campus": "Main campus", "v-far": "Gym", "v-gym": None}
    assert ingest(GYM)["duplicates"] == 1  # an older version changes nothing
    assert rows("stezu_my_places")["p-gym"]["latitude"] == 0.05


def test_place_time_daily_sums_known_durations(db, tmp_path):
    _, ingest, _, _ = db
    ingest(CAMPUS, LIBRARY, GYM, place("p-gym-2", "Gym", 0.05, 0.05, 100),
           visit("lib-1", 0.0, 0.0012, "2026-10-21T09:00:00.000-04:00", "2026-10-21T10:30:00.000-04:00"),
           visit("lib-2", 0.0, 0.0011, "2026-10-21T14:00:00.000-04:00", "2026-10-21T14:45:00.000-04:00"),
           visit("lib-open", 0.0, 0.001, "2026-10-21T16:00:00.000-04:00"),  # no departure yet
           visit("nowhere", 0.2, 0.2, "2026-10-21T18:00:00.000-04:00", "2026-10-21T19:00:00.000-04:00"),
           visit("gym-1", 0.0105, 0.0, "2026-10-22T07:00:00.000-04:00", "2026-10-22T08:00:00.000-04:00"),
           visit("campus-open", 0.0, -0.002, "2026-10-22T12:00:00.000-04:00"),
           # Two circles with the same name: one Gym row for the day.
           visit("gym-a", 0.0105, 0.0, "2026-10-23T07:00:00.000-04:00", "2026-10-23T07:30:00.000-04:00"),
           visit("gym-b", 0.05, 0.05, "2026-10-23T18:00:00.000-04:00", "2026-10-23T18:20:00.000-04:00"))
    with sqlite3.connect(f"file:{tmp_path / 'health.db'}?mode=ro", uri=True) as ro:
        got = {(day, name): rest for day, name, *rest in ro.execute(
            "SELECT day, my_place_name, visits, timed_visits, total_min FROM place_time_daily")}
    got = {k: tuple(v) for k, v in got.items()}
    assert got == {("2026-10-21", "Library"): (3, 2, 135.0),
                   ("2026-10-22", "Campus"): (1, 0, None),  # visited, but no duration known: NULL, not 0
                   ("2026-10-22", "Gym"): (1, 1, 60.0),
                   ("2026-10-23", "Gym"): (2, 2, 50.0)}


def test_my_places_view_columns(db):
    _, ingest, rows, _ = db
    ingest(place("p-1", "  Library  ", 0.0, 0.001, 50, note=" "),
           place("p-2", "Gym", 0.01, 0.0, 10, note="Leg day", created_at="2026-10-19T07:00:00.000-04:00"))
    assert rows("stezu_my_places") == {
        "p-1": {"id": "p-1", "name": "Library", "note": None, "latitude": 0.0, "longitude": 0.001,
                "radius_m": 50, "created_at": "2026-10-20T12:00:00.000-04:00",
                "updated_at": "2026-10-21T12:00:00.000Z"},
        "p-2": {"id": "p-2", "name": "Gym", "note": "Leg day", "latitude": 0.01, "longitude": 0.0,
                "radius_m": 10, "created_at": "2026-10-19T07:00:00.000-04:00",
                "updated_at": "2026-10-21T12:00:00.000Z"}}


@pytest.mark.parametrize("change, error", [
    ({"latitude": 90.5}, "my_place latitude must be a number from -90 to 90"),
    ({"latitude": True}, "my_place latitude must be a number from -90 to 90"),
    ({"longitude": -180.01}, "my_place longitude must be a number from -180 to 180"),
    ({"longitude": None}, "my_place longitude must be a number from -180 to 180"),
    ({"radius_m": 9.99}, "my_place radius_m must be a number from 10 to 2000"),
    ({"radius_m": 2000.5}, "my_place radius_m must be a number from 10 to 2000"),
    ({"radius_m": "75"}, "my_place radius_m must be a number from 10 to 2000"),
    ({"name": ""}, "my_place name must be a non-blank string of at most 200 characters"),
    ({"name": "   "}, "my_place name must be a non-blank string of at most 200 characters"),
    ({"name": None}, "my_place name must be a non-blank string of at most 200 characters"),
    ({"name": "x" * 201}, "my_place name must be a non-blank string of at most 200 characters"),
    ({"note": 3}, "my_place note must be null or a string of at most 1000 characters"),
    ({"created_at": None}, "my_place created_at: timestamps must be ISO 8601 strings"),
    ({"created_at": "2026-10-20T12:00:00"}, "my_place created_at: timestamp '2026-10-20T12:00:00' needs a UTC offset"),
    ({"id": "p-other"}, "my_place payload id must equal the record id"),
])
def test_invalid_my_place_is_rejected_with_a_clear_error(db, change, error):
    send, _, rows, _ = db
    good = place("p-ok", "Gym", 0.01, 0.0, 100)
    bad = place("p-bad", "Gym", 0.01, 0.0, 100)
    bad["payload"] = bad["payload"] | change
    counts = send(good, bad)
    assert (counts["accepted"], counts["rejected"]) == (1, 1)
    assert counts["errors"] == [f"records[1]: {error}"]
    assert set(rows("stezu_my_places")) == {"p-ok"}


def test_limits_are_inclusive_and_tombstones_need_no_payload(db):
    send, _, rows, _ = db
    counts = send(place("p-min", "Small", -90, -180, 10), place("p-max", "Big", 90, 180, 2000),
                  rec("my_place", "p-gone", None, deleted=True),
                  rec("my_place", "p-gone-2", {"id": "p-gone-2"}, deleted=True))
    assert (counts["accepted"], counts["rejected"]) == (4, 0), counts["errors"]
    assert set(rows("stezu_my_places")) == {"p-min", "p-max"}


def test_my_place_views_exist_and_read_only_access_works(db, tmp_path):
    _, _, rows, _ = db
    assert rows("stezu_my_places") == rows("stezu_visits_named") == {}
    assert rows("place_time_daily", key="day") == {}
    with sqlite3.connect(f"file:{tmp_path / 'health.db'}?mode=ro", uri=True) as ro:
        names = {r[0] for r in ro.execute("SELECT name FROM sqlite_master WHERE type = 'view'")}
        assert set(VIEWS) <= names
        with pytest.raises(sqlite3.OperationalError):
            ro.execute("INSERT INTO records VALUES ('my_place', 'x', 'now', 0, '{}', 'now')")
