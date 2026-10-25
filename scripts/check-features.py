#!/usr/bin/env python3
"""Feature ledger gate (G2), and the only sanctioned way to flip an entry to passing.

features.json (schema 2) holds two kinds of entries:
  engine  F-xxx  core logic, judged by unit tests (F-001 to F-010, built first).
  story   S-xxx  something Isaac does in the app, judged by a UI test that drives its steps
                 on the simulator and saves the named screenshots.

Gate mode:  scripts/check-features.py --base origin/main
  main:      validates the schema only.
  infra/*:   may restructure the ledger; validates the schema only.
  any other branch (a card, wt/F-xxx or wt/S-xxx): compares features.json with the merge
             base. Only the card's entry may change, and only its "passes" field. passes:true
             needs every listed test and screenshot name to exist.

Flip mode:  scripts/check-features.py --flip S-004 [--approved]
  Checks that every depends_on story already passes, that every listed test exists, runs the
  StezuCoreTests ones with swift test, and checks that every screenshot name appears in
  App/UITests. AppTests and AppUITests run in the required ios CI job, not here. Engine
  entries with needs_approval need --approved, given only after Isaac approves.

Ready mode: scripts/check-features.py --ready
  Lists stories that do not pass yet and whose depends_on all pass: tonight's candidates.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def git_root() -> Path:
    here = Path(__file__).resolve().parent
    out = subprocess.run(["git", "-C", str(here), "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("check-features: FAIL: not inside a git checkout")
    return Path(out.stdout.strip())


ROOT = git_root()
LEDGER = "features.json"
SCHEMA = 2
ENGINE_FIELDS = {"id": str, "kind": str, "title": str, "area": str, "needs_approval": bool,
                 "passes": bool, "steps": list, "tests": list}
STORY_FIELDS = {"id": str, "kind": str, "area": str, "title": str, "steps": list,
                "tap_budget": str, "depends_on": list, "core_tests": list, "ui_tests": list,
                "screenshots": list, "needs_server": bool, "passes": bool}
ENGINE_ID_RE = re.compile(r"^F-\d{3}$")
STORY_ID_RE = re.compile(r"^S-\d{3}$")
STORY_AREAS = ("shell", "workout", "food", "data")
TEST_RE = re.compile(r"^(StezuCoreTests|AppTests|AppUITests)\.([A-Za-z_]\w*)/(test\w*)$")
SHOT_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
TEST_DIRS = {"StezuCoreTests": ROOT / "Packages/StezuCore/Tests/StezuCoreTests",
             "AppTests": ROOT / "App/Tests",
             "AppUITests": ROOT / "App/UITests"}
BRANCH_RE = re.compile(r"(?:^|/)wt/([FS]-\d{3})\b")


def fail(msg: str) -> None:
    print(f"check-features: FAIL: {msg}")
    sys.exit(1)


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)


def check_tests(where: str, tests, targets: tuple[str, ...], errs: list[str]) -> None:
    for t in tests:
        m = TEST_RE.match(t) if isinstance(t, str) else None
        if not m or m.group(1) not in targets:
            errs.append(f"{where}: test {t!r} must look like "
                        f"{'|'.join(targets)}.Class/testMethod")


def validate_engine(f: dict, errs: list[str]) -> None:
    where = f["id"]
    if not ENGINE_ID_RE.match(f["id"]):
        errs.append(f"{where}: engine id must look like F-001")
    if f["area"] not in ("core", "app"):
        errs.append(f"{where}: engine area must be core or app")
    if not f["tests"]:
        errs.append(f"{where}: tests must not be empty")
    check_tests(where, f["tests"], ("StezuCoreTests", "AppTests"), errs)


def validate_story(f: dict, story_ids_before: list[str], errs: list[str]) -> None:
    where = f["id"]
    if not STORY_ID_RE.match(f["id"]):
        errs.append(f"{where}: story id must look like S-001")
    if f["area"] not in STORY_AREAS:
        errs.append(f"{where}: story area must be one of {STORY_AREAS}")
    if not f["tap_budget"].strip():
        errs.append(f"{where}: empty tap_budget")
    for d in f["depends_on"]:
        if d not in story_ids_before:
            errs.append(f"{where}: depends_on {d!r} must be a story listed earlier")
    check_tests(where, f["core_tests"], ("StezuCoreTests", "AppTests"), errs)
    if not f["ui_tests"]:
        errs.append(f"{where}: every story has a screen, so ui_tests must not be empty")
    check_tests(where, f["ui_tests"], ("AppUITests",), errs)
    if not f["screenshots"]:
        errs.append(f"{where}: screenshots must not be empty")
    for s in f["screenshots"]:
        if not isinstance(s, str) or not SHOT_RE.match(s):
            errs.append(f"{where}: screenshot {s!r} must be lowercase letters, digits and -")


def validate(doc) -> list[str]:
    errs: list[str] = []
    if not isinstance(doc, dict) or set(doc) != {"schema", "features"}:
        return ['top level must be an object with exactly "schema" and "features"']
    if doc["schema"] != SCHEMA:
        return [f"schema must be {SCHEMA} (rebase on origin/main if your branch is older)"]
    feats = doc["features"]
    if not isinstance(feats, list) or not feats:
        return ["features must be a non-empty list"]
    seen: set[str] = set()
    shots: set[str] = set()
    stories: list[str] = []
    for i, f in enumerate(feats):
        where = f"features[{i}]"
        if not isinstance(f, dict) or f.get("kind") not in ("engine", "story"):
            errs.append(f'{where} must be an object with "kind" engine or story')
            continue
        fields = ENGINE_FIELDS if f["kind"] == "engine" else STORY_FIELDS
        if set(f) != set(fields):
            errs.append(f"{where} ({f['kind']}) fields must be exactly {sorted(fields)}")
            continue
        bad = [k for k, typ in fields.items() if not isinstance(f[k], typ)]
        if bad:
            errs.append(f"{where}: wrong types for {bad}")
            continue
        if f["id"] in seen:
            errs.append(f"{f['id']}: duplicate id")
        seen.add(f["id"])
        if not f["title"].strip():
            errs.append(f"{f['id']}: empty title")
        if not f["steps"] or not all(isinstance(s, str) and s.strip() for s in f["steps"]):
            errs.append(f"{f['id']}: steps must be non-empty strings")
        if f["kind"] == "engine":
            validate_engine(f, errs)
        else:
            validate_story(f, stories, errs)
            for s in f["screenshots"]:
                if s in shots:
                    errs.append(f"{f['id']}: screenshot name {s!r} is used twice")
                shots.add(s)
            stories.append(f["id"])
    return errs


def load(text: str, label: str) -> dict:
    try:
        doc = json.loads(text)
    except json.JSONDecodeError as e:
        fail(f"{label} is not valid JSON: {e}")
    errs = validate(doc)
    if errs:
        fail(f"{label} schema: " + "; ".join(errs))
    return doc


def test_exists(name: str) -> bool:
    target, cls, method = TEST_RE.match(name).groups()
    cls_re = re.compile(rf"\b(class|extension)\s+{cls}\b")
    fn_re = re.compile(rf"\bfunc\s+{method}\s*\(")
    for path in TEST_DIRS[target].rglob("*.swift"):
        text = path.read_text(encoding="utf-8", errors="replace")
        if cls_re.search(text) and fn_re.search(text):
            return True
    return False


def ui_sources() -> str:
    return "\n".join(p.read_text(encoding="utf-8", errors="replace")
                     for p in TEST_DIRS["AppUITests"].rglob("*.swift"))


def all_tests(f: dict) -> list[str]:
    return f["tests"] if f["kind"] == "engine" else f["core_tests"] + f["ui_tests"]


def missing_evidence(f: dict) -> list[str]:
    """Tests and screenshot names that a passing entry needs but that do not exist."""
    missing = [t for t in all_tests(f) if not test_exists(t)]
    if f["kind"] == "story":
        src = ui_sources()
        missing += [f"screenshot {s!r} (no \"{s}\" literal in App/UITests)"
                    for s in f["screenshots"] if f'"{s}"' not in src]
    return missing


def current_branch() -> str:
    if os.environ.get("GITHUB_HEAD_REF"):
        return os.environ["GITHUB_HEAD_REF"]
    ref = os.environ.get("GITHUB_REF", "")
    if ref.startswith("refs/heads/"):
        return ref[len("refs/heads/"):]
    sym = git("symbolic-ref", "--short", "-q", "HEAD")  # works on an unborn branch too
    if sym.returncode == 0:
        return sym.stdout.strip()
    return git("rev-parse", "--abbrev-ref", "HEAD").stdout.strip()


def card_feature(branch: str) -> str | None:
    if os.environ.get("FEATURE_ID"):
        return os.environ["FEATURE_ID"]
    m = BRANCH_RE.search(branch)
    return m.group(1) if m else None


def gate(base: str) -> None:
    head = load((ROOT / LEDGER).read_text(encoding="utf-8"), LEDGER)
    branch = current_branch()
    counts = {k: sum(f["kind"] == k for f in head["features"]) for k in ("engine", "story")}
    if branch == "main":
        print(f"check-features: OK (main: schema only, {counts['engine']} engine entries, "
              f"{counts['story']} stories)")
        return
    if branch.startswith("infra/"):
        print(f"check-features: OK (infra branch: schema only, {counts['engine']} engine "
              f"entries, {counts['story']} stories)")
        return
    if git("rev-parse", "--verify", "--quiet", f"{base}^{{commit}}").returncode != 0:
        fail(f"base {base} not found (fetch full history)")
    mb = git("merge-base", base, "HEAD").stdout.strip()
    shown = git("show", f"{mb}:{LEDGER}")
    if shown.returncode != 0:
        fail(f"{LEDGER} is missing at the merge base")
    old = {f["id"]: f for f in load(shown.stdout, f"{LEDGER} at merge base")["features"]}
    new = {f["id"]: f for f in head["features"]}
    if set(old) != set(new):
        fail(f"entries added or removed: {sorted(set(old) ^ set(new))}; only main or an "
             "infra/* branch may do that")
    changed = sorted(i for i in new if new[i] != old[i])
    if not changed:
        print("check-features: OK (no entry changed)")
        return
    if len(changed) > 1:
        fail(f"more than one entry changed: {changed}")
    fid = card_feature(branch)
    if fid is None:
        fail(f"{changed[0]} changed, but there is no FEATURE_ID and the branch is not "
             "wt/F-xxx or wt/S-xxx")
    if changed[0] != fid:
        fail(f"{changed[0]} changed, but this card is {fid}")
    fields = sorted(k for k in new[fid] if new[fid][k] != old[fid][k])
    if fields != ["passes"]:
        fail(f"{fid}: only 'passes' may change, but {fields} changed")
    if new[fid]["passes"]:
        missing = missing_evidence(new[fid])
        if missing:
            fail(f"{fid} passes:true but these do not exist: {missing}")
    print(f"check-features: OK ({fid} passes -> {new[fid]['passes']})")


def run_core_tests(tests: list[str]) -> None:
    core = [t for t in tests if t.startswith("StezuCoreTests.")]
    if not core:
        return
    cmd = ["swift", "test"]
    for t in core:
        cmd += ["--filter", f"^{re.escape(t)}$"]
    run = subprocess.run(cmd, cwd=ROOT / "Packages/StezuCore", capture_output=True, text=True)
    out = run.stdout + run.stderr
    if run.returncode != 0:
        print(out[-4000:])
        fail("swift test failed")
    for t in core:
        _, cls, method = TEST_RE.match(t).groups()
        if not re.search(rf"{cls}[ .]{method}\]?' passed", out):
            print(out[-4000:])
            fail(f"{t} did not run and pass")


def flip(fid: str, approved: bool) -> None:
    path = ROOT / LEDGER
    doc = load(path.read_text(encoding="utf-8"), LEDGER)
    by_id = {f["id"]: f for f in doc["features"]}
    feat = by_id.get(fid)
    if feat is None:
        fail(f"no entry {fid}")
    card = card_feature(current_branch())
    if card and card != fid:
        fail(f"this card is {card}, not {fid}")
    if feat["kind"] == "engine" and feat["needs_approval"] and not approved:
        fail(f"{fid} needs approval; pass --approved only after Isaac approves it")
    if feat["kind"] == "story":
        waiting = [d for d in feat["depends_on"] if not by_id[d]["passes"]]
        if waiting:
            fail(f"{fid} depends on stories that do not pass yet: {waiting}")
    missing = missing_evidence(feat)
    if missing:
        fail(f"these do not exist: {missing}")
    run_core_tests(all_tests(feat))
    others = [t for t in all_tests(feat) if not t.startswith("StezuCoreTests.")]
    if others:
        print(f"check-features: note: {len(others)} AppTests/AppUITests exist; the required "
              "ios CI job runs them")
    feat["passes"] = True
    path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    print(f"check-features: {fid} passes -> true")


def ready() -> None:
    doc = load((ROOT / LEDGER).read_text(encoding="utf-8"), LEDGER)
    by_id = {f["id"]: f for f in doc["features"]}
    for f in doc["features"]:
        if f["kind"] == "story" and not f["passes"] and \
                all(by_id[d]["passes"] for d in f["depends_on"]):
            print(f"{f['id']}  [{f['area']}]  {f['title']}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--flip", metavar="ID")
    ap.add_argument("--approved", action="store_true")
    ap.add_argument("--ready", action="store_true")
    args = ap.parse_args()
    if args.flip:
        flip(args.flip, args.approved)
    elif args.ready:
        ready()
    else:
        gate(args.base)


if __name__ == "__main__":
    main()
