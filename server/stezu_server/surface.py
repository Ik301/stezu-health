"""GET /surface/today: today's word, goal and due tasks, read from the Obsidian vault (D-153).

Every read happens at request time and nothing is kept. A note that is missing or unreadable
gives null; nothing is ever filled in. Rules are documented in server/README.md.
"""

from __future__ import annotations

import logging
import re
from datetime import date as Date
from pathlib import Path
from typing import Any

log = logging.getLogger("stezu.surface")

EPOCH = Date(2026, 1, 1)  # word index = days since EPOCH mod the number of words
MAX_GOALS = 3
WORD = re.compile(r"^\s*(?:[-*+]\s+)?\*\*(.+?):\*\*\s*(.*)$")
HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
TOP_ITEM = re.compile(r"^(?:[-*+]|\d+[.)])\s+(?:\[(.)\]\s+)?(.*)$")
TASK = re.compile(r"^\s*[-*+]\s+\[ \]\s+(.*)$")
DUE = re.compile(r"📅\s*(\d{4}-\d{2}-\d{2})|\[due::\s*(\d{4}-\d{2}-\d{2})\s*\]")
FIELD = re.compile(r"\[[\w-]+::[^\]]*\]")
SIGNIFIER = re.compile("[📅⏳🛫➕✅❌🔁⏫🔼🔽🔺⏬🆔⛔🏁]")
WIKILINK = re.compile(r"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]")


def read_note(vault: Path | None, rel: str | None) -> list[str] | None:
    """The note's lines, or None when the vault or note is unset, missing, outside it or unreadable."""
    if vault is None or not rel:
        return None
    path = (vault / rel).resolve()
    if not path.is_relative_to(vault.resolve()) or not path.is_file():
        return None
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        log.warning("cannot read a vault note: %s", type(exc).__name__)
        return None


def body(lines: list[str]) -> list[str]:
    """Lines after YAML front matter."""
    if lines and lines[0].strip() == "---":
        for i, line in enumerate(lines[1:], 1):
            if line.strip() == "---":
                return lines[i + 1:]
    return lines


def plain(text: str) -> str:
    """Wikilinks to their label, emphasis markers dropped, whitespace collapsed."""
    text = WIKILINK.sub(lambda m: m[2] or m[1], text)
    return " ".join(re.sub(r"\*\*|__|`", "", text).split())


def word_of_day(lines: list[str] | None, today: Date) -> tuple[str | None, str | None]:
    """`**Word:** definition` lines with a non-empty definition, picked by date."""
    words = [(plain(m[1]), plain(m[2])) for m in map(WORD.match, body(lines or [])) if m]
    words = [(w, d) for w, d in words if w and d]
    if not words:
        return None, None
    return words[(today - EPOCH).days % len(words)]


def goals(lines: list[str] | None) -> list[str] | None:
    """The first top-level list under the first heading containing "Current" (any case), or,
    with no such heading, the first top-level list in the note. Completed items are left out."""
    lines = body(lines or [])
    for i, line in enumerate(lines):
        h = HEADING.match(line)
        if h and "current" in h[2].lower():
            level, section = len(h[1]), []
            for rest in lines[i + 1:]:
                nh = HEADING.match(rest)
                if nh and len(nh[1]) <= level:
                    break
                section.append(rest)
            lines = section
            break
    found: list[str] = []
    for line in lines:
        item = TOP_ITEM.match(line)
        if item:
            if (item[1] or " ").lower() != "x" and plain(item[2]):
                found.append(plain(item[2]))
        elif found and line.strip() and not line[0].isspace():
            break  # any other unindented line ends the list; blanks and sub-items do not
    return found[:MAX_GOALS] or None


def due_tasks(vault: Path | None, files: tuple[str, ...], today: Date) -> list[dict[str, Any]] | None:
    """Open `- [ ]` items due today or earlier (`📅 YYYY-MM-DD` or `[due:: YYYY-MM-DD]`), oldest
    first. Callout `>` prefixes are read through; fenced code is skipped. None when no file reads."""
    tasks, read_any = [], False
    for rel in files:
        lines = read_note(vault, rel)
        if lines is None:
            continue
        read_any, fenced = True, False
        for raw in lines:
            line = re.sub(r"^(?:\s*>)+ ?", "", raw)
            if line.lstrip().startswith("```"):
                fenced = not fenced
                continue
            task, due = TASK.match(line), DUE.search(line)
            if fenced or not task or not due:
                continue
            try:
                when = Date.fromisoformat(due[1] or due[2])
            except ValueError:
                continue
            text = plain(SIGNIFIER.split(FIELD.sub("", task[1]))[0])
            if when <= today and text:
                tasks.append({"text": text, "due": when.isoformat(), "source": rel})
    return sorted(tasks, key=lambda t: t["due"]) if read_any else None


def today_payload(vault: Path | None, vocab: str | None, goal: str | None,
                  task_files: tuple[str, ...], today: Date) -> dict[str, Any]:
    word, definition = word_of_day(read_note(vault, vocab), today)
    return {"date": today.isoformat(), "word": word, "definition": definition,
            "goal": goals(read_note(vault, goal)), "tasks": due_tasks(vault, task_files, today)}
