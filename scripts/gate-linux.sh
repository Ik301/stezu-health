#!/usr/bin/env bash
# Linux gates G1 to G8. Works from the main checkout or any git worktree.
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

g6_mac_uploader() {
  # The Mac Screen Time uploader (mac/screentime, stdlib Python) brings its own offline tests.
  if [ ! -f mac/screentime/run_tests.sh ]; then
    echo "notice: mac/screentime/run_tests.sh not found; G6 skipped"
    return 0
  fi
  bash mac/screentime/run_tests.sh
}

g8_mac_autoinstall() {
  # The Mac auto-installer (mac/autoinstall, bash) brings its own tests with stubbed Xcode tools.
  if [ ! -f mac/autoinstall/run_tests.sh ]; then
    echo "notice: mac/autoinstall/run_tests.sh not found; G8 skipped"
    return 0
  fi
  bash mac/autoinstall/run_tests.sh
}

g7_token_lint() {
  # UI code takes colours and fonts from Theme.swift only (design/system/tokens.json).
  local theme=App/Shared/Theme.swift
  local literals='(^|[^[:alnum:]_])(Color)?\.(white|black)\b|(^|[^[:alnum:]_])Color\((red|hex|white|\.sRGB)|#[0-9A-Fa-f]{6}\b|0x[0-9A-Fa-f]{6}\b|\.system\(size:'
  local hits
  hits="$(grep -rnE --include='*.swift' "$literals" App/Sources App/RestActivity App/Shared |
    grep -v "^$theme:")"
  if [ -n "$hits" ]; then
    echo "colour or font literals outside $theme (use a Theme token):"
    echo "$hits"
    return 1
  fi
  # Theme.swift carries every token in tokens.json, with the same values.
  python3 - "$theme" design/system/tokens.json <<'EOF'
import json, re, sys

theme = open(sys.argv[1]).read()
tokens = json.load(open(sys.argv[2]))
errors = []


def camel(name):
    parts = name.removeprefix("t-").split("-")
    return parts[0] + "".join(p[0].upper() + p[1:] for p in parts[1:])


def rgba(value):
    value = value.strip().lower()
    if value.startswith("#"):
        return value[1:], 1.0
    r, g, b, a = re.fullmatch(r"rgba\((\d+), *(\d+), *(\d+), *([\d.]+)\)", value).groups()
    return "%02x%02x%02x" % (int(r), int(g), int(b)), float(a)


for token in tokens["color"]["tokens"]:
    name, value = camel(token["name"]), token["value"]
    ref = re.fullmatch(r"\{([\w-]+)\}", value["light"])
    if ref:
        if f"static let {name} = {camel(ref.group(1))}\n" not in theme:
            errors.append(f"{name}: expected = {camel(ref.group(1))}")
        continue
    m = re.search(
        rf"static let {name} = color\(0x(\w{{6}}), dark: 0x(\w{{6}})"
        r"(?:, alpha: ([\d.]+), darkAlpha: ([\d.]+))?\)", theme)
    want = rgba(value["light"]) + rgba(value["dark"])
    got = m and (m[1].lower(), float(m[3] or 1), m[2].lower(), float(m[4] or 1))
    if got != want:
        errors.append(f"{name}: tokens.json has {want}, Theme.swift {got}")

for group in ("spacing", "radius", "size"):
    for token in tokens[group]["tokens"]:
        name, points = camel(token["name"]), token["value"].removesuffix("px")
        if f"static let {name}: CGFloat = {points}\n" not in theme:
            errors.append(f"{name}: expected {points}")


def cases(var):
    """`case .a, .b: value` lines of one TextStyle property, as {case: value}."""
    block = re.search(rf"var {var}: [\w.]+ \{{\n(.*?)\n    \}}", theme, re.S)
    found = {}
    for names, value in re.findall(r"case ([^:]+): (\S+)", block.group(1) if block else ""):
        for case in names.split(","):
            found[case.strip().lstrip(".")] = value
    return found


sizes, weights, tracking = cases("size"), cases("weight"), cases("tracking")
weight_names = {400: ".regular", 500: ".medium", 600: ".semibold"}
for group in tokens["type"]["groups"]:
    for style in group["styles"]:
        name = camel(style["name"])
        if sizes.get(name) != style["fontSize"].removesuffix("px"):
            errors.append(f"{name}: size {style['fontSize']}, Theme.swift {sizes.get(name)}")
        if weights.get(name) != weight_names[style["fontWeight"]]:
            errors.append(f"{name}: weight {style['fontWeight']}, Theme.swift {weights.get(name)}")
        spacing = float(style.get("letterSpacing", "0px").removesuffix("px"))
        if float(tracking.get(name, "0")) != spacing:
            errors.append(f"{name}: tracking {spacing}, Theme.swift {tracking.get(name)}")

for error in errors:
    print("Theme.swift differs from tokens.json:", error)
sys.exit(1 if errors else 0)
EOF
}

run_gate "G1 build and test" g1_build_test
run_gate "G2 feature ledger" g2_features
run_gate "G3 diff budget" g3_diff_budget
run_gate "G4 format lint" g4_format
run_gate "G5 server tests" g5_server
run_gate "G6 mac uploader tests" g6_mac_uploader
run_gate "G7 token lint" g7_token_lint
run_gate "G8 mac autoinstall tests" g8_mac_autoinstall

if [ "${#failed[@]}" -gt 0 ]; then
  printf 'gate-linux: FAILED:'
  printf ' [%s]' "${failed[@]}"
  printf '\n'
  exit 1
fi
echo "gate-linux: all gates passed"
