#!/usr/bin/env bash
# Offline tests for the Mac auto-installer: stubbed git, xcrun, xcodebuild, xcodegen, osascript
# and security, synthetic devices only. Linux or macOS. BASH_UNDER_TEST=/path/to/bash-3.2 checks
# the script under macOS's /bin/bash version.
set -euo pipefail
cd "$(dirname "$0")"
exec bash Tests/test_autoinstall.sh "$@"
