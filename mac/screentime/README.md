# Screen Time from the Mac (iPhone app focus to Stezu)

`stezu_screentime.py` reads the iPhone's app-focus events that macOS keeps when Screen Time's
**Share Across Devices** is on, turns them into per-app focus intervals, and posts them to the Stezu
server's `POST /sync` as `app_usage` records. It needs no paid Apple Developer Program and no app
change: the Mac already holds the data (D-078, decision D-081, research note 11).

Status: built and tested on Linux with synthetic SEGB files and a synthetic sync.db only. Nothing
here has run on a Mac yet. Other tools confirm the Biome layout on macOS 26.1 and 27; on 26.6.2 it is
assumed to be the same, unverified.

## What it collects

One record per closed focus interval of an app on the iPhone: device name and model, bundle id
(`com.example.app`), start, end, duration in seconds, whether it was capped, and the local day of
the start. Nothing else: no app content, window titles, URLs, notifications or pickups. `app_name`
is null (Biome stores only the bundle id). The Mac's own stream is off by default because
ActivityWatch covers the Mac; `--include-local` adds it.

Source: `~/Library/Biome/streams/restricted/App.InFocus/remote/<device id>/` (SEGB files of small
protobuf events: bundle id, gained or lost focus, time), with the device list in
`~/Library/Biome/sync/sync.db` (table `DevicePeer`). **Biome keeps about 4 weeks**, so a Mac that
stays off longer than that loses the oldest days.

Intervals: an iPhone shows one app at a time, so an app's interval ends when it loses focus or when
another app gains it. Zero or negative lengths are dropped. An interval longer than 4 hours
(`--cap-hours`) is cut to 4 hours and sent with `capped: true`. An app still in focus when the
script runs is held back and sent by a later run, once it has ended.

## Set up (on the Mac)

1. On the iPhone and the Mac: Settings > Screen Time > Share Across Devices on, same Apple Account.
2. The Command Line Tools python: `xcode-select -p` prints a path, else `xcode-select --install`.
3. A device token for the Mac: on the VM, add a new token to `STEZU_TOKENS` in
   `~/.config/stezu/server.env` (`python3 -c "import secrets; print(secrets.token_urlsafe(32))"`)
   and restart the server. The iPhone's token works too, but a separate one can be revoked alone.
4. From a clone of this repo:

       python3 mac/screentime/stezu_screentime.py --list-devices
       python3 mac/screentime/stezu_screentime.py --dry-run
       mac/screentime/install.sh

   `--list-devices` and `--dry-run` run under Terminal's Full Disk Access. `install.sh` copies the
   script to `~/Library/Application Support/Stezu/`, asks for the server URL (the same https base URL
   as the iPhone app) and the token (input hidden) if `~/.config/stezu/mac-uploader.env` does not
   exist yet, prints the interpreter that needs Full Disk Access, opens that settings pane, loads the
   agent, and waits for its first run to read Biome and upload.

The settings file `~/.config/stezu/mac-uploader.env` (mode 0600, never in the repo):

    STEZU_BASE_URL=https://<the server, as in the app>
    STEZU_TOKEN=<device token>
    # optional:
    STEZU_DEVICES=<device id>[,<device id>]
    STEZU_CA_FILE=<CA bundle, only if the server's certificate is not trusted by default>

`python3 stezu_screentime.py --setup` rewrites the URL and token.

## Which devices

By default only remote devices whose `DevicePeer.model` in sync.db starts with `iPhone` are sent.
A device without a model there is never guessed to be an iPhone. If none qualifies, the run sends
nothing and exits 3 with a message: run `--list-devices` (every device with its id, name, model and
event count) and pin the iPhone in the settings file with `STEZU_DEVICES=<id>`. `--device <id or
name>` overrides it for one run. Device ids stay on the Mac and the server; never paste them into
the repo or an issue.

## Full Disk Access

macOS checks the binary that opens the files. `/usr/bin/python3` is only a shim: it starts the
Command Line Tools python, a framework build that re-execs
`.../Python3.framework/Versions/3.x/Resources/Python.app/Contents/MacOS/Python`. So the agent runs
that binary directly, and that is the file to grant. `install.sh` prints the exact path on your Mac
(it is the `Python.app/Contents/MacOS/Python` inside `sys.base_prefix`, or the real path of
`sys.executable` for other pythons). Steps:

1. System Settings > Privacy & Security > Full Disk Access.
2. Click +, press Cmd+Shift+G, paste the path, Return, Open. If the picker will not select the file,
   paste the `Python.app` folder that contains it.
3. Make sure its switch is on.

Terminal's grant covers runs typed into Terminal, not the agent. A Command Line Tools update can move
the interpreter (a new `Versions/3.x`): the agent then fails to start (`launchctl print` shows the
last exit code and no new log line appears), or logs `FULL DISK ACCESS DENIED` with the new path.
Rerun `install.sh` and grant the path it prints. `PYTHON=/path/to/python3 mac/screentime/install.sh` picks
another interpreter.

## Schedule

The agent (`~/Library/LaunchAgents/com.ik301.stezu.screentime.plist`) runs **daily at 8 p.m.**
(20:00 local time) and once when it is loaded (login, install). launchd runs a missed 8 p.m. run when
the Mac wakes.

Every run re-sends the trailing 7 days (counted from the previous successful run, so a Mac that was
off for a while catches up), because the iPhone's events reach the Mac late and out of order. Each
interval keeps its id (a hash of device, bundle id and start) and gets a newer `updated_at`, and the
server keeps one row per id, so re-sending is harmless. The first run sends everything Biome holds.
`--days N` changes the window; `--full` sends everything. The state file
(`~/Library/Application Support/Stezu/screentime-state.json`) holds only the last run, whether it
worked, and its counts.

Because 8 p.m. is before the day ends, **a day is complete on the server after the next evening's
run**: today's late usage, and anything the iPhone syncs late, arrive the following day.

To change the time, edit `Hour` and `Minute` under `StartCalendarInterval` in
`com.ik301.stezu.screentime.plist` here and rerun `install.sh`, or edit the installed copy and reload
it: `launchctl bootout gui/$(id -u)/com.ik301.stezu.screentime` then
`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ik301.stezu.screentime.plist`.

## Check that it works

    tail -n 5 ~/Library/Logs/Stezu/stezu-screentime.log ~/Library/Logs/Stezu/stezu-screentime.err.log
    launchctl print gui/$(id -u)/com.ik301.stezu.screentime | grep -E 'state|last exit'
    launchctl kickstart -k gui/$(id -u)/com.ik301.stezu.screentime     # run it now, as launchd does
    cat ~/Library/Application\ Support/Stezu/screentime-state.json

A good run logs one line: `... stezu-screentime: ok devices=1 sent=N accepted=N duplicates=0
rejected=0 held_open=0 bad_files=0 bad_records=0`. Running the script by hand
(`python3 mac/screentime/stezu_screentime.py`) does the same upload immediately. On the VM,
`select day, device_name, total_min, apps from screen_time_daily order by day desc limit 7` shows the
result (server/README.md, views `stezu_app_usage` and `screen_time_daily`).

Exit codes: 0 ok, 2 no Full Disk Access, 3 no Biome stream or no iPhone identified, 4 upload failed
(nothing is lost: the next run re-sends the window).

## Record format

`kind: app_usage`, `id` = sha256 hex of `<device id>|<bundle id>|<start in UTC>`, `updated_at` =
the run's time (UTC, milliseconds). Payload (snake_case): `id`, `device_name`, `device_model`,
`bundle_id`, `app_name` (null), `start`, `end` (ISO 8601 with the Mac's offset, milliseconds),
`duration_s`, `capped`, `day` (local date of `start`). Batches hold at most 2,000 records; the
batch's `device_id` is `mac-screentime`.

## Tests

    mac/screentime/run_tests.sh        # stdlib unittest, Linux or macOS, Python 3.9+

They build SEGB v1 and v2 files, App.InFocus protobufs and a sync.db in a temp folder, with made-up
devices and `com.example.*` bundle ids, and cover parsing, device selection, intervals, capping, ids,
the payload, batching, the trailing re-send, held-back open intervals, `--setup` and the Full Disk
Access message. `scripts/gate-linux.sh` runs them as G6.

## Uninstall

    mac/screentime/uninstall.sh           # unload the agent and remove its plist
    mac/screentime/uninstall.sh --purge   # also the script copy, state, logs and settings file

Then remove the interpreter from Full Disk Access by hand.

## Sources and licenses

The SEGB reader and protobuf decoder are written here from published format notes; no code was
copied.

- [ccl-segb](https://github.com/cclgroupltd/ccl-segb) (CCL Forensics, MIT) and Cellebrite's
  "Understanding and decoding the newest iOS SEGB format": the SEGB v1 and v2 layouts.
- [iLEAPP](https://github.com/abrignoni/iLEAPP) `scripts/artifacts/biomeInfocus.py` (MIT): the
  App.InFocus fields (3 in focus, 4 time, 6 bundle id), the local and remote folders, tombstones.
- [nichtlegacy/screentime](https://github.com/nichtlegacy/screentime) (MIT): `DevicePeer` in sync.db,
  that Biome keeps about four weeks, and that Full Disk Access goes to the resolved interpreter.
- [ActivityWatch/aw-import-screentime](https://github.com/ActivityWatch/aw-import-screentime) (no
  license file, so read only): its notes on the same protobuf fields.
