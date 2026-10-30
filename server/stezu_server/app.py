"""HTTP API. Run: uvicorn --factory stezu_server.app:create_app --host <tailnet ip> --port <port>"""

from __future__ import annotations

import hmac
import json
import logging
from datetime import date as Date
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request
from fastapi.concurrency import run_in_threadpool

from . import __version__, barcode, foodpro, latemeal, scan, search
from .config import Settings, load_settings
from .health import HealthDB, TooLarge, gunzip
from .model import AnthropicClient, ModelError
from .net import Http
from .store import Store

log = logging.getLogger("stezu")
MAX_BODY = 9 * 1024 * 1024
MAX_SYNC_BODY = 24 * 1024 * 1024


def create_app(settings: Settings | None = None, http: Any = None, model: Any = None) -> FastAPI:
    settings = settings or load_settings()
    app = FastAPI(title="Stezu food server", version=__version__, docs_url=None, redoc_url=None, openapi_url=None)
    store, http = Store(settings.db_path), http or Http()
    model = model or AnthropicClient(settings, http)
    health_db = HealthDB(settings.health_db or settings.db_path.with_name("health.db"), settings.health_tz)
    if not settings.tokens:
        log.warning("no device tokens configured: every authenticated request will get 401")

    def require_token(request: Request) -> None:
        scheme, _, token = request.headers.get("authorization", "").partition(" ")
        ok = scheme.lower() == "bearer" and any(
            hmac.compare_digest(token.strip().encode(), t.encode()) for t in settings.tokens
        )
        if not ok:
            raise HTTPException(401, "missing or invalid bearer token", headers={"WWW-Authenticate": "Bearer"})

    def today() -> str:
        return datetime.now(ZoneInfo(settings.timezone)).date().isoformat()

    def day(value: str | None) -> str:
        try:
            return Date.fromisoformat(value).isoformat() if value else today()
        except ValueError:
            raise HTTPException(400, "date must be YYYY-MM-DD") from None

    def menu_for(d: str, refresh: bool = False) -> dict[str, Any]:
        return latemeal.add_to(foodpro.get_menu(store, http, d, today(), refresh), d)

    api = APIRouter(dependencies=[Depends(require_token)])

    @app.get("/health")
    def health() -> dict[str, Any]:
        return {"status": "ok", "version": __version__}

    @api.get("/menu")
    def menu(date: str | None = None, refresh: bool = False) -> dict[str, Any]:
        return menu_for(day(date), refresh)

    @api.post("/scan")
    async def scan_photo(request: Request) -> dict[str, Any]:
        if int(request.headers.get("content-length") or 0) > MAX_BODY:
            raise HTTPException(413, "request too large")
        image = None
        if request.headers.get("content-type", "").startswith("multipart/form-data"):
            form = await request.form()
            fields: Any = {k: v for k, v in form.items() if isinstance(v, str)}
            upload = form.get("photo")
            if upload is None or isinstance(upload, str):
                raise HTTPException(400, "a multipart scan needs a photo file field")
            image = await upload.read()
        else:
            try:
                fields = await request.json()
            except ValueError:
                raise HTTPException(400, "body must be JSON or multipart/form-data") from None
            if not isinstance(fields, dict):
                raise HTTPException(400, "body must be a JSON object")
        try:
            req = scan.parse_request(fields) | {"date": day(fields.get("date"))}
            image, sha = scan.decode_image(image, fields.get("image_base64"), fields.get("photo_sha256"))
        except scan.ScanError as exc:
            raise HTTPException(400, str(exc)) from None
        return await run_in_threadpool(scan_sync, req, image, sha)

    def scan_sync(req: dict[str, Any], image: bytes, sha: str) -> dict[str, Any]:
        items = foodpro.meal_items(menu_for(req["date"]), req["meal"]) if req["mode"] == "dining" else []
        if not items:
            req = req | {"mode": "open_world"}  # no hall serves this meal: estimate open-world
        try:
            return scan.run_scan(store, model, items, req, image, sha)
        except ModelError as exc:
            raise HTTPException(502, str(exc)) from None

    @api.get("/search")
    def search_food(q: str, date: str | None = None, meal: str | None = None,
                    estimate: bool = False) -> dict[str, Any]:
        q = q.strip()
        if not 0 < len(q) <= 120:
            raise HTTPException(400, "q must be 1 to 120 characters")
        d = day(date)
        items = foodpro.meal_items(menu_for(d), meal)
        groups = search.run_search(store, http, model, settings.usda_key, q, items, estimate)
        return {"q": q, "date": d, "meal": meal, "groups": groups}

    @api.get("/barcode/{gtin}")
    def lookup_barcode(gtin: str) -> dict[str, Any]:
        try:
            return barcode.lookup(store, http, gtin)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from None
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(502, f"Open Food Facts lookup failed: {exc}") from None

    @api.post("/sync")
    async def sync(request: Request) -> dict[str, Any]:
        if int(request.headers.get("content-length") or 0) > MAX_SYNC_BODY:
            raise HTTPException(413, "request too large")
        raw = await request.body()
        try:
            if request.headers.get("content-encoding", "").lower() == "gzip":
                raw = gunzip(raw, MAX_SYNC_BODY)
            body = json.loads(raw)
            if not isinstance(body, dict):
                raise ValueError("body must be a JSON object")
            return await run_in_threadpool(health_db.ingest, body)
        except TooLarge as exc:
            raise HTTPException(413, str(exc)) from None
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from None

    @api.get("/sync/status")
    def sync_status() -> dict[str, Any]:
        return health_db.status()

    app.include_router(api)
    return app
