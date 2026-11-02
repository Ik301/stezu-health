"""The restore read-back path (D-143): GET /records/summary, GET /records, and the `program` kind.

Every record here is synthetic.
"""

from __future__ import annotations

import copy
import itertools
import json
import sqlite3

import pytest

PHONE = ("location", "meal", "my_place", "program", "set", "visit", "weigh_in", "workout_session")
batches = itertools.count()


def at(minute: int, second: int = 0) -> str:
    return f"2026-10-21T08:{minute:02d}:{second:02d}.000-04:00"


def utc(minute: int, second: int = 0) -> str:
    return f"2026-10-21T12:{minute:02d}:{second:02d}.000Z"


def rec(kind, rid, payload=None, minute=0, deleted=False):
    if payload is None and not deleted:
        payload = {"id": rid, "note": f"{kind} {rid}"}
    return {"kind": kind, "id": rid, "updated_at": at(minute), "deleted": deleted, "payload": payload}


def sset(rid, session, minute=0, deleted=False):
    return rec("set", rid, None if deleted else {"id": rid, "session_id": session, "exercise_key": "bench-press",
                                                 "pounds": 95, "reps": 8, "logged_at": at(minute)},
               minute, deleted)


def sync(client, *records):
    r = client.post("/sync", json={"device_id": "device-test", "batch_id": f"b-{next(batches)}",
                                   "records": list(records)})
    assert r.status_code == 200, r.text
    return r.json()


def stored(client, *records):
    counts = sync(client, *records)
    assert counts["rejected"] == 0, counts["errors"]
    return counts


def pages(client, limit, kinds=""):
    got, after, calls = [], None, 0
    while True:
        params = {"limit": limit, "kinds": kinds} | ({"after": after} if after else {})
        r = client.get("/records", params=params)
        assert r.status_code == 200, r.text
        body, calls = r.json(), calls + 1
        assert len(body["records"]) <= limit
        got += body["records"]
        after = body["next"]
        if after is None:
            return got, calls


EXERCISE = {"key": "bench-press", "name": "Bench Press", "sets": 3, "repsLow": 8, "repsHigh": 12, "restSeconds": 120}
CAMEL = {"seed_version": 3, "templates": [
    {"key": "day-1", "name": "Day 1", "addOn": False, "exercises": [EXERCISE, EXERCISE | {
        "key": "row", "name": "Row", "repsLow": 10, "repsHigh": 10, "restSeconds": 0, "weightStep": 5,
        "startPounds": 45}]},
    {"key": "abs", "name": "Abs", "addOn": True, "exercises": []}]}
SNAKE = {"seed_version": None, "templates": [
    {"key": "day-1", "name": "Day 1", "exercises": [
        {"key": "squat", "name": "Squat", "sets": 1, "reps_low": 1, "reps_high": 1, "rest_seconds": 90}]},
    {"key": "abs", "name": "Abs", "add_on": True, "exercises": []}]}


def program(payload, rid="library", minute=0):
    return rec("program", rid, payload, minute)


def test_summary_counts_live_phone_kinds_and_sessions_from_sets(make_client):
    client = make_client()
    stored(client, sset("s1", "w1", 1), sset("s2", "w1", 2), sset("s3", "w1", 3), sset("s4", "w2", 4),
           sset("s5", "w2", 5), sset("s6", "w3", 6), rec("set", "s7", {"id": "s7", "reps": 5}, 7),
           rec("meal", "m1", minute=1), rec("meal", "m2", minute=9), rec("visit", "v1", minute=2),
           rec("app_usage", "u1", minute=30), rec("workout_session", "w1", minute=3), program(CAMEL, minute=4))
    stored(client, sset("s6", "w3", 20, deleted=True), rec("meal", "m2", minute=40, deleted=True))
    body = client.get("/records/summary").json()
    assert body["counts"] == {"location": 0, "meal": 1, "my_place": 0, "program": 1, "set": 6, "visit": 1,
                              "weigh_in": 0, "workout_session": 1}
    # Tombstones are not live: the deleted set's and meal's newer times are left out, app_usage too.
    assert body["updated_at"] == {"location": None, "meal": utc(1), "my_place": None, "program": utc(4),
                                  "set": utc(7), "visit": utc(2), "weigh_in": None, "workout_session": utc(3)}
    # w3's only set was deleted, and s7 has no session_id: two workouts.
    assert body["sessions_from_sets"] == 2


def test_pages_cover_every_live_record_exactly_once(make_client):
    client = make_client()
    records = ([sset(f"s{i:02d}", f"w{i % 3}", i) for i in range(9)] + [rec("meal", f"m{i}", minute=i) for i in range(5)]
               + [rec("visit", f"v{i}", minute=i) for i in range(3)] + [rec("weigh_in", "wi-1"), program(SNAKE)]
               + [rec("app_usage", "u1"), rec("future_kind", "x1")])
    stored(client, *records)
    stored(client, sset("s03", "w0", 50, deleted=True), rec("meal", "m4", minute=50, deleted=True))
    live = {(r["kind"], r["id"]): r["payload"] for r in records
            if r["kind"] in PHONE and (r["kind"], r["id"]) not in {("set", "s03"), ("meal", "m4")}}
    want = sorted(live)
    assert len(want) == 17
    for limit, n_pages in ((1, 17), (2, 9), (5, 4), (16, 2), (17, 1), (18, 1), (2000, 1)):
        got, calls = pages(client, limit)
        assert [(r["kind"], r["id"]) for r in got] == want, limit
        assert calls == n_pages, limit
    got, _ = pages(client, 500)
    for r in got:
        assert r["payload"] == live[(r["kind"], r["id"])]  # parsed JSON, as sent
        assert set(r) == {"kind", "id", "updated_at", "payload"}
    meals_and_sets, _ = pages(client, 3, kinds=" set,meal ,set")
    assert [(r["kind"], r["id"]) for r in meals_and_sets] == [k for k in want if k[0] in ("meal", "set")]
    # The default page is 500 and an empty kinds means every phone kind.
    body = client.get("/records").json()
    assert len(body["records"]) == 17 and body["next"] is None


def test_older_replay_never_shadows_the_newer_version_and_deleted_stay_out(make_client):
    client = make_client()
    old, new = sset("s1", "w1", 1), sset("s1", "w1", 9)
    new["payload"]["reps"] = 10
    stored(client, new)
    assert sync(client, old)["duplicates"] == 1
    [served] = client.get("/records", params={"kinds": "set"}).json()["records"]
    assert served["updated_at"] == utc(9) and served["payload"]["reps"] == 10
    stored(client, sset("s1", "w1", 20, deleted=True))
    stored(client, new)  # an older live copy after the delete does not bring it back
    assert client.get("/records", params={"kinds": "set"}).json() == {"records": [], "next": None}
    assert client.get("/records/summary").json()["counts"]["set"] == 0


@pytest.mark.parametrize("params, message", [
    ({"kinds": "bogus"}, "unknown kind bogus"),
    ({"kinds": "set,app_usage"}, "unknown kind app_usage"),
    ({"after": "not-a-cursor"}, "after is not a cursor"),
    ({"after": "WyJzZXQiXQ"}, "after is not a cursor"),  # base64 of ["set"]
    ({"limit": "0"}, "limit must be a whole number"),
    ({"limit": "ten"}, "limit must be a whole number"),
])
def test_bad_parameters_are_400_with_a_reason(make_client, params, message):
    r = make_client().get("/records", params=params)
    assert r.status_code == 400 and message in r.json()["detail"]


def test_limit_is_capped_and_reads_change_nothing(make_client):
    client = make_client()
    stored(client, *[rec("location", f"l{i:04d}") for i in range(2001)])
    before = client.get("/sync/status").json()
    body = client.get("/records", params={"limit": 99999, "kinds": "location"}).json()
    assert len(body["records"]) == 2000 and body["next"] is not None
    last = client.get("/records", params={"after": body["next"]}).json()
    assert [r["id"] for r in last["records"]] == ["l2000"] and last["next"] is None
    client.get("/records/summary")
    after = client.get("/sync/status").json()
    assert {**before, "server_time": None} == {**after, "server_time": None}


def test_both_endpoints_need_the_token(make_client):
    client = make_client()
    for headers in ({"Authorization": ""}, {"Authorization": "Bearer wrong"}):
        for path in ("/records", "/records/summary"):
            assert client.get(path, headers=headers).status_code == 401


def test_program_in_either_case_is_stored_served_verbatim_and_viewed(make_client, tmp_path):
    client = make_client()
    stored(client, program(SNAKE, minute=1))
    stored(client, program(CAMEL, minute=2))  # the app's Codable keys, newer: replaces it
    [served] = client.get("/records", params={"kinds": "program"}).json()["records"]
    assert served == {"kind": "program", "id": "library", "updated_at": utc(2), "payload": CAMEL}
    with sqlite3.connect(f"file:{tmp_path / 'health.db'}?mode=ro", uri=True) as ro:
        row = ro.execute("SELECT id, seed_version, n_templates, templates, updated_at FROM stezu_program").fetchone()
    assert row[:3] == ("library", 3, 2) and json.loads(row[3]) == CAMEL["templates"] and row[4] == utc(2)
    stored(client, {"kind": "program", "id": "library", "updated_at": at(3), "deleted": True, "payload": None})
    assert client.get("/records/summary").json()["counts"]["program"] == 0
    with sqlite3.connect(f"file:{tmp_path / 'health.db'}?mode=ro", uri=True) as ro:
        assert ro.execute("SELECT count(*) FROM stezu_program").fetchone()[0] == 0


def bad(edit):
    payload = copy.deepcopy(CAMEL)
    edit(payload)
    return payload


def ex(p):
    return p["templates"][0]["exercises"][0]


@pytest.mark.parametrize("rid, payload, message", [
    ("programme", CAMEL, 'program id must be "library"'),
    ("library", bad(lambda p: p.pop("templates")), "templates must be an array of 1 to 50"),
    ("library", bad(lambda p: p.update(templates=[])), "templates must be an array of 1 to 50"),
    ("library", bad(lambda p: p.update(templates=[{**p["templates"][1], "key": f"t{i}"} for i in range(51)])),
     "templates must be an array of 1 to 50"),
    ("library", bad(lambda p: p["templates"][0].update(exercises=[EXERCISE] * 41)), "at most 40 exercises"),
    ("library", bad(lambda p: p.update(seed_version="3")), "seed_version must be an integer or null"),
    ("library", bad(lambda p: p["templates"].append(p["templates"][0])), "templates[2].key 'day-1' appears twice"),
    ("library", bad(lambda p: p["templates"][0].update(name="  ")), "templates[0].name must be a non-blank"),
    ("library", bad(lambda p: p["templates"][1].update(addOn="yes")), "templates[1].addOn must be true, false"),
    ("library", bad(lambda p: p["templates"][0].update(exercises=["bench"])), "exercises[0] must be an object"),
    ("library", bad(lambda p: ex(p).pop("key")), "exercises[0].key must be a non-blank"),
    ("library", bad(lambda p: ex(p).update(sets=0)), "exercises[0].sets must be an integer >= 1"),
    ("library", bad(lambda p: ex(p).update(sets="3")), "exercises[0].sets must be an integer >= 1"),
    ("library", bad(lambda p: ex(p).update(sets=True)), "exercises[0].sets must be an integer >= 1"),
    ("library", bad(lambda p: ex(p).update(sets=2.5)), "exercises[0].sets must be an integer >= 1"),
    ("library", bad(lambda p: ex(p).update(repsLow=0)), "exercises[0].repsLow must be an integer >= 1"),
    ("library", bad(lambda p: ex(p).update(repsHigh=7)), "exercises[0].repsHigh must be an integer >= 8"),
    ("library", bad(lambda p: ex(p).pop("repsHigh")), "exercises[0].reps_high must be an integer >= 8"),
    ("library", bad(lambda p: ex(p).update(restSeconds=-1)), "exercises[0].restSeconds must be an integer >= 0"),
    ("library", bad(lambda p: ex(p).update(weightStep=-5)), "exercises[0].weightStep must be null or a number"),
    ("library", {"seed_version": 1, "templates": [{"key": "d", "name": "D", "exercises": [
        {"key": "x", "name": "X", "sets": 2, "reps_low": 5, "reps_high": 4, "rest_seconds": 60}]}]},
     "exercises[0].reps_high must be an integer >= 5"),
])
def test_bad_program_is_rejected_with_a_clear_error(make_client, rid, payload, message):
    client = make_client()
    counts = sync(client, program(payload, rid=rid), rec("meal", "m1"))
    assert counts["rejected"] == 1 and counts["accepted"] == 1  # the rest of the batch is stored
    assert counts["errors"][0].startswith("records[0]: program") and message in counts["errors"][0]
    assert client.get("/records/summary").json()["counts"]["program"] == 0
