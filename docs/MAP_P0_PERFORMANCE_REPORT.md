# Map P0 performance report — AE-034 before/after

> The measured outcome of the two P0 fixes (render cache + transform
> replay; label placement memory). BEFORE is run 84 (commit 08f583c,
> pre-fix probe); AFTER is run 85 (commit 191fd7a, all fixes). Same test
> (`testMapInteractionBaselineMeasurements`), same workload (4 slow
> strokes, 6 fast alternating strokes, 3×3 zoom cycles), same
> macos-26/iPhone-16-Pro simulator runner. All numbers **MEASURED** by
> the in-app probe; everything else is labeled. Companions:
> `MAP_RUNTIME_BASELINE.md` (§5, the BEFORE evidence),
> `MAP_PERFORMANCE_TARGETS.md` (the acceptance criteria),
> `MAP_INTERACTION_ARCHITECTURE.md` (what changed).

## 1. The table

| METRIC | BEFORE (run 84) | AFTER (run 85) | CHANGE | STATUS |
| --- | --- | --- | --- | --- |
| Slow drag: avg draw | 16.84 ms | 11.39 ms | −32 % | IMPROVED |
| Slow drag: frames drawn (same 4 strokes) | 53 | 96 | +81 % | IMPROVED |
| Slow drag: label identity churn / frame | 3.92 | 1.35 | −66 % | IMPROVED |
| Slow drag: label position hops / frame | 1.72 | 0.40 | −77 % | IMPROVED |
| Fast drag: avg draw | 22.06 ms | 11.40 ms | −48 % | IMPROVED |
| Fast drag: frames drawn (same 6 strokes) | 37 | 56 | +51 % | IMPROVED |
| Fast drag: churn / frame | 8.05 | 3.89 | −52 % | IMPROVED |
| Fast drag: hops / frame | 2.78 | 0.55 | −80 % | IMPROVED |
| Worst frame anywhere in the run | 256.31 ms (mid fast drag) | 169.18 ms (the map-open first frame) | −34 % | IMPROVED |
| Zoom cycles: avg draw | 12.31 ms | 11.16 ms | −9 % | IMPROVED |
| Zoom cycles: churn / frame | 24.50 | 14.55 | −41 % | IMPROVED |
| Zoom cycles: hops / frame | 8.72 | 10.20 | +17 % | **WORSE** |
| Core tests | 414/414 | 414/414 | — | PASS |
| Map baseline test | passed | passed | — | PASS |
| UI suite | 16/16 | 15/16 | one flake, §4 | see §4 |

## 2. What the numbers mean, and their limits

- The **worst frame after the fix is the map's opening frame** (the first
  full cache build, 169 ms). No interaction frame in the entire AFTER run
  exceeded it; before the fix, a rapid drag alone produced a 256 ms
  stall. The one remaining stall candidate is screen entry, once.
- **Frames drawn went up ~80 %/~50 % for the identical gestures**: the
  draw now keeps pace with the gesture event rate instead of dropping
  events. This — not the avg alone — is the "map no longer catches up"
  evidence a static number can give. Smoothness on a device is still
  **not claimed**; these are simulator CPU numbers for `MapFrame.draw`.
- The residual ~11.3 ms avg is dominated by the per-frame dynamic pass
  and, at each stroke's end, the settle re-placement; it sits inside a
  60 fps budget on this simulator where the BEFORE numbers did not.
- **The one worse number is honest and diagnosable**: hops/frame during
  zoom *cycling* rose 8.72 → 10.20 (total hops 157 → 204). Zoom commits
  are settles, and every settle legitimately re-decides placement; nine
  zoom commits re-rank labels nine times by design. What the drags show
  (hops 0.40/0.55) is that placement is now stable under *movement*; the
  zoom-cycle figure measures deliberate re-decisions per (much fewer)
  drawn frames. Decomposing it needs the cache counters below.

## 3. An instrumentation gap, stated

The probe's counter line gained a `placements N` token in the P0-2
commit, and the test's log-forwarding regex (`MAP-CACHE …`) was not
updated to match — so run 85 carries **no cache rebuild/replay/placement
counters**, and the structural targets (D1: zero rebuilds mid-gesture;
L1–L3: placements ≈ settle events) are verified this run only indirectly
(the timing/churn deltas above and the frame inspection in §5). The
regex is fixed; the next CI run carries the counters. Until it lands,
"rebuilds were flat during drags" is **NOT VALIDATED** as a counted
fact — deliberately not claimed.

## 4. The one red test

`testAcquireAircraftThenOpenARoute` failed: its lease tap opened the
"Buy used (8y)?" dialog — the row one pitch above — on attempts 1 *and*
3, with the list photographed perfectly still, then exhausted retries.
Two other tests in the same run lease successfully with the same helper,
so the app path is fine; the miss is stale accessibility geometry, off
by exactly one reported row pitch. The helper now measures that pitch
from the wrong dialog itself and corrects the aim on later attempts.
Verification: next CI run.

## 5. Visual validation (OBSERVED, run 85 decoded frames)

Looked at, not just collected: B0–B3 (before/after each drag and zoom
sequence), KEY-70–75 (each zoom tier + double-tap + pinch), KEY-81/82
(flight en route at two zooms), KEY-86/87 (selection at two zooms),
dark and light map variants. Checked for the cache-failure classes:
missing land at screen edges (headroom), wrong stroke widths (replay
compensation), stale or duplicated routes, labels floating off markers,
terminator misplacement, content snapping after settle. **None found**;
compositions match run 84's equivalents. Known cosmetic issue that
remains (pre-existing, both runs): labels clipped at the screen edge
when their anchor is just offscreen (`GAME_EXPERIENCE_PRIORITY.md`
EXP-03). Not covered by any frame: antimeridian routes and late-game
density — no scripted scenario produces them; listed as untested rather
than assumed fine.

## 6. Regression protection

- The probe + MAP-BASELINE deltas run on every CI pass; the baseline
  test asserts frames advance and the format is a parse contract.
- Counter *assertions* (e.g. "rebuild delta during a drag == 0") are
  deliberately deferred one run: pinning a bound before the first
  counted run would be a guess, and a wrong bound gets a test disabled.
  Add them from the first MAP-CACHE-carrying run's evidence.
