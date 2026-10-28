#!/bin/bash
# Rebuilds Ingest (the StezuHealth app) from origin/main and installs it on the iPhone over Wi-Fi,
# so the free Personal Team's 7-day signing never runs out (D-104). macOS only; bash 3.2.
# launchd (com.ik301.stezu.autoinstall) runs the copy that install.sh puts in
# ~/Library/Application Support/Stezu/autoinstall/, never the one in a clone.
#
#   stezu_autoinstall.sh             install when main moved or the last install is 5+ days old
#   stezu_autoinstall.sh --force     install now
#   stezu_autoinstall.sh --dry-run   decide and find the iPhone, print the plan, build nothing
#   stezu_autoinstall.sh --status    last install, days until the 7-day expiry, iPhone reachability
#
# Exit codes: 0 installed, skipped, or iPhone not reachable (the next hourly run retries);
# 1 failed (a notification says why; logs in ~/Library/Logs/Stezu/autoinstall/); 2 usage or setup.
#
# Settings (~/.config/stezu/autoinstall.env, KEY=value lines, never in the repo):
#   STEZU_LOCAL_XCCONFIG=<working clone>/Config/Local.xcconfig   written by install.sh
#   STEZU_DEVICE_ID=<UDID or CoreDevice identifier>              optional: pin one iPhone
set -u
set -o pipefail

SUPPORT="$HOME/Library/Application Support/Stezu/autoinstall"
CLONE="$SUPPORT/stezu-health"
DERIVED="$SUPPORT/DerivedData"
STATE="$SUPPORT/state"
FAILED_BUILD="$SUPPORT/last-build-failure"
WARNED="$SUPPORT/last-expiry-warning"
LOCK="$SUPPORT/.lock"
LOG_DIR="$HOME/Library/Logs/Stezu/autoinstall"
SUMMARY_LOG="$LOG_DIR/autoinstall.log"
CONFIG="$HOME/.config/stezu/autoinstall.env"

# From project.yml: the app scheme and target, its product, the embedded Live Activity extension.
SCHEME=StezuHealth
PRODUCT=StezuHealth.app
EXTENSION=RestActivity.appex
BUNDLE_IDS="com.ik301.stezuhealth com.ik301.stezuhealth.RestActivity"
RENEW_AFTER_DAYS=5 # a free team's profile lasts 7 days
KEEP_RUN_LOGS=10
DAY=86400

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

MODE=run
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --dry-run) MODE=dry ;;
    --status) MODE=status ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "stezu-autoinstall: unknown option '$arg'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$SUPPORT" "$LOG_DIR"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/stezu-autoinstall.XXXXXX")" || exit 2
HAVE_LOCK=0
cleanup() {
  rm -rf "$TMP"
  if [ "$HAVE_LOCK" = 1 ]; then rm -rf "$LOCK"; fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------------------------
# Helpers

RUN_LOG=""
stamp() { date '+%Y-%m-%d %H:%M:%S'; }

# Detail line: stdout and the run log.
say() {
  echo "stezu-autoinstall: $*"
  if [ -n "$RUN_LOG" ]; then echo "$(stamp) $*" >>"$RUN_LOG"; fi
}

# The one line a run leaves in autoinstall.log (and on stdout).
summary() {
  echo "stezu-autoinstall: $*"
  echo "$(stamp) $*" >>"$SUMMARY_LOG"
  if [ -n "$RUN_LOG" ]; then echo "$(stamp) $*" >>"$RUN_LOG"; fi
  if [ $(($(wc -l <"$SUMMARY_LOG"))) -gt 2000 ]; then
    tail -n 1000 "$SUMMARY_LOG" >"$TMP/summary" && mv "$TMP/summary" "$SUMMARY_LOG"
  fi
}

# A macOS notification. The text goes in as an argument, so quotes in it cannot break the script.
notify() {
  osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Stezu autoinstall"' \
    -e 'end run' "$1" >/dev/null 2>&1 || true
}

prune_logs() {
  ls -1 "$LOG_DIR" 2>/dev/null | grep -E '^run-[0-9-]+\.log$' | sort -r | tail -n +"$((KEEP_RUN_LOGS + 1))" |
    while read -r old; do rm -f "$LOG_DIR/$old"; done
}

fail() {
  summary "FAILED: $1"
  notify "Ingest install failed: $1"
  prune_logs
  exit 1
}

# Setup problems: in a launchd run they notify like any failure; by hand they just print.
setup_error() {
  if [ "$MODE" = run ]; then fail "$1"; fi
  echo "stezu-autoinstall: $1" >&2
  exit 2
}

# KEY=value from a file; the last one wins. Never sourced, so the file cannot run code.
kv_get() {
  [ -f "$1" ] || return 0
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//p" "$1" | tail -n 1 |
    sed -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

is_number() {
  case "${1:-}" in '' | *[!0-9]*) return 1 ;; esac
  return 0
}

# origin/main as a full commit id. (A failed rev-parse without --verify prints its argument.)
main_sha() {
  local sha
  sha="$(git -C "$CLONE" rev-parse --verify --quiet 'origin/main^{commit}')" || return 1
  case "$sha" in '' | *[!0-9a-f]*) return 1 ;; esac
  [ "${#sha}" -ge 40 ] || return 1
  echo "$sha"
}

fmt_time() {
  python3 -c 'import sys, time; print(time.strftime("%Y-%m-%d %H:%M", time.localtime(int(sys.argv[1]))))' "$1"
}

# "6 d 23 h" from seconds.
fmt_span() {
  local s="$1"
  echo "$((s / DAY)) d $(((s % DAY) / 3600)) h"
}

take_lock() {
  if mkdir "$LOCK" 2>/dev/null; then
    echo $$ >"$LOCK/pid"
    HAVE_LOCK=1
    return 0
  fi
  local other
  other="$(cat "$LOCK/pid" 2>/dev/null)"
  if is_number "$other" && kill -0 "$other" 2>/dev/null; then
    return 1
  fi
  rm -rf "$LOCK"
  mkdir "$LOCK" 2>/dev/null || return 1
  echo $$ >"$LOCK/pid"
  HAVE_LOCK=1
}

# Python helpers (stdlib). Read with read -d '' rather than $(cat <<...), which bash 3.2 misparses.
IFS= read -r -d '' PY_DEVICES <<'PY'
# Picks the iPhone from `xcrun devicectl list devices --json-output` (jsonVersion 2 and later).
# Shape, as also parsed by Flutter (core_devices.dart), Expo (devicectl.ts) and KeepAlive:
#   {"info": {"outcome": "success", "jsonVersion": N, ...},
#    "result": {"devices": [{"identifier": <CoreDevice id>,
#      "connectionProperties": {"pairingState": "paired", "transportType": "localNetwork"|"wired",
#                               "tunnelState": "disconnected"|"connected"|"unavailable", ...},
#      "deviceProperties": {"name": ..., "osVersionNumber": ..., "developerModeStatus": ...},
#      "hardwareProperties": {"udid": ..., "platform": "iOS", "deviceType": "iPhone",
#                             "reality": "physical", "marketingName": ...}}]}}
# "unavailable" (or no tunnelState) means CoreDevice cannot see the phone right now.
# Prints "udid<TAB>name<TAB>transport<TAB>iOS version". Exit 3: not reachable; 4: JSON shape;
# 5: several reachable iPhones and none pinned; 6: reachable but Developer Mode is off.
import json, sys

path, pin = sys.argv[1], sys.argv[2].strip().lower()


def die(code, message):
    print(message, file=sys.stderr)
    sys.exit(code)


try:
    with open(path) as f:
        data = json.load(f)
except (OSError, ValueError) as error:
    die(4, "devicectl wrote no readable JSON (%s)" % error)
info = data.get("info") if isinstance(data, dict) else None
info = info if isinstance(info, dict) else {}
result = data.get("result") if isinstance(data, dict) else None
devices = result.get("devices") if isinstance(result, dict) else None
if not isinstance(devices, list):
    die(4, "devicectl JSON has no result.devices list (jsonVersion %s, outcome %s); its format "
        "changed, so update find_device in stezu_autoinstall.sh"
        % (info.get("jsonVersion"), info.get("outcome")))
if info.get("outcome") not in (None, "success"):
    die(4, "devicectl list devices reported outcome %s" % info.get("outcome"))

phones, shaped = [], 0
for d in devices:
    if not isinstance(d, dict):
        continue
    conn, hw = d.get("connectionProperties"), d.get("hardwareProperties")
    props = d.get("deviceProperties") if isinstance(d.get("deviceProperties"), dict) else {}
    if not isinstance(conn, dict) or not isinstance(hw, dict):
        continue
    shaped += 1
    # Xcode 27 omits `reality` for physical devices; simulators also show transport sameMachine.
    if hw.get("reality") == "simulated" or conn.get("transportType") == "sameMachine":
        continue
    if hw.get("platform") != "iOS":
        continue
    if not str(hw.get("deviceType") or hw.get("marketingName") or "").startswith("iPhone"):
        continue
    transport, tunnel = conn.get("transportType"), conn.get("tunnelState") or "unavailable"
    paired = conn.get("pairingState") == "paired"
    phones.append({
        "udid": str(hw.get("udid") or ""),
        "identifier": str(d.get("identifier") or ""),
        "name": str(props.get("name") or hw.get("marketingName") or "iPhone"),
        "os": str(props.get("osVersionNumber") or "?"),
        "transport": str(transport),
        "paired": paired,
        "reachable": paired and tunnel != "unavailable" and transport in ("wired", "localNetwork"),
        "developer_mode": props.get("developerModeStatus"),
        "why": "not paired" if not paired else "tunnel %s, transport %s" % (tunnel, transport),
    })
if devices and not shaped:
    die(4, "none of the %d devices in the devicectl JSON has connectionProperties and "
        "hardwareProperties; its format changed, so update find_device in stezu_autoinstall.sh"
        % len(devices))

if pin:
    matches = [p for p in phones if pin in (p["udid"].lower(), p["identifier"].lower())]
    if not matches:
        die(3, "the pinned iPhone (STEZU_DEVICE_ID) is not among the %d iPhones devicectl lists"
            % len(phones))
    phone = matches[0]
    if not phone["reachable"]:
        die(3, "%s (pinned): %s" % (phone["name"], phone["why"]))
else:
    paired = [p for p in phones if p["paired"]]
    if not paired:
        die(3, "no paired iPhone (pair it once in Xcode: toolbar device menu > Manage Devices..., which opens Device Hub)")
    reachable = [p for p in paired if p["reachable"]]
    if not reachable:
        die(3, "; ".join("%s: %s" % (p["name"], p["why"]) for p in paired))
    if len(reachable) > 1:
        die(5, "%d paired iPhones are reachable (%s); pin one with STEZU_DEVICE_ID=<udid> in "
            "~/.config/stezu/autoinstall.env" % (len(reachable),
                                                 ", ".join(p["name"] for p in reachable)))
    phone = reachable[0]
if not phone["udid"]:
    die(4, "devicectl lists %s without hardwareProperties.udid" % phone["name"])
if phone["developer_mode"] not in (None, "enabled"):
    die(6, "Developer Mode is %s on %s (Settings > Privacy & Security > Developer Mode)"
        % (phone["developer_mode"], phone["name"]))
print("\t".join([phone["udid"], phone["name"], phone["transport"], phone["os"]]))
PY

IFS= read -r -d '' PY_PROFILES <<'PY'
# expiry <app>: the ExpirationDate (epoch) of the profile embedded in a built .app, or nothing.
# clear <bundle id>...: deletes Xcode's cached profiles for exactly these bundle ids, so the next
# -allowProvisioningUpdates build gets a fresh 7-day profile instead of reusing a half-used one
# (the approach KeepAlive, github.com/oli-zr/keepalive, takes). Wildcards and other apps stay.
import calendar, os, plistlib, subprocess, sys


def decode(path):
    try:
        out = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True,
                             check=True).stdout
        return plistlib.loads(out)
    except (OSError, subprocess.CalledProcessError, ValueError, plistlib.InvalidFileException):
        return None


if sys.argv[1] == "expiry":
    profile = decode(os.path.join(sys.argv[2], "embedded.mobileprovision"))
    expires = profile.get("ExpirationDate") if isinstance(profile, dict) else None
    if expires is not None:
        print(calendar.timegm(expires.utctimetuple()))
elif sys.argv[1] == "clear":
    ids, removed = set(sys.argv[2:]), []
    library = os.path.expanduser("~/Library")
    for folder in ("Developer/Xcode/UserData/Provisioning Profiles",
                   "MobileDevice/Provisioning Profiles"):
        folder = os.path.join(library, folder)
        names = sorted(os.listdir(folder)) if os.path.isdir(folder) else []
        for name in names:
            if not name.endswith((".mobileprovision", ".provisionprofile")):
                continue
            path = os.path.join(folder, name)
            profile = decode(path)
            entitlements = profile.get("Entitlements") if isinstance(profile, dict) else None
            app_id = entitlements.get("application-identifier") if isinstance(entitlements, dict) else None
            if isinstance(app_id, str) and "." in app_id and app_id.split(".", 1)[1] in ids:
                os.remove(path)
                removed.append(name)
    print(len(removed))
PY

# Sets DEV_UDID, DEV_NAME, DEV_TRANSPORT, DEV_OS; or DEV_ERROR with return 3 (not reachable),
# 4 (devicectl failed or its JSON changed), 5 (several iPhones) or 6 (Developer Mode off).
find_device() {
  local json="$TMP/devices.json" out rc pin
  DEV_ERROR=""
  rm -f "$json"
  if ! xcrun devicectl list devices --json-output "$json" >"$TMP/devicectl.out" 2>&1; then
    DEV_ERROR="xcrun devicectl list devices failed: $(grep -v '^[[:space:]]*$' "$TMP/devicectl.out" | tail -n 1)"
    return 4
  fi
  pin="${STEZU_DEVICE_ID:-$(kv_get "$CONFIG" STEZU_DEVICE_ID)}"
  out="$(python3 -c "$PY_DEVICES" "$json" "$pin" 2>"$TMP/devices.err")"
  rc=$?
  if [ "$rc" != 0 ]; then
    DEV_ERROR="$(tr '\n' ' ' <"$TMP/devices.err" | sed 's/ *$//')"
    return "$rc"
  fi
  DEV_UDID="$(printf '%s\n' "$out" | cut -f 1)"
  DEV_NAME="$(printf '%s\n' "$out" | cut -f 2)"
  DEV_TRANSPORT="$(printf '%s\n' "$out" | cut -f 3)"
  DEV_OS="$(printf '%s\n' "$out" | cut -f 4)"
  return 0
}

# When the phone stays out of reach and the signing is about to lapse, say so once a day.
warn_if_expiring() {
  local last expires today
  last="$(kv_get "$STATE" LAST_INSTALL_EPOCH)"
  expires="$(kv_get "$STATE" PROFILE_EXPIRES_EPOCH)"
  is_number "$last" || return 0
  is_number "$expires" || expires=$((last + 7 * DAY))
  today="$(date +%Y-%m-%d)"
  if [ $((expires - NOW)) -lt $((DAY * 3 / 2)) ] && [ "$(cat "$WARNED" 2>/dev/null)" != "$today" ]; then
    echo "$today" >"$WARNED"
    notify "Ingest signing expires $(fmt_time "$expires"); the iPhone has not been reachable"
  fi
}

# Sets REASON (why to install) or leaves it empty and sets SKIP_WHY.
decide() {
  local last_sha last_epoch last_day expires age
  last_sha="$(kv_get "$STATE" LAST_SHA)"
  last_epoch="$(kv_get "$STATE" LAST_INSTALL_EPOCH)"
  last_day="$(kv_get "$STATE" LAST_INSTALL_DAY)"
  expires="$(kv_get "$STATE" PROFILE_EXPIRES_EPOCH)"
  REASON=""
  SKIP_WHY=""
  if [ "$FORCE" = 1 ]; then
    REASON="forced"
  elif [ -z "$last_sha" ] || ! is_number "$last_epoch"; then
    REASON="first install"
  elif [ "$last_sha" != "$TARGET" ]; then
    REASON="main moved from ${last_sha:0:7} to ${TARGET:0:7}"
  else
    age=$((NOW - last_epoch))
    if [ "$age" -ge $((RENEW_AFTER_DAYS * DAY)) ]; then
      REASON="the last install is $((age / DAY)) days old"
    elif is_number "$expires" && [ $((expires - NOW)) -lt $((2 * DAY)) ] &&
      [ "$last_day" != "$(date +%Y-%m-%d)" ]; then
      REASON="the installed signing expires $(fmt_time "$expires")"
    else
      SKIP_WHY="up to date: ${TARGET:0:7} installed $(fmt_time "$last_epoch"), $((age / DAY)) days ago"
    fi
  fi
  # A commit that failed to build today is not rebuilt every hour; a new commit, tomorrow or
  # --force tries again.
  if [ -n "$REASON" ] && [ "$FORCE" = 0 ] &&
    [ "$(cat "$FAILED_BUILD" 2>/dev/null)" = "$TARGET $(date +%Y-%m-%d)" ]; then
    SKIP_WHY="${TARGET:0:7} already failed to build today; waiting for a new commit (or --force)"
    REASON=""
  fi
}

show_status() {
  local last_sha last_epoch expires source left installed
  last_sha="$(kv_get "$STATE" LAST_SHA)"
  last_epoch="$(kv_get "$STATE" LAST_INSTALL_EPOCH)"
  expires="$(kv_get "$STATE" PROFILE_EXPIRES_EPOCH)"
  if [ -n "$last_sha" ] && is_number "$last_epoch"; then
    echo "Last install:   ${last_sha:0:7} at $(fmt_time "$last_epoch") ($(fmt_span $((NOW - last_epoch))) ago) on $(kv_get "$STATE" DEVICE_NAME)"
    source="the installed provisioning profile"
    if ! is_number "$expires"; then
      expires=$((last_epoch + 7 * DAY))
      source="estimated: install + 7 days"
    fi
    left=$((expires - NOW))
    if [ "$left" -gt 0 ]; then
      echo "Signing expires: $(fmt_time "$expires") ($source)"
      echo "Days until the 7-day expiry: $((left / DAY)) ($(fmt_span "$left"))"
    else
      echo "Signing expired: $(fmt_time "$expires") ($source); the app will not open until reinstalled"
      echo "Days until the 7-day expiry: 0 (expired)"
    fi
    installed="$last_sha"
  else
    echo "Last install:   none recorded"
    installed=""
  fi
  if [ -n "$TARGET" ]; then
    if [ "$TARGET" = "$installed" ]; then
      echo "origin/main:    ${TARGET:0:7} (installed)"
    else
      echo "origin/main:    ${TARGET:0:7} (not installed yet)"
    fi
  fi
  if find_device; then
    echo "iPhone:         $DEV_NAME, reachable over $DEV_TRANSPORT (iOS $DEV_OS)"
  else
    echo "iPhone:         not reachable: $DEV_ERROR"
  fi
  if [ -f "$SUMMARY_LOG" ]; then
    echo "Last run:       $(tail -n 1 "$SUMMARY_LOG")"
  fi
}

# ---------------------------------------------------------------------------------------------
# Main

NOW="$(date +%s)"
TARGET=""
if [ ! -d "$CLONE/.git" ]; then
  setup_error "no dedicated clone at $CLONE; run mac/autoinstall/install.sh"
fi

if [ "$MODE" = status ]; then
  git -C "$CLONE" fetch --quiet origin >/dev/null 2>&1 || echo "(git fetch failed; origin/main is as of the last fetch)"
  TARGET="$(main_sha 2>/dev/null)"
  show_status
  exit 0
fi

if ! take_lock; then
  summary "another run is in progress (pid $(cat "$LOCK/pid" 2>/dev/null)); skipped"
  exit 0
fi

if ! git -C "$CLONE" fetch --quiet origin >"$TMP/git.out" 2>&1; then
  summary "git fetch failed ($(tail -n 1 "$TMP/git.out")); offline? will retry"
  warn_if_expiring
  exit 0
fi
if ! TARGET="$(main_sha 2>"$TMP/git.out")"; then
  fail "the dedicated clone has no origin/main commit (git rev-parse failed)"
fi
if [ "$MODE" = run ] && ! git -C "$CLONE" reset --hard --quiet origin/main >"$TMP/git.out" 2>&1; then
  fail "git reset --hard origin/main failed: $(tail -n 1 "$TMP/git.out")"
fi

decide
if [ -z "$REASON" ] && [ "$MODE" = run ]; then
  summary "skip: $SKIP_WHY"
  exit 0
fi

find_device
rc=$?
if [ "$rc" = 3 ]; then
  summary "phone not reachable, will retry ($DEV_ERROR)"
  if [ "$MODE" = run ]; then warn_if_expiring; fi
  exit 0
elif [ "$rc" != 0 ]; then
  if [ "$MODE" = dry ]; then
    echo "stezu-autoinstall: dry run: $DEV_ERROR" >&2
    exit 1
  fi
  fail "$DEV_ERROR"
fi

APP="$DERIVED/Build/Products/Debug-iphoneos/$PRODUCT"
if [ "$MODE" = dry ]; then
  if [ -n "$REASON" ]; then
    summary "dry run: would install ${TARGET:0:7} ($REASON) on $DEV_NAME over $DEV_TRANSPORT"
  else
    summary "dry run: would skip ($SKIP_WHY); $DEV_NAME is reachable over $DEV_TRANSPORT"
  fi
  cat <<EOF
It would run, in $CLONE:
  git reset --hard origin/main
  cp "$(kv_get "$CONFIG" STEZU_LOCAL_XCCONFIG)" Config/Local.xcconfig
  xcodegen generate
  (delete Xcode's cached provisioning profiles for $BUNDLE_IDS)
  xcodebuild -project StezuHealth.xcodeproj -scheme $SCHEME -configuration Debug -destination id=$DEV_UDID -derivedDataPath "$DERIVED" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
  xcrun devicectl device install app --device $DEV_UDID "$APP"
EOF
  exit 0
fi

# --- Build and install --------------------------------------------------------------------------

RUN_LOG="$LOG_DIR/run-$(date +%Y%m%d-%H%M%S).log"
: >"$RUN_LOG"
LOG_NAME="$(basename "$RUN_LOG")"
say "installing ${TARGET:0:7} ($REASON) on $DEV_NAME ($DEV_TRANSPORT, iOS $DEV_OS)"

LOCAL_XCCONFIG="$(kv_get "$CONFIG" STEZU_LOCAL_XCCONFIG)"
if [ -n "$LOCAL_XCCONFIG" ] && [ -f "$LOCAL_XCCONFIG" ]; then
  cp "$LOCAL_XCCONFIG" "$CLONE/Config/Local.xcconfig" || fail "could not copy $LOCAL_XCCONFIG"
elif [ -f "$CLONE/Config/Local.xcconfig" ]; then
  say "warning: ${LOCAL_XCCONFIG:-STEZU_LOCAL_XCCONFIG} is missing; using the copy from the last run"
else
  fail "no signing team: run scripts/set-team.sh in your working clone, then mac/autoinstall/install.sh"
fi

say "xcodegen generate"
if ! (cd "$CLONE" && xcodegen generate) >>"$RUN_LOG" 2>&1; then
  fail "xcodegen generate failed (see $LOG_NAME)"
fi

removed="$(python3 -c "$PY_PROFILES" clear $BUNDLE_IDS 2>>"$RUN_LOG")"
say "removed ${removed:-0} cached provisioning profile(s), so Xcode issues a fresh 7-day one"

say "xcodebuild (log: $RUN_LOG)"
if ! (cd "$CLONE" && xcodebuild -project StezuHealth.xcodeproj -scheme "$SCHEME" \
  -configuration Debug -destination "id=$DEV_UDID" -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build) >>"$RUN_LOG" 2>&1; then
  echo "$TARGET $(date +%Y-%m-%d)" >"$FAILED_BUILD"
  error="$(grep -m 1 'error:' "$RUN_LOG" | sed 's/^.*error: *//' | cut -c 1-160)"
  fail "build failed: ${error:-see $LOG_NAME} ($LOG_NAME)"
fi
if [ ! -d "$APP" ]; then
  fail "xcodebuild succeeded but $APP is missing"
fi
if [ ! -d "$APP/PlugIns/$EXTENSION" ]; then
  fail "the built app has no PlugIns/$EXTENSION (the Live Activity extension)"
fi

EXPIRES="$(python3 -c "$PY_PROFILES" expiry "$APP" 2>>"$RUN_LOG")"
if is_number "$EXPIRES"; then
  say "signing valid until $(fmt_time "$EXPIRES")"
else
  EXPIRES=""
  say "warning: could not read the embedded provisioning profile; assuming 7 days"
fi

say "xcrun devicectl device install app --device $DEV_UDID $PRODUCT"
if ! xcrun devicectl device install app --device "$DEV_UDID" "$APP" >"$TMP/install.out" 2>&1; then
  cat "$TMP/install.out" >>"$RUN_LOG"
  if grep -qi 'locked' "$TMP/install.out"; then
    summary "phone not reachable, will retry (locked during install; built ${TARGET:0:7})"
    prune_logs
    exit 0
  fi
  fail "install failed: $(grep -v '^[[:space:]]*$' "$TMP/install.out" | tail -n 1 | cut -c 1-160) ($LOG_NAME)"
fi
cat "$TMP/install.out" >>"$RUN_LOG"

{
  echo "LAST_SHA=$TARGET"
  echo "LAST_INSTALL_EPOCH=$NOW"
  echo "LAST_INSTALL_DAY=$(date +%Y-%m-%d)"
  echo "LAST_INSTALL_AT=$(fmt_time "$NOW")"
  echo "PROFILE_EXPIRES_EPOCH=$EXPIRES"
  echo "DEVICE_UDID=$DEV_UDID"
  echo "DEVICE_NAME=$DEV_NAME"
} >"$STATE.tmp" && mv "$STATE.tmp" "$STATE" || fail "installed, but could not write $STATE"
rm -f "$FAILED_BUILD" "$WARNED"

message="Ingest updated to ${TARGET:0:7}"
if is_number "$EXPIRES" && [ $((EXPIRES - NOW)) -lt $((6 * DAY)) ]; then
  message="$message, but its signing still expires $(fmt_time "$EXPIRES")"
fi
summary "installed ${TARGET:0:7} on $DEV_NAME ($REASON); signing until $(fmt_time "${EXPIRES:-$((NOW + 7 * DAY))}")"
notify "$message"
prune_logs
exit 0
