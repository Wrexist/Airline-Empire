# Airline Empire

A premium offline-first airline management simulator for iPhone and iPad.
The player starts with a single aircraft on a single route and builds a
global aviation empire — driven by a deterministic, testable simulation, not
a collection of menus.

**Status, 11 September 2026:** TestFlight **1.0.16 (6)** is ready; physical
acceptance remains before submission. PRs #22 through #26 are merged. Exact-candidate
full native CI, Launch safety and portability passed. Apple processed build 6,
assigned it to Tester and has the app plus all three purchases and their group
in one five-item draft. The launch is configured for **173 regions**, excluding
China mainland and Vietnam, with a **16 October 2026** pre-order release date.
The app has not been submitted or published. Start with the
[remaining owner steps](docs/RELEASE_OWNER_STEPS.md) and
[current execution record](docs/RELEASE_CONTINUATION_STATUS.md).
See the [release plan](docs/RELEASE_PLAN.md),
[dated audit](docs/RELEASE_AUDIT_2026-09-10.md),
[ordered checklist](tasks/RELEASE_CHECKLIST.md) and
[execution prompt](docs/RELEASE_EXECUTION_PROMPT.md).

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
| `/docs/RELEASE_OWNER_STEPS.md` | **Current device acceptance and final submission steps** |
| `/docs/GO_LIVE.md` | Historical account/build setup walkthrough |
| `/docs/MONETIZATION.md` | Free-to-play, the Pro entitlement, the gates, and the paywall's compliance rules |
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
