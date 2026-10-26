#!/bin/bash
# Installs the Stezu Screen Time uploader as a launchd agent for this user (macOS only).
# Usage: mac/screentime/install.sh     (PYTHON=/path/to/python3 picks another interpreter)
# It copies the script out of the clone, saves the server settings (--setup) if needed, prints the
# binary that needs Full Disk Access, loads the agent and checks that its first run could read Biome.
set -euo pipefail

LABEL=com.ik301.stezu.screentime
HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HOME/Library/Application Support/Stezu"
SCRIPT="$APP_DIR/stezu_screentime.py"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/Stezu"
OUT="$LOG_DIR/stezu-screentime.log"
ERR="$LOG_DIR/stezu-screentime.err.log"
CONFIG="$HOME/.config/stezu/mac-uploader.env"
DOMAIN="gui/$(id -u)"

[ "$(uname -s)" = Darwin ] || { echo "install.sh: macOS only"; exit 1; }

# 1. The interpreter. /usr/bin/python3 is a shim that runs the Command Line Tools python, and that
# framework python re-execs Python.app/Contents/MacOS/Python. Full Disk Access belongs to the binary
# that opens the files, so launchd starts that binary directly and that is the one to grant.
if [ -z "${PYTHON:-}" ]; then
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "Install the Command Line Tools first: xcode-select --install"
    exit 1
  fi
  PYTHON=/usr/bin/python3
fi
check='import sys, sqlite3, ssl, gzip; assert sys.version_info >= (3, 9)'
REAL="$("$PYTHON" -c 'import os, sys
from pathlib import Path
app = Path(sys.base_prefix) / "Resources/Python.app/Contents/MacOS/Python"
print(app if app.exists() else os.path.realpath(sys.executable))')"
if ! "$REAL" -c "$check" 2>/dev/null; then
  REAL="$("$PYTHON" -c 'import os, sys; print(os.path.realpath(sys.executable))')"
fi
if ! "$REAL" -c "$check"; then
  echo "install.sh: $REAL is not a Python 3.9+ with sqlite3 and ssl"
  exit 1
fi

# 2. The script, outside the clone so moving the clone does not break the agent.
mkdir -p "$APP_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
cp "$HERE/stezu_screentime.py" "$SCRIPT"
chmod 755 "$SCRIPT"

# 3. Server URL and token, saved with mode 0600 outside the repo.
if [ ! -f "$CONFIG" ]; then
  "$REAL" "$SCRIPT" --setup
fi
chmod 600 "$CONFIG"

# 4. Full Disk Access for the interpreter. macOS matches the grant against the Python.app bundle
#    that holds the binary: adding the bare binary shows an "exec" entry that never matches.
APP="${REAL%%/Contents/MacOS/*}"
case "$APP" in *.app) ;; *) APP="$REAL" ;; esac
cat <<EOF

Full Disk Access is needed by the Python that launchd runs directly:

  $APP

  1. System Settings > Privacy & Security > Full Disk Access (opening it now).
  2. Click +, press Cmd+Shift+G, paste this folder, and press Return:
       $(dirname "$APP")/
  3. Select $(basename "$APP") (Python's rocket icon), then Open, and make sure its switch is on.
     An entry with a plain "exec" icon is the bare binary and does not work: remove it with -.
  Terminal's own grant does not cover the agent.

EOF
open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles" 2>/dev/null || true
read -r -p "Press Return once the switch is on... " _

# 5. The agent: daily at 20:00 and once now (RunAtLoad).
sed -e "s|__PYTHON__|$REAL|" -e "s|__SCRIPT__|$SCRIPT|" -e "s|__LOG_DIR__|$LOG_DIR|" \
  "$HERE/$LABEL.plist" >"$PLIST"
plutil -lint "$PLIST" >/dev/null
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
touch "$OUT" "$ERR"
out_lines=$(wc -l <"$OUT")
err_lines=$(wc -l <"$ERR")
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Loaded $LABEL; waiting for its first run (a test read of Biome, then the upload)..."

# 6. The test read, as launchd runs it (the same binary and grant as every later run).
for _ in $(seq 1 90); do
  sleep 1
  new_out="$(tail -n +"$((out_lines + 1))" "$OUT")"
  new_err="$(tail -n +"$((err_lines + 1))" "$ERR")"
  if printf '%s' "$new_err" | grep -q "FULL DISK ACCESS DENIED"; then
    printf '%s\n\n' "$new_err"
    echo "FAILED: the agent cannot read Biome. Grant Full Disk Access to the bundle $APP (not an \"exec\" entry) as above, then run:"
    echo "  launchctl kickstart -k $DOMAIN/$LABEL && sleep 20 && tail -n 5 \"$OUT\" \"$ERR\""
    exit 1
  fi
  if printf '%s' "$new_out" | grep -q "stezu-screentime: ok"; then
    printf '%s\n' "$new_out"
    echo "OK: the agent read Biome and uploaded. It runs daily at 20:00. Logs: $LOG_DIR"
    exit 0
  fi
  if [ -n "$new_err" ] && ! launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -q "state = running"; then
    printf '%s\n' "$new_err"
    echo "FAILED: see the message above (devices: \"$REAL\" \"$SCRIPT\" --list-devices)."
    exit 1
  fi
done
echo "No result after 90 s. Check: tail -n 5 \"$OUT\" \"$ERR\""
exit 1
