# Airline Empire — TODO

Active task list. Format follows the Master Task Rule (see
`/tasks/MASTER_PLAN.md`). Completed tasks move to `/tasks/COMPLETED.md`.

---

## AE-023
**Title:** macOS queue — compile, validate, and polish the authored app
**Purpose:** Take the app target from AUTHORED to PRODUCTION READY: generate
the Xcode project, compile, run in the simulator, validate every screen
against the live Core, then execute phases 16, 17, 19b, 20b, 21, the final
22 pass, and 23 in order (owner's Mac/Xcode/polish/QA/release prompt,
2026-08-26).
**Dependencies:** A macOS session with Xcode + xcodegen (blocker B-002).
Everything Linux-executable is done — Core is complete (212 tests green,
save v10) and the static integration audit below has already cleared the
known compile blockers.
**Implementation notes:**
- `cd AirlineEmpireApp && xcodegen generate`, open the project, build.
- Work the owner's phase ladder A→R in order; statuses move
  AUTHORED → COMPILED → TESTED → RUNTIME VALIDATED → PRODUCTION READY,
  never by assertion.
- Priorities P0 (crash/corruption) → P3 (polish); never polish while a
  P0/P1 is open.
- 2026-08-26 static integration audit (Linux session): all 12 app source
  files parse; every Core API the app touches was verified against the
  package by inspection (command initializers, read-model fields, enum
  case arities, catalog accessors, hardcoded content codes). Findings
  fixed: BUG-001 (Core visibility compile blocker), deprecated alert API,
  force-unwraps in RouteDetailView, per-render content/disk IO in
  NewGameView.
- 2026-08-26 continuation: BUG-002 fixed (no aircraft-assignment UI
  existed — core loop was uncloseable); TD-002 fixed (event-stream task
  cancellation); onboarding beat built to the Linux limit — Core
  `OnboardingModel` + 4 tests, Dashboard card + prefilled route sheet
  authored (PRODUCT_REVIEW Critical #2 now pending only runtime
  validation). Phase L's remaining scope: validate the beat live and
  add the evening-digest surface.
**Acceptance criteria:**
- App compiles with zero new warnings; runs in the iPhone and iPad
  simulators; new game → first route → fast-forward → save → relaunch →
  load walkthrough passes.
- Map renders the live network and flights; save/load UX honest about
  backup recovery; large-world (hundreds of aircraft/routes) stays
  responsive.
- Onboarding beat (guided first route, PLAYER_JOURNEY §1), UX polish,
  art direction, accessibility audit, UI-surface adversarial QA,
  Instruments profiling, release checklist — per the phase ladder.
**Tests:** Core suite stays green (never weakened); UI validation is
manual walkthrough + Instruments evidence recorded in docs/.
**Status:** BLOCKED on environment (B-002) — this session (2026-08-26) is
Linux; `xcodebuild`/`xcodegen` unavailable. All audit-scope work done.

---

## Backlog (do not start before AE-023 clears)

- **AE-015** — Revenue-management fare buckets (docs/EXPANSION_ROADMAP.md).
- **Hub connections** — first content update (decision D-010).
- **AI market-entry lever** — post-playtest (BALANCING F-001).
- Everything else: `docs/EXPANSION_ROADMAP.md`, `tasks/POST_LAUNCH.md`.
