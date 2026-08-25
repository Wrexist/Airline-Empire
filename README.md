# Airline Empire

A premium offline-first airline management simulator for iPhone and iPad.
The player starts with a single aircraft on a single route and builds a
global aviation empire — driven by a deterministic, testable simulation, not
a collection of menus.

**Status:** Pre-production. Phase 0 (repository audit & baseline) complete;
next up is Phase 1 (Master Architecture).

## Project navigation

| Where | What |
|-------|------|
| `/docs/PROJECT_AUDIT.md` | Phase 0 baseline audit — start here |
| `/docs/ARCHITECTURE.md` | Architecture (baseline constraints; authored fully in Phase 1) |
| `/tasks/MASTER_PLAN.md` | The 25-phase roadmap, agent roles, rules, Definition of Done |
| `/tasks/CURRENT_PHASE.md` | Single source of truth for the active phase |
| `/tasks/TODO.md` | Active tasks (AE-nnn format) |
| `/tasks/DECISIONS.md` | Decision log |
| `/tasks/TECH_DEBT.md` | Debt register |
| `/tasks/BUGS.md` | Bug register |

## Ground rules (short form)

- Offline-first: no backend, no account, no runtime network dependency.
- Simulation, game state, UI, persistence, and content are strictly separated.
- Deterministic where designed to be; seeded randomness; no frame-coupled logic.
- All game logic lives in a platform-agnostic SwiftPM core package with unit
  tests; the iOS app is a thin SwiftUI shell (decision D-002, pending Phase 1
  ratification).
- Nothing is "done" because it compiles — see the Definition of Done in
  `/tasks/MASTER_PLAN.md`.

## Toolchain note

Automated development sessions currently run on Linux without a Swift
toolchain (blocker **B-001** — see `/docs/PROJECT_AUDIT.md` §4). Phase 3+
implementation must wait until the environment can run `swift test`, or until
work moves to macOS. Phases 1–2 are documentation phases and are unaffected.
