#!/usr/bin/env bash
# Linux gates G1 to G5. Works from the main checkout or any git worktree.
# Usage: scripts/gate-linux.sh   (env: FEATURE_ID=F-xxx, BASE=origin/main)
set -uo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 1
cd "$ROOT" || exit 1
BASE="${BASE:-origin/${GITHUB_BASE_REF:-main}}"

failed=()
run_gate() {
  local name="$1"
  shift
  echo "== $name"
  if "$@"; then
    echo "== $name: PASS"
  else
    echo "== $name: FAIL"
    failed+=("$name")
  fi
}

g1_build_test() {
  (cd Packages/StezuCore && swift build && swift test)
}

g2_features() {
  python3 scripts/check-features.py --base "$BASE"
}

g3_diff_budget() {
  scripts/diff-budget.sh "$BASE"
}

g4_format() {
  if ! swift format --version >/dev/null 2>&1; then
    echo "notice: swift-format is not available; G4 skipped"
    return 0
  fi
  swift format lint --strict --recursive Packages/StezuCore/Package.swift \
    Packages/StezuCore/Sources Packages/StezuCore/Tests App
}

g5_server() {
  # The VM server (server/, built separately) brings its own test runner.
  if [ ! -f server/run_tests.sh ]; then
    echo "notice: server/run_tests.sh not found; G5 skipped"
    return 0
  fi
  bash server/run_tests.sh
}

run_gate "G1 build and test" g1_build_test
run_gate "G2 feature ledger" g2_features
run_gate "G3 diff budget" g3_diff_budget
run_gate "G4 format lint" g4_format
run_gate "G5 server tests" g5_server

if [ "${#failed[@]}" -gt 0 ]; then
  printf 'gate-linux: FAILED:'
  printf ' [%s]' "${failed[@]}"
  printf '\n'
  exit 1
fi
echo "gate-linux: all gates passed"
