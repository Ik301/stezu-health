from __future__ import annotations

import base64
import json

import pytest
from conftest import FakeHttp, fixture, foodpro_http
from test_scan import JPEG, FakeModel, code_for

from stezu_server import foodpro, latemeal, scan

MONDAY, FRIDAY, SATURDAY, SUNDAY = "2026-10-26", "2026-10-30", "2026-10-31", "2026-11-01"


def lm_hall(body):
    return next((h for h in body["halls"] if h["hall_id"] == "LM"), None)


def test_json_is_valid_and_every_item_is_an_estimate_with_a_basis():
    data = json.loads(latemeal.PATH.read_text(encoding="utf-8"))
    assert data["retrieved"] == "2026-10-30" and data["ondemand"]["tenant"] == 2047
    assert "TO BE CONFIRMED" in data["note"] and "DataDome" in data["source"]
    names = [i["name"] for i in data["items"]]
    assert len(names) == len(set(names)) == 13 and data["fries"] in names
    for item in data["items"]:
        assert item["estimated"] is True and item["basis"].strip() and item["description"].strip()
        assert item["serving"].strip()
        values = [item[k] for k in latemeal.NUTRIENTS]
        assert all(isinstance(v, (int, float)) and v > 0 for v in values), item["name"]
        kcal_from_macros = 4 * item["protein_g"] + 4 * item["carbs_g"] + 9 * item["fat_g"]
        assert abs(kcal_from_macros - item["kcal"]) / item["kcal"] < 0.1, item["name"]
        if "plate" in item:
            assert item["plate"]["name"] == f"{item['name']} with fries"
            assert item["plate"]["serving"] == "1 plate, with fries"
            assert "fries are a separate item" in item["serving"]
    assert sum("plate" in i for i in data["items"]) == 9


def test_late_meal_runs_on_weekdays_with_the_friday_dinner_off(make_client):
    client = make_client(foodpro_http())
    monday = lm_hall(client.get(f"/menu?date={MONDAY}").json())
    assert monday["hall"] == "Frist Late Meal" and monday["status"] == "available"
    assert monday["source"] == "static" and monday["estimated"] is True
    assert [(m["meal"], m["hours"]) for m in monday["meals"]] == [
        ("Late Lunch", "14:00-16:00"), ("Late Dinner", "20:30-22:00")]
    friday = lm_hall(client.get(f"/menu?date={FRIDAY}").json())
    assert [m["meal"] for m in friday["meals"]] == ["Late Lunch"]
    for weekend in (SATURDAY, SUNDAY):
        body = client.get(f"/menu?date={weekend}").json()
        assert lm_hall(body) is None and len(body["halls"]) == 13


def test_items_follow_the_id_pattern_and_plates_sum_their_parts(make_client):
    lunch = lm_hall(make_client(foodpro_http()).get(f"/menu?date={MONDAY}").json())["meals"][0]
    items = {i["id"]: i for i in lunch["items"]}
    assert len(items) == 13 + 9
    tenders, fries = items["LM-LL-chicken-tenders"], items["LM-LL-french-fries"]
    plate = items["LM-LL-chicken-tenders-with-fries"]
    assert plate["name"] == "Chicken Tenders with fries" and plate["serving"] == "1 plate, with fries"
    assert plate["plate"] is True and plate["parts"] == [tenders["id"], fries["id"]]
    for k in latemeal.NUTRIENTS:
        assert plate[k] == round(tenders[k] + fries[k], 1)
    assert tenders["hall"] == "Frist Late Meal" and tenders["meal"] == "Late Lunch"
    assert tenders["estimated"] is True and tenders["basis"] and "plate" not in tenders
    assert all(i["hall_id"] == "LM" and i["kcal"] > 0 for i in items.values())


def test_late_meal_survives_a_foodpro_failure_and_the_menu_cache(make_client):
    down = FakeHttp().add("menuDetails.asp", OSError("timed out"))
    body = make_client(down).get(f"/menu?date={MONDAY}").json()
    assert all(h["status"] == "error" for h in body["halls"] if h["hall_id"] != "LM")
    assert lm_hall(body)["status"] == "available"
    client = make_client(foodpro_http())
    client.get(f"/menu?date={MONDAY}")
    cached = client.get(f"/menu?date={MONDAY}").json()
    assert cached["cached"] is True and lm_hall(cached)["status"] == "available"


def test_late_meal_serves_lunch_and_dinner_but_not_breakfast(make_client):
    menu = make_client(foodpro_http()).get(f"/menu?date={MONDAY}").json()

    def lm_meals(meal):
        return {i["meal"] for i in foodpro.meal_items(menu, meal) if i["hall_id"] == "LM"}

    assert lm_meals("breakfast") == set()
    assert lm_meals("lunch") == {"Late Lunch"}
    assert lm_meals("dinner") == {"Late Dinner"}
    assert foodpro.serves("Late Lunch", {"lunch"}) and not foodpro.serves("Late Lunch", {"breakfast", "brunch"})


def test_estimated_items_get_a_wider_range_and_plates_are_never_candidates(make_client):
    forbes_lunch = foodpro.parse_menu(fixture("foodpro_forbes.html"), "03")[1]["items"][0]

    def answer(text):
        return {"items": [
            {"code": code_for(text, "Chicken Tenders"), "name": "tenders", "servings": 1,
             "confidence": 0.8, "alternates": []},
            {"code": code_for(text, forbes_lunch["name"]), "name": "dish", "servings": 1,
             "confidence": 0.8, "alternates": []}]}

    model = FakeModel(answer)
    body = {"meal_id": "lm-1", "date": MONDAY, "meal": "lunch",
            "image_base64": base64.b64encode(JPEG).decode()}
    out = make_client(foodpro_http(), model).post("/scan", json=body).json()
    prompt = model.calls[0]["text"]
    assert "with fries |" not in prompt and "| French Fries |" in prompt
    assert "Frist Late Meal (estimated values)" in prompt
    lm, fp = out["items"]
    assert lm["item_id"] == "LM-LL-chicken-tenders" and lm["estimated"] is True and lm["rough"] is False
    assert fp["hall"] == "Forbes College" and fp["estimated"] is False and out["estimated"] is True
    assert lm["kcal"] == scan.span(515, 1, scan.spread(0.8, False, True), 0)

    def half_width(r):
        return (r["high"] - r["low"]) / (r["high"] + r["low"])

    assert half_width(lm["kcal"]) == pytest.approx(0.43, abs=0.005)
    assert half_width(fp["kcal"]) == pytest.approx(0.28, abs=0.01)


def test_spread_is_15_points_wider_for_estimates():
    assert scan.spread(1.0, True, True) == pytest.approx(0.30)
    assert scan.spread(1.0, False, True) == pytest.approx(0.40)
    assert scan.spread(1.0, True) == pytest.approx(0.15)
    assert scan.spread(0.0, False, True) > scan.spread(0.0, False)


def test_search_finds_late_meal_items_by_name_and_by_late_meal(make_client):
    client = make_client(foodpro_http())
    groups = {g["source"]: g for g in client.get(f"/search?q=chicken tenders&date={MONDAY}").json()["groups"]}
    names = {(r["name"], r["hall"]) for r in groups["dining"]["results"]}
    assert ("Chicken Tenders", "Frist Late Meal") in names
    assert ("Chicken Tenders with fries", "Frist Late Meal") in names
    assert all(r["estimated"] for r in groups["dining"]["results"] if r["hall"] == "Frist Late Meal")
    groups = {g["source"]: g for g in client.get(f"/search?q=late meal burger&date={MONDAY}").json()["groups"]}
    top = groups["dining"]["results"][0]
    assert top["hall"] == "Frist Late Meal" and "Burger" in top["name"]
    assert any(r["name"] == "Signature Cheeseburger with fries" for r in groups["dining"]["results"])
