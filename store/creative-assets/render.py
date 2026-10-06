#!/usr/bin/env python3
"""Renders the App Store creative assets (Header and Search Results).

  header.png          3840 x 1646 (21:9)  product page header
  search-results.png  3840 x 2560 (3:2)   search results asset

No words, logos or prices in either image: the App Store lays the app icon,
name and Get button over and beside them, and text-free art works in every
locale. Both are cut from the listing's existing text-free key art
(store/artwork/cinematic, decorative and labelled as such in prompts.json).

That art is 1536 x 1024, so it is first upscaled 4x with Real-ESRGAN x4plus
(ONNX, CPU) and then resampled down to Apple's canvas, which keeps edges
crisp instead of stretching pixels 2.5x.

  python3 -m venv .venv && .venv/bin/pip install onnxruntime numpy pillow huggingface_hub
  .venv/bin/python store/creative-assets/render.py [cache-dir]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

HERE = Path(__file__).resolve().parent
ART = HERE.parent / "artwork" / "cinematic"
CACHE = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/ae-creative-cache")


def upscale(name):
    """Real-ESRGAN x4 in overlapping 64 px tiles; cached between runs."""
    out_path = CACHE / f"{name}@4x.png"
    if out_path.exists():
        return Image.open(out_path).convert("RGB")
    import onnxruntime as ort
    from huggingface_hub import hf_hub_download

    model = hf_hub_download("imgdesignart/realesrgan-x4-onnx", "onnx/model.onnx")
    sess = ort.InferenceSession(model, providers=["CPUExecutionProvider"])
    img = np.asarray(Image.open(ART / f"{name}.png").convert("RGB"), np.float32) / 255
    h, w, _ = img.shape
    tile, lap = 64, 12
    step = tile - 2 * lap
    pad = np.pad(img, ((lap, lap + tile), (lap, lap + tile), (0, 0)), mode="reflect")
    out = np.zeros((h * 4, w * 4, 3), np.float32)
    for y in range(0, h, step):
        for x in range(0, w, step):
            t = np.ascontiguousarray(pad[y:y + tile, x:x + tile].transpose(2, 0, 1)[None])
            r = sess.run(None, {"input.1": t})[0][0].transpose(1, 2, 0)
            core = r[lap * 4:(lap + step) * 4, lap * 4:(lap + step) * 4]
            ch, cw = min(step, h - y) * 4, min(step, w - x) * 4
            out[y * 4:y * 4 + ch, x * 4:x * 4 + cw] = core[:ch, :cw]
    CACHE.mkdir(parents=True, exist_ok=True)
    result = Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8))
    result.save(out_path)
    return result


def shade(img, top, bottom):
    """Navy gradients at the top (nav buttons, status bar) and bottom (where
    the App Store sets the app name and Get button), so its UI stays legible."""
    w, h = img.size
    navy = np.array([10, 18, 36], np.float32)
    ys = np.linspace(0, 1, h)[:, None, None]
    a = top[1] * np.clip(1 - ys / top[0], 0, 1) ** 2
    a = a + bottom[1] * np.clip((ys - (1 - bottom[0])) / bottom[0], 0, 1) ** 2
    px = np.asarray(img, np.float32)
    px = px * (1 - a) + navy * a
    return Image.fromarray(np.clip(px + 0.5, 0, 255).astype(np.uint8))


def render(name, box, size, top, bottom, out):
    """box is (left, top, right, bottom) in the 1536 x 1024 source."""
    big = upscale(name)
    crop = big.crop(tuple(v * 4 for v in box)).resize(size, Image.LANCZOS)
    crop = crop.filter(ImageFilter.UnsharpMask(radius=2, percent=40, threshold=2))
    img = shade(crop, top, bottom)
    img.save(HERE / out, optimize=True)  # RGB, no alpha: Apple wants opaque
    print(f"✓ {out} {img.size[0]}x{img.size[1]}")


# Header: the jet climbing toward the dawn, centred in the 21:9 band. The
# fuselage and tail sit well inside the centred art-safe area (x 520-3320).
render("06-progression", (0, 262, 1536, 920), (3840, 1646),
       top=(0.22, 0.35), bottom=(0.30, 0.45), out="header.png")

# Search results: the full 3:2 frame of the jet over the clouds at sunset,
# aircraft centred, sky above and clouds below left calm for the overlay.
render("01-network", (0, 0, 1536, 1024), (3840, 2560),
       top=(0.18, 0.25), bottom=(0.28, 0.50), out="search-results.png")
