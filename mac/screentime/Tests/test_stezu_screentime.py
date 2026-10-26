"""Offline tests for the Mac Screen Time uploader, on synthetic data only.

The SEGB files, protobufs and sync.db are built here from the format notes; every device id,
name and bundle id is made up (com.example.*). Nothing here has run against a real Mac's Biome.
Runs on Linux and macOS with the stdlib: `mac/screentime/run_tests.sh`.
"""

from __future__ import annotations

import io
import json
import os
import sqlite3
import stat
import struct
import sys
import tempfile
import time
import unittest
import zlib
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import stezu_screentime as st  # noqa: E402

PHONE = "00000000-0000-4000-8000-0000000000a1"
PAD = "00000000-0000-4000-8000-0000000000a2"
MAC = "00000000-0000-4000-8000-0000000000a3"
BARE = "00000000-0000-4000-8000-0000000000a4"  # an iOS peer whose sync.db row has no model
T0 = datetime(2026, 10, 20, 12, 0, tzinfo=timezone.utc).timestamp()  # 08:00 EDT


def varint(n: int) -> bytes:
    out = b""
    while True:
        b, n = n & 0x7F, n >> 7
        out += bytes([b | (0x80 if n else 0)])
        if not n:
            return out


def pb(bundle: str, gained: bool, t: float, extra: bool = True) -> bytes:
    """An App.InFocus event as proto3 writes it: in_foreground 0 (lost) is left out."""
    b = bundle.encode()
    out = (varint(1 << 3 | 2) + varint(5) + b"swipe") if extra else b""
    out += varint(2 << 3) + varint(1)
    if gained:
        out += varint(3 << 3) + varint(1)
    out += varint(4 << 3 | 1) + struct.pack("<d", t - st.COCOA_EPOCH)
    out += varint(6 << 3 | 2) + varint(len(b)) + b
    if extra:
        out += varint(9 << 3 | 2) + varint(3) + b"1.0" + varint(13 << 3) + varint(1)
        out += varint(15 << 3 | 5) + b"\x01\x02\x03\x04"
    return out


def segb2(entries) -> bytes:
    """entries: (state, unix time, payload); state 4 adds an empty slot, None a zeroed one."""
    body, trailer = b"", b""
    for state, t, payload in entries:
        if state is None:
            trailer += struct.pack("<iid", 0, 0, 0.0)
            continue
        if state != 4:
            body += b"\0" * (-len(body) % 4) + struct.pack("<Ii", zlib.crc32(payload), 0) + payload
        trailer += struct.pack("<iid", len(body), state, t - st.COCOA_EPOCH)
    body += b"\0" * (-len(body) % 4) + b"\0" * 64  # Biome preallocates; zeros sit before the trailer
    return b"SEGB" + struct.pack("<id", len(entries), 0.0) + b"\0" * 16 + body + trailer


def segb1(entries) -> bytes:
    body = b""
    for state, t, payload in entries:
        cf = t - st.COCOA_EPOCH
        body += struct.pack("<iiddIi", len(payload), state, cf, cf, zlib.crc32(payload), 0) + payload
        body += b"\0" * (-(56 + len(body)) % 8)
    return struct.pack("<I", 56 + len(body)) + b"\0" * 48 + b"SEGB" + body


def ev(t: float, bundle: str, gained: bool):
    return (1, t, pb(bundle, gained, t))


class Fixture(unittest.TestCase):
    def setUp(self):
        self._tz = os.environ.get("TZ")
        os.environ["TZ"] = "America/New_York"
        time.tzset()
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.library = self.root / "Library"
        self.remote = self.library / st.STREAM / "remote"
        self.remote.mkdir(parents=True)
        (self.library / st.STREAM / "local").mkdir()
        db = self.library / st.SYNC_DB
        db.parent.mkdir(parents=True)
        with sqlite3.connect(db) as conn:
            conn.execute("CREATE TABLE DevicePeer (device_identifier, ids_device_identifier, me, name, model,"
                         " platform, last_sync_date, protocol_version)")
            conn.executemany("INSERT INTO DevicePeer VALUES (?, 'ids', ?, ?, ?, ?, 0, 5)", [
                (PHONE, 0, "Test iPhone", "iPhone15,2", 2), (PAD, 0, "Test iPad", "iPad13,1", 2),
                (MAC, 1, "Test Mac", "Mac14,2", 4), (BARE, 0, "Test Phone", "", 2)])
        self.config = self.root / "mac-uploader.env"
        self.config.write_text("STEZU_BASE_URL=https://stezu.invalid\nSTEZU_TOKEN=synthetic-token\n")
        self.config.chmod(0o600)
        self.state = self.root / "state.json"
        self.bodies = []

    def tearDown(self):
        if self._tz is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = self._tz
        time.tzset()

    def write(self, device: str, name: str, events, v1: bool = False):
        folder = self.remote / device
        folder.mkdir(exist_ok=True)
        (folder / name).write_bytes(segb1(events) if v1 else segb2(events))

    def post(self, body):
        self.bodies.append(json.loads(json.dumps(body)))
        n = len(body["records"])
        return {"accepted": n, "duplicates": 0, "deleted": 0, "rejected": 0, "errors": []}

    def run_main(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = st.main(["--library", str(self.library), "--config", str(self.config),
                            "--state", str(self.state), *args], post=self.post)
        return code, out.getvalue(), err.getvalue()

    def sent(self, run_from=0):
        return [r for body in self.bodies[run_from:] for r in body["records"]]


class SegbTests(Fixture):
    def test_segb_v2_reads_written_entries_and_skips_deleted_and_empty_slots(self):
        data = segb2([ev(T0, "com.example.one", True), (3, T0 + 1, pb("com.example.gone", True, T0 + 1)),
                      (4, T0 + 2, b""), (None, 0, b""), ev(T0 + 60, "com.example.one", False)])
        entries = st.read_segb(data)
        self.assertEqual([round(t) for t, _ in entries], [round(T0), round(T0 + 60)])
        self.assertEqual([st.parse_in_focus(p)[:2] for _, p in entries],
                         [("com.example.one", True), ("com.example.one", False)])

    def test_segb_v1_reads_written_entries(self):
        data = segb1([ev(T0, "com.example.two", True), (3, T0, pb("com.example.gone", True, T0)),
                      ev(T0 + 5, "com.example.two", False)])
        self.assertEqual([st.parse_in_focus(p)[0] for _, p in st.read_segb(data)], ["com.example.two"] * 2)
        with self.assertRaises(ValueError):
            st.read_segb(b"not a segb file" * 8)

    def test_lost_event_omits_field_3_and_unknown_fields_are_skipped(self):
        bundle, gained, cf = st.parse_in_focus(pb("com.example.one", False, T0))
        self.assertEqual((bundle, gained, round(cf + st.COCOA_EPOCH)), ("com.example.one", False, round(T0)))
        self.assertTrue(st.parse_in_focus(pb("com.example.one", True, T0, extra=False))[1])
        self.assertIsNone(st.parse_in_focus(varint(3 << 3) + varint(1)))  # no bundle id
        with self.assertRaises(ValueError):
            st.parse_in_focus(varint(6 << 3 | 2) + varint(40) + b"short")


class DeviceTests(Fixture):
    def test_only_remote_devices_whose_sync_db_model_is_an_iphone_are_selected(self):
        for device in (PHONE, PAD, BARE, "00000000-0000-4000-8000-0000000000ff"):
            self.write(device, "1", [ev(T0, "com.example.one", True), ev(T0 + 60, "com.example.one", False)])
        devices = st.list_devices(self.library)
        self.assertEqual([d["id"] for d in st.select_devices(devices, [])], [PHONE])
        self.assertEqual([d["id"] for d in st.select_devices(devices, [BARE, "Test iPad"])], [PAD, BARE])
        code, out, _ = self.run_main("--list-devices")
        self.assertEqual(code, 0)
        self.assertIn(f"selected  {PHONE}  name='Test iPhone' model='iPhone15,2'", out)
        self.assertIn("events=2", out)
        self.assertIn(f"{MAC}  name='Test Mac' model='Mac14,2' platform=4 me=1 events=no stream", out)

    def test_no_identifiable_iphone_fails_until_stezu_devices_pins_one(self):
        self.write(BARE, "1", [ev(T0, "com.example.one", True), ev(T0 + 60, "com.example.one", False)])
        code, _, err = self.run_main()
        self.assertEqual(code, 3)
        self.assertIn("--list-devices", err)
        self.assertIn("STEZU_DEVICES", err)
        self.assertEqual(self.bodies, [])
        with self.config.open("a") as f:
            f.write(f"STEZU_DEVICES={BARE}\n")
        code, _, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual(len(self.sent()), 1)


class IntervalTests(Fixture):
    def test_switches_repeats_zero_durations_and_the_cap(self):
        a, b, c = "com.example.one", "com.example.two", "com.example.three"
        events = [(T0, a, True), (T0 + 30, a, True), (T0 + 60, a, False),  # a repeated gain keeps the start
                  (T0 + 100, b, True), (T0 + 160, c, True),  # gaining c ends b without a lost event
                  (T0 + 200, c, False), (T0 + 200, c, False), (T0 + 300, a, False),  # duplicate, stray loss
                  (T0 + 400, b, True), (T0 + 400, b, False),  # zero length: dropped
                  (T0 + 500, a, True), (T0 + 500 + 5 * 3600, a, False)]  # 5 h: capped at 4 h
        closed, current = st.build_intervals(events, 4 * 3600)
        self.assertIsNone(current)
        self.assertEqual([(i[0], i[1] - T0, i[3], i[4]) for i in closed], [
            (a, 0, 60, False), (b, 100, 60, False), (c, 160, 40, False), (a, 500, 4 * 3600, True)])
        self.assertEqual(closed[-1][2] - T0, 500 + 4 * 3600)

    def test_open_interval_is_held_back_then_sent_with_its_real_end(self):
        now = time.time()
        self.write(PHONE, "1", [ev(now - 600, "com.example.one", True), ev(now - 540, "com.example.one", False),
                                ev(now - 300, "com.example.two", True)])  # still in focus at run time
        self.assertEqual(self.run_main()[0], 0)
        first = self.sent()
        self.assertEqual([r["payload"]["bundle_id"] for r in first], ["com.example.one"])
        self.assertEqual(json.loads(self.state.read_text())["last_counts"]["held_open"], 1)
        time.sleep(0.01)
        self.write(PHONE, "2", [ev(now - 120, "com.example.two", False)])
        self.assertEqual(self.run_main()[0], 0)
        second = {r["payload"]["bundle_id"]: r for r in self.sent(run_from=1)}
        self.assertEqual(second["com.example.one"]["id"], first[0]["id"])  # re-sent, same id
        self.assertGreater(second["com.example.one"]["updated_at"], first[0]["updated_at"])
        self.assertEqual(second["com.example.two"]["payload"]["duration_s"], 180)

    def test_late_events_stamped_before_the_last_run_are_still_sent(self):
        now = time.time()
        self.write(PHONE, "1", [ev(now - 3600, "com.example.one", True), ev(now - 3000, "com.example.one", False)])
        self.assertEqual(self.run_main()[0], 0)
        # Events from two days ago reach the Mac only after that run (late, out of order).
        self.write(PHONE, "0", [ev(now - 2 * 86400, "com.example.late", True),
                                ev(now - 2 * 86400 + 900, "com.example.late", False)])
        self.assertEqual(self.run_main()[0], 0)
        self.assertEqual(sorted(r["payload"]["bundle_id"] for r in self.sent(run_from=1)),
                         ["com.example.late", "com.example.one"])

    def test_each_run_resends_the_trailing_week_and_the_first_run_sends_everything(self):
        now = time.time()
        self.write(PHONE, "1", [ev(now - 20 * 86400, "com.example.old", True),
                                ev(now - 20 * 86400 + 60, "com.example.old", False),
                                ev(now - 7.5 * 86400, "com.example.week", True),
                                ev(now - 7.5 * 86400 + 60, "com.example.week", False)])
        self.assertEqual(self.run_main()[0], 0)
        self.assertEqual(len(self.sent()), 2)  # nothing uploaded before: the whole Biome window
        yesterday = datetime.fromtimestamp(now - 86400, timezone.utc).isoformat()
        self.state.write_text(json.dumps({"last_success": yesterday}))
        self.assertEqual(self.run_main()[0], 0)
        self.assertEqual([r["payload"]["bundle_id"] for r in self.sent(run_from=1)], ["com.example.week"])


class PayloadTests(Fixture):
    def test_payload_ids_day_and_millisecond_times(self):
        late = datetime(2026, 10, 21, 3, 30, tzinfo=timezone.utc).timestamp()  # 23:30 EDT on the 20th
        self.write(PHONE, "1", [ev(late, "com.example.one", True), ev(late + 90.25, "com.example.one", False)],
                   v1=True)
        self.assertEqual(self.run_main()[0], 0)
        (body,) = self.bodies
        self.assertEqual(body["device_id"], "mac-screentime")
        (rec,) = body["records"]
        self.assertEqual((rec["kind"], rec["deleted"]), ("app_usage", False))
        self.assertRegex(rec["updated_at"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}\+00:00$")
        self.assertEqual(rec["id"], st.record_id(PHONE, "com.example.one", late))
        self.assertEqual(len(rec["id"]), 64)
        self.assertEqual(rec["payload"], {
            "id": rec["id"], "device_name": "Test iPhone", "device_model": "iPhone15,2",
            "bundle_id": "com.example.one", "app_name": None, "start": "2026-10-20T23:30:00.000-04:00",
            "end": "2026-10-20T23:31:30.250-04:00", "duration_s": 90.25, "capped": False, "day": "2026-10-20"})
        self.assertNotEqual(st.record_id(PAD, "com.example.one", late), rec["id"])

    def test_batches_hold_at_most_2000_records(self):
        now = time.time()
        events = [e for i in range(2500) for e in (ev(now - 86400 + 20 * i, f"com.example.app{i % 7}", True),
                                                   ev(now - 86400 + 20 * i + 10, f"com.example.app{i % 7}", False))]
        self.write(PHONE, "1", events)
        code, out, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual([len(b["records"]) for b in self.bodies], [2000, 500])
        self.assertEqual(len({b["batch_id"] for b in self.bodies}), 2)
        self.assertIn("sent=2500 accepted=2500", out)

    def test_dry_run_prints_minutes_per_day_and_sends_nothing(self):
        self.write(PHONE, "1", [ev(T0, "com.example.one", True), ev(T0 + 600, "com.example.one", False),
                                ev(T0 + 86400, "com.example.two", True), ev(T0 + 86400 + 90, "com.example.two", False),
                                ev(T0 + 86400 + 100, "com.example.one", True)])
        self.config.unlink()  # a dry run needs no server settings
        code, out, _ = self.run_main("--dry-run")
        self.assertEqual(code, 0)
        self.assertEqual(self.bodies, [])
        self.assertFalse(self.state.exists())
        self.assertIn("Test iPhone (iPhone15,2): 5 events, 2 intervals (0 capped), 1 still open", out)
        self.assertIn("2026-10-20  Test iPhone  10.0 min  (1 intervals)", out)
        self.assertIn("2026-10-21  Test iPhone  1.5 min  (1 intervals)", out)


class SetupAndAccessTests(Fixture):
    def test_setup_writes_mode_0600_and_never_echoes_the_token(self):
        self.config.unlink()
        out = io.StringIO()
        with mock.patch("builtins.input", return_value="https://stezu.invalid/"), \
                mock.patch("getpass.getpass", return_value="synthetic-secret"), \
                mock.patch.object(st, "request", side_effect=OSError("offline")), redirect_stdout(out):
            st.main(["--setup", "--config", str(self.config)])
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o600)
        self.assertEqual(self.config.read_text(),
                         "STEZU_BASE_URL=https://stezu.invalid\nSTEZU_TOKEN=synthetic-secret\n")
        self.assertNotIn("synthetic-secret", out.getvalue())
        self.assertEqual(st.load_config(self.config), ("https://stezu.invalid", "synthetic-secret", None))

    def test_access_denied_explains_full_disk_access(self):
        with mock.patch.object(st, "list_devices", side_effect=PermissionError(1, "Operation not permitted")):
            code, _, err = self.run_main("--check-access")
        self.assertEqual(code, 2)
        self.assertIn("FULL DISK ACCESS DENIED", err)
        self.assertIn("Privacy & Security > Full Disk Access", err)
        self.assertIn(st.fda_target(), err)
        code, out, _ = self.run_main("--check-access")
        self.assertEqual((code, out.startswith("stezu-screentime: access ok")), (0, True))


if __name__ == "__main__":
    unittest.main()
