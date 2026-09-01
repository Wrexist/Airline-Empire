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
save v10 — the baseline **as of 2026-08-26**; see AE-025 below for the
current one) and the static integration audit below has already cleared the
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
- 2026-08-29 UI/UX forensic audit + remediation: `docs/UIUX_FORENSIC_AUDIT.md`
  is the new baseline. It found the screen set complete and the *product* thin
  — five P0s, nine P1s, 22 P2/P3s — and the list has been worked. Three more
  defects surfaced while fixing (BUG-009 tab overflow, BUG-010 a Start button
  that could only refuse, BUG-011 a chart whose zero line moved per bar), and
  five more that only a real compiler could see. Core gained `EraGate`,
  `MissionMath`, `AdvisoryModels`, month-to-date route economics and
  `Airline.livery` (save v11, D-015). 285 tests.
**Status:** LINUX SCOPE COMPLETE, AND THE COMPILE QUESTION IS ANSWERED.
`xcodebuild` runs on every dispatch (D-014) and run 33244671402 is green on
`macos-26`. What remains is genuinely device-only — rendering, gestures, size
classes, `@Observable` behaviour, scene-phase autosave, accessibility,
Instruments and signing. `docs/APPLE_VALIDATION.md` §4 and §4b are the script;
§4b lists the nine things this UI pass added to it, starting with the one that
matters most: that five tabs render as five, with no *More* item.

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

## AE-025
**Title:** Map runtime validation
**Purpose:** The world map (MASTER PROMPT 2, `docs/MAP_ARCHITECTURE.md`) is
authored and — once CI is green — compiled. Nothing about how it *renders*
is known. This task is the list of questions only a screen can answer.
**Dependencies:** macOS + Xcode + a device or simulator (blocker B-002).
**Implementation notes:** none — this is validation, not construction. If it
finds defects they become their own tasks.
**Acceptance criteria:**
- The world reads as a world at each zoom level (world / regional / local),
  and the label layout genuinely avoids collisions on a 393pt-wide screen.
- Pan and pinch behave as one gesture; a tap selects the thing under the
  finger, aircraft before airports before routes; selection cards do not
  cover what was selected.
- A route crossing the antimeridian draws as two segments leaving and
  re-entering the edges, and its aircraft crosses without a jump (BUG-012
  is fixed and unit-tested; this is the visual confirmation).
- 60fps held at 16x on a late-game save with hundreds of live flights,
  measured in Instruments — not inferred from `ae-map-bench`, which times the
  model on Linux and says nothing about drawing (TD-003).
- Paused really stops the timeline (no CPU, no battery). Reduce Motion stops
  interpolation without stopping updates.
- VoiceOver over the canvas reads a useful summary and the current selection.
- Route health is distinguishable in greyscale and with a colour-blindness
  simulation, per the dash/weight encoding.
**Tests:** manual walkthrough + Instruments evidence recorded in `docs/`.
**Status:** BLOCKED on B-002.

---

## AE-026
**Title:** Audio and haptics listening pass
**Purpose:** The audio system (MASTER PROMPT 3, `docs/AUDIO_ARCHITECTURE.md`)
is tested as policy and compiled as code. Nobody has heard a single sound.
This is the list of questions only ears and a device can answer.
**Dependencies:** macOS + Xcode + a physical device (blocker B-002). A
simulator answers most of the audio questions but **not** the haptic ones.
**Implementation notes:** none — this is validation. Defects it finds become
their own tasks. `docs/AUDIO_ASSET_MANIFEST.md` §4 is the brief for anything that
needs re-voicing rather than fixing.
**Acceptance criteria:**
- Every one of the 52 non-ambience cues triggered at least once, audibly
  (`AudioCue` has 54 cases; the other two are the looping ambience beds, which
  are not triggered but held), with the palette
  judged as a set rather than one sound at a time: does it sound like one
  product, and does it sound expensive?
- The loudness hierarchy holds by ear, not only by peak measurement — a tap
  must disappear next to an era change.
- A tap's sound arrives with the tap. Latency on a pooled `AVAudioPlayerNode`
  is the first thing that would make this feel cheap.
- 16x on a large save: the flurries carry a busy minute and nothing spams.
- BUG-013 confirmed on device: save a flying airline, quit, load — silence,
  not four first-time sounds.
- Background and foreground: audio stops, the route is released, nothing is
  left sounding, and it comes back.
- Playing next to a podcast: the game mixes and never interrupts. Silent
  switch silences it.
- Haptics read as weight rather than noise across an hour, and turning them
  off genuinely stops all of them (the regression BUG-014 fixed).
- Ambience on for an hour without becoming irritating — the test TD-007
  expects it to fail.
- Instruments: no player-node churn, no growth in audio memory over a long
  session, no CPU cost while muted.

**Added by AE-AUDIO-01** — the continuous layer, none of which has been heard:
- Every music transition heard at least once: menu → planning → operating →
  crisis and back. The crossfade must sound like a crossfade, not a cut and
  not a dip (BUG-018 was fixed blind; this is where it is confirmed).
- The four beds judged for an hour each. TD-009 expects them to be the first
  thing a composer replaces.
- The ambience response curves tuned against a real speaker (TD-010): the
  three zoom levels, saturation at 24 airborne, the pause thinning and the
  solvency recession are all plausible-on-paper numbers.
- Growth actually reads as *richer and not louder* — the property the whole
  design rests on, and the one only ears can confirm.
- Mute everything, then unmute: the mix the player built comes back.
**Tests:** manual listening + Instruments evidence recorded in `docs/`.
**Status:** BLOCKED on B-002.

---

## AE-027
**Title:** Density and hierarchy pass on the management screens
**Purpose:** The moment-to-moment audit (`docs/UIUX_FORENSIC_AUDIT.md` §18)
found ten issues that are redesign rather than defect — empty states that are
structurally present and semantically blank, rows that read as spreadsheet
lines, a hub that is four cards and space. They are listed there as D-01
through D-10.
**Dependencies:** Best done where the result can be seen (blocker B-002), and
after AE-025/AE-026 have put eyes on the map and ears on the audio.
**Implementation notes:** §18 of MASTER PROMPT AE-AUDIO-01 is explicit that
these must not be redesigned blindly, which is why they were recorded rather
than done. Two of the ten (D-06, D-08) are closer to defects than to taste and
could go first.
**Acceptance criteria:**
- Finance reads as a screen with nothing *yet* rather than a screen that is
  broken, in all four of its empty cards.
- A statement is scannable: revenue and cost are visually distinct, and the
  largest lines are findable without reading all seventeen.
- A brand-new route does not present as three warnings.
- The ops feed inserts rows rather than re-binding all of them.
- The World hub shows something live, not only links to it.
**Tests:** Core read-model tests where a finding turns out to need one;
otherwise a walkthrough on a device.
**Status:** OPEN.

---

## Backlog (do not start before AE-023 clears)

- **AE-015** — Revenue-management fare buckets (docs/EXPANSION_ROADMAP.md).
- **Hub connections** — first content update (decision D-010).
- **AI market-entry lever** — post-playtest (BALANCING F-001).
- Everything else: `docs/EXPANSION_ROADMAP.md`, `tasks/POST_LAUNCH.md`.

---

## AE-028 — UI/UX polish, density, design system (MASTER PROMPT 4)
**Status:** IN PROGRESS 2026-08-30. Foundation complete; screen-by-screen
rework continuing.

**Done:**

*Design system*
- `AEType` — twelve type roles, replacing "pick a system size and hope"
  (`docs/DESIGN_SYSTEM.md` §2).
- `AEPanel` / `AEMetric` / `AECompactMetric` / `AEMetricStrip` — containers
  below a card, so a screen is not 40 equal rounded rectangles (§3).
- `AEButtonRole` — primary / secondary / tertiary / destructive (§4), adopted
  on the three genuine primary actions.
- `Rejections` — refusals answer what happened, why, and what to do next (§8).

*Core read models*
- `NetworkSummary` + `FleetSummary`, with tests holding each against the
  per-row models it summarises (§5). 17 new tests this phase, 381 total.
- `RouteVerdict` + `Vocab.routeVerdict` — Route Detail says *why* a route earns
  or loses, attributed to the dominant term in its own recorded month, and
  stays silent when nothing stands out (§13).

*Screens*
- **§6 Home** leads with the pulse — in the air, load factor, aircraft used,
  month to date — above yesterday's digest and next week's calendar, and shows
  the live-flight number Core was already computing and no screen rendered.
- **§9/§12** Fleet and Routes boards gained summary headers fed by those models.
- **§10/§11** aircraft silhouettes in the market and detail header; new / used /
  lease as one price comparison.
- **§13 Route Detail** reordered to the decision hierarchy; operations gained
  frequency and distance.
- **§14 Route Creation** shows competition (`incumbents`), which Core computed
  and the sheet discarded.
- **§15 Finance** gained month-to-date revenue / costs / operating profit and a
  best-and-weakest-route panel.
- **§16 World** events show severity as a band.
- **§22** card fatigue: Home 6→2, Route Detail 8→4, Progression / Reputation /
  Economy 9→3.

*Bugs*
- BUG-027 live flights counted every aeroplane in the world.
- BUG-028 a save warning followed the player into the next game.
- BUG-029 / BUG-030 dead navigation links on three entry paths.
- BUG-031 derived caches keyed on the tick, so a paused player's own command
  changed nothing on screen. Found by review; older than this phase.

**Still not done:**
- The type scale reaches shared components and reworked screens only; several
  hundred call sites still name system sizes (TD-011).
- `MapModel.health`'s `.grounded` and `NetworkSummary.idleRoutes` describe one
  population through two Core functions. A test now fails if they disagree, but
  the duplication remains (TD-012).
- Nothing checks that a value-based navigation link can resolve (TD-013) —
  three instances found by hand is the argument for the script.
- §14's estimated economics: projecting revenue before an aircraft is assigned
  would be fabrication, so the inputs are shown instead.
- iPad screens are phone layouts in a wider column (§31); §18's era-scaled
  visual storytelling is untouched.
- **Nothing has been visually validated.** There is no simulator and no device
  in this environment, so every claim above is "compiles, and is tested where
  testable" — never "looks right" (TD-003, TD-006).

---

## AE-029 — Fleet and aircraft experience (MASTER PROMPT 5)

### Done

**Assignment (§23, §24)** — `AssignmentEligibility` in Core, mirroring
`AssignAircraftToRouteCommand.validate` beside the validator, used by both
pickers. Ineligible pairings shown with their reason. Fit notes derived from
real data or omitted. BUG-032.

**Refusals (§24)** — three dead mappings fixed, `progression.lockedCategory`
and four fleet codes added, `RejectionCodeContractTests` pins each string
against a real command. BUG-033.

**Market and detail (§10, §11, §21)** — `AircraftRole` and
`SeatEfficiencyBand`; the raw burn-per-seat figure replaced by a band against
the catalog's best, on both the market card and the detail header.

**Fleet at scale (§17, §37)** — `FleetFilter` in Core, tested for partitioning
the fleet; bar appears past eight aircraft; empty results offer the way back.

**Content audit (§38, §39)** — measured, documented, pinned, not rebalanced.
`docs/AIRCRAFT.md` corrected.

**Docs (§49)** — `docs/AIRCRAFT_UX.md`, `docs/AIRCRAFT_ASSET_BIBLE.md`.

### Still not done

- **§31 "Show on map"** — the map exposes no focus API at all. There is no
  camera to ask; adding one is real work, not wiring, and it is the single
  most valuable remaining item because it closes the last navigation loop.
- **§14 acquisition moment** — no confirmation using the artwork. The sheet
  dismisses and the feed announces it.
- **§26 aircraft-level profitability** — Core attributes economics to routes,
  not airframes. Splitting a route's P&L across the aeroplanes that flew it
  would be an invented allocation, so route economics are shown instead.
- **§18 grouping** — filtering shipped; grouping did not. Filters answered the
  scale problem and grouping would have been a second control competing with
  them for the same row.
- **§22 registrations** — Core has no player-facing aircraft identifier and
  §22 says not to add a persisted one for decoration. Not added.
- **TD-014/TD-015** — artwork does not distinguish within a class, and the
  fleet row still uses an SF Symbol rather than the silhouette. Both need a
  device to judge.

---

## AE-031 — The app runs (MASTER PROMPT: premium game feel)

### Done
- `AirlineEmpireUITests`: first target that runs the app. Launch, found an
  airline, all five tabs, market reachable. 3 tests.
- CI boots a real simulator (resolved at runtime, not hardcoded), keeps the
  result bundle, and prints downscaled screenshots into the job log.
- BUG-035 found by screenshot, root-caused, fixed, re-confirmed by screenshot.
- `docs/UI_FULL_AUDIT.md` — first audit here written against screens, with
  every finding marked observed / asserted / read.

### Next, in order
1. **Dark appearance.** The app has been seen only in light. One line in the
   UI test. Highest-value next observation, because the design system is
   written about an appearance nobody has verified exists.
2. **Frame assertions** (TD-019) so BUG-035's class fails CI rather than
   waiting for someone to look.
3. **Extend the journey**: buy an aircraft, open a route, assign it. That is
   where BUG-032 lived and it is still undriven.
4. Home, Map, Finance, World — observe, then audit.

## AE-034 — Map performance (2026-08-31)

### Done
- Baseline measured (run 84), P0 fixes landed, after measured (run 85):
  drag avg −32/−48 %, churn −66 %, hops −77 %, worst frame now the one-time
  map-open build. `docs/MAP_P0_PERFORMANCE_REPORT.md` is the evidence.
- Runtime audits written: `docs/PLAYER_JOURNEY_RUNTIME_AUDIT.md`,
  `docs/GAME_EXPERIENCE_PRIORITY.md` (ranked EXP backlog).

### Next, in order
1. Verify on next CI run: MAP-CACHE counters (regex fixed) and the lease
   aim correction (BUG-041).
2. Counter assertions from that run's evidence (TD-024).
3. EXP-01/EXP-02 (post-checklist direction on Home; summary strips) — the
   two P2s a player meets in their first session.
4. Game-feel moments (first revenue, route draw-in, assignment) — designs
   in `docs/GAME_EXPERIENCE_PRIORITY.md`, each on the settle/celebration
   machinery, never per-frame.
