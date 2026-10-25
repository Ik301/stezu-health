#!/usr/bin/env python3
"""Feature ledger gate (G2), and the only sanctioned way to flip a feature to passing.

Gate mode:  scripts/check-features.py --base origin/main
  On main: validates the schema only. On a branch: compares features.json with the
  merge base. Only the entry for $FEATURE_ID (or the wt/F-xxx branch) may change, and
  only its "passes" field. passes:true requires every listed test to exist.

Flip mode:  scripts/check-features.py --flip F-001 [--approved]
  Checks that every listed test exists, runs the StezuCoreTests ones with swift test,
  and sets "passes": true. AppTests are only checked for existence here; the ios CI job
  runs them. Features with needs_approval need --approved, given only after Isaac approves.
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
FIELDS = {"id": str, "title": str, "area": str, "needs_approval": bool, "passes": bool,
          "steps": list, "tests": list}
ID_RE = re.compile(r"^F-\d{3}$")
TEST_RE = re.compile(r"^(StezuCoreTests|AppTests)\.([A-Za-z_]\w*)/(test\w*)$")
TEST_DIRS = {"StezuCoreTests": ROOT / "Packages/StezuCore/Tests/StezuCoreTests",
             "AppTests": ROOT / "App/Tests"}
BRANCH_RE = re.compile(r"(?:^|/)wt/(F-\d{3})\b")


def fail(msg: str) -> None:
    print(f"check-features: FAIL: {msg}")
    sys.exit(1)


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)


def validate(doc) -> list[str]:
    errs = []
    if not isinstance(doc, dict) or set(doc) != {"schema", "features"}:
        return ['top level must be an object with exactly "schema" and "features"']
    if doc["schema"] != 1:
        errs.append("schema must be 1")
    feats = doc["features"]
    if not isinstance(feats, list) or not feats:
        return errs + ["features must be a non-empty list"]
    seen = set()
    for i, f in enumerate(feats):
        where = f"features[{i}]"
        if not isinstance(f, dict):
            errs.append(f"{where} must be an object")
            continue
        if set(f) != set(FIELDS):
            errs.append(f"{where} fields must be exactly {sorted(FIELDS)}")
            continue
        for key, typ in FIELDS.items():
            if not isinstance(f[key], typ):
                errs.append(f"{where}.{key} must be {typ.__name__}")
        if errs:
            continue
        where = f["id"]
        if not ID_RE.match(f["id"]):
            errs.append(f"{where}: id must look like F-001")
        if f["id"] in seen:
            errs.append(f"{where}: duplicate id")
        seen.add(f["id"])
        if not f["title"].strip():
            errs.append(f"{where}: empty title")
        if f["area"] not in ("core", "app"):
            errs.append(f"{where}: area must be core or app")
        if not f["steps"] or not all(isinstance(s, str) and s.strip() for s in f["steps"]):
            errs.append(f"{where}: steps must be non-empty strings")
        if not f["tests"]:
            errs.append(f"{where}: tests must not be empty")
        for t in f["tests"]:
            if not isinstance(t, str) or not TEST_RE.match(t):
                errs.append(f"{where}: test {t!r} must look like StezuCoreTests.Class/testMethod")
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
    if branch == "main":
        print(f"check-features: OK (main: schema only, {len(head['features'])} features)")
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
        fail(f"features added or removed: {sorted(set(old) ^ set(new))}; only main may do that")
    changed = sorted(i for i in new if new[i] != old[i])
    if not changed:
        print("check-features: OK (no feature changed)")
        return
    if len(changed) > 1:
        fail(f"more than one feature changed: {changed}")
    fid = card_feature(branch)
    if fid is None:
        fail(f"{changed[0]} changed, but there is no FEATURE_ID and the branch is not wt/F-xxx")
    if changed[0] != fid:
        fail(f"{changed[0]} changed, but this card is {fid}")
    fields = sorted(k for k in new[fid] if new[fid][k] != old[fid][k])
    if fields != ["passes"]:
        fail(f"{fid}: only 'passes' may change, but {fields} changed")
    if new[fid]["passes"]:
        missing = [t for t in new[fid]["tests"] if not test_exists(t)]
        if missing:
            fail(f"{fid} passes:true but these tests do not exist: {missing}")
    print(f"check-features: OK ({fid} passes -> {new[fid]['passes']})")


def flip(fid: str, approved: bool) -> None:
    path = ROOT / LEDGER
    doc = load(path.read_text(encoding="utf-8"), LEDGER)
    feat = next((f for f in doc["features"] if f["id"] == fid), None)
    if feat is None:
        fail(f"no feature {fid}")
    card = card_feature(current_branch())
    if card and card != fid:
        fail(f"this card is {card}, not {fid}")
    if feat["needs_approval"] and not approved:
        fail(f"{fid} needs approval; pass --approved only after Isaac approves it")
    missing = [t for t in feat["tests"] if not test_exists(t)]
    if missing:
        fail(f"tests do not exist: {missing}")
    core = [t for t in feat["tests"] if t.startswith("StezuCoreTests.")]
    if core:
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
    apps = [t for t in feat["tests"] if t.startswith("AppTests.")]
    if apps:
        print(f"check-features: note: {len(apps)} AppTests exist; the ios CI job runs them")
    feat["passes"] = True
    path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    print(f"check-features: {fid} passes -> true")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--flip", metavar="F-xxx")
    ap.add_argument("--approved", action="store_true")
    args = ap.parse_args()
    if args.flip:
        flip(args.flip, args.approved)
    else:
        gate(args.base)


if __name__ == "__main__":
    main()
