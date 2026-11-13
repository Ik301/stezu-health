from __future__ import annotations

import json

from conftest import FakeHttp, fixture, foodpro_http
from test_scan import FakeModel

from stezu_server import search

DATE = "2026-10-26"


def groups(resp):
    return {g["source"]: g for g in resp.json()["groups"]}


def http_with_sources():
    http = foodpro_http(("03", "08"))
    http.add("search.openfoodfacts.org", fixture("off_search.json"))
    return http.add("api.nal.usda.gov", fixture("usda_search.json"))


def test_fuzzy_dining_match_tolerates_typos():
    assert search.score("bacn sausage", "Bacon or Sausage") >= 0.6
    assert search.score("bacon", "Bacon or Sausage") == 1.0
    assert search.score("sushi", "Bacon or Sausage") < 0.6


def test_search_groups_dining_off_usda_and_estimate(make_client):
    model = FakeModel({})
    client = make_client(http_with_sources(), model, usda_key="DEMO_KEY")
    resp = client.get(f"/search?q=bacon&date={DATE}&meal=breakfast")
    g = groups(resp)
    assert list(g) == ["dining", "open_food_facts", "usda_fdc", "estimate"]
    hit = g["dining"]["results"][0]
    assert hit["name"] == "Bacon or Sausage" and hit["kcal"] == 193
    assert hit["halls"] == ["Forbes College", "Whitman College & Butler College"]
    off = g["open_food_facts"]["results"][0]
    assert off["name"] == "Nonfat Greek Yogurt" and off["brand"] == "Chobani"
    assert off["per_100"]["kcal"] == 52.9
    usda = g["usda_fdc"]["results"][0]
    assert usda["per_100"] == {"unit": "g", "kcal": 165, "protein_g": 20.4}
    assert usda["per_serving"]["kcal"] == round(165 * 2.84, 1)
    assert g["estimate"]["status"] == "available" and model.calls == []


def test_meal_filter_and_no_usda_key(make_client):
    client = make_client(http_with_sources())
    g = groups(client.get(f"/search?q=bacon&date={DATE}&meal=dinner"))
    meals = {r["meal"] for r in g["dining"]["results"]}
    assert meals and meals <= {"Dinner", "Late Dinner"}  # Late Meal's bacon items, never breakfast
    assert g["usda_fdc"]["status"] == "skipped"


def test_one_failing_source_does_not_sink_the_rest(make_client):
    http = foodpro_http()
    http.routes.insert(0, ("search.openfoodfacts.org", OSError("timed out")))
    g = groups(make_client(http).get(f"/search?q=bacon&date={DATE}"))
    assert g["open_food_facts"]["status"] == "error" and g["dining"]["results"]


def test_text_estimate_on_request_is_rough_and_cached(make_client):
    model = FakeModel({"name": "Chipotle burrito", "portion": "1 burrito",
                       "kcal": {"low": 900, "high": 1100}, "protein_g": {"low": 40, "high": 50}})
    http = foodpro_http()
    http.add("search.openfoodfacts.org", json.dumps({"hits": []}))
    client = make_client(http, model)
    est = groups(client.get(f"/search?q=chipotle+chicken+burrito&date={DATE}&estimate=true"))["estimate"]
    result = est["results"][0]
    assert est["status"] == "ok" and result["rough"] is True
    assert result["kcal"] == {"low": 600, "high": 1400}
    assert model.calls[0]["text"] == "chipotle chicken burrito"
    client.get(f"/search?q=chipotle+chicken+burrito&date={DATE}&estimate=true")
    assert len(model.calls) == 1


def test_query_is_required(make_client):
    client = make_client(http_with_sources())
    assert client.get("/search?q=").status_code == 400
    assert client.get("/search").status_code == 422


def test_packaged_result_without_a_serving_falls_back_to_100g(make_client):
    # Open Food Facts' search index carries only per-100 g nutrients, so every packaged result
    # used to reach the phone with no per-serving kcal and showed "-- kcal" (2026-11-09).
    g = groups(make_client(http_with_sources(), usda_key="DEMO_KEY").get(f"/search?q=yogurt&date={DATE}"))
    off = g["open_food_facts"]["results"][0]
    assert off["per_serving"] == {"label": "100 g", "quantity": 100, "unit": "g", "kcal": 52.9,
                                  "protein_g": 9.4, "basis": "per_100"}


def test_results_without_numbers_sort_last():
    http = FakeHttp().add("search.openfoodfacts.org", json.dumps({"hits": [
        {"code": "1", "product_name": "Creatine", "nutriments": {}},
        {"code": "2", "product_name": "Creatine monohydrate", "nutriments": {"energy-kcal_100g": 0}},
    ]}))
    names = [r["name"] for r in search.off_search(http, "creatine")]
    assert names == ["Creatine monohydrate", "Creatine"]  # 0 kcal is a number, not missing


def test_generic_usda_food_uses_its_first_household_measure():
    http = FakeHttp().add("api.nal.usda.gov", json.dumps({"foods": [
        {"fdcId": 1, "description": "Chicken tenders", "dataType": "Survey (FNDDS)",
         "foodNutrients": [{"nutrientNumber": "208", "value": 280}, {"nutrientNumber": "203", "value": 18}],
         "foodMeasures": [{"disseminationText": "Quantity not specified", "gramWeight": 200},
                          {"disseminationText": "1 tender", "gramWeight": 25}]},
        {"fdcId": 2, "description": "Rice", "dataType": "SR Legacy",
         "foodNutrients": [{"nutrientNumber": "208", "value": 130}, {"nutrientNumber": "203", "value": 2.7}]},
    ]}))
    tender, rice = search.usda_search(http, "chicken tenders", "KEY")
    assert tender["per_serving"] == {"label": "1 tender", "quantity": 25, "unit": "g", "kcal": 70.0,
                                     "protein_g": 4.5, "basis": "measure"}
    assert rice["per_serving"]["label"] == "100 g" and rice["per_serving"]["kcal"] == 130


def test_short_queries_skip_the_remote_sources(make_client):
    # Typing "c", "cr", ... used to spend the USDA quota (DEMO_KEY: 30 calls an hour) on every keystroke.
    http = http_with_sources()
    g = groups(make_client(http, usda_key="DEMO_KEY").get(f"/search?q=ba&date={DATE}"))
    assert g["open_food_facts"]["status"] == "skipped" and g["usda_fdc"]["status"] == "skipped"
    assert not [u for u in http.calls if "openfoodfacts" in u or "nal.usda.gov" in u]


def creatine_hits():
    return FakeHttp().add("search.openfoodfacts.org", fixture("off_search_creatine.json"))


def test_brand_only_and_nameless_off_hits_are_dropped():
    # "creatine optimum nutrition": OFF's top hits were entries named just "Optimum Nutrition" (2026-11-12).
    codes = [r["gtin"] for r in search.off_search(creatine_hits(), "creatine optimum nutrition")]
    assert "0000000000017" not in codes  # name == brand
    assert "0000000000024" not in codes  # same, other case and a trailing space
    assert "0000000000031" not in codes and "0000000000086" not in codes  # blank or empty name
    assert "0000000000048" not in codes  # name is one brand of a comma-separated list
    assert codes == ["0000000000062", "0000000000079", "0000000000093", "0000000000055"]


def test_relevance_beats_having_a_kcal():
    results = search.off_search(creatine_hits(), "creatine optimum nutrition")
    names = [r["name"] for r in results]
    assert names[:2] == ["Micronized Creatine Powder", "Micronized Creatine Powder"]
    assert results[3]["name"] == "Gold Standard Bar" and results[3]["per_serving"]["kcal"] == 419
    assert results[0]["per_serving"]["kcal"] is None  # ranked first without a number
    # A brand written into the name (no brand set) earns no more than the brand field would.
    assert results[2]["name"] == "Optimum Nutrition Whey" and results[2]["per_serving"]["kcal"] is not None


def test_kcal_breaks_only_ties_in_relevance():
    http = FakeHttp().add("search.openfoodfacts.org", json.dumps({"hits": [
        {"code": "1", "product_name": "Creatine Capsules", "brands": "Acme", "nutriments": {}},
        {"code": "2", "product_name": "Creatine Gummies", "brands": "Acme", "nutriments": {"energy-kcal_100g": 300}},
        {"code": "3", "product_name": "Creatine Powder", "brands": "Acme", "nutriments": {}},
        {"code": "4", "product_name": "Electrolyte Mix", "brands": "Acme", "nutriments": {"energy-kcal_100g": 50}},
    ]}))
    codes = [r["gtin"] for r in search.off_search(http, "acme creatine")]
    assert codes == ["2", "1", "3", "4"]  # equal relevance: kcal first, then OFF's order; less relevant last
    assert search.relevance("acme creatine", "Creatine Capsules", "Acme") == 0.75
    assert search.relevance("acme creatine", "Electrolyte Mix", "Acme") == 0.25


def test_off_results_carry_package_size():
    by_code = {r["gtin"]: r for r in search.off_search(creatine_hits(), "creatine optimum nutrition")}
    assert by_code["0000000000062"]["package_size"] == "600 g"  # OFF's quantity label
    assert by_code["0000000000079"]["package_size"] == "300 g"  # from product_quantity and its unit
    assert by_code["0000000000055"]["package_size"] is None


def test_off_fetches_more_than_it_keeps():
    http = FakeHttp().add("search.openfoodfacts.org", json.dumps({"hits": [
        {"code": str(i), "product_name": f"Creatine {i}", "brands": "Acme", "nutriments": {}} for i in range(30)
    ]}))
    results = search.off_search(http, "creatine")
    assert f"page_size={search.OFF_PAGE}" in http.calls[0] and search.OFF_PAGE > search.OFF_KEEP and len(results) == search.OFF_KEEP


def test_usda_results_carry_package_size_and_search_returns_it(make_client):
    http = FakeHttp().add("api.nal.usda.gov", json.dumps({"foods": [
        {"fdcId": 1, "description": "Creatine Monohydrate", "brandOwner": "Acme", "dataType": "Branded",
         "packageWeight": "10.6 oz/300 g", "servingSize": 5, "servingSizeUnit": "g",
         "foodNutrients": [{"nutrientNumber": "208", "value": 0}]},
        {"fdcId": 2, "description": "Creatine Chews", "brandOwner": "Acme", "dataType": "Branded",
         "foodNutrients": [{"nutrientNumber": "208", "value": 350}]},
    ]}))
    assert [r["package_size"] for r in search.usda_search(http, "creatine", "KEY")] == ["10.6 oz/300 g", None]
    http = foodpro_http().add("search.openfoodfacts.org", fixture("off_search_creatine.json"))
    off = groups(make_client(http).get(f"/search?q=creatine+optimum+nutrition&date={DATE}"))["open_food_facts"]
    assert [r["package_size"] for r in off["results"][:2]] == ["600 g", "300 g"]
