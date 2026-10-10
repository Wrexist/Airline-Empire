# Hub View — 3D model pipeline (Meshy + Blender + Claude)

> How the models in [`HUB_MODEL_LIST.md`](HUB_MODEL_LIST.md) get made: Meshy
> generates them, Claude cleans them up in Blender, and a checker plus the
> simulator captures prove each one before it ships. This is step 4 of the
> plan in [`HUB_HANDOFF.md`](HUB_HANDOFF.md). Written 2026-10-09.

It starts from a popular six-step "Claude + Blender MCP + Meshy + Unreal"
workflow and changes every step that doesn't fit this project:

| Generic workflow | For Airline Empire | Why |
|---|---|---|
| Connect Blender MCP and Meshy MCP | **Kept** (§1), plus the repo's scripts | — |
| Brainstorm 5 game ideas, pick one, expand it | **Lock the look** (§2): the hero jet goes through the whole loop first and becomes the style anchor | The game exists and the target is fixed: the owner's reference clip. Style drift between 33 models is the real risk. |
| Tell it your GPU; push graphics as far as it runs | **Budget for the phone** (§3): per-model triangle budgets, flat colour, no PBR textures | The hub runs on an iPhone 13-class A15 at 60 fps, not on the PC. |
| Meshy makes props; Claude imports and cleans in Blender | **Kept, made exact** (§4–§5): concept image → image-to-3D → `clean_model.py` (orient, palette slots, decimate, scale, pivot, export) → hand fixes | Generated meshes come out the wrong size, facing, density and colours; the app needs `ae_<slot>` prims to apply liveries and night mode. |
| Claude builds the level, lighting, HUD, minimap in Unreal | **Drop into the app** (§6): `Resources/HubModels/`, check, capture, compare | The game is native iOS on RealityKit. The level, lighting and HUD already exist in Swift and load these files with no code changes. |

> **Update, 2026-10-11 — the free route the models now take.** The owner
> has no paid Meshy plan, so models are **built from code in Blender**
> instead: `scripts/hub-models/procedural/kit.py` (lofts, lathes, airfoil
> surfaces, decals on curved skin, per-face slots) plus one script per
> model. Each script writes `Hub_<slot>.usdz` straight into
> `Resources/HubModels/` at real size, facing +X, on budget and split into
> `ae_<slot>` prims, so stages 4–5 below (generate, colour-match, decimate)
> are skipped; §6 (check, capture, compare) is unchanged. No licence or
> credit line is needed. Run headless, with workbench previews to look at:
>
> ```bash
> blender --background --factory-startup \
>     --python scripts/hub-models/procedural/aircraft_narrowbody.py -- --preview .hub-review/models
> python scripts/hub-models/check_usdz.py
> ```
>
> Meshy's free plan (output under CC BY 4.0, commercial use with credit)
> stays a fallback for organic shapes such as people. The rest of this file
> describes the generator route.

---

## 1. Setup (once, on the PC that runs Blender)

Do this on the Windows PC. Running **Claude Code locally there** is the
simplest: it reaches Blender's MCP server directly, and works in the repo.

1. **Blender 4.2 or newer** (5.0 tested with the scripts).
2. **Blender MCP**: install the `blender-mcp` add-on (`addon.py` from the
   blender-mcp project) in Blender → Preferences → Add-ons; in the 3D view's
   side panel (N) → BlenderMCP → *Connect to Claude*. Install `uv`
   (`winget install astral-sh.uv`), then register the server:
   ```bash
   claude mcp add blender -- uvx blender-mcp
   ```
3. **Meshy**: create an API key at meshy.ai (a paid plan, so the output may
   be used commercially), then add Meshy's MCP server following Meshy's own
   docs, with the key in its environment:
   ```bash
   claude mcp add meshy --env MESHY_API_KEY=msy_... -- <command from Meshy's MCP docs>
   ```
   Never commit the key.
4. **Repo tools** (for headless runs and the checker):
   ```bash
   py -3.11 -m pip install bpy usd-core pillow   # bpy needs Python 3.11
   ```
5. Check: `claude mcp list` shows `blender` and `meshy` as connected, and
   `python scripts/hub-models/check_usdz.py` prints "no Hub_*.usdz models".

(Claude in the cloud can use the same servers when this chat is linked to
the PC from the desktop app; they appear under the computer's tools.
Higgsfield's image-to-3D connector is a fallback generator if Meshy is
unavailable; every later stage is the same.)

## 2. Lock the look first (the hero jet)

Run `aircraft_narrowbody` through **every stage below before anything
else**, and get the owner's approval on the in-game capture. Then:

- its approved concept image is attached as the **style reference** to every
  later concept prompt;
- its Blender file (`--save-blend`) is the reference for bevel size, detail
  density and proportions;
- anything that drifts from it (glossy, realistic, warm grey, busy texture)
  is regenerated, not patched.

The style in one line, used in every prompt: *"soft clay-style 3D game asset,
simplified rounded shapes with bevelled edges, matte flat colours, no
texture detail, no text, isometric 3/4 view, plain light background"*.

## 3. Budget for the phone

From `HUB_MODEL_LIST.md` §0 and `scripts/hub-models/manifest.json`:

| Class | LOD0 triangles | Examples |
|---|---|---|
| Aircraft | 8 000 – 12 000 | hero jet, other categories |
| Vehicle | 1 200 – 3 000 | fuel truck, belt loader, tug, golf cart |
| Person | 600 – 1 200 | passengers, crew |
| Hero building | 6 000 – 15 000 | terminal hall, villa |
| Building | 1 500 – 6 000 | concourse module, jet bridge, apartments |
| Prop | 80 – 800 | kiosk, gate sign, shelving |
| Tree | 200 – 500 | round tree |

Up to ~20 aircraft, ~60 vehicles and ~120 people are on screen at once; the
app shares one mesh per file. Colour comes from the `ae_` palette slots,
not from textures: Meshy's textures are used only to *decide which slot a
face gets*, then thrown away.

## 4. Generate (Meshy)

Per model, in the priority order of `HUB_MODEL_LIST.md` §9 (the manifest's
`priority` field):

1. **Concept image first** (cheap to iterate). Prompt = the style line +
   the model's row in `HUB_MODEL_LIST.md` (shape, parts, real size) +
   *"colours: <its slots with their hex values from manifest.json>"* +
   *"facing right, 3/4 view from the front-left"*. Attach the style
   reference (§2). Generate 3–4, pick one; the owner approves the hero
   models' concepts.
2. **Image-to-3D** from the approved concept. Ask for low poly / remesh to
   about the budget's top value, triangles, and **texture on** (the colours
   drive slot assignment). Generate 2 variants; keep the cleaner one.
3. Save the raw GLB **outside the repo** (or in `art/hub-models/raw/`,
   which is git-ignored) as `<slot>_v<n>.glb`.

Prompting rules that save regenerations:

- Ask for the palette colours by hex, and for **solid colour regions**
  (no gradients, no dirt, no logos): `clean_model.py` assigns faces by
  nearest colour, so clean colours give clean slots.
- Aircraft: *"plain white fuselage, no cheatline, no airline logo or
  text"*; liveries are painted by the app.
- Never ask for real brands, airline liveries or the reference's names
  (`HUB_MODEL_LIST.md` §10).

## 5. Clean (Blender, Claude via MCP)

**Automatic pass** — `scripts/hub-models/clean_model.py` does the mechanical
work identically every time. From Claude via the Blender MCP, run the file
with its arguments; headless it is:

```bash
python3.11 scripts/hub-models/clean_model.py --input raw/aircraft_narrowbody_v2.glb \
    --slot aircraft_narrowbody --yaw -90 --save-blend raw/aircraft_narrowbody.blend
```

1. joins the meshes, turns the front to +X (`--yaw`) and applies transforms;
2. gives every face the nearest **allowed** palette slot for this model
   (sampling Meshy's texture), smoothed over neighbours;
3. decimates to the budget; 4. scales to real size (by length, else height);
5. pivots to the footprint centre on the ground;
6. drops textures and splits into one `ae_<slot>` object per slot with a
   matte preview material; 7. smooth-shades and exports
   `AirlineEmpireApp/Resources/HubModels/Hub_<slot>.usdz` (Y-up, metres).

Find `--yaw` by importing once and looking: the nose/cab/face must end up
pointing +X (Blender +X), the aircraft's door side towards Blender +Y
(the app's −Z).

**Hand pass** — Claude, through the Blender MCP, on the saved `.blend`:

- fix slots the colour match got wrong (e.g. sharklets must be
  `ae_livery`, the tail flash `ae_liveryAccent`, window rows
  `ae_windowDark`) by selecting faces and moving them to the right
  `ae_<slot>` object;
- add the **named prims** the model list asks for: `cutaway_*` on the
  terminal hall, `tunnel_inner`/`tunnel_outer`/`cab`/`bogie` on the jet
  bridge, the un-prefixed polished-silver tank on the fuel truck;
- bevel hero edges if the mesh reads sharp (2–15 cm, model list §0);
- take a viewport screenshot (MCP) at the reference shot's angle and lay
  it beside the concept; save, then re-export with
  `clean_model.py --input <fixed>.blend --slot <slot>` (a `.blend` input is
  exported as is).

## 6. Validate and drop in

```bash
python3.11 scripts/hub-models/check_usdz.py      # every model in Resources/HubModels
```

It fails a model whose size, pivot, facing, triangle count, `ae_` slots or
textures are off (the rules of `HUB_MODEL_LIST.md` §0, from
`manifest.json`). The `Hub models` workflow runs the same check on every PR
that touches models.

Then: commit the `.usdz` (only the final file — never raw generator output),
open a PR, let **Hub view review** render the shots, and run the comparison
loop (`HUB_HANDOFF.md` §4). A model is done when:

- [ ] `check_usdz.py` passes;
- [ ] it appears in the captures at the right size and facing, day and night;
- [ ] livery / night repaint works (the player's colour on the jet's tail,
      lit windows at night);
- [ ] beside the reference frame it reads as the same object, same style as
      the hero jet;
- [ ] frame time is still inside budget (`HUB_VIEW_3D.md` §7) once a batch
      lands.

**Batch by shot** so each PR visibly moves one comparison row: gate
(jet, bridge, concourse, sign, turnaround vehicles, crew) → people →
terminal (hall + interior props) → district (villa, trees, cart + trailer,
apartments) → the rest.

## 7. Files

| File | Role |
|---|---|
| `scripts/hub-models/manifest.json` | Machine-readable spec: file name, class, size, triangle budget, allowed and required slots, palette, priority. Keep in sync with `HUB_MODEL_LIST.md`. |
| `scripts/hub-models/clean_model.py` | Blender cleanup and USDZ export (headless, `blender --python`, or via MCP). |
| `scripts/hub-models/check_usdz.py` | Validator (`pip install usd-core pillow`). |
| `.github/workflows/hub-models.yml` | Runs the validator on PRs. |
| `AirlineEmpireApp/Resources/HubModels/` | Where finished models go; the app loads `Hub_<slot>.usdz` by name. |

Tested end to end on a synthetic generator-style GLB (wrong scale, facing and
offset, textured): the script produced a passing `Hub_aircraft_narrowbody.usdz`
with five slot prims, and the checker caught a deliberately short wingspan.
Not yet tested: a real Meshy export, and loading the result on a device.
