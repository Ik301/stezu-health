"""GET /search: dining items (fuzzy), Open Food Facts, USDA FoodData Central, text estimate."""

from __future__ import annotations

import re
from concurrent.futures import ThreadPoolExecutor
from difflib import SequenceMatcher
from typing import Any
from urllib.parse import quote, urlencode

from .barcode import OFF_FIELDS, product_view
from .scan import ROUGH_SPREAD, widen

OFF_SEARCH = "https://search.openfoodfacts.org/search?q={q}&page_size=8&fields=" + OFF_FIELDS
USDA_SEARCH = "https://api.nal.usda.gov/fdc/v1/foods/search?"
TTL = 86400
ESTIMATE_SYSTEM = (
    "Estimate the calories and protein of the food described, as eaten in one typical portion. "
    "Give honest ranges, wide when the description is vague. Answer only through the tool."
)
RANGE = {"type": "object", "properties": {"low": {"type": "number"}, "high": {"type": "number"}},
         "required": ["low", "high"]}
ESTIMATE_TOOL = {
    "name": "estimate_food",
    "description": "Rough nutrition for a described food.",
    "input_schema": {"type": "object", "properties": {
        "name": {"type": "string"}, "portion": {"type": "string"}, "kcal": RANGE, "protein_g": RANGE,
    }, "required": ["name", "portion", "kcal", "protein_g"]},
}


def score(query: str, name: str) -> float:
    """Whole-string similarity, or the share of query words found (typos allowed) in the name."""
    q, n = query.lower().strip(), name.lower()
    words = re.findall(r"\w+", n)
    q_words = re.findall(r"\w+", q)
    hits = sum(any(w.startswith(t) or SequenceMatcher(None, t, w).ratio() >= 0.8 for w in words)
               for t in q_words)
    return max(SequenceMatcher(None, q, n).ratio(), hits / len(q_words) if q_words else 0.0)


def dining(items: list[dict[str, Any]], query: str, limit: int = 15) -> list[dict[str, Any]]:
    groups: dict[tuple, dict[str, Any]] = {}
    for item in items:
        s = score(query, item["name"])
        if s < 0.6:
            continue
        key = (item["name"].lower(), item["meal"], item["serving"], item["kcal"])
        if key in groups:
            groups[key]["halls"].append(item["hall"])
        else:
            groups[key] = item | {"halls": [item["hall"]], "score": round(s, 2)}
    return sorted(groups.values(), key=lambda g: -g["score"])[:limit]


def off_search(http: Any, query: str) -> list[dict[str, Any]]:
    data = http.get_json(OFF_SEARCH.format(q=quote(query)), timeout=10)
    return [product_view(p) for p in data.get("hits", []) if p.get("product_name")]


def usda_search(http: Any, query: str, key: str) -> list[dict[str, Any]]:
    data = http.get_json(USDA_SEARCH + urlencode({"api_key": key, "query": query, "pageSize": 8}), timeout=10)
    out = []
    for food in data.get("foods", []):
        nutrients = {n.get("nutrientNumber"): n.get("value") for n in food.get("foodNutrients", [])}
        kcal, protein = nutrients.get("208"), nutrients.get("203")
        size, unit = food.get("servingSize"), (food.get("servingSizeUnit") or "").lower()
        per = (size / 100) if size and unit in ("g", "grm", "ml", "mlt") else None
        out.append({
            "fdc_id": food.get("fdcId"), "name": food.get("description"), "brand": food.get("brandOwner"),
            "data_type": food.get("dataType"),
            "per_100": {"unit": "g", "kcal": kcal, "protein_g": protein},
            "per_serving": {
                "label": food.get("householdServingFullText"), "quantity": size, "unit": unit or None,
                "kcal": round(kcal * per, 1) if per and kcal is not None else None,
                "protein_g": round(protein * per, 1) if per and protein is not None else None,
            },
        })
    return out


def estimate(model: Any, query: str) -> dict[str, Any]:
    answer = model.tool_call(ESTIMATE_SYSTEM, [{"type": "text", "text": query}], ESTIMATE_TOOL, 400)
    return {"name": answer.get("name") or query, "portion": answer.get("portion"), "rough": True,
            "spread_min": ROUGH_SPREAD, "model_id": model.model_id,
            "kcal": widen(answer.get("kcal"), 0), "protein_g": widen(answer.get("protein_g"), 1)}


def run_search(store: Any, http: Any, model: Any, usda_key: str | None, query: str,
               items: list[dict[str, Any]], want_estimate: bool) -> list[dict[str, Any]]:
    def remote(source: str, fn: Any) -> dict[str, Any]:
        key = f"search:{source}:{query.lower()}"
        cached = store.get(key, TTL)
        if cached is not None:
            return {"source": source, "status": "ok", "results": cached}
        try:
            results = fn()
        except Exception as exc:  # noqa: BLE001 - one source failing must not sink the rest
            return {"source": source, "status": "error", "error": str(exc)[:200], "results": []}
        store.put(key, results)
        return {"source": source, "status": "ok", "results": results}

    jobs = [("open_food_facts", lambda: off_search(http, query))]
    if usda_key:
        jobs.append(("usda_fdc", lambda: usda_search(http, query, usda_key)))
    with ThreadPoolExecutor(max_workers=2) as pool:
        groups = list(pool.map(lambda job: remote(*job), jobs))
    if not usda_key:
        groups.append({"source": "usda_fdc", "status": "skipped", "error": "no USDA key", "results": []})
    groups.insert(0, {"source": "dining", "status": "ok", "results": dining(items, query)})
    est: dict[str, Any] = {"source": "estimate", "status": "available", "results": []}
    if want_estimate:
        cached = store.get(f"estimate:{query.lower()}")
        try:
            result = cached or estimate(model, query)
            store.put(f"estimate:{query.lower()}", result)
            est = est | {"status": "ok", "results": [result]}
        except Exception as exc:  # noqa: BLE001
            est = est | {"status": "error", "error": str(exc)[:200]}
    return groups + [est]
