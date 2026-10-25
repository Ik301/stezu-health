#!/usr/bin/env bash
# Runs the server tests offline. Creates server/.venv on first use (pip needs the
# network once); the tests themselves block all sockets.
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -x .venv/bin/python ]; then
  "${PYTHON:-python3}" -m venv .venv || { echo "run_tests: cannot create a venv (install python3-venv)"; exit 1; }
fi
if ! .venv/bin/python -c "import fastapi, httpx, pytest, python_multipart" 2>/dev/null; then
  .venv/bin/python -m pip install -q -r requirements-dev.txt
fi
exec .venv/bin/python -m pytest -q -p no:cacheprovider Tests "$@"
