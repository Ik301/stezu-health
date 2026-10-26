"""The place views Hermes reads (stezu_visits, stezu_locations, places_daily), fed by S-032.

Every coordinate here is synthetic (0.0, 1.0, -1.0). Missing or odd fields must read as NULL,
never 0, and never make a view fail. Times carry the phone's offset (EDT, -04:00).
"""

from __future__ import annotations

import sqlite3

import pytest

from stezu_server.health import HealthDB

VIEWS = ("stezu_visits", "stezu_locations", "places_daily")


def rec(kind, rid, payload, at="2026-10-21T10:00:00.000-04:00", deleted=False):
    return {"kind": kind, "id": rid, "updated_at": at, "deleted": deleted, "payload": payload}


def visit(vid, arrived="2026-10-21T09:00:00.000-04:00", departed=None, **extra):
    return {"id": vid, "arrived_at": arrived, "departed_at": departed, "latitude": 0.0, "longitude": 0.0,
            "horizontal_accuracy_m": 50.0, "day": (arrived or departed or "")[:10] or None} | extra


def fix(fid, at="2026-10-21T12:00:00.000-04:00", **extra):
    return {"id": fid, "at": at, "latitude": 1.0, "longitude": -1.0, "horizontal_accuracy_m": 100.0,
            "speed_mps": None, "day": at[:10]} | extra


@pytest.fixture
def db(tmp_path):
    path = tmp_path / "health.db"
    store = HealthDB(path, "America/New_York")
    batches = iter(range(10_000))

    def ingest(*records):
        counts = store.ingest({"device_id": "device-test", "batch_id": f"b-{next(batches)}",
                               "records": list(records)})
        assert counts["rejected"] == 0, counts["errors"]
        return counts

    def rows(view, key="id"):
        with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as ro:
            ro.row_factory = sqlite3.Row
            return {r[key]: dict(r) for r in ro.execute(f"SELECT * FROM {view} ORDER BY {key}")}

    return ingest, rows


def test_visit_departure_updates_the_same_row(db):
    ingest, rows = db
    ingest(rec("visit", "v-1", visit("v-1")))
    open_visit = rows("stezu_visits")["v-1"]
    assert open_visit["departed_at"] is None and open_visit["duration_min"] is None
    assert open_visit["day"] == "2026-10-21"
    # The departure arrives later: same id, newer updated_at.
    counts = ingest(rec("visit", "v-1", visit("v-1", departed="2026-10-21T10:30:00.000-04:00"),
                        at="2026-10-21T10:30:01.000-04:00"))
    assert counts["accepted"] == 1
    # Replaying the open version changes nothing.
    assert ingest(rec("visit", "v-1", visit("v-1")))["duplicates"] == 1
    visits = rows("stezu_visits")
    assert list(visits) == ["v-1"]
    assert visits["v-1"] | {"updated_at": None} == {
        "id": "v-1", "arrived_at": "2026-10-21T09:00:00.000-04:00",
        "departed_at": "2026-10-21T10:30:00.000-04:00", "day": "2026-10-21", "latitude": 0.0,
        "longitude": 0.0, "horizontal_accuracy_m": 50.0, "duration_min": pytest.approx(90.0),
        "updated_at": None}


def test_missing_or_odd_place_fields_are_null_not_zero(db):
    ingest, rows = db
    ingest(rec("visit", "bare", {}), rec("location", "bare", {}),
           # CLVisit's unknown ends, as an app might send them, and impossible values.
           rec("visit", "odd", {"arrived_at": "0001-01-01T00:00:00.000Z",
                                "departed_at": "4001-01-01T00:00:00.000Z",
                                "latitude": 200.0, "longitude": "0", "horizontal_accuracy_m": -1}),
           rec("visit", "no-arrival", visit("no-arrival", arrived=None, departed="2026-10-22T08:00:00.000-04:00",
                                            day=None)),
           rec("location", "odd", {"at": 5, "latitude": None, "longitude": True, "horizontal_accuracy_m": -1,
                                   "speed_mps": -1.0, "day": "yesterday"}),
           rec("location", "still", fix("still", speed_mps=0.0)))
    visits, fixes = rows("stezu_visits"), rows("stezu_locations")
    for row in (visits["bare"], fixes["bare"], visits["odd"], fixes["odd"]):
        assert all(v is None for k, v in row.items() if k not in ("id", "updated_at")), row
    late = visits["no-arrival"]
    assert (late["arrived_at"], late["duration_min"], late["day"]) == (None, None, "2026-10-22")
    assert fixes["still"]["speed_mps"] == 0.0  # standing still is a measured 0, not a missing one
    assert fixes["still"]["day"] == "2026-10-21"


def test_places_daily_counts_visits_and_fixes_per_day(db):
    ingest, rows = db
    ingest(rec("visit", "v-1", visit("v-1")),
           rec("visit", "v-2", visit("v-2", arrived="2026-10-21T18:00:00.000-04:00")),
           rec("visit", "v-3", visit("v-3")),
           rec("visit", "v-4", visit("v-4", arrived="2026-10-23T07:00:00.000-04:00")),
           *(rec("location", f"l-{i}", fix(f"l-{i}", at=f"2026-10-21T1{i}:00:00.000-04:00")) for i in range(3)),
           # No payload day: 23:30 EDT on the 22nd is the 23rd in UTC, and the phone's date wins.
           rec("location", "l-late", fix("l-late", at="2026-10-22T23:30:00.000-04:00", day=None)))
    ingest(rec("visit", "v-3", None, at="2026-10-21T10:00:00.001-04:00", deleted=True))
    daily = rows("places_daily", key="day")
    assert daily == {
        "2026-10-21": {"day": "2026-10-21", "visits": 2, "location_fixes": 3},
        "2026-10-22": {"day": "2026-10-22", "visits": None, "location_fixes": 1},
        "2026-10-23": {"day": "2026-10-23", "visits": 1, "location_fixes": None}}
    assert set(rows("stezu_visits")) == {"v-1", "v-2", "v-4"}


def test_place_views_exist_and_read_only_access_works(db, tmp_path):
    ingest, rows = db
    for view in VIEWS:
        assert rows(view, key="day" if view == "places_daily" else "id") == {}
    with sqlite3.connect(f"file:{tmp_path / 'health.db'}?mode=ro", uri=True) as ro:
        names = {r[0] for r in ro.execute("SELECT name FROM sqlite_master WHERE type = 'view'")}
        assert set(VIEWS) <= names
        with pytest.raises(sqlite3.OperationalError):
            ro.execute("INSERT INTO records VALUES ('visit', 'x', 'now', 0, '{}', 'now')")
