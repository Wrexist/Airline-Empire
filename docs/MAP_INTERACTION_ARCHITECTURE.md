# Map interaction architecture — AE-034

> How a finger move becomes a frame, after the P0 fixes. Companions:
> `MAP_RUNTIME_BASELINE.md` (the measured problem), `MAP_PERFORMANCE_TARGETS.md`
> (the acceptance criteria), `MAP_ARCHITECTURE.md` (the rendering design this
> sits inside).

## 1. The two paths

```
ACTIVE INTERACTION (per gesture event / animation frame)
  finger → camera state (panOffset / pinch)          O(1)
         → cached paths replayed under one           O(layers)
           uniform scale + translation
         → per-frame dynamic pass                    O(visible airports
           (airports, flights, labels-from-memory)     + airborne flights)

DELIBERATE RECOMPUTATION (counted, per cause)
  rebuild geography | rebuild routes | re-place labels
```

The old architecture had only the second path and ran it per finger event —
16.84 ms average, 256 ms worst (baseline §5). The fast path exists because
the projection is affine: `screen = (map − center) · worldSize + viewport/2`,
and both world dimensions scale with zoom, so any camera change maps
already-projected geometry by one uniform scale `s = zoom/builtZoom` plus a
translation. Stroke widths and dashes are divided by `s` at replay so line
weights hold while geometry scales.

## 2. Cache ownership and lifetime

One `MapRenderCache` per map screen, owned by `MapView` as plain `@State` —
a class, deliberately **not** `@Observable`, because it is read and written
from inside the draw and observing it would let a frame's own output
invalidate the view that drew it (the same rule as `MapHitGeometry`). It
dies with the screen; nothing outlives navigation.

| Cache | Contents | Space | Bound |
| --- | --- | --- | --- |
| Geography | graticule, equator, land, lakes, borders, terminator | screen space at built camera | one set |
| Routes | per-route strokes (glow + main, rivals-under-players order) + hit polylines | screen space at built camera | one set |
| Label memory | last placement's decisions (code, text rung, side offset) + country anchors in map space | decisions, not pixels | ≤ ~30 airport + ~18 country entries |
| Trail arcs | full great-circle samples per player flight | map space | one per live player flight, cleared per tick |

## 3. Invalidation, exhaustively

Every rebuild is counted by cause and published through the probe
(`cache rebuilds N replays M placements P reasons […]`), so the structural
targets are verified by deterministic counters rather than wall clock.

| Trigger | Geography | Routes | Labels |
| --- | --- | --- | --- |
| LOD tier change | rebuild | rebuild | re-place |
| Canvas size / world-offset set change | rebuild | rebuild | re-place |
| Game hour change | rebuild (terminator) | — | — |
| Simulation tick (4 Hz) | — | rebuild (health/frequency restyle) | re-place |
| Overlay change | — | rebuild | — |
| Selection change | — | rebuild (selected route leaves the cache) | re-place |
| Gesture settles (`MapCamera.settleGeneration`) | — | — | re-place |
| Zoom drifts past ±25% of built zoom | rebuild | rebuild | re-place |
| Pan beyond 80% of the 0.75-screen headroom | rebuild | rebuild | re-place |
| **A finger move** | **never** | **never** | **never** |

The headroom is why a replayed pan never reveals unbuilt world: builders
cull against the viewport expanded by 0.75 screens per side and the rebuild
fires at 80% of that. The latest camera state always wins by construction —
nothing is enqueued; each draw reads the camera as it is.

## 4. Label memory

Placement is a decision; the baseline measured deciding per frame (3.92
identity changes/frame while panning). Between placements the remembered
choices — airport, text rung, side offset — re-project with the camera, so
labels move exactly with the world. Placements are stable across each other
too: the placer is seeded with its previous memory, keeping text and side
while they still fit, with enter/exit hysteresis at the viewport (8 pt in to
appear, 12 pt out to leave) and a 0.4-zoom grace on reveal thresholds, so a
settle two pixels from the last one changes nothing. The reveal ladder
itself (what appears at which zoom) is unchanged from AE-033 — only *when*
it is consulted moved.

## 5. Hit-testing under replay

The honesty rule — a tap resolves against what was actually drawn — held by
testing from the other side: route polylines stay in the cache's screen
space, and `MapHitGeometry` carries the tap through the inverse of the
displayed transform (and scales the tolerance with it). One point is
transformed instead of five thousand waypoints re-projected. Airports and
flights are projected per frame and tested in current space; the selected
route is drawn per frame (halo under its own stroke) and tested in current
space via its own slot.

## 6. What deliberately stayed per-frame

Ocean fills (two), event fields, opportunity arcs, airport markers (~94
projections and a handful of circles), flights (interpolated after an
endpoint-bbox precull), trail prefixes (one slerp per flight for the moving
tip), and label re-projection from memory. All O(visible), none O(world).

## 7. Known limits, stated

- During a pinch, replayed stroke dashes scale with `s` until the ±25% band
  triggers a rebuild — visible only as slightly stretched dashes mid-pinch.
- The ambient timeline remains 30 Hz (a documented battery choice);
  gesture- and animation-driven invalidations exceed it during interaction,
  which is where responsiveness is felt. Raising it is a hardware-evidence
  decision, recorded in TECH_DEBT.
- Pan at the world's y-clamp still absorbs the finger silently (baseline
  §4); the resistance-and-spring treatment the zoom limits have is future
  work, recorded in TECH_DEBT.
