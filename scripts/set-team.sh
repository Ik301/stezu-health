#!/usr/bin/env bash
# Sets your Apple signing team for local builds, once per clone. macOS only.
#
#   scripts/set-team.sh              # detect the team from your first Apple Development certificate
#   scripts/set-team.sh ABCDE12345   # or pass the Team ID yourself
#
# Writes Config/Local.xcconfig (gitignored) with DEVELOPMENT_TEAM. Config/Signing.xcconfig
# includes it for StezuHealth and RestActivity, so `xcodegen generate` no longer resets signing.
# Then it runs `xcodegen generate`. Never commit Local.xcconfig: the repo is public (D-034).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL="$ROOT/Config/Local.xcconfig"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "set-team: macOS only (it reads your keychain and generates the Xcode project)." >&2
  exit 1
fi

how_to_find() {
  cat >&2 <<'EOF'
set-team: need your Team ID. Find it one of these ways, then run: scripts/set-team.sh <TEAM_ID>

  1. No certificate yet (you never ran on a device): Xcode > Settings > Accounts, add your
     Apple ID, select it, Manage Certificates..., + > Apple Development. Then run
     scripts/set-team.sh again with no argument; it finds the team itself.
  2. Keychain Access: open the "Apple Development: <your name>" certificate. Its
     Organizational Unit is your Team ID (10 letters and digits).
  3. Xcode: open StezuHealth.xcodeproj, select the StezuHealth target, Signing & Capabilities,
     pick your team (a free account shows "<your name> (Personal Team)"), then Build Settings,
     search for DEVELOPMENT_TEAM. The value is your Team ID.
EOF
}

# The Team ID is the OU of the certificate's subject. macOS's LibreSSL prints
# "subject= /UID=.../CN=.../OU=ABCDE12345/O=...", OpenSSL 3 "subject=UID=..., OU=ABCDE12345, ...".
detect() {
  command -v security >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1 || return 0
  local subject
  subject="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null)" || return 0
  printf '%s\n' "$subject" | grep -oE '(^|[/,]) *OU *= *[A-Z0-9]{10}' | head -n 1 \
    | sed -E 's/.*= *//' || true
}

team="${1:-}"
if [ -z "$team" ]; then
  team="$(detect)"
  if [ -n "$team" ]; then
    echo "set-team: found team $team on your first Apple Development certificate."
  fi
fi
if [ -z "$team" ]; then
  how_to_find
  exit 1
fi
if ! [[ "$team" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "set-team: '$team' is not a Team ID (10 capital letters and digits)." >&2
  how_to_find
  exit 1
fi

mkdir -p "$ROOT/Config"
cat >"$LOCAL" <<EOF
// Written by scripts/set-team.sh. Gitignored: your own signing team, never committed.
DEVELOPMENT_TEAM = $team
EOF
echo "set-team: wrote Config/Local.xcconfig (DEVELOPMENT_TEAM = $team)."
if ! git -C "$ROOT" check-ignore -q Config/Local.xcconfig; then
  echo "set-team: WARNING: Config/Local.xcconfig is not gitignored; do not commit it." >&2
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "set-team: xcodegen not found. Run: brew install xcodegen && xcodegen generate" >&2
  exit 1
fi
(cd "$ROOT" && xcodegen generate)
echo "set-team: done. Open StezuHealth.xcodeproj, pick your iPhone and press Cmd+R."
echo "set-team: later regenerates (xcodegen generate) keep this team."
