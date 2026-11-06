"""Settings from an env file kept outside the repo (default ~/.config/stezu/server.env)."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_ENV_FILE = "~/.config/stezu/server.env"


def read_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if path.is_file():
        for raw in path.read_text(encoding="utf-8").splitlines():
            key, sep, value = raw.strip().partition("=")
            if sep and key and not key.startswith("#"):
                values[key.strip()] = value.strip().strip("\"'")
    return values


@dataclass(frozen=True)
class Settings:
    tokens: frozenset[str]
    db_path: Path
    anthropic_base_url: str = "https://api.anthropic.com"
    anthropic_api_key: str | None = None
    anthropic_key_file: Path | None = None
    model: str = "claude-sonnet-4-6"
    temperature: float | None = 0.0
    usda_key: str | None = None
    timezone: str = "America/New_York"
    health_db: Path | None = None  # None: health.db next to db_path
    health_tz: str = "America/New_York"
    vault_dir: Path | None = None  # None: /surface/today answers nulls
    vocab_note: str = "04-Knowledge/Concepts/Vocabulary.md"
    goal_note: str = "03-Self/Goals/Goals.md"
    task_notes: tuple[str, ...] = ("01-Daily/School Planner.md",)

    def api_key(self) -> str | None:
        """Read at call time, so a rotated key file needs no restart."""
        if self.anthropic_api_key:
            return self.anthropic_api_key
        if self.anthropic_key_file and self.anthropic_key_file.is_file():
            return self.anthropic_key_file.read_text(encoding="utf-8").strip() or None
        return None


def load_settings(env_file: str | None = None) -> Settings:
    path = Path(env_file or os.environ.get("STEZU_ENV_FILE", DEFAULT_ENV_FILE)).expanduser()
    env = read_env_file(path) | {k: v for k, v in os.environ.items() if k.startswith("STEZU_")}
    temperature = env.get("STEZU_MODEL_TEMPERATURE", "0").strip().lower()
    key_file = env.get("STEZU_ANTHROPIC_KEY_FILE")
    vault = env.get("STEZU_VAULT_DIR")
    task_notes = env.get("STEZU_SURFACE_TASK_NOTES")
    return Settings(
        tokens=frozenset(t.strip() for t in env.get("STEZU_TOKENS", "").split(",") if t.strip()),
        db_path=Path(env.get("STEZU_DB", "~/.local/share/stezu/server.sqlite3")).expanduser(),
        anthropic_base_url=env.get("STEZU_ANTHROPIC_BASE_URL", Settings.anthropic_base_url).rstrip("/"),
        anthropic_api_key=env.get("STEZU_ANTHROPIC_API_KEY") or None,
        anthropic_key_file=Path(key_file).expanduser() if key_file else None,
        model=env.get("STEZU_MODEL", Settings.model),
        temperature=None if temperature in ("", "none") else float(temperature),
        usda_key=env.get("STEZU_USDA_KEY") or None,
        health_db=Path(env.get("STEZU_HEALTH_DB", "~/.local/share/stezu/health.db")).expanduser(),
        health_tz=env.get("STEZU_HEALTH_TZ", Settings.health_tz),
        timezone=env.get("STEZU_TIMEZONE", Settings.timezone),
        vault_dir=Path(vault).expanduser() if vault else None,
        vocab_note=env.get("STEZU_SURFACE_VOCAB_NOTE", Settings.vocab_note),
        goal_note=env.get("STEZU_SURFACE_GOAL_NOTE", Settings.goal_note),
        task_notes=Settings.task_notes if task_notes is None else
        tuple(p.strip() for p in task_notes.split(",") if p.strip()),
    )
