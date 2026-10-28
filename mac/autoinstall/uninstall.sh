#!/bin/bash
# Removes the Stezu auto-install agent. --purge also deletes the dedicated clone, its DerivedData,
# the script copy, the state, the logs and the settings (~/.config/stezu/autoinstall.env).
# Ingest stays on the iPhone and stops opening when its current signing expires.
set -euo pipefail

LABEL=com.ik301.stezu.autoinstall
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
echo "Unloaded and removed $LABEL."
if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/Library/Application Support/Stezu/autoinstall" "$HOME/Library/Logs/Stezu/autoinstall"
  rm -f "$HOME/.config/stezu/autoinstall.env"
  echo "Deleted the dedicated clone, DerivedData, script copy, state, logs and settings."
fi
