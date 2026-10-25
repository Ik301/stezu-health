"""Shared fakes. Every test runs with sockets blocked: no network, ever."""

from __future__ import annotations

import json
import socket
import sys
from pathlib import Path
from typing import Any

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi.testclient import TestClient  # noqa: E402

from stezu_server.app import create_app  # noqa: E402
from stezu_server.config import Settings  # noqa: E402
from stezu_server.net import HttpError  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"
TOKEN = "test-token-not-a-secret"


def fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


@pytest.fixture(autouse=True)
def no_network(monkeypatch: pytest.MonkeyPatch) -> None:
    def refuse(*args: Any, **kwargs: Any) -> None:
        raise RuntimeError("tests must not touch the network")

    monkeypatch.setattr(socket.socket, "connect", refuse)
    monkeypatch.setattr(socket, "create_connection", refuse)


class FakeHttp:
    """Answers by URL substring, first match wins; unknown URLs fail loudly."""

    def __init__(self) -> None:
        self.routes: list[tuple[str, Any]] = []
        self.calls: list[str] = []
        self.posts: list[dict[str, Any]] = []
        self.post_replies: list[Any] = []

    def add(self, needle: str, reply: Any) -> FakeHttp:
        self.routes.append((needle, reply))
        return self

    def get_text(self, url: str, timeout: float = 20.0) -> str:
        self.calls.append(url)
        for needle, reply in self.routes:
            if needle in url:
                if isinstance(reply, Exception):
                    raise reply
                return reply if isinstance(reply, str) else json.dumps(reply)
        raise HttpError(599, f"no fake route for {url}")

    def get_json(self, url: str, timeout: float = 20.0) -> Any:
        return json.loads(self.get_text(url, timeout))

    def post_json(self, url: str, payload: Any, headers: dict[str, str], timeout: float = 90.0) -> Any:
        self.posts.append({"url": url, "payload": json.loads(json.dumps(payload)), "headers": headers})
        reply = self.post_replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return reply


def foodpro_http(halls: tuple[str, ...] = ("03",)) -> FakeHttp:
    """The saved Forbes page for the given halls; every other hall shows No Data Available."""
    http = FakeHttp()
    for hall in halls:
        http.add(f"locationNum={hall}&", fixture("foodpro_forbes.html"))
    return http.add("menuDetails.asp", fixture("foodpro_nodata.html"))


@pytest.fixture
def settings(tmp_path: Path) -> Settings:
    return Settings(tokens=frozenset({TOKEN}), db_path=tmp_path / "test.sqlite3")


@pytest.fixture
def make_client(settings: Settings):
    def make(http: Any = None, model: Any = None, **overrides: Any) -> TestClient:
        cfg = Settings(**{**settings.__dict__, **overrides})
        client = TestClient(create_app(cfg, http=http or FakeHttp(), model=model))
        client.headers["Authorization"] = f"Bearer {TOKEN}"
        return client

    return make
