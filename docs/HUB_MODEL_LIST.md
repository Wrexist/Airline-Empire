# Hub View — 3D model list

> The models that take the Hub View (docs/HUB_VIEW_3D.md) from procedural
> stand-ins to the reference clip's finish. Every entry was catalogued from
> the reference video frame by frame (277 frames, 30 fps, both panels, 3×
> crops of the sharpest frame in each shot). Timestamps below are into that
> clip; "Opus" is its lower panel, "GPT" its upper.
>
> **Drop-in:** a file named exactly as the **File** column, added to
> `AirlineEmpireApp/Resources/HubModels/`, replaces that piece everywhere on
> the next build. No code changes. Missing files fall back to the procedural
> model, so they can arrive one at a time.

---

## 0. Rules for every model

These are what makes a model drop in cleanly and read like the reference.

### Format and scale

| | |
|---|---|
| Format | **USDZ** (export from Blender 4.x with the USD exporter, or Reality Converter from glTF) |
| Units | **metres**, 1 unit = 1 m, real-world size |
| Up | **+Y** |
| Forward | **+X** for anything with a front (aircraft nose, vehicle cab, person's face) |
| Right | **+Z** (so the left/port side, where aircraft doors are, faces −Z) |
| Pivot | **centre of the footprint, on the ground** (y = 0). Aircraft: centre of the fuselage length, wheels on y = 0 |
| Scale | apply all transforms; no negative scales |
| Buildings | the **main face** (hangar doors, villa garden front, office street front, terminal street front, kiosk screen, desk front) points **+X**; the app turns it to face the apron or the street |
| Fitting | buildings, villas, pools and gardens are scaled uniformly to their plot; trees to their height; jet bridges stretched along X to reach the aircraft; vehicles, people and props are used at their real size |
| People | model at real size (1.75 m); the app draws everyone 1.8× larger, as the reference does, so they read from the dashboard camera |

### Look (the reference's "clay" style)

- **Soft, rounded, simplified.** Bevel every hard edge (2–4 cm on props,
  5–15 cm on vehicles and buildings, 1 segment + weighted normals). No sharp
  CAD edges anywhere: the bevel catching light is half the look.
- **Matte.** Roughness 0.75–0.95, metallic 0, for everything except glass
  (roughness 0.1, opacity 0.45–0.6) and screens (emissive).
- **Flat colour, no detail textures.** Colour comes from materials, not
  painted textures. Allowed textures: decals with text or logos (gate sign,
  shop fascia, fuel-truck logo), the FIDS screen content, window grids on
  mid-rise façades. Max 512 × 512 each.
- **Detail by geometry, sparingly.** Window rows, door outlines, panel lines
  are separate thin inset/extruded pieces in a darker colour, not texture.
- **No baked lighting, no AO textures, no shadows in the mesh.** The scene
  lights everything; the app adds contact shadows.

### Material slots (so liveries and night mode still work)

Split each model into child prims, one per material, and **name the prim
`ae_<slot>`** (a suffix like `ae_livery_2` is ignored). The app repaints
those prims with its own palette; any prim without the prefix keeps the
material you authored.

| Slot | Day colour (albedo) | Used for |
|---|---|---|
| `ae_white` | `#F1F3FA` | aircraft skin, vehicle bodies, white trim |
| `ae_livery` | airline colour (player: indigo `#3B4FC4`) | tail fin, engine nacelles, winglets |
| `ae_liveryAccent` | second airline colour (orange `#F5A623` on indigo) | tail flash |
| `ae_windowDark` | `#56648F` (glows warm at night) | cockpit, cabin windows, building windows |
| `ae_glass` | `#7DB6E4` @ 55 % | curtain walls, glazed roofs |
| `ae_building` | `#D6DCF1` | façades, walls |
| `ae_buildingShade` | `#BFC7E8` | secondary walls, plinths |
| `ae_roof` | `#CDD5F1` | flat roofs |
| `ae_houseRoof` | `#3D5A9C` | navy roofs, terminal roof slab |
| `ae_houseWood` | `#B9805C` | wood slats, shelving, counters |
| `ae_darkMetal` | `#3A3F5C` | chassis, frames, poles, belts |
| `ae_tyre` | `#2B2F45` | tyres |
| `ae_hiVis` | `#F5B83D` | vests, safety stripes |
| `ae_cone` | `#F2843A` | cones, warning parts |
| `ae_cloth` | varies by instance | people's clothes |
| `ae_skin` | varies by instance | people's skin |
| `ae_screen` | `#1F3A7A` emissive | kiosks, FIDS, monitors |
| `ae_lamp` | warm white, emissive at night | lamp heads, light boxes |
| `ae_water` | `#6FC6EA` | pools |
| `ae_tree` | `#4DA16E` | canopies |
| `ae_trunk` | `#8A8FAE` | trunks |
| `ae_grass` / `ae_grassBright` | `#6CC290` / `#8AD6AB` | lawns, hedges |

The whole world is graded towards periwinkle: keep neutrals cool (lean
blue-violet), never warm grey.

### Budgets (iPhone, 60 fps)

| Class | Triangles (LOD0) | LOD1 (optional, < 40 % of LOD0) |
|---|---|---|
| Aircraft | 8 000 – 12 000 | 2 500 |
| Ground vehicle | 1 200 – 3 000 | 500 |
| Person | 600 – 1 200 | 250 |
| Hero building (villa, terminal hall) | 6 000 – 15 000 | — |
| Other buildings | 1 500 – 6 000 | — |
| Props (kiosk, cone, sign) | 80 – 800 | — |
| Tree | 200 – 500 | — |

The scene shows up to ~20 aircraft, ~60 vehicles and ~120 people at once;
the app shares one mesh per file across all copies.

---

## 1. Aircraft

Seen in every shot. 13 on screen in the overview (0.0–1.4 s), the hero jet
fills the gate shot (1.9–2.9 s), three taxi past in the district (6.0–8.6 s).

### 1.1 `Hub_aircraft_narrowbody.usdz` — **the hero jet** (highest priority)

A320-class single-aisle twin. 38 m long, 35.8 m span, 11.8 m tall at the fin.

| Part | What the reference shows |
|---|---|
| Fuselage | White (`ae_white`), round section ~4 m, plain: **no cheatline**. Belly fairing very slightly greyer. Rounded nose, short taper; tail cone sweeps up to a small APU exhaust. |
| Cockpit | Four-pane windscreen in one dark band (`ae_windowDark`), wrapping round the nose; thin white posts between panes. |
| Cabin windows | One row each side, ~28 small rounded windows, dark, evenly spaced, just above mid-height. |
| Doors | Two forward and two aft door outlines each side, slightly darker inset lines; forward-left door is where the bridge docks (−Z side, 5 m behind the nose). |
| Wings | Low-mounted, 25° sweep, light grey-white. **Sharklet winglets** curving up, in `ae_livery`. Flap-track fairings as small pods under the trailing edge. |
| Engines | Two under-wing nacelles in `ae_livery` (indigo), round intakes with a light silver lip and dark fan face; short pylons. |
| Tail | Vertical fin in `ae_livery` with a **diagonal orange flash** (`ae_liveryAccent`) sweeping from the leading edge root up to the trailing edge (see gate shot, 2.4 s). Horizontal stabilisers white. |
| Gear | Twin nose wheels on a strut, two main bogies with two wheels each; dark tyres, light grey struts. Gear down, sitting on y = 0. |
| Slots | `ae_white`, `ae_livery`, `ae_liveryAccent`, `ae_windowDark`, `ae_tyre`, `ae_darkMetal` |
| Pivot | centre of fuselage length, on the ground; nose towards +X |

### 1.2 `Hub_aircraft_regional.usdz` — E-Jet class
33 m long, 28 m span. Same treatment as 1.1, smaller; under-wing engines;
T-tail **no** (conventional tail like the E-Jet). Not in the reference;
match 1.1's style exactly.

### 1.3 `Hub_aircraft_largeNarrowbody.usdz` — A321-class
44.5 m long, 35.8 m span; 1.1 stretched, four doors per side.

### 1.4 `Hub_aircraft_widebody.usdz` — A330/787 class
60 m long, 60 m span, fuselage ~5.6 m, two large engines, dihedral wings,
two-aisle window spacing. Same livery placement as 1.1.

### 1.5 `Hub_aircraft_largeWidebody.usdz` — 777-9/A350-1000 class
70 m long, 65 m span, two very large engines (the game's largest category;
four-engine jumbos are out of the catalogue).

### 1.6 `Hub_aircraft_turboprop.usdz` — ATR 72 class
27 m long, 27 m span, **high wing**, two turboprop nacelles with 6-blade
propellers as a single dark disc each, T-tail. Livery on fin and nacelles.

---

## 2. Ground vehicles

### 2.1 `Hub_vehicle_fuelTruck.usdz` — **hero vehicle**
Seen twice in the gate shot (left, 2.1 s; front-left, 2.6 s), in the
terminal shot (front-left, 4.5 s), three in the overview.
Rigid three-axle tanker, 9.5 m × 2.5 m × 3.3 m.
- Cab-over cab, white, rounded front, large dark windscreen and side
  windows, black grille strip, small round headlights.
- Elliptical tank, **light silver-white** (`ae_white`, slightly greyer),
  with three bands and a **round yellow logo** on the side (decal,
  original design — not the reference's).
- Dark chassis, side skirts, rear ladder and hose reel cabinet.
- Six dark wheels with light hubs.

### 2.2 `Hub_vehicle_beltLoader.usdz`
Gate shot, at the forward hold (2.6 s). 7.5 m × 2 m. White low chassis
with a driver seat on the left; long conveyor ramp with side rails,
**metal grey belt, yellow edge stripes** (`ae_hiVis`), raised to ~3.5 m at
the aircraft end. Separate the ramp as its own prim (`ramp`) pivoted at the
low end so it can be raised.

### 2.3 `Hub_vehicle_tug.usdz` — pushback tractor
White, low, wide, 5 m × 2.6 m × 1.7 m; small offset cab with dark windows,
yellow beacon, tow bar at the front.

### 2.4 `Hub_vehicle_serviceTruck.usdz`
The small white cab-over box trucks dotted across the apron in the
overview (0.5–1.4 s). 6 m × 2.2 m × 2.6 m, white box body, dark windows,
thin livery stripe (`ae_livery`).

### 2.5 `Hub_vehicle_serviceCar.usdz`
The white car/pick-up beside the belt loader (2.6 s). 4.6 m, rounded,
white, dark glasshouse.

### 2.6 `Hub_vehicle_golfCart.usdz` — **hero of the district shot**
District (6.6–8.6 s), and the icon riding the turnaround timeline. Four-seat
white golf cart, 3 m × 1.3 m × 2 m: white canopy roof on four thin posts,
dark seats, white body, small dark wheels. Tow hitch at the rear.

### 2.7 `Hub_vehicle_tankTrailer.usdz`
Towed by the golf cart (district). Small single-axle cylindrical tank
trailer, 3.5 m, light silver, dark chassis, A-frame drawbar to the front.

### 2.8 `Hub_vehicle_boxTruck.usdz`
District right edge (7.0 s) and GPT terminal shot. Large white rigid
lorry, 8.5 m × 2.5 m × 3.6 m, cab-over with dark windows, plain white box.

### 2.9 `Hub_vehicle_car_sedan.usdz`, `Hub_vehicle_car_suv.usdz`
Parked and driving cars (district day and night, car parks). 4.6 m and
4.8 m, rounded, body in `ae_cloth` (the app picks colours), dark glass,
emissive headlight and tail-light strips (`ae_lamp`) for night.

### 2.10 `Hub_vehicle_baggageTrain.usdz`
Tractor + three open luggage dollies with coloured bags. 12 m overall.
Not prominent in the reference; keep it simple.

### 2.11 `Hub_vehicle_bus.usdz`
Apron bus for remote stands. 12 m × 2.6 m × 3 m, white, full-length dark
windows, livery band. Not in the reference.

---

## 3. People

Seen in every daytime shot. ~25 queuing at the gate, ~28 in the terminal,
crew at the aircraft.

Style: **slightly stylised, adult proportions, 1.75 m** (the app enlarges
them 1.8× at runtime, matching the reference's oversized figures), simple faces
(no eyes needed at this distance), soft rounded hands and shoes, clothes as
separate prims so the app can recolour them.

| File | Description |
|---|---|
| `Hub_person_passenger_a.usdz` | Man, jacket over shirt, trousers, walking pose, rolling suitcase |
| `Hub_person_passenger_b.usdz` | Woman, coat, trousers, standing, shoulder bag |
| `Hub_person_passenger_c.usdz` | Person in hoodie and jeans, backpack |
| `Hub_person_passenger_d.usdz` | Person in shirt, standing at a kiosk (arm raised) |
| `Hub_person_crew.usdz` | Ground crew: **hi-vis yellow vest** (`ae_hiVis`) over dark overalls, ear defenders, standing |
| `Hub_person_staff.usdz` | Terminal staff: navy uniform, standing behind a desk |

Clothing colours seen in the reference (the app cycles through these on
`ae_cloth`): navy `#3A4A8C`, white `#EDEFF7`, red `#E85D75`, teal `#2FA88A`,
mustard `#F2B544`, orange `#E07A2E`, grey `#7D8099`. Skin on `ae_skin`.

Animation (optional, adds a lot): a 1 s walk loop and a 2 s idle, as USD
skeletal animation on the passenger and crew files. Without animation the
app slides static people along their paths, as now.

---

## 4. Airside buildings

### 4.1 `Hub_concourse_glass.usdz` — **hero building of the gate shot**
The glazed concourse behind the hero jet (gate shot, 1.9–2.9 s;
overview centre). A **barrel-vaulted glass roof on white steel ribs**
(ribs every ~3 m), over glass walls with thin white mullions, on a white
base 1.2 m high. Inside: a few people visible through the glass.
Module: **30 m long × 18 m deep × 11 m to the crown**, open ends so modules
butt together. Provide also `Hub_concourse_glass_end.usdz` (closed end,
quarter-dome) for the tip of a pier.

### 4.2 `Hub_terminal_pavilion.usdz`
The white flat-roofed block where the bridge enters (gate shot, right).
20 m × 16 m × 9 m, white render, **dark ribbon window**, rooftop plant
boxes, parapet. Doubles as the pier head.

### 4.3 `Hub_jetBridge.usdz` — **hero**
Gate shot (2.0–2.9 s). Apron-drive passenger bridge, 22 m long at rest:
- Rotunda at the building end: round white drum on a column.
- **Two telescoping tunnel sections**, white, boxy with rounded edges,
  vertical rib lines every ~1.2 m, small side windows.
- Drive column and **wheel bogie** under the outer section (dark).
- Cab at the aircraft end: wider white box with a dark bellows canopy.
- Floor ~4.5 m above the apron.
- Separate prims: `tunnel_inner`, `tunnel_outer`, `cab`, `bogie` so the app
  can extend it to the aircraft door.

### 4.4 `Hub_gateSign.usdz`
"Gate 14" sign on the concourse glass (2.4 s). Black panel 3 m × 2.2 m with
a thin frame, white bold "Gate", large number, white arrow and two lines of
small yellow text. Provide the panel as geometry and the text as a decal
texture **without** the number; the app renders the number.

### 4.5 `Hub_hangar.usdz`
The pair top-right of the overview (0.0–1.4 s). 60 m × 50 m × 22 m:
**barrel-vault roof** in light grey-lavender, white side walls, the apron
face mostly a **dark door opening** with a row of light window panels above
it, a small text plate on the gable, a lower annex on one side.

### 4.6 `Hub_terminal_hall.usdz` + `Hub_terminal_hall_interior.usdz` — **hero of the terminal shot**
The two-storey hall (terminal shot, 4.4–6.0 s). 60 m × 34 m × 12 m.
- **Shell** (`Hub_terminal_hall.usdz`): **navy flat roof slab**
  (`ae_houseRoof`) overhanging 1.5 m; glass curtain wall with dark
  mullions; white columns; upper floor slab edge visible as a white band.
  Build the front (+Z) wall and roof as separate prims named `cutaway_*` —
  the app hides those in the cutaway.
- **Interior** (`…_interior.usdz`), everything the cutaway reveals:
  - Upper floor (mezzanine) along the back with a **glass balustrade**.
  - **Central staircase/escalator** rising diagonally to it, glass sides.
  - **Departure board** high on the back wall: two large screens side by
    side (blue with white/green rows — texture), on a dark frame.
  - Yellow-on-black overhead wayfinding signs, two or three.
  - Light floor, slightly darker walkway strips.

### 4.7 `Hub_controlTower.usdz`
Not clearly in the reference; match the style: white tapered shaft 45–70 m,
wider glazed cab ring, flat cap, antenna.

### 4.8 `Hub_cargoShed.usdz`, `Hub_fuelTank.usdz`
Not in the reference; simple white boxes / white cylinders in the style.

---

## 5. Terminal interior props

All seen in the terminal shot (4.4–6.0 s), Opus panel, unless noted.

| File | Size (m) | Description | Count |
|---|---|---|---|
| `Hub_kiosk_selfService.usdz` | 0.6 × 1.6 × 0.6 | White rounded pedestal, **tilted blue screen** at the top (`ae_screen`), small printer slot | 8 |
| `Hub_checkInDesk.usdz` | 2 × 1.1 × 0.9 | White counter, dark top, monitor, bag scale belt | 4 |
| `Hub_eGate.usdz` | 1 × 1.2 × 2.5 | Automated border gate: white pedestal with **glass flaps**, small screen; place in rows | 6 |
| `Hub_metalDetector.usdz` | 1.2 × 2.4 × 0.9 | **White walk-through arch**, square, thick posts | 1–2 |
| `Hub_stanchion_belt.usdz` | 2 m segment | Two chrome posts with a dark retractable belt; tile into queue mazes | 30 |
| `Hub_shop_pharmacy.usdz` | 10 × 4 × 5 | Shopfront: **dark fascia** with a sign decal (our own name, e.g. "Nord Care"), **warm wood shelving** packed with small product boxes, a white counter | 1 |
| `Hub_shop_shelving.usdz` | 4 × 2.2 × 0.6 | Tall wood shelf unit stocked with colourful products (convenience store, right side) | 6 |
| `Hub_shop_gondola.usdz` | 3 × 1.4 × 1 | Low island shelf with goods both sides | 2 |
| `Hub_cafe_counter.usdz` | 5 × 1.1 × 1.2 | Wood counter, glass display case, coffee machine, menu board | 1 |
| `Hub_luggageTrolley.usdz` | 1 × 1 × 0.6 | White trolley loaded with **blue suitcases** | 4 |
| `Hub_electricCart.usdz` | 2.8 × 1.6 × 1.3 | White indoor passenger cart, two bench seats | 2 |
| `Hub_seatRow.usdz` | 4 × 0.9 × 0.7 | Grey bench of linked seats (GPT terminal) | 6 |
| `Hub_plant_pot.usdz` | 0.6 × 1.5 | Round planter with a leafy plant | 4 |

---

## 6. Apron props

| File | Description | Seen |
|---|---|---|
| `Hub_barrier_fin.usdz` | **Red/pink crowd-control fin barrier**: a slanted red panel on a white post, 1.2 m, placed in a row along the queue walkway | gate shot right (2.4 s), overview centre (12 of them) |
| `Hub_cone.usdz` | Orange cone with white band, 0.7 m | gate shot (3–4) |
| `Hub_wheelChock.usdz` | Small yellow chock pair | optional |
| `Hub_gpu.usdz` | Ground power unit: small white cart with cable | optional |
| `Hub_apronMast.usdz` | 20 m floodlight mast with a 4-lamp head | overview |

---

## 7. Landside and district

### 7.1 `Hub_house_villa.usdz` — **hero of the district shot**
District (6.0–8.6 s) and night (8.6–9.3 s). Two-storey modern villa,
footprint ~16 m × 12 m, 8.5 m tall.
- Walls: **white render** (`ae_building`), crisp blocks.
- Roof: **dark navy** (`ae_houseRoof`) shallow pitched main roof plus a flat
  roof wing, both with thin overhanging edges.
- **Large glazed openings** with dark frames on the ground floor; a corner
  window upstairs; at night all glazing glows warm (`ae_windowDark`).
- **Vertical warm-wood slat panels** (`ae_houseWood`) on part of the upper
  façade and beside the entrance.
- An **orange/terracotta** accent box (planter or porch wall).
- Small balcony with a glass or white rail.
- Garden: separate file `Hub_house_garden.usdz` — low **white boundary
  wall** (0.9 m) with a dark gate, lawn plinth, two rounded hedges, a pool
  (see 7.6).
- Three variants: `Hub_house_villa_b.usdz` (mirrored massing, more wood),
  `Hub_house_villa_c.usdz` (flat roof only).

### 7.2 `Hub_midrise_apartment.usdz`
District background (6.0–9.3 s). 5–6 storeys, 24 m × 16 m × 20 m, white
and light-grey render, **recessed balconies** with glass rails in a regular
grid, dark window bands; a window-grid texture is fine. Night: windows
glow warm (texture's window cells emissive).

### 7.3 `Hub_office_low.usdz`
The big pale low blocks in the overview foreground (0.0–1.4 s). 60 m × 40 m
× 8 m, flat roof with a few plant boxes, light façade with a long dark window
band. Two variants.

### 7.4 `Hub_guardhouse.usdz`
District left (6.5 s): small white security booth with a dark window and a
flat roof, plus a **boom barrier** (white arm with red stripes) and a
sliding gate section.

### 7.5 `Hub_tree_round.usdz` (+ `_tall`, `_small`)
Everywhere. **Lollipop trees**: a single smooth, slightly egg-shaped canopy
in bright green (`ae_tree`, reference `#58BB7F` lit), a thin grey trunk.
Heights 6, 9, 12 m. 200–400 triangles. Also `Hub_bush.usdz`: low rounded
bush 1–1.5 m, and `Hub_hedge.usdz`: 4 m rounded hedge segment.

### 7.6 `Hub_pool.usdz`
District / night. 10 m × 5 m rectangular pool, white coping, water surface
as its own prim (`ae_water`; the app makes it glow cyan at night).

### 7.7 `Hub_streetLamp.usdz`
Slim dark pole 7.5 m with one flat head; head prim `ae_lamp`.

### 7.8 `Hub_pathLight.usdz`
The rows of small light points along kerbs at night (8.6–9.3 s): 0.6 m
bollard with an `ae_lamp` top.

---

## 8. Keep procedural (no model needed)

These are already generated by the app and should stay that way:
runways, taxiways and markings; roads, kerbs, lane dashes and zebra
crossings; apron slabs and stand markings; lawns; the glowing route lines;
the pink stand outline; pulse rings; heatmap; map pins and pills (SwiftUI).

---

## 9. Priority order

Biggest visible difference first:

1. `Hub_aircraft_narrowbody` — on screen in every shot.
2. `Hub_person_passenger_a…d`, `Hub_person_crew` — the reference is full of
   people.
3. `Hub_jetBridge`, `Hub_concourse_glass`, `Hub_gateSign` — the gate shot.
4. `Hub_fuelTruck`, `Hub_beltLoader`, `Hub_tug`, `Hub_serviceTruck`.
5. `Hub_terminal_hall` + interior + the §5 props — the terminal shot.
6. `Hub_house_villa` + garden, `Hub_tree_round`, `Hub_golfCart` +
   `Hub_tankTrailer`, `Hub_midrise_apartment` — the district and night.
7. `Hub_hangar`, `Hub_office_low`, remaining aircraft sizes.
8. Everything optional.

## 10. Do not copy

The reference is someone else's product. Match its **style, proportions,
colours and density**, not its identity: no "WareTrack" or "AirOps Digital
Twin" names or logos, no copying of its shop names ("BodyTree"), no
real airline liveries or registrations. Every sign, logo and decal is ours.
