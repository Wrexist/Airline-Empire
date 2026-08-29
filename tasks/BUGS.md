# Airline Empire — Bug Register

Open bugs, with reproduction steps and the architectural layer at fault.
Bugs are fixed at the correct layer, never papered over in the UI.

Format: BUG-nnn — Title · Severity · Phase found · Repro · Root cause · Status.

---

## BUG-001 — DemandSystem.referenceFare inaccessible to the app target
**Severity:** P1 (compile blocker) · **Phase found:** AE-023 static
integration audit, 2026-08-26.
**Repro:** Compile AirlineEmpireApp — `OpenRouteSheet` (RoutesView.swift)
calls `DemandSystem.referenceFare(distanceKm:tuning:)`, which was
`internal` to AirlineEmpireCore.
**Root cause:** The function was authored for in-module read models
(Phase 14) and its cross-module use in the route-opening sheet was never
compiled (B-002), so the access level was never exercised.
**Fix layer:** Core — access level only (`public`), no behavior change;
the app duplicating the fare formula would violate "views never
calculate". Core build + demand/read-model tests re-run green.
**Status:** FIXED 2026-08-26.

---

## BUG-002 — No way to assign an aircraft to a route in the authored UI
**Severity:** P1 (core loop unplayable) · **Phase found:** AE-023
continuation session, 2026-08-26.
**Repro:** Open a route, go looking for "assign aircraft": FleetView's
swipe actions offer only Unassign/Sell/Return; RouteDetailView had no
aircraft section; no screen submitted `AssignAircraftToRouteCommand`.
Flights can never be scheduled, so nothing ever flies.
**Root cause:** Phase 14 authored the fleet/route screens against read
models but the assignment interaction fell between the two screens; with
zero runtime validation (B-002) nobody ever walked the loop.
**Fix layer:** App — RouteDetailView gains an "Aircraft" card: assigned
list with Unassign, plus an Assign menu of idle active aircraft
(submits the existing, test-covered Core command). Status remains
AUTHORED until the macOS pass.
**Status:** FIXED (authored) 2026-08-26.

---

## BUG-003 — Game over is a dead end
**Severity:** P1 (player cannot continue playing) · **Phase found:**
V3 Linux continuation, 2026-08-26.
**Repro:** Let the airline collapse. `RootView` switches to `GameOverView`
whenever `progression.gameOver`, and that view had no controls at all.
`GameController` had no way to release a session, so the player was stuck
on the game-over screen for the rest of the app's life — no new game, no
loading another save, no menu.
**Root cause:** The new-game path is gated on `controller.hasGame`, which
only ever went `false → true`. Nothing could take it back.
**Fix layer:** App — `GameController.quitToMenu()` cancels the pump,
event, and rejection tasks and clears session/snapshot/catalog state;
`GameOverView` gains "Start a new airline"; Settings gains "Save and quit
to menu" (which also closes the "cannot load a different save mid-game"
gap).
**Status:** FIXED (authored) 2026-08-26.

---

## BUG-004 — Player feed showed rivals' private business
**Severity:** P1 (misleading financial information) · **Phase found:**
V3 Linux continuation, 2026-08-26.
**Repro:** Play with competitors. `StatementRollupSystem` emits
`statementClosed` for **every** airline (`for airlineID in
state.orderedAirlineIDs`), and `FlightOpsSystem` emits flight events for
every flight. The dashboard feed rendered the raw stream, so with 5 rivals
the player saw 6 "Month N closed: ¤X" lines a month — 5 of them other
airlines' books, presented as the player's own — plus every rival's flight
delays. Separately, `airlineEnteredAdministration` had no case in
`EventRow`, so the single most important warning in the game rendered
nothing at all.
**Root cause:** No audience concept existed. Event payloads carry entity
IDs, not owners, so classification needs state — which the view does not
have and must not compute.
**Fix layer:** Core (additive, pure) + App. `GameState.subjectAirline(of:)`
and `isFeedEvent(_:for:)` classify an event against the state that
produced it; `GameSession.events(playerFeedOnly:)` filters at publish time.
`GameController` subscribes to the filtered stream; `EventRow` renders
administration and collapse with alarm emphasis and distinguishes the
player's own fate from a rival's. No state added, save format unchanged.
**Tests:** `EventFeedTests` (6).
**Status:** FIXED 2026-08-26 (Core+App; App remains Apple-validation pending).

---

## BUG-005 — Commands rejected while running failed silently
**Severity:** P1 (core actions fail with no feedback) · **Phase found:**
V3 Linux continuation, 2026-08-26.
**Repro:** Unpause, then submit any command that fails validation (buy an
aircraft you cannot afford). `GameSession.submit` returns `nil` for a
queued command by design; the engine rejects it at the next tick boundary
into `lastCommandResults`, which `GameSession.advance` then overwrites on
the following chunk. Nothing ever reached the UI: no alert, no event, no
change. The player taps a button and the game does nothing, forever
unexplained.
**Root cause:** The rejection existed in Core but had no delivery path out
of the actor. Only the paused path returned a result.
**Fix layer:** Core (additive) + App. `GameSession.rejections()` publishes
queued-command rejections per chunk, before the next advance can overwrite
them; `GameController` subscribes and routes them to the existing
rejection alert.
**Tests:** `EventFeedTests.queuedCommandRejectionReachesTheSubscriber`,
`appliedQueuedCommandsProduceNoRejection`.
**Status:** FIXED 2026-08-26 (Core+App; App remains Apple-validation pending).

---

## BUG-006 — Airport populations 1000x too large; pricing had no downside
**Severity:** P1 (core mechanic inert; misleading UI) · **Phase found:**
2026-08-27, while producing a screen-by-screen dump of a real game to show
what the UI would display.
**Repro:** Start any game, open a route, raise the fare. Passengers carried
do not change. At 0.6x and 2.4x of the reference fare a route carries the
identical 75,780 passengers at exactly 100% load, and monthly profit rises
¤614k -> ¤7.43M. Raising price cost nothing, so the dominant strategy was
to charge as much as the UI allowed.
**Root cause:** `AirportSpec.Demographics.populationThousands` held raw
people rather than thousands (Tromso 80,000; London 14,800,000; Tokyo
37,300,000 — real metro populations). The gravity model uses
`sqrt(popA * popB)`, so every demand pool was exactly 1000x too large —
~1,600x the seats any aircraft could offer. Demand could therefore never
fall below capacity, and the interior revenue optimum the exponential price
utility was designed around (docs/ECONOMY.md, Phase 7) was unreachable.
Same class as the Phase 8 `tuning.json` cents bug, also 1000x.
**How it hid:** every unit test of the demand curve passed, because the
curve itself was correct; the defect only appears when capacity truncates
demand in the full pipeline. The balance battery never ran a high-fare
strategy, so it measured the symptom (fat margins, F-001) and not the cause.
**Fix layer:** Content — all 80 populations divided by 1000 so the data
matches its declared unit. No tuning constant, formula, or capacity changed.
Secondary (App/Core): `OnboardingModel` published the raw pool as
"travellers/day" (≈2,610,001 on the first suggested route); it now reports
`expectedDailyPassengers`, the share a representative starter service would
actually capture, via `DemandSystem.expectedCapturedPassengers`.
**Verification:** price now moves volume (load 99.5% -> 45.4% from 1.0x to
2.0x fare) and profit has an interior optimum at ~1.6x. Full suite 251
passing before and after; release bench unchanged at 3.02 s. Pinned by
`BalanceTests.pricingHasRealConsequencesEndToEnd`, which fails on the old
data with all four diagnostics. Documented as BALANCING F-006; F-001
marked root-caused.
**Status:** FIXED 2026-08-27.

## BUG-007 — Deleted-entity events leaked into the player's feed
**Severity:** P2 (misleading feed; undercounted digest) · **Phase found:**
CodeRabbit review of PR #1, 2026-08-28 — verified against the code and
confirmed real.
**Repro:** `GameSession.publish()` classifies a whole tick chunk's events
against the state at the *end* of that chunk. `SolvencySystem.collapse()`
deletes an airline's routes (`state.routes[id] = nil`) and fleet
(`state.aircraft[id] = nil`) within the same chunk. The flight events that
airline emitted earlier the same day then resolve to no owner, and
`isFeedEvent` treated a nil subject as world news — so a collapsing rival's
`flightDelayed` events reached the player's filtered feed and rendered as
if they were the player's own. The same nil-owner path undercounted
`DailyDigestModel.flightsCompleted` after any route closure.
**Root cause:** conflating "belongs to nobody" (a storm, the calendar) with
"owner can no longer be resolved" (an entity deleted since). Both arrived
as `subjectAirline(of:) == nil`.
**Fix layer:** Core. `GameState.isEntityScoped(_:)` distinguishes events
whose subject must be resolved from an aircraft, route, or flight; an
entity-scoped event with an unresolvable owner is now excluded from the
feed rather than promoted to world news. `dailyDigest` additionally reports
`isComplete: false` when it saw flight events it could not attribute, so a
truncated count is never presented as a whole day.
**Not done:** storing the subject airline in the event payload, as the
review suggested. `eventLog` is persisted inside `GameState`, so changing
`SimEventKind` payloads would force save format v11 for a defect that a
pure read-side fix resolves. Save format stays v10.
**Tests:** `EventFeedTests.deletedEntityEventsAreNotTreatedAsWorldNews`,
`collapsingRivalDoesNotLeakIntoThePlayerFeed`.
**Status:** FIXED 2026-08-28.

---

*(Historical note: bugs found and fixed test-first inside a phase are
recorded in that phase's COMPLETED.md entry, not here — this register is
for bugs that escape a phase.)*

---

## BUG-008 — First screen after founding an airline crashes the app
**Severity:** P0 (crash on the primary path) · **Phase found:** TestFlight
build 1.0.0 (1) on a physical iPhone 15 Pro, iOS 26.5.2, 2026-08-29 — the
first time the app has ever run on a device.
**Repro:** Launch, name an airline, tap "Found the airline". The Dashboard
appears and the process dies immediately. 100% reproducible; it is the first
thing every new player does.

**Crash:**
```
EXC_BREAKPOINT (SIGTRAP) · Swift runtime failure: precondition failure
GameCalendar.date(at:startYear:)   (GameCalendar.swift:28)
GameState.dailyDigest(for:day:)    (DailyDigest.swift:114)
DashboardView.body.getter          (DashboardView.swift:30)
```

**Root cause:** `DashboardView` asks for the evening digest of *yesterday* —
`snapshot.clock.now.dayIndex - 1`. On the first day `dayIndex` is 0, so it
asks for day −1. `dailyDigest` accepted that, built a `SimTime` before the
epoch, and handed it to `GameCalendar.date(at:)`, whose
`precondition(day >= 0, "Simulation time before epoch has no date")` is a
trap in release builds.

Two defects, one line apart in the stack, and both were fixed:

1. **Core accepted a day that cannot exist.** `dailyDigest` already returns
   nil for an unknown airline; a day before the game began is the same kind of
   "no such thing" and now returns nil too. This is the fix that guarantees no
   other caller can reach the precondition.
2. **The view asked a question with no answer.** `SimTime.previousDayIndex`
   now returns `Int64?`, so "there is no yesterday" is representable instead
   of being arithmetic that silently produces −1.

**Why the test suite missed it:** every digest test built a world that had
already run for at least a day (`DailyDigestTests.flyingWorld` advances the
clock before asserting anything), so day 0 — the only day a player is
guaranteed to see — was the one day never exercised. The new tests cover it
directly, and were verified the hard way: with the Core guard removed they
crash with the same trap, and with it they pass.

**Fix layer:** Core (`DailyDigest.swift`, `SimTime.swift`) and App
(`DashboardView.swift`). Regression tests: `digestBeforeEpochIsNil`,
`previousDayIndexIsSafe`. Full suite 257 tests green on Linux, Swift 6.0.3.
**Status:** FIXED 2026-08-29, awaiting a device run of the next build to
confirm on hardware.



---

## BUG-009 — Six tabs overflow into the system *More* list on iPhone
**Severity:** P0 (two of six top-level areas demoted, and the only path to
saving or quitting among them) · **Phase found:** UI/UX forensic audit,
2026-08-29.
**Repro:** Launch on any iPhone. `GameTabs` declared six `tabItem`s — Home,
Map, Routes, Fleet, Finance, World. iOS shows four plus an automatic *More*
tab once a tab bar passes five, so Finance (the survival system) and the whole
World hub (events, competitors, progression, missions, service tier,
reputation, **save and quit**) sat one level deeper than everything else,
inside a system-styled list that ignores the app's design language.
**Root cause:** the tab set grew a screen at a time across phases 14–17 and
nobody counted it against the platform's limit. Invisible on Linux; invisible
to a compiler; visible the first second the app renders.
**Fix layer:** App. Five tabs: Routes and Fleet merge into **Network** behind
a segmented switch (they are the two halves of one question and a player
crosses between them constantly), and Settings moves to the Home toolbar,
where a player looks for settings and where saving and quitting belong.
**Status:** FIXED (authored) 2026-08-29 — needs a device to confirm, like
every rendering claim in this project.

---

## BUG-010 — Capability programs offered a Start button that could only refuse
**Severity:** P2 (a control whose sole outcome is an error) · **Phase found:**
while implementing the audit's UI-008, 2026-08-29.
**Repro:** Start any game and open World → Progression. Every capability shows
an enabled "Start" button. Tap one: `StartCapabilityProgramCommand.validate`
rejects with "Capability programs open in the National era" — three eras away.
**Root cause:** the era gate lived only inside the command's `validate`, so
the view had no way to know about it and rendered the same affordance in every
state. The same hole hid the program limit and affordability.
**Fix layer:** Core (additive) + App. `CapabilityProgram.unlockEra` names the
gate once and the command defers to it; `ProgressionModel.CapabilityStatus`
models `.eraLocked`, `.blockedBySlots` and `.unaffordable` alongside
`.available`, and its `isStartable` is asserted by test to agree with the
command's own validation in every state.
**Tests:** `AdvisoryModelTests.startableAgreesWithTheCommand`,
`capabilitiesAreEraLockedEarly`, `programLimitIsVisible`.
**Status:** FIXED 2026-08-29.

---

## BUG-011 — The monthly profit chart drew its zero line in a different place for every bar
**Severity:** P1 (the finance screen misrepresented its own data) ·
**Phase found:** UI/UX forensic audit, 2026-08-29.
**Repro:** Play to two closed months with one profit and one loss, then open
Finance. `MonthlyBars` built each column as a centred
`VStack { Spacer; +bar; 1pt rule; -bar; Spacer }`. The column's content height
is `barHeight + 1`, and the `HStack` centres each column independently — so
the rule that represents zero sat at a different y for every month. Bars could
not be compared against each other or against zero.
**Root cause:** a hand-rolled chart that encoded the baseline as *layout*
rather than as a scale. `docs/UI_ARCHITECTURE.md` §2 specified Swift Charts
from the start; the hand-rolled version was a placeholder that outlived its
note.
**Fix layer:** App. Swift Charts `BarMark` on a shared y-scale, with axes,
month labels and per-bar accessibility values.
**Status:** FIXED (authored) 2026-08-29.

---

## BUG-012 — Great-circle arcs crossing the date line drew a line back across the whole world
**Severity:** P1 (the map's central visual, wrong on exactly the routes a
player is proudest of) · **Phase found:** map overhaul adversarial bug hunt
(MASTER PROMPT 2 §27), 2026-08-29, in code written earlier the same session.
**Repro:** Open a route from Tokyo (HND) to Los Angeles (LAX) and look at the
map. The slerp waypoints are correct in latitude/longitude, but projected to
normalised x they run ~0.94 → 0.99 → **0.01** → 0.06. A path stroked through
those points draws a near-full-width horizontal streak across the Atlantic,
Africa and Eurasia between the two Pacific segments — and the aircraft marker
teleports along it.
**Root cause:** `MapMath` projected each waypoint independently and the
renderer stroked them in order. Projection is per-point correct; a *polyline*
through an equirectangular projection is not, because the seam at ±180° is a
discontinuity in x that a straight segment interpolates straight through.
Core's own comment claimed the date line was handled — true of the points,
false of the line between them, which is the kind of half-truth a comment can
carry for a long time.
**Fix layer:** Core. `MapMath.unwrap(_:)` walks the projected points and
carries a whole-world offset whenever consecutive x jump more than half a
world, so the arc becomes monotone and may legitimately run past x=1 or below
x=0; `MapMath.worldOffsets(for:)` then reports which ±1 world copies a shape
touches, and the renderer draws it once per copy so the arc leaves one edge
and re-enters the other. Fixed in Core rather than in the drawing code because
the guarantee belongs to the projection, and the same unwrap is what makes
flight-marker interpolation continuous across the seam.
**Tests:** `AntimeridianTests` (7) — an eastward Pacific crossing, a westward
one, a route that does not cross (offset never moves), monotonicity of the
unwrapped sequence, offsets for a shape straddling the seam, and that unwrap
preserves y exactly.
**Status:** FIXED 2026-08-29 (Core; covered by tests, so this one is *tested*,
not merely authored).

---

## BUG-013 — Loading a played save would have replayed the whole first hour
**Severity:** P1 (a design defect caught before it shipped, in a system that
did not exist yet) · **Phase found:** audio architecture, MASTER PROMPT 3 §26,
2026-08-29.
**Repro (of the naive design):** play until aircraft are flying and money is
coming in, save, quit, load. A presentation layer that remembers "has the
player seen their first departure?" in its own memory starts that memory
empty on load — so the game announces the first route, the first departure,
the first arrival and the first revenue, all four, at somebody who has been
running an airline for a season.
**Root cause:** the once-per-campaign moments are not events. They are facts
about the world that become true once, and the batch that contained the
arrival is long gone by the time anyone reloads. Any memory of them held
outside the save is wrong after a restore.
**Fix layer:** Core. `AudioDirector.Milestones(state:)` reads the airline's
own persisted books — `RouteStats.flightsCompleted` and `passengersCarried`,
which travel with the save — and the director is constructed from the state
at session start. A mature airline therefore begins with all four already
true. They also latch forward only, so closing every route cannot re-arm
"your first route".
**Tests:** `loadedGameDoesNotReplayMilestones`,
`firstTimesFireOnceForANewAirline`, `milestonesLatchForward`,
`loadingPublishesNoBacklog`. Both directions were verified by sabotage:
seeding from an empty `Milestones()` fires all four at a loaded save, and
making the state check always return false silences them for a new one.
**Also checked and found already correct:** `GameSession` seeds
`deliveredEventCount` from `state.eventLog.totalCount` at init and `events()`
yields no backlog, so the *stream* never republished history. That was
existing good design, not something this phase added, and it is now covered
by a test so it stays that way.
**Status:** FIXED 2026-08-29 (Core, tested).

---

## BUG-014 — The haptics setting only worked on two screens
**Severity:** P2 (a preference the player sets and the app ignores) ·
**Phase found:** audio architecture audit, MASTER PROMPT 3 §2, 2026-08-29.
**Repro:** Settings → turn Haptics off. Open the map and change the overlay:
the phone still buzzes. Same in the network Routes/Fleet switcher, and three
times over in new-game (livery, start airport, difficulty).
**Root cause:** haptics had grown one `.sensoryFeedback` call at a time as
screens were built. Seven call sites existed; only two — the celebration
banner and the speed control — passed the `preferences.haptics` condition.
The other five simply fired. Nothing enforced the check because nothing named
it: the condition was a closure each site had to remember to write.
**Fix layer:** App, structurally rather than by adding five conditions. All
feedback now goes through one path (`Feedback.emit`), which consults the
preference once; views ask for a semantic cue and never touch
`.sensoryFeedback` directly. `grep -rn sensoryFeedback AirlineEmpireApp`
returns nothing, which is what stops the sixth site from reintroducing it.
**Status:** FIXED 2026-08-29.

---

## BUG-015 — The celebration banner was about to fire two haptics for one moment
**Severity:** P2 (found while building, fixed before it shipped) ·
**Phase found:** MASTER PROMPT 3 §29 bug hunt, 2026-08-29.
**Repro (of the state mid-phase):** advance to a new era. `CelebrationOverlay`
carried its own `.sensoryFeedback(.success, trigger: celebration.id)`, and the
new audio director independently gives `eraAdvanced` a `.heavy` haptic — as it
does for milestones, achievements, finished capability programmes and
completed missions, which are the other four things that raise a celebration.
Every one of them would have buzzed twice.
**Root cause:** two systems acquiring responsibility for the same moment, one
of them newly. Exactly the "haptics triggering repeatedly" failure the phase
brief names.
**Fix layer:** App. The banner's own feedback is removed, with a comment
saying why, because the next person to look at that view will notice it is the
only celebration in the app that does not announce itself and wonder.
**Status:** FIXED 2026-08-29.

---

## BUG-016 — Per-play volume would have ducked a long sound under a later tap
**Severity:** P2 (a real defect in new code, found by reading it) ·
**Phase found:** MASTER PROMPT 3 §29 bug hunt, 2026-08-29.
**Repro (of the first implementation):** trigger an era change (a 2.6-second
swell) and tap eight things while it plays. The eighth tap lands on the same
pooled `AVAudioPlayerNode` and sets its volume to the UI level — and an
`AVAudioPlayerNode`'s volume applies to what it is *currently sounding*, not
to the buffer being scheduled. The swell ducks to a tap's loudness mid-note.
Eight sounds inside one tail is not a stretch: a 16x flurry reaches it.
**Root cause:** treating a node property as if it were a per-buffer parameter.
**Fix layer:** App. The per-category trim is scaled into the samples once, at
load; node volume is a constant 1; and the mixer carries the player's master
setting, which is uniform across every sound at any instant so re-levelling a
sounding node is harmless. A play now costs one `scheduleBuffer` and nothing
else, which also serves §28.
**Status:** FIXED 2026-08-29 (not runtime validated — see TD-006).

---

## BUG-017 — The audio graph was wired to guess its own format, and would have crashed
**Severity:** P0 had it shipped (a crash on the first sound of every session) ·
**Phase found:** MASTER PROMPT 3 §29 bug hunt, 2026-08-29, in code written the
same day.
**Repro (of the first implementation):** launch the app and trigger any cue.
`AudioEngine.prepare()` connected the eight player nodes with `format: nil`
and only *then* decoded the buffers. With a nil format the engine infers one
from the destination, which resolves to the hardware's — stereo. Every asset
in this game is mono. `AVAudioPlayerNode.scheduleBuffer` with a buffer whose
format does not match the node's output connection raises an Objective-C
exception, and Swift cannot catch that: it is a crash, not a failure.
**Root cause:** ordering. The graph was built before there was anything to
measure, so the only format available to build it with was a guess. Nothing in
a compile can see this — the code is perfectly well-typed — and no Linux test
can reach it, which is exactly the class of defect that survives to a device.
**Fix layer:** App. Buffers are decoded first, the voices are wired with the
real format of a real decoded buffer, and `play` additionally refuses a buffer
whose format does not match the node it would go to — turning any future
mismatch into silence rather than a crash. `scripts/audio/check-assets.py`
already enforces that all 52 assets share one format, which is what makes
"any buffer's format" a safe choice.
**Status:** FIXED 2026-08-29 (authored; the crash it prevents has never been
observed, because nothing has run — see TD-006).
