# Hub View 3D — visual bible and architecture

> Target: Airline Empire **1.1**. Written 2026-10-06 from a frame-by-frame
> breakdown of the reference clip the owner supplied (a 9.3 s side-by-side of
> two AI-built "WareTrack" airport dashboards). The brief is "identical to the
> video": the same isometric clay world, the same light glass dashboard, the
> same scenes — re-skinned as *the player's own hub*, driven by the
> simulation, not by decoration.
>
> Nothing from the reference is copied as a brand: no "WareTrack" name, logo or
> avatar. The airline's own name, livery and airport fill those slots.

---

## 1. What the reference actually shows

Sampled at 4 fps (37 frames, 540×780, two stacked 540×300 panels). Both
panels show the same product; the lower one is the more finished and is the
primary target.

| Shot | Time | What is on screen |
|---|---|---|
| **A. Overview** | 0.0–1.5 s | Whole airport from ~40° elevation: terminal with two glass piers, ~12 stands with jet bridges, parked white jets with indigo tails, a runway and parallel taxiway behind, barrel-roof hangars back right, landside roads with zebra crossings and white buildings in front, mint lawns and round trees. Slow dolly in. |
| **B. Gate turnaround** | 1.5–3.5 s | Close on one stand: aircraft nose-in at a glass jet bridge and rotunda, "Gate 14" sign, a **pink stand-safety outline** on the apron, a **cyan glowing passenger queue** on the walkway, fuel truck, belt loader, tug, cones, ground crew. A **blue pulse ring** around the engine/wing root. A glass **callout** floats over the jet: "Flight BA-284 · Boarding", rows for HVAC and power, progress bar. |
| **C. Terminal cutaway** | 3.5–5.5 s | The terminal opens like a doll's house: roof and front wall gone, mezzanine, escalator, check-in kiosks, security lanes with metal-detector frames, retail with stocked shelves, FIDS screens, ~40 people. A **heatmap** (blue→yellow→red) pools on the floor where the queue is densest; two map pins mark hotspots. |
| **D. Landside / district** | 5.5–7.5 s | Roads, a modern house in a walled garden with **pins and pill labels** ("Maintenance", "Trash pickup"), service route drawn as a **glowing cyan path**, golf cart, tanker, aircraft crossing on the airside edge. |
| **E. Night** | 7.5–9.3 s | Same district at night: indigo ground, warm window glow, street lamps as points of light, glowing route lines, pills still readable. The **dashboard stays light**. |

### Dashboard chrome (constant across shots)

```
┌───────────────────────────────────────────────────────────────────────────┐
│ ◆ Brand   🔍 Search sites, trucks, flights…    [▣ Hub ▾]  ● Live 09:41  🔔 (◉ Name / Role) │  top bar, frosted
├──────────┬──────────┬──────────┐                               ┌─┐ ┌────────────────┐
│ KPI 88.4%│ KPI 32   │ KPI 8m   │                               │+│ │ Inspector card │
│ ▲ delta  │ subtitle │ subtitle │                               │−│ │ aircraft render │
└──────────┴──────────┴──────────┘                               │↻│ │ fact rows       │
                                                                 │◎│ └────────────────┘
                        (3D world, full bleed)                   └─┘
┌─────────────────────────────────────────────┬──────────┐        ┌────────────────────┐
│ Turnaround · AE 284   ●──●──○──○──○  [cart] │ Next     │        │ Departures│Arr│Delay│
│ Deboard Service Board Pushback Departed     │ action   │        │ rows with status chip│
└─────────────────────────────────────────────┴──────────┘        └────────────────────┘
```

---

## 2. Palette (measured, k-means over the scene)

The world is **periwinkle-graded**: every neutral leans blue-violet; shadows
are lavender, never grey. Values are the cluster centres, rounded.

| Token | Day | Night | Use |
|---|---|---|---|
| `concrete` | `#A3AAD3` | `#4F4F6F` | apron, sidewalks |
| `concreteLight` | `#B4BDE0` | `#5E5F80` | pier roofs, kerbs |
| `asphalt` | `#6C779F` | `#3A3D5E` | runways, roads |
| `asphaltDark` | `#576086` | `#2D2E50` | taxiway shoulders |
| `building` | `#D2D8EF` | `#6A6F92` | white façades |
| `buildingShade` | `#C5CEED` | `#565B80` | secondary walls |
| `glass` | `#71B0DE` @45% | `#4B87CB` @55% | curtain walls, bridges |
| `grass` | `#6CC290` | `#2E5A4A` | lawns |
| `grassBright` | `#89D3AA` | `#3A6E58` | lawn highlights |
| `tree` | `#4DA16E` | `#24493E` | canopies |
| `marking` | `#F4F6FC` | `#C9CDE6` | zebra, lane dashes |
| `taxiLine` | `#F2C94C` | `#F2C94C` | lead-in lines |
| `safety` | `#E8517A` | `#FF6A92` | stand outline |
| `pulse` | `#2F8BFF` | `#4DA3FF` | pulse ring, pins |
| `queueGlow` | `#3FE0E8` | `#3FE0E8` | queue + route lines |
| `windowNight` | — | `#FFD9A0` | emissive windows |
| `sky` | `#DCE3F7`→`#F4F6FF` | `#1C1E4A`→`#2D3175` | IBL gradient |

Livery: white fuselage, tail and engine nacelles in the airline's `Livery`
colour, a thin accent cheat line. The reference's indigo tail is the player's
`azure`/`violet`; rivals keep their own livery colours; generic traffic is
`slate`.

## 3. Camera

- Perspective, **24° vertical FOV** (reads isometric, keeps the slight
  convergence visible in shot B).
- Pitch **−38°** (overview) to **−28°** (gate), yaw **35°** off the runway axis
  so runways and roads cross the frame on diagonals, as in every frame.
- Distance 2 200 m (overview) → 260 m (gate) → 180 m (terminal).
- Pan by drag on the ground plane, pinch to zoom along the view ray, two-finger
  twist for yaw (clamped ±60°). Shots are animated presets.
- Idle drift: 0.6 m/s dolly, as the reference never holds perfectly still.

## 4. Lighting and materials

- One directional key light, elevation 52°, azimuth 140°, warm-white, casting
  shadows; an image-based environment generated at runtime from the `sky`
  gradient supplies the lavender fill. No baked lightmaps in 1.1.
- **Contact shadows**: a soft radial-gradient decal under every building,
  aircraft and vehicle, which is what gives the clay "ambient occlusion" look
  where RealityKit has no SSAO.
- All materials are matte (roughness 0.75–0.95, metallic 0) except glass
  (roughness 0.15, 45% opacity, tinted) and emissives.
- Rounded edges everywhere: boxes use `cornerRadius` ≈ 6% of the smallest side.

## 5. The object kit

Everything is generated in code (`AirlineEmpireApp/Sources/Hub/`), so the
scene ships with zero binary assets and every piece can be swapped later for
an authored USDZ of the same name (`HubAssetSlot`).

| Group | Pieces |
|---|---|
| Ground | grass base, apron slab, runway with threshold piano keys + centreline, taxiways with yellow centrelines, roads with lane dashes and zebra crossings, sidewalks, parking bays |
| Airside buildings | terminal hall (glass façade, overhanging white roof, columns), piers, jet bridges + rotundas, gate sign boards, control tower, barrel-roof hangars, cargo sheds, fuel farm |
| Aircraft | lofted fuselage with nose cone and tail cone, cockpit glazing, window strip, swept wings with winglets, horizontal + vertical stabiliser, two or four engines with intake rings; sized per `AircraftCategory` |
| Ground vehicles | fuel truck, belt loader, pushback tug, catering truck, baggage tractor + carts, apron bus, cones |
| People | capsule figures in five clothing colours, ground crew in hi-vis |
| Landside | white mid-rise blocks with window grid, houses with pitched navy roofs and garden walls, trees (cluster canopies), lamp posts, cars, golf cart |
| Overlays | pulse rings, stand outline, queue glow, route lines, map pins, heatmap decal |

## 6. What drives the scene (no decoration without data)

| Simulation | Scene |
|---|---|
| `AirportSpec.runwayClass` | runway count and length, piers, bridge vs. stairs |
| `slotCapacityPerDay` | stand count (6 → 18) |
| `terminalCapacityPerDay` | terminal length, check-in rows, security lanes |
| `AirportRuntime.slotAllocations` | how many stands are occupied, movement rate |
| player `Aircraft` at the hub | parked at stands in the player's livery |
| player `Flight.phase` at the hub | turnaround stage, callout, timeline, board |
| rival aircraft at the hub | parked in their liveries |
| `AirportFacilities.groundServices` | number of ground vehicles per stand |
| `AirportFacilities.lounge` | lounge block in the cutaway |
| local time (`utcOffsetMinutes`) | day / dusk / night |
| passengers today ÷ terminal capacity | heatmap intensity in the cutaway |

Layout and live state are computed in **Core** (`HubLayout`, `HubSnapshot`),
deterministic and unit-tested on Linux. The app only renders them.

## 7. Platform

- `ARView(cameraMode: .nonAR)` in a `UIViewRepresentable`; no AR session, no
  camera permission. **The Hub View needs iOS 18** (the app's floor stays
  17): the iOS 26 SDK makes the CGImage-to-texture and CGImage-to-environment
  generators iOS 18-only, and `OpacityComponent` is iOS 18. On iOS 17 the
  "View hub in 3D" button simply does not appear.
- Meshes: `MeshResource.generateBox(…cornerRadius:)` plus a small
  `MeshDescriptor` generator for lathed (fuselage, engines, tower) and extruded
  (wings, fins, roofs) shapes, because `generateCylinder`/`generateCone` need
  iOS 18.
- World-anchored UI (callouts, pins, pills) is SwiftUI, positioned each frame
  with `ARView.project(_:)`.
- Resources are shared: one mesh + material per piece type, cloned.
- Budget: ≤ 2 500 entities, ≤ 250 k triangles at the overview, 60 fps on
  A15, 30 fps cap when idle, rendering paused when the view disappears.

## 8. Phases

| Phase | Deliverable | Validated by |
|---|---|---|
| H1 | `HubLayout` + `HubSnapshot` in Core | `swift test` (Linux) |
| H2 | Procedural kit, overview scene, glass chrome | `hub-view-review` simulator captures vs. reference frames |
| H3 | Gate shot: turnaround vehicles, queue, pulse, callout | captures |
| H4 | Terminal cutaway + heatmap, district + night | captures |
| H5 | Device performance pass, authored USDZ swap-ins where procedural falls short | Instruments on device |

## 9. Honest limits

The reference frames look pre-rendered (soft global illumination, hundreds of
detailed figures). A real-time phone renderer will match its **composition,
palette, camera, chrome and behaviour**; matching its *micro-detail*
(individual faces, shelf stock, cabin windows at gate distance) needs authored
models. The `HubAssetSlot` seam exists so an artist can replace any procedural
piece with a USDZ without touching layout or simulation code.

## 10. Status — first capture loop (2026-10-06)

Six render-and-compare passes on the `hub-view-review` workflow (iPad Pro 13"
landscape, iPhone 17 Pro Max portrait), each frame set laid beside the
matching reference frame.

**Matches the reference**

- Composition of all five shots, camera language (isometric-reading
  perspective, 24° FOV, diagonal axes), periwinkle-graded palette, matte clay
  materials with soft shadows and contact-shadow decals.
- The whole dashboard: frosted top bar with search, hub chip, live clock,
  bell and profile; three KPI cards; vertical map controls; aircraft inspector
  with profile render and fact rows; turnaround timeline with the tug riding
  the progress line and a next-action card; departures/arrivals/delays board;
  world-anchored glass callout, pins and pills.
- Gate: jet bridges, gate signs, pink stand envelope, pulse rings, turnaround
  vehicles and crew, passenger queue with cyan glow while boarding.
- Terminal cutaway with heatmap pools; district of walled villas with the
  glowing service route; indigo night with warm windows and lamp pools.

**Still short of the reference**

- Micro-detail: the reference's figures, shop stock, cabin windows and
  façade structure are richer than procedural primitives. The `HubAssetSlot`
  plan (§9) — authored USDZ models swapped in by piece kind — closes this.
- The terminal interior is sparser than the reference's two-storey hall.
- No baked global illumination: corners are lit evenly where the reference
  pools soft occlusion.
- Not yet measured on a physical device (Phase H5).

**Next:** the shot-by-shot gap list and the ordered work plan to close it
are in [`HUB_HANDOFF.md`](HUB_HANDOFF.md).
