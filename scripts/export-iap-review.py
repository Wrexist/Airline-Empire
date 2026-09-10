"""Export unaltered paywall review captures from the launch-safety result."""
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
with tempfile.TemporaryDirectory(prefix="ae-iap-") as temporary:
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                    "--output-path", temporary], check=True)
    for manifest in Path(temporary).rglob("manifest.json"):
        for suite in json.loads(manifest.read_text()):
            for attachment in suite.get("attachments", []):
                name = attachment.get("suggestedHumanReadableName", "")
                source = manifest.parent / attachment.get("exportedFileName", "")
                if not name.startswith("IAP-") or not source.is_file():
                    continue
                target = output / (name.removeprefix("IAP-").split("_")[0] + ".png")
                shutil.copyfile(source, target)
                records.append({"file": target.name, "attachment": name,
                                "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
if {r["file"] for r in records} != {"weekly.png", "yearly.png", "lifetime.png"}:
    raise SystemExit("Missing one or more genuine Pro review captures")
(output / "manifest.json").write_text(json.dumps(records, indent=2) + "\n")
print(f"Exported {len(records)} unaltered paywall review captures")
