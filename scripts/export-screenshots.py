#!/usr/bin/env python3
"""Export the screenshots UI tests attached (XCTAttachment, lifetime keepAlways) from an
xcresult bundle into a flat folder of images named after each attachment, for the CI artifact.
Then check that every passing story's screenshot names were exported.

Usage: scripts/export-screenshots.py build/ios.xcresult build/screenshots
Exits 1 only when the export worked and a passing story's screenshot is missing.
"""

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUFFIX_RE = re.compile(r"_\d+_[0-9A-Fa-f-]{36}(?=\.\w+$)")


def main() -> int:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    bundle, out = Path(sys.argv[1]), Path(sys.argv[2])
    if not bundle.exists():
        print(f"export-screenshots: notice: {bundle} does not exist; nothing to export")
        return 0
    raw = out / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    run = subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path",
                          str(bundle), "--output-path", str(raw)], capture_output=True, text=True)
    manifest = raw / "manifest.json"
    if run.returncode != 0 or not manifest.exists():
        print("export-screenshots: notice: xcresulttool export failed; the xcresult artifact "
              "still holds the attachments\n" + run.stdout[-2000:] + run.stderr[-2000:])
        return 0
    exported: list[str] = []
    for test in json.loads(manifest.read_text()):
        for att in test.get("attachments", []):
            src = raw / att.get("exportedFileName", "")
            if not src.is_file():
                continue
            name = SUFFIX_RE.sub("", att.get("suggestedHumanReadableName") or src.name)
            dest = out / name
            n = 1
            while dest.exists():
                dest = out / f"{Path(name).stem}-{n}{Path(name).suffix}"
                n += 1
            shutil.copyfile(src, dest)
            exported.append(dest.name)
    print(f"export-screenshots: {len(exported)} attachments exported to {out}")
    for name in sorted(exported):
        print(f"  {name}")
    ledger = json.loads((ROOT / "features.json").read_text())
    missing = [f"{f['id']}: {s}" for f in ledger["features"]
               if f.get("kind") == "story" and f["passes"] for s in f["screenshots"]
               if not any(e == s or e.startswith(s + ".") or e.startswith(s + "_")
                          for e in exported)]
    if missing:
        print("export-screenshots: FAIL: passing stories without their screenshots: "
              + "; ".join(missing))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
