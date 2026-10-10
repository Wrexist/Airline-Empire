"""Pick the KEY-HUB-* attachments out of exported xcresult folders.

usage: collect.py <downloaded-artifacts-dir> <out-dir>
"""
import json
import os
import shutil
import sys

from PIL import Image

src, out = sys.argv[1], sys.argv[2]
for device in ("ipad", "iphone"):
    captures = os.path.join(src, f"hub-review-{device}", "captures")
    manifest = os.path.join(captures, "manifest.json")
    if not os.path.exists(manifest):
        print(f"{device}: no captures")
        continue
    dest = os.path.join(out, device)
    os.makedirs(dest, exist_ok=True)
    for test in json.load(open(manifest)):
        for a in test.get("attachments", []):
            name = a.get("suggestedHumanReadableName") or a["exportedFileName"]
            if not name.startswith("KEY-HUB"):
                continue
            key = name.split("_0_")[0].replace(" ", "_").removesuffix(".png")
            path = os.path.join(dest, key + ".png")
            shutil.copy(os.path.join(captures, a["exportedFileName"]), path)
            if device == "ipad":
                im = Image.open(path)
                if im.height > im.width:
                    im.rotate(90, expand=True).save(path)
    print(device, sorted(os.listdir(dest)))
