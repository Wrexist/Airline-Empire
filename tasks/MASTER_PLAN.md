# Airline Empire — Master Plan

The authoritative phase roadmap, derived from the project owner's complete
agentic development plan. Phases execute **sequentially**; a phase is entered
only when the previous phase's Definition of Done is met and its review is
complete. `/tasks/CURRENT_PHASE.md` names the active phase.

## Vision

A premium offline-first airline management simulator for iPhone and iPad.
One aircraft → one route → one airline → regional carrier → national carrier →
international airline → global aviation empire. Simulation-driven, deep but
understandable, deterministic where appropriate, no backend, no account.

Target stack: Swift, SwiftUI, SpriteKit/Canvas where appropriate, SwiftPM,
local persistence, local JSON/data assets, automated tests.

## Agent roles

- **Fable — Principal Architect / Lead Designer / Reviewer:** architecture,
  system & economy design, planning, audits, reviews, risk and balance
  analysis, refactoring plans.
- **Opus — Senior Production Engineer:** implementation, Swift/SwiftUI,
  simulation systems, UI, tests, refactors, bug fixing, integration,
  performance, visual implementation.

Handoff loop after each implementation phase:
PLAN → IMPLEMENT → TEST → REVIEW (Fable) → FIX → VERIFY → DOCUMENT → NEXT PHASE.
Neither agent may blindly trust previous work.

## Phase roadmap

| Phase | Title | Lead | Status |
|-------|-------|------|--------|
| 0 | Repository Audit and Baseline | Fable | **COMPLETE** (2026-08-25) |
| 1 | Master Architecture | Fable | **COMPLETE** (2026-08-25) |
| 2 | Game Design Bible | Fable | **COMPLETE** (2026-08-25) |
| 3 | Data Model and Simulation Kernel | Opus | **COMPLETE** (2026-08-25) |
| 4 | World and Airport System | Opus | **COMPLETE** (2026-08-25) |
| 5 | Aircraft and Fleet System | Opus | **COMPLETE** (2026-08-25) |
| 6 | Routes and Flight Operations | Opus | **COMPLETE** (2026-08-25) |
| 7 | Passenger Demand and Pricing | Opus | **COMPLETE** (2026-08-25) |
| 8 | Finance and Airline Economics | Opus | **COMPLETE** (2026-08-25) |
| 9 | Reputation, Service and Airline Quality | Opus | **COMPLETE** (2026-08-25) |
| 10 | Competitor Airlines | Opus | **COMPLETE** (2026-08-25) |
| 11 | Events and Living World | Opus | **COMPLETE** (2026-08-25) |
| 12 | Progression, Research and Long-Term Goals | Opus | **COMPLETE** (2026-08-25) |
| 13 | Save System and Offline Persistence | Opus | **COMPLETE** (2026-08-25) |
| 14 | Main UI Architecture | Opus | **AUTHORED** (2026-08-25; macOS build validation pending) |
| 15 | Interactive World Map | Opus | **AUTHORED** (2026-08-25; core math tested; macOS validation pending) |
| 16 | UX Polish and Game Feel | Opus | NOT STARTED (macOS required) |
| 17 | Visual Art Direction | Fable+Opus | NOT STARTED (macOS required) |
| 18 | Balance and Simulation Stress Testing | Fable | **COMPLETE** (2026-08-25) |
| 19 | Full QA and Bug Elimination | Opus | **HEADLESS SCOPE COMPLETE** (2026-08-25; UI-surface QA queued for macOS) |
| 20 | Performance Optimization | Opus | **HEADLESS SCOPE COMPLETE** (2026-08-25; budget met, UI profiling queued for macOS) |
| 21 | Accessibility and Device Compatibility | Opus | NOT STARTED (macOS required) |
| 22 | Final Product Review | Fable | **CURRENT-SCOPE AUDIT COMPLETE** (2026-08-25; final pass re-runs after macOS queue) |
| 23 | Release Candidate | Opus | NOT STARTED (macOS required) |
| 24 | Post-Launch Expansion Architecture | Fable | **COMPLETE** (2026-08-25) |

### Direction II — the cozy living world (2026-09-06)

Phases 0–24 built and hardened the simulation. Phases 25 onward are set by the
project owner's direction decisions of 2026-09-06 (`docs/GAME_DIRECTION.md`):
a **cozy builder with a living world map at its centre**, played in 20–40
minute sittings, guided but with real stakes. The detailed plan — seams, data
impact, tests, risks and definition of done per phase — is
`docs/ROADMAP_DIRECTION_II.md`.

| Phase | Title | Layer | Status |
|-------|-------|-------|--------|
| 25 | AE-046 Follow a flight | App | PLANNED |
| 26 | AE-047 Airports that breathe, weather you can see | App + read model | PLANNED |
| 27 | AE-048 The map is the home screen | App | PLANNED |
| 28 | AE-049 The investor rescue | Core + App | PLANNED |
| 29 | AE-050 Capped offline catch-up | Core + App | PLANNED |
| 30 | AE-051 Goals that pull: era objectives and contracts | Core + App | PLANNED |
| 31 | AE-052 The first hour, on the new home | App | PLANNED |
| 32 | AE-053 The fleet you want | Content + App | BLOCKED (naming, art) |
| 33 | AE-054 Hub connections | Core + App | PLANNED |

Phases 25–27 are one piece of work in three shippable parts. Phases 28–30 are
Core-side and interleave when an app phase is blocked.

**Gate before Phase 3:** RESOLVED 2026-08-25. Swift 6.0.3 runs in the agent
environment via `scripts/setup-linux-toolchain.sh` (decision D-009); build
and tests verified working.

"macOS required" marks phases whose primary validation surface (SwiftUI iOS
app, simulator, Instruments, signing) needs macOS/Xcode; their Core-package
portions remain Linux-testable.

## Universal agent rules (binding for every phase)

1. Inspect the repository before changing anything; read docs and task state.
2. Understand existing architecture before implementing; never rewrite
   working systems unnecessarily; preserve behavior unless the task changes it.
3. Small cohesive modules; simulation independent from UI; state independent
   from presentation; no global mutable state; no hidden dependencies; no
   magic numbers; typed models.
4. Tests for important systems; documentation for architectural decisions;
   run tests and build after meaningful changes; fix errors rather than
   documenting them as acceptable.
5. Never mark a task complete because it compiles; no placeholder
   implementations passed off as complete; no fake systems where real
   deterministic systems are required.
6. No unnecessary third-party dependencies; everything offline-compatible;
   design for long-term extensibility.
7. Before declaring a system finished: edge cases, balance impact, save
   compatibility impact, performance impact.
8. Every phase finishes: Implement → Test → Build → Review → Fix → Document →
   Update tasks.

## Task format (Master Task Rule)

Every task in `/tasks/TODO.md` carries: ID (AE-nnn), Title, Purpose,
Dependencies, Implementation notes, Acceptance criteria, Tests, Status.

## Definition of Done

A feature is complete only when: implementation exists; architecture is
correct; tests exist and pass; build succeeds; edge cases handled; UI usable
where applicable; persistence works where applicable; documentation updated;
task updated; no known critical bug remains.

## Guiding principle

Optimize for "how quickly can the AI produce stable, understandable, testable
systems that survive the next 100 features" — never for raw generation speed.
The finished game must make the player feel "I am running an airline," not
"I am pressing buttons in a spreadsheet."
