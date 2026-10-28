#!/bin/bash
# Installs the Stezu auto-install job for this user (macOS only). It makes a dedicated clone,
# saves where your signing team lives, copies the script out of the clone, does a dry run, loads
# a launchd agent that rebuilds Ingest and installs it on the iPhone over Wi-Fi every morning,
# and offers a first install now (D-104).
#
#   mac/autoinstall/install.sh                   # run from your working clone (where set-team.sh ran)
#   mac/autoinstall/install.sh <working clone>   # or name the clone
#
# Rerun it after pulling a change to mac/autoinstall/: launchd runs the copy, not the clone.
# STEZU_REPO_URL overrides the dedicated clone's URL (default: the public GitHub repo, https).
set -euo pipefail

LABEL=com.ik301.stezu.autoinstall
HERE="$(cd "$(dirname "$0")" && pwd)"
SUPPORT="$HOME/Library/Application Support/Stezu/autoinstall"
CLONE="$SUPPORT/stezu-health"
SCRIPT="$SUPPORT/stezu_autoinstall.sh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/Stezu/autoinstall"
CONFIG="$HOME/.config/stezu/autoinstall.env"
DOMAIN="gui/$(id -u)"
REPO_URL="${STEZU_REPO_URL:-https://github.com/Ik301/stezu-health.git}"

[ "$(uname -s)" = Darwin ] || {
  echo "install.sh: macOS only"
  exit 1
}

# 1. Tools: full Xcode (the Command Line Tools have no xcodebuild or devicectl), xcodegen, git.
missing=0
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild does not run. Install Xcode from the App Store, open it once, then run:"
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  missing=1
elif ! xcrun --find devicectl >/dev/null 2>&1; then
  echo "xcrun cannot find devicectl: this needs Xcode 15 or later."
  missing=1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is missing: brew install xcodegen"
  missing=1
fi
if ! command -v git >/dev/null 2>&1; then
  echo "git is missing (it comes with Xcode)."
  missing=1
fi
if ! python3 -c 'import json, plistlib, subprocess' >/dev/null 2>&1; then
  echo "python3 does not run (it comes with Xcode's developer tools)."
  missing=1
fi
[ "$missing" = 0 ] || exit 1
echo "Tools: $(xcodebuild -version | head -n 1), $(xcodegen --version 2>/dev/null | head -n 1), $(git --version)"

# 2. Your working clone, for its gitignored Config/Local.xcconfig (the signing team).
WORKING="${1:-}"
if [ -z "$WORKING" ]; then
  WORKING="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -z "$WORKING" ] || [ "$WORKING" = "$CLONE" ]; then
  read -r -p "Path to your working clone of stezu-health (where you ran scripts/set-team.sh): " WORKING
fi
case "$WORKING" in "~"/*) WORKING="$HOME/${WORKING#\~/}" ;; esac
WORKING="$(cd "$WORKING" && pwd)"
TEAM_FILE="$WORKING/Config/Local.xcconfig"
if [ ! -f "$TEAM_FILE" ]; then
  echo "$TEAM_FILE does not exist, so that clone has no signing team yet. Run this first:"
  echo "  cd \"$WORKING\" && scripts/set-team.sh"
  echo "then rerun mac/autoinstall/install.sh."
  exit 1
fi
if ! grep -q 'DEVELOPMENT_TEAM' "$TEAM_FILE"; then
  echo "$TEAM_FILE sets no DEVELOPMENT_TEAM. Run scripts/set-team.sh in $WORKING again."
  exit 1
fi
echo "Signing team: from $TEAM_FILE (copied into the dedicated clone before every build)"

# 3. The dedicated clone. The job resets it to origin/main on every run, so never edit it.
mkdir -p "$SUPPORT" "$LOG_DIR" "$HOME/Library/LaunchAgents" "$(dirname "$CONFIG")"
if [ -d "$CLONE/.git" ]; then
  echo "Dedicated clone: $CLONE (exists)"
else
  echo "Dedicated clone: cloning $REPO_URL into $CLONE"
  git clone --quiet "$REPO_URL" "$CLONE"
fi

# 4. Settings, mode 0600 outside the repo. Other lines (STEZU_DEVICE_ID) are kept.
{
  if [ -f "$CONFIG" ]; then
    grep -v '^[[:space:]]*STEZU_LOCAL_XCCONFIG[[:space:]]*=' "$CONFIG" || true
  else
    echo "# Stezu autoinstall settings (read by stezu_autoinstall.sh; never commit this file)."
    echo "# Pin one iPhone, if several are paired: STEZU_DEVICE_ID=<UDID from xcrun devicectl list devices>"
  fi
  echo "STEZU_LOCAL_XCCONFIG=$TEAM_FILE"
} >"$CONFIG.tmp"
mv "$CONFIG.tmp" "$CONFIG"
chmod 600 "$CONFIG"

# 5. The script, outside the clone: a reset of the clone must never rewrite a running script.
cp "$HERE/stezu_autoinstall.sh" "$SCRIPT"
chmod 755 "$SCRIPT"

# 6. A dry run: decides, looks for the iPhone, builds nothing.
echo
echo "Dry run:"
if ! out="$(/bin/bash "$SCRIPT" --dry-run 2>&1)"; then
  printf '%s\n' "$out"
  echo "The dry run failed; fix the message above and rerun install.sh."
  exit 1
fi
printf '%s\n' "$out"
reachable=1
if printf '%s' "$out" | grep -q 'phone not reachable'; then
  reachable=0
  cat <<'EOF'

The iPhone is not reachable over the network yet. Pair it once (see mac/autoinstall/README.md):
  1. Connect it with a cable, unlock it, tap Trust.
  2. Xcode > Window > Devices and Simulators > select the iPhone > tick "Connect via network".
  3. Unplug it. Keep it unlocked on the same Wi-Fi as the Mac (not eduroam: use home Wi-Fi or the
     iPhone's hotspot). A network icon next to it in that window means it works.
The agent is loaded anyway and retries every hour.
EOF
fi

# 7. The agent: 06:30, then hourly retries 07:00 to 22:00.
sed -e "s|__SCRIPT__|$SCRIPT|" -e "s|__LOG_DIR__|$LOG_DIR|" "$HERE/$LABEL.plist" >"$PLIST"
plutil -lint "$PLIST" >/dev/null
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
sleep 1
if ! launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null; then
  sleep 2
  launchctl bootstrap "$DOMAIN" "$PLIST"
fi
echo
echo "Loaded $LABEL: daily at 06:30, retried hourly 07:00 to 22:00 until an install succeeds."

# 8. The first install now, in this Terminal, so a keychain prompt can be answered (Always Allow).
if [ "$reachable" = 1 ] && [ -t 0 ]; then
  read -r -p "Build and install now (about 5 minutes)? [Y/n] " answer
  case "${answer:-y}" in
    [Yy]*)
      /bin/bash "$SCRIPT" || echo "The first install failed; see the message above and the log it names."
      ;;
  esac
fi

cat <<EOF

Check it:
  "$SCRIPT" --status
  tail -n 5 "$LOG_DIR/autoinstall.log"
  launchctl print $DOMAIN/$LABEL | grep -E 'state|last exit'
  launchctl kickstart $DOMAIN/$LABEL     # run it now, as launchd does
Settings: $CONFIG    Logs: $LOG_DIR
EOF
