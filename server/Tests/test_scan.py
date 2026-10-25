from __future__ import annotations

import base64
import hashlib
import re

import pytest
from conftest import FakeHttp, fixture, foodpro_http

from stezu_server import foodpro
from stezu_server.config import Settings
from stezu_server.model import AnthropicClient, ModelError
from stezu_server.net import HttpError

DATE = "2026-10-26"
JPEG = b"\xff\xd8\xff\xe0" + b"synthetic-jpeg-bytes" * 10


class FakeModel:
    model_id = "fake-model"

    def __init__(self, answer):
        self.answer, self.calls = answer, []

    def tool_call(self, system, content, tool, max_tokens=1500):
        text = next(b["text"] for b in content if b["type"] == "text")
        self.calls.append({"system": system, "text": text, "content": content, "tool": tool})
        return self.answer(text) if callable(self.answer) else self.answer


def code_for(text: str, name: str) -> str:
    return re.search(rf"^(c\d+) \| {re.escape(name)} \|", text, re.M).group(1)


def body(**extra):
    return {"meal_id": "meal-1", "date": DATE, "meal": "breakfast",
            "image_base64": base64.b64encode(JPEG).decode()} | extra


def bacon(text, servings=1.3, confidence=0.9, region=None):
    item = {"code": code_for(text, "Bacon or Sausage"), "name": "bacon", "servings": servings,
            "confidence": confidence, "alternates": [{"code": "c999", "confidence": 0.1}]}
    return {"items": [item | ({"region_id": region} if region else {})]}


def test_scan_matches_every_hall_for_the_meal_and_returns_ranges(make_client):
    model = FakeModel(bacon)
    resp = make_client(foodpro_http(("03", "08")), model).post("/scan", json=body())
    assert resp.status_code == 200, resp.text
    out = resp.json()
    prompt = model.calls[0]["text"]
    assert "Bacon or Sausage" in prompt and "Forbes College, Whitman College & Butler College" in prompt
    breakfast = foodpro.parse_menu(fixture("foodpro_forbes.html"), "03")[0]["items"]
    assert out["candidates"] == len(breakfast)  # two halls, same dishes: merged, breakfast only
    item = out["items"][0]
    assert item["item_id"] == "03-B-581044" and item["servings"] == 1.5  # snapped to 0.5 steps
    assert item["halls"] == ["Forbes College", "Whitman College & Butler College"]
    assert item["hall"] == "Forbes College" and item["rough"] is False
    assert item["alternates"] == []  # invented codes are dropped
    mid = 193 * 1.5
    assert item["kcal"]["low"] < mid < item["kcal"]["high"]
    assert item["kcal"]["low"] == round(mid * (1 - 0.265)) and item["kcal"]["high"] == round(mid * 1.265)
    assert out["totals"]["kcal"] == item["kcal"] and out["rough"] is False
    assert out["model_id"] == "fake-model" and out["photo_sha256"] == hashlib.sha256(JPEG).hexdigest()
    image = model.calls[0]["content"][0]
    assert image["type"] == "image" and image["source"]["media_type"] == "image/jpeg"


def test_good_depth_narrows_the_range(make_client):
    model = FakeModel(lambda t: bacon(t, servings=1, confidence=1.0, region="r1"))
    regions = [{"region_id": "r1", "volume_ml": 120, "depth_confidence": 0.9}]
    out = make_client(foodpro_http(), model).post("/scan", json=body(regions=regions)).json()
    assert out["items"][0]["kcal"] == {"low": round(193 * 0.85), "high": round(193 * 1.15)}
    assert "r1: 120 mL" in model.calls[0]["text"]


def test_unlisted_item_is_rough_with_a_wide_range(make_client):
    answer = {"items": [{"code": "unlisted", "name": "Homemade curry", "servings": 1, "confidence": 0.4,
                         "alternates": [], "unlisted_kcal": {"low": 450, "high": 550},
                         "unlisted_protein_g": {"low": 18, "high": 22}}]}
    out = make_client(foodpro_http(), FakeModel(answer)).post("/scan", json=body()).json()
    item = out["items"][0]
    assert item["item_id"] == "unlisted" and item["rough"] is True and out["rough"] is True
    assert item["kcal"] == {"low": 300, "high": 700}  # widened to +-40% of the midpoint
    assert item["protein_g"] == {"low": 12.0, "high": 28.0}


def test_same_meal_and_photo_is_idempotent(make_client):
    model = FakeModel(bacon)
    client = make_client(foodpro_http(), model)
    first = client.post("/scan", json=body()).json()
    second = client.post("/scan", json=body()).json()
    assert len(model.calls) == 1 and second["cached"] is True
    assert second["estimate_id"] == first["estimate_id"]
    other = body(image_base64=base64.b64encode(JPEG + b"x").decode())
    client.post("/scan", json=other)
    assert len(model.calls) == 2


def test_multipart_upload(make_client):
    model = FakeModel(bacon)
    resp = make_client(foodpro_http(), model).post(
        "/scan", data={"meal_id": "m-2", "date": DATE, "meal": "breakfast", "regions": "[]"},
        files={"photo": ("p.jpg", JPEG, "image/jpeg")})
    assert resp.status_code == 200, resp.text
    assert resp.json()["items"][0]["item_id"] == "03-B-581044"


def test_no_open_hall_falls_back_to_open_world(make_client):
    model = FakeModel({"items": []})
    closed = FakeHttp().add("menuDetails.asp", fixture("foodpro_nodata.html"))
    out = make_client(closed, model).post("/scan", json=body(meal="dinner"))
    assert out.json()["mode"] == "open_world" and out.json()["rough"] is True
    assert "No menu applies" in model.calls[0]["text"]


@pytest.mark.parametrize("extra, message", [
    ({"image_base64": base64.b64encode(b"GIF89a").decode()}, "JPEG"),
    ({"photo_sha256": "0" * 64}, "does not match"),
    ({"meal_id": ""}, "meal_id"),
    ({"meal": None}, "meal is required"),
    ({"mode": "other"}, "mode"),
    ({"regions": "not json"}, "regions"),
    ({"date": "tomorrow"}, "date"),
])
def test_bad_requests_are_400(make_client, extra, message):
    resp = make_client(foodpro_http(), FakeModel({"items": []})).post("/scan", json=body(**extra))
    assert resp.status_code == 400 and message in resp.json()["detail"]


def test_model_failure_is_502(make_client):
    class Broken(FakeModel):
        def tool_call(self, *a, **k):
            raise ModelError("model call failed: HTTP 529")

    assert make_client(foodpro_http(), Broken(None)).post("/scan", json=body()).status_code == 502


def tool_reply(data):
    return {"content": [{"type": "text", "text": "x"}, {"type": "tool_use", "name": "t", "input": data}]}


def test_client_sends_temperature_zero_and_a_forced_tool(tmp_path):
    http = FakeHttp()
    http.post_replies.append(tool_reply({"ok": True}))
    s = Settings(tokens=frozenset(), db_path=tmp_path / "d", anthropic_base_url="http://model.test",
                 anthropic_api_key="k", model="m-1")
    out = AnthropicClient(s, http).tool_call("sys", [{"type": "text", "text": "hi"}], {"name": "t"})
    sent = http.posts[0]
    assert out == {"ok": True} and sent["url"] == "http://model.test/v1/messages"
    assert sent["payload"]["temperature"] == 0 and sent["payload"]["model"] == "m-1"
    assert sent["payload"]["tool_choice"] == {"type": "tool", "name": "t"}
    assert sent["headers"]["x-api-key"] == "k"


def test_client_retries_without_temperature_when_the_model_rejects_it(tmp_path):
    http = FakeHttp()
    http.post_replies += [HttpError(400, "`temperature` is deprecated for this model."), tool_reply({})]
    s = Settings(tokens=frozenset(), db_path=tmp_path / "d", anthropic_api_key="k")
    AnthropicClient(s, http).tool_call("sys", [], {"name": "t"})
    assert "temperature" in http.posts[0]["payload"] and "temperature" not in http.posts[1]["payload"]


def test_client_reads_key_file_and_reports_missing_key(tmp_path):
    s = Settings(tokens=frozenset(), db_path=tmp_path / "d", anthropic_key_file=tmp_path / "none")
    with pytest.raises(ModelError, match="no model API key"):
        AnthropicClient(s, FakeHttp()).tool_call("sys", [], {"name": "t"})
