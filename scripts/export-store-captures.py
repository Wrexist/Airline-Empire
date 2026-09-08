"""Export native, unaltered STORE attachments and their provenance from xcresult."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

bundle, output = map(Path, sys.argv[1:3])
output.mkdir(parents=True, exist_ok=True)
records = []
with tempfile.TemporaryDirectory(prefix="ae-store-") as temporary:
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                    "--output-path", temporary], check=True)
    for manifest in Path(temporary).rglob("manifest.json"):
        for suite in json.loads(manifest.read_text()):
            for attachment in suite.get("attachments", []):
                name = attachment.get("suggestedHumanReadableName", "")
                source = manifest.parent / attachment.get("exportedFileName", "")
                if not name.startswith("STORE-") or not source.is_file():
                    continue
                # XCTest appends UUIDs; our storyboard key precedes the first underscore.
                target = output / (name.removeprefix("STORE-").split("_")[0] + ".png")
                shutil.copyfile(source, target)
                records.append({"file": target.name, "attachment": name,
                                "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
expected = {"01-network.png", "02-fleet.png", "02b-market.png", "03-route.png",
            "03b-routes.png", "04-finance.png", "05-rivals.png", "05b-world.png",
            "06-progression.png", "06b-briefing.png"}
found = {r["file"] for r in records}
if expected != found:
    raise SystemExit(f"Incomplete capture: missing={expected-found}, unexpected={found-expected}")
(output / "capture-manifest.json").write_text(json.dumps(records, indent=2) + "\n")
print(f"Exported {len(records)} native screenshots to {output}")
