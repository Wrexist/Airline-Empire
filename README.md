# Airline Empire

A premium offline-first airline management simulator for iPhone and iPad.
The player starts with a single aircraft on a single route and builds a
global aviation empire — driven by a deterministic, testable simulation, not
a collection of menus.

**Status:** Pre-production. The simulation core is complete and Linux-validated
(253 tests); the SwiftUI app is authored and has never been compiled by Xcode.
`/tasks/CURRENT_PHASE.md` is the live picture — this line has been wrong before
and it is not the source of truth.

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
| `/docs/GO_LIVE.md` | **Step by step from here to the App Store — start here for shipping** |
| `/docs/APP_STORE_CONNECT_FILL_IN.md` | Every App Store Connect field with the exact value to paste (generated from `/store`) |
| `/docs/RELEASE_PIPELINE.md` | How a commit becomes a build and a listing |
| `/docs/APP_STORE_CONNECT.md` | The one-time Apple account setup, and its secrets |
| `/docs/ASO.md` | The store listing's design rationale |
| `/store/` | The listing itself: copy, categories, review notes |

## Ground rules (short form)

- Offline-first: no backend, no account, no runtime network dependency.
- Simulation, game state, UI, persistence, and content are strictly separated.
- Deterministic where designed to be; seeded randomness; no frame-coupled logic.
- All game logic lives in a platform-agnostic SwiftPM core package with unit
  tests; the iOS app is a thin SwiftUI shell (decision D-002, pending Phase 1
  ratification).
- Nothing is "done" because it compiles — see the Definition of Done in
  `/tasks/MASTER_PLAN.md`.

## Continuous integration

`.github/workflows/ci.yml` runs on every push and pull request:

- **Core** — `swift test` and a warnings-as-errors release build on Linux
  (Swift 6.0.3).
- **Release tooling** — the App Store tooling's own tests, and validation of
  the store listing in `/store`.
- **iOS app** — `xcodegen generate` and `xcodebuild build` on a macOS runner,
  which is the first thing in this project's history able to answer whether the
  SwiftUI shell compiles. It answers only that: rendering, gestures,
  accessibility, Instruments and signing still need a device
  (`/docs/APPLE_VALIDATION.md`).

Releases are `/docs/RELEASE_PIPELINE.md`.

## Toolchain note

Automated development sessions run on Linux. The Swift toolchain is available
(blocker **B-001**, resolved — `scripts/setup-linux-toolchain.sh`, decision
D-009); Xcode is not, so the Apple layer is prepared here and validated on
macOS or on the CI runner above. What is proven versus assumed:
`/docs/APPLE_VALIDATION.md` and `/docs/LINUX_QA_AUDIT.md`.
