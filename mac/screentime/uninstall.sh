#!/bin/bash
# Removes the Stezu Screen Time agent. --purge also deletes the script copy, state, logs and the
# server settings (~/.config/stezu/mac-uploader.env). Data already on the server stays there.
set -euo pipefail

LABEL=com.ik301.stezu.screentime
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
echo "Unloaded and removed $LABEL."
if [ "${1:-}" = "--purge" ]; then
  rm -f "$HOME/Library/Application Support/Stezu/stezu_screentime.py" \
    "$HOME/Library/Application Support/Stezu/screentime-state.json" \
    "$HOME/.config/stezu/mac-uploader.env"
  rm -rf "$HOME/Library/Logs/Stezu"
  echo "Deleted the script copy, state, logs and server settings."
fi
echo "Remove the interpreter from System Settings > Privacy & Security > Full Disk Access by hand."
