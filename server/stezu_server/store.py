"""SQLite JSON cache: menus per date, scans per meal_id and photo hash, barcodes."""

from __future__ import annotations

import json
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any


class Store:
    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self._db = sqlite3.connect(str(path), check_same_thread=False)
        self._lock = threading.Lock()
        with self._lock:
            self._db.execute("PRAGMA journal_mode=WAL")
            self._db.execute(
                "CREATE TABLE IF NOT EXISTS cache"
                " (key TEXT PRIMARY KEY, value TEXT NOT NULL, stored_at REAL NOT NULL)"
            )
            self._db.commit()

    def get(self, key: str, max_age: float | None = None) -> Any | None:
        with self._lock:
            row = self._db.execute("SELECT value, stored_at FROM cache WHERE key = ?", (key,)).fetchone()
        if row is None or (max_age is not None and time.time() - row[1] > max_age):
            return None
        return json.loads(row[0])

    def put(self, key: str, value: Any) -> None:
        with self._lock:
            self._db.execute(
                "INSERT OR REPLACE INTO cache VALUES (?, ?, ?)", (key, json.dumps(value), time.time())
            )
            self._db.commit()
