# Airline Empire — Project Audit (Phase 0 Baseline)

Audit date: 2026-08-25
Auditor role: Principal Engineer (Phase 0 — Repository Audit and Baseline)
Branch: `claude/airline-empire-plan-oln7v7`

## 1. Executive summary

The repository `Wrexist/Airline-Empire` is **completely empty**. At audit time it
contained zero commits, zero files, zero branches on the remote, and no
configuration of any kind. This is a greenfield project.

Consequence: there is no legacy code to preserve, refactor, or remove. Every
audit dimension below is answered honestly as "does not exist yet". The value of
this audit is therefore (a) establishing that fact on the record, (b) auditing
the *development environment* the agents will work in, and (c) fixing the
baseline decisions and risks before Phase 1 (Master Architecture) begins.

## 2. Audit findings (per the Phase 0 checklist)

| # | Dimension | Finding |
|---|-----------|---------|
| 1 | Current technology stack | None. No source files, no project files, no package manifests. Target stack per the master plan: Swift, SwiftUI, SpriteKit/Canvas, SwiftPM, local persistence. |
| 2 | Current application architecture | None exists. To be designed in Phase 1. |
| 3 | Existing functionality | None. |
| 4 | Existing incomplete functionality | None. |
| 5 | Existing technical debt | None in code. One environment-level debt item exists (see §4, toolchain blocker) and is tracked in `/tasks/TECH_DEBT.md`. |
| 6 | Existing architectural problems | None (no architecture exists). |
| 7 | Existing dependencies | None. No `Package.swift`, no `.xcodeproj`, no lockfiles. |
| 8 | Existing performance risks | None in code. Future risks noted in §5. |
| 9 | Existing save/persistence implementation | None. To be designed in Phase 1, implemented in Phase 13 (with save-safe state transitions from Phase 3 onward). |
| 10 | Existing UI architecture | None. |
| 11 | Existing simulation architecture | None. |
| 12 | Existing test coverage | None. No test targets exist. |
| 13 | Build status | Nothing to build. Additionally, the current remote agent environment **cannot build Swift at all** (see §4). |
| 14 | What can safely be reused | Nothing (empty repo). The master development plan supplied by the project owner is the only existing asset and is captured in `/tasks/MASTER_PLAN.md`. |
| 15 | What should be refactored | Nothing. |
| 16 | What should be removed | Nothing. |
| 17 | What must be preserved | The task/docs control files created in this phase, and the phase discipline of the master plan. |

## 3. Development environment audit

The remote agent environment (where automated development sessions run):

- **OS:** Ubuntu 24.04.4 LTS, Linux x86_64, 4 CPU cores.
- **Swift toolchain:** **Not installed.** `swift`, `swiftc`, and `xcodebuild`
  are all absent.
- **Network policy:** Outbound HTTPS goes through a policy proxy.
  `download.swift.org` is **denied** (verified: `CONNECT` returned 403 at
  2026-08-25T19:26Z), so the Swift-for-Linux toolchain cannot currently be
  installed in-session. Package registries npm, PyPI, crates.io, and
  proxy.golang.org are allowlisted; swift.org is not.
- **Xcode:** Never available on Linux. iOS app targets can only be built and
  signed on macOS.

## 4. Critical blockers

**B-001 — No Swift toolchain available in the agent environment (CRITICAL).**
The master plan mandates "run tests after meaningful changes" and "build the
project after meaningful changes". Neither is possible in this environment
today for Swift code.

Root cause: environment network policy denies `download.swift.org`; no
toolchain is preinstalled.

Remediation (owner action required, in preference order):
1. Add `swift.org` / `download.swift.org` to the environment's network
   allowlist **and** add a setup script that installs the Swift 6.x Ubuntu
   24.04 toolchain (tarball ~800 MB; disk headroom exists — ~30 GB available).
   This enables `swift build` / `swift test` on Linux for all non-UI code.
2. Alternatively, run implementation phases in a macOS-based environment
   (e.g. local Claude Code on a Mac with Xcode) where both the package tests
   and the iOS app target can be built.

Until one of these lands, phases 3+ cannot satisfy the Definition of Done
(tests must pass, build must succeed) in this environment. Phases 1–2 are
documentation/design phases and are unaffected.

**B-002 — iOS app target requires macOS regardless (STRUCTURAL).**
Even with Swift-on-Linux installed, SwiftUI-for-iOS, SpriteKit, signing, and
simulator runs require macOS/Xcode. This cannot be remediated in a Linux
environment; it constrains *where* app-shell work is validated, not whether it
can be written.

## 5. Structural consequence for the architecture (input to Phase 1)

To keep the vast majority of the game buildable and testable on Linux (and by
CI), the repository should be structured as:

- **`AirlineEmpireCore`** — a SwiftPM package containing *all* simulation,
  economy, world, fleet, AI, event, progression, and persistence logic.
  Foundation-only; no UIKit/SwiftUI/SpriteKit imports; fully deterministic and
  unit-tested; builds with `swift test` on Linux and macOS.
- **`AirlineEmpire` (iOS app)** — a thin Xcode app target consuming the Core
  package: SwiftUI views, map rendering, haptics, audio, platform glue.
  Built/validated on macOS only.

This split is not merely a workaround: it enforces master-plan rules 8–9
(simulation independent from UI, state independent from presentation) at the
compiler level, and it means ~90% of the game (everything in phases 3–13 and
18) has automated tests that run anywhere. It is recorded as proposed decision
D-002 in `/tasks/DECISIONS.md` and must be ratified or overturned in Phase 1.

## 6. Major risks (forward-looking)

| Risk | Severity | Notes |
|------|----------|-------|
| Toolchain blocker (B-001) turns later phases into untested code drops | Critical | Do not start Phase 3 until resolved; see remediation above. |
| Simulation/UI coupling creeping in once UI phases begin | High | Mitigated structurally by the Core/App package split (D-002). |
| Save-format churn across phases 3–13 breaking saves | High | Version the save format from the first serialized byte; migration infra is Phase 13 but versioning discipline starts in Phase 3. |
| Economy balance built on untested equations | Medium | Phases 7–8 must ship with economic tests and headless balance simulations, not just unit tests. |
| Scope creep from the very broad master plan | Medium | Enforced by phase discipline and `/tasks/CURRENT_PHASE.md`. |
| Performance on large networks (thousands of entities) | Medium | Architectural requirement in Phase 1; measured in Phase 20, not guessed earlier. |

## 7. Recommended implementation order

The master plan's phase order (0 → 24) is sound for this codebase and is
adopted unchanged, with one gate added:

**Gate before Phase 3:** blocker B-001 must be resolved (Swift toolchain
available in the working environment) so the simulation kernel can be built
and tested for real. Phases 1 and 2 (architecture + game design bible) are
pure documentation and can proceed immediately.

Precise next steps:
1. **Owner:** resolve B-001 (allowlist swift.org + setup script, or move
   implementation sessions to macOS).
2. **Phase 1 (Fable):** author the master architecture per Master Prompt 1,
   ratifying or overturning D-002.
3. **Phase 2 (Fable):** author the game design bible per Master Prompt 2.
4. **Phase 3 (Opus):** scaffold `AirlineEmpireCore` SwiftPM package and
   implement the simulation kernel with full tests — only after the gate.

## 8. Baseline declaration

Baseline state: empty repository + Phase 0 control files (this commit).
Nothing is incomplete because nothing beyond documentation exists; no
incomplete system is being represented as complete. Phase 0 is done when this
document, the control files, and `/docs/ARCHITECTURE.md` (baseline stub) are
committed and pushed.
