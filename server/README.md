# Stezu food server

A small HTTP service that the iPhone app calls over the owner's tailnet for food logging:
Princeton FoodPro menus for every dining hall, photo identification through Claude, text
search, and barcode lookup. Python 3.12 or newer, FastAPI, one SQLite cache file.

The phone never holds a model key. Only the photo, the region volumes and the menu reach the
model; no health data does. Decisions: D-035 (matching across all halls, ranges), D-036
(where keys and tokens live), D-037 (how ranges are built).

## Run

    server/run_tests.sh      # offline tests; creates server/.venv on first use
    cd server && .venv/bin/uvicorn --factory stezu_server.app:create_app --host <tailnet address> --port <port>

`run_tests.sh` installs `requirements-dev.txt` into `server/.venv` when it is missing (that
step needs the network once). The tests block every socket.

## Configuration

Settings are read from `~/.config/stezu/server.env` (override the path with `STEZU_ENV_FILE`).
Keep that file outside the repo with mode 0600. Environment variables with the same names win.

| Key | Meaning | Default |
|---|---|---|
| `STEZU_TOKENS` | Comma-separated device bearer tokens, one per device | none: every call gets 401 |
| `STEZU_HOST`, `STEZU_PORT` | Bind address and port (used by the systemd unit) | none |
| `STEZU_DB` | SQLite cache file | `~/.local/share/stezu/server.sqlite3` |
| `STEZU_ANTHROPIC_BASE_URL` | Anthropic Messages API base URL, or a local proxy | `https://api.anthropic.com` |
| `STEZU_ANTHROPIC_API_KEY` | API key | none |
| `STEZU_ANTHROPIC_KEY_FILE` | File holding the key, read at call time (used when no key is set) | none |
| `STEZU_MODEL` | Model id | `claude-sonnet-4-6` |
| `STEZU_MODEL_TEMPERATURE` | `0`, or `none` for models that reject the parameter | `0` |
| `STEZU_USDA_KEY` | FoodData Central key (`DEMO_KEY` works for low volume) | none: USDA skipped |

Generate a device token with `python3 -c "import secrets; print(secrets.token_urlsafe(32))"`.

## Endpoints

Every endpoint except `/health` needs `Authorization: Bearer <device token>` and answers 401
without it. Missing numbers are `null`, never 0.

### `GET /health`

`{"status": "ok", "version": "0.1.0"}`

### `GET /menu?date=YYYY-MM-DD[&refresh=true]`

Every hall and meal period for the date (default: today in New York), cached per date (past
dates for good, today and later for 6 hours; a day where a hall failed to load is not cached).

```json
{"date": "2026-10-26", "source": "foodpro", "cached": false, "halls": [
  {"hall_id": "03", "hall": "Forbes College", "status": "available", "meals": [
    {"meal": "Breakfast", "items": [
      {"id": "03-B-581044", "recipe_id": "581044", "name": "Bacon or Sausage", "hall_id": "03",
       "hall": "Forbes College", "meal": "Breakfast", "station": "Early Entree", "serving": "1 each",
       "kcal": 193.0, "protein_g": 10.5, "carbs_g": 0.1, "fat_g": 16.4}]}]},
  {"hall_id": "04", "hall": "Graduate College", "status": "unavailable",
   "reason": "FoodPro shows No Data Available for this date", "meals": []},
  {"hall_id": "07", "hall": "Shultz Cafe", "status": "error", "error": "HTTP 503", "meals": []}]}
```

`status` is `available`, `unavailable` (the hall posts no menu that day) or `error`.
Cafes publish all-day cards such as "Today's Menu"; those count for every meal.

### `POST /scan`

JSON body, or `multipart/form-data` with the same fields and the JPEG in a `photo` file field:

```json
{"meal_id": "client UUID", "date": "2026-10-26", "meal": "lunch", "mode": "dining",
 "image_base64": "<JPEG, about 1000 px>", "photo_sha256": "optional, checked if sent",
 "regions": [{"region_id": "r1", "volume_ml": 240, "depth_confidence": 0.8}]}
```

The candidates are the items of every hall serving that meal on that date (`lunch` and
`breakfast` also match brunch). The same dish at several halls is one candidate. If no hall
serves the meal, or `mode` is `open_world`, every item is estimated open-world. The model
answers through a forced tool call (strict JSON), at temperature 0.

```json
{"estimate_id": "…", "meal_id": "…", "photo_sha256": "…", "date": "2026-10-26", "meal": "lunch",
 "mode": "dining", "model_id": "claude-sonnet-4-6", "candidates": 112, "rough": false,
 "complete": true, "cached": false,
 "items": [{"region_id": "r1", "item_id": "03-L-123456", "name": "…", "hall": "Forbes College",
            "halls": ["Forbes College", "Whitman College & Butler College"], "serving": "4 oz",
            "servings": 1.5, "confidence": 0.85, "rough": false,
            "alternates": [{"item_id": "…", "name": "…", "hall": "…", "confidence": 0.1}],
            "kcal": {"low": 213, "high": 366}, "protein_g": {"low": 11.6, "high": 19.9}}],
 "totals": {"kcal": {"low": 213, "high": 366}, "protein_g": {"low": 11.6, "high": 19.9}}}
```

`item_id` is `unlisted` when nothing on the menus fits; such items carry `rough: true` and a
range at least ±40% wide. A repeated `meal_id` with the same photo returns the cached answer
with `cached: true`. Errors: 400 for a bad request, 502 when the model call fails.

Range half-width for a menu item: 15% with a good depth region (confidence at least 0.6), else
25%, plus 15% times (1 − confidence), at most 50%, around FoodPro value × servings (D-037).

### `GET /search?q=…[&date=…][&meal=…][&estimate=true]`

Grouped results, each group with `source`, `status` (`ok`, `error`, `skipped`, `available`)
and `results`:

1. `dining`: fuzzy name matches across all halls for the date (and meal, if given), one
   entry per dish with every hall that serves it;
2. `open_food_facts`: packaged foods, per serving, per package and per 100 g or mL;
3. `usda_fdc`: FoodData Central, when `STEZU_USDA_KEY` is set;
4. `estimate`: `available` until asked; with `estimate=true` the model gives a rough kcal and
   protein range for the text (`rough: true`, at least ±40%). Use it for restaurant dishes.

One failing source never sinks the others. Remote results are cached for a day.

### `GET /barcode/{gtin}`

Open Food Facts lookup (8 to 14 digits; a 12-digit UPC is retried as EAN-13), cached:

```json
{"status": "found", "source": "open_food_facts", "gtin": "0049000028911", "name": "…",
 "brand": "…", "per_serving": {"label": "1 can (354.9 mL)", "quantity": 354.9, "unit": "ml",
 "kcal": 0, "protein_g": 0}, "per_package": {…}, "per_100": {"unit": "ml", "kcal": 0, "protein_g": 0},
 "cached": false}
```

or `{"status": "not_found", "gtin": "…"}`.

## Deploy as a systemd user service

Bind to the tailnet address only; do not open firewall ports. Run from a checkout of `main`
(a detached worktree keeps branch switches in the dev checkout from touching the service):

```ini
# ~/.config/systemd/user/stezu-server.service
[Unit]
Description=Stezu food server
After=network-online.target

[Service]
EnvironmentFile=%h/.config/stezu/server.env
WorkingDirectory=<checkout>/server
ExecStart=<checkout>/server/.venv/bin/uvicorn --factory stezu_server.app:create_app --host ${STEZU_HOST} --port ${STEZU_PORT} --no-server-header
Restart=on-failure
RestartSec=5
MemoryMax=300M

[Install]
WantedBy=default.target
```

    systemctl --user daemon-reload && systemctl --user enable --now stezu-server
    journalctl --user -u stezu-server -f      # logs go to journald

`Restart=on-failure` covers a boot where the tailnet address is not up yet. User services need
lingering (`loginctl enable-linger`) to run without a login session.
