# Airline Empire — Technical Standards

> Phase 1 document. Binding for all code in this repository. Deviations
> require a `/tasks/DECISIONS.md` entry.

## 1. Language & toolchain

- Swift 6.x, SwiftPM. Core package: `swift-tools-version: 6.0`,
  platform-agnostic (builds on Linux + macOS; iOS 17+ when consumed by app).
- Strict concurrency checking enabled (`StrictConcurrency` / Swift 6 mode).
- Zero warnings policy: warnings are errors in CI mindset — fix, don't
  accumulate.
- Linux toolchain for agent sessions: `scripts/setup-linux-toolchain.sh`
  (installs Swift 6.0.3 from the GitHub mirror; see script header).

## 2. Project layout

```
AirlineEmpireCore/
  Package.swift
  Sources/AirlineEmpireCore/
    Foundation/      // SimTime, GameDate, Money, SeededGenerator, typed IDs, FNV hash
    Domain/          // GameState + entity types (one file per entity family)
    Simulation/      // engine, clock, pipeline, commands, events, context
    Systems/         // one file per SimulationSystem
    Content/         // ContentCatalog, specs, loaders, validation
    Persistence/     // envelope, codec, store, migrations
    Session/         // GameSession, ScenarioBootstrap, SaveManager, LocalAnalytics
  Sources/AirlineEmpireCore/Resources/   // airports.json, aircraft.json, tuning.json, …
  Tests/AirlineEmpireCoreTests/          // mirrors Sources structure
scripts/             // toolchain setup, CI helpers, balance-sim runners
AirlineEmpire/       // iOS app target (created in Phase 14 on macOS)
docs/  tasks/
```

## 3. Code rules

- **Typed everything:** IDs are typed wrappers; quantities with units are
  wrappers (`Money`, `SimTime`, `Distance`, `FuelMass`). No bare `Int`
  crossing an API meaning "cents" or "minutes".
- **No magic numbers:** gameplay constants live in `Tuning` content;
  structural constants are named `static let`s with a comment stating *why
  that value*.
- **Value types first:** structs/enums for all domain data; classes only for
  identity-bearing services (`ContentCatalog`, `GameSession`, stores).
- **No global mutable state.** No singletons. Dependencies injected via
  initializers; systems receive `SimContext`.
- **Access control is architecture:** `public` in Core is only the session
  façade, snapshot/read models, commands, events, and content specs. Engine
  internals are `internal`; `@testable import` is for tests only.
- **Errors:** typed errors / result types at boundaries (commands, IO);
  `precondition` for internal invariants; no `try!`/`as!` outside tests; no
  silently swallowed catches.
- **Naming:** domain vocabulary from DOMAIN_MODEL.md; systems end in
  `System`; commands are imperative verbs; events are past tense.
- **Comments** state non-obvious constraints and rationale ("why"), not
  narration. Public API in Core gets doc comments. Formulas cite their doc
  (e.g. `// demand share model: docs/ECONOMY.md §3`).
- **Banned in Core:** `Date()`/`.now` (except in persistence metadata
  clearly outside simulation), `SystemRandomNumberGenerator`,
  `Task.sleep`/timers inside simulation logic, `hashValue` for anything
  persisted or deterministic, `DispatchQueue` (use actors), print (use the
  injected `SimLogger`), force unwraps of dictionary joins (use checked
  accessors).

## 4. Testing standards

- Framework: Swift Testing (`import Testing`) — works on Linux & macOS.
- Every system ships with tests in the same PR/commit as the system.
- Test categories (tagged): unit, determinism, integration (multi-system over
  many ticks), economy (quantitative assertions with tolerances), migration
  (fixture saves), performance sanity (budget smoke, not micro-benchmarks).
- Tests must be deterministic (seeded) and parallel-safe (no shared temp
  paths — use per-test scratch dirs).
- The chunk-invariance, dual-run-hash, and save/restore-continuation tests
  (SIMULATION_ARCHITECTURE §6) are the permanent regression core; they run
  on every change.

## 5. Workflow

- Branch per the session's designated branch; small cohesive commits;
  commit messages state *what and why*, present tense.
- Every meaningful change: `swift build && swift test` before commit.
- Docs and `/tasks` updated in the same commit as the change they describe.
- New architectural decision → `/tasks/DECISIONS.md` entry in the same
  commit. New debt knowingly incurred → `/tasks/TECH_DEBT.md` entry.
- Content file changes run the content validator (a test) — broken data
  fails the build, not the runtime.

## 6. Performance discipline

- Design to the budgets in ARCHITECTURE.md §11; *measure* before optimizing
  beyond them (Phase 20 owns systematic profiling).
- Hot paths (per-tick systems) avoid allocation in steady state; prefer
  in-place mutation of `GameState` slices via `inout`.
- No `O(n²)` cross-entity scans (ARCHITECTURE.md §11 rule); maintain indices
  incrementally when a system needs them.
