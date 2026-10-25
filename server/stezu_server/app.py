"""HTTP API. Run: uvicorn --factory stezu_server.app:create_app --host <tailnet ip> --port <port>"""

from __future__ import annotations

import hmac
import logging
from datetime import date as Date
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request

from . import __version__, barcode, foodpro
from .config import Settings, load_settings
from .net import Http
from .store import Store

log = logging.getLogger("stezu")


def create_app(settings: Settings | None = None, http: Any = None, model: Any = None) -> FastAPI:
    settings = settings or load_settings()
    app = FastAPI(title="Stezu food server", version=__version__, docs_url=None, redoc_url=None, openapi_url=None)
    store, http = Store(settings.db_path), http or Http()
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
        return foodpro.get_menu(store, http, d, today(), refresh)

    api = APIRouter(dependencies=[Depends(require_token)])

    @app.get("/health")
    def health() -> dict[str, Any]:
        return {"status": "ok", "version": __version__}

    @api.get("/menu")
    def menu(date: str | None = None, refresh: bool = False) -> dict[str, Any]:
        return menu_for(day(date), refresh)

    @api.get("/barcode/{gtin}")
    def lookup_barcode(gtin: str) -> dict[str, Any]:
        try:
            return barcode.lookup(store, http, gtin)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from None
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(502, f"Open Food Facts lookup failed: {exc}") from None

    app.include_router(api)
    return app
