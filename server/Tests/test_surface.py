"""GET /surface/today (D-152). Every note here is synthetic: made-up words, goals and tasks."""

from __future__ import annotations

from datetime import date as Date
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

from stezu_server import app as app_module
from stezu_server import surface
from stezu_server.config import load_settings

VOCAB = """---
tags: [synthetic]
---
# Words
**Florble:** a small sound a kettle makes
**Quibbit:**
- **Zandle:** to tidy a [[Shelf Note|shelf]] in a hurry
**Mopsy:**   \t
**Wexfrond:** a **bright** fern
not a word line
"""
WORDS = [("Florble", "a small sound a kettle makes"), ("Zandle", "to tidy a shelf in a hurry"),
         ("Wexfrond", "a bright fern")]

GOALS = """---
status: synthetic
---
# Goals
Some intro text.
## Later
- Grow a moon garden
## Current focus
- Learn to juggle [[Plum Note]]
  - a sub-item that is ignored

- [x] Finished goal is left out
- [ ] Paint the gate blue
1. Read the cloud atlas
- Fourth goal beyond the cap
## Someday
- Never shown
"""

PLANNER = """# Planner
- [ ] Turn in the ferret essay 📅 2026-03-10 ⏫
- [ ] Future quiz 📅 2026-03-12
- [x] Done thing 📅 2026-03-01
- [-] Cancelled thing 📅 2026-03-01
- [ ] No due date at all
> [!todo] Week 10
> - [ ] FLB 101 · Problem set 4 [due:: 2026-03-11] [course:: FLB 101] [type:: pset]
>> ```dataviewjs
>> - [ ] inside code 📅 2026-03-01
>> ```
  - [ ] Indented overdue 📅 2026-02-28 🔁 every week
- [ ] Bad date 📅 2026-13-40
"""
TODAY = Date(2026, 3, 11)


def write(root: Path, rel: str, text: str) -> None:
    (root / rel).parent.mkdir(parents=True, exist_ok=True)
    (root / rel).write_text(text, encoding="utf-8")


@pytest.fixture
def vault(tmp_path: Path) -> Path:
    root = tmp_path / "vault"
    write(root, "Words.md", VOCAB)
    write(root, "Self/Goals.md", GOALS)
    write(root, "Daily/Planner.md", PLANNER)
    write(root, "Daily/Other.md", "- [ ] Water the cactus 📅 2026-03-11\n")
    return root


@pytest.fixture
def surface_client(make_client, vault: Path):
    def make(**overrides):
        return make_client(**({"vault_dir": vault, "vocab_note": "Words.md", "goal_note": "Self/Goals.md",
                               "task_notes": ("Daily/Planner.md", "Daily/Other.md")} | overrides))
    return make


def at(monkeypatch: pytest.MonkeyPatch, *args: int) -> None:
    """Freeze the server clock at a New York wall time."""
    class Frozen(datetime):
        @classmethod
        def now(cls, tz=None):
            return datetime(*args, tzinfo=ZoneInfo("America/New_York")).astimezone(tz)

    monkeypatch.setattr(app_module, "datetime", Frozen)


def test_word_is_same_all_day_and_changes_daily(surface_client, monkeypatch) -> None:
    client = surface_client()
    seen = []
    for hour, minute in ((0, 1), (12, 0), (23, 59)):
        at(monkeypatch, 2026, 3, 11, hour, minute)
        seen.append(client.get("/surface/today").json())
    assert len({(b["date"], b["word"], b["definition"]) for b in seen}) == 1
    assert seen[0]["date"] == "2026-03-11" and seen[0]["word"] in {w for w, _ in WORDS}
    at(monkeypatch, 2026, 3, 12, 0, 1)
    nxt = client.get("/surface/today").json()
    assert nxt["date"] == "2026-03-12" and nxt["word"] != seen[0]["word"]


def test_word_index_is_days_since_epoch_mod_count() -> None:
    lines = VOCAB.splitlines()
    for offset in range(7):
        day = Date.fromordinal(surface.EPOCH.toordinal() + offset)
        assert surface.word_of_day(lines, day) == WORDS[offset % 3]
    assert surface.word_of_day(lines, Date(2025, 12, 31)) == WORDS[-1]


def test_local_timezone_decides_the_day(surface_client, monkeypatch) -> None:
    at(monkeypatch, 2026, 3, 11, 23, 30)  # already 03-12 in UTC
    ny = surface_client().get("/surface/today").json()
    utc = surface_client(timezone="UTC").get("/surface/today").json()
    assert ny["date"] == "2026-03-11" and utc["date"] == "2026-03-12"
    assert (ny["word"], ny["definition"]) == surface.word_of_day(VOCAB.splitlines(), Date(2026, 3, 11))


def test_empty_definitions_are_skipped() -> None:
    lines = VOCAB.splitlines()
    picked = {surface.word_of_day(lines, Date.fromordinal(TODAY.toordinal() + i))[0] for i in range(30)}
    assert picked == {"Florble", "Zandle", "Wexfrond"}
    assert surface.word_of_day(["**Quibbit:**", "**Mopsy:**  "], TODAY) == (None, None)


def test_goal_is_first_list_under_current_heading() -> None:
    assert surface.goals(GOALS.splitlines()) == ["Learn to juggle Plum Note", "Paint the gate blue",
                                                 "Read the cloud atlas"]


def test_goal_without_current_heading_is_first_top_level_list() -> None:
    note = "---\na: b\n---\n# Goals\nIntro.\n\n- Plant a pear\n- Fix the bike\n\nA paragraph.\n- Later list\n"
    assert surface.goals(note.splitlines()) == ["Plant a pear", "Fix the bike"]
    assert surface.goals(["# Goals", "Just prose."]) is None


def test_tasks_due_today_or_overdue_only(vault: Path) -> None:
    tasks = surface.due_tasks(vault, ("Daily/Planner.md", "Daily/Other.md"), TODAY)
    assert tasks == [
        {"text": "Indented overdue", "due": "2026-02-28", "source": "Daily/Planner.md"},
        {"text": "Turn in the ferret essay", "due": "2026-03-10", "source": "Daily/Planner.md"},
        {"text": "FLB 101 · Problem set 4", "due": "2026-03-11", "source": "Daily/Planner.md"},
        {"text": "Water the cactus", "due": "2026-03-11", "source": "Daily/Other.md"},
    ]


def test_tasks_empty_list_when_nothing_due_null_when_no_note_reads(vault: Path) -> None:
    assert surface.due_tasks(vault, ("Daily/Other.md",), Date(2026, 3, 1)) == []
    assert surface.due_tasks(vault, ("Daily/Missing.md",), TODAY) is None
    assert surface.due_tasks(vault, (), TODAY) is None
    assert surface.due_tasks(vault, ("../outside.md",), TODAY) is None


def test_endpoint_payload_and_cache_header(surface_client, monkeypatch) -> None:
    at(monkeypatch, 2026, 3, 11, 9, 0)
    r = surface_client().get("/surface/today")
    assert r.status_code == 200
    assert r.headers["cache-control"] == "private, max-age=300"
    body = r.json()
    assert list(body) == ["date", "word", "definition", "goal", "tasks"]
    assert body["goal"][0] == "Learn to juggle Plum Note"
    assert [t["text"] for t in body["tasks"]][-1] == "Water the cactus"
    at(monkeypatch, 2026, 3, 11, 23, 58)
    assert surface_client().get("/surface/today").headers["cache-control"] == "private, max-age=120"


def test_missing_files_return_nulls(surface_client, tmp_path: Path, monkeypatch) -> None:
    at(monkeypatch, 2026, 3, 11, 9, 0)
    empty = {"date": "2026-03-11", "word": None, "definition": None, "goal": None, "tasks": None}
    assert surface_client(vault_dir=tmp_path / "no-vault").get("/surface/today").json() == empty
    assert surface_client(vault_dir=None).get("/surface/today").json() == empty
    missing = surface_client(vocab_note="Nope.md", goal_note="Self/Nope.md", task_notes=("Nope.md",))
    assert missing.get("/surface/today").json() == empty


def test_401_without_or_with_wrong_token(surface_client) -> None:
    client = surface_client()
    del client.headers["Authorization"]
    r = client.get("/surface/today")
    assert r.status_code == 401 and r.headers["www-authenticate"] == "Bearer"
    assert "word" not in r.text
    assert client.get("/surface/today", headers={"Authorization": "Bearer wrong"}).status_code == 401


def test_settings_from_env_file(tmp_path: Path, monkeypatch) -> None:
    env = tmp_path / "server.env"
    env.write_text("STEZU_VAULT_DIR=~/some-vault\nSTEZU_SURFACE_GOAL_NOTE=G/Goals.md\n"
                   "STEZU_SURFACE_TASK_NOTES=A.md, B/C.md\nSTEZU_TIMEZONE=UTC\n", encoding="utf-8")
    monkeypatch.setenv("HOME", str(tmp_path))
    s = load_settings(str(env))
    assert s.vault_dir == tmp_path / "some-vault" and s.goal_note == "G/Goals.md"
    assert s.task_notes == ("A.md", "B/C.md") and s.timezone == "UTC"
    assert s.vocab_note == "04-Knowledge/Concepts/Vocabulary.md"
    d = load_settings(str(tmp_path / "absent.env"))
    assert d.vault_dir is None and d.task_notes == ("01-Daily/School Planner.md",)
