#!/usr/bin/env python3
"""Expose bounded UI checkpoints in CI logs; full images remain in xcresult."""
import base64
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

bundle = Path(sys.argv[1])
output = Path(sys.argv[2]) if len(sys.argv) > 2 else None
if output:
    output.mkdir(parents=True, exist_ok=True)
if not bundle.is_dir():
    raise SystemExit("No result bundle was produced")
with tempfile.TemporaryDirectory(prefix="ae-checkpoints-") as directory:
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                    "--output-path", directory], check=True)
    pairs = []
    for manifest in Path(directory).rglob("manifest.json"):
        for suite in json.loads(manifest.read_text()):
            for attachment in suite.get("attachments", []):
                name = attachment.get("suggestedHumanReadableName", "")
                path = manifest.parent / attachment.get("exportedFileName", "")
                if name.startswith(("KEY-", "FREE-", "AX-COMPONENT-")) and path.is_file():
                    pairs.append((name, path))
    if output:
        records = []
        for index, (name, path) in enumerate(sorted(pairs)):
            target = output / f"{index:03d}-{Path(name).name}.png"
            shutil.copyfile(path, target)
            records.append({"file": target.name, "attachment": name,
                            "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
        (output / "manifest.json").write_text(json.dumps(records, indent=2) + "\n")
        print(f"Retained {len(records)} unaltered native review captures")
    for name, path in sorted((n, p) for n, p in pairs if not n.startswith("AX-COMPONENT-"))[:16]:
        small = path.with_name(path.name + ".small.png")
        subprocess.run(["sips", "-s", "format", "png", "--resampleWidth", "360",
                        str(path), "--out", str(small)], check=True, capture_output=True)
        data = base64.b64encode(small.read_bytes()).decode()
        print(f"===SHOT {name} {len(data)}")
        for offset in range(0, len(data), 500):
            print(data[offset:offset + 500])
        print("===ENDSHOT")
