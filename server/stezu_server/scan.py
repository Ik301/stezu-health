"""POST /scan: identify a meal photo against every hall's items for that date and meal."""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
from typing import Any

SYSTEM = """You identify the foods on a plate photographed at Princeton University dining halls.
The candidates are the menu items of every hall open for this meal, one per line:
code | name | serving | kcal per serving | protein g per serving | halls
Rules:
- Report each distinct food you can see once.
- Choose only from the candidates. Use "unlisted" when nothing fits.
- servings: how many listed servings are on the plate, in steps of 0.5, at least 0.5.
- confidence: 0 to 1 that your chosen code is right.
- alternates: up to 2 other plausible candidate codes, each with a confidence.
- For "unlisted" give a short name and a kcal and protein range for the portion shown.
- Region volumes, when given, come from the phone's depth camera; use them for portions.
Answer only through the report_items tool."""

RANGE = {"type": "object", "properties": {"low": {"type": "number"}, "high": {"type": "number"}},
         "required": ["low", "high"]}
TOOL = {
    "name": "report_items",
    "description": "Report the foods identified in the photo.",
    "input_schema": {
        "type": "object",
        "properties": {"items": {"type": "array", "items": {
            "type": "object",
            "properties": {
                "code": {"type": "string", "description": "candidate code, or unlisted"},
                "name": {"type": "string"},
                "region_id": {"type": "string"},
                "servings": {"type": "number"},
                "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                "alternates": {"type": "array", "maxItems": 2, "items": {
                    "type": "object",
                    "properties": {"code": {"type": "string"}, "confidence": {"type": "number"}},
                    "required": ["code", "confidence"],
                }},
                "unlisted_kcal": RANGE,
                "unlisted_protein_g": RANGE,
            },
            "required": ["code", "name", "servings", "confidence", "alternates"],
        }}},
        "required": ["items"],
    },
}
ROUGH_SPREAD = 0.4  # open-world estimates are off by 35-50% (research report 03)
ESTIMATED_EXTRA = 0.15  # menu values that are estimates themselves (Frist Late Meal, D-131)
MAX_IMAGE_BYTES = 6 * 1024 * 1024


class ScanError(ValueError):
    pass


def decode_image(image: bytes | None, image_b64: str | None, claimed_sha: str | None) -> tuple[bytes, str]:
    if image is None:
        try:
            image = base64.b64decode(image_b64 or "", validate=True)
        except (binascii.Error, ValueError):
            raise ScanError("image_base64 is not valid base64") from None
    if not image.startswith(b"\xff\xd8") or len(image) > MAX_IMAGE_BYTES:
        raise ScanError("photo must be a JPEG under 6 MB")
    sha = hashlib.sha256(image).hexdigest()
    if claimed_sha and claimed_sha.lower() != sha:
        raise ScanError("photo_sha256 does not match the photo")
    return image, sha


def candidates(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """One code per distinct dish; the same recipe served at several halls lists every hall.

    Plates (an entree with its fries summed) are left out: the photo shows the entree and the
    fries, which are candidates of their own, so a plate could only double count.
    """
    groups: dict[tuple, dict[str, Any]] = {}
    for item in items:
        if item.get("plate"):
            continue
        key = (item["name"].lower(), item["serving"], item["kcal"], item["protein_g"])
        if key in groups:
            groups[key]["halls"].append(item["hall"])
        else:
            groups[key] = item | {"code": f"c{len(groups) + 1}", "halls": [item["hall"]]}
    return list(groups.values())


def spread(confidence: float, depth_ok: bool, estimated: bool = False) -> float:
    """Half-width of a range as a fraction: 15-25% on campus (report 03), wider when unsure.

    An estimated menu value (no published nutrition) adds 15 points: 30-40%, at most 65%.
    """
    extra = ESTIMATED_EXTRA if estimated else 0.0
    return min(0.5 + extra, (0.15 if depth_ok else 0.25) + extra + 0.15 * (1 - confidence))


def span(per_serving: float | None, servings: float, s: float, digits: int) -> dict[str, Any]:
    if per_serving is None:
        return {"low": None, "high": None}
    mid = per_serving * servings
    return {"low": round(mid * (1 - s), digits), "high": round(mid * (1 + s), digits)}


def widen(r: dict[str, Any] | None, digits: int) -> dict[str, Any]:
    """At least +-40% around the midpoint for a rough, open-world estimate."""
    if not r or r.get("low") is None or r.get("high") is None:
        return {"low": None, "high": None}
    low, high = sorted((max(0.0, float(r["low"])), max(0.0, float(r["high"]))))
    mid = (low + high) / 2
    return {"low": round(min(low, mid * (1 - ROUGH_SPREAD)), digits),
            "high": round(max(high, mid * (1 + ROUGH_SPREAD)), digits)}


def prompt(req: dict[str, Any], cands: list[dict[str, Any]], image: bytes) -> list[dict[str, Any]]:
    lines = [f"{c['code']} | {c['name']} | {c['serving'] or '?'} | {c['kcal']} | {c['protein_g']} | "
             + ", ".join(c["halls"]) + (" (estimated values)" if c.get("estimated") else "") for c in cands]
    regions = [f"{r.get('region_id', '?')}: {r.get('volume_ml')} mL, depth confidence "
               f"{r.get('depth_confidence')}" for r in req["regions"]]
    text = (f"Date {req['date']}, meal {req['meal'] or 'unknown'}.\n"
            + ("Candidates:\n" + "\n".join(lines) if lines else
               "No menu applies: name every item as unlisted with an open-world estimate.")
            + ("\nRegions:\n" + "\n".join(regions) if regions else ""))
    return [{"type": "image", "source": {"type": "base64", "media_type": "image/jpeg",
                                          "data": base64.b64encode(image).decode()}},
            {"type": "text", "text": text}]


def run_scan(store: Any, model: Any, menu_items: list[dict[str, Any]], req: dict[str, Any],
             image: bytes, sha: str) -> dict[str, Any]:
    key = f"scan:{req['meal_id']}:{sha}"
    cached = store.get(key)
    if cached is not None:
        return cached | {"cached": True}
    cands = candidates(menu_items) if req["mode"] == "dining" else []
    by_code = {c["code"]: c for c in cands}
    depth = {r.get("region_id"): (r.get("depth_confidence") or 0) >= 0.6 for r in req["regions"]}
    answer = model.tool_call(SYSTEM, prompt(req, cands, image), TOOL)
    items = []
    for raw in answer.get("items", []):
        servings = max(0.5, round(float(raw.get("servings") or 1) * 2) / 2)
        conf = min(1.0, max(0.0, float(raw.get("confidence") or 0)))
        alternates = [{"item_id": by_code[a["code"]]["id"], "name": by_code[a["code"]]["name"],
                       "hall": by_code[a["code"]]["hall"], "confidence": a.get("confidence")}
                      for a in raw.get("alternates", [])[:2] if a.get("code") in by_code]
        base = {"region_id": raw.get("region_id"), "servings": servings, "confidence": conf,
                "alternates": alternates}
        c = by_code.get(raw.get("code"))
        if c is None:  # unlisted, or a code the model invented
            items.append(base | {"item_id": "unlisted", "name": raw.get("name") or "Unknown food",
                                 "hall": None, "halls": [], "serving": None, "rough": True,
                                 "estimated": False,
                                 "kcal": widen(raw.get("unlisted_kcal"), 0),
                                 "protein_g": widen(raw.get("unlisted_protein_g"), 1)})
            continue
        estimated = bool(c.get("estimated"))
        s = spread(conf, depth.get(raw.get("region_id"), False), estimated)
        items.append(base | {"item_id": c["id"], "name": c["name"], "hall": c["hall"],
                             "halls": c["halls"], "serving": c["serving"], "rough": False,
                             "estimated": estimated,
                             "kcal": span(c["kcal"], servings, s, 0),
                             "protein_g": span(c["protein_g"], servings, s, 1)})
    totals = {k: {"low": round(sum(i[k]["low"] or 0 for i in items), 1),
                  "high": round(sum(i[k]["high"] or 0 for i in items), 1)} for k in ("kcal", "protein_g")}
    result = {
        "estimate_id": hashlib.sha256(key.encode()).hexdigest()[:16],
        "meal_id": req["meal_id"], "photo_sha256": sha, "date": req["date"], "meal": req["meal"],
        "mode": req["mode"], "model_id": model.model_id, "candidates": len(cands),
        "rough": req["mode"] == "open_world" or any(i["rough"] for i in items),
        "estimated": any(i["estimated"] for i in items),
        "complete": all(i[k]["low"] is not None for i in items for k in ("kcal", "protein_g")),
        "items": items, "totals": totals,
    }
    store.put(key, result)
    return result | {"cached": False}


def parse_request(fields: dict[str, Any]) -> dict[str, Any]:
    meal_id = str(fields.get("meal_id") or "").strip()
    if not meal_id or len(meal_id) > 100:
        raise ScanError("meal_id is required (a client UUID, at most 100 characters)")
    mode = fields.get("mode") or "dining"
    if mode not in ("dining", "open_world"):
        raise ScanError("mode must be dining or open_world")
    regions = fields.get("regions") or []
    if isinstance(regions, str):
        try:
            regions = json.loads(regions)
        except ValueError:
            raise ScanError("regions must be a JSON list") from None
    if not isinstance(regions, list) or not all(isinstance(r, dict) for r in regions):
        raise ScanError("regions must be a list of objects")
    meal = (fields.get("meal") or "").strip().lower() or None
    if mode == "dining" and not meal:
        raise ScanError("meal is required in dining mode (breakfast, brunch, lunch or dinner)")
    return {"meal_id": meal_id, "mode": mode, "regions": regions[:20], "meal": meal}
