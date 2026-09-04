# AI asset prompts

**15 prompts, one per image.** Each one is numbered, says exactly what it makes,
where the file goes and what to call it, and is **complete on its own** — copy
the whole grey block, paste it into the model, done. Nothing to assemble, no
style block to paste in from elsewhere.

Written for **conversational image models** — ChatGPT / DALL·E, Gemini / Nano
Banana. No `--ar` flags or weighted tokens anywhere: framing, aspect and
exclusions are plain sentences, because that is what these models read.

---

## How to use this file

1. Find your asset in the index below.
2. Go to that numbered prompt. Copy the **entire** grey block.
3. Paste it into the model. Change nothing.
4. Save the result under **exactly** the filename shown. Filenames are matched
   literally by `Contents.json`, `upload-screenshots.mjs` and the CI validator
   — they are not suggestions.
5. Put it in **exactly** the folder shown.
6. Run the check underneath the prompt. If it fails, fix it before moving on.

All paths are from the repository root — the folder holding `AirlineEmpireApp/`
and `docs/`. Make the three new folders once, before you start:

```bash
mkdir -p docs/design/aircraft docs/design/store docs/design/illustrations
```

---

## Index — all 15 prompts

| # | What it makes | Save as | Folder | Size | Alpha |
| --- | --- | --- | --- | --- | :---: |
| **01** | Turboprop planform | `turboprop.png` | `docs/design/aircraft/` | 2048² | yes |
| **02** | Regional jet planform | `regional-jet.png` | `docs/design/aircraft/` | 2048² | yes |
| **03** | Narrowbody planform | `narrowbody.png` | `docs/design/aircraft/` | 2048² | yes |
| **04** | Widebody planform | `widebody.png` | `docs/design/aircraft/` | 2048² | yes |
| **05** | Screenshot canvas, iPhone | `canvas-iphone.png` | `docs/design/store/` | 1320 × 2868 | no |
| **06** | Screenshot canvas, iPad | `canvas-ipad.png` | `docs/design/store/` | 2064 × 2752 | no |
| **07** | Key art / feature graphic | `key-art.png` | `docs/design/store/` | 1920 × 1080 | no |
| **08** | Website cover **+ favicon** | `cover.png` | `site/assets/` | 1200 × 1200 | no |
| **09** | App icon (only for an A/B) | `icon-1024.png` | `AirlineEmpireApp/Resources/Assets.xcassets/AppIcon.appiconset/` | 1024² | **no** |
| **10** | Empty state — fleet | `empty-fleet.png` | `docs/design/illustrations/` | 2048² | yes |
| **11** | Empty state — routes | `empty-routes.png` | `docs/design/illustrations/` | 2048² | yes |
| **12** | Empty state — search | `empty-search.png` | `docs/design/illustrations/` | 2048² | yes |
| **13** | Empty state — route closed | `empty-route-closed.png` | `docs/design/illustrations/` | 2048² | yes |
| **14** | Empty state — calm skies | `empty-calm-skies.png` | `docs/design/illustrations/` | 2048² | yes |
| **15** | Empty state — no rivals | `empty-no-rivals.png` | `docs/design/illustrations/` | 2048² | yes |

**The six App Store screenshots are not in this list on purpose.** They are
screen captures from a real mid-game world, never generated — see the rules
below. Prompts 05 and 06 make the *backdrop* they sit on. Where the finished
files go is §B at the end.

---

## The four rules

**1 · Two visual languages, never mixed.** Inside the app everything is *flat*:
solid fill, no stroke, no gradient, no shadow, no internal detail, readable at
10 pixels. On the store and the icon everything is *painterly*: dusk, cloud,
warm light on metal. Prompts 01–04 and 10–15 are flat. Prompts 05–09 are
painterly. Never swap them.

**2 · Nothing real, ever.** Every prompt below already contains an exclusion
paragraph. Do not delete it. If a result comes back with a recognisable tail
logo, a real manufacturer's wing, or a registration on the fuselage, **throw it
away and regenerate** — do not retouch it out. A retouched real aircraft is
still a real aircraft, and `docs/ASSET_PROVENANCE.md` claims on this project's
behalf that nothing here references a real aircraft, airline or airport.

**3 · Screenshots are captured, not generated.** `docs/ASO.md` §5: *"No fake
UI, no invented numbers, no screens the app does not have. A screenshot is a
claim."* If a model offers you a convincing app screen, you cannot use it.

**4 · Alpha matters, in both directions.** Prompts 01–04 and 10–15 **must** have
a transparent background — the app tints those shapes at runtime and a baked-in
white background makes that impossible. Prompt 09 (the icon) **must not** have
alpha — Apple rejects it. The checks below catch both.

---

## The palette

Give the model hex, never colour names — "deep blue" gets you six different
blues across six generations. These are read from `AirlineEmpireApp/Sources/DesignSystem/Theme.swift`.

| Use | Hex |
| --- | --- |
| Accent / azure — the interactive blue, and the player's own livery | `#3D82EB` |
| Ember — warm light, the tail mark | `#F2A83B` |
| Fuselage white | `#F4F6FA` |
| Dusk sky, top of frame | `#0A1224` |
| Dusk sky, at the horizon | `#1A2138` |
| Map background | `#0B101B` |
| Map land | `#212B3C` |

The eight airline liveries, if a prompt needs more than one carrier in shot:
`azure #3D82EB` · `ember #F28C33` · `jade #29B37A` · `crimson #DE3D52` ·
`violet #8F5CDE` · `slate #7D8FA6` · `gold #DBB333` · `teal #299EAD`

---
---

# Prompts 01–04 · Aircraft

**This is the one real visual gap in the product** — `docs/ASSET_INVENTORY.md`
§5 says so plainly; everything else in the app is already solved in code.

You are making **four shapes, not fourteen aircraft.** The catalog's six
categories collapse onto four planforms, and two pairs share deliberately:

| Catalog category | Uses prompt | Types in the game |
| --- | --- | --- |
| `turboprop` | **01** | NA70 (68 seats), KT72 (74) |
| `regionalJet` | **02** | AV90 (88), KT95 (95) |
| `narrowbody` | **03** | NA160 (162), MR180 (180), PA184 (184) |
| `largeNarrowbody` | **03** — same shape | MR220 (221), PA228 (228) |
| `widebody` | **04** | PA290 (288), MR300 (298), AV310 (310) |
| `largeWidebody` | **04** — same shape | MR410 (408), AV420 (422) |

At map scale a narrowbody and a large narrowbody are the same object — the
difference is 40 seats, which has no silhouette. Do not generate a fifth shape
to fix that; it is tracked as TD-014 and the fix is a scale factor, not new art.

**Generate 03 first.** It is the whole startup-era fleet and the first shape a
new player ever sees, and the other three are easier once you have its
proportions to match.

---

## PROMPT 01 — Turboprop planform

> **Save as** `turboprop.png` → **`docs/design/aircraft/`** · 2048 × 2048 · transparent background

```
A flat top-down plan-view silhouette of a generic twin-engine regional
turboprop airliner, seen from directly above.

SHAPE: A slender straight fuselage roughly 7 times longer than it is wide. A
high, straight, unswept wing of constant chord, spanning slightly wider than
the fuselage is long, mounted about 40% of the way back from the nose. One
engine nacelle on each wing, set about a third of the way out from the
fuselage, each with a blunt rounded propeller spinner projecting forward of the
wing leading edge — draw each propeller as a simple solid circular disc centred
on its spinner, which is how a spinning prop reads from above. At the very
back, a conventional tail: one horizontal tailplane about 40% of the main
wing's span, with the vertical fin reading from directly above only as a narrow
solid spine along the centre line. The nose is rounded and blunt.

STYLE: Pure top-down orthographic plan view, camera directly overhead, no
perspective, no tilt, no vanishing point. The aircraft is a single solid
silhouette in one flat colour (#3D82EB) on a fully transparent background.
Absolutely flat: no gradient, no shading, no highlight, no drop shadow, no
ambient occlusion, no reflection, and no outline or stroke of any kind. No
internal detail whatsoever — no windows, no doors, no cockpit glazing, no
engine cowl lines, no panel lines, no registration, no text, no numbers. The
shape must still read correctly when scaled down to 10 pixels tall, so every
feature is chunky and unambiguous; omit thin spars, antennae and pitot tubes
rather than drawing them thin.

FRAMING: Nose points to the top of the frame. The aircraft is perfectly
vertical and bilaterally symmetrical about the vertical centre line, centred
with even margins. Square canvas, 2048 x 2048 pixels, transparent background.

MUST NOT CONTAIN: any real aircraft's outline, any manufacturer's design
language, any airline livery, logo, roundel, flag, registration or text of any
kind. This is a generic fictional planform, not a depiction of an existing
aeroplane.
```

---

## PROMPT 02 — Regional jet planform

> **Save as** `regional-jet.png` → **`docs/design/aircraft/`** · 2048 × 2048 · transparent background

```
A flat top-down plan-view silhouette of a generic regional jet airliner, seen
from directly above.

SHAPE: A slim fuselage roughly 9 times longer than it is wide, noticeably more
slender than a mainline airliner. A low wing with a modest sweep of about 20
degrees, spanning a little less than the fuselage length, mounted just behind
the midpoint. The engines are mounted on the REAR FUSELAGE, not on the wings:
two short rounded nacelles sitting either side of the fuselage close to the
tail, so the wing itself is completely clean with nothing hanging beneath it. A
T-tail: the horizontal tailplane sits at the top of the fin, so from directly
above it reads as a clean horizontal bar crossing the extreme rear of the
fuselage, about 35% of the main wing's span. The nose is pointed and tapered.

STYLE: Pure top-down orthographic plan view, camera directly overhead, no
perspective, no tilt, no vanishing point. The aircraft is a single solid
silhouette in one flat colour (#3D82EB) on a fully transparent background.
Absolutely flat: no gradient, no shading, no highlight, no drop shadow, no
ambient occlusion, no reflection, and no outline or stroke of any kind. No
internal detail whatsoever — no windows, no doors, no cockpit glazing, no
engine cowl lines, no panel lines, no registration, no text, no numbers. The
shape must still read correctly when scaled down to 10 pixels tall, so every
feature is chunky and unambiguous; omit thin spars, antennae and pitot tubes
rather than drawing them thin.

FRAMING: Nose points to the top of the frame. The aircraft is perfectly
vertical and bilaterally symmetrical about the vertical centre line, centred
with even margins. Square canvas, 2048 x 2048 pixels, transparent background.

MUST NOT CONTAIN: any real aircraft's outline, any manufacturer's design
language, any airline livery, logo, roundel, flag, registration or text of any
kind. This is a generic fictional planform, not a depiction of an existing
aeroplane.
```

---

## PROMPT 03 — Narrowbody planform · **generate this one first**

> **Save as** `narrowbody.png` → **`docs/design/aircraft/`** · 2048 × 2048 · transparent background

```
A flat top-down plan-view silhouette of a generic single-aisle narrowbody
airliner, seen from directly above.

SHAPE: A clean tubular fuselage roughly 10 times longer than it is wide. A low
wing swept back about 25 degrees, spanning slightly less than the fuselage
length, mounted just aft of the midpoint, tapering from a broad root to a
narrower tip with a small squared-off wingtip. One engine under each wing,
mounted about 35% of the way out from the fuselage and set forward of the wing
leading edge so each nacelle clearly projects ahead of the wing — each is a
plain rounded capsule. At the extreme rear, a conventional tail: one horizontal
tailplane swept to match the wing, about 35% of the main wing's span, with the
vertical fin reading from above as a narrow solid spine on the centre line
between the tailplanes. The nose is a smooth rounded cone.

STYLE: Pure top-down orthographic plan view, camera directly overhead, no
perspective, no tilt, no vanishing point. The aircraft is a single solid
silhouette in one flat colour (#3D82EB) on a fully transparent background.
Absolutely flat: no gradient, no shading, no highlight, no drop shadow, no
ambient occlusion, no reflection, and no outline or stroke of any kind. No
internal detail whatsoever — no windows, no doors, no cockpit glazing, no
engine cowl lines, no panel lines, no registration, no text, no numbers. The
shape must still read correctly when scaled down to 10 pixels tall, so every
feature is chunky and unambiguous; omit thin spars, antennae and pitot tubes
rather than drawing them thin.

FRAMING: Nose points to the top of the frame. The aircraft is perfectly
vertical and bilaterally symmetrical about the vertical centre line, centred
with even margins. Square canvas, 2048 x 2048 pixels, transparent background.

MUST NOT CONTAIN: any real aircraft's outline, any manufacturer's design
language, any airline livery, logo, roundel, flag, registration or text of any
kind. This is a generic fictional planform, not a depiction of an existing
aeroplane.
```

---

## PROMPT 04 — Widebody planform

> **Save as** `widebody.png` → **`docs/design/aircraft/`** · 2048 × 2048 · transparent background

```
A flat top-down plan-view silhouette of a generic twin-aisle widebody
airliner, seen from directly above.

SHAPE: A long, visibly THICK fuselage roughly 9 times longer than it is wide —
the extra width against a narrowbody is the entire point of this shape and must
be obvious at a glance. A low wing swept back about 32 degrees, spanning a
little more than the fuselage length, with a long tapering planform and a raked
wingtip. One engine under each wing, mounted about 30% of the way out from the
fuselage, each a large rounded capsule projecting well forward of the wing
leading edge and clearly bigger relative to the wing than a narrowbody's. At
the extreme rear, a conventional tail with a broad swept horizontal tailplane
about 38% of the main wing's span. The nose is a wide, blunt, rounded dome.

STYLE: Pure top-down orthographic plan view, camera directly overhead, no
perspective, no tilt, no vanishing point. The aircraft is a single solid
silhouette in one flat colour (#3D82EB) on a fully transparent background.
Absolutely flat: no gradient, no shading, no highlight, no drop shadow, no
ambient occlusion, no reflection, and no outline or stroke of any kind. No
internal detail whatsoever — no windows, no doors, no cockpit glazing, no
engine cowl lines, no panel lines, no registration, no text, no numbers. The
shape must still read correctly when scaled down to 10 pixels tall, so every
feature is chunky and unambiguous; omit thin spars, antennae and pitot tubes
rather than drawing them thin.

FRAMING: Nose points to the top of the frame. The aircraft is perfectly
vertical and bilaterally symmetrical about the vertical centre line, centred
with even margins. Square canvas, 2048 x 2048 pixels, transparent background.

MUST NOT CONTAIN: any real aircraft's outline, any manufacturer's design
language, any airline livery, logo, roundel, flag, registration or text of any
kind. This is a generic fictional planform, not a depiction of an existing
aeroplane.
```

---

## Check prompts 01–04

Run this once all four are saved:

```bash
python3 - <<'EOF'
import pathlib, struct
for name in ["turboprop", "regional-jet", "narrowbody", "widebody"]:
    f = pathlib.Path(f"docs/design/aircraft/{name}.png")
    if not f.exists():
        print(f"✗ {name}.png — missing"); continue
    b = f.read_bytes()
    w, h = struct.unpack(">II", b[16:24])
    alpha = b[25] in (4, 6)          # PNG colour type 4 = grey+A, 6 = RGBA
    ok = w == h == 2048 and alpha
    print(f"{'✓' if ok else '✗'} {name}.png — {w}x{h}, "
          f"{'transparent' if alpha else 'NO ALPHA — regenerate'}")
EOF
```

All four must read `2048x2048, transparent`. Then check them by eye:

- [ ] Nose up, symmetrical, one flat colour with no gradient at 15% zoom.
- [ ] No windows, text or panel lines anywhere.
- [ ] Shrunk to 10 px each still reads as its own category.
- [ ] Side by side, the four are obviously one family and obviously four
      different aeroplanes.
- [ ] None of them looks like a specific real aircraft.

---
---

# Prompts 05–09 · Store, marketing and icon

Painterly register. Everything here is warm dusk: deep navy sky, amber light,
cloud, wet apron.

---

## PROMPT 05 — Screenshot canvas, iPhone

The backdrop a captured screenshot is composited onto. The middle must stay
empty, because the screenshot covers it.

> **Save as** `canvas-iphone.png` → **`docs/design/store/`** · 1320 × 2868

```
A vertical portrait marketing background for a mobile game store listing,
1320 pixels wide by 2868 pixels tall, a tall 9:19.5 aspect.

COMPOSITION: The centre is deliberately EMPTY. A large calm region runs from
15% to 90% of the image height where a phone screenshot will later be laid on
top, so nothing important, bright or busy may sit there — keep that whole band
a smooth, dark, gently graded navy.

Interest lives only at the extreme top and the extreme bottom. Across the top
20%: a dusk sky with layered amber-lit cloud and one small fictional airliner
in silhouette climbing away, tiny, in the upper right. Across the bottom 12%:
the soft out-of-focus glow of an airport apron at night, runway edge lights and
terminal windows reduced almost to bokeh, with no readable structure.

The impression is depth and calm, not activity. This is a stage, not a scene.

STYLE: Cinematic dusk aviation illustration, painterly and warm, in the style
of a premium mobile strategy game's marketing art. Deep navy night sky (#0A1224
at the top, #1A2138 near the horizon) with warm amber light (#F2A83B).
Volumetric cloud catching the amber. Rich contrast, clean edges, no grain, no
lens dirt, no chromatic aberration.

MUST NOT CONTAIN: any text, caption, lettering or watermark anywhere in the
image; any real airline's name, logo, livery or colours; any real aircraft
manufacturer's design language; any real airport's identifiable architecture;
any registration, flag or brand mark. Every aircraft and carrier here is
fictional.
```

**Check:**

```bash
python3 -c "import struct;b=open('docs/design/store/canvas-iphone.png','rb').read();print(struct.unpack('>II',b[16:24]))"
```

Expect `(1320, 2868)`.

---

## PROMPT 06 — Screenshot canvas, iPad

Same idea, wider frame and a slightly larger quiet band.

> **Save as** `canvas-ipad.png` → **`docs/design/store/`** · 2064 × 2752

```
A vertical portrait marketing background for a tablet game store listing,
2064 pixels wide by 2752 pixels tall, a 3:4 portrait aspect.

COMPOSITION: The centre is deliberately EMPTY. A large calm region runs from
12% to 92% of the image height where a tablet screenshot will later be laid on
top, so nothing important, bright or busy may sit there — keep that whole band
a smooth, dark, gently graded navy.

Interest lives only at the extreme top and the extreme bottom. Across the top
10%: a dusk sky with layered amber-lit cloud and one small fictional airliner
in silhouette climbing away, tiny, in the upper right. Across the bottom 8%:
the soft out-of-focus glow of an airport apron at night, runway edge lights and
terminal windows reduced almost to bokeh, with no readable structure.

The impression is depth and calm, not activity. This is a stage, not a scene.

STYLE: Cinematic dusk aviation illustration, painterly and warm, in the style
of a premium mobile strategy game's marketing art. Deep navy night sky (#0A1224
at the top, #1A2138 near the horizon) with warm amber light (#F2A83B).
Volumetric cloud catching the amber. Rich contrast, clean edges, no grain, no
lens dirt, no chromatic aberration.

MUST NOT CONTAIN: any text, caption, lettering or watermark anywhere in the
image; any real airline's name, logo, livery or colours; any real aircraft
manufacturer's design language; any real airport's identifiable architecture;
any registration, flag or brand mark. Every aircraft and carrier here is
fictional.
```

**Check:**

```bash
python3 -c "import struct;b=open('docs/design/store/canvas-ipad.png','rb').read();print(struct.unpack('>II',b[16:24]))"
```

Expect `(2064, 2752)`.

---

## PROMPT 07 — Key art / feature graphic

One hero image for a press kit, a custom product page header, or social. It has
to survive a square crop.

> **Save as** `key-art.png` → **`docs/design/store/`** · 1920 × 1080

```
A wide 16:9 cinematic key art image, 1920 by 1080 pixels, for a mobile airline
management strategy game.

SUBJECT: A fictional twin-engine narrowbody airliner in a deep azure and white
livery (#3D82EB and #F4F6FA) climbs away from the viewer at a shallow angle,
seen from below and slightly behind, filling the right third of the frame. Its
tail carries a simple abstract amber mark — a stylised aeroplane glyph in
#F2A83B, geometric and flat, invented, not any real carrier's logo.

BACKGROUND: Behind and below, a modern airport at dusk: a glass terminal with
warm amber interior light, a control tower to the left, a wet apron reflecting
the lights, and a second fictional airliner in a different livery parked at a
gate. Beyond the airfield the land falls away into a dark landscape scattered
with the pinpoint lights of distant cities, hinting at a network reaching to
the horizon.

COMPOSITION: The left third of the frame is deliberately uncluttered sky so a
title can be placed over it later — but do not draw any title yourself.
Compose so that a centre square crop still contains both the aircraft and the
terminal, because this image is also used at 1:1.

STYLE: Cinematic dusk aviation illustration, painterly and warm, in the style
of a premium mobile strategy game's marketing art. Deep navy night sky (#0A1224
at the top, #1A2138 near the horizon) with warm amber light (#F2A83B) from
terminal windows, apron floodlights and the last of the sun. Volumetric cumulus
cloud catching the amber. Rich contrast, clean edges, no grain, no lens dirt,
no chromatic aberration.

MUST NOT CONTAIN: any text, title, caption, lettering or watermark anywhere in
the image; any real airline's name, logo, livery or colours; any real aircraft
manufacturer's design language; any real airport's identifiable architecture;
any registration or flag. Every aircraft and carrier here is fictional.
```

**Check:**

```bash
python3 -c "import struct;b=open('docs/design/store/key-art.png','rb').read();print(struct.unpack('>II',b[16:24]))"
```

Expect `(1920, 1080)`.

---

## PROMPT 08 — Website cover **and favicon**

**Read this before generating: it is not a banner.** `site/index.html` uses
`assets/cover.png` for four jobs at once:

```html
<link rel="icon" href="assets/cover.png">
<link rel="apple-touch-icon" href="assets/cover.png">
<meta property="og:image" content="assets/cover.png">
<img class="cover" src="assets/cover.png" width="1200" height="1200"
```

So it is a **square** that must work as a 16-pixel browser favicon, a home-screen
icon, a social preview card, and a large image on the page. Changing its shape
would break the favicon and contradict the hardcoded `width`/`height`.
Legibility at 16 px is the binding constraint, which is why this brief is far
simpler than the key art.

> **Save as** `cover.png` → **`site/assets/`** · 1200 × 1200 · replaces a live file

```
A square image, 1200 by 1200 pixels, for a mobile airline strategy game. It
will be seen both very large and as a 16-pixel browser favicon, so the whole
composition must survive being shrunk to almost nothing.

SUBJECT: One bold central subject — a fictional airliner seen from a low
three-quarter rear angle, climbing to the upper right, in deep azure and white
(#3D82EB and #F4F6FA), occupying roughly the central 55% of the frame. A single
thin amber arc (#F2A83B) sweeps behind it from lower left to upper right,
suggesting a flight path.

BACKGROUND: A simple dusk sky graded from #0A1224 at the top to #1A2138 at the
bottom, with one soft warm glow low in the frame suggesting a lit airport far
below. No terminal, no control tower, no runway markings, no second aircraft,
and no clouds with fine structure — at favicon size every one of those becomes
noise.

FRAMING: Full bleed to all four edges. No border, no rounded corners, no drop
shadow outside the artwork.

STYLE: Cinematic dusk aviation illustration, painterly and warm, in the style
of a premium mobile strategy game's marketing art. Rich contrast, clean edges,
no grain, no lens dirt, no chromatic aberration.

MUST NOT CONTAIN: any text, caption, lettering or watermark anywhere in the
image; any real airline's name, logo, livery or colours; any real aircraft
manufacturer's design language; any registration or flag. The aircraft and
carrier here are fictional.
```

**Check** — keep a way back, because this file is live:

```bash
cp site/assets/cover.png site/assets/cover-previous.png
# drop the new cover.png in, then:
python3 -c "import struct;b=open('site/assets/cover.png','rb').read();print(struct.unpack('>II',b[16:24]))"
```

Expect exactly `(1200, 1200)`. Then **open `site/index.html` in a browser and
look at the tab** — that is the favicon test, and it is the one this asset most
often fails. Delete `cover-previous.png` when you are happy, or restore from it
if you are not.

---

## PROMPT 09 — App icon

**An icon already ships and works.** It is at 1024 × 1024 with its master kept
in `docs/design/icon-source-1254.png`. Only generate a new one if you are
deliberately A/B testing — `docs/ASO.md` §7 says change one listing variable at
a time, and the icon is the highest-leverage one on the page.

The constraint that decides this asset is **thumbnail legibility**: in search
results the icon is about 60 pixels, and the shipped one's terminal, tower and
clouds are all lost at that size. This brief is deliberately simpler for that
reason.

> **Save as** `icon-1024.png` → **`AirlineEmpireApp/Resources/Assets.xcassets/AppIcon.appiconset/`** · 1024 × 1024 · **no alpha**

That filename is not negotiable: `Contents.json` in that folder names
`icon-1024.png` literally, so a file called anything else is invisible to the
build.

```
A square app icon, 1024 by 1024 pixels, for a premium airline management
strategy game.

SUBJECT: A single bold subject, centred, that stays readable at 60 pixels — the
tail fin of a fictional airliner seen from a low three-quarter angle, filling
roughly the central 60% of the frame, in deep azure (#3D82EB), carrying a crisp
amber (#F2A83B) abstract aeroplane glyph: a simple geometric swept shape, flat,
no detail, invented rather than any real carrier's logo.

BACKGROUND: A simple dusk gradient from #0A1224 at the top to #1A2138 at the
bottom, with one soft amber glow low and to the left suggesting terminal light.
A single thin azure arc curves behind the fin from lower left to upper right,
suggesting a flight path. Keep the background almost empty — depth comes from
the gradient and the glow, not from detail. No clouds with structure, no
buildings, no runway markings, no other aircraft: everything must survive being
shrunk to a thumbnail.

FRAMING: Square, full bleed to all four edges, no rounded corners of its own,
no border, no drop shadow outside the artwork, fully opaque with no
transparency anywhere.

MUST NOT CONTAIN: any text, lettering, caption or watermark; any real airline's
name, logo, livery or colours; any real manufacturer's design language; any
registration or flag.
```

**Check** — back up the shipped icon first, then use the repo's own checker,
which is what CI runs:

```bash
cd AirlineEmpireApp/Resources/Assets.xcassets/AppIcon.appiconset
cp icon-1024.png icon-1024-previous.png
# drop the new icon-1024.png in, then from the repo root:
cd - && node scripts/asc/check-app-icon.mjs
```

It must print `✓ App icon present, 1024×1024, no alpha.`

**An icon with an alpha channel is rejected by Apple**, and it is the usual way
this file goes wrong — most models return RGBA by default. If the check fails
on alpha, flatten rather than regenerate:

```bash
python3 -c "
from PIL import Image
p='AirlineEmpireApp/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png'
Image.open(p).convert('RGB').save(p)"
```

**Then judge it honestly:** shrink it to 60 px and put it beside the shipped
icon and four competitors' icons at the same size. If you cannot tell at a
glance which one is yours, it has failed however good it looks at full size.

---
---

# Prompts 10–15 · Empty-state illustrations

**Read this first: these are optional, and a bad set is worse than none.**
`docs/ASSET_INVENTORY.md` rates them P2 and warns against introducing
illustrations that are stylistically unrelated to the rest of the product.
Today an empty state is an SF Symbol, a title, a message and an action, and the
copy is doing the work perfectly well.

They are also **not drop-in assets**: `EmptyStateView` takes an SF Symbol name,
not an image, so using them needs a developer change (§C). Generate all six or
none — a partial set in a different style is exactly the failure the inventory
warns about.

All six share one style, so they read as a family.

---

## PROMPT 10 — Empty state · Fleet ("No aircraft")

> **Save as** `empty-fleet.png` → **`docs/design/illustrations/`** · 2048 × 2048 · transparent

```
A single flat vector spot illustration: an empty aircraft hangar reduced to its
simplest geometry — a wide arched opening, an empty floor line, and nothing
inside it.

STYLE: One colour (#3D82EB) plus a lighter tint of the same colour, on a fully
transparent background. Geometric and minimal, built from simple shapes with
generous strokes of even thickness. No gradient, no shadow, no texture, no
perspective, no background scene, no people, no text. It must read clearly at
64 pixels.

FRAMING: Square canvas, 2048 x 2048 pixels, subject centred with generous
margins, transparent background.

MUST NOT CONTAIN: any real airline or manufacturer reference, any logo, any
lettering.
```

---

## PROMPT 11 — Empty state · Routes ("No routes yet")

> **Save as** `empty-routes.png` → **`docs/design/illustrations/`** · 2048 × 2048 · transparent

```
A single flat vector spot illustration: two small circular airport dots on a
plain field with one dashed arc curving between them, deliberately left
incomplete so it stops short of the second dot.

STYLE: One colour (#3D82EB) plus a lighter tint of the same colour, on a fully
transparent background. Geometric and minimal, built from simple shapes with
generous strokes of even thickness. No gradient, no shadow, no texture, no
perspective, no background scene, no people, no text. It must read clearly at
64 pixels.

FRAMING: Square canvas, 2048 x 2048 pixels, subject centred with generous
margins, transparent background.

MUST NOT CONTAIN: any real airline or manufacturer reference, any logo, any
lettering.
```

---

## PROMPT 12 — Empty state · Search ("No matches")

> **Save as** `empty-search.png` → **`docs/design/illustrations/`** · 2048 × 2048 · transparent

```
A single flat vector spot illustration: a magnifying glass positioned over a
small grid of four dots, one of which is hollow rather than filled, suggesting
a gap rather than a result.

STYLE: One colour (#3D82EB) plus a lighter tint of the same colour, on a fully
transparent background. Geometric and minimal, built from simple shapes with
generous strokes of even thickness. No gradient, no shadow, no texture, no
perspective, no background scene, no people, no text. It must read clearly at
64 pixels.

FRAMING: Square canvas, 2048 x 2048 pixels, subject centred with generous
margins, transparent background.

MUST NOT CONTAIN: any real airline or manufacturer reference, any logo, any
lettering.
```

---

## PROMPT 13 — Empty state · Route closed ("Route closed")

> **Save as** `empty-route-closed.png` → **`docs/design/illustrations/`** · 2048 × 2048 · transparent

```
A single flat vector spot illustration: a single route arc between two small
circular dots, with a clean break in the middle of the arc so the two ends are
drawn slightly apart from each other.

STYLE: One colour (#3D82EB) plus a lighter tint of the same colour, on a fully
transparent background. Geometric and minimal, built from simple shapes with
generous strokes of even thickness. No gradient, no shadow, no texture, no
perspective, no background scene, no people, no text. It must read clearly at
64 pixels.

FRAMING: Square canvas, 2048 x 2048 pixels, subject centred with generous
margins, transparent background.

MUST NOT CONTAIN: any real airline or manufacturer reference, any logo, any
lettering.
```

---

## PROMPT 14 — Empty state · Calm skies ("Calm skies")

> **Save as** `empty-calm-skies.png` → **`docs/design/illustrations/`** · 2048 × 2048 · transparent

```
A single flat vector spot illustration: a simple sun disc sitting low behind
two flat horizontal cloud bars, and nothing else in the frame.

STYLE: One colour (#3D82EB) plus a lighter tint of the same colour, on a fully
transparent background. Geometric and minimal, built from simple shapes with
generous strokes of even thickness. No gradient, no shadow, no texture, no
perspective, no background scene, no people, no text. It must read clearly at
64 pixels.

FRAMING: Square canvas, 2048 x 2048 pixels, subject centred with generous
margins, transparent background.

MUST NOT CONTAIN: any real airline or manufacturer reference, any logo, any
lettering.
```

---

## PROMPT 15 — Empty state · No rivals ("No rivals")

> **Save as** `empty-no-rivals.png` → **`docs/design/illustrations/`** · 2048 × 2048 · transparent

```
A single flat vector spot illustration: three small circular airport dots
connected to each other by thin arcs, all drawn in the same single colour, with
the space around them conspicuously empty.

STYLE: One colour (#3D82EB) plus a lighter tint of the same colour, on a fully
transparent background. Geometric and minimal, built from simple shapes with
generous strokes of even thickness. No gradient, no shadow, no texture, no
perspective, no background scene, no people, no text. It must read clearly at
64 pixels.

FRAMING: Square canvas, 2048 x 2048 pixels, subject centred with generous
margins, transparent background.

MUST NOT CONTAIN: any real airline or manufacturer reference, any logo, any
lettering.
```

---

## Check prompts 10–15

```bash
python3 - <<'EOF'
import pathlib, struct
names = ["empty-fleet", "empty-routes", "empty-search",
         "empty-route-closed", "empty-calm-skies", "empty-no-rivals"]
for name in names:
    f = pathlib.Path(f"docs/design/illustrations/{name}.png")
    if not f.exists():
        print(f"✗ {name}.png — missing"); continue
    b = f.read_bytes()
    w, h = struct.unpack(">II", b[16:24])
    alpha = b[25] in (4, 6)
    ok = w == h == 2048 and alpha
    print(f"{'✓' if ok else '✗'} {name}.png — {w}x{h}, "
          f"{'transparent' if alpha else 'NO ALPHA — regenerate'}")
EOF
```

Then put all six side by side at 64 px. If any one looks like it came from a
different set, redo that one — a family that is nearly a family is the failure
mode here.

---
---

# §A · Getting the aircraft into the app

**The PNGs from prompts 01–04 are tracing references, not shippable assets.**

The app draws these shapes as SwiftUI `Shape` paths in
`AirlineEmpireApp/Sources/Map/AircraftSilhouette.swift` — not as images. So the
handoff is: trace each PNG to a vector, export the outline as a path, and give
that to a developer to replace the existing planform.

Dropping the PNGs in as image assets instead would break runtime tinting (the
map colours each aircraft by its airline's livery), cost memory at three zoom
levels, and lose the crispness the current shapes have — the map redraws these
every frame.

---

# §B · Where the finished App Store screenshots go

Prompts 05 and 06 make backdrops. The finished six — backdrop, plus a real
screen capture, plus a caption — go into the tree the upload script reads, and
those folder names are **App Store Connect enum values passed to Apple's API
unchanged**. Spell them exactly:

```
store/screenshots/en-US/APP_IPHONE_67/01-map.png
store/screenshots/en-US/APP_IPHONE_67/02-route-detail.png
store/screenshots/en-US/APP_IPHONE_67/03-fleet.png
store/screenshots/en-US/APP_IPHONE_67/04-finance.png
store/screenshots/en-US/APP_IPHONE_67/05-world.png
store/screenshots/en-US/APP_IPHONE_67/06-dashboard.png
```

and the same six filenames under each of:

- `store/screenshots/en-US/APP_IPAD_PRO_3GEN_129/`
- `store/screenshots/en-GB/APP_IPHONE_67/`
- `store/screenshots/en-GB/APP_IPAD_PRO_3GEN_129/`

**24 files.** Two locales, because en-GB is what the UK, Ireland, Australia and
New Zealand storefronts serve (`docs/ASO.md` §3).

Two traps worth knowing before making 24 of anything:

- **`APP_IPHONE_67` is the 6.9-inch canvas.** Apple's enum still carries the
  older 6.7-inch device's inches. The canvas is 1320 × 2868. Likewise
  `APP_IPAD_PRO_3GEN_129` takes 2064 × 2752. Do not rename the folders to match
  the inches.
- **No alpha, or the upload is rejected.** Flatten every file.

```bash
mkdir -p store/screenshots/en-US/APP_IPHONE_67 \
         store/screenshots/en-US/APP_IPAD_PRO_3GEN_129 \
         store/screenshots/en-GB/APP_IPHONE_67 \
         store/screenshots/en-GB/APP_IPAD_PRO_3GEN_129
# after dropping the files in:
node scripts/asc/validate-metadata.mjs --allow-placeholders
```

That validator is what CI runs on a pull request; it checks dimensions and
rejects any image carrying an alpha channel.

The caption for each shot, and what each has to prove, is in `docs/ASO.md` §5.
Use the same seed and the same airline name across all six so the gallery reads
as one story rather than six unrelated screens.

---

# §C · What the empty states would need

If you decide to use prompts 10–15, one imageset per illustration:

```
AirlineEmpireApp/Resources/Assets.xcassets/EmptyFleet.imageset/
├── Contents.json
└── empty-fleet.png
```

with `Contents.json`:

```json
{
  "images" : [
    { "filename" : "empty-fleet.png", "idiom" : "universal", "scale" : "1x" },
    { "idiom" : "universal", "scale" : "2x" },
    { "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`EmptyStateView` then needs teaching to take an image rather than an SF Symbol
name. Hand the six PNGs and this skeleton to a developer; do not wire it
yourself unless you are comfortable in the Swift.

---

# §D · Order to work in

| Do | Prompts | Why here |
| --- | --- | --- |
| 1st | **03**, then 04, 02, 01 | The narrowbody is the whole startup fleet and the first shape a player sees. Generate the other three against it so the family holds. This is the only real gap in the product. |
| 2nd | **07** key art | Immediately useful for a press kit or a product page. |
| 3rd | **08** cover | Replaces a live file that already works. Test it at 16 px. |
| 4th | **05**, **06** canvases | Only useful once the six real captures exist (§B). |
| 5th | **09** icon | Only as a deliberate A/B. One already ships and works. |
| 6th | **10–15** empty states | Optional, needs a developer change to use, easy to make worse. Last, or never. |

**If you do only one thing: prompt 03.**

---

# §E · The rule under all of it

Every asset here is original and fictional. No real aircraft, no real airline,
no real airport, no borrowed artwork — that is the claim
`docs/ASSET_PROVENANCE.md` makes on this project's behalf, and an image model
will happily break it for you if you let it.

So the test is not "does this look good". It is **"could anyone point at this
and name the real thing it came from"**. If yes, it does not ship, however good
it looks.
