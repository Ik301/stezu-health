#!/usr/bin/env python3
"""Send the iPhone's Screen Time app-focus intervals from a Mac to the Stezu server.

With Screen Time's "Share Across Devices" on, macOS keeps the iPhone's app-focus events in Biome
(~/Library/Biome/streams/restricted/App.InFocus/remote/<device id>/). This script reads them,
turns them into per-app focus intervals and posts them to POST /sync as `app_usage` records.
Stdlib only, Python 3.9+ (the Xcode Command Line Tools python). See README.md.

Format sources, read for the layout only; this reader is written from those notes:
- ccl-segb (CCL Forensics, MIT) and Cellebrite's "Understanding and decoding the newest iOS SEGB
  format": the SEGB v1 and v2 containers.
- iLEAPP scripts/artifacts/biomeInfocus.py (MIT): App.InFocus protobuf fields 3, 4 and 6, the
  local/remote folders, tombstone folders.
- nichtlegacy/screentime (MIT): DevicePeer in Biome/sync/sync.db, platform codes, and which binary
  needs Full Disk Access under launchd.
- ActivityWatch/aw-import-screentime (no license file, so nothing is copied): its field notes.
"""

from __future__ import annotations

import argparse
import getpass
import gzip
import hashlib
import json
import os
import sqlite3
import ssl
import struct
import sys
import urllib.error
import urllib.request
import uuid
from collections import defaultdict
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path

STREAM = Path("Biome/streams/restricted/App.InFocus")
SYNC_DB = Path("Biome/sync/sync.db")
CONFIG = Path.home() / ".config/stezu/mac-uploader.env"
STATE = Path.home() / "Library/Application Support/Stezu/screentime-state.json"
COCOA_EPOCH = 978307200.0  # 2001-01-01T00:00:00Z in Unix seconds
WRITTEN, DELETED = 1, 3  # SEGB entry states; 4 is an empty slot
BATCH = 2000
UPLOADER_ID = "mac-screentime"  # the /sync device_id of this uploader


class AccessDenied(Exception):
    pass


# ---- SEGB container -------------------------------------------------------------------------


def read_segb(data: bytes) -> list:
    """Written entries of a SEGB v1 or v2 file, as (entry time in Unix seconds, payload bytes)."""
    if data[:4] == b"SEGB":
        return _segb2(data)
    if len(data) >= 56 and data[52:56] == b"SEGB":
        return _segb1(data)
    raise ValueError("not a SEGB file")


def _segb2(data: bytes) -> list:
    # 32-byte header (magic, entry count, creation time, padding); records from offset 32, each an
    # 8-byte header (crc32, unknown) then the payload, 4-byte aligned; a trailer of 16-byte entries
    # (end offset relative to 32, state, time) closes the file.
    (count,) = struct.unpack_from("<i", data, 4)
    trailer = len(data) - 16 * count
    if count < 0 or trailer < 32:
        raise ValueError("bad SEGB v2 entry count")
    states: dict = defaultdict(list)
    for i in range(count):
        end, state, ts = struct.unpack_from("<iid", data, trailer + 16 * i)
        if state in (WRITTEN, DELETED) and end > 0:
            states[end].append((state, ts))
    out, prev = [], 0
    for end in sorted(states):
        start, stop = 32 + prev + (-prev % 4), 32 + end
        if stop - start < 8 or stop > trailer:
            continue  # a stale entry inside data already read, or past the data area
        prev = end
        seen = states[end]
        if all(s == WRITTEN for s, _ in seen):  # an entry written and later deleted shares its end
            out.append((seen[0][1] + COCOA_EPOCH, data[start + 8 : stop]))
    return out


def _segb1(data: bytes) -> list:
    # 56-byte header (end of data at 0, magic at 52); records of a 32-byte header (length, state,
    # two times, crc32, unknown) then the payload, 8-byte aligned.
    end_data = min(struct.unpack_from("<I", data, 0)[0], len(data))
    pos, out = 56, []
    while pos + 32 <= end_data:
        length, state, ts1, _ts2, _crc, _unk = struct.unpack_from("<iiddIi", data, pos)
        if length <= 0 or pos + 32 + length > len(data):
            break
        if state == WRITTEN:
            out.append((ts1 + COCOA_EPOCH, data[pos + 32 : pos + 32 + length]))
        pos += 32 + length
        pos += -pos % 8
    return out


# ---- App.InFocus protobuf -------------------------------------------------------------------


def _varint(buf: bytes, i: int) -> tuple:
    value, shift = 0, 0
    while True:
        if i >= len(buf) or shift > 63:
            raise ValueError("bad varint")
        b = buf[i]
        value |= (b & 0x7F) << shift
        i, shift = i + 1, shift + 7
        if not b & 0x80:
            return value, i


def parse_in_focus(buf: bytes):
    """(bundle id, gained focus, CFAbsoluteTime or None) from one event, or None without a bundle.
    Fields: 3 in_foreground (1 gained, 0 lost; proto3 omits a 0), 4 time (double), 6 bundle id."""
    fields, i = {}, 0
    while i < len(buf):
        key, i = _varint(buf, i)
        num, wire = key >> 3, key & 7
        if wire == 0:
            val, i = _varint(buf, i)
        elif wire in (1, 5):
            size = 8 if wire == 1 else 4
            val, i = buf[i : i + size], i + size
        elif wire == 2:
            size, i = _varint(buf, i)
            val, i = buf[i : i + size], i + size
        else:
            raise ValueError(f"unsupported wire type {wire}")
        if i > len(buf):
            raise ValueError("truncated field")
        fields.setdefault(num, (wire, val))
    bundle = fields.get(6)
    if not bundle or bundle[0] != 2 or not bundle[1]:
        return None
    fg, when = fields.get(3, (0, 0)), fields.get(4)
    cf = struct.unpack("<d", when[1])[0] if when and when[0] == 1 else None
    return bundle[1].decode("utf-8"), fg[0] == 0 and fg[1] == 1, cf


# ---- Devices and events ---------------------------------------------------------------------


def _rows(db: Path, sql: str) -> list:
    """Rows as dicts from an Apple database, read-only (immutable: never touch its -wal file)."""
    if not db.exists():
        return []
    uri = db.absolute().as_uri() + "?mode=ro&immutable=1"
    try:
        with closing(sqlite3.connect(uri, uri=True)) as conn:
            conn.row_factory = sqlite3.Row
            return [dict(zip(r.keys(), r)) for r in conn.execute(sql)]
    except sqlite3.Error as exc:
        if "authoriz" in str(exc) or "unable to open" in str(exc):
            raise AccessDenied(f"{db}: {exc}") from None
        return []


def list_devices(library: Path) -> list:
    """Peers from sync.db plus every remote App.InFocus folder, with name, model and platform."""
    remote = library / STREAM / "remote"
    streams = {p.name for p in remote.iterdir() if p.is_dir() and not p.name.startswith(".")} if remote.is_dir() else set()
    peers = {r.get("device_identifier"): r for r in _rows(library / SYNC_DB, "SELECT * FROM DevicePeer")}
    devices = []
    for did in sorted(d for d in set(peers) | streams if d):
        p = peers.get(did, {})
        devices.append({"id": did, "name": p.get("name") or None, "model": p.get("model") or None,
                        "platform": p.get("platform"), "me": bool(p.get("me")), "stream": did in streams})
    return devices


def select_devices(devices: list, pinned: list) -> list:
    """Pinned ids or names (STEZU_DEVICES, --device), else the remote devices whose sync.db model is
    an iPhone. A device without a model is never guessed to be one."""
    remote = [d for d in devices if d["stream"] and not d["me"]]
    if pinned:
        return [d for d in remote if d["id"] in pinned or (d["name"] or "") in pinned]
    return [d for d in remote if str(d["model"] or "").startswith("iPhone")]


def read_events(folder: Path, stats: dict) -> list:
    """(Unix time, bundle id, gained) for every written event in one stream folder."""
    events = []
    files = sorted((p for p in folder.iterdir() if p.is_file() and not p.name.startswith(".")),
                   key=lambda p: (len(p.name), p.name))  # segment files are numbered
    for path in files:
        try:
            entries = read_segb(path.read_bytes())
        except (ValueError, struct.error):
            stats["bad_files"] += 1
            continue
        for entry_time, payload in entries:
            try:
                event = parse_in_focus(payload)
            except (ValueError, struct.error, UnicodeDecodeError):
                event = None
            if event is None:
                stats["bad_records"] += 1
                continue
            bundle, gained, cf = event
            t = cf + COCOA_EPOCH if cf is not None and 1e8 < cf < 2e9 else entry_time
            events.append((t, bundle, gained))
    return events


# ---- Intervals and records ------------------------------------------------------------------


def build_intervals(events: list, cap_s: float) -> tuple:
    """Closed intervals (bundle, start, end, duration_s, capped) and the still-open one, if any.
    An iPhone shows one app at a time, so an app gaining focus also ends the open one."""
    raw, current = [], None
    # At one instant a gain goes first: an app cannot lose focus before it had it.
    for t, bundle, gained in sorted(set(events), key=lambda e: (e[0], not e[2], e[1])):
        if gained:
            if current and current[0] == bundle:
                continue  # a repeated gain keeps the first start
            if current:
                raw.append((current[0], current[1], t))
            current = (bundle, t)
        elif current and current[0] == bundle:
            raw.append((bundle, current[1], t))
            current = None
    closed = []
    for bundle, start, end in raw:
        duration = end - start
        if duration <= 0:
            continue
        capped = duration > cap_s
        if capped:
            end, duration = start + cap_s, cap_s
        closed.append((bundle, start, end, duration, capped))
    return closed, current


def iso(t: float, tz=None) -> str:
    """ISO 8601 with milliseconds and an offset; the Mac's local zone unless tz is given."""
    dt = datetime.fromtimestamp(t, timezone.utc)
    return (dt if tz else dt.astimezone()).isoformat(timespec="milliseconds")


def record_id(device_id: str, bundle: str, start: float) -> str:
    return hashlib.sha256(f"{device_id}|{bundle}|{iso(start, timezone.utc)}".encode()).hexdigest()


def to_record(device: dict, interval: tuple, updated_at: str) -> dict:
    bundle, start, end, duration, capped = interval
    rid = record_id(device["id"], bundle, start)
    start_local = iso(start)
    return {"kind": "app_usage", "id": rid, "updated_at": updated_at, "deleted": False,
            "payload": {"id": rid, "device_name": device["name"], "device_model": device["model"],
                        "bundle_id": bundle, "app_name": None, "start": start_local, "end": iso(end),
                        "duration_s": round(duration, 3), "capped": capped, "day": start_local[:10]}}


# ---- Config, state, server ------------------------------------------------------------------


def read_env(path: Path) -> dict:
    """KEY=VALUE lines of the env file ({} when it is missing). Never executed as shell."""
    if not path.exists():
        return {}
    if path.stat().st_mode & 0o077:
        print(f"stezu-screentime: warning: {path} is readable by others; chmod 600 it", file=sys.stderr)
    values = {}
    for line in path.read_text().splitlines():
        key, sep, value = line.strip().partition("=")
        if sep and not key.startswith("#"):
            values[key.strip()] = value.strip().strip("'\"")
    return values


def load_config(path: Path) -> tuple:
    values = read_env(path)
    if not values:
        raise SystemExit(f"stezu-screentime: no config at {path}; run with --setup first")
    url, token = values.get("STEZU_BASE_URL"), values.get("STEZU_TOKEN")
    if not url or not token:
        raise SystemExit(f"stezu-screentime: {path} needs STEZU_BASE_URL and STEZU_TOKEN; run --setup")
    return url.rstrip("/"), token, values.get("STEZU_CA_FILE") or None


def request(url: str, token, body=None, ca_file=None) -> dict:
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    data = None
    if body is not None:
        data = gzip.compress(json.dumps(body).encode())
        headers.update({"Content-Type": "application/json", "Content-Encoding": "gzip"})
    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    with urllib.request.urlopen(req, timeout=60, context=ssl.create_default_context(cafile=ca_file)) as resp:
        return json.load(resp)


def setup(path: Path) -> None:
    url = input("Stezu server base URL (the one in the iPhone app's Settings): ").strip().rstrip("/")
    if not url.startswith(("https://", "http://")):
        raise SystemExit("stezu-screentime: the URL must start with https://")
    token = getpass.getpass("Device token (input is hidden): ").strip()
    if not token:
        raise SystemExit("stezu-screentime: no token given")
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(f"STEZU_BASE_URL={url}\nSTEZU_TOKEN={token}\n")
    os.chmod(path, 0o600)
    print(f"Saved {path} (mode 0600).")
    try:
        status = request(url + "/sync/status", token)
        print(f"Server reached: records_total {status.get('records_total')}.")
    except (urllib.error.URLError, OSError, ValueError) as exc:
        print(f"Could not reach {url}/sync/status yet: {exc}")


def load_state(path: Path) -> dict:
    """Diagnostics only (last run, counts); the window below is the only thing it moves."""
    try:
        state = json.loads(path.read_text())
    except (OSError, ValueError):
        state = {}
    return state if isinstance(state, dict) else {}


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=1))
    os.replace(tmp, path)


def fda_target() -> str:
    """The binary that needs Full Disk Access: a framework python re-execs into Python.app."""
    app = Path(sys.base_prefix) / "Resources/Python.app/Contents/MacOS/Python"
    return str(app) if app.exists() else os.path.realpath(sys.executable)


FDA_HELP = """stezu-screentime: FULL DISK ACCESS DENIED ({detail}).
Grant it to the binary that opens the files:
  {exe}
System Settings > Privacy & Security > Full Disk Access > +, press Cmd+Shift+G, paste that path,
Open, and make sure its switch is on. Run from Terminal, Terminal needs the grant instead."""


# ---- Main -----------------------------------------------------------------------------------


def collect(library: Path, devices: list, include_local: bool, cap_s: float) -> tuple:
    """Per device: (device, closed intervals, open interval, event count); plus parse stats."""
    stats = {"bad_files": 0, "bad_records": 0}
    sources = [(d, library / STREAM / "remote" / d["id"]) for d in devices]
    if include_local:
        me = next((d for d in list_devices(library) if d["me"]), None)
        local = me or {"id": "local", "name": "This Mac", "model": "Mac", "platform": None}
        sources.append((local, library / STREAM / "local"))
    out = []
    for device, folder in sources:
        events = read_events(folder, stats) if folder.is_dir() else []
        closed, current = build_intervals(events, cap_s)
        out.append((device, closed, current, len(events)))
    return out, stats


def main(argv=None, post=None) -> int:
    ap = argparse.ArgumentParser(description="Upload iPhone Screen Time from this Mac to Stezu.")
    ap.add_argument("--setup", action="store_true", help="save the server URL and token, then exit")
    ap.add_argument("--list-devices", action="store_true", help="print the devices in sync.db, then exit")
    ap.add_argument("--check-access", action="store_true", help="test Full Disk Access, then exit")
    ap.add_argument("--dry-run", action="store_true", help="print a summary; send nothing")
    ap.add_argument("--device", action="append", default=[], help="device id or name; overrides STEZU_DEVICES")
    ap.add_argument("--include-local", action="store_true", help="also send this Mac's own stream")
    ap.add_argument("--cap-hours", type=float, default=4.0, help="longest interval kept (default 4)")
    ap.add_argument("--days", type=float, default=7.0, help="re-send this many trailing days (default 7)")
    ap.add_argument("--full", action="store_true", help="send everything Biome still holds (about 4 weeks)")
    ap.add_argument("--library", type=Path, default=Path.home() / "Library", help=argparse.SUPPRESS)
    ap.add_argument("--config", type=Path, default=CONFIG, help=argparse.SUPPRESS)
    ap.add_argument("--state", type=Path, default=STATE, help=argparse.SUPPRESS)
    args = ap.parse_args(argv)
    if args.setup:
        setup(args.config)
        return 0
    try:
        (args.library / STREAM).stat()
        if (args.library / STREAM / "remote").is_dir():
            list((args.library / STREAM / "remote").iterdir())
        devices = list_devices(args.library)
    except (PermissionError, AccessDenied) as exc:
        print(FDA_HELP.format(detail=exc, exe=fda_target()), file=sys.stderr)
        return 2
    except FileNotFoundError:
        print(f"stezu-screentime: no {args.library / STREAM}; is Screen Time on?", file=sys.stderr)
        return 3
    if args.check_access:
        print(f"stezu-screentime: access ok ({fda_target()})")
        return 0
    pinned = args.device or [d.strip() for d in read_env(args.config).get("STEZU_DEVICES", "").split(",") if d.strip()]
    selected = select_devices(devices, pinned)
    if args.list_devices:
        stats = {"bad_files": 0, "bad_records": 0}
        for d in devices:
            folder = args.library / STREAM / "remote" / d["id"]
            n = len(read_events(folder, stats)) if d["stream"] else 0
            mark = "selected" if d in selected else "-"
            print(f"{mark:9} {d['id']}  name={d['name']!r} model={d['model']!r} platform={d['platform']}"
                  f" me={int(d['me'])} events={n if d['stream'] else 'no stream'}")
        return 0
    if not selected:
        why = f"none of STEZU_DEVICES/--device {pinned} has a remote stream" if pinned else (
            "no remote device has an iPhone model in sync.db")
        print(f"stezu-screentime: {why}. Run --list-devices, then pin the iPhone's id in"
              f" {args.config} as STEZU_DEVICES=<id>[,<id>]. Nothing was sent.", file=sys.stderr)
        return 3
    try:
        per_device, stats = collect(args.library, selected, args.include_local, args.cap_hours * 3600)
    except (PermissionError, AccessDenied) as exc:
        print(FDA_HELP.format(detail=exc, exe=fda_target()), file=sys.stderr)
        return 2
    state = load_state(args.state)
    now_ts = datetime.now(timezone.utc).timestamp()
    now = iso(now_ts, timezone.utc)
    floor = window_start(state, now_ts, args.days, args.full)
    # Every run re-sends the trailing window, because the iPhone's events reach the Mac late and out
    # of order. Ids are stable and updated_at is newer, so the server keeps one row per interval.
    # Intervals still open at run time are held back until a later run sees them end.
    pending = sorted(((iv[1], to_record(device, iv, now)) for device, closed, _cur, _n in per_device
                      for iv in closed if iv[1] >= floor), key=lambda p: p[0])
    if args.dry_run:
        print_summary(per_device, stats, len(pending), floor)
        return 0
    url, token, ca_file = load_config(args.config)
    send = post or (lambda body: request(url + "/sync", token, body, ca_file))
    totals = {"accepted": 0, "duplicates": 0, "rejected": 0}
    state.update(last_run=now, last_run_ok=False)
    for i in range(0, len(pending), BATCH):
        body = {"device_id": UPLOADER_ID, "batch_id": str(uuid.uuid4()),
                "records": [p[1] for p in pending[i : i + BATCH]]}
        try:
            answer = send(body)
        except (urllib.error.URLError, OSError, ValueError) as exc:
            print(f"stezu-screentime: upload failed after {i} of {len(pending)} records: {exc}", file=sys.stderr)
            save_state(args.state, state)
            return 4
        for key in totals:
            totals[key] += int(answer.get(key) or 0)
        if answer.get("errors"):
            print(f"stezu-screentime: server rejected: {answer['errors'][:5]}", file=sys.stderr)
    held = sum(1 for _d, _c, current, _n in per_device if current)
    state.update(last_run_ok=True, last_success=now, last_counts=dict(
        totals, sent=len(pending), held_open=held, devices=len(per_device), window_from=iso(floor, timezone.utc)
        if floor > 0 else None, **stats))
    save_state(args.state, state)
    print(f"{now} stezu-screentime: ok devices={len(per_device)} sent={len(pending)}"
          f" accepted={totals['accepted']} duplicates={totals['duplicates']} rejected={totals['rejected']}"
          f" held_open={held} bad_files={stats['bad_files']} bad_records={stats['bad_records']}")
    return 0


def window_start(state: dict, now_ts: float, days: float, full: bool) -> float:
    """Start of the re-send window: the trailing `days`, reaching further back when the last good
    run is older than that (the Mac was off), and everything before the first good run."""
    if full or not state.get("last_success"):
        return -1.0
    try:
        last = datetime.fromisoformat(state["last_success"]).timestamp()
    except (TypeError, ValueError):
        return -1.0
    return min(now_ts, last) - days * 86400


def print_summary(per_device: list, stats: dict, new: int, floor: float) -> None:
    print("Devices:")
    days: dict = defaultdict(lambda: [0.0, 0])
    total = 0
    for device, closed, current, n in per_device:
        capped = sum(1 for iv in closed if iv[4])
        print(f"  {device['name'] or device['id']} ({device['model'] or 'model unknown'}): {n} events,"
              f" {len(closed)} intervals ({capped} capped){', 1 still open' if current else ''}")
        total += len(closed)
        for iv in closed:
            cell = days[(iso(iv[1])[:10], device["name"] or device["id"])]
            cell[0] += iv[3] / 60
            cell[1] += 1
    since = "everything (no successful run yet)" if floor <= 0 else f"starts from {iso(floor)[:16]}"
    print(f"Intervals: {total}; a run now would send {new}: {since}."
          f" Unreadable: {stats['bad_files']} files, {stats['bad_records']} records.")
    print("Minutes per day (local date of each start):")
    for (day, name), (minutes, n) in sorted(days.items()):
        print(f"  {day}  {name}  {minutes:.1f} min  ({n} intervals)")
    print("Dry run: nothing was sent.")


if __name__ == "__main__":
    sys.exit(main())
