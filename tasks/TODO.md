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
**Status:** COMPLETE 2026-08-25 — moved to COMPLETED.md.

---

Later phases (4–24) are tracked at roadmap level in `/tasks/MASTER_PLAN.md`
and get AE-numbered task breakdowns when their phase opens — pre-writing
detailed tasks for unarchitected systems would be speculation.

---

## AE-005
**Title:** Phase 4 — World and Airport System
**Purpose:** Data-driven airports (specs + runtime slice), world data layer,
distance/eligibility/slot logic, content loading + validation, per Master
Prompt 4.
**Dependencies:** AE-004 (kernel) — complete.
**Acceptance criteria:** data-driven airport specs with all designed
attributes; ContentCatalog loading with referential validation; distance
(great-circle) and route-eligibility calculations; slot allocation logic;
regional classification; tests for distance/capacity/slots/invalid
routes/lookup; docs/AIRPORTS.md; offline-only.
**Tests:** geographic math, capacity/slot invariants, invalid data rejection,
lookup, eligibility edge cases.
**Status:** COMPLETE 2026-08-25 — moved to COMPLETED.md.

---

## AE-006
**Title:** Phase 5 — Aircraft and Fleet System
**Purpose:** Data-driven aircraft types + fleet lifecycle (buy/lease/sell,
assignment, availability, age, condition, maintenance state, reliability,
utilization, operating cost, lifecycle states) per Master Prompt 5.
**Dependencies:** AE-005 (world) — complete.
**Acceptance criteria:** AircraftTypeSpec content with all designed
attributes; Airline + Aircraft runtime entities; purchase/lease/sell
commands through the command pipeline with ledger-ready cost hooks;
aging/depreciation/reliability model; integration with kernel; tests incl.
expensive edge cases; docs/AIRCRAFT.md.
**Tests:** acquisition validation, lifecycle transitions, depreciation
curve, availability rules, save round-trip with fleet.
**Status:** COMPLETE 2026-08-25 — moved to COMPLETED.md.

---

## AE-007
**Title:** Phase 6 — Routes and Flight Operations
**Purpose:** Routes (create/modify/close, schedules, aircraft assignment,
slot consumption) and the real flight lifecycle driven by the simulation
(scheduled→boarding→departing→enRoute→arriving→turnaround→ready, with
disruptions), per Master Prompt 6.
**Dependencies:** AE-006 (fleet) — complete.
**Acceptance criteria:** Route + Flight entities; open/modify/close/assign
commands consuming slots; schedule materialization; per-tick flight phase
system; travel time from distance/speed; operating cost hooks (fuel, fees,
crew) posted per flight; disruption states from reliability/weather;
conflict detection; multi-aircraft concurrency without corruption; tests;
docs/ROUTES.md.
**Status:** COMPLETE 2026-08-25 — moved to COMPLETED.md.

---

## AE-008
**Title:** Phase 7 — Passenger Demand and Pricing
**Purpose:** The demand engine per Master Prompt 7: market demand pools from
demographics × seasonality × economy, logit share allocation across
competing offers (price, schedule quality, reputation hooks, comfort,
punctuality), price elasticity by segment, passengers allocated to
departures, ticket revenue posted.
**Dependencies:** AE-007 (flights) — complete.
**Acceptance criteria:** DemandSystem + PassengerAllocation into flights;
price→demand→load→revenue chain measurable; low/optimal/high price
simulations as tests; demand conservation (no passenger counted twice);
docs/ECONOMY.md started; economy tests with tolerances.
**Status:** OPEN — next up.
