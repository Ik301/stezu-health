"""Frist Late Meal: the Frist Gallery grill counter's menu, static with estimated nutrition (D-131).

The grill items live only in Agilysys OnDemand (no nutrition, behind DataDome), so the menu is a
hand-kept file, data/frist_late_meal.json. Each item served with fries is listed three ways:
the plate ("<entree> with fries", entree + fries summed), the entree alone and the fries. The plate
is for search and the menu; a photo scan only ever sees the entree and the fries (scan.candidates
drops plates), so a plate cannot be counted twice.
"""

from __future__ import annotations

import json
import re
from datetime import date as Date
from functools import lru_cache
from pathlib import Path
from typing import Any

PATH = Path(__file__).parent / "data" / "frist_late_meal.json"
DAYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")
NUTRIENTS = ("kcal", "protein_g", "carbs_g", "fat_g")
KEYWORDS = "Frist Late Meal grill"  # search.dining also matches these words


@lru_cache(maxsize=1)
def load() -> dict[str, Any]:
    return json.loads(PATH.read_text(encoding="utf-8"))


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def card_items(data: dict[str, Any], card: dict[str, Any]) -> list[dict[str, Any]]:
    """A card's items: each plate first, then its entree; the fries once, where the file lists them."""

    def item(name: str, src: dict[str, Any], serving: str, values: dict[str, float], basis: str) -> dict[str, Any]:
        return {
            "id": f"{data['hall_id']}-{card['code']}-{slug(name)}", "recipe_id": None, "name": name,
            "hall_id": data["hall_id"], "hall": data["hall"], "meal": card["meal"],
            "station": data["station"], "serving": serving, **values,
            "estimated": True, "basis": basis, "description": src["description"], "keywords": KEYWORDS,
        }

    fries = next(i for i in data["items"] if i["name"] == data["fries"])
    out = []
    for src in data["items"]:
        part = item(src["name"], src, src["serving"], {k: src[k] for k in NUTRIENTS}, src["basis"])
        if src.get("plate"):
            plate = src["plate"]
            values = {k: round(src[k] + fries[k], 1) for k in NUTRIENTS}
            fries_id = f"{data['hall_id']}-{card['code']}-{slug(fries['name'])}"
            out.append(item(plate["name"], src, plate["serving"], values,
                            f"{src['name']} + {fries['name']}, the two estimates summed")
                       | {"plate": True, "parts": [part["id"], fries_id]})
        out.append(part)
    return out


def hall(date: str) -> dict[str, Any] | None:
    """The pseudo-hall for a date, or None on a day Late Meal does not run (weekends)."""
    data = load()
    day = DAYS[Date.fromisoformat(date).weekday()]
    meals = [{"meal": c["meal"], "hours": c["hours"], "items": card_items(data, c)}
             for c in data["cards"] if day in c["days"]]
    if not meals:
        return None
    return {"hall_id": data["hall_id"], "hall": data["hall"], "status": "available", "source": "static",
            "estimated": True, "retrieved": data["retrieved"], "meals": meals}


def add_to(menu: dict[str, Any], date: str) -> dict[str, Any]:
    """The FoodPro menu plus Late Meal. Added after FoodPro's cache, so a FoodPro failure never hides it."""
    try:
        lm = hall(date)
    except Exception as exc:  # noqa: BLE001 - a broken file must not sink the FoodPro halls
        lm = {"hall_id": "LM", "hall": "Frist Late Meal", "status": "error", "source": "static",
              "error": str(exc)[:200], "meals": []}
    return menu if lm is None else menu | {"halls": [*menu["halls"], lm]}
