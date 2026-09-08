#!/usr/bin/env python3
"""Expose bounded UI checkpoints in CI logs; full images remain in xcresult."""
import base64
import json
from pathlib import Path
import subprocess
import sys
import tempfile

bundle = Path(sys.argv[1])
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
                if name.startswith(("KEY-", "FREE-")) and path.is_file():
                    pairs.append((name, path))
    for name, path in sorted(pairs)[:16]:
        small = path.with_name(path.name + ".small.png")
        subprocess.run(["sips", "-s", "format", "png", "--resampleWidth", "360",
                        str(path), "--out", str(small)], check=True, capture_output=True)
        data = base64.b64encode(small.read_bytes()).decode()
        print(f"===SHOT {name} {len(data)}")
        for offset in range(0, len(data), 500):
            print(data[offset:offset + 500])
        print("===ENDSHOT")
