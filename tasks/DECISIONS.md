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

---

## D-010 — v1.0 scope trims recorded at product review
**Date:** 2026-08-25 · **Status:** ACCEPTED · **Phase:** 22
**Context:** Current-scope audit (docs/PRODUCT_REVIEW.md) found three
design-doc promises not implemented and judged against building them now.
**Decision:**
1. **Hub connections** (GAME_DESIGN §4.14 spill demand): descoped from
   v1.0 to the first content update. Rationale: the mid-game hub beat
   deserves validated UI to land on; the demand-engine seam (a spill term
   in the pool split) is reserved and the aggregates rule keeps it cheap.
2. **Command-replay tooling** (SIMULATION_ARCHITECTURE §2 command log):
   determinism is guaranteed and continuously verified by dual-run hashes
   and save/continue equality; a replay log is QA tooling, built when QA
   needs it. Doc amended by this entry.
3. **LocalAnalytics service** (ARCHITECTURE §8): superseded by statement
   series + route monthly economics, which already feed every planned
   chart. Doc amended by this entry.
**Consequences:** v1.0 ships point-to-point networks; PRODUCT_REVIEW.md
carries these as tracked items, not silent gaps. Scenario/difficulty
presets — the other High finding — were implemented in this phase instead
of deferred (content-driven Founder/Entrepreneur/Magnate).

---

## D-011 — Event audience and rejection delivery belong in Core
**Date:** 2026-08-26 · **Status:** ACCEPTED · **Phase:** AE-023 (Linux)
**Context:** Two P1 defects (BUG-004, BUG-005) both stem from information
that exists inside Core never reaching the player. Core is protected by
default, so each change is justified against the eight-point test:

1. **Problem reproduced.** BUG-004: `statementClosed` is emitted for every
   airline, so the player's feed carried rivals' books; and
   `airlineEnteredAdministration` rendered nothing. BUG-005: a command
   queued while running is rejected into `engine.lastCommandResults`,
   which the next `advance` chunk clears — the rejection is destroyed
   before any caller can see it.
2. **Why Core, not App.** Event payloads carry entity IDs, not owners
   (`aircraftDelivered(id:)`), so deciding whose business an event is
   requires resolving ownership against state — domain knowledge the view
   layer must not compute (ARCHITECTURE §3). And `GameSession` is the only
   façade across the actor boundary (D-008); the App cannot observe
   per-chunk engine results without reaching past it, which the
   architecture forbids. Both fixes are *outbound delivery* of facts Core
   already computes.
3. **Invariants affected: none.** Commands, systems, tick order, state
   mutation and event emission are untouched. The additions are one pure
   `GameState` extension (reads only) and two publish-time hooks.
4. **Tests.** `EventFeedTests` — 6 new tests covering ownership
   resolution, rival privacy, public-fate visibility, kernel-chatter
   suppression, live filtered subscription, and rejection delivery.
5. **Determinism.** No RNG, no state writes, no ordering change;
   `stateHash` is unaffected. Dual-run and save/continue tests still pass.
6. **Save compatibility.** No persisted state added; format stays **v10**.
   No migration.
7. **Performance.** Classification runs per delivered event only when a
   subscriber exists; rejection publishing iterates a per-chunk array that
   is empty in the normal case. Bench unchanged (3.05 s at 200×200).

**Decision:** Add `GameState.subjectAirline(of:)` / `isFeedEvent(_:for:)`
(`Session/EventFeed.swift`), `GameSession.events(playerFeedOnly:)`, and
`GameSession.rejections()`. `events()` keeps its existing semantics by
default so no caller or test changes meaning.
**Consequences:** The App can present an honest feed and report queued
failures without duplicating domain logic. Future event kinds must be
classified in `subjectAirline(of:)` — the switch is exhaustive, so the
compiler enforces it.

---

## D-012 — The store listing is versioned content, not a web form
**Date:** 2026-08-28 · **Status:** ACCEPTED · **Phase:** 23 (prepared early)
**Context:** An App Store listing — name, subtitle, keywords, description,
screenshots — is normally edited in App Store Connect's web UI, where it has
no history, no review and no way back. It is also the surface that decides
whether anyone ever installs the game.
**Decision:** `store/` is the source of truth: one text file per field, one
directory per locale, plus a `config.json` for the non-localised settings.
App Store Connect is a deployment target, written to by
`scripts/asc/push-metadata.mjs`. A validator enforces Apple's limits and this
project's rules offline, on every pull request.
**Consequences:** Listing changes are diffed and reviewed like code, and
reverting a commit restores the previous listing exactly. The cost is a second
place the listing exists: an edit made directly in App Store Connect will be
overwritten by the next push, and that is the intended direction of travel.
The layout matches fastlane `deliver`'s so the tooling can be replaced without
moving any copy.

---

## D-013 — Node for the release tooling, in a Swift repository
**Date:** 2026-08-28 · **Status:** ACCEPTED · **Phase:** 23 (prepared early)
**Context:** The release path needs an App Store Connect API client: an ES256
JWT and a dozen REST calls, running before and after the compile, on Linux and
macOS runners. Master plan rule 6 forbids unnecessary dependencies.
**Decision:** `scripts/asc/` is dependency-free Node — no packages, no
`package.json`, no lockfile — and ships in nothing. Swift was the natural
choice and is the wrong one: building a helper binary on every runner costs
more than the helper saves, and the tooling must run at points where the app
cannot be built at all. Ruby (fastlane) would add a toolchain and a Gemfile for
the same REST calls; bash would mean hand-converting OpenSSL's DER signature
into the raw r||s pair JWS requires.
**Consequences:** Node is now required to work on the release path, and it is
preinstalled on every GitHub runner. The crypto is covered by tests that verify
a real signature (`scripts/asc/selftest.mjs`), because the failure mode — a
DER-encoded signature — produces a well-formed token that Apple answers with a
bare 401.

---

## D-014 — CI compiles the iOS app on a macOS runner
**Date:** 2026-08-28 · **Status:** ACCEPTED · **Phase:** 23 (prepared early)
**Context:** Blocker B-002 has stood since Phase 14: `AirlineEmpireApp` is
authored, parsed and structurally validated, and has never been compiled,
because no session has had macOS. Every Apple-layer claim in the project is
qualified by that.
**Decision:** `.github/workflows/ci.yml` runs `xcodegen generate` and
`xcodebuild build` on a `macos-26` runner, scoped by a `git diff` to commits
that touch the app, the core or the workflow itself.
**Consequences:** The compile question is answerable by anyone who can push a
branch, and a regression in the app shell is caught by the machine rather than
by the first macOS session. It does **not** close B-002: rendering, gestures,
`@Observable` behaviour, scene-phase autosave, accessibility, Instruments and
signing still need a device and a person, and `docs/APPLE_VALIDATION.md`
remains the list. macOS minutes bill at ten times ubuntu ones, which is why
the job is scoped rather than unconditional.

