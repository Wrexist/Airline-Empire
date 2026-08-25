# Airline Empire — TODO

Active task list. Format follows the Master Task Rule (see
`/tasks/MASTER_PLAN.md`). Completed tasks move to `/tasks/COMPLETED.md`.

---

## AE-001
**Title:** Resolve Swift toolchain blocker B-001
**Purpose:** Make `swift build` / `swift test` possible in the agent
environment so phases 3+ can satisfy the Definition of Done.
**Dependencies:** None. **Owner action required** (environment settings are
not controllable from inside a session).
**Implementation notes:** Either (a) allowlist `swift.org` +
`download.swift.org` in the remote environment's network policy and add a
setup script installing the Swift 6.x Ubuntu 24.04 toolchain, or (b) run
implementation phases on macOS with Xcode. Details: `/docs/PROJECT_AUDIT.md` §4.
**Acceptance criteria:**
- `swift --version` succeeds in a fresh session, OR implementation sessions
  run on macOS with Xcode available.
**Tests:** n/a (environment task).
**Status:** RESOLVED 2026-08-25 (in-session) — Swift 6.0.3 installed via GitHub mirror; see D-009 and `scripts/setup-linux-toolchain.sh`. Moved to COMPLETED.md.

---

## AE-002
**Title:** Phase 1 — Master Architecture
**Purpose:** Author the complete long-term architecture (the "architectural
constitution") covering all systems listed in Master Prompt 1, with strict
rules for simulation/UI separation, persistence, determinism, DI,
testability, concurrency, performance, data-driven content, versioned saves.
**Dependencies:** Phase 0 (complete).
**Implementation notes:** Ratify or overturn proposed decision D-002
(Core package / app-shell split) in `/tasks/DECISIONS.md`. Must support
thousands of entities offline. Review as if maintaining for five years.
**Acceptance criteria:**
- `/docs/ARCHITECTURE.md` fully authored (replaces Phase 0 stub)
- `/docs/DOMAIN_MODEL.md`, `/docs/SIMULATION_ARCHITECTURE.md`,
  `/docs/PERSISTENCE_ARCHITECTURE.md`, `/docs/UI_ARCHITECTURE.md`,
  `/docs/TECHNICAL_STANDARDS.md` created
- Architectural risks identified; `/tasks/MASTER_PLAN.md` updated
- No large gameplay systems implemented
**Tests:** n/a (design phase).
**Status:** COMPLETE 2026-08-25 — moved to COMPLETED.md.

---

## AE-003
**Title:** Phase 2 — Game Design Bible
**Purpose:** Define the complete player experience, all game systems and
their interactions, per Master Prompt 2.
**Dependencies:** AE-002.
**Acceptance criteria:**
- `/docs/GAME_DESIGN.md`, `/docs/CORE_LOOP.md`, `/docs/PROGRESSION.md`,
  `/docs/GAME_BALANCE.md`, `/docs/PLAYER_JOURNEY.md` created
- Every system has a purpose; complexity without decisions removed
**Tests:** n/a (design phase).
**Status:** COMPLETE 2026-08-25 — moved to COMPLETED.md.

---

## AE-004
**Title:** Phase 3 — Simulation kernel scaffold and implementation
**Purpose:** Implement the foundational simulation kernel (state, clock,
ticks, deterministic RNG, events, commands, snapshots, scheduling, system
ordering, pause/resume/speed) as the `AirlineEmpireCore` SwiftPM package.
**Dependencies:** AE-001 (toolchain), AE-002 (architecture), AE-003 (design).
**Acceptance criteria:** per Master Prompt 3 — real infrastructure, no
placeholders, deterministic, testable without SwiftUI, full unit tests
passing, docs updated.
**Tests:** time progression, deterministic randomness, state transitions,
event ordering, scheduling, pause/resume, speed, edge cases.
**Status:** OPEN — next up (AE-003 complete).

---

Later phases (4–24) are tracked at roadmap level in `/tasks/MASTER_PLAN.md`
and get AE-numbered task breakdowns when their phase opens — pre-writing
detailed tasks for unarchitected systems would be speculation.
