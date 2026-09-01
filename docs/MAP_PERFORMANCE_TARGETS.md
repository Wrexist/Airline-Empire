# Map performance targets — AE-034

> The acceptance criteria for the P0 interaction fixes, written **before** the
> implementation so the implementation cannot quietly redefine success.
> Companions: `MAP_RUNTIME_BASELINE.md` (what is being fixed),
> `MAP_ARCHITECTURE.md` (what must not break).

## 1. The shape of these targets

Two kinds, deliberately:

- **Structural targets** — counters and invariants the instrumentation can
  check exactly ("zero full geometry rebuilds per pointer event"). These are
  the real acceptance criteria, because they are deterministic and cannot
  flake with runner load.
- **Timing targets** — milliseconds from the draw-stats probe. These are
  *reported*, before and after, on the same simulator class; they are held to
  "materially better than baseline", not to an absolute frame rate, because a
  CI simulator's clock proves ordering and magnitude, not hardware
  performance. 60 FPS on a device is the goal; **claiming it from a
  simulator number would be fabrication**, so the hardware claim stays open
  until `APPLE_VALIDATION.md` §4 runs on hardware.

## 2. Drag (P0-1)

| # | Target | Kind | How verified |
| --- | --- | --- | --- |
| D1 | A pointer-move event rebuilds **no** geography, route, or label geometry — camera state updates and cached paths replay under an affine transform | structural | cache counters: `rebuilds` does not increase during a drag sequence; `replays` does |
| D2 | Cache invalidation happens only on: zoom drifting past the rebuild ratio, LOD tier change, visible world-offset set change, simulation tick, overlay/selection change, size change | structural | invalidation reasons are counted per cause; a drag sequence shows zero zoom/tick-cause rebuilds it did not earn |
| D3 | The latest camera state always wins — no queued stale rebuilds, no catch-up | structural | by construction (the draw reads current camera state; nothing is enqueued); reviewed, not counted |
| D4 | Average draw cost during the baseline drag sequences is materially lower than baseline, and worst-case draw does not regress | timing | probe deltas on the identical UI test, same runner class, quoted before/after |
| D5 | No visible snap when a gesture settles into the refined frame | observed | consecutive checkpoints around gesture end, compared |

## 3. Labels (P0-2)

| # | Target | Kind | How verified |
| --- | --- | --- | --- |
| L1 | During a continuous drag, label **identity churn is zero**: no label appears, vanishes, or changes its text rung mid-gesture (labels may leave with the world they are pinned to — see L2) | structural | probe `identity` delta ≈ 0 across the drag window (small tolerance for labels scrolled fully off-world) |
| L2 | During a continuous drag, **position hops are zero**: every label moves exactly with the camera translation | structural | probe `hops` delta = 0 across the drag window |
| L3 | Re-placement happens deliberately: on settle, on LOD change, on tick, on selection change — not per frame | structural | placement-run counter increments match those events, not the frame count |
| L4 | Hysteresis at edges: a label is not dropped for being one point past a bound and restored one point back | structural | placement policy uses distinct enter/exit margins; unit-tested |
| L5 | The settled re-placement may add, remove and re-rank labels — the reveal ladder from AE-033 is unchanged in *what* it shows, only in *when* it decides | correctness | existing zoom-reveal UI test still passes; frames compared |

## 4. Correctness invariants (must not move)

- Antimeridian: a Pacific arc still leaves one edge and enters the other
  (`AntimeridianTests`, 7 tests, plus the world-offset replay).
- Hit-testing still resolves against the geometry the last frame actually
  drew — including during a drag, when that geometry is a transformed cache.
- Zoom anchoring (pinch about the fingers), limit resistance and spring-back
  are unchanged.
- Camera bounds are unchanged.
- The player's network is never hidden at any zoom.
- Core is untouched: 414/414 before, 414/414 after, and no save-format edit.

## 5. Cadence and simulation independence

- Simulation ticks (4 Hz) invalidate content caches; gestures never block or
  re-order simulation delivery.
- The 30 Hz ambient timeline stays as-is in this phase (it is a deliberate,
  documented battery choice); gesture- and animation-driven invalidations
  already exceed it during interaction, which is where responsiveness is
  felt. Raising the ambient cadence is a separate decision to take with
  hardware evidence, not a simulator number.

## 6. Memory

Cached paths are bounded: at most one geography path set per (LOD, layer),
one route path set per style bucket, and the label memory of the last
placement (≤ ~30 entries). No per-frame allocations of point arrays for
static geometry. Order-of-magnitude: the Local-LOD point set is ~29k points
≈ a few hundred KB as `Path` storage — held once, not rebuilt 30× a second.

## 7. What is explicitly not claimed

- Hardware frame rates (no device in this environment).
- GPU/compositor cost (the probe times CPU-side path building and encoding).
- ProMotion behaviour.
- Late-game (200-route / 450-flight) *interaction* numbers — no UI journey
  reaches that state; the Core-side cost is measured and the renderer's
  scaling argument is structural (per-frame work no longer proportional to
  waypoint count during gestures).
