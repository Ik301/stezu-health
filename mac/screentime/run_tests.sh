#!/usr/bin/env bash
# Offline tests for the Mac Screen Time uploader (stdlib unittest, synthetic data only).
set -euo pipefail
cd "$(dirname "$0")"
exec "${PYTHON:-python3}" -m unittest discover -s Tests -p "test_*.py" "$@"
