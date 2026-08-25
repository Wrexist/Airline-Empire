# Airline Empire — Simulation Architecture

> Phase 1 document; Phase 3 implements it and appends the "as-built" section.
> Binding rules marked **[RULE]**.

## 1. Time model

- `SimTime` = integer **minutes** since scenario epoch (Int64). Wraps never
  (5.8M game-years fit in Int32; Int64 is free insurance).
- `GameDate` (year/month/day/hour/minute, plus weekday and season) is
  *derived* from `SimTime` by a pure calendar (365-day year, 12 months,
  simplified but stable — no leap years, documented in-game).
- **Base tick = 15 game-minutes.** Chosen so a game-day is 96 ticks: fine
  enough for flight phases (shortest turnaround ≈ 30 min), coarse enough
  that a game-year ≈ 35k ticks stays cheap. Changing tick size is a save-
  format-relevant decision (**[RULE]** — requires decision entry + migration).
- **Cadences:** systems subscribe to `everyTick`, `hourly`, `daily`,
  `weekly`, or `monthly` boundaries, computed from `SimTime`. Heavy
  economics run daily/weekly; only flight-phase advancement and clock/event
  bookkeeping run per-tick.

## 2. Determinism

- **RNG:** SplitMix64-based `SeededGenerator`, one independent substream per
  (system, purpose) pair, derived as
  `substreamSeed = hash(worldSeed, streamLabel)` with a stable
  non-Foundation hash (FNV-1a over UTF-8; **[RULE]** never
  `Swift.Hashable.hashValue`, which is process-seeded). Substream states are
  part of `GameState.rng` and serialize with the save.
- **[RULE] Draw discipline:** a system draws only from its own substreams;
  draws happen in loops ordered by sorted entity ID. Adding/removing a
  system never shifts another's sequence.
- **[RULE] Iteration order:** any dictionary iteration whose effects touch
  state or RNG iterates over sorted keys (helper: `state.orderedAirlines`
  etc.). Determinism tests hash full state after N ticks across two runs and
  across command-replay.
- **Floating point:** `Double` allowed in intermediate math (demand curves,
  distances); results that persist are quantized (money → cents via one
  rounding choke point; probabilities compared against RNG draws directly).
  No transcendental-function results are stored unquantized across
  platforms' math-library seams: gameplay-critical curves use polynomial /
  table forms defined in content, not `libm` behavior.
- **Command log:** commands are recorded with their tick into a bounded
  replay window (debug/QA builds unbounded) enabling: replay tests, bug
  repro from saves, and Phase 19 adversarial testing.

## 3. Engine loop

```
SimulationEngine.advance(ticks: n):
  for each tick:
    1. clock.advance(tickDuration)
    2. drain command queue (in submission order; validate → apply → emit)
    3. for system in pipeline where system.cadence fires at this SimTime:
         system.update(&state, context)   // context: catalog, rng access, emitter
    4. integrity checks (debug builds)
    5. append emitted events to bounded log; publish snapshot if due
```

- Commands submitted mid-tick batch apply at the *next* tick boundary —
  the UI is asynchronous anyway; determinism requires a defined point.
- `advance` is synchronous and reentrancy-free; `GameSession`'s actor is the
  only caller. Fast-forward = larger `n` per real-time slice, chunked so the
  actor stays responsive to pause commands (**[RULE]** chunk ≤ 1 game-day
  between command-queue drains).
- Pause = no `advance` calls. Speed = scheduler frequency in `GameSession`.
  Neither exists inside the engine (§4 ARCHITECTURE.md).

## 4. System pipeline (fixed order, Phase-1 design)

Order encodes causality for one tick; each system reads what earlier systems
wrote this tick and what later systems wrote last tick.

| # | System | Cadence | Responsibility (implementing phase) |
|---|--------|---------|-------------------------------------|
| 1 | WorldSystem | daily + event-driven | season, macro cycle, fuel price walk, world-event lifecycle (11) |
| 2 | DemandSystem | daily | per-market base demand from demographics × season × events × economy (7) |
| 3 | CompetitorAISystem | daily (staggered per AI) | AI decisions → commands into next drain (10) |
| 4 | ScheduleSystem | daily | materialize `Flight` instances from route schedules; slot & conflict checks (6) |
| 5 | FlightOpsSystem | everyTick | advance flight phases, disruptions, arrivals, turnarounds (6) |
| 6 | PassengerAllocationSystem | per departure | allocate demand → seats at departure using price/quality shares (7) |
| 7 | MaintenanceSystem | daily | wear, condition, checks, groundings (5) |
| 8 | EconomySystem | daily + per flight-completion | post revenues/costs to ledger, lease/loan/payroll/fee schedules (8) |
| 9 | ReputationSystem | daily | punctuality/service/satisfaction indices → reputation components (9) |
| 10 | ProgressionSystem | daily | milestones, achievements, unlocks (12) |
| 11 | AnalyticsRollupSystem | daily/monthly | bounded history series, statement rollups (8/13) |

**[RULE]** Systems conform to `SimulationSystem { cadence; update(&GameState, SimContext) }`,
are stateless values (all state in `GameState`), never call each other, and
are registered once in this documented order. Reordering = decision entry.

## 5. Snapshots

A snapshot is just a copy of the `GameState` value (COW makes it cheap) plus
derived read-model conveniences computed lazily app-side. Published to the
UI at most once per frame-ish interval and on demand; saves serialize the
same value. **[RULE]** The UI holds snapshots only — never the live state.

## 6. Testing obligations (Phase 3 acceptance)

- Time: tick→date derivations, cadence boundary detection (incl. month ends),
  long-run overflow sanity.
- Determinism: dual-run state-hash equality (1 game-year); replay equality;
  substream independence (adding a dummy system leaves others' draws
  unchanged).
- Commands: validation rejections, batch ordering, mid-fast-forward
  submission.
- Pause/resume/speed: state identical regardless of chunking pattern for the
  same total ticks (chunk-invariance test).
- Save-safe: serialize → restore → continue ⇒ identical to uninterrupted run
  (the single most important test in the project — **[RULE]** runs in CI on
  every change from Phase 3 onward).
