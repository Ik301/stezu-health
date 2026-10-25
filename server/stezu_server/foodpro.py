"""Princeton FoodPro menus (menus.princeton.edu): every hall, every meal, per-item nutrition."""

from __future__ import annotations

import html
import re
from concurrent.futures import ThreadPoolExecutor
from typing import Any
from urllib.parse import quote, quote_plus

BASE = "https://menus.princeton.edu/dining/_Foodpro/online-menu/menuDetails.asp"
LOCATIONS = {
    "01": "Rockefeller & Mathey Colleges",
    "03": "Forbes College",
    "04": "Graduate College",
    "05": "Center for Jewish Life",
    "06": "Yeh & Huo Colleges",
    "07": "Shultz Cafe",
    "08": "Whitman College & Butler College",
    "12": "Tiger Tea Room",
    "15": "The Gallery",
    "16": "Witherspoon's",
    "23": "Chemistry CaFe",
    "24": "EQuad Cafe",
    "26": "Genomics Cafe",
}
MEAL_CODES = {"breakfast": "B", "brunch": "R", "lunch": "L", "dinner": "D"}
PERIODS = ("breakfast", "brunch", "lunch", "dinner")
# A requested meal also matches the weekend brunch card.
MEAL_MATCH = {
    "breakfast": {"breakfast", "brunch"},
    "lunch": {"lunch", "brunch"},
    "brunch": {"brunch", "breakfast", "lunch"},
    "dinner": {"dinner"},
}
CARD_RE = re.compile(r'<div class="card\s+mealCard">')
HEADER_RE = re.compile(r'<div class="card-header">\s*([^<]+)<')
TOKEN_RE = re.compile(
    r'<div class="mealStation">\s*(.*?)</div>'
    r'|<div class="btn-text" data-recipeid="(\d+)">\s*<span class="title">(.*?)</span>',
    re.DOTALL,  # station names span lines
)
FACT_RE = re.compile(r"<strong>(?:&nbsp;|\s)*([^<:]+):(?:&nbsp;)*</strong>(?:&nbsp;|\s)*([^<]*)", re.DOTALL)
MENU_TTL = 6 * 3600  # today's and future menus get refreshed; past ones are kept


def menu_url(location: str, date: str) -> str:
    yyyy, mm, dd = date.split("-")
    dtdate = quote(f"{int(mm)}/{int(dd)}/{yyyy}", safe="")  # slashes must be %2F
    return (
        f"{BASE}?sName=Princeton+University+Campus+Dining&locationNum={location}"
        f"&locationName={quote_plus(LOCATIONS[location])}&dtdate={dtdate}&myaction=read&naFlag=1"
    )


def clean(text: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", text))).strip()


def number(text: str | None) -> float | None:
    """First number in a label value; None when absent (absent is not zero)."""
    m = re.search(r"\d+(?:\.\d+)?", (text or "").replace(",", ""))
    return float(m.group()) if m else None


def parse_menu(page: str, location: str) -> list[dict[str, Any]] | None:
    """Meal periods with items. None when the page has no meal cards."""
    blocks = CARD_RE.split(page)[1:]
    if not blocks:
        return None
    meals = []
    for block in blocks:
        header = HEADER_RE.search(block)
        meal = clean(header.group(1)) if header else "Menu"
        code = MEAL_CODES.get(meal.lower()) or "".join(w[0] for w in re.findall(r"[A-Za-z]+", meal)).upper()
        tokens = list(TOKEN_RE.finditer(block))
        station, items, seen = None, [], set()
        for i, m in enumerate(tokens):
            if m.group(1) is not None:
                station = clean(m.group(1))
                continue
            end = tokens[i + 1].start() if i + 1 < len(tokens) else len(block)
            facts: dict[str, str] = {}
            for label, value in FACT_RE.findall(block[m.end() : end]):
                facts.setdefault(clean(label), clean(value))
            item_id = f"{location}-{code}-{m.group(2)}"
            if item_id in seen:
                continue
            seen.add(item_id)
            carbs = facts.get("Total Carbohydrates", facts.get("Total Carbohydrate"))
            items.append({
                "id": item_id,
                "recipe_id": m.group(2),
                "name": clean(m.group(3)),
                "hall_id": location,
                "hall": LOCATIONS[location],
                "meal": meal,
                "station": station,
                "serving": facts.get("Serving Size"),
                "kcal": number(facts.get("Calories")),
                "protein_g": number(facts.get("Protein")),
                "carbs_g": number(carbs),
                "fat_g": number(facts.get("Total Fat")),
            })
        meals.append({"meal": meal, "items": items})
    return meals


def fetch_hall(http: Any, location: str, date: str) -> dict[str, Any]:
    hall = {"hall_id": location, "hall": LOCATIONS[location], "meals": []}
    try:
        page = http.get_text(menu_url(location, date))
    except Exception as exc:  # noqa: BLE001 - one hall failing must not sink the day
        return hall | {"status": "error", "error": str(exc)[:200]}
    meals = parse_menu(page, location)
    if meals is None and "No Data Available" in page:
        # Closed that day: absent, not an empty menu.
        return hall | {"status": "unavailable", "reason": "FoodPro shows No Data Available for this date"}
    if meals is None:
        return hall | {"status": "error", "error": "unrecognized menu page"}
    return hall | {"status": "available", "meals": [m for m in meals if m["items"]]}


def get_menu(store: Any, http: Any, date: str, today: str, refresh: bool = False) -> dict[str, Any]:
    """All halls for a date, cached per date. A day with fetch errors is not cached."""
    key = f"menu:{date}"
    cached = None if refresh else store.get(key, None if date < today else MENU_TTL)
    if cached is not None:
        return cached | {"cached": True}
    with ThreadPoolExecutor(max_workers=4) as pool:
        halls = list(pool.map(lambda loc: fetch_hall(http, loc, date), LOCATIONS))
    menu = {"date": date, "source": "foodpro", "halls": halls}
    if all(h["status"] != "error" for h in halls):
        store.put(key, menu)
    return menu | {"cached": False}


def serves(card: str, wanted: set[str]) -> bool:
    """'Continental Breakfast' counts as breakfast; a cafe's all-day card counts for every meal."""
    periods = {p for p in PERIODS if p in card.lower()}
    return not periods or bool(periods & wanted)


def meal_items(menu: dict[str, Any], meal: str | None = None) -> list[dict[str, Any]]:
    """Items across every available hall, optionally for one meal period."""
    wanted = MEAL_MATCH.get(meal.lower(), {meal.lower()}) if meal else None
    return [
        item
        for hall in menu["halls"]
        for m in hall["meals"]
        if wanted is None or serves(m["meal"], wanted)
        for item in m["items"]
    ]
