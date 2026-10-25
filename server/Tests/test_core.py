from __future__ import annotations

import json
import os

from conftest import TOKEN, FakeHttp, fixture

from stezu_server.config import load_settings
from stezu_server.net import HttpError
from stezu_server.store import Store


def test_health_needs_no_token(make_client):
    client = make_client()
    client.headers.pop("Authorization")
    assert client.get("/health").json()["status"] == "ok"


def test_endpoints_refuse_missing_or_wrong_token(make_client):
    client = make_client()
    client.headers.pop("Authorization")
    assert client.get("/barcode/049000028911").status_code == 401
    wrong = client.get("/barcode/049000028911", headers={"Authorization": "Bearer nope"})
    assert wrong.status_code == 401
    assert wrong.headers["www-authenticate"] == "Bearer"


def test_no_configured_tokens_refuses_everything(make_client):
    client = make_client(tokens=frozenset())
    assert client.get("/barcode/049000028911").status_code == 401


def test_settings_from_env_file(tmp_path, monkeypatch):
    for key in [k for k in os.environ if k.startswith("STEZU_")]:
        monkeypatch.delenv(key)
    env = tmp_path / "server.env"
    env.write_text(
        "# comment\nSTEZU_TOKENS=a, b\nSTEZU_MODEL=some-model\nSTEZU_MODEL_TEMPERATURE=none\n"
        f"STEZU_ANTHROPIC_KEY_FILE={tmp_path}/key\nSTEZU_ANTHROPIC_BASE_URL=http://localhost:1/\n"
    )
    (tmp_path / "key").write_text("k-123\n")
    s = load_settings(str(env))
    assert s.tokens == {"a", "b"}
    assert (s.model, s.temperature, s.anthropic_base_url) == ("some-model", None, "http://localhost:1")
    assert s.api_key() == "k-123"
    assert load_settings(str(tmp_path / "missing.env")).tokens == frozenset()


def test_store_round_trip_and_age(tmp_path):
    store = Store(tmp_path / "s" / "db.sqlite3")
    store.put("k", {"a": 1})
    assert store.get("k") == {"a": 1}
    assert store.get("k", max_age=-1) is None
    assert store.get("missing") is None


def test_barcode_found_with_serving_and_package(make_client):
    http = FakeHttp().add("product/049000028911.json", fixture("off_product.json"))
    body = make_client(http).get("/barcode/049000028911").json()
    assert body["status"] == "found" and body["name"] == "Diet Coke Soft Drink"
    # A labelled zero stays zero; it is not treated as missing.
    assert body["per_serving"]["kcal"] == 0 and body["per_serving"]["label"] == "1 can (354.9 mL)"
    assert body["per_package"]["kcal"] == 0 and body["per_package"]["unit"] == "ml"


def test_barcode_scales_per_100_to_serving_and_package(make_client):
    product = {"status": 1, "product": {
        "code": "12345678", "product_name": "Granola", "brands": "Generic", "serving_size": "30 g",
        "serving_quantity": 30, "product_quantity": 300, "quantity": "300 g",
        "nutriments": {"energy-kcal_100g": 450, "proteins_100g": 10}}}
    http = FakeHttp().add("product/12345678.json", product)
    body = make_client(http).get("/barcode/12345678").json()
    assert (body["per_serving"]["kcal"], body["per_serving"]["protein_g"]) == (135, 3)
    assert (body["per_package"]["kcal"], body["per_package"]["protein_g"]) == (1350, 30)
    assert body["per_100"]["kcal"] == 450


def test_barcode_missing_values_are_absent_not_zero(make_client):
    http = FakeHttp().add("product/12345670.json", {"status": 1, "product": {"product_name": "X"}})
    body = make_client(http).get("/barcode/12345670").json()
    assert body["per_serving"]["kcal"] is None and body["per_package"]["protein_g"] is None


def test_barcode_upc_retries_as_ean13_and_caches(make_client):
    http = FakeHttp().add("product/049000028911.json", HttpError(404, "{}"))
    http.add("product/0049000028911.json", fixture("off_product.json"))
    client = make_client(http)
    assert client.get("/barcode/049000028911").json()["cached"] is False
    calls = len(http.calls)
    again = client.get("/barcode/049000028911").json()
    assert again["cached"] is True and again["status"] == "found" and len(http.calls) == calls


def test_barcode_not_found_and_invalid(make_client):
    http = FakeHttp().add("product/", {"status": 0, "status_verbose": "product not found"})
    client = make_client(http)
    assert client.get("/barcode/00000000").json()["status"] == "not_found"
    assert client.get("/barcode/abc").status_code == 400


def test_barcode_upstream_failure_is_502(make_client):
    http = FakeHttp().add("product/", HttpError(503, "down"))
    assert make_client(http).get("/barcode/12345678").status_code == 502


def test_token_constant_is_synthetic():
    assert json.dumps(TOKEN).startswith('"test-')
