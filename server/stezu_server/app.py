"""HTTP API. Run: uvicorn --factory stezu_server.app:create_app --host <tailnet ip> --port <port>"""

from __future__ import annotations

import hmac
import logging
from typing import Any

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request

from . import __version__, barcode
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

    api = APIRouter(dependencies=[Depends(require_token)])

    @app.get("/health")
    def health() -> dict[str, Any]:
        return {"status": "ok", "version": __version__}

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
