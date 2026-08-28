# App resources

## `PrivacyInfo.xcprivacy`

Apple's privacy manifest, required for App Store submission. It declares no
tracking, no collected data and no required-reason API use — all three derived
from the code, not from a template. Read the comment inside it before changing
anything: if one of those three facts stops being true, the file changes in the
same commit as the code that changed it.

## `Assets.xcassets`

`AppIcon.appiconset/icon-1024.png` — 1024×1024, no alpha, full bleed.

**Provenance and processing.** Generated 2026-08-28 from the brief in
`docs/ASO.md` §6; the untouched render is kept at
`docs/design/icon-source-1254.png` so the crop is reproducible. It arrived at
1254×1254 **with a rounded-corner mask already applied**, which is a trap: iOS
applies its own mask to whatever you ship, so pre-rounded corners either show
as white wedges inside the mask or read as a double-rounded icon. The fix was
to crop to the largest square that sits fully inside that rounded rect —
78 px per side, which is `r · (1 − 1/√2)` for the measured ~253 px radius —
and then resize to 1024:

```python
from PIL import Image
im = Image.open('docs/design/icon-source-1254.png').convert('RGB')
w, h = im.size
im.crop((78, 78, w - 78, h - 78)).resize((1024, 1024), Image.LANCZOS) \
  .save('.../AppIcon.appiconset/icon-1024.png', optimize=True)
```

`node scripts/asc/check-app-icon.mjs` verifies the two things Apple rejects
uploads over: the dimensions and the alpha channel. It runs on the cheap
runner before any archive.

**One open question, worth testing rather than assuming.** This is a detailed,
photographic scene — a control tower, a terminal, an airliner, ground traffic.
That is a lot of information for a 60-point square, which is where an icon
actually lives. Before launch, look at it on a real home screen next to the
competition; if it reads as a smudge at that size, the answer is a simpler
crop (the tail and the nose alone) rather than a redraw. `docs/ASO.md` §6 has
the reasoning and the alternative directions.
