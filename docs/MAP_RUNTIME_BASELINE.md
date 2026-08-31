# Map runtime baseline — AE-034

> What the map actually does when a finger touches it, established **before**
> changing anything, because the brief's first rule is the project's own:
> AUTHORED ≠ VALIDATED, and a fix for an unmeasured problem is a guess.
> Companions: `MAP_ARCHITECTURE.md` (the design), `UI_RUNTIME_VALIDATION.md`
> (the evidence discipline). Every claim below is labeled:
> **MEASURED** (a number from a real run), **OBSERVED** (a frame looked at),
> **READ** (traced in source, not yet seen moving).

## 0. The reported problems this baseline answers

From the AE-034 brief: dragging feels laggy; the map jumps while dragging;
labels overlap, collide and jump while panning; too much is visible at once;
camera behaviour is unpolished. Each is triaged below with its suspected root
cause. Interaction *feel* cannot be fully observed from this environment —
no human hand, no ProMotion display — so the baseline leans on three honest
instruments: the Linux benchmarks (Core-side cost), a draw-stats probe inside
the live canvas (`MapDrawStats`, `-AEUITestProbes` only), and the UI test
that drags the real map on the booted simulator and reads the probe back
(`testMapInteractionBaselineMeasurements` — MAP TESTS B, C, E, F).
What a person on hardware must still judge is listed in §6.

## 1. What is already right (so no fix churns it)

Verified by reading, and worth writing down before criticising the rest:

- **The simulation is exonerated.** `mapModel` is rebuilt once per sim tick
  (4 Hz), not per frame, and costs **1.96 ms/call at late-game scale**
  (8 airlines, 200 routes, 200 aircraft, **450 live flights**, 5,000 route
  arc waypoints) — MEASURED, `ae-map-bench`, Linux, this commit. Market
  opportunities alone: 0.60 ms. Nothing on the Core side is in the frame
  budget's way.
- Per-polygon bounding-box culling exists for land, lakes and borders, with
  the boxes precomputed at parse time.
- Hit-testing resolves against the geometry the last frame actually drew
  (`MapHitGeometry`), not a recomputed layout.
- The pinch is anchored to the world point under the fingers; limits resist
  rather than clamp dead; a flick coasts on `predictedEndTranslation`
  damped to 45%, off under Reduce Motion.
- Labels are ranked by player relevance and placed greedily by priority —
  the *ranking* is stable frame to frame.
- Three LOD tiers for geography, chosen by zoom.

## 2. P0 — every gesture event rebuilds the entire frame

**READ**, traced end to end; per-frame cost to be MEASURED by the probe.

The drag path is:

```
finger moves (60–120 Hz)
  → dragGesture.onChanged: camera.panOffset = translation   (MapCamera is @Observable)
  → the Canvas closure reads camera.liveZoom / liveCenter    (observation registers)
  → full MapFrame rebuilt and drawn, synchronously, on main
```

There is **no fast path**. A pan is affine — in screen space it is a pure
translation of everything already drawn — yet each finger event re-does, from
scratch (`MapFrame.draw`, `rendersAsynchronously: false`):

| Layer | Work per frame | Scale |
| --- | --- | --- |
| Graticule | full path rebuild × world offsets | ~30 lines |
| Land / lakes / borders | every point of every *visible* polygon re-projected and re-appended | Local LOD totals 28,937 + lakes + 393 border lines; a Europe view keeps thousands after culling |
| Night terminator | 2 passes × 97 trig samples | 194 samples |
| Airport projection | all airports | 94 |
| **Label placement** | full re-run: score + sort 94, then per candidate up to 3 text widths × 4 positions × rect tests against every placed box **and all 94 marker discs** | thousands of rect tests |
| Country labels | full re-placement against airport boxes | 175 candidates |
| Routes | every polyline point re-projected, per visible world copy | **5,000 waypoints** at late-game scale |
| Flight trails | 21 great-circle slerps per airborne player flight | per frame, per flight |
| Flights | `interpolate()` (slerp) for **every** flight *before* the visibility check | **450 at late-game scale** |

Two multipliers make it worse than the table reads:

1. **Gesture invalidations are not throttled by the timeline.** The
   `TimelineView(.animation(minimumInterval: 1/30))` caps *animation* ticks
   at 30 Hz, but each `panOffset` write is a separate invalidation — on a
   120 Hz device the draw is attempted at up to 120 Hz while the finger
   moves, which is precisely when it can least afford to.
2. **The map is capped at 30 FPS by design** the rest of the time. The brief
   targets 60. Both halves are wrong in opposite directions: too many draws
   during the gesture, too few allowed outside it.

**Fix direction (hypothesis, not yet applied):** separate camera motion from
content recomputation. Static geography and route geometry can be built once
per (LOD, world-offset, tick) in map space and replayed under a context
transform; a pan then costs a translation, not a rebuild.

## 3. P0 — label placement runs per frame in screen space, so labels churn

**READ**, with photographic history; churn per frame to be MEASURED.

`MapLabelLayout.place` runs inside every draw. Four mechanisms can each
change a label between two consecutive frames of a pan:

1. The **budget** (`labelBudget`, cap at world = 10): a candidate crossing
   the priority boundary pops in or out.
2. The **text ladder** ("Charles de Gaulle (Paris)" → "Paris" → "CDG"): the
   chosen rung depends on neighbours' screen positions, which change every
   frame of a pan.
3. The **four-position fallback** (above → below → right → left, added in
   AE-033): a label can flip sides of its marker the moment a neighbour's
   disc crosses it.
4. The **viewport-bounds refusal** (AE-033): a label near the screen edge is
   dropped entirely, so panning pops labels at the edges.

Each mechanism is individually correct — AE-033's frames (runs 76–81,
`UI_FULL_AUDIT.md` §6.10–6.14) prove the *static* result converged — but all
four re-decide every frame with no memory of the previous frame. The probe
counts exactly this: identity changes (appear/vanish/text-rung change) and
position hops (movement differing from the shared camera translation) per
compared frame. **The numbers land in §5 when CI reports.**

**Fix direction (hypothesis):** placement with hysteresis — keep last frame's
choices while they remain valid, re-decide on settle/zoom-level change, and
fade rather than pop.

## 4. P1/P2 — the smaller suspects, triaged

- **P1 · 30 FPS cap** (`minimumInterval: 1.0/30.0`) — READ. Deliberate
  battery choice predating this phase; the brief targets 60 minimum. Cannot
  be raised safely until §2's per-frame cost drops.
- **P2 · Edge clamp absorbs the finger** — READ. `clamp` pins
  x∈[0,1], y∈[0.05,0.95] *during* `liveCenter`, so dragging at a world edge
  eats finger motion silently; resuming reads as a jump. The zoom limits got
  resistance-and-spring treatment; the pan limits did not.
- **P2 · `commitPan` computes its world size from `zoom`, not `liveZoom`** —
  READ. Correct when no pinch is active (`pinch == 1`); wrong during a
  combined pinch-drag release. Small, real, and easy to hit with two fingers.
- **P2 · All 450 flights slerp before the visibility check** — READ.
  `drawFlights` interpolates (two trig-heavy great-circle evaluations) for
  every flight, then projects, then culls. At world zoom with rival aircraft
  suppressed at 16×, the interpolation still ran.
- **P3 · Night terminator recomputed per frame** — READ. 194 samples of
  trig for a shape that changes once per game minute.

## 5. Measured interaction numbers — CI probe

*This section is filled from the first CI run carrying the probe
(commit 08f583c). Until those numbers are quoted here with their run number,
every interaction claim above is READ, not MEASURED.*

## 6. What this baseline cannot measure, honestly

- **Feel.** Frame timing bounds it; only a hand on a device judges it.
  ProMotion behaviour (120 Hz) does not exist on the simulator at all.
- **GPU-side cost.** The probe times `MapFrame.draw` — CPU-side path
  building and encoding. Compositing after the closure returns is invisible
  to it. Instruments on hardware remains the authority
  (`tasks/TODO.md`, map runtime validation).
- **Late-game interaction.** The UI tests run a new game (1 route, 1
  flight). The 200-route/450-flight numbers are Core-side only; no UI
  journey reaches that state. Recorded as a gap, not silently scoped away.

## 7. Reproduction

Open Map → zoom twice toward Europe → drag continuously; exactly the
sequence `testMapInteractionBaselineMeasurements` drives (slow strokes,
rapid alternating strokes, zoom cycling), with checkpoints
`B0`–`B3` photographing label state around each sequence.
