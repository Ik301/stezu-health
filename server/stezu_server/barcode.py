"""Packaged food by GTIN from Open Food Facts, cached."""

from __future__ import annotations

import re
from typing import Any

from .net import HttpError

OFF_FIELDS = (
    "code,product_name,brands,serving_size,serving_quantity,product_quantity,"
    "product_quantity_unit,quantity,nutriments"
)
OFF_PRODUCT = "https://world.openfoodfacts.org/api/v2/product/{code}.json?fields=" + OFF_FIELDS
FOUND_TTL = 30 * 86400
MISS_TTL = 86400


def _num(value: Any) -> float | None:
    try:
        return None if value in (None, "") else float(value)
    except (TypeError, ValueError):
        return None


def product_view(p: dict[str, Any]) -> dict[str, Any]:
    """Name, serving and kcal/protein per serving, per package and per 100 g or mL."""
    n = p.get("nutriments") or {}
    unit = p.get("product_quantity_unit") or "g"

    def amount(key: str, suffix: str, quantity: float | None) -> float | None:
        labelled = _num(n.get(f"{key}_{suffix}")) if suffix == "serving" else None
        per100 = _num(n.get(f"{key}_100g"))
        if labelled is not None:
            return labelled
        return round(per100 * quantity / 100, 1) if per100 is not None and quantity else None

    def portion(label: Any, quantity: float | None, suffix: str) -> dict[str, Any]:
        return {
            "label": label,
            "quantity": quantity,
            "unit": unit,
            "kcal": amount("energy-kcal", suffix, quantity),
            "protein_g": amount("proteins", suffix, quantity),
        }

    brands = p.get("brands")
    return {
        "gtin": p.get("code"),
        "name": p.get("product_name") or None,
        "brand": ", ".join(brands) if isinstance(brands, list) else brands or None,
        "per_serving": portion(p.get("serving_size"), _num(p.get("serving_quantity")), "serving"),
        "per_package": portion(p.get("quantity"), _num(p.get("product_quantity")), "package"),
        "per_100": {
            "unit": unit,
            "kcal": _num(n.get("energy-kcal_100g")),
            "protein_g": _num(n.get("proteins_100g")),
        },
    }


def lookup(store: Any, http: Any, gtin: str) -> dict[str, Any]:
    if not re.fullmatch(r"\d{8,14}", gtin):
        raise ValueError("gtin must be 8 to 14 digits")
    cached = store.get(f"barcode:{gtin}", FOUND_TTL) or store.get(f"barcode-miss:{gtin}", MISS_TTL)
    if cached is not None:
        return cached | {"cached": True}
    for code in [gtin] + (["0" + gtin] if len(gtin) == 12 else []):  # UPC-A as EAN-13
        try:
            data = http.get_json(OFF_PRODUCT.format(code=code), timeout=10)
        except HttpError as exc:
            if exc.status != 404:
                raise
            continue
        if data.get("status") == 1 and data.get("product"):
            result = {"status": "found", "source": "open_food_facts"} | product_view(data["product"])
            store.put(f"barcode:{gtin}", result)
            return result | {"cached": False}
    result = {"status": "not_found", "gtin": gtin, "source": "open_food_facts"}
    store.put(f"barcode-miss:{gtin}", result)
    return result | {"cached": False}
