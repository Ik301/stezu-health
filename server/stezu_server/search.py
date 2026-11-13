"""GET /search: dining items (fuzzy), Open Food Facts, USDA FoodData Central, text estimate."""

from __future__ import annotations

import re
from concurrent.futures import ThreadPoolExecutor
from difflib import SequenceMatcher
from typing import Any
from urllib.parse import quote, urlencode

from .barcode import OFF_FIELDS, _num, product_view
from .scan import ROUGH_SPREAD, widen

OFF_PAGE = 100  # OFF puts brand-only entries first and the real product near hit 50; fetch past it
OFF_KEEP = 8
OFF_SEARCH = f"https://search.openfoodfacts.org/search?q={{q}}&page_size={OFF_PAGE}&fields=" + OFF_FIELDS
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
    """An item's `keywords` (Frist Late Meal's hall words) count as part of its name."""
    groups: dict[tuple, dict[str, Any]] = {}
    for item in items:
        s = score(query, item["name"])
        if item.get("keywords"):
            s = max(s, score(query, f"{item['keywords']} {item['name']}"))
        if s < 0.6:
            continue
        key = (item["name"].lower(), item["meal"], item["serving"], item["kcal"])
        if key in groups:
            groups[key]["halls"].append(item["hall"])
        else:
            groups[key] = item | {"halls": [item["hall"]], "score": round(s, 2)}
    return sorted(groups.values(), key=lambda g: -g["score"])[:limit]


MIN_REMOTE_QUERY = 3  # shorter queries are keystrokes in progress; they would spend the USDA quota


def with_portion(result: dict[str, Any]) -> dict[str, Any]:
    """A result with no per-serving kcal gets 100 g (or mL) as its serving, marked `basis: per_100`.

    Open Food Facts' search index carries only per-100 g nutrients and USDA generic foods have no
    serving size, so without this the phone shows "-- kcal" for numbers the source does have.
    """
    serving, per100 = result.get("per_serving") or {}, result.get("per_100") or {}
    if serving.get("kcal") is not None or per100.get("kcal") is None:
        return result
    unit = "mL" if (per100.get("unit") or "g").lower() in ("ml", "mlt") else "g"
    protein = per100.get("protein_g")
    return result | {"per_serving": {"label": f"100 {unit}", "quantity": 100, "unit": unit.lower(),
                                     "kcal": round(per100["kcal"], 1),
                                     "protein_g": round(protein, 1) if protein is not None else None,
                                     "basis": "per_100"}}


def _words(text: str | None) -> list[str]:
    return re.findall(r"\w+", (text or "").lower())


def relevance(query: str, name: str | None, brand: str | None, brand_words: frozenset[str] = frozenset()) -> float:
    """Points per query word that starts a word of the name or brand, over the number of query words.

    A word found in the name scores 1; a brand word scores ½ wherever it is found, so the product
    itself outranks the brand: for "creatine optimum nutrition", "Micronized Creatine Powder" by
    Optimum Nutrition scores 2/3 and an Optimum Nutrition protein bar 1/3. `brand_words` are the
    brand words of every result in the list, so "Optimum Nutrition Whey" with no brand set still
    counts its brand words at ½.
    """
    q_words = list(dict.fromkeys(_words(query)))
    if not q_words:
        return 0.0
    name_words, own_brand = _words(name), _words(brand)
    points = 0.0
    for t in q_words:
        branded = t in own_brand or t in brand_words  # whole words: "bar" is not the brand Barebells
        if any(w.startswith(t) for w in name_words):
            points += 0.5 if branded else 1.0
        elif any(w.startswith(t) for w in own_brand):
            points += 0.5
    return round(points / len(q_words), 4)


def rank(results: list[dict[str, Any]], query: str) -> list[dict[str, Any]]:
    """Most relevant first; at equal relevance, results the phone can log (a kcal) first; then the source's order."""
    brands = frozenset(w for r in results for w in _words(r.get("brand")))
    return sorted(results, key=lambda r: (-relevance(query, r.get("name"), r.get("brand"), brands),
                                          (r.get("per_serving") or {}).get("kcal") is None))


def _brand_only(p: dict[str, Any]) -> bool:
    """An OFF hit with no name, or whose name is just one of its brands ("Optimum Nutrition")."""
    name = (p.get("product_name") or "").strip().lower()
    brands = p.get("brands") or ""
    parts = ",".join(brands) if isinstance(brands, list) else str(brands)
    return not name or name in {b.strip().lower() for b in parts.split(",")}


def package_size(p: dict[str, Any]) -> str | None:
    """The package as labelled ("600 g"): OFF's `quantity`, else `product_quantity` and its unit."""
    label = str(p.get("quantity") or "").strip()
    if label:
        return label
    amount = _num(p.get("product_quantity"))
    return f"{amount:g} {p.get('product_quantity_unit') or 'g'}" if amount else None


def off_search(http: Any, query: str) -> list[dict[str, Any]]:
    data = http.get_json(OFF_SEARCH.format(q=quote(query)), timeout=10)
    hits = [p for p in data.get("hits", []) if not _brand_only(p)]
    results = [with_portion(product_view(p)) | {"package_size": package_size(p)} for p in hits]
    return rank(results, query)[:OFF_KEEP]


def _measure(food: dict[str, Any]) -> tuple[str, float] | None:
    """The first household measure with a weight ("1 tender", 25 g), skipping "Quantity not specified"."""
    for m in food.get("foodMeasures") or []:
        text, grams = (m.get("disseminationText") or "").strip(), m.get("gramWeight")
        if text and grams and "not specified" not in text.lower():
            return text, float(grams)
    return None


def usda_search(http: Any, query: str, key: str) -> list[dict[str, Any]]:
    data = http.get_json(USDA_SEARCH + urlencode({"api_key": key, "query": query, "pageSize": 8}), timeout=10)
    out = []
    for food in data.get("foods", []):
        nutrients = {n.get("nutrientNumber"): n.get("value") for n in food.get("foodNutrients", [])}
        kcal, protein = nutrients.get("208"), nutrients.get("203")
        size, unit = food.get("servingSize"), (food.get("servingSizeUnit") or "").lower()
        per = (size / 100) if size and unit in ("g", "grm", "ml", "mlt") else None
        measure = None if per else _measure(food)
        if measure and kcal is not None:
            label, grams = measure
            out.append({
                "fdc_id": food.get("fdcId"), "name": food.get("description"), "brand": food.get("brandOwner"),
                "data_type": food.get("dataType"), "package_size": food.get("packageWeight") or None,
                "per_100": {"unit": "g", "kcal": kcal, "protein_g": protein},
                "per_serving": {
                    "label": label, "quantity": grams, "unit": "g", "kcal": round(kcal * grams / 100, 1),
                    "protein_g": round(protein * grams / 100, 1) if protein is not None else None,
                    "basis": "measure",
                },
            })
            continue
        out.append({
            "fdc_id": food.get("fdcId"), "name": food.get("description"), "brand": food.get("brandOwner"),
            "data_type": food.get("dataType"), "package_size": food.get("packageWeight") or None,
            "per_100": {"unit": "g", "kcal": kcal, "protein_g": protein},
            "per_serving": {
                "label": food.get("householdServingFullText"), "quantity": size, "unit": unit or None,
                "kcal": round(kcal * per, 1) if per and kcal is not None else None,
                "protein_g": round(protein * per, 1) if per and protein is not None else None,
            },
        })
    return rank([with_portion(r) for r in out], query)


def estimate(model: Any, query: str) -> dict[str, Any]:
    answer = model.tool_call(ESTIMATE_SYSTEM, [{"type": "text", "text": query}], ESTIMATE_TOOL, 400)
    return {"name": answer.get("name") or query, "portion": answer.get("portion"), "rough": True,
            "spread_min": ROUGH_SPREAD, "model_id": model.model_id,
            "kcal": widen(answer.get("kcal"), 0), "protein_g": widen(answer.get("protein_g"), 1)}


def run_search(store: Any, http: Any, model: Any, usda_key: str | None, query: str,
               items: list[dict[str, Any]], want_estimate: bool) -> list[dict[str, Any]]:
    def remote(source: str, fn: Any) -> dict[str, Any]:
        key = f"search3:{source}:{query.lower()}"  # search3: relevance order, brand-only rows dropped, package_size
        cached = store.get(key, TTL)
        if cached is not None:
            return {"source": source, "status": "ok", "results": cached}
        try:
            results = fn()
        except Exception as exc:  # noqa: BLE001 - one source failing must not sink the rest
            return {"source": source, "status": "error", "error": str(exc)[:200], "results": []}
        store.put(key, results)
        return {"source": source, "status": "ok", "results": results}

    if len(query.strip()) < MIN_REMOTE_QUERY:
        short = {"status": "skipped", "error": "query too short", "results": []}
        groups = [{"source": "open_food_facts"} | short, {"source": "usda_fdc"} | short]
    else:
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
