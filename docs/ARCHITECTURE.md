# Airline Empire — Architecture

> **Status: BASELINE STUB (Phase 0).** The full architecture is authored in
> Phase 1 (Master Architecture) and will replace the body of this document.
> Only environment-driven constraints established during the Phase 0 audit are
> recorded here so Phase 1 starts from facts, not assumptions.

## Constraints fixed at baseline

These come from the master development plan and the Phase 0 environment audit
(`/docs/PROJECT_AUDIT.md`) and bind all later phases:

1. **Offline-first, no backend.** The game is fully playable with no account
   and no server. Nothing may depend on network availability at runtime.
2. **Simulation is independent of UI.** Simulation logic, game state, and
   persistence must not import SwiftUI/UIKit/SpriteKit. UI consumes state; it
   never owns game logic.
3. **Deterministic where designed to be.** Seeded, injectable randomness; no
   frame-rate-dependent gameplay logic; no wall-clock reads inside simulation
   systems.
4. **Versioned persistence from the first serialized byte.** Save-format
   versioning discipline starts in Phase 3 even though migration
   infrastructure lands in Phase 13.
5. **Data-driven content.** Airports, aircraft, events, etc. load from local
   data assets, not hardcoded logic.
6. **Scales to thousands of entities on-device.** Architecture must support
   large fleets/networks without a backend (validated in Phase 20).

## Proposed repository structure (D-002, pending Phase 1 ratification)

```
/AirlineEmpireCore          SwiftPM package — ALL game logic
    Sources/AirlineEmpireCore/
    Tests/AirlineEmpireCoreTests/
/AirlineEmpire              iOS app (Xcode target) — SwiftUI shell, map, audio, haptics
/docs                       Architecture & design documentation
/tasks                      Project control files (plan, todo, decisions, debt)
```

Rationale: the Core package is Foundation-only and builds/tests with
`swift test` on both Linux and macOS, which (a) enforces the simulation/UI
separation at the compiler level and (b) keeps phases 3–13 and 18 fully
testable in the Linux agent environment once the Swift toolchain blocker
(B-001, see the audit) is resolved. The iOS app target is validated on macOS.

## To be authored in Phase 1

Application layer, game state, simulation engine and clock, deterministic
random systems, economy, airports, aircraft, routes, flights, passengers,
demand, pricing, fleet, maintenance, staff, competitors, events, progression,
achievements, missions, world state, save/load, settings, local analytics, UI
state, map rendering, audio, haptics — plus core models, services, systems,
repositories, commands, events, state transitions, dependency rules, ownership
boundaries, concurrency model, and testing standards.
