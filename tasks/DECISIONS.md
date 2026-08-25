# Airline Empire — Decision Log

Architectural and project decisions. Every entry records context, decision,
status, and consequences. Decisions are only changed by a new entry that
supersedes the old one.

---

## D-001 — Adopt the phased master plan as the project constitution
**Date:** 2026-08-25 · **Status:** ACCEPTED · **Phase:** 0
**Context:** Greenfield repository; the owner supplied a complete 25-phase
agentic development plan.
**Decision:** The phase order, universal agent rules, task format, and
Definition of Done from the master plan are binding. Phases run sequentially;
`/tasks/CURRENT_PHASE.md` is the single source of truth for what is active.
**Consequences:** No implementation before architecture (Phase 1) and design
(Phase 2) exist. No phase is skipped or merged without an explicit decision
entry.

---

## D-002 — Core SwiftPM package + thin iOS app shell
**Date:** 2026-08-25 · **Status:** PROPOSED (ratify in Phase 1) · **Phase:** 0
**Context:** The agent environment is Linux (no Xcode ever; Swift installable
only after a network-policy change). The master plan mandates
simulation/UI separation and tests after every meaningful change.
**Decision (proposed):** All game logic (simulation, economy, world, fleet,
AI, events, progression, persistence) lives in a Foundation-only SwiftPM
package `AirlineEmpireCore`, testable via `swift test` on Linux and macOS.
The iOS app (`AirlineEmpire`) is a thin SwiftUI/SpriteKit shell consuming the
package, validated on macOS.
**Consequences:** Simulation/UI separation is compiler-enforced; phases 3–13
and 18 stay fully testable in agent sessions; UI phases (14–17, 20–21, 23)
need macOS validation.

---

## D-003 — No backend, offline-first (reaffirmed)
**Date:** 2026-08-25 · **Status:** ACCEPTED · **Phase:** 0
**Context:** Master plan requirement.
**Decision:** No server, no account, no runtime network dependency. Analytics,
saves, and content are all local. A backend is only considered if a future
requirement absolutely demands one, via a new decision entry.
**Consequences:** All content ships as local data assets; persistence is
on-device with versioning and migration (Phase 13).

---

## D-004 — Save-format versioning starts with the first serialized byte
**Date:** 2026-08-25 · **Status:** ACCEPTED · **Phase:** 0
**Context:** Phases 3–12 all touch serializable state before the full save
system lands in Phase 13; retrofitting versioning is a known failure mode.
**Decision:** Every serialized structure carries a format version from its
first implementation in Phase 3. Migration infrastructure arrives in
Phase 13, but no unversioned save data is ever written.
**Consequences:** Slight upfront cost per model; eliminates a whole class of
save-compatibility breakage across the implementation phases.
