"""The record views Hermes reads (stezu_sets, stezu_sessions, stezu_weighins, stezu_meals).

Every payload here is synthetic. Missing or odd fields must read as NULL, never 0, and never
make a view fail. Times carry the phone's offset (EDT, -04:00).
"""

from __future__ import annotations

import sqlite3

import pytest

from stezu_server.health import HealthDB

VIEWS = ("stezu_sets", "stezu_sessions", "stezu_weighins", "stezu_meals")


def rec(kind, rid, payload, at="2026-10-21T10:00:00.000-04:00", deleted=False):
    return {"kind": kind, "id": rid, "updated_at": at, "deleted": deleted, "payload": payload}


@pytest.fixture
def db(tmp_path):
    path = tmp_path / "health.db"
    store = HealthDB(path, "America/New_York")

    def ingest(*records):
        counts = store.ingest({"device_id": "device-test", "batch_id": f"b-{id(records)}",
                               "records": list(records)})
        assert counts["rejected"] == 0, counts["errors"]

    def rows(view, order="id"):
        with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as ro:
            ro.row_factory = sqlite3.Row
            return {r["id"]: dict(r) for r in ro.execute(f"SELECT * FROM {view} ORDER BY {order}")}

    return ingest, rows


def a_set(sid, session="sess-1", pounds=135.0, reps=8, at="2026-10-21T21:30:05.250-04:00", **extra):
    return {"id": sid, "session_id": session, "template_key": "day-1", "exercise_key": "bench-press",
            "exercise_name": "Bench Press", "pounds": pounds, "reps": reps, "logged_at": at,
            "kind": "working"} | extra


def test_sets_view_reads_live_sets_and_keeps_bodyweight_null(db):
    ingest, rows = db
    ingest(rec("set", "set-1", a_set("set-1")),
           rec("set", "set-2", a_set("set-2", pounds=None, reps=12, exercise_key="pull-up",
                                     exercise_name="Pull-up")),
           rec("set", "set-3", a_set("set-3")))
    # Undo: the same id again, newer and deleted.
    ingest(rec("set", "set-3", None, at="2026-10-21T10:00:00.001-04:00", deleted=True))
    sets = rows("stezu_sets")
    assert set(sets) == {"set-1", "set-2"}
    assert sets["set-1"] | {"updated_at": None} == {
        "id": "set-1", "session_id": "sess-1", "template_key": "day-1", "exercise_key": "bench-press",
        "exercise_name": "Bench Press", "pounds": 135.0, "reps": 8,
        "logged_at": "2026-10-21T21:30:05.250-04:00", "day": "2026-10-21", "kind": "working",
        "updated_at": None}
    assert sets["set-2"]["pounds"] is None and sets["set-2"]["reps"] == 12


def test_missing_or_odd_set_fields_are_null_not_zero(db):
    ingest, rows = db
    ingest(rec("set", "bare", {}),
           rec("set", "odd", {"pounds": 0, "reps": "eight", "logged_at": 5, "session_id": ["x"],
                              "name": "Dip", "day": "2026-10-20"}))
    sets = rows("stezu_sets")
    assert all(v is None for k, v in sets["bare"].items() if k not in ("id", "updated_at"))
    odd = sets["odd"]
    assert (odd["pounds"], odd["reps"], odd["logged_at"], odd["session_id"]) == (None, None, None, None)
    assert (odd["exercise_name"], odd["day"]) == ("Dip", "2026-10-20")


def test_sessions_view_counts_sets_from_the_payload(db):
    ingest, rows = db
    ingest(rec("workout_session", "sess-1", {
        "id": "sess-1", "template_key": "day-1", "template_name": "Day 1",
        "started_at": "2026-10-21T20:00:00.000-04:00", "ended_at": "2026-10-21T21:15:30.000-04:00",
        "exercises": [
            {"exercise_key": "bench-press", "exercise_name": "Bench Press",
             "sets": [a_set("a"), a_set("b", reps=6), a_set("c", reps=None)]},
            {"exercise_key": "pull-up", "exercise_name": "Pull-up", "sets": [a_set("d", pounds=None, reps=10)]},
            "not an exercise", {"exercise_key": "no-sets"}],
        "in_health": True}))
    s = rows("stezu_sessions")["sess-1"]
    assert (s["started_at"], s["ended_at"], s["day"]) == ("2026-10-21T20:00:00.000-04:00",
                                                          "2026-10-21T21:15:30.000-04:00", "2026-10-21")
    assert (s["template_key"], s["template_name"], s["in_health"]) == ("day-1", "Day 1", 1)
    assert s["duration_min"] == pytest.approx(75.5)
    assert (s["n_exercises"], s["n_sets"], s["total_reps"]) == (4, 4, 24)


def test_sessions_fall_back_to_set_records_and_stay_null_without_sets(db):
    ingest, rows = db
    ingest(rec("set", "s1", a_set("s1", session="sess-2", reps=5)),
           rec("set", "s2", a_set("s2", session="sess-2", reps=7)),
           rec("workout_session", "sess-2", {"start": "2026-10-22T07:00:00-04:00", "template": "Day 2"}),
           rec("workout_session", "sess-3", {"exercises": "garbage", "end": "2026-10-22T08:00:00-04:00"}),
           rec("workout_session", "sess-4", {"started_at": "2026-10-22T09:00:00-04:00", "exercises": []}),
           rec("workout_session", "gone", {}, deleted=False))
    ingest(rec("workout_session", "gone", None, at="2026-10-22T00:00:00-04:00", deleted=True))
    sessions = rows("stezu_sessions")
    assert set(sessions) == {"sess-2", "sess-3", "sess-4"}
    two, three, four = sessions["sess-2"], sessions["sess-3"], sessions["sess-4"]
    assert (two["started_at"], two["day"], two["template_name"]) == ("2026-10-22T07:00:00-04:00", "2026-10-22",
                                                                    "Day 2")
    assert (two["n_exercises"], two["n_sets"], two["total_reps"]) == (None, 2, 12)
    assert (two["ended_at"], two["duration_min"], two["in_health"]) == (None, None, None)
    assert (three["n_sets"], three["total_reps"], three["day"]) == (None, None, None)
    # An empty exercise list is a session with no sets: 0 sets is recorded, reps are unknown.
    assert (four["n_exercises"], four["n_sets"], four["total_reps"]) == (0, 0, None)


def test_weighins_view_converts_to_kg_and_keeps_health_state(db):
    ingest, rows = db
    ingest(rec("weigh_in", "w1", {"id": "w1", "measured_at": "2026-10-21T07:05:00.000-04:00", "pounds": 180.0,
                                  "in_health": True}),
           rec("weigh_in", "w2", {"measured_at": "2026-10-22T07:00:00-04:00", "pounds": 179.5,
                                  "inHealth": False}),
           rec("weigh_in", "w3", {"measured_at": "2026-10-23T07:00:00-04:00", "pounds": 0}),
           rec("weigh_in", "w4", {"pounds": 178}),
           rec("weigh_in", "w5", {"pounds": 177}, deleted=False))
    ingest(rec("weigh_in", "w5", None, at="2026-10-24T00:00:00-04:00", deleted=True))
    w = rows("stezu_weighins")
    assert set(w) == {"w1", "w2", "w3", "w4"}
    assert (w["w1"]["day"], w["w1"]["pounds"], w["w1"]["in_health"]) == ("2026-10-21", 180.0, 1)
    assert w["w1"]["kg"] == pytest.approx(81.6466, abs=1e-4)
    assert (w["w2"]["in_health"], w["w2"]["day"]) == (0, "2026-10-22")
    assert (w["w3"]["pounds"], w["w3"]["kg"], w["w3"]["in_health"]) == (None, None, None)
    assert (w["w4"]["measured_at"], w["w4"]["day"], w["w4"]["kg"]) == (None, None, pytest.approx(80.7394, abs=1e-4))


def item(name, kcal=None, protein=None):
    out = {"item_id": name.lower(), "name": name, "source": "estimate", "rough": True}
    if kcal:
        out["kcal"] = {"low": kcal[0], "high": kcal[1]}
    if protein:
        out["protein_g"] = {"low": protein[0], "high": protein[1]}
    return out


def test_meals_view_sums_item_ranges_like_the_app(db):
    ingest, rows = db
    meal = {"id": "m1", "eaten_at": "2026-10-21T12:30:00-04:00", "day": "2026-10-21", "status": "confirmed",
            "edited": False, "in_health": True}
    ingest(rec("meal", "m1", meal | {"items": [item("Oatmeal", (150, 200), (5, 7)), item("Eggs", (140, 160), (12, 13))]}),
           rec("meal", "m2", meal | {"items": [item("Soup", (100, 150), (4, 6)), item("Bread", (80, 90))],
                                     "in_health": None}),
           rec("meal", "m3", meal | {"items": []}),
           rec("meal", "m4", {"eaten_at": "2026-10-22T08:00:00-04:00", "items": ["junk", item("Tea", (0, 5), (0, 0))]}),
           rec("meal", "m5", {}))
    m = rows("stezu_meals")
    one = m["m1"]
    assert (one["n_items"], one["kcal_low"], one["kcal_high"], one["protein_g_low"], one["protein_g_high"]) == (
        2, 290, 360, 17, 20)
    assert (one["day"], one["status"], one["edited"], one["in_health"], one["items"]) == (
        "2026-10-21", "confirmed", 0, 1, "Oatmeal; Eggs")
    assert (m["m2"]["kcal_low"], m["m2"]["kcal_high"], m["m2"]["protein_g_low"], m["m2"]["in_health"]) == (
        180, 240, None, None)
    assert (m["m3"]["n_items"], m["m3"]["kcal_low"], m["m3"]["items"]) == (0, None, None)
    assert (m["m4"]["n_items"], m["m4"]["kcal_low"], m["m4"]["day"], m["m4"]["items"]) == (
        2, None, "2026-10-22", "Tea")
    assert all(v is None for k, v in m["m5"].items() if k not in ("id", "updated_at"))


def test_record_views_exist_and_read_only_access_works(db):
    _, rows = db
    for view in VIEWS:
        assert rows(view) == {}
