# Airline Empire — Master Architecture

> **Status: AUTHORED (Phase 1).** This is the architectural constitution of
> Airline Empire. Every later phase implements *within* this architecture.
> Changes to anything marked **[RULE]** require a new entry in
> `/tasks/DECISIONS.md`.
>
> Companion documents: `DOMAIN_MODEL.md` (entities and relationships),
> `SIMULATION_ARCHITECTURE.md` (engine internals), `PERSISTENCE_ARCHITECTURE.md`
> (saves), `UI_ARCHITECTURE.md` (presentation), `TECHNICAL_STANDARDS.md`
> (coding standards).

## 1. Architectural goals

Ranked. When goals conflict, the higher one wins.

1. **Correct, deterministic simulation** — same seed + same commands ⇒ same
   world, on every device, forever.
2. **Testability** — every game rule verifiable headlessly, without UI, on
   Linux or macOS.
3. **Player trust** — no lost progress, no corrupt saves, explainable numbers.
4. **Performance at scale** — thousands of entities (aircraft, routes,
   flights, competitor networks) on an iPhone, offline.
5. **Five-year extensibility** — cargo, alliances, subsidiaries etc. (Phase 24
   candidates) must slot in without rewrites.
6. **UI independence** — the game is complete without any particular frontend.

## 2. Layer map

```
┌────────────────────────────────────────────────────────────┐
│  AirlineEmpire (iOS app target — macOS-built, thin)        │
│  SwiftUI views · view models · map renderer (SpriteKit/    │
│  Canvas) · haptics · audio · scene lifecycle · settings UI │
└──────────────────────────┬─────────────────────────────────┘
                           │ GameSession (async boundary)
┌──────────────────────────┴─────────────────────────────────┐
│  AirlineEmpireCore (SwiftPM package — Foundation-only)     │
│                                                            │
│  Application services   GameSession · SaveManager ·        │
│                         ScenarioBootstrap · LocalAnalytics │
│  Simulation engine      SimulationEngine · Clock · RNG ·   │
│                         Command queue · Event log ·        │
│                         System pipeline · Snapshots        │
│  Domain systems         Flights · Demand · Economy ·       │
│                         Maintenance · Reputation · AI ·    │
│                         WorldEvents · Progression          │
│  Domain model           GameState + entity value types     │
│  Content                ContentCatalog (airports, aircraft,│
│                         events, tuning) + validation       │
│  Persistence            Versioned save codec · migrations ·│
│                         atomic file store                  │
└────────────────────────────────────────────────────────────┘
```

**[RULE] Dependency direction is strictly downward.** The Core package never
imports SwiftUI, UIKit, SpriteKit, Combine, or any app module. The app never
reaches around `GameSession` into engine internals. Enforced by the package
boundary (D-002, ratified).

**[RULE] No third-party dependencies in Core.** Foundation (and Swift
standard library) only. The app target may add Apple frameworks freely but no
external packages without a decision entry.

## 3. State architecture

### 3.1 Single root value

The entire mutable world is one value type:

```swift
struct GameState: Codable, Equatable {
    var meta: GameMeta                 // save version, scenario, seed, difficulty
    var clock: ClockState              // current SimTime, speed, pause
    var world: WorldState              // market conditions, fuel price, season, active world events
    var airlines: [AirlineID: Airline] // player + competitors, same type
    var aircraft: [AircraftID: Aircraft]
    var routes: [RouteID: Route]
    var flights: [FlightID: Flight]    // live flight instances only
    var ledger: Ledger                 // transactions, statements (player + AI)
    var progression: ProgressionState  // milestones, unlocks, achievements
    var rng: RNGState                  // seeded stream states (serialized!)
    var eventLog: BoundedEventLog      // recent SimEvents for UI/analytics
}
```

**[RULE] All game state lives in `GameState`.** No system, service, or view
model holds authoritative game data. Anything not reachable from `GameState`
is, by definition, presentation or cache and may be destroyed at any time.

**[RULE] `GameState` is a pure value type** (structs, enums, value
collections). Copy-on-write gives cheap snapshots for UI and saves; value
semantics eliminate aliasing bugs and make Equatable-based determinism tests
possible.

**[RULE] The player's airline is an `Airline` like any other.** Competitors
run through the same economic systems (Phase 10 requirement). Player-only
concerns (camera, notifications) live outside `GameState.airlines`.

### 3.2 Mutation model

Exactly two things mutate `GameState`:

1. **Commands** — player/AI intents (`buyAircraft`, `openRoute`,
   `setTicketPrice`, `takeLoan` …). Validated against current state; rejected
   commands produce a typed `CommandRejection`, never a crash or silent no-op.
2. **The tick pipeline** — ordered systems advancing the world one time step.

**[RULE] No other mutation path exists.** UI never writes state directly.
This is what makes the game deterministic, replayable, and save-safe.

### 3.3 Events

Systems and commands emit `SimEvent`s (flight departed, loan payment taken,
competitor opened route, milestone reached…). Events are **outputs, not
inputs**: replaying commands over ticks regenerates all events. Events feed
the UI feed, notifications, local analytics, and achievement checks.

## 4. Simulation engine (summary — full detail in SIMULATION_ARCHITECTURE.md)

- **Time** is integer minutes since scenario epoch (`SimTime`). One tick = a
  fixed number of game minutes. Systems declare cadence (per-tick, hourly,
  daily, weekly, monthly). **[RULE] No wall-clock, no `Date()`, no
  frame-delta inside Core.**
- **Randomness** is a seeded, serializable generator with named substreams
  per system, so adding a system never perturbs another system's draws.
  **[RULE] `SystemRandom`/`Double.random` etc. are banned in Core.**
- **Ordering** is a fixed, documented pipeline (see §5 of
  SIMULATION_ARCHITECTURE.md). **[RULE] Systems never call each other**; they
  communicate only through state written earlier in the pipeline.
- **Concurrency:** the engine is single-threaded inside one dedicated
  execution context (an actor owned by `GameSession`). Parallelism, if ever
  needed, happens *inside* a system over disjoint data — never across systems.
- **Speed/pause** scale how many ticks run per real second; they are
  presentation-driver concerns and never change tick semantics.

## 5. Money, units, and numeric policy

- **Money is `Int64` cents** (`Money` type). **[RULE] No floating-point
  balances, ever.** Intermediate economic math may use `Double`, but every
  amount entering the ledger is rounded by a single documented rule
  (banker's-free: round half away from zero) at a single choke point.
- Distances in kilometers (`Double`), fuel in kg, capacities as `Int`.
  All quantities are typed wrappers, not bare numerals (TECHNICAL_STANDARDS §3).
- **[RULE] Every financial mutation goes through the `Ledger`** as a
  categorized `Transaction` with source entity, category, and timestamp —
  this is what makes Phase 8's "where did my money go?" answerable and is
  cheaper to build in from day one than to retrofit.

## 6. Content architecture

Static content (airport database, aircraft types, event definitions, tuning
constants) ships as versioned JSON resources inside the Core package, loaded
into an immutable **`ContentCatalog`** at startup.

- **[RULE] Content is data, not code.** No airport or aircraft literals in
  logic. Balance tuning constants live in a `Tuning` content file, not as
  magic numbers.
- Loading validates referential integrity (unknown IDs, negative capacities,
  unreachable airports) and fails loudly in development builds.
- `ContentCatalog` is immutable and passed by reference (a final class) —
  it is *not* part of `GameState`; saves reference content by stable string
  IDs plus a content version for forward compatibility.

## 7. Persistence (summary — full detail in PERSISTENCE_ARCHITECTURE.md)

- Saves serialize `GameState` in a versioned envelope; **format version is
  written from the very first build** (D-004).
- Atomic write (temp file + fsync + rename), rolling backup generation,
  corruption detection via checksum, migration chain v1→vN.
- Autosave at scene-background and every N game days; save is a snapshot of
  the value-typed state, so it never blocks or tears mid-tick.

## 8. Application services

- **`GameSession`** — the single façade the app talks to: start/load/save
  game, submit commands, subscribe to state snapshots and events, control
  speed/pause. Owns the simulation actor and the autosave policy.
- **`ScenarioBootstrap`** — builds a new `GameState` from a scenario
  definition (starting airport, cash, difficulty, seed).
- **`LocalAnalytics`** — append-only, on-device gameplay metrics (route
  profitability history, net-worth curve) for in-game charts. No network.
  Bounded storage.
- **`SaveManager`** — slots, autosave, migration orchestration.

## 9. UI architecture (summary — full detail in UI_ARCHITECTURE.md)

- SwiftUI + `@Observable` view models; one view model per screen area,
  subscribing to `GameSession` snapshots; commands go back through
  `GameSession`. **[RULE] No business rules in views or view models** —
  view models format and forward, nothing else.
- The map is a renderer of simulation state (airports, routes, live flights
  interpolated between ticks for smoothness — interpolation is presentation
  only and never feeds back into the simulation).
- Design system components (Phase 14) live in the app target.

## 10. Error-handling policy

- **Command rejections are values**, surfaced to the player with reasons.
- **Content/load errors** fail fast at startup in dev; in release, missing
  optional content degrades, corrupt saves fall back per
  PERSISTENCE_ARCHITECTURE §6 (backups), and the player is told the truth.
- **[RULE] The simulation never throws mid-tick.** Systems are total
  functions over valid state; invalid states are prevented at the command
  boundary and by construction (typed IDs, non-optional invariants).
  `precondition` guards internal invariants in debug; violations are bugs to
  fix, never to catch.

## 11. Performance architecture

Budgets (validated in Phase 20, designed for now):

- A daily tick over a late-game world (≈100 airports active, ≈300 aircraft,
  ≈500 routes, 8 competitors) must run well under one UI frame; a simulated
  game-year of fast-forward under 10 s on an A15.
- Achieved structurally by: value-type state with COW (no allocation storms),
  dictionary-keyed entities with typed IDs, cadenced systems (heavy economics
  daily/weekly, not per-tick), event log bounded, demand computed per
  route-day not per passenger (passengers are aggregated quantities, not
  entities — **[RULE]**), map rendering decoupled from tick rate with LOD.
- **[RULE] No system may iterate all entity pairs** (O(n²)) without a
  decision entry; competition lookups go through per-market indices
  maintained incrementally.

## 12. Extensibility strategy

- New gameplay = new system in the pipeline + new state slice + new content
  files + new commands/events. Existing systems unchanged.
- Save migrations make state slices addable; content versioning makes data
  addable; the event enum is extended (never reused) case by case.
- Phase 24 candidates (cargo, alliances, subsidiaries, staff depth) each map
  to this recipe — cargo, for instance, is a demand segment + fleet
  capability + revenue category, all of which have seams reserved (demand
  segments are an enum with associated data; `Transaction.Category` is
  extensible; `AircraftType` carries capability flags).

## 13. Architectural risks (tracked)

| Risk | Mitigation |
|------|------------|
| Value-type `GameState` grows until copies hurt | COW collections already amortize; snapshots are taken at most once per UI frame; measure in Phase 20 before any redesign. |
| Determinism broken by `Dictionary` iteration order | **[RULE]** any iteration whose order affects outcomes must iterate sorted keys or stable arrays; determinism tests (same seed twice ⇒ identical state hash) run in CI from Phase 3. |
| Double non-determinism across architectures | Only x86_64/arm64 IEEE-754 basic ops are used (no FMA-dependent tuning, no `sin/cos` in gameplay-critical paths without tolerance); determinism tests run on both architectures. |
| Save format churn phases 3–13 | Versioning from first byte (D-004); migrations tested with fixture saves per version. |
| AI phase (10) tempted to cheat with private APIs | AI acts only via the same `Command` set as the player (**[RULE]**). |
| UI phase (14+) tempted to read engine internals | Only `GameSession` is `public` in Core beyond model/read types. Access control enforces the façade. |

## 14. Decisions ratified in this phase

- **D-002 ratified:** Core SwiftPM package + thin iOS shell.
- **D-005:** single value-type `GameState`, command/tick-only mutation.
- **D-006:** integer time (minutes) and integer money (cents); deterministic
  rounding at ledger boundary.
- **D-007:** fixed-timestep cadenced pipeline; aggregate passengers.
- **D-008:** single simulation actor; snapshot-based UI delivery.

See `/tasks/DECISIONS.md` for full context and consequences.
