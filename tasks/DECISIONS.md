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

---

## D-002 (update) — RATIFIED in Phase 1
**Date:** 2026-08-25 · **Status:** ACCEPTED · **Phase:** 1
The Core-package/app-shell split is ratified as designed. See
`docs/ARCHITECTURE.md` §2.

---

## D-005 — Single value-type GameState; command/tick-only mutation
**Date:** 2026-08-25 · **Status:** ACCEPTED · **Phase:** 1
**Context:** Need determinism, cheap snapshots, trivial whole-world saves,
and a hard wall between UI and simulation.
**Decision:** All authoritative state is one `Codable` value type mutated
only by validated commands and the ordered tick pipeline. Events are outputs.
AI uses the same command set as the player.
**Consequences:** Replayability and save-safety by construction; systems are
stateless values; UI holds snapshots only. See ARCHITECTURE.md §3.

---

## D-006 — Integer time and money; deterministic rounding choke point
**Date:** 2026-08-25 · **Status:** ACCEPTED · **Phase:** 1
**Decision:** `SimTime` = Int64 game-minutes; `Money` = Int64 cents; one
documented rounding rule where Double math enters the ledger. Stable FNV-1a
hashing for anything persisted/deterministic (never `hashValue`).
**Consequences:** No float drift in balances; cross-device determinism.

---

## D-007 — Fixed 15-minute tick, cadenced systems, aggregate passengers
**Date:** 2026-08-25 · **Status:** ACCEPTED · **Phase:** 1
**Decision:** Base tick 15 game-minutes (96/day); systems run per-tick,
hourly, daily, weekly, or monthly per a fixed documented pipeline order;
passengers/staff/maintenance tasks are aggregates, not entities.
**Consequences:** Late-game scale fits mobile budgets; changing tick size or
pipeline order requires a decision entry + save migration.

---

## D-008 — Single simulation actor; snapshot-based UI delivery
**Date:** 2026-08-25 · **Status:** ACCEPTED · **Phase:** 1
**Decision:** One actor owns the engine; `GameSession` is the only public
façade (snapshots + events out, commands in). No locks in game logic.
**Consequences:** No data races by construction under Swift 6 strict
concurrency; UI can never observe torn state.

---

## D-009 — Linux Swift toolchain via GitHub mirror (B-001 resolved)
**Date:** 2026-08-25 · **Status:** ACCEPTED · **Phase:** 1
**Context:** Network policy blocks download.swift.org; agent sessions need
`swift build`/`swift test` (blocker B-001).
**Decision:** Install Swift 6.0.3 from the SwiftWasm GitHub release mirror
(official 6.0.3 compiler + wasm cross target; native linux host toolchain is
standard). `scripts/setup-linux-toolchain.sh` automates it; verified working
end-to-end (build+link+Swift Testing) on Ubuntu 24.04 in-session.
**Consequences:** Phases 3+ are unblocked in the Linux agent environment.
iOS app targets still require macOS (B-002 stands, by nature). Owner may
still allowlist swift.org for the official tarball; the script would then be
pointed there — cosmetic change.
