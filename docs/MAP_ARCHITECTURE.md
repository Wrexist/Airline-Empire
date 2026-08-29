# Airline Empire — Map Architecture

> How the world map is built, drawn, and kept honest. Written 2026-08-29 with
> the map overhaul; companions: `UI_ARCHITECTURE.md` §3 (the original
> contract), `UIUX_FORENSIC_AUDIT.md` §8 (why the previous map failed).

---

## 1. The audit that preceded this

The map read as "sparse dots on a dark field" for reasons that were
measurable, not aesthetic:

| Finding | Evidence |
|---|---|
| The geography was a silhouette, not cartography | 260 coordinate pairs across 16 polygons. Europe was 8 points |
| No spatial structure at all | No graticule, no ocean depth, one flat fill behind everything |
| Airports were one visual class | A single `prominence` scalar drove radius. No tiering, no hub/spoke distinction, no competitor bases |
| Labels were all-or-nothing | The rule was `zoom > 2.5 \|\| servedByPlayer`, with no priority and no collision test |
| Routes carried one bit | `profitable: Bool`. No health taxonomy, no load factor, no disruption |
| Every aircraft was the same symbol | One SF Symbol at 10–13 pt, so a turboprop and a widebody were identical |
| Motion stuttered under fast-forward | Positions came from the snapshot only; at 16× a two-hour flight got ~7 updates |
| Nothing was selectable but airports | And selecting one led nowhere — the callout had no actions |
| No overlays, no events, no competitor structure | The living world had no geography |
| The early-game map was empty | A player with no routes saw dots and nothing else |

Reusable and kept: `MapProjector`, the `Canvas` approach, `MapMath`'s
great-circle arcs, the per-tick model cache in `GameController`, `Livery`.

---

## 2. Art direction

Premium strategy cartography, not a satellite image and not a road map.

- **Value range.** Ocean `#0B101B`, deep water `#060A13`, land `#19212F`,
  coast `#2B384C`. The entire geography sits inside a narrow, dark band so it
  can never compete with the network drawn over it. Land supports information;
  it is not information.
- **Graticule** at 30°, at 10% opacity, with the equator a shade stronger. A
  grid is what makes a dark field read as a *map*, and it gives the eye
  something to measure a great circle against.
- **Colour carries meaning, never alone.** Route health drives weight, opacity
  and dash as well as hue: a grounded route is thin, grey and dotted, so it
  reads as *stopped* rather than as a different colour.
- **The player is always the brightest thing on screen.** Rival routes sit at
  16–42% opacity depending on zoom; the player's are 90–100%.

---

## 3. Geography (`WorldGeometry.swift`)

631 coordinate pairs across 24 landmasses, hand-traced at 2–6° along coasts
and finer where a shape is recognisable — the Baltic, the Gulf, the Horn, the
Malay peninsula, the Bering Strait. These are the shapes a player orients by.

Hand-authored because the build environment has no network access to fetch
Natural Earth, and a coarse trace that ships beats an accurate one that does
not. Deliberately *not* finer than this: a coastline with every fjord competes
with the routes over it.

Presentation only. Airport positions come from `airports.json` through
`MapModel`; nothing in this file reaches the simulation.

---

## 4. Coordinate system and projection

**Map space** is normalised equirectangular: `x = (longitude + 180) / 360`,
`y = (90 - latitude) / 180`, both 0…1, defined by `MapPoint` in Core.

`MapProjector` maps that to screen points. The world is 2:1 and fitted to
width, so `worldWidth = viewportWidth × zoom` and `worldHeight = worldWidth/2`.
`zoom` is "how many viewport widths the world spans"; `center` is the
normalised point held at the middle of the viewport.

### The antimeridian

A great circle from Tokyo to Los Angeles crosses 180°, and in map space its x
values jump from ~0.99 to ~0.01 between two waypoints. Drawn naively that is a
straight line back across the whole map — **BUG-012**, and one of the ugliest
bugs a strategy map can have.

`MapMath.unwrap` walks an arc accumulating whole-world offsets so x stays
continuous even when it leaves 0…1; `MapMath.worldOffsets` says which world
copies (−1, 0, +1) the result reaches into. The renderer draws the unwrapped
polyline once per copy, so a Pacific leg leaves one edge and its continuation
enters the other.

This lives in Core rather than in the renderer because it is geometry, and
because Core's own comment had always claimed correct date-line handling —
true of the points, not of the line through them. Seven tests
(`AntimeridianTests`).

---

## 5. Renderer: why `Canvas`

**Chosen: SwiftUI `Canvas` inside `TimelineView(.animation)`.**

| Option | Verdict |
|---|---|
| **SwiftUI `Canvas`** | **Chosen.** Immediate mode: the whole map is one view drawing a few thousand primitives, not a view per airport — which is what makes a SwiftUI map fall over. Composites on the same path as the rest of the UI, so the chrome layers over it for free |
| A `View` per element | Rejected outright. 80 airports + 200 routes + flights is thousands of views and a layout pass per frame |
| SpriteKit | Rejected. A scene graph and a texture atlas for objects that move every frame anyway, plus an `SKView` host and a second run loop to keep in step with the 4 Hz pump |
| Metal | Rejected. A great deal of machinery for ~3–5k path segments; nothing here is shader-bound |
| Web / MapKit | Rejected. MapKit is a *geographic* map with its own tiles, gestures and styling; this is a stylised strategy board where the geography is deliberately abstract. No web view in a native game |

No new dependencies were added.

### Layers, back to front

```
ocean → graticule → land → event fields → opportunity arcs
→ rival routes → player routes → airports → flights → labels
```

Order *is* the hierarchy: geography never draws over the network, and the
player's airline never draws under a rival's. `MapFrame` is a struct built,
drawn and discarded each frame; the only thing that outlives it is its
`Geometry`, which the view keeps so hit-testing resolves against what was
actually on screen.

---

## 6. Aircraft assets (`AircraftSilhouette.swift`)

Four original planforms — high-wing turboprop, T-tail regional jet, swept
narrowbody, twin-aisle widebody — drawn as programmatic vector paths in a unit
box, nose at `(0.5, 0)`, centred on `(0.5, 0.5)`.

Vector rather than bitmap because they scale exactly from 8 pt to 40 pt and
because every aircraft is recoloured to its operator's livery, which would
otherwise need one asset per colour. Original rather than traced: no real
manufacturer's planform, no airline's branding.

| Category | Planform | Relative size |
|---|---|---|
| `turboprop` | `turboprop` | 0.82 |
| `regionalJet` | `regionalJet` | 0.90 |
| `narrowbody`, `largeNarrowbody` | `narrowbody` | 1.00 |
| `widebody`, `largeWidebody` | `widebody` | 1.22 |

Six categories collapse to four planforms: at map scale a narrowbody and a
large narrowbody are the same shape, and drawing them apart would be a
difference nobody can see. A directional `wedge` replaces the planform at
world zoom, where a silhouette is a smudge but "which way is it going" still
reads. `AircraftShape` wraps the same paths as a SwiftUI `Shape` so the fleet
screens can use them from one definition.

---

## 7. Zoom and level of detail

`MapZoomLevel` is what the map is *for* at a magnification, not raw scale.
Zooming in reveals different things, not merely bigger ones.

| Level | Zoom | Airports shown | Labels | Aircraft | Rival routes |
|---|---|---|---|---|---|
| **World** | < 2.6 | Major and above | ≤ 14 | Wedges | 16% opacity |
| **Regional** | 2.6–6 | Regional and above | ≤ 28 | Silhouettes | 30% |
| **Local** | > 6 | Everything | ≤ 28 | Large silhouettes | 42% |

**The player's own network is never hidden, at any zoom.** That is the promise
`MapDetailPolicy.shows` makes, and closed airports are also always drawn
because a closure is something you must not miss.

At 16× in world view, rival aircraft are dropped: they are the least
informative moving objects on screen, and removing them keeps the player's own
fleet legible when the world is moving fast.

### Labels

`MapLabelLayout.place` ranks by what the player needs to read — selection
(1000), home (900), a closure (850), a hub (800), any served airport (700),
then size by zoom level — and refuses any label whose box overlaps one already
placed. Greedy by priority, which is stable frame to frame because the ranking
is.

---

## 8. Overlays

One at a time, deliberately: each answers one strategic question, and stacking
them answers none.

| Overlay | Question | What it draws |
|---|---|---|
| **Network** | What does my airline look like? | Routes by health, event fields |
| **Demand** | Where should I fly next? | Ranked unopened markets as dashed arcs |
| **Profit** | Which routes are making money? | Player routes recoloured by margin; airport heat by whether their routes are working |
| **Rivals** | Where am I fighting someone? | All rival routes at full weight; heat where a rival is based |
| **Risk** | Where are operations at risk? | Event fields, closures, slot pressure, weather exposure |

The picker shows each question, because an overlay whose purpose has to be
guessed will not be used.

---

## 9. Screen layout

The rule: **the map is the screen.** Chrome floats over it and nothing
permanent occupies the middle.

- **Top** — date, clock, speed control, and at most one world banner. Solvency
  outranks weather: a storm costs a day, insolvency costs the game.
- **Upper left / right** — overlay picker and zoom controls, both 44 pt.
- **Bottom** — whatever is selected. Nothing selected shows the single most
  useful true thing the current overlay can say; a player with no routes gets
  the empty-state invitation instead.

The navigation bar is hidden on this screen so the map is full-bleed.

---

## 10. Selection

`MapHitTester` resolves a tap **aircraft → airports → routes**, nearest-first
within tolerance. The order is deliberate: an aircraft is the smallest and most
transient thing on the map so it must win where it overlaps, and a route line
passes under hundreds of pixels and would otherwise swallow every nearby tap
(routes also use half the tolerance).

Hit-testing runs against `MapFrame.Geometry` — the geometry the last frame
actually drew — so the tap resolves against what the player saw rather than
against a recomputed layout.

Each card answers *what it is*, *how it is doing*, and *what you can do from
here*: an airport can open a route or jump to one you fly; a route links to its
detail screen with its health explained in a sentence; an aircraft shows its
progress and links to the airframe.

---

## 11. Performance

The map model is rebuilt once per simulation tick, so its cost sits directly in
the renderer's frame budget. Measured with `ae-map-bench` (release, Linux
x86-64, 8 airlines / 200 routes / 200 aircraft / 403 flight records):

| | Before | After |
|---|---|---|
| `mapModel` build | **15.42 ms** | **1.79 ms** |
| — of which `marketOpportunities` | 13.93 ms | 0.47 ms |
| — model without opportunities | 1.36 ms | 1.38 ms |

The whole cost was the opportunity ranking scanning every airport the airline
*touches* against all eighty. Airlines expand from **bases**, not from every
spoke, so origins are now home plus anywhere with three or more routes, capped
at five. That is both the right product answer and an 8.6× speedup.

Other measures taken:

- `GameController` caches the model per tick, so N views in a frame cost one
  build (`UIUX_FORENSIC_AUDIT` UI-016).
- `MapFrame` builds an airport dictionary once per frame; interpolating 50
  flights was doing two linear scans of 80 airports each, 30 times a second.
- Every layer culls against the viewport with a margin before drawing.
- `MapHitGeometry` is deliberately **not** `@Observable`: it is written from
  inside the draw and read only on a tap, and observing it would let a frame's
  own output invalidate the view that produced it.

**Not measured:** actual frame time on a device. Canvas draw cost, gesture
latency and memory under sustained 16× play need Instruments and a phone.

---

## 12. Animation

`TimelineView(.animation(minimumInterval: 1/30))`, paused when the simulation
is paused **or** when Reduce Motion is on.

`MapModel` gives each flight its progress at the tick it was built. The pump
publishes four snapshots a second, so at 1× motion is already smooth — but at
16× a two-hour flight gets about seven updates and the aircraft stutters. So
`InterpolatedFlight.advance` moves a *copy* of the fraction by real time
elapsed × the speed's game-minutes-per-real-second, clamped at 1, and re-syncs
the instant a new snapshot arrives.

Standard client-side prediction. The simulation is never asked, never told and
never affected; determinism is untouched; nothing visual is persisted. Paused
means zero game-minutes-per-second, so nothing moves — which is what the pause
button promises. The clamp at 1 means a marker never reaches the airport before
the simulation lands the flight.

---

## 13. What the model carries

`MapModel` (Core, tested) answers every question the screen asks, so the
renderer never reaches past it into `GameState`:

- **Airports** — tier (from catchment, slot capacity and runway class), region,
  player home / hub / served, player route count, competitor presence and
  bases, slot pressure, weather risk, closure.
- **Routes** — origin and destination, great-circle arc, frequency, load
  factor, `RouteHealth` (grounded / disrupted / weak / healthy / strong),
  operator livery.
- **Flights** — route, aircraft, endpoints, progress, scheduled duration,
  category, delay, ferry flag, livery.
- **Events** — kind, severity, window, the airports they reach, whether they
  are global, and **which of the player's routes they touch**.
- **Opportunities** — the ranked unopened markets, positioned.

`RouteHealth` puts *grounded* above everything: a route with no aircraft is not
"unprofitable", it is not operating, and the map should say so.

---

## 14. Testing

23 tests added in Core (`MapPresentationTests`, `AntimeridianTests`), covering
what a renderer cannot check for itself:

- every airport reaches the map exactly once
- tiers form a real hierarchy and no tier swallows the world
- home / hub / competitor marking matches the routes it claims to describe
- grounded outranks money in route health
- every arc starts and ends on its own airports, inside map bounds
- flight progress, route and endpoints match the simulation's own flight
- **no ghost markers**: drawn flights are exactly the live ones, checked over
  six simulated days
- an airborne flight sits on the great circle between its airports
- events name the airports they actually reach, and only player routes
- a new airline is offered real markets; opportunities never propose a market
  already flown; the ranking is deterministic
- the onboarding card and the map rank the same markets
- antimeridian: raw arcs do wrap, unwrapping removes every jump, shifts are
  whole worlds only, latitude is preserved, ordinary arcs are untouched,
  crossings ask for two world copies, and every real route in the content pack
  stays joined to its airports

**Not tested, because it needs a device:** rendering, gestures, frame rate,
label legibility, colour on a real display.

---

## 15. Known limitations

- **Nothing here has been seen to render.** The app compiles (CI 33244671402);
  the map has never been drawn on a screen. Everything visual is authored.
- **No hub mechanic.** `isPlayerHub` is behavioural — three or more routes —
  because the game has no hub system yet (D-010). When hubs land, this becomes
  a real flag.
- **Antarctica is omitted** and the poles are clipped by the camera clamp. No
  airport is below 47°S.
- **The graticule does not label its meridians.** Deliberate: the numbers would
  be clutter on a game map.
- **Rival aircraft vanish at 16× world zoom.** A readability trade, documented
  in §7, not a bug.
- **No route-opening drag.** You select an airport and tap; there is no
  drag-from-A-to-B gesture yet.
