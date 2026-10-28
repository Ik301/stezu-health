#!/usr/bin/env bash
# Tests for stezu_autoinstall.sh that run on Linux or macOS: git, xcrun (devicectl), xcodebuild,
# xcodegen, osascript and security are fake executables in stubs/, first on PATH. Synthetic
# devices and shas only. BASH_UNDER_TEST picks the bash that runs the script (default: bash);
# point it at a bash 3.2 build to check macOS's /bin/bash.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/stezu_autoinstall.sh"
STUBS="$HERE/stubs"
FIXTURES="$HERE/fixtures"
BASH_UNDER_TEST="${BASH_UNDER_TEST:-bash}"

SHA_A=aaaaaaa111111111111111111111111111111111
SHA_B=bbbbbbb222222222222222222222222222222222
PHONE_1=00000000-000A000000000001
PHONE_2=00000000-000A000000000002
CORE_ID_2=AAAAAAAA-0000-4000-8000-000000000002
DAY=86400

passed=0
failed=0
failures=""
ok=1
current=""

# --- harness -----------------------------------------------------------------------------------

setup() {
  T="$(mktemp -d "${TMPDIR:-/tmp}/autoinstall-test.XXXXXX")"
  export HOME="$T/home"
  SUPPORT="$HOME/Library/Application Support/Stezu/autoinstall"
  CLONE="$SUPPORT/stezu-health"
  STATE="$SUPPORT/state"
  LOGS="$HOME/Library/Logs/Stezu/autoinstall"
  CONFIG="$HOME/.config/stezu/autoinstall.env"
  WORK="$T/working-clone"
  mkdir -p "$CLONE/.git" "$CLONE/Config" "$WORK/Config" "$(dirname "$CONFIG")"
  echo "DEVELOPMENT_TEAM = ABCDE12345" >"$WORK/Config/Local.xcconfig"
  echo "STEZU_LOCAL_XCCONFIG=$WORK/Config/Local.xcconfig" >"$CONFIG"
  export STUB_LOG="$T/calls.log" NOTIFY_LOG="$T/notifications.log"
  : >"$STUB_LOG"
  : >"$NOTIFY_LOG"
  export FAKE_SHA="$SHA_B" FAKE_DEVICES="$FIXTURES/devices-wifi.json"
  unset FAKE_BUILD_RC FAKE_INSTALL_RC FAKE_INSTALL_MSG FAKE_FETCH_RC STEZU_DEVICE_ID
}

teardown() {
  rm -rf "$T"
}

run() {
  OUT="$(PATH="$STUBS:$PATH" "$BASH_UNDER_TEST" "$SCRIPT" "$@" 2>&1)"
  RC=$?
}

# write_state <sha> <seconds ago> [profile expires in seconds]
write_state() {
  local now
  now="$(date +%s)"
  mkdir -p "$SUPPORT"
  {
    echo "LAST_SHA=$1"
    echo "LAST_INSTALL_EPOCH=$((now - $2))"
    echo "LAST_INSTALL_DAY=2000-01-01"
    if [ -n "${3:-}" ]; then echo "PROFILE_EXPIRES_EPOCH=$((now + $3))"; fi
    echo "DEVICE_UDID=$PHONE_1"
    echo "DEVICE_NAME=Test iPhone"
  } >"$STATE"
  cp "$STATE" "$T/state.before"
}

state_get() {
  sed -n "s/^$1=//p" "$STATE" | tail -n 1
}

fail_check() {
  echo "  FAIL [$current] $1"
  ok=0
}

expect_rc() {
  [ "$RC" = "$1" ] || fail_check "exit code $RC, expected $1; output:
$OUT"
}

expect_out() {
  printf '%s' "$OUT" | grep -qF -- "$1" || fail_check "output lacks '$1'; output:
$OUT"
}

expect_called() {
  grep -qF -- "$1" "$STUB_LOG" || fail_check "no call matching '$1'; calls:
$(cat "$STUB_LOG")"
}

expect_not_called() {
  if grep -qF -- "$1" "$STUB_LOG"; then fail_check "unexpected call matching '$1'"; fi
}

expect_notified() {
  grep -qF -- "$1" "$NOTIFY_LOG" || fail_check "no notification '$1'; got: $(cat "$NOTIFY_LOG")"
}

expect_no_notification() {
  if [ -s "$NOTIFY_LOG" ]; then fail_check "unexpected notification: $(cat "$NOTIFY_LOG")"; fi
}

expect_state_unchanged() {
  if [ -f "$T/state.before" ]; then
    cmp -s "$STATE" "$T/state.before" || fail_check "state changed: $(cat "$STATE" 2>/dev/null)"
  elif [ -f "$STATE" ]; then
    fail_check "state written: $(cat "$STATE")"
  fi
}

expect_eq() {
  [ "$1" = "$2" ] || fail_check "$3: got '$1', expected '$2'"
}

# A cached Xcode profile for <application-identifier>, as Xcode keeps them.
cached_profile() {
  local dir="$HOME/Library/MobileDevice/Provisioning Profiles"
  mkdir -p "$dir"
  cat >"$dir/$1.mobileprovision" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>ExpirationDate</key><date>2030-01-01T00:00:00Z</date>
<key>Entitlements</key><dict><key>application-identifier</key><string>$2</string></dict>
</dict></plist>
EOF
}

# --- tests -------------------------------------------------------------------------------------

test_no_change_and_recent_install_skips() {
  write_state "$SHA_B" "$DAY"
  run
  expect_rc 0
  expect_out "skip: up to date: bbbbbbb installed"
  expect_called "git -C $CLONE fetch --quiet origin"
  expect_not_called "devicectl"
  expect_not_called "xcodebuild"
  expect_not_called "xcodegen"
  expect_no_notification
  expect_state_unchanged
  expect_eq "$(wc -l <"$LOGS/autoinstall.log" | tr -d ' ')" 1 "lines in autoinstall.log"
  expect_eq "$(ls "$LOGS" | grep -c '^run-')" 0 "run logs for a skip"
}

test_almost_five_days_still_skips() {
  write_state "$SHA_B" $((5 * DAY - 3600))
  run
  expect_rc 0
  expect_out "skip: up to date"
  expect_not_called "xcodebuild"
}

test_new_sha_builds_installs_and_writes_state() {
  write_state "$SHA_A" "$DAY"
  cached_profile stezu "ABCDE12345.com.ik301.stezuhealth"
  cached_profile stezu-rest "ABCDE12345.com.ik301.stezuhealth.RestActivity"
  cached_profile other "ABCDE12345.com.example.other"
  cached_profile wildcard "ABCDE12345.*"
  before="$(date +%s)"
  run
  expect_rc 0
  expect_out "installing bbbbbbb (main moved from aaaaaaa to bbbbbbb) on Test iPhone (localNetwork"
  expect_called "git -C $CLONE reset --hard --quiet origin/main"
  expect_called "xcodegen generate (cwd $CLONE) (DEVELOPMENT_TEAM = ABCDE12345)"
  expect_called "xcodebuild -project StezuHealth.xcodeproj -scheme StezuHealth -configuration Debug -destination id=$PHONE_1 -derivedDataPath $SUPPORT/DerivedData -allowProvisioningUpdates -allowProvisioningDeviceRegistration build (cwd $CLONE)"
  expect_called "xcrun devicectl device install app --device $PHONE_1 $SUPPORT/DerivedData/Build/Products/Debug-iphoneos/StezuHealth.app"
  expect_eq "$(state_get LAST_SHA)" "$SHA_B" "LAST_SHA"
  expect_eq "$(state_get DEVICE_UDID)" "$PHONE_1" "DEVICE_UDID"
  installed="$(state_get LAST_INSTALL_EPOCH)"
  [ "$installed" -ge "$before" ] || fail_check "LAST_INSTALL_EPOCH $installed is older than the run"
  expires="$(state_get PROFILE_EXPIRES_EPOCH)"
  left=$((expires - before))
  [ "$left" -gt $((7 * DAY - 120)) ] && [ "$left" -le $((7 * DAY + 120)) ] ||
    fail_check "PROFILE_EXPIRES_EPOCH is $left s away, expected 7 days"
  expect_notified "Ingest updated to bbbbbbb"
  cmp -s "$WORK/Config/Local.xcconfig" "$CLONE/Config/Local.xcconfig" || fail_check "Local.xcconfig not copied"
  profiles="$(ls "$HOME/Library/MobileDevice/Provisioning Profiles" | tr '\n' ' ')"
  expect_eq "$profiles" "other.mobileprovision wildcard.mobileprovision " "cached profiles left"
  expect_out "removed 2 cached provisioning profile(s)"
  expect_eq "$(ls "$LOGS" | grep -c '^run-')" 1 "run logs"
  # Order: fetch, reset, xcodegen, xcodebuild, install.
  order="$(call_order | tr '\n' ',')"
  expect_eq "$order" "fetch,rev-parse,reset,list,xcodegen,xcodebuild,install," "call order"
}

# The stub calls, one word each. (A function: bash 3.2 misparses case inside $(...).)
call_order() {
  local line
  while read -r line; do
    case "$line" in
      "git "*" fetch "*) echo fetch ;;
      "git "*" rev-parse "*) echo rev-parse ;;
      "git "*" reset "*) echo reset ;;
      "xcrun devicectl list devices"*) echo list ;;
      "xcrun devicectl device install app"*) echo install ;;
      xcodegen*) echo xcodegen ;;
      xcodebuild*) echo xcodebuild ;;
      *) echo "other: $line" ;;
    esac
  done <"$STUB_LOG"
}

test_five_day_old_install_reinstalls() {
  write_state "$SHA_B" $((5 * DAY + 60))
  run
  expect_rc 0
  expect_out "(the last install is 5 days old)"
  expect_called "xcodebuild"
  expect_called "devicectl device install app"
  expect_eq "$(state_get LAST_SHA)" "$SHA_B" "LAST_SHA"
  now="$(date +%s)"
  [ $((now - $(state_get LAST_INSTALL_EPOCH))) -lt 120 ] || fail_check "LAST_INSTALL_EPOCH not renewed"
  expect_notified "Ingest updated to bbbbbbb"
}

test_profile_close_to_expiry_reinstalls() {
  # Installed 3 days ago, but the profile it got was already half used (expires in 1 day).
  write_state "$SHA_B" $((3 * DAY)) "$DAY"
  run
  expect_rc 0
  expect_out "(the installed signing expires"
  expect_called "devicectl device install app"
}

test_phone_unreachable_exits_zero_and_keeps_state() {
  write_state "$SHA_A" "$DAY"
  export FAKE_DEVICES="$FIXTURES/devices-unreachable.json"
  run
  expect_rc 0
  expect_out "phone not reachable, will retry"
  expect_out "Test iPhone: tunnel unavailable"
  expect_not_called "xcodebuild"
  expect_not_called "device install"
  expect_no_notification
  expect_state_unchanged
}

test_unreachable_near_expiry_warns_once_a_day() {
  write_state "$SHA_A" $((6 * DAY))
  export FAKE_DEVICES="$FIXTURES/devices-unreachable.json"
  run
  expect_rc 0
  run
  expect_rc 0
  expect_eq "$(grep -c 'Ingest signing expires' "$NOTIFY_LOG")" 1 "expiry warnings"
  expect_state_unchanged
}

test_build_failure_notifies_and_keeps_state() {
  write_state "$SHA_A" "$DAY"
  mkdir -p "$LOGS"
  for i in 01 02 03 04 05 06 07 08 09 10 11 12; do : >"$LOGS/run-20000101-0000$i.log"; done
  export FAKE_BUILD_RC=65
  run
  expect_rc 1
  expect_out "FAILED: build failed: cannot find 'Bar' in scope"
  expect_notified "Ingest install failed: build failed: cannot find 'Bar' in scope"
  expect_not_called "device install"
  expect_state_unchanged
  expect_eq "$(ls "$LOGS" | grep -c '^run-')" 10 "run logs kept"
  newest="$(ls "$LOGS" | grep '^run-' | sort | tail -n 1)"
  grep -q "BUILD FAILED" "$LOGS/$newest" || fail_check "the newest run log lacks the xcodebuild output"
  # The same commit is not rebuilt every hour the same day...
  : >"$STUB_LOG"
  run
  expect_rc 0
  expect_out "already failed to build today"
  expect_not_called "xcodebuild"
  # ...but --force tries again.
  unset FAKE_BUILD_RC
  run --force
  expect_rc 0
  expect_called "xcodebuild"
  expect_eq "$(state_get LAST_SHA)" "$SHA_B" "LAST_SHA after --force"
}

test_install_failure_keeps_state() {
  write_state "$SHA_A" "$DAY"
  export FAKE_INSTALL_RC=1
  run
  expect_rc 1
  expect_notified "Ingest install failed: install failed: ERROR: Failed to install the app"
  expect_state_unchanged
}

test_locked_phone_during_install_retries_quietly() {
  write_state "$SHA_A" "$DAY"
  export FAKE_INSTALL_RC=1 FAKE_INSTALL_MSG="ERROR: The device is locked. (kAMDMobileImageMounterDeviceLocked)"
  run
  expect_rc 0
  expect_out "phone not reachable, will retry (locked during install"
  expect_no_notification
  expect_state_unchanged
}

test_pinned_device_id_is_used() {
  write_state "$SHA_A" "$DAY"
  export FAKE_DEVICES="$FIXTURES/devices-two-phones.json"
  echo "STEZU_DEVICE_ID=$PHONE_2" >>"$CONFIG"
  run
  expect_rc 0
  expect_out "on Second iPhone (wired"
  expect_called "-destination id=$PHONE_2 "
  expect_called "device install app --device $PHONE_2 "
  expect_eq "$(state_get DEVICE_UDID)" "$PHONE_2" "DEVICE_UDID"
}

test_pin_by_coredevice_identifier_builds_for_its_udid() {
  write_state "$SHA_A" "$DAY"
  export FAKE_DEVICES="$FIXTURES/devices-two-phones.json"
  echo "STEZU_DEVICE_ID=\"$CORE_ID_2\"" >>"$CONFIG"
  run
  expect_rc 0
  expect_called "-destination id=$PHONE_2 "
}

test_pinned_device_absent_is_not_reachable() {
  write_state "$SHA_A" "$DAY"
  echo "STEZU_DEVICE_ID=00000000-000A00000000FFFF" >>"$CONFIG"
  run
  expect_rc 0
  expect_out "phone not reachable, will retry (the pinned iPhone (STEZU_DEVICE_ID) is not among the 1 iPhones"
  expect_not_called "xcodebuild"
  expect_state_unchanged
}

test_two_reachable_phones_unpinned_fails() {
  write_state "$SHA_A" "$DAY"
  export FAKE_DEVICES="$FIXTURES/devices-two-phones.json"
  run
  expect_rc 1
  expect_out "2 paired iPhones are reachable (Test iPhone, Second iPhone); pin one with STEZU_DEVICE_ID"
  expect_not_called "xcodebuild"
}

test_unexpected_devicectl_json_fails_clearly() {
  write_state "$SHA_A" "$DAY"
  export FAKE_DEVICES="$FIXTURES/devices-bad-shape.json"
  run
  expect_rc 1
  expect_out "devicectl JSON has no result.devices list (jsonVersion 99"
  expect_notified "Ingest install failed: devicectl JSON has no result.devices list"
  expect_not_called "xcodebuild"
  expect_state_unchanged
}

test_dry_run_builds_nothing() {
  run --dry-run
  expect_rc 0
  expect_out "dry run: would install bbbbbbb (first install) on Test iPhone over localNetwork"
  expect_out "xcodebuild -project StezuHealth.xcodeproj -scheme StezuHealth -configuration Debug -destination id=$PHONE_1"
  expect_called "devicectl list devices"
  expect_not_called "reset"
  expect_not_called "xcodegen"
  expect_not_called "xcodebuild"
  expect_not_called "device install"
  [ -f "$STATE" ] && fail_check "dry run wrote state"
  expect_no_notification
}

test_force_installs_when_up_to_date() {
  write_state "$SHA_B" 60
  run --force
  expect_rc 0
  expect_out "(forced)"
  expect_called "device install app"
}

test_offline_fetch_retries_quietly() {
  write_state "$SHA_A" "$DAY"
  export FAKE_FETCH_RC=128
  run
  expect_rc 0
  expect_out "git fetch failed"
  expect_out "will retry"
  expect_not_called "devicectl"
  expect_no_notification
  expect_state_unchanged
}

test_missing_origin_main_fails() {
  write_state "$SHA_A" "$DAY"
  export FAKE_SHA=""
  run
  expect_rc 1
  expect_out "the dedicated clone has no origin/main commit"
  expect_not_called "reset"
  expect_not_called "xcodebuild"
  expect_state_unchanged
}

test_missing_signing_team_fails() {
  write_state "$SHA_A" "$DAY"
  rm -f "$WORK/Config/Local.xcconfig" "$CLONE/Config/Local.xcconfig"
  run
  expect_rc 1
  expect_out "no signing team: run scripts/set-team.sh in your working clone"
  expect_not_called "xcodebuild"
}

test_status_reports_days_left_and_reachability() {
  write_state "$SHA_A" $((2 * DAY)) $((5 * DAY + 1800))
  run --status
  expect_rc 0
  expect_out "Last install:   aaaaaaa at"
  expect_out "Days until the 7-day expiry: 5 (5 d 0 h)"
  expect_out "origin/main:    bbbbbbb (not installed yet)"
  expect_out "iPhone:         Test iPhone, reachable over localNetwork (iOS 26.0)"
  expect_not_called "xcodebuild"
  expect_state_unchanged
}

test_no_dedicated_clone_is_a_setup_error() {
  rm -rf "$CLONE"
  run --status
  expect_rc 2
  expect_out "run mac/autoinstall/install.sh"
}

test_launchd_template() {
  python3 - "$ROOT/com.ik301.stezu.autoinstall.plist" <<'EOF' || fail_check "launchd template"
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
assert p["Label"] == "com.ik301.stezu.autoinstall", p["Label"]
assert p["ProgramArguments"] == ["/bin/bash", "__SCRIPT__"], p["ProgramArguments"]
times = [(e["Hour"], e["Minute"]) for e in p["StartCalendarInterval"]]
assert times == [(6, 30)] + [(h, 0) for h in range(7, 23)], times
assert p["RunAtLoad"] is False and p["LowPriorityIO"] is True and p["ProcessType"] == "Background"
path = p["EnvironmentVariables"]["PATH"].split(":")
assert "/opt/homebrew/bin" in path and "/usr/local/bin" in path and "/usr/bin" in path, path
assert p["StandardOutPath"].startswith("__LOG_DIR__/"), p["StandardOutPath"]
EOF
}

test_scripts_parse_under_this_bash() {
  local f
  for f in stezu_autoinstall.sh install.sh uninstall.sh; do
    "$BASH_UNDER_TEST" -n "$ROOT/$f" || fail_check "$f does not parse"
  done
}

# --- runner ------------------------------------------------------------------------------------

tests="$(grep -oE '^test_[a-z0-9_]+' "$0")"
echo "stezu_autoinstall tests under $("$BASH_UNDER_TEST" -c 'echo bash $BASH_VERSION')"
for current in $tests; do
  if [ -n "${1:-}" ] && [ "$current" != "$1" ]; then continue; fi
  ok=1
  setup
  "$current"
  teardown
  if [ "$ok" = 1 ]; then
    passed=$((passed + 1))
    echo "ok   $current"
  else
    failed=$((failed + 1))
    failures="$failures $current"
    echo "FAIL $current"
  fi
done
echo "$passed passed, $failed failed"
if [ "$failed" != 0 ]; then
  echo "failed:$failures"
  exit 1
fi
