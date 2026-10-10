"""Lay each Hub View render beside its reference frame.

usage: compare.py [captures-dir] [reference-dir] [out.jpg]
defaults: .hub-review/captures .hub-review/reference .hub-review/compare.jpg

Writes one stacked sheet plus compare_<shot>.jpg per shot. Read the images:
the comparison is visual, there is no pixel metric worth trusting here.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

caps = sys.argv[1] if len(sys.argv) > 1 else ".hub-review/captures"
refs = sys.argv[2] if len(sys.argv) > 2 else ".hub-review/reference"
out = sys.argv[3] if len(sys.argv) > 3 else ".hub-review/compare.jpg"
shots = [("Overview", "01-overview"), ("Gate turnaround", "02-gate"),
         ("Terminal cutaway", "03-terminal"), ("District", "04-district"),
         ("Night", "05-district-night")]
H = 520
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 28)
except OSError:
    font = ImageFont.load_default()
rows = []
for title, key in shots:
    ours_path = os.path.join(caps, "ipad", f"KEY-HUB-{key}.png")
    ref_path = os.path.join(refs, f"REF-HUB-{key}.png")
    if not (os.path.exists(ours_path) and os.path.exists(ref_path)):
        print("skip", key)
        continue
    ref = Image.open(ref_path).convert("RGB")
    ref = ref.resize((int(ref.width * H / ref.height), H), Image.LANCZOS)
    ours = Image.open(ours_path).convert("RGB")
    ours = ours.resize((int(ours.width * H / ours.height), H), Image.LANCZOS)
    row = Image.new("RGB", (ref.width + ours.width + 30, H + 50), "white")
    ImageDraw.Draw(row).text((10, 10), f"{title} - reference (left) vs Airline Empire (right)",
                             fill=(30, 40, 80), font=font)
    row.paste(ref, (0, 50))
    row.paste(ours, (ref.width + 30, 50))
    rows.append((key, row))
if not rows:
    sys.exit("nothing to compare")
W = max(r.width for _, r in rows)
sheet = Image.new("RGB", (W, sum(r.height for _, r in rows)), "white")
y = 0
for key, r in rows:
    sheet.paste(r, (0, y))
    y += r.height
    r.save(os.path.join(os.path.dirname(out) or ".", f"compare_{key}.jpg"), quality=85)
sheet.save(out, quality=85)
print(out, sheet.size)
