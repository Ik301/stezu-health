"""Outbound HTTP with the stdlib. Tests swap Http for a fake and block sockets."""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Any

USER_AGENT = "Mozilla/5.0 (compatible; StezuHealth-server/0.1; personal food logger)"


class HttpError(Exception):
    def __init__(self, status: int, body: str = "") -> None:
        super().__init__(f"HTTP {status}")
        self.status = status
        self.body = body


class Http:
    def _send(self, req: urllib.request.Request, timeout: float) -> str:
        req.add_header("User-Agent", USER_AGENT)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as exc:
            raise HttpError(exc.code, exc.read().decode("utf-8", "replace")[:2000]) from exc

    def get_text(self, url: str, timeout: float = 20.0) -> str:
        return self._send(urllib.request.Request(url), timeout)

    def get_json(self, url: str, timeout: float = 20.0) -> Any:
        return json.loads(self.get_text(url, timeout))

    def post_json(self, url: str, payload: Any, headers: dict[str, str], timeout: float = 90.0) -> Any:
        data = json.dumps(payload).encode()
        req = urllib.request.Request(url, data=data, headers={"content-type": "application/json", **headers})
        return json.loads(self._send(req, timeout))
