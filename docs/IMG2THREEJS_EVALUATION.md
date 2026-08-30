# img2threejs — evaluation

**Verdict: LIMITED USE. Not adopted in AE-030.**

Evaluated 2026-08-30 by cloning and reading the tool, not by reading its
README. Repository: `img2threejs/img2threejs`, Apache-2.0, v1.5.1, last commit
2026-08-29 (active), 6.4 MB, 52 commits on main.

This document exists so the decision is auditable and so a future phase can
reverse it cheaply if the premises change. The premises are stated explicitly
in §5.

---

## 1. What the tool actually is

**Reconstruction by code, not photogrammetry.** It takes a reference image and
produces a TypeScript factory function returning a `THREE.Group` assembled from
primitives and procedural shaders, plus an `ObjectSculptSpec` JSON describing
the component tree.

Five stages under `forge/`: `stage1_intake`, `stage2_spec`, `stage3_build`,
`stage4_review`, `stage5_rig`. Python 3.10+ standard library for the tooling;
optional MediaPipe / SAM2 / Depth-Anything integrations are external and not
required.

**It does not emit a mesh file.** No glTF, no OBJ, no USDZ from the core
pipeline. The output is source code that only means anything inside a Three.js
runtime.

This is important and easy to get wrong from the name. The pipeline MASTER
ASSET PIPELINE §7 sketches —

    3D SOURCE → STANDARDIZED CAMERA → RENDERED ASSET → NATIVE ASSET

— is not what this tool hands you. To get a raster out you need the tool's
render bridge (`scripts/capture_threejs_playwright.py`), which requires a live
page exposing `window.__IMG2THREEJS_READY__` and
`window.__IMG2THREEJS_CAPTURE__.setCamera(...)`, driven by Playwright against a
real browser canvas. The script explicitly "never renders a replacement scene in
Python and fails closed when the runtime contract is absent."

So the real toolchain is: **Python tooling + Node + Three.js + a hosted web app
+ Playwright + Chromium**, offline, to produce PNGs.

For a project whose entire shipping app currently contains **one** image file
and **zero** third-party dependencies, that is the cost side of the ledger.

---

## 2. What Airline Empire actually needs from aircraft artwork

Measured from the code, not assumed (`docs/AIRCRAFT_ASSET_BIBLE.md` §4):

| Surface | Size | Rotates? | Tinted? | Instances on screen |
| --- | --- | --- | --- | --- |
| Map, world zoom | 9 pt | yes, 0–360° | per-airline livery | up to 200+ |
| Map, regional | 13 pt × planform scale | yes | per-airline livery | dozens |
| Map, local | 18 pt × planform scale | yes | per-airline livery | dozens |
| Market card | 34 × 34 | no | accent / muted | 14 in a list |
| Detail header | 44 × 44 | no | player livery | 1 |
| Fleet row | caption | no | accent | up to 200 in a list |

Two properties in that table decide the evaluation.

### 2.1 Rotation rules out a perspective render

Map aircraft are rotated to their heading. A ¾ elevated render — the
presentation that makes a 3D pipeline worth having — cannot be rotated in 2D: a
plane drawn in perspective and spun about the screen normal reads as sliding
sideways, not as flying north. Only a plan (top-down) view survives arbitrary
rotation, which is exactly why the existing silhouettes are plan view.

A top-down 3D render *would* rotate correctly. But a top-down render at 9–18 pt
is a silhouette with lighting on it, and at that size the lighting is one or two
pixels of gradient. It is not distinguishable from the vector path already
there.

### 2.2 Livery tinting rules out baked shading

Every map aircraft is filled with its airline's livery colour, and the detail
header with the player's. A rendered raster has its shading baked in. To keep
per-airline colour you would need either

- one render per (type × airline) — combinatorial, and airline colours are
  player-chosen at founding, so the set is not even known at build time; or
- a tint blend over the render, which flattens the shading you built the whole
  pipeline to obtain.

The second option is the honest one, and it means paying five tools to produce
an image that then gets flattened back toward a silhouette.

**This is not a limitation of img2threejs.** It is a property of shipping
rasters into a game that recolours its objects at runtime. Any render-to-PNG
pipeline hits it.

---

## 3. The provenance problem, which is structural

MASTER ASSET PIPELINE §22 forbids shipping "manufacturer promotional artwork
without rights" and "random images downloaded from search results".

img2threejs is *reference-driven by design*: stage 1 is intake of a reference
image. Every aircraft in this game is fictional — `MR180`, `AV310`, `KT72`, with
invented manufacturers. **There is no reference image of an MR180, because the
MR180 does not exist.**

That leaves two routes, and both are problems:

1. **Use a photograph of a real aircraft** (a 737, an A320) as the reference.
   The output is then a reconstruction derived from that photograph. This is
   precisely what §22 forbids, and it would make every aircraft in the game a
   derivative work of somebody's photo.
2. **Author an original reference first.** Legitimate — but if you have already
   drawn an original side view of the aircraft, the 3D reconstruction step is
   adding a browser, a bundler and a screenshot harness to convert your drawing
   into a slightly different drawing.

Worth noting plainly, since it is evidence rather than speculation: the tool's
own showcase gallery is substantially reconstructions of copyrighted
third-party IP — CS:GO weapon skins ("Talon Knife | Doppler Ruby", "AWP |
Medusa"), and a Pokémon character. That is the workflow the project is built
around and demonstrates. It is a fine capability; it is not one this project can
use, and it signals that provenance discipline is left entirely to the caller.

---

## 4. Where it would genuinely help

One place, and it is real: **a large aircraft hero on the detail screen.**

MASTER ASSET PIPELINE §9D asks for "the largest and highest-quality version".
Today the detail header draws the same 4-planform silhouette at 44 pt. A
320×180 rendered aircraft would be a genuine step up in presence, and it is
static, unrotated, and shown one at a time — none of §2's objections apply.

That is 14 images. It is the only category where the pipeline earns its cost,
and it still needs §3 solved first: somebody has to author 14 original
reference views, because the aircraft are fictional.

---

## 5. Decision, and what would reverse it

**Not adopted in AE-030.** Aircraft presentation stays procedural and native.

The decision rests on four premises. If any changes, re-open this document:

| Premise | Reverses if |
| --- | --- |
| Aircraft are recoloured per-airline at runtime | livery tinting is dropped, or aircraft render neutral |
| Map aircraft rotate to heading | the map stops rotating markers |
| The largest aircraft presentation is 44 pt | a detail hero at 200 pt+ is designed and wanted |
| Aircraft are fictional with no license-safe reference | original reference views are authored or licensed |

The fourth is the one to watch: **it is the only premise that is not about
engineering.** The other three are reversible by a design decision. That one
requires somebody to make artwork, and once they have, the cheapest path is
usually to use it directly rather than to reconstruct it.

### What was kept from the evaluation

The tool's *philosophy* is the right one for this project and is already its
architecture: **rebuild the object as parameterised code rather than ship
art.** img2threejs does it in TypeScript against Three.js; Airline Empire does
it in Swift against `Path`. Both give resolution independence, runtime
recolouring, zero disk cost, and no possibility of a missing asset.

What the audit showed is that this project has the right *technique* and
under-invested in the *fidelity*: four crude planforms shared across fourteen
types, so five aircraft draw identically at identical scale
(`tasks/TECH_DEBT.md` TD-014). That is the gap worth closing, and it is closed
by writing better geometry in the language the app already speaks — not by
adding a browser to the build.

---

## 6. Reproducing this evaluation

```
git clone --depth 1 https://github.com/img2threejs/img2threejs.git
ls forge/                     # stage1_intake … stage5_rig
head -40 scripts/capture_threejs_playwright.py   # the render bridge contract
```

No part of this evaluation required running the generation pipeline, because
the disqualifying facts are architectural (§2 rotation and tinting, §3
provenance) and visible from the interface. If the premises in §5 change, the
next step would be to run stages 1–3 on one authored reference and capture a
hero render to judge fidelity — roughly a day's work, and worth doing then.
