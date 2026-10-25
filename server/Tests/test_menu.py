from __future__ import annotations

from conftest import FakeHttp, fixture, foodpro_http

from stezu_server import foodpro

DATE = "2026-10-26"  # the date of the saved Forbes page


def test_parse_forbes_page_has_three_meals_with_nutrition():
    meals = foodpro.parse_menu(fixture("foodpro_forbes.html"), "03")
    assert [m["meal"] for m in meals] == ["Breakfast", "Lunch", "Dinner"]
    assert sum(len(m["items"]) for m in meals) == 27
    first = meals[0]["items"][0]
    assert first == {
        "id": "03-B-581044", "recipe_id": "581044", "name": "Bacon or Sausage", "hall_id": "03",
        "hall": "Forbes College", "meal": "Breakfast", "station": "Early Entree", "serving": "1 each",
        "kcal": 193.0, "protein_g": 10.5, "carbs_g": 0.1, "fat_g": 16.4,
    }
    every = [i for m in meals for i in m["items"]]
    assert all(i["kcal"] is not None and i["protein_g"] is not None for i in every)
    assert len({i["id"] for i in every}) == len(every)


def test_no_data_page_parses_as_no_menu():
    assert foodpro.parse_menu(fixture("foodpro_nodata.html"), "04") is None


def test_url_encodes_date_slashes_and_names():
    url = foodpro.menu_url("16", "2026-10-26")
    assert "dtdate=10%2F26%2F2026" in url and "locationName=Witherspoon%27s" in url
    assert "locationName=Whitman+College+%26+Butler+College" in foodpro.menu_url("08", DATE)


def test_number_keeps_absent_distinct_from_zero():
    assert foodpro.number("0g") == 0.0 and foodpro.number(None) is None and foodpro.number("1,200") == 1200


def test_menu_lists_every_hall_and_marks_closed_ones_unavailable(make_client):
    body = make_client(foodpro_http()).get(f"/menu?date={DATE}").json()
    halls = {h["hall_id"]: h for h in body["halls"]}
    assert len(halls) == 13 and body["date"] == DATE
    assert halls["03"]["status"] == "available"
    assert [m["meal"] for m in halls["03"]["meals"]] == ["Breakfast", "Lunch", "Dinner"]
    assert all(h["status"] == "unavailable" and h["meals"] == [] for k, h in halls.items() if k != "03")
    item = halls["03"]["meals"][1]["items"][0]
    assert {"id", "name", "hall", "meal", "serving", "kcal", "protein_g", "carbs_g", "fat_g"} <= set(item)


def test_menu_is_cached_per_date(make_client):
    http = foodpro_http()
    client = make_client(http)
    assert client.get(f"/menu?date={DATE}").json()["cached"] is False
    calls = len(http.calls)
    assert client.get(f"/menu?date={DATE}").json()["cached"] is True
    assert len(http.calls) == calls == 13
    client.get("/menu?date=2026-10-27")
    assert len(http.calls) == 26


def test_unrecognized_page_or_failure_is_an_error_and_not_cached(make_client):
    http = FakeHttp().add("locationNum=03&", "<html>redesigned</html>")
    http.add("locationNum=04&", OSError("timed out"))
    http.add("menuDetails.asp", fixture("foodpro_nodata.html"))
    client = make_client(http)
    halls = {h["hall_id"]: h for h in client.get(f"/menu?date={DATE}").json()["halls"]}
    assert halls["03"]["status"] == "error" and halls["04"]["status"] == "error"
    assert halls["05"]["status"] == "unavailable"
    assert client.get(f"/menu?date={DATE}").json()["cached"] is False


def test_menu_rejects_bad_dates(make_client):
    assert make_client().get("/menu?date=10/26/2026").status_code == 400


def test_meal_items_match_brunch_continental_and_all_day_cards():
    def card(meal, name):
        return {"meal": meal, "items": [{"name": name}]}

    menu = {"halls": [{"meals": [card("Brunch", "Waffle"), card("Dinner", "Soup")]},
                      {"meals": [card("Continental Breakfast", "Bagel"), card("Today's Menu", "Wrap")]}]}

    def names(meal):
        return [i["name"] for i in foodpro.meal_items(menu, meal)]

    assert names("lunch") == ["Waffle", "Wrap"]
    assert names("breakfast") == ["Waffle", "Bagel", "Wrap"]
    assert names("Dinner") == ["Soup", "Wrap"]
    assert len(names(None)) == 4


def test_unusual_card_names_get_distinct_id_codes():
    page = fixture("foodpro_forbes.html").replace(">Lunch", ">Today's Menu", 1)
    meals = foodpro.parse_menu(page, "24")
    assert meals[1]["meal"] == "Today's Menu" and meals[1]["items"][0]["id"].startswith("24-TSM-")
