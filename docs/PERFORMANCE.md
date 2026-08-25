# Airline Empire — Performance (Phase 20, headless scope)

## Benchmark harness

`swift run -c release ae-bench` (Sources/AEBench) — deterministic worlds at
three scales, measuring game-year fast-forward wall time and save codec
cost. Measured 2026-08-25 on the Linux CI environment (4-core x86_64;
single-thread perf roughly comparable to modern iPhone big cores).

## Results (release build)

| World | 1 game-year | Live flights | Save size | Encode / decode |
|---|---|---|---|---|
| 2 airlines × 5 routes (10 aircraft) | 0.45 s | 40 | 251 KiB | 30 / 20 ms |
| 4 × 15 (60 aircraft) | 1.64 s | 161 | 363 KiB | 40 / 30 ms |
| 8 × 25 (200 aircraft, 200 routes) | 3.66 s | 348 | 607 KiB | 60 / 40 ms |

## Conclusions (evidence-based; no premature optimization)

1. **Budget met.** ARCHITECTURE §11 target: late-game year < 10 s.
   The 200-route/200-aircraft world runs 3.66 s/year; scaling is linear in
   entity count (0.45 → 1.64 → 3.66 across ~4× steps), so even a 500-route
   monster projects ~9 s — inside budget with no optimization work.
   A daily tick at this scale ≈ 0.1 ms — invisible next to a UI frame.
2. **Debug ≠ release.** The test suite's slower sims are dominated by the
   per-tick `assert(integrityViolations())` sweep, which compiles out of
   release builds. This is working as designed (heavy invariants in
   debug/CI, zero cost shipped) — do not "fix" test-time speed by weakening
   the sweep.
3. **JSON saves are fine.** 607 KiB / 60 ms at late-game scale: the binary
   codec contemplated in PERSISTENCE_ARCHITECTURE §1 is not justified by
   measurement; revisit only if devices disagree.
4. **No hotspots worth touching.** Sorting entity IDs per tick and the
   bounded event ring are microscopic at realistic populations (hundreds of
   entities); the pipeline's cadence design (heavy systems daily, only
   flight-phase advancement per tick) is doing its job.

## Remaining (macOS/Instruments queue)

UI rendering, map Canvas frame cost at zoom levels, startup time, memory
footprint on device, background/foreground transitions, battery — all need
the running app; they join the Phase 14–17 macOS work with the budgets in
ARCHITECTURE §11 (snapshot→frame work O(visible), map LOD verified there).
