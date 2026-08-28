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
- 2026-08-26 V3 Linux-first pass: player-journey gap hunt found and fixed
  three more P1 defects (BUG-003 game-over dead end, BUG-004 rivals'
  private business in the player feed + missing administration warning,
  BUG-005 silent rejection of commands queued while running). Core gained
  an event-audience classifier and a rejection stream (decision D-011,
  additive and pure — save format still v10). New suites:
  `PlayerJourneyTests`, `EventFeedTests`, `ScreenContractTests`,
  `ContentQualityTests`. `docs/APPLE_VALIDATION.md` written as the Xcode
  handoff. Content audited (no dead SKUs; F-004 runway-ladder finding
  documented, not unilaterally changed). Offline-first re-verified.
**Status:** LINUX SCOPE COMPLETE — no known Linux-side P0/P1 remains.
Apple-runtime steps (compile, simulator, rendering, gestures,
accessibility, Instruments, signing) are blocked on macOS (B-002) and
fully enumerated in `docs/APPLE_VALIDATION.md`.

---

## AE-024
**Title:** Release pipeline and App Store listing (authored; Apple steps pending)
**Purpose:** Give the project a way to get a build onto a phone and a listing
onto the App Store that does not depend on anyone remembering a sequence of
manual steps — and, in the same move, answer the question this repository has
never been able to answer: does the SwiftUI app compile?
**Dependencies:** An Apple Developer account, an App Store Connect app record
and a signing certificate — none of which exist (`docs/APP_STORE_CONNECT.md`).
Everything not requiring them is done.
**Implementation notes:**
- `.github/workflows/ci.yml` — Swift 6.0.3 core build + test on Linux, the
  release tooling's own tests, listing validation, and an **`xcodebuild`
  compile of the app on macOS**, scoped by a `git diff` so a docs commit does
  not spend 10x-billed minutes. This closes B-002 for the *compile* question
  without anyone owning a Mac; it does not close rendering, gestures,
  Instruments or accessibility, which still need a device.
- `.github/workflows/ios-testflight.yml` — preflight (ubuntu) → archive,
  export, upload (macOS) → wait for processing (ubuntu). The split is a cost
  decision with a measured origin; see the file header.
- `.github/workflows/app-store-metadata.yml` — validates the listing on every
  PR that touches it; deploys it on an explicit dispatch with a typed
  confirmation. `.github/workflows/pages.yml` publishes the support and
  privacy pages Apple requires a link to.
- `scripts/asc/` — dependency-free Node: App Store Connect JWT client, build
  number resolver, preflight, listing validator, metadata push, screenshot
  upload, processing watcher, and 30 tests over the parts that can be tested
  from Linux.
- `store/` — the listing as files (en-US, en-GB, review notes), with the
  reasoning in `docs/ASO.md`.
- App-side: `PrivacyInfo.xcprivacy` (nothing collected, nothing tracked, no
  required-reason APIs — each derived from the code), an asset catalogue with
  an empty `AppIcon` slot, and a pinned bundle id, marketing version, build
  number and export-compliance declaration in `project.yml`.
**Acceptance criteria:**
- [x] Core tests, tooling tests and listing validation run in CI on Linux
- [x] Listing validated: no over-long field, no wasted keyword character, no
      third-party mark, no unresolvable URL
- [x] Every path that can be exercised without an Apple account is exercised
- [x] The macOS `app` job has produced a green compile — CI run 33213797384,
      2026-08-28, `** BUILD SUCCEEDED **` with no source changes
- [x] A build has been archived, signed and exported — run 33216345773,
      2026-08-28. The upload itself is still unproven: Apple refused that
      bundle at validation (error 90474, iPad orientations), which is fixed
- [ ] The listing has been pushed to App Store Connect — **never run**
**Blocking a submission (none of it fixable from Linux):**
1. ~~App icon~~ — **placed 2026-08-28**, 1024×1024 with no alpha, cropped out
   of a pre-rounded 1254 render (`AirlineEmpireApp/Resources/README.md`).
   Open question: whether a photographic scene reads at 60 pt (`docs/ASO.md` §6)
2. Screenshots — need a simulator and a real mid-game world (`docs/ASO.md` §5)
3. `REPLACE_ME` in `store/config.json` and `site/support.html` — the App
   Review contact, the copyright entity and the support email
4. An in-app rating prompt: deliberately not implemented, policy written in
   `docs/ASO.md` §9
**Owner's runbook:** `docs/GO_LIVE.md` — the twelve stages from here to a
released app, in dependency order, marked by who does each one.
**Status:** LINUX SCOPE COMPLETE.

---

## Backlog (do not start before AE-023 clears)

- **AE-015** — Revenue-management fare buckets (docs/EXPANSION_ROADMAP.md).
- **Hub connections** — first content update (decision D-010).
- **AI market-entry lever** — post-playtest (BALANCING F-001).
- Everything else: `docs/EXPANSION_ROADMAP.md`, `tasks/POST_LAUNCH.md`.
