#!/usr/bin/env bash
# G3: diff budget against the merge base with BASE (default origin/main).
# Counts committed, uncommitted and untracked changes. Skipped on main.
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT"
BASE="${1:-origin/main}"
MAX_LINES="${MAX_LINES:-300}"
MAX_FILES="${MAX_FILES:-12}"

branch="${GITHUB_HEAD_REF:-}"
if [ -z "$branch" ]; then
  case "${GITHUB_REF:-}" in
    refs/heads/*) branch="${GITHUB_REF#refs/heads/}" ;;
  esac
fi
[ -n "$branch" ] || branch="$(git symbolic-ref --short -q HEAD || git rev-parse --abbrev-ref HEAD)"
if [ "$branch" = "main" ]; then
  echo "diff-budget: SKIP on main"
  exit 0
fi

if ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
  echo "diff-budget: FAIL: base $BASE not found (fetch full history)"
  exit 1
fi
mb="$(git merge-base "$BASE" HEAD)"

is_test() {
  case "$1" in
    *Tests/*) return 0 ;;
  esac
  return 1
}

errors=0
err() {
  echo "diff-budget: FAIL: $*"
  errors=$((errors + 1))
}

changed="$( (git diff --name-only --no-renames "$mb"; git ls-files --others --exclude-standard) | sort -u)"

lines=0
files=0
while IFS=$'\t' read -r add del path; do
  [ -n "$path" ] || continue
  case "$path" in *.md) continue ;; esac
  if is_test "$path"; then continue; fi
  [ "$add" = "-" ] && add=0
  [ "$del" = "-" ] && del=0
  files=$((files + 1))
  lines=$((lines + add + del))
done < <(git diff --numstat --no-renames "$mb")

while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in *.md) continue ;; esac
  if is_test "$path"; then continue; fi
  files=$((files + 1))
  if [ -f "$path" ]; then
    lines=$((lines + $(wc -l <"$path")))
  fi
done < <(git ls-files --others --exclude-standard)

echo "diff-budget: $lines changed non-test lines in $files files (limits $MAX_LINES lines, $MAX_FILES files)"
[ "$lines" -le "$MAX_LINES" ] || err "more than $MAX_LINES changed non-test lines"
[ "$files" -le "$MAX_FILES" ] || err "more than $MAX_FILES changed non-test files"

while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in
    *.xcodeproj | *.xcodeproj/*) err "changes a generated Xcode project: $path" ;;
    *.entitlements) err "changes an entitlements file: $path" ;;
  esac
done <<<"$changed"

if [ -f project.yml ]; then
  signing='DEVELOPMENT_TEAM|CODE_SIGN_IDENTITY|CODE_SIGN_ENTITLEMENTS|PROVISIONING_PROFILE|developmentTeam|provisioningProfile|entitlements:'
  if grep -nE "$signing" project.yml; then
    err "signing keys or entitlements in project.yml"
  fi
fi

while IFS= read -r path; do
  case "$path" in *.swift) ;; *) continue ;; esac
  if ! is_test "$path"; then continue; fi
  before="$(git show "$mb:$path" | grep -c 'func test' || true)"
  after=0
  if [ -f "$path" ]; then
    after="$(grep -c 'func test' "$path" || true)"
  fi
  if [ "$after" -lt "$before" ]; then
    err "$path has $after 'func test' (was $before); tests may not be removed"
  fi
done < <(git ls-tree -r --name-only "$mb")

if [ "$errors" -gt 0 ]; then
  exit 1
fi
echo "diff-budget: OK"
