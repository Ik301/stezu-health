# Stezu food server

A small HTTP service that the iPhone app calls over the owner's tailnet for food logging:
Princeton FoodPro menus for every dining hall, photo identification through Claude, text
search, and barcode lookup. Python 3.12 or newer, FastAPI, one SQLite cache file.

The phone never holds a model key. Only the photo, the region volumes and the menu reach the
model; no health data does. Decisions: D-035 (matching across all halls, ranges), D-036
(where keys and tokens live), D-037 (how ranges are built).

It also receives the phone's Apple Health samples and Stezu's own records through `POST /sync`
and keeps them in a separate SQLite database that Hermes reads (D-048). `/sync` never calls a
model.

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
| `STEZU_HEALTH_DB` | Health database for `/sync` (created on start, mode 0600, WAL) | `~/.local/share/stezu/health.db` |
| `STEZU_HEALTH_TZ` | Time zone for the day keys in the health views | `America/New_York` |

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

**Frist Late Meal (`hall_id` `LM`, D-131).** The Frist Gallery grill counter, where a meal-plan
swipe buys a grill plate, is not in FoodPro (location 15 "The Gallery" has the rest of Frist). Its
items exist only in Agilysys OnDemand, which publishes no nutrition and sits behind DataDome, so
the menu is a static file, `stezu_server/data/frist_late_meal.json`, and every number is an
estimate built from components (USDA FoodData Central or a restaurant equivalent, written in
each item's `basis`). On weekdays `/menu` appends
`{"hall_id": "LM", "hall": "Frist Late Meal", "status": "available", "source": "static", "estimated": true, ...}`
with a "Late Lunch" card (Mon-Fri 14:00-16:00, ids `LM-LL-<slug>`) and a "Late Dinner" card
(Mon-Thu 20:30-22:00, `LM-LD-<slug>`); weekends have no `LM` hall, and university breaks are not
known. The card names make it count for lunch and dinner, never breakfast. It is added after the
FoodPro cache, so a FoodPro failure never hides it. Items carry `estimated: true`, `basis`,
`description` and `keywords` beside the FoodPro fields (`recipe_id` is `null`).

A grill entree served with fries appears three times: the plate "Chicken Tenders with fries"
(serving "1 plate, with fries", `plate: true`, `parts` = the two ids below, values summed), the
entree alone ("Chicken Tenders", "4 tenders (entree only; the fries are a separate item)") and
"French Fries" (one order, the same portion as the side). Search and the menu offer the plate; a
photo scan never sees plates, only entrees and fries, so a plate cannot be counted twice.

To refresh: read the grill menu (tenant 2047, display profile 4880, concept 9461, menu 14323;
Late Meal is profile 4912, concept 10110) in a browser, edit the JSON (an item with fries gets a
`plate`), keep every number > 0 with a `basis`, set `retrieved`, run `server/run_tests.sh` and
restart the server (the file is read once per process).

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
An item whose menu values are estimates (Frist Late Meal) gets 15 points more (30% or 40% base,
at most 65%) and `estimated: true`; the reply has `estimated: true` when any item does. Every
item carries `estimated` (`false` for FoodPro and unlisted items; unlisted ones are `rough`).

### `GET /search?q=…[&date=…][&meal=…][&estimate=true]`

Grouped results, each group with `source`, `status` (`ok`, `error`, `skipped`, `available`)
and `results`:

1. `dining`: fuzzy name matches across all halls for the date (and meal, if given), one
   entry per dish with every hall that serves it. Frist Late Meal items also match on
   "Frist Late Meal grill" ("late meal burger" finds its burgers) and carry `estimated: true`;
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

### `POST /sync`

Stores a batch of Apple Health samples, deletions and Stezu records. Send
`Content-Type: application/json`; the body may be gzipped with `Content-Encoding: gzip`.
**Limits: at most 5,000 items (samples + deleted + records) per request and 24 MiB of JSON
after decompression; more answers 413 and stores nothing.** The app sends about 2,000.

Every value below is synthetic.

```json
{"device_id": "0F6E2B9C-1D4A-4C3B-9E8F-000000000001",
 "batch_id": "5A1C7E3D-2B4F-4A6E-8D9C-000000000042",
 "samples": [
  {"uuid": "3C9A1E52-7B44-4F0A-9D1E-000000000001", "type": "HKQuantityTypeIdentifierHeartRate",
   "start": "2026-10-21T08:00:00-04:00", "end": "2026-10-21T08:00:00-04:00",
   "value": 62, "unit": "count/min", "source_name": "Example Watch", "source_bundle": "com.example.watch",
   "metadata": {"HKMetadataKeyHeartRateMotionContext": 1}},
  {"uuid": "3C9A1E52-7B44-4F0A-9D1E-000000000002", "type": "HKCategoryTypeIdentifierSleepAnalysis",
   "start": "2026-10-21T23:30:00-04:00", "end": "2026-10-22T01:00:00-04:00",
   "value": 4, "unit": null, "source_name": "Example Watch", "source_bundle": "com.example.watch"},
  {"uuid": "3C9A1E52-7B44-4F0A-9D1E-000000000003", "type": "HKWorkoutTypeIdentifier",
   "start": "2026-10-21T17:00:00-04:00", "end": "2026-10-21T18:00:00-04:00",
   "value": null, "unit": null, "source_name": "Stezu", "source_bundle": "com.ik301.stezuhealth",
   "metadata": {"activity_type": 50, "activity_name": "traditionalStrengthTraining", "duration_s": 3600,
                "total_energy_kcal": 250, "total_distance_m": null}}],
 "deleted": [{"uuid": "3C9A1E52-7B44-4F0A-9D1E-0000000000AA", "type": "HKQuantityTypeIdentifierStepCount"}],
 "records": [
  {"kind": "set", "id": "8E2D4C6A-0000-4000-8000-000000000007", "updated_at": "2026-10-21T17:20:00-04:00",
   "deleted": false, "payload": {"session_id": "…", "exercise": "Bench Press", "pounds": 95, "reps": 8}},
  {"kind": "meal", "id": "8E2D4C6A-0000-4000-8000-000000000008", "updated_at": "2026-10-21T19:00:00-04:00",
   "deleted": true, "payload": null}]}
```

Top level:

| Field | Type | Rules |
|---|---|---|
| `device_id` | string, 1–128 | Stable per install (a random UUID kept on the device). |
| `batch_id` | string, 1–128 | Unique per batch; reuse it when retrying the same batch. |
| `samples`, `deleted`, `records` | arrays | Each may be omitted, `null` or empty. |

`samples[]` (HealthKit samples; the HealthKit UUID is the dedupe key):

| Field | Type | Rules |
|---|---|---|
| `uuid` | string, 1–64 | `HKObject.uuid.uuidString`. Compared case-insensitively (stored upper-case). |
| `type` | string, starts with `HK` | The identifier's raw value, e.g. `HKQuantityTypeIdentifierStepCount`. Workouts use `HKWorkoutTypeIdentifier`. |
| `start`, `end` | string | ISO 8601 **with an offset** (`-04:00` or `Z`); `end` ≥ `start`. |
| `value` | number or null | Quantity samples: the value in `unit`. Category samples: the raw `Int` value (sleep: 0 inBed, 1 asleepUnspecified, 2 awake, 3 asleepCore, 4 asleepDeep, 5 asleepREM). Required, except `null` for workouts. Never send 0 for a missing value. |
| `unit` | string or null, ≤ 40 | `HKUnit.unitString`: `count/min`, `ms`, `lb`, `kg`, `%`, `degC`, `count`, `kcal`, … `null` for category samples and workouts. `%` carries HealthKit's fraction: 0.97 means 97%. |
| `source_name`, `source_bundle` | string or null | `sourceRevision.source.name` and `.bundleIdentifier`. |
| `metadata` | object or null | HealthKit metadata with JSON-safe values (dates as ISO strings). Workouts put `activity_type` (`HKWorkoutActivityType` raw value), `activity_name`, `duration_s`, `total_energy_kcal` and `total_distance_m` here (`null` when absent). |

`deleted[]`: `{"uuid": string, "type": string or null}` from `HKDeletedObject`; `type` is
optional but recommended. A deletion may arrive before the sample it deletes; it is kept as a
tombstone, so the sample stays deleted if it arrives (or is replayed) later.

`records[]` (Stezu's own data; `(kind, id)` is the key):

| Field | Type | Rules |
|---|---|---|
| `kind` | string | Lower-case `[a-z][a-z0-9_]*`, ≤ 40. Known kinds: `workout_session`, `set`, `meal`, `weigh_in`, `visit`, `location`, `app_usage`; others are stored too. |
| `id` | string, 1–128 | The app's stable id for the record. |
| `updated_at` | string | ISO 8601 with an offset. The newest version wins; an equal or older `updated_at` is a duplicate and changes nothing, so bump it on every edit. |
| `deleted` | bool | Default `false`. `true` is a tombstone. |
| `payload` | object | The record as the app models it, stored verbatim. May be `null` only when `deleted` is true. |

Answer (200):

```json
{"accepted": 5, "duplicates": 0, "deleted": 1, "rejected": 0, "errors": [],
 "server_time": "2026-10-21T23:10:00.123Z"}
```

Every item lands in exactly one count:

- `accepted`: a new sample, a new record, or a newer version of a record (tombstones included);
- `duplicates`: it changed nothing (a known UUID, an already deleted UUID, a record that is not newer);
- `deleted`: a `deleted` entry that removed a stored sample or recorded a tombstone for an unseen one;
- `rejected`: it failed validation. `errors` lists the first 20 as `"samples[3]: reason"`. The
  rest of the batch is stored. Resending a rejected item fails the same way, so log it and move on.

Replaying a batch is always safe: it returns `accepted: 0` and counts everything as a duplicate.
Within a batch, samples are stored before deletions. A batch of 5,000 samples takes about 0.15 s
on the VM.

Errors (nothing is stored): 400 for a body that is not a JSON object, bad gzip, a missing
`device_id` or `batch_id`, or `samples`/`deleted`/`records` that are not arrays; 401; 413 over
the limits. After a 5xx or a network failure, retry the same batch later.

### `GET /sync/status`

What the server holds, for the Settings row:

```json
{"server_time": "2026-10-21T23:10:01.456Z", "samples_total": 1204, "records_total": 31,
 "types": [{"type": "HKQuantityTypeIdentifierHeartRate", "count": 1200, "deleted": 2,
            "first_start": "2026-07-23T12:00:00.000Z", "last_start": "2026-10-21T21:59:00.000Z"},
           {"type": "HKQuantityTypeIdentifierStepCount", "count": 4, "deleted": 0,
            "first_start": "2026-10-21T12:00:00.000Z", "last_start": "2026-10-21T22:30:00.000Z"}],
 "kinds": [{"kind": "set", "count": 30, "deleted": 1, "last_updated_at": "2026-10-21T21:20:00.000Z"}],
 "devices": [{"device_id": "0F6E2B9C-1D4A-4C3B-9E8F-000000000001",
              "last_batch_at": "2026-10-21T23:10:00.123Z",
              "last_batch_id": "5A1C7E3D-2B4F-4A6E-8D9C-000000000042", "batches": 12}]}
```

`count` excludes deleted items; `deleted` counts tombstones. `first_start` and `last_start` are
the earliest and latest start of a stored sample of that type (`null` when none). `samples_total`
and `records_total` sum the `count`s. `last_batch_at` is when the server last received a batch
from that device (a replay counts). Times the server writes are UTC, fixed width,
`YYYY-MM-DDTHH:MM:SS.mmmZ`.

## Health database (for Hermes)

The file named by `STEZU_HEALTH_DB` (default `~/.local/share/stezu/health.db`), mode 0600, WAL
mode, created when the server starts. Read it read-only:
`sqlite3 -readonly "$STEZU_HEALTH_DB"`, or `sqlite3.connect(f"file:{path}?mode=ro", uri=True)`.

Tables:

- `samples`: `uuid` (key), `type`, `start_ts` and `end_ts` (UTC text), `start_local` and
  `end_local` (wall time in `STEZU_HEALTH_TZ`, no offset), `utc_offset` (the offset the phone
  sent, e.g. `-04:00`), `value`, `unit`, `source_name`, `source_bundle`, `metadata_json`,
  `received_at`, `deleted_at`. A tombstone has `deleted_at` set and may have no times. Index on
  `(type, start_ts)`.
- `records`: `kind`, `id` (key together), `updated_at`, `deleted` (0/1), `payload_json`, `received_at`.
- `batches`: `batch_id` (key), `device_id`, `received_at`, `counts_json`.

Views (recreated on every start). `day` is the local date of a sample's start in
`STEZU_HEALTH_TZ` (default `America/New_York`); changing the zone recomputes the local columns at
the next start. Absent is not zero: a metric or sleep stage with no samples has no row or a
NULL, never 0.

| View | Rows and columns |
|---|---|
| `live_samples` | `samples` without deleted rows, plus `day`. |
| `daily_quantity` | Per `day`, `type`, `unit`: `n`, `min_value`, `mean_value`, `max_value`, `sum_value`, `sources`. |
| `steps_by_source` | Per `day` and source: `steps`, `n`. |
| `daily_steps` | Per `day`: `steps` (the largest single-source total), `steps_raw_sum` (all sources added), `source_count`, `top_source`, `top_bundle`. |
| `sleep_by_source` | Per `night` and source: `asleep_min`, `core_min`, `deep_min`, `rem_min`, `unspecified_min`, `awake_min`, `in_bed_min`, `bedtime`, `wake_time`, `n`. |
| `sleep_nights` | Per `night`: the source with the most asleep minutes, with the same columns, plus `source_count`. |
| `body_mass` | Every weigh-in: `uuid`, `measured_at`, `day`, `value`, `unit`, `kg`, `source_name`, `source_bundle`, `stezu_weighin` (1 when `source_bundle` is `com.ik301.stezuhealth`). |
| `heart_rate_daily`, `resting_hr`, `hrv`, `spo2`, `respiratory_rate`, `temperature` | Per `day`, `type`, `unit`: `n`, `min_value`, `mean_value`, `max_value`, `sources`. Types: HeartRate, RestingHeartRate, HeartRateVariabilitySDNN (ms), OxygenSaturation (a fraction), RespiratoryRate, and BodyTemperature, AppleSleepingWristTemperature, BasalBodyTemperature. |
| `workouts` | HealthKit workouts: `uuid`, `day`, `start_local`, `end_local`, `activity_type`, `activity_name`, `duration_min`, `energy_kcal`, `distance_m`, `source_name`, `source_bundle`. |
| `stezu_records` | `records` without tombstones. |
| `stezu_sets` | One row per live `set` record: `id`, `session_id`, `template_key`, `exercise_key`, `exercise_name`, `pounds` (NULL for bodyweight), `reps`, `logged_at`, `day`, `kind` (e.g. `working`), `updated_at`. |
| `stezu_sessions` | One row per live `workout_session` record: `id`, `started_at`, `ended_at`, `day`, `template_key`, `template_name`, `duration_min`, `n_exercises`, `n_sets`, `total_reps`, `in_health` (1/0), `updated_at`. |
| `stezu_weighins` | One row per live `weigh_in` record: `id`, `measured_at`, `day`, `pounds`, `kg`, `in_health` (1/0), `updated_at`. |
| `stezu_visits` | One row per live `visit` record: `id`, `arrived_at`, `departed_at` (NULL while unknown), `day`, `latitude`, `longitude`, `horizontal_accuracy_m`, `duration_min` (NULL unless both ends are known and departure is not before arrival), `updated_at`. |
| `stezu_locations` | One row per live `location` record: `id`, `at`, `day`, `latitude`, `longitude`, `horizontal_accuracy_m`, `speed_mps`, `updated_at`. |
| `places_daily` | Per `day` with at least one visit or fix: `visits` (visits by their `day`) and `location_fixes`; a count with nothing recorded that day is NULL, not 0. |
| `stezu_app_usage` | One row per live `app_usage` record (an iPhone app-focus interval from the Mac uploader): `id`, `device_name`, `device_model`, `bundle_id`, `app_name`, `started_at`, `ended_at`, `day`, `duration_s` (the payload's when positive, else `ended_at` minus `started_at`, else NULL), `capped` (1/0), `updated_at`. |
| `screen_time_daily` | Per `day` and `device_name` with at least one interval that has a bundle id and a length: `total_min`, `apps` (distinct bundle ids), `top_apps` (JSON array of the five apps with the most minutes, `[{"bundle_id", "minutes"}]`, most first), `intervals`, `capped_intervals` (NULL when no interval says). An interval counts toward the day it started. |
| `stezu_meals` | One row per live `meal` record: `id`, `eaten_at`, `day`, `status`, `edited` (1/0), `in_health` (1/0), `n_items`, `kcal_low`, `kcal_high`, `protein_g_low`, `protein_g_high` (the items' ranges summed), `items` (names, `; `-separated), `updated_at`. |

The record views read `payload_json` with `json_extract` and never fail on an odd payload:
a field that is missing, `null` or of the wrong type is NULL, never 0. `pounds` of 0 or less is
NULL (bodyweight, or a bad value). A record's `day` is the payload's `day` when it is a
`YYYY-MM-DD` string, else the date part of its timestamp as the phone stamped it (its own zone
and offset), so it matches the day the app shows; it is not recomputed in `STEZU_HEALTH_TZ`.
`n_sets` and `total_reps` count `exercises[].sets[]` in the session payload; a session without an
`exercises` array falls back to the live `set` records with its `session_id`, and is NULL when
there are none. A meal's range is NULL when it has no items or any item lacks that range, as in
the app (`FoodRange.total`). Booleans are 1, 0 or NULL. In the place views a latitude outside
-90 to 90, a longitude outside -180 to 180, and a negative accuracy or speed (CoreLocation's
"invalid") are NULL; a speed of 0 is kept. A timestamp whose year is before 1970 or after 2999
(CLVisit's `distantPast` and `distantFuture`) is NULL. A visit's `day` falls back to the date of
`arrived_at`, then `departed_at`.

Record payloads (snake_case, as `MealRecord` in StezuCore's SyncRecord.swift). The views read
these names; the names in brackets are also accepted:

| Kind | Payload fields |
|---|---|
| `set` (S-030) | `id`, `session_id`, `template_key`, `exercise_key`, `exercise_name` [`name`], `pounds` (number, `null` for bodyweight, never 0), `reps`, `logged_at` (ISO 8601 with offset, milliseconds), `kind` (`working`), optional `day`. Undo sends the same id with `deleted: true`. |
| `workout_session` (S-030) | `id`, `template_key`, `template_name` [`template`], `started_at` [`start`], `ended_at` [`end`, `finished_at`], `in_health` [`inHealth`], `exercises`: `[{exercise_key, exercise_name, sets: [set payloads as above]}]`, optional `day`. |
| `weigh_in` (S-031) | `id`, `measured_at`, `pounds`, `in_health` [`inHealth`] (`null` until the Health write was tried), optional `day`. |
| `visit` (S-032) | `id`, `arrived_at` (ISO 8601 with offset, or `null` when unknown), `departed_at` (`null` until the departure is known), `latitude`, `longitude` (degrees, WGS 84), `horizontal_accuracy_m` (metres), `day`. A departure, or any other change, resends the same id with a newer `updated_at`; it replaces the row, never adds one. Send `null` for an unknown end, not `distantPast` or `distantFuture`. |
| `location` (S-032) | `id`, `at` (ISO 8601 with offset), `latitude`, `longitude`, `horizontal_accuracy_m`, `speed_mps` (`null` when CoreLocation reports none, never a negative or 0 for missing), `day`. A significant location change. |
| `app_usage` (Mac uploader, D-081) | `id` (sha256 hex of device id, bundle id and UTC start), `device_name`, `device_model` (e.g. `iPhone15,2`), `bundle_id`, `app_name` (`null`: Biome has only the bundle id), `start`, `end` (ISO 8601 with the Mac's offset, milliseconds), `duration_s` (> 0; at most the cap), `capped` (true when the interval was cut at the uploader's cap, 4 h by default), `day` (local date of `start`). Sent by `mac/screentime/stezu_screentime.py` with batch `device_id` `mac-screentime`; every daily run re-sends the trailing 7 days with a newer `updated_at` (milliseconds), which replaces the row. An interval still open at run time is not sent until it ends. |
| `meal` (S-029) | `id`, `eaten_at`, `day`, `status`, `edited`, `in_health`, `items`: `[{item_id, name, source, halls, serving, servings, confidence, rough, kcal: {low, high}, protein_g: {low, high}}]`. |

A night is keyed by its wake date: a sleep segment belongs to the local date of its end plus
6 hours. A segment ending at 23:30 on the 21st and one ending at 06:40 on the 22nd both belong
to the night of the 22nd; anything ending at 18:00 or later counts toward the next date.

Sources overlap. Apple Health shows merged numbers: where a watch and a phone both counted
steps, it keeps the source higher on the user's priority list for that interval. HealthKit does
not expose that list and the server gets raw samples, so adding every source double counts
(`steps_raw_sum`). `daily_steps.steps` takes the largest single-source total of the day instead;
it reads low on a day when no one device was carried throughout. `sleep_nights` makes the same
choice per night, and `sleep_by_source` keeps every source.

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
