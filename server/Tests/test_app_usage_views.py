"""The Screen Time views Hermes reads (stezu_app_usage, screen_time_daily), fed by the Mac uploader.

Every device and bundle id here is synthetic (com.example.*). Missing or odd fields must read as
NULL, never 0, and never make a view fail. Times carry the Mac's offset (EDT, -04:00).
"""

from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timedelta

import pytest

from stezu_server.health import HealthDB

VIEWS = ("stezu_app_usage", "screen_time_daily")


def rec(rid, payload, at="2026-10-21T20:00:00.000+00:00", deleted=False):
    return {"kind": "app_usage", "id": rid, "updated_at": at, "deleted": deleted, "payload": payload}


def usage(rid, bundle="com.example.one", start="2026-10-21T09:00:00.000-04:00", minutes=10.0, **extra):
    end = (datetime.fromisoformat(start) + timedelta(minutes=minutes)).isoformat(timespec="milliseconds")
    return {"id": rid, "device_name": "Test iPhone", "device_model": "iPhone15,2", "bundle_id": bundle,
            "app_name": None, "start": start, "end": end, "duration_s": minutes * 60, "capped": False,
            "day": start[:10]} | extra


@pytest.fixture
def db(tmp_path):
    path = tmp_path / "health.db"
    store = HealthDB(path, "America/New_York")
    batches = iter(range(10_000))

    def ingest(*records):
        counts = store.ingest({"device_id": "mac-screentime", "batch_id": f"b-{next(batches)}",
                               "records": list(records)})
        assert counts["rejected"] == 0, counts["errors"]
        return counts

    def rows(view, key="id"):
        with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as ro:
            ro.row_factory = sqlite3.Row
            return {r[key] if isinstance(key, str) else tuple(r[k] for k in key): dict(r)
                    for r in ro.execute(f"SELECT * FROM {view}")}

    return ingest, rows


def test_one_row_per_interval_and_a_resend_replaces_it(db):
    ingest, rows = db
    ingest(rec("a-1", usage("a-1")))
    row = rows("stezu_app_usage")["a-1"]
    assert row == {"id": "a-1", "device_name": "Test iPhone", "device_model": "iPhone15,2",
                   "bundle_id": "com.example.one", "app_name": None,
                   "started_at": "2026-10-21T09:00:00.000-04:00", "ended_at": "2026-10-21T09:10:00.000-04:00",
                   "day": "2026-10-21", "duration_s": 600.0, "capped": 0,
                   "updated_at": "2026-10-21T20:00:00.000Z"}
    # The next evening's run re-sends the same id with a newer updated_at: still one row.
    assert ingest(rec("a-1", usage("a-1", minutes=12), at="2026-10-22T20:00:00.000+00:00"))["accepted"] == 1
    assert ingest(rec("a-1", usage("a-1"), at="2026-10-21T20:00:00.000+00:00"))["duplicates"] == 1
    usage_rows = rows("stezu_app_usage")
    assert list(usage_rows) == ["a-1"] and usage_rows["a-1"]["duration_s"] == 720.0


def test_missing_or_odd_fields_are_null_not_zero(db):
    ingest, rows = db
    ingest(rec("bare", {}),
           rec("odd", {"device_name": 5, "bundle_id": ["x"], "start": "yesterday", "end": 3,
                       "duration_s": "600", "capped": "no", "day": "today"}),
           # No usable duration_s: the length comes from the two ends.
           rec("ends", usage("ends", duration_s=None, minutes=5)),
           rec("zero", usage("zero", duration_s=0, end="2026-10-21T09:00:00.000-04:00")))
    got = rows("stezu_app_usage")
    for rid in ("bare", "odd"):
        assert all(v is None for k, v in got[rid].items() if k not in ("id", "updated_at")), got[rid]
    assert got["ends"]["duration_s"] == pytest.approx(300.0)
    assert got["zero"]["duration_s"] is None
    assert rows("screen_time_daily", key=("day", "device_name")) == {
        ("2026-10-21", "Test iPhone"): {"day": "2026-10-21", "device_name": "Test iPhone", "total_min": 5.0,
                                        "apps": 1, "top_apps": '[{"bundle_id":"com.example.one","minutes":5.0}]',
                                        "intervals": 1, "capped_intervals": 0}}


def test_screen_time_daily_totals_apps_and_top_five(db):
    ingest, rows = db
    minutes = {"com.example.one": 30, "com.example.two": 25, "com.example.three": 20, "com.example.four": 15,
               "com.example.five": 10, "com.example.six": 5}
    ingest(*(rec(f"{b}-{i}", usage(f"{b}-{i}", bundle=b, minutes=m / 2, start=f"2026-10-21T1{i}:00:00.000-04:00"))
             for b, m in minutes.items() for i in range(2)),
           rec("capped", usage("capped", bundle="com.example.one", minutes=240, capped=True,
                               start="2026-10-22T01:00:00.000-04:00")),
           # 23:30 on the 22nd local is the 23rd in UTC; the uploader's day (local start) wins.
           rec("late", usage("late", bundle="com.example.two", start="2026-10-22T23:30:00.000-04:00", day=None)),
           rec("pad", usage("pad", device_name="Test iPad", start="2026-10-21T08:00:00.000-04:00")))
    ingest(rec("com.example.six-0", None, at="2026-10-21T20:00:00.001+00:00", deleted=True))
    daily = rows("screen_time_daily", key=("day", "device_name"))
    phone = daily[("2026-10-21", "Test iPhone")]
    assert (phone["total_min"], phone["apps"], phone["intervals"], phone["capped_intervals"]) == (102.5, 6, 11, 0)
    assert json.loads(phone["top_apps"]) == [
        {"bundle_id": "com.example.one", "minutes": 30.0}, {"bundle_id": "com.example.two", "minutes": 25.0},
        {"bundle_id": "com.example.three", "minutes": 20.0}, {"bundle_id": "com.example.four", "minutes": 15.0},
        {"bundle_id": "com.example.five", "minutes": 10.0}]
    next_day = daily[("2026-10-22", "Test iPhone")]
    assert (next_day["total_min"], next_day["apps"], next_day["capped_intervals"]) == (250.0, 2, 1)
    assert daily[("2026-10-21", "Test iPad")]["total_min"] == 10.0
    assert set(daily) == {("2026-10-21", "Test iPhone"), ("2026-10-22", "Test iPhone"), ("2026-10-21", "Test iPad")}


def test_app_usage_views_exist_and_read_only_access_works(db, tmp_path):
    ingest, rows = db
    assert rows("stezu_app_usage") == {} and rows("screen_time_daily", key="day") == {}
    with sqlite3.connect(f"file:{tmp_path / 'health.db'}?mode=ro", uri=True) as ro:
        names = {r[0] for r in ro.execute("SELECT name FROM sqlite_master WHERE type = 'view'")}
        assert set(VIEWS) <= names
        with pytest.raises(sqlite3.OperationalError):
            ro.execute("INSERT INTO records VALUES ('app_usage', 'x', 'now', 0, '{}', 'now')")
