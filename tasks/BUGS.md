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

---

## BUG-018 — Every music transition died a quarter-second in
**Severity:** P1 (the music system's central feature, broken in its first
implementation) · **Phase found:** AE-AUDIO-01 §23 bug hunt, 2026-08-29, in
code written the same day.
**Repro (of the first implementation):** pause a running game. The music state
moves `operating → planning`, a four-second equal-power crossfade starts, and
250 ms later the next snapshot arrives. `applyMusic` re-derives the state,
finds it unchanged, and calls `setMusic(sameTrack, fade: 0)` to re-level —
which took the "same bed" branch, and that branch **cancelled the fade in
flight**. The two decks are left stranded wherever the ramp had reached: the
outgoing track at about 0.98, the incoming at about 0.08. The game stays on
the *previous* bed at nearly full volume, permanently, and every subsequent
transition does the same thing.
**Root cause:** a re-levelling path and a transition path sharing one entry
point, in a system whose caller runs four times a second. The doc comment on
`setMusic` even claimed it was "safe to call from an observation that fires on
every snapshot" — which was true of the duplicate-track case it was written
for and false of the fade it also cancelled.
**Fix layer:** App, in three places, because one would not have been enough:
1. The same-track branch no longer touches a running fade — it re-levels only
   when `musicFade == nil`. A running fade reads `musicTarget` itself.
2. The crossfade reads `musicTarget` on **every step** rather than capturing
   it once, so a slider moved mid-transition is obeyed instead of ignored for
   four seconds.
3. `applyMusic` only calls into the engine when the state or the gain actually
   changed, so the hot path is not in the fade machinery at all.
**Also removed:** `duckContinuous`, an unused helper that multiplied the
ambience mixer by a factor *cumulatively* and never restored it — repeated
calls would have driven the bed to zero and left it there. Dead code with a
latent bug in it; deleting beat fixing.
**Status:** FIXED 2026-08-29 (authored; not runtime validated — no crossfade
has ever been heard, TD-006).

---

## BUG-019 — The audio session category was silently never applied
**Severity:** P1 (the game would have interrupted whatever the player was
listening to) · **Phase found:** CodeRabbit review of PR #6, 2026-08-29.
**Repro:** launch the app with a podcast playing. The podcast stops.
**Root cause:** `setCategory(.ambient, mode: .default, options: [.mixWithOthers])`.
`.mixWithOthers` is only valid with `.playback`, `.playAndRecord` and
`.multiRoute`; passing it with `.ambient` makes `setCategory` throw. The call
site used `try?`, so the throw was swallowed and the session stayed on its
default **`.soloAmbient`** — which does not mix and does interrupt.
`.ambient` already mixes by definition, so the option was not merely
unnecessary, it was the thing that stopped the category from being set at all.
**Why it survived review here:** the line is one call with a plausible comment
above it explaining behaviour that the line prevented. Nothing in a compile or
a Linux test can reach it, and `docs/AUDIO_ARCHITECTURE.md` §10 asserted the
correct behaviour confidently enough that re-reading the file did not question
it. A confident comment is not a mechanism.
**Fix layer:** App. `setCategory(.ambient, mode: .default)`.
**Status:** FIXED 2026-08-29 (authored; not runtime validated — no audio
session has ever been configured on a device, TD-006).

---

## BUG-020 — A parked aircraft made its airport permanently untappable
**Severity:** P1 (the map's most-used target, unreachable) · **Phase found:**
CodeRabbit review of PR #6, 2026-08-29.
**Repro:** open the map with any aircraft on the ground at home — the normal
state — and tap the home airport. The parked aircraft is selected instead.
The airport can never be selected while anything is parked there.
**Root cause:** `MapFrame.drawFlights` appended **every** drawn flight to the
hit geometry, airborne or not. A parked flight projects to its airport's own
position, and `MapHitTester.hit` tests flights first, with a 26pt tolerance,
returning on the first hit. So a 2pt dot with a 26pt target sat on top of the
airport and won every tap.
**The reasoning that allowed it:** `MapHitTester`'s ordering comment argues
that "an aircraft is the smallest and most transient thing on the map, so it
must win where it overlaps". That is a sound argument about an aircraft *in
flight*. It is not an argument for a stationary dot outranking the airport it
is drawn on top of, and the code applied it to both because the distinction
was never made.
**Fix layer:** App. Only airborne flights enter the hit geometry. Parked
aircraft remain reachable through the airport card, which is the better route
to them regardless.
**Status:** FIXED 2026-08-29 (authored; the map has still never been tapped —
TD-003).

---

## BUG-021 — "Save and quit to menu" threw the save away
**Severity:** P0 (silent, unrecoverable loss of player progress, on the button
whose entire purpose is not losing it) · **Phase found:** CodeRabbit review of
PR #6, 2026-08-29, and independently while tracing it.
**Repro:** play past the last autosave, open Settings, tap "Save and quit to
menu", reload the save. Everything since the last autosave is gone, and
nothing said so.
**Root cause:** ordering across an async boundary.

    controller.saveNow()      // starts a Task
    controller.quitToMenu()   // runs now; sets session = nil

Both the button body and `saveNow` are on the main actor, so the queued task
cannot begin until the button's closure returns. By then `quitToMenu` has
released the session, and `save(slot:announce:)` opens with
`guard let session else { return }` — so it returns having written nothing.
The failure is silent twice over: no file is written, and the code path that
sets `lastSaveOutcome = .failed` is never reached, so the existing "say what
happened when a save fails" machinery (UI-012) reports success by omission.
**Fix layer:** App, in the controller rather than the screen.
`saveAndQuit(slot:)` awaits the save and only then quits, and it carries
`lastSaveOutcome` across the transition so a failed save is still reported on
the menu — `quitToMenu` clears it.
**Status:** FIXED 2026-08-29.

---

## BUG-022 — A rival's strike was reported as disrupting the player's routes
**Severity:** P2 (a false alarm on the map's disruption overlay, contradicting
the game's own wording of what a strike does) · **Phase found:** CodeRabbit
review of PR #6, 2026-08-29.
**Repro:** fly out of any large airport a competitor also serves, wait for that
competitor to strike. The overlay reports "1 world event touching your routes"
and names routes that are flying normally.
**Root cause:** for `.strike(airline)`, `affected` collects every airport the
striking airline's routes touch, and `touched` then names every *player* route
sharing one of those airports. Sharing a hub with a rival is the normal case at
a large airport, so the two carriers meeting was enough to manufacture the
claim. `Vocab.worldEventEffect` describes a strike as affecting that airline's
own flights, so the overlay contradicted the text beside it.
**Fix layer:** Core (`MapModel.mapModel`). A strike names player routes only
when the striking airline *is* the player. The affected airports are still
listed — the strike is real, it is simply not the player's.
**Status:** FIXED 2026-08-30. Covered by a test that fails on the old
behaviour (all three player routes claimed).

---

## BUG-023 — An arriving aircraft snapped to due north
**Severity:** P3 (cosmetic, but the map is the screen where a wrong picture is
indistinguishable from a right one) · **Phase found:** CodeRabbit review of
PR #6, 2026-08-29 (app side); the identical defect in Core was found while
fixing it.
**Repro:** watch any flight reach its destination at x4 or x16.
**Root cause:** heading was sampled as the bearing from the current point to
one 2% further along the arc. Progress is clamped to 1 so a flight waiting for
the next snapshot has `advanced == 1` and `min(1, advanced + 0.02) == 1` — two
identical coordinates. `MapMath.heading` computes `atan2(0, 0)` for those and
returns 0, so the symbol rotated to north and stayed there until the snapshot
changed.
**Fix layer:** Core. `MapMath.heading(alongRouteFrom:to:at:)` measures the leg
just travelled once the fraction reaches 1, and both call sites — the app's
interpolator and Core's own `mapModel` — now use it, so the two cannot drift
apart again.
**Status:** FIXED 2026-08-30.

---

## BUG-024 — A milestone silenced the music instead of ducking it
**Severity:** P2 · **Phase found:** CodeRabbit review of PR #6, 2026-08-29.
**Repro:** complete a mission. The music stops for twelve seconds and fades
back in.
**Root cause:** `MusicDirector.asset(for: .milestone)` returns nil on purpose —
a milestone is marked by its own cue, not by a track — and the comment beside
it says the state exists "so the *bed* can duck under the cue and return".
`applyMusic` handed that nil straight to `setMusic`, which fades out and stops
the deck. `MusicDirector.duck(for: .milestone)`, the 0.55 that was written for
exactly this, was applied to nothing.
**Fix layer:** App (`Feedback.applyMusic`). The bed is derived from the state
*without* the celebration, and the celebration decides only the level.
**Status:** FIXED 2026-08-30 (not runtime validated — TD-006).

---

## BUG-025 — Turning sound effects off silenced the music for the session
**Severity:** P2 · **Phase found:** CodeRabbit review of PR #6, 2026-08-29.
**Repro:** with music on, turn Sound Effects off. The music stops and never
comes back, whatever you do to the music controls.
**Root cause:** `settingsChanged` called `audio.stopAll()` when the effects
gain reached zero, and `stopAll` also stopped the ambience and the music decks.
Because `musicState` and `lastMusicGain` were left untouched, the next refresh
saw no change and took the early-out, so nothing ever restarted it.
**Fix layer:** App. `AudioEngine.stopEffects()` stops the one-shot voices only;
`stopAll` is now composed from the three layer stops.
**Status:** FIXED 2026-08-30 (not runtime validated — TD-006).

---

## BUG-026 — A failed autosave raised a modal the player had not asked for
**Severity:** P3 · **Phase found:** CodeRabbit review of PR #6, 2026-08-29.
**Repro:** background the app with the disk full, come back. A modal "Save"
alert is waiting, attached to nothing the player did.
**Root cause:** `saveOnBackground` passes `announce: false` precisely so it
never interrupts, and the doc comment says a failure is "recorded but never
interrupts". The catch block set `lastSaveOutcome` regardless, and that is the
one piece of state `GameShell` raises an alert from.
**Fix layer:** App. The announced path keeps the alert; the quiet path records
`quietSaveFailure`, which Settings' Save section reports in place — quiet, but
not silent, which was the whole point of UI-012.
**Status:** FIXED 2026-08-30.

---

## BUG-027 — "Live flights" counted every aeroplane in the world
**Severity:** P2 (a headline metric that was simply wrong; it escaped notice
only because no screen rendered it) · **Phase found:** MASTER PROMPT 4, while
adding the network summary, 2026-08-30.
**Repro:** any save. `DashboardModel.liveFlightCount` reported 34 for a player
with nothing in the air.
**Root cause:** `liveFlightCount: flights.count`. Every other field on that
model is scoped to the player; this one was the raw size of the world's flight
dictionary — every airline's aeroplanes, in every phase, including `scheduled`
and `boarding`. So the number was neither live nor the player's.
**How it survived:** `dashboardModel()` is one long initialiser call. Each
argument is a short expression and `flights.count` reads perfectly plausibly in
a list of `fleet(of:).count` and `routes.count` — the mistake is only visible
if you notice that the two neighbours are scoped and this one is not. Nothing
displayed it, so no screen ever looked wrong.
**Fix layer:** Core. `airborneFlightCount(for:)` resolves ownership through the
route (a flight carries no airline of its own) and counts only `.enRoute`.
`dashboardModel` and `networkSummary` both call it, so they cannot drift.
**Status:** FIXED 2026-08-30. Covered by a test asserting the two agree, and
that both equal an independently spelled-out count.

---

## BUG-028 — A failed autosave warning followed the player into the next game
**Severity:** P3 · **Phase found:** MASTER PROMPT 4 §34 bug hunt, 2026-08-30.
**Repro:** let a background autosave fail, quit to the menu, start a different
airline, open Settings. The Save section warns that the last automatic save did
not complete — describing a game that is no longer loaded.
**Root cause:** `quietSaveFailure` was added in the previous phase (BUG-026) and
not added to `quitToMenu`, which clears every other piece of per-game state.
The same leak class as BUG-013, and introduced by the fix for the bug two
entries above it — which is the honest reason to keep both recorded.
**Fix layer:** App. `quitToMenu` clears it with the rest.
**Status:** FIXED 2026-08-30.

---

## BUG-029 — Finance's route links were inert on the Finance tab
**Severity:** P3 (a dead link, and only on one of the two paths to the same
screen) · **Phase found:** AE-028 §15, while adding the best/weakest route
panel, 2026-08-30.
**Repro:** open Finance from the tab bar and tap a route it names. Nothing
happens. Reach the same content from Home's "Last month" tile and the identical
link works.
**Root cause:** `FinanceContent` has no navigation stack of its own — by
design, so Home can push it as the explanation behind a stat tile. It therefore
inherits whatever destinations its host declares. Home's stack declares
`RouteID` and `AircraftID`; `FinanceView`, which wraps the same content for the
tab, declared neither. A `NavigationLink(value:)` with no matching
`navigationDestination` is silently inert — no warning, no crash, nothing to
see in a diff.
**Why it is worth recording:** the defect is invisible in the file that
contains the bug. `FinanceView` looks complete; the missing declaration is only
wrong in the light of a link added elsewhere. This is the failure mode of
value-based navigation, and the reason to check both hosts whenever a shared
content view gains a link.
**Fix layer:** App. `FinanceView` declares both destinations, matching
`NetworkView` and the Dashboard.
**Status:** FIXED 2026-08-30.

---

## BUG-030 — Route Detail's aircraft link was dead on two of its five entry paths
**Severity:** P3 · **Phase found:** AE-028, auditing every `NavigationLink(value:)`
against its host stack rather than waiting for a review bot, 2026-08-30.
**Repro:** open World events → tap an affected route → tap the assigned
aircraft. Nothing happens. Same from the airport browser: an airport → one of
its routes → the aircraft. The identical tap works when Route Detail is reached
from Network, Home, the map or Finance.
**Root cause:** the same class as BUG-029, which is why it is worth its own
entry. `RouteDetailView` links onward to its assigned aircraft with
`NavigationLink(value: aircraft.id)`. A value-based link resolves against
whatever `navigationDestination`s its *host stack* declares, and
`WorldEventsView` and `AirportDetailView` each declared `RouteID` only. Pushing
Route Detail therefore worked; the screen behind it was half-wired.
**The systemic part.** Three occurrences now (BUG-029, and these two). The
defect is never visible in the file that contains it: every one of these hosts
looks complete on its own, and only becomes wrong in the light of a link
declared two screens away. A `NavigationLink(value:)` with no matching
destination is silently inert — no warning, no crash, nothing in a diff, and
nothing a compile or `swiftc -parse` can see.

The check that actually finds them is mechanical: for every
`NavigationLink(value:)`, list the value's type, then confirm every stack that
can host that view declares it. Doing that across the app is what found these
two. It is a five-line grep and should be a CI script.
**Fix layer:** App. Both stacks now declare `AircraftID` alongside `RouteID`.
**Status:** FIXED 2026-08-30.

---

## BUG-031 — Derived caches were keyed on the tick, so a paused player's own command changed nothing on screen
**Severity:** P2 (a stale headline figure the player caused themselves) ·
**Phase found:** CodeRabbit review of PR #7, 2026-08-30. **Predates AE-028.**
**Repro:** pause the game. Buy an aircraft. The Fleet board still shows the old
count. Open a route: the Routes board header still shows the old one. Nothing
updates until the player unpauses and a tick lands.
**Root cause:** `GameController.invalidateCachesIfNeeded` opened with
`guard state.clock.tickCount != cachedTick else { return }`. That is the wrong
key. While paused, `GameSession.submit` takes the `engine.applyNow` branch,
which builds its context with `tick: SimDuration(minutes: 0)` and never touches
`state.clock.tickCount`; only `advance` increments it. So the command produced
a genuinely new `GameState` at an unchanged tick, the guard returned early, and
every tick-keyed cache kept serving pre-command values.
**Scope.** Five caches: `cachedMap`, `cachedRouteCards`, `cachedFleetCards`
(all three since UI-016) and the two summaries added in AE-028. The bug is
older than this phase; AE-028 only widened it.
**Why it survived:** the tick is an *almost* correct key. It is right for every
running-game path, which is nearly all of them, and the pause path is the one
case where state advances without the clock. A cache invalidated on "the
simulation moved" reads as obviously correct until you notice the player can
move the simulation without moving the clock.
**Fix layer:** App. `invalidateCaches()` clears unconditionally on every
published snapshot; the accessors ask only whether a value is present.
`cachedTick` is gone. This costs one recomputation per published snapshot,
which is what already happened on every tick while running — the cache's real
job is stopping repeated `body` evaluations between snapshots from each
rebuilding the map, and it still does that.
**Regression cover:** there is no app test target that runs on Linux, so the
Core *precondition* is pinned instead:
`SummaryModelTests.pausedCommandChangesStateAtTheSameTick` asserts that a
command applied while paused changes the state without advancing the tick.
Anything that caches on the tick alone is broken by that fact, and the test is
where it is written down.
**Status:** FIXED 2026-08-30.

---

## BUG-032 — Both assignment pickers offered moves Core would refuse
**Severity:** P1 (a dead-end in the game's central loop; no data loss).
**Found:** 2026-08-30, AE-029 §23 audit.
**Symptom:** the player picks an aircraft for a route from either direction,
and the command is rejected. From Aircraft Detail, routes the aeroplane cannot
reach were listed as targets; from Route Detail, aeroplanes that cannot reach
the route were listed as candidates.
**Root cause:** each screen re-derived eligibility. Both filtered on
"unassigned and active" and stopped. `AssignAircraftToRouteCommand.validate`
checks six things, and the two the UI missed — range and runway class — are
precisely the two a player cannot work out by looking at a row.
**Wrong in the other direction too.** Core permits assigning an aircraft that
is in a maintenance check. The `isActive` filter hid those, so a grounded
aeroplane could not be given its next job while it sat in the hangar. One
picker, simultaneously too permissive and too restrictive.
**And a third:** Fleet's picker listed only routes with *no* aircraft
(`assignedAircraft.isEmpty`), although `apply` appends to `assignedAircraft`
without complaint. Adding a second aircraft to a busy route was unreachable
from the screen that owns the aircraft.
**Why it survived:** nothing connected the two layers. The UI's filter was a
plausible-looking subset of the real rules, it compiled, it ran, and the only
symptom was a refusal that looked like the player's mistake.
**Fix layer:** Core. `AssignmentEligibility` puts the rules beside the
validator they mirror; both screens render it and neither decides anything.
Ineligible pairings are now listed with their reason rather than omitted —
an aeroplane silently missing from a picker is indistinguishable from a bug.
**Regression cover:** `AssignmentEligibilityTests.blockersAgreeWithTheValidator`
drives every aircraft against every route in a real world and asserts the model
and the validator agree on each, with a guard that the fixture actually
contains refusals. Sabotage-checked: disabling the range branch fails it on
four pairings.
**Status:** FIXED 2026-08-30.

---

## BUG-033 — Three refusal mappings could never fire
**Severity:** P2 (player-facing copy that no player could reach).
**Found:** 2026-08-30, by diffing every code Core emits against every code the
app maps.
**Symptom:** two of the most confusing refusals in the fleet flow — "this
airport cannot take your aircraft" and "wait for your flights to land" —
appeared under the generic "Not possible" title with no suggestion, despite
tailored copy for both existing in `Rejections.swift`.
**Root cause:** the strings did not match. The app mapped
`route.hasAirborneFlights`; Core emits `route.flightsAirborne`. The app mapped
`route.runway` and `route.runwayTooShort`; Core emits `route.runwayTooSmall`.
`progression.lockedCategory` — the refusal a player meets whenever they try to
buy an aircraft their era does not allow, and so the most common refusal in the
market — had no mapping at all.
**Why it survived:** this fails silently by construction. A `switch` case on a
string that nothing produces compiles cleanly and is simply never taken. There
is no warning, no crash, and the fallback is plausible enough that a reader
would not know they were seeing it.
**Fix layer:** App for the strings; Core tests for the guard.
**Regression cover:** `RejectionCodeContractTests` provokes each refusal from a
real command and pins its literal code, and names the three wrong strings
explicitly so that reintroducing one meets a failing test rather than a no-op.
The app's half cannot be tested here — that target does not build on Linux —
which is the residual risk, recorded as part of TD-016.
**Status:** FIXED 2026-08-30.

---

## BUG-034 — An aircraft in a maintenance check was described as idle
**Severity:** P3 (misleading copy).
**Found:** 2026-08-30, while fixing BUG-032.
**Symptom:** Aircraft Detail told the player an aeroplane undergoing a
maintenance check was "Idle at STV. It earns nothing here" — which reads as
the player's oversight and as something they could fix by finding it a route.
**Root cause:** the branch tested `assignedRoute == nil` and `isOnOrder`, and
treated everything else as idle. `inMaintenance` fell through to the idle copy.
**Fix layer:** App. The check is named, and the route picker still appears
beneath it, because the aeroplane's *next* route can be chosen while it sits
in the hangar — which is what Core allows and what BUG-032's fix exposed.
**Status:** FIXED 2026-08-30.

---

## BUG-035 — A third of the Network tab was empty, and the picker floated in it
**Severity:** P1 (the first screen a new player reaches, and the tab's primary
control sat 40% of the way down under nothing).
**Found:** 2026-08-30, AE-031 — **by looking at a screenshot**, which is the
first time this project has been able to do that.
**Symptom:** on the Network tab with no routes and no aircraft — the state
every new game starts in — roughly the top third of the screen was blank, the
Routes/Fleet segmented picker sat mid-screen, and another large gap ran from
the empty-state card down to the tab bar.
**Root cause:** a SwiftUI default doing exactly what it documents.
`EmptyStateView` is a compact card, and a view smaller than its parent is
centred in it. It was the only child of a `Group` filling the screen, so it
centred vertically. `safeAreaInset(edge: .top)` then placed the section picker
against the **content's** top edge — which by then was halfway down the
screen. One default produced both gaps, which is why they looked like two
separate problems.
**Why nothing caught it:** it compiles, it parses, no test covers layout, and
it appears *only* in the empty state — a list-bearing screen fills its parent
and has nowhere to float to. So it was invisible on every screen anyone would
think to check, and present on the one a new player meets first.
**Why it took four phases:** nothing in this project had ever rendered the app.
The UI test target and the screenshot pipeline added earlier in AE-031 are what
made it findable; it was found within minutes of the first image.
**Fix layer:** App. `aeEmptyStatePlacement()` — top alignment inside the
available space — applied to the Routes and Fleet empty states.
**Regression cover:** none yet, and worth being honest about. XCUITest can
assert an element's frame, so "the picker sits in the top quarter of the
screen" is expressible; it is not written. Recorded as TD-019.
**Status:** FIXED 2026-08-30, **visually confirmed**. The re-run screenshot
shows the picker directly under the navigation title with the card immediately
below it. Both gaps closed with the one change, which corroborates the
single-cause diagnosis — had they been two problems, the fix would have closed
one.

---

## BUG-036 — map chrome is illegible in light appearance

**Severity:** P1. It hits the one card that tells a new player what the map is
showing them, in the appearance the simulator defaults to.
**Found:** 2026-08-30, AE-032 — by looking at a map screenshot.
**Symptom:** the "Your airline begins here" card over the map rendered as
white text on a pale, near-white panel. The body line — *"The dashed lines are
the strongest markets from your home airport"* — was effectively invisible.
The same applies to every glass element over the map: the time controls, the
overlay picker, the zoom cluster.
**Root cause:** an agreement between two correct decisions that were never
checked against each other. The canvas is fixed near-black in *both*
appearances by design (docs/MAP_ARCHITECTURE.md §2), so its chrome is written
with hardcoded `.white` text. But that chrome sits on `aeGlass` —
`glassEffect` on iOS 26, `.ultraThinMaterial` before it — and both resolve
against the **system** appearance. In light mode the panel goes pale and the
text stays white.
**Why nothing caught it:** the map's own palette is a constant, so it looks
identical in every screenshot; the chrome is not, and until AE-032 no
screenshot of the map existed at all. It compiles, and no test can read
contrast.
**Fix layer:** App. `.environment(\.colorScheme, .dark)` on the map's
`ZStack`, so every material and semantic colour inside resolves against the
surface it is actually drawn on. One statement at the level where the fact is
true, rather than restyling each piece of chrome. Sheets and pushed
destinations are attached outside that `ZStack` and keep the system
appearance, which is correct — they are ordinary surfaces, not map chrome.
**Regression cover:** partial and worth stating plainly. XCUITest cannot read
contrast, so no assertion covers this. What exists is
`testLightAppearanceMapForComparison`, which now proves the app is genuinely
in light appearance and captures the map — turning this from invisible into
observable at every run.
**Status:** FIXED — **visually confirmed.** Run 59's `KEY-61-light-map`
(main, c387dde) was decoded and looked at in AE-032: the shell is proven
light by the appearance guard, and every piece of map chrome — the time
controls, overlay picker, zoom cluster and the "Your airline begins here"
card — renders dark glass with legible white text.

## BUG-037 — Core rejection messages print raw cents

**Severity:** P2. Cosmetic, but on the exact line that explains to a player
why they cannot afford something.
**Found:** 2026-08-30, AE-032 — in run 59's `MARKET-DID-NOT-CLOSE`
screenshot: a blocked market row captioned **"Need 110000000 for this
offer"**.
**Root cause:** five rejection messages in Core interpolated
`money.cents / 100` — a raw Int64 — because Core had no money formatting at
all. The app then surfaces `rejection.message` verbatim, both in the market
caption (`FleetView.purchase`) and in the rejection alert.
**Why nothing caught it:** `RejectionCodeContractTests` pins codes, not
message text; the copy in `Rejections.present` wraps the message without
reading it; and the message only renders when a command is *blocked*, a state
no screenshot had ever shown.
**Fix layer:** Core. `Money.compact` — `$110.0M` / `$790k` / `$1,234`,
thresholds mirroring the app's `Format.money` — used by all five sites
(FleetCommands ×3, FinanceCommands, ProgressionCommands).
**Regression cover:** `MoneyFormattingTests` pins the format and drives the
three blocked market commands, asserting no rejection message carries a
digit-run long enough to be an unformatted balance.
**Status:** FIXED — **visually confirmed.** Run 61's market frame shows the
blocked Buy-new row captioned "Need $110.0M for this aircraft".

## BUG-038 — the route-opening journey drove controls that were not there

**Severity:** P1 for the evidence pipeline; P2 for the product. The app
worked; the proof did not, and one real UX flaw hid underneath.
**Found:** 2026-08-30, AE-032 — run 59's checkpoints 05 and 06 are
pixel-identical, and both journey tests failed.
**Symptom:** `testAcquireAircraftThenOpenARoute` tapped
`app.cells.firstMatch` on the route sheet — which is the **From picker**, not
a destination — selecting nothing; then reached for `app.buttons["Open"]`,
which has never existed (the real label is "Open this route"). Both misses
were silent; only the final "board still empty" assertion fired. The same
`cells.firstMatch` pattern on the routes and fleet boards taps the *summary
row*, which navigates nowhere.
**The product flaw underneath:** the "Open this route" row sat below all ~40
destination candidates, so a player who picks the top-ranked suggestion must
scroll past every destination they just rejected to commit.
**Fix layer:** both. App: the commit row rides a bottom `safeAreaInset` on
the sheet, always visible once a destination is chosen; stable identifiers
`ae-route-destination`, `ae-route-open`, `ae-route-row`, `ae-fleet-row`.
Tests: `openARoute()` selects by identifier and treats the commit bar's
appearance as proof the selection took; a disabled commit button fails with
Core's printed reason in the screenshot.
**Status:** FIXED — **asserted and observed.** Run 61's
`testDetailScreensAndSettingsRender` drove the new path end to end: a
destination selected by identifier, the bottom commit bar tapped, and the
route photographed on its own detail screen (STV – LNW, "No aircraft
assigned, so this route is not flying" — correct for the state).

## BUG-039 — the zoom test manufactured its own evidence

**Severity:** P1 for the evidence pipeline. The audit recorded "world,
regional and local zoom observed; pinch asserted" — none of which was true.
**Found:** 2026-08-30, AE-032 — by hashing run 59's screenshots:
`71-map-regional-zoom` and `72-map-local-zoom` are byte-identical,
`70-map-world-zoom` differs from them by 0.01% of pixels, and
`73-map-zoomed-back-out` is **the Finance screen** — the wide synthetic
pinch-out planted a finger on the tab bar and switched tabs. The test passed
throughout, because it asserted only that the canvas existed.
**Root cause:** two agreements no assertion checked. The map opens framed on
the home network, near the zoom clamp, so pinching *in* moves nothing; and
an XCUITest pinch on a full-screen canvas spans the floating tab bar.
**Fix layer:** both. App: the canvas publishes `zoom N.Nx` in its
accessibility value, so a camera move is now a checkable fact. Test: buttons
drive the camera out to the world and back in with hard assertions at each
level; double tap is asserted to zoom; the pinch is attempted and, if the
camera does not move, recorded as an explicit `XCTSkip` — NOT VERIFIED —
because a broken recognizer and an unsynthesized gesture are
indistinguishable from CI. A person with a device settles the pinch.
**Status:** FIXED — **asserted and observed.** Run 61's rebuilt test passed
with every level a genuinely different frame: world (six zoom-outs), regional
and local (buttons), double-tap, and the synthetic pinch itself moved the
camera this time, so pinch is asserted on the simulator. On *hardware* a real
two-finger pinch remains untested, as does everything else — that is
docs/APPLE_VALIDATION.md's list, not this bug's.

## BUG-040 — the game can launch permanently frozen

**Severity:** P0. The core loop — time passing — silently never starts, on a
race the player cannot see or influence.
**Found:** 2026-08-30, AE-032 — by run 64's flight journey, the first time
any automation reached the state the game is *for*: an aircraft assigned to
a route with the clock running. Frame `81-flight-in-progress` shows 16×
selected and the clock still at day one, 00:00, after two real minutes.
**Root cause:** two stacked halves, and the second is the one that matters.
`setPumping` — the loop that feeds elapsed real time to the simulation — was
called only from `.onChange(of: scenePhase)`, which (half one) does not fire
for the value already present. But even when it fires (half two, proven by
run 65 still freezing after `initial: true`), it fires at launch — on the
menu — where `session` is nil and the guard returns without arming anything.
Nothing called `setPumping` again when a session was finally created, so
**founding or loading a game never started the clock at all**; the game only
ever ran for a player who backgrounded the app and came back.
**Why nothing caught it:** every earlier journey ended before running the
clock; Core's 414 tests drive time directly and never meet SwiftUI's scene
machinery; and a frozen game *renders perfectly* — every screen this phase
photographed before run 64 was of a world at day one, 00:00, and looked
right.
**Fix layer:** App, both halves: `.onChange(of: scenePhase, initial: true)`
(iOS 17+) so the current phase is delivered on attach, and — the load-bearing
line — `setPumping(true)` at the end of `startNewGame` and `loadGame`, where
a session finally exists to pump.
**Regression cover:** `testAnAircraftFliesItsRouteOnTheMap` is the guard —
it polls the map's own airborne count at 16× and fails if nothing flies in
five game days, which is exactly how this was caught.
**Status:** FIXED — **asserted and observed.** Run 67's
`testTheClockActuallyRuns` passed, and its frame shows Home at
**2030-01-03** with 16× selected, the fuel price moved and the economy
trending — the first photograph of a running world in this project's
history. The flight journey (an aircraft observed in the air) remains
gated on the runner's flaky market-sheet taps, not on this bug.

## BUG-041 — the lease tap misses by exactly one row on a still list

**Severity:** P2, test infrastructure only. The app leases correctly — the
same run that failed this proved it twice through the same helper.
**Found:** 2026-08-31, AE-034 — run 85, `testAcquireAircraftThenOpenARoute`,
"No lease completed after four attempts", 15/16 UI tests otherwise green.
**Symptom:** the coordinate tap aimed at the market row's Lease action opens
the **"Buy used (8y)?"** dialog — the row one pitch (~58 pt) above — on
attempts 1 *and* 3 of the same test, then attempt 4's tap lands on nothing.
**Root cause (photographed, not guessed):** the attempt frames show the list
perfectly still, ruling out the scroll-momentum explanation that
`waitUntilStill` (added after run 78's identical miss) was built on. A
stationary, *repeatable* one-row miss means XCUITest's resolved frame for
the row is stale by exactly one reported row pitch — the accessibility
snapshot lags the expanded card's layout, and re-reading it returns the same
stale answer, which is why polling for stillness passes and the tap still
misses.
**Why the earlier fix was incomplete:** `waitUntilStill` detects *changing*
answers. It cannot detect a consistently wrong one.
**Fix layer:** UITests. The wrong dialog identifies the miss precisely: if
aiming at the reported Lease centre opened Buy-used, the true Lease position
is one reported row pitch lower (the *difference* between two rows from the
same stale snapshot is right even when both absolutes are wrong). The helper
now measures `lease.midY − buyUsed.midY` when the wrong dialog appears and
applies it as an aim correction on later attempts.
**Regression cover:** the helper's own retry loop plus the LEASE-ATTEMPT
frame captures; three tests exercise it every run.
**Status:** SECOND FIX AUTHORED. Run 86 disproved half the first diagnosis:
all three lease-dependent tests failed, and the attempt frames showed a
second miss mode — the tap landing on *nothing* (the inert caption between
rows), which the dialog-measured correction can never see — repeated
identically four times, because when the row already sits in the middle
band nothing changes between attempts and the stale snapshot answers every
retry the same way. The helper now (a) prefers `lease.tap()` when the
system reports the row hittable — the hit point is resolved at event time,
(b) applies a dialog-measured correction for exactly one following tap,
and (c) jiggles the list after any no-dialog miss so each retry sees fresh
geometry. Run 86 also re-proved the app path is healthy (414/414 Core, map
baseline green with numbers matching run 85). Not claimed fixed until a
run shows the lease tests green.
**Verified:** run 87 (commit ede33c8) — **all 16 UI tests green**, all
three lease-dependent journeys included. FIXED.

## BUG-042 — A rival's idle aircraft always went onto its one full route

**Severity:** P1 (world). Every AI airline was a single-route airline for
the life of a game, so the "competitor expansion" the design promises never
happened anywhere.
**Found:** 2026-09-01, AE-037 — by `ae-rival-probe`, the first tool to diff
rival state day by day. Five years from Stockholm: every rival opened
exactly one route in its first week and never another; one carried
sixteen aircraft on a pair the scheduler could use ten on; three of five
collapsed under lease bills for aircraft that flew nothing.
**Root cause:** `CompetitorAISystem.employ` preferred thickening a "hot"
route (lifetime load > 0.82) over opening a market, with no check that the
route could use another airframe. A trunk route pinned at full load is hot
forever, and once `manageRoutes` had pushed it to the 20-rotation cap, every
new aircraft was assigned to it and sat on the ground.
**Fix layer:** Core, one guard. `routeNeedsAnotherAircraft` asks the
scheduler's own capacity arithmetic (`FlightSchedulingSystem.
roundTripsPerAircraftPerDay`, extracted rather than copied) whether the
assigned aircraft already cover the frequency target; a covered route no
longer absorbs aircraft, so the idle airframe opens the best new market.
**Regression cover:** `CompetitionTests.rivalOpensASecondMarket` — three of
five rivals fly two or more routes within 120 days, and no AI route carries
more than one aircraft beyond what it can use.
**Status:** FIXED, MEASURED (probe: rivals reach five routes each; the
Stockholm cast's collapses fall from two in two years to zero in the
fight campaign, one in the plain one).

## BUG-043 — The competitor cast was founded where the player would never go

**Severity:** P1 (world). Combined with BUG-042 it meant a European start
never met a rival at all: MEASURED zero contested player markets in five
years from Stockholm, Barcelona *and* Singapore.
**Found:** 2026-09-01, AE-037, same probe.
**Root cause:** `WorldSetup.createCompetitors` took the world's most
populous large airports outright — Tokyo, Jakarta, Delhi, Shanghai, Seoul —
and an AI expands only from where its aircraft sit, among its sixteen
nearest airports. No rival ever had a reason to be within 5,000 km of
Stockholm. The Barcelona curated start's blurb promises "real competition";
the Singapore one says "so do your rivals". Neither was true.
**Fix layer:** Core, world population. At least half the cast (⌈n/2⌉) is
founded at the busiest large airports of the player's own region, the rest
at the busiest anywhere. From Stockholm the nearby rivals are Istanbul,
London and Paris — exactly the markets the guided first route and the Next
Moves ranking send the player to.
**Regression cover:** `CompetitionTests.castIsFoundedNearThePlayer`.
**Status:** FIXED, MEASURED. Rival routes now touch the player's airports
from day 3 (London–Paris while the player flies Stockholm–London). Note what
this does *not* change: rivals still do not enter a pair the player already
flies unless it is one of the world's largest — the AI halves a market's
value per incumbent and there are always open markets left. Competition on
the player's own pairs is player-initiated (the fight in
`RivalPressureCampaignTests`), which the design lists as intended
("fight, flank or cede"); recorded as TD-026, not a bug.

## BUG-044 — Everything a rival did to the player's market was invisible

**Severity:** P0 by the AE-037 ranking: the player suffered the consequence
(a third of a market at full load, a monthly loss) with no way to know why.
**Found:** 2026-09-01, AE-037 — measured on the London–Paris fight. Of the
rivals' responses over four months (a fare cut, thirty-two frequency
increases, one retreat), the feed carried **none**: `SetRoutePrice` and
`SetRouteFrequency` emit no event at all; a rival's `routeOpened` names no
airline and is filtered as its private business (BUG-004's rule, correct
for the events it had); `routeClosed` names a route that no longer exists
and so can never be attributed (BUG-007). The route screen listed the
rivals' fares and frequencies as state, but said nothing about the split,
the standing or the cause.
**Fix layer:** Core + App.
- Core: `world.marketMoves`, a bounded record of who entered and left which
  pair (written by the open/close commands and the collapse path; save v12
  with a migration), plus two events, `marketEntered` / `marketLeft`, which
  the feed admits exactly when the pair is one the player flies.
- Core: `MarketCompetition` (per route: rivals with share, standing against
  an even split, the dominant attractiveness term as the *why*) and
  `CompetitionSummary` (contested/leading/trailing counts, the rival that
  touches the player most, recent moves, and one prioritised headline).
- App: the route screen's competition section (standing sentence, share
  bar, per-rival share, the named response); a Home card that renders only
  the headline and nothing in a quiet world; the World hub's live line and
  badge; the Competitors screen re-ordered by pressure with contested
  routes as links; the map's Rivals overlay hint counting contested routes
  rather than shared airports.
**Regression cover:** `CompetitionTests` (11), `RivalPressureCampaignTests`
(the seed-2039 fight, day by day), and the campaign UI journey's COMP
checkpoints.
**Status:** FIXED — TESTED in Core, **OBSERVED** on every screen (runs
112–116: the route on entry and a week on, Home, the World hub, the
Competitors screen, the retreat and the late game — see
docs/RIVAL_PRESSURE_AUDIT.md §8 for what each frame showed).

## BUG-045 — The guided route sheet could open empty

**Severity:** P1. Home's strongest guidance surface — tap a suggested
market, get its route sheet — sometimes handed the player a blank sheet
instead: From their home, nothing picked, the whole ranked list.
**Found:** 2026-09-02, AE-037 — run 116's `FEB-ROUTE-SHEET-STUCK-1` frame,
read against `KEY-32`: Home on 1 Feb offered ARN → CDG and ARN → IST, the
journey tapped the first, and the sheet that came up had no destination.
The route it eventually opened was Stockholm–Tokyo, 8,168 km, for a fleet
of 5,700 km narrowbodies; it sat bare through March. Run 112's
`FEB-ROUTE-SHEET-STUCK-1` was the same defect, then read as harness
flakiness.
**Root cause:** `DashboardView` presented the sheet with
`.sheet(isPresented:)` driven by a Bool set in the same statement as a
separate optional `guidedRoute`, and the sheet's body did
`if let guidedRoute … else OpenRouteSheet()`. SwiftUI can evaluate the
sheet content with the optional still nil on the presentation that flips
the Bool, and the else branch renders a plain sheet. A deliberate fallback
made the race invisible.
**Why nothing caught it:** the plain sheet is a legitimate screen, so
nothing on it was wrong; the journey photographed it as "stuck" and moved
on; Core never sees SwiftUI presentation.
**Fix layer:** App. `.sheet(item:)` on the optional itself, with a private
`Identifiable` wrapper — a sheet that cannot present without its value.
The else branch is gone.
**Regression cover:** the campaign journey's February (two suggestion
taps, `FEB-*` frames on any miss) and its "no bare routes at the end of
February" assertion, which is what failed in run 116.
`NextMovesServabilityTests` pins the other half of the diagnosis: the
card's ranking from Stockholm on 1 Feb is all within the fleet's reach,
so the unflyable route was the sheet's doing, not the card's.
**Status:** FIXED — **OBSERVED** in run 117 (`KEY-32b`: both suggestions
became the routes the card named, ARN–CDG earning $478k by 9 Feb, no
Tokyo, no `FEB-*` frame; 18 of 18 journeys green).

## BUG-046 — The route's frequency advice said a rotation needed an aircraft it already had

**Severity:** P2. Misleading competitive advice on the one lever the
measurement says works.
**Found:** 2026-09-02, AE-038 — `RivalsComeToYouTests` on seed 2030 from
New York: with SwiftJet at three rotations against the player's two on
JFK–ORD, the route screen's response line read *"Answer with frequency:
another rotation needs another aircraft on this route."* The Linux twin
then set the frequency to three on the one leased narrowbody already
there, the scheduler flew it, and the route's profit rose from about
$1.3M to about $1.9M a month for the rest of the year (docs/RIVALS_THAT_COME_TO_YOU_AUDIT.md §4).
**Root cause:** `Vocab.competitiveResponse` had one sentence for the
schedule edge and no way to know whether the assigned aircraft could fly
another rotation; `MarketCompetition` carried the standing, the share and
the why, but not the capacity fact the advice turns on.
**Why nothing caught it:** AE-037's frames were of London–Paris where
the incumbents flew twenty rotations and the player's response genuinely
needed more aircraft; the sentence was true there.
**Fix layer:** Core + App. `MarketCompetition.spareRotationsToday` — the
scheduler's own per-aircraft capacity times aircraft on the route, minus
the frequency — and the advice reads it: *"your aircraft on this route can
fly one more rotation today"* when it can, the old sentence when it cannot.
**Regression cover:** `RivalsComeToYouTests` asserts a spare rotation on
the pair a month after entry; `CompetitionTests` covers the model.
**Status:** FIXED — TESTED, **OBSERVED** (run 119, KEY-R4: *"your
aircraft on this route can fly one more rotation today"*, and KEY-R7 after
the third rotation: *"another rotation needs another aircraft"*).

## BUG-047 — A rival's move named the pair the rival's way round

**Severity:** P3. Wording.
**Found:** 2026-09-02, AE-038 — run 119's KEY-R2: *"SwiftJet entered your
ORD–JFK market yesterday."* on Home, above a route the player opened as
JFK–ORD and sees as JFK–ORD everywhere else.
**Root cause:** `world.marketMoves` records the rival's route orientation;
`competitionSummary` handed it through unchanged.
**Fix layer:** Core. On the player's own pair the move takes the
orientation of the player's route.
**Regression cover:** `RivalsComeToYouTests` — the headline's pair equals
the player's first route.
**Status:** FIXED — TESTED, **OBSERVED** (run 120, KEY-R2: *"SwiftJet
entered your JFK–ORD market yesterday."*).

## BUG-048 — A month-old entry still led Home over a live fight

**Severity:** P3. Priority, not correctness: the sentence was true.
**Found:** 2026-09-02, AE-038 — run 119's KEY-R4-home-a-month-on:
*"SwiftJet entered your ORD–JFK market 30 days ago."* while the route
screen said "An even fight — 49% … mostly because they fly more often."
**Root cause:** the headline let the most recent move on a player pair lead
for the whole thirty-day window the Competitors screen keeps.
**Fix layer:** Core. `CompetitionSummary.headlineMoveWindowDays = 14`: a
move leads for a fortnight, then the standing of the fight takes over.
**Regression cover:** `RivalsComeToYouTests` — the headline a month after
entry is `fighting`.
**Status:** FIXED — TESTED, **OBSERVED** (run 120, KEY-R4: *"One of your
routes is contested — an even fight so far."* a month after the entry).

## BUG-049 — The fare advice named one answer where the measurement found two

**Severity:** P2. Misleading competitive advice, on the lever the player is
about to pull.
**Found:** 2026-09-02, AE-039 — `MunichHorizonTests`: a month after
PacificBlue came to Munich–Istanbul at $142 against the player's $167 the
route screen read *"Answer with the fare below, or accept a smaller share
at a better price."* The twin then measured both answers over the
following months: a tenth off the fare took the share from 35% to 40% and
the route's month from about $2.0M to $1.7M; one more rotation on the
aircraft already there took it to 38% and $2.2M. The advice had named the
answer that costs money and left out the one that makes it.
**Root cause:** `Vocab.competitiveResponse` had one sentence for the fare
edge whatever the capacity fact; `MarketCompetition.spareRotationsToday`
(BUG-046) was only consulted for the schedule edge.
**Fix layer:** App. With a rotation to spare: *"They are cheaper. Another
rotation keeps the money; matching the fare keeps the share."* Without
one, the old sentence.
**Regression cover:** `MunichHorizonTests` measures both responses; the
Munich journey photographs the line (HORIZON-KEY-05).
**Status:** FIXED — TESTED, OBSERVED (run 121, KEY-HZ5-response-line).

## BUG-050 — A rival that was there first "entered your market"

**Severity:** P3. A false sentence on the Competitors screen, and for a
fortnight after the player opens a pair it can lead Home.
**Found:** 2026-09-02, AE-039 — run 121's KEY-46 (Competitors, 9 Feb):
*"Aurora Atlantic entered your LHR–BER market 21 days ago."* Aurora
opened London–Berlin on 19 January; the player opened it on 1 February,
into a market the route sheet had already marked *"1 airline already
flies it"*. The player entered Aurora's market, not the other way round.
**Root cause:** `WorldState.competitionSummary` classified a rival's move
as `.onPlayerMarket` when the pair is one of the player's routes *now*;
it never asked whether the player was flying the pair when the move
happened. The world's move record carries the player's own entries and
exits, so the question was answerable.
**Fix layer:** Core read model. A rival's move on a pair the player was
not yet flying is `RivalMove.Relevance.beforePlayerJoined`; it does not
lead Home, and the Competitors screen reads *"Aurora Atlantic was already
flying LHR–BER when you opened it (21 days ago)."* A rival's exit after
the player joined stays a move on the player's market. Save format
unchanged.
**Regression cover:** `CompetitionTests.aRivalThereFirstIsNotAnEntryIntoYourMarket`.
**Status:** FIXED — TESTED, OBSERVED (run 122, KEY-46: *"Aurora Atlantic
was already flying LHR–BER when you opened it (21 days ago)."*).

## Finding — New York's arrival was an artefact of ranking by passengers

Not a bug entry of its own; recorded so the AE-038 evidence reads right.
SwiftJet's entry into New York–Chicago on day 3 (AE-038, OBSERVED in runs
119–120) happened because the AI ranked candidate markets by passengers
alone. The ledger says the regional rival's 70-seat turboprops lost $277k
a month on that pair at 100% load (and $953k on Chicago–Toronto). Once
markets are ranked by what an airframe day sells (AE-039), SwiftJet does
not open it, and no other rival can see New York–Chicago as its best
market. The world-initiated twin and journey moved to Munich
(`MunichHorizonTests`, `HorizonArrivalUITests`); the New York ones were
removed. The founding helper's any-home picker stays.

## BUG-051 — A movement cost the same whatever landed

**Severity:** P1. An entire airline archetype could not function, and a
player flying the same aircraft paid the same.
**Found:** 2026-09-02, AE-040 — `ae-fee-baseline`: on every pair in a
forty-route battery the 68-seat turboprop's airport fees were 1.7–1.9×
the 180-seat narrowbody's as a share of revenue (LHR–CDG 157% vs 85%,
JFK–ORD 75% vs 40%), and no turboprop route in the world paid for its
lease; the regional archetype had 40 profitable candidates out of 542 at
28 of 88 homes (docs/FEE_ECONOMY_BASELINE.md §6, docs/REGIONAL_ARCHETYPE_AUDIT.md
§2). Previously recorded as TD-029 from the symptoms (SwiftJet's
JFK–ORD −$277k a month, KEY-48's "airport fees take 96% of the
revenue").
**Root cause:** `AirportSpec.movementFee` was charged per arrival for
both ends with no term for the aircraft: a 68-seat cabin and a 422-seat
one paid the same two movements. Real landing charges follow aircraft
weight; the game's passenger fee already followed passengers, the
movement fee followed nothing. CASE B, wrong scale.
**Fix layer:** Core. `AirportSpec.movementFee(for:ops:)` — the quoted fee
in proportion to seats over `OpsTuning.movementFeeReferenceSeats` (180,
new tuning constant), integer cents — used by `FlightOpsSystem.arrive`
and the AI's estimator. The 180-seat narrowbody pays exactly what it
paid; the anchor economy does not move. No save-format change.
**Regression cover:** `FeeEconomyTests` (scale, once-per-arrival posting,
the category, the two types on one pair, long haul not subsidised, the
archetype's markets from Paris and in the standard cast).
**Status:** FIXED — AUTHORED; TESTED and MEASURED pending this phase's
batteries (docs/AE040_FEE_ECONOMY_REPORT.md).

## BUG-052 — The AI's profit estimate charged maintenance ten times what the ledger books

**Severity:** P2 (AI only; the withheld profit ranking's view of the
world).
**Found:** 2026-09-02, AE-040 — `ae-fee-baseline --months 12` against
`airframeDayValue(basis: .profit)` over forty routes: fuel, fees and crew
within 4–8% (the scheduled rotations that do not fly), service and
revenue exact, maintenance 9.8× (docs/FEE_ECONOMY_ESTIMATOR_AUDIT.md).
**Root cause:** the estimator charged `maintenancePerFlightHour` for every
block hour; `FleetSystem` charges a 60-hour check each time condition
falls by 0.25, which at real utilisation is one check per 500–650 flight
hours. Two definitions of the same cost (CASE D).
**Fix layer:** Core AI. `FleetEconomics.expectedMaintenancePerDay` — the
fleet system's constants integrated: check cost × (daily decay + wear ×
hours flown) / (1 − threshold) — replaces the hourly line in the
estimator. The ledger is unchanged.
**Regression cover:** `FeeEconomyTests.expectedMaintenanceMatchesTheLedger`
(two years, within one check), `estimateMatchesTheLedgerOnActualPassengers`.
**Status:** FIXED — AUTHORED; TESTED pending.

## BUG-053 — An airframe the AI could not place froze its pricing for good

**Severity:** P2. A rival with an idle aircraft and nowhere to put it
stopped answering undercuts, pushing frequency and trimming losers —
all of route management — until the aircraft found a market.
**Found:** 2026-09-02, AE-040 — the full Core suite after the fee fix:
`CompetitorAITests.aiRespondsToUndercutting` failed because its target,
SwiftJet on Tokyo–Osaka, held its fare at $71.72 through three decision
cycles of a 40% undercut. Diagnostic: the healthier archetype had bought
a fourth turboprop that could reach nothing in its region it did not
already fly, so every decision slot found an idle airframe, tried to
employ it, and returned.
**Root cause:** `CompetitorAISystem.decide` returned after *attempting*
to employ an idle aircraft, whether or not the attempt placed it. Latent
since Phase 10; reached only once an archetype could afford an aircraft
with nowhere to go.
**Fix layer:** Core AI. `employ` reports whether it placed the airframe;
a slot that placed one is spent as before, a slot that could not goes on
to route management and growth.
**Regression cover:** `aiRespondsToUndercutting` (the failing case), the
AI suites and campaign twins re-run green (27 tests), the full suite and
the scans re-run after the change.
**Status:** FIXED — TESTED.

---

## BUG-054 — A rival bought an airframe on a six-month runway, then retrenched a week later

**Severity:** P2. In 143 of 150 two-year campaigns on the shipped
ranking the conservative archetype opened its third route, flew it full
for three weeks, closed it, and sold the airframe it had bought the week
before — an airline that looks, from the outside, like it cannot make
up its mind, and pays the used-market spread for the privilege.
**Found:** 2026-09-03, AE-041 — the scan's new opening classifier
(`rival openings … CLOSED BEFORE A FULL MONTH 143`) and
`ae-rival-scan 730 2039 ARN --follow "Crown Meridian"`
(docs/AE041_ECONOMIC_CREDIBILITY.md §3).
**Repro (MEASURED, seed 2039, Stockholm cast):** day 58 Crown Meridian
opens Tokyo–Beijing with its fifth airframe (cash $23.0M, runway 14.8
months on the February statement). Day 72, its decision slot: runway
6.10 months ≥ the archetype's 6.0, so it buys a sixth AV90 for $19.9M
and is left with $4.3M — 1.09 months. Day 79, next slot: runway 1.30 <
1.5, retrench: the "worst loss-maker" by last closed month is
Tokyo–Beijing, whose closed month is two days of February (−$29k, no
revenue) while the route is flying 74 flights at 95% load and +$734k in
the month under way; the route is closed and the week-old airframe sold.
**Root cause:** two rules in `CompetitorAISystem`. The growth step
tested the runway *before* the outlay and nothing after it, so an
archetype whose airframe costs five months of its outgoings always
landed at the retrench line; and `retrench` ranked routes by
`economicsLastMonth` whether or not that month had been flown.
**Fix layer:** Core AI, the decision loop only. `acquireAircraft` takes
a cash floor — the archetype's own expansion runway in months of the
latest statement's costs — and a signing or purchase that would leave
less waits (a loan, where the archetype tolerates debt, is sized to hold
the floor); `retrench` chooses among routes with a closed month of
revenue. A floor at the retrench line alone was measured first and left
one buy-and-sell a campaign (the next statement's costs pulled the
runway back under the line); the archetype's own threshold left none.
**Regression cover:** `RivalCredibilityTests.aRivalDoesNotBuyAnAirframeAndRetrenchAWeekLater`
— seed 2039, 150 days: no rival route with a real schedule closes, no
rival airframe goes within a month of arriving, Tokyo–Beijing is still
flown. The AI, horizon, Munich and campaign suites re-run green.
**Measured after (25 campaigns, seeds 2030–2034 × five starts):**
early closures 143 per 150 → 0 of 25; airframes disposed of within
thirty days 25 → 0; world-initiated entries unchanged (Munich day 61 in
5 of 5, Singapore days 509–537 in 5 of 5). Full 150-campaign figures:
docs/AE041_PROFIT_VS_REVENUE_REPORT.md §7.
**Status:** FIXED — TESTED.

---

## BUG-055 — The player's Next Moves card ranks markets by passengers, and from New York it recommends two routes that cannot pay for an aircraft

**Severity:** P1 (a player who follows the game's guidance from a
curated start collapses). **Found:** 2026-09-03, AE-041 — the scan's
`--player` narration, added because every New York campaign ended with
zero player routes.
**Repro (MEASURED, seed 2030, New York, the scripted campaign; 28 of 30
seeds in every configuration):** day 1 New York–Chicago ($59M cash).
Day 31: a used narrowbody and a lease, and the two markets the Next
Moves card names — New York–Boston at $61 and New York–Toronto at $85 —
opened at two rotations each ($8.3M left). −$811k a month; administration
(fire sale of one aircraft) and collapse on day 430.
`ae-fee-baseline --pairs JFK-BOS,JFK-YYZ,JFK-ORD --types PA184 --rotations 2 --months 3`:
Boston $1.29M revenue, fees $1.15M (89%), direct operating profit $16k,
−$1.17M a month after the $790k lease; Toronto $1.81M, direct $439k,
−$747k after everything; Chicago $2.78M, direct $1.24M, +$47k.
**Root cause:** `GameState.marketOpportunities` scores a market by the
passengers an entrant captures over the incumbents (`pool / (1 +
incumbents)`) — the passenger ranking the rival AI abandoned in AE-039
because it puts every short large pair ahead of every longer one. Short
pairs at hub fees are fee-bound for everyone (TD-031: the arrival
passenger fee alone is 40–45% of a $60–69 fare), so the card's top two
from New York are exactly the pairs no aircraft pays for. From Stockholm
and Munich the same rule happens to name pairs that pay (London,
Istanbul, Cairo), which is why the campaign twins never met it.
**Fix shape:** rank the player's opportunities by what one airframe day
sells — `CompetitorAISystem.airframeDayValue` on the revenue basis with
the fleet's own airframe (or the era's, before any is owned) — the rule
the rivals use, so the two cannot drift apart. Not done in AE-041: the
change re-pins the February picks of every campaign twin and journey
(`MunichHorizonTests` requires Munich–Istanbul among them;
`CampaignUITests` fights London–Berlin from Stockholm; TD-028's save
fixtures are worlds built on those picks), and a phase that changes them
must re-photograph them. Recommended as the next phase
(docs/AE041_PROFIT_VS_REVENUE_REPORT.md §16).
**Status:** OPEN — root-caused, MEASURED, fix designed.

---

## BUG-055 — The game's own advice recommended routes that cannot pay for the aircraft they need

**Severity:** P1 (a player who follows the game's guidance from a curated
start can be bankrupted by it). **Found:** 2026-09-03, AE-041, measuring the
New York campaign. **Root-caused and fixed:** 2026-09-03, AE-042.

**Repro (MEASURED).** Found an airline anywhere and read Home. At **21 of the
93 homes a player can pick**, the first suggestion either loses money after
the airframe it needs or cannot be flown by anything the era sells:
Manchester is told to fly London (243 km, **96% of revenue in airport fees**,
**−$1.18M a month** in the ledger over six months), London is told to fly
Paris (347 km, 85% in fees, **−$1.38M**), New York's second suggestion is
Toronto (−$494k) and Singapore's is Kuala Lumpur (−$684k). London's first
suggestion ranks **#44 of 44** of its own markets by what they keep;
Manchester's ranks #42 of 45. From Nadi both suggestions are beyond every
era airframe's range and the card shows them anyway. AE-041's scripted New
York campaign following that advice went into administration and collapsed
on day 430 in **28 of 30 seeds** (`ae-rival-scan 730 2030-2059 JFK --player`).

**Root cause.** `GameState.marketOpportunities` scored markets as
`pool / (1 + incumbents)` — the passengers a starter service would capture,
and nothing else. Aircraft entered only as a boolean range-and-runway gate;
fees, fuel, crew, maintenance, capacity, rotations, lease and cash appeared
nowhere. Because the reference fare rises with distance while the two
movement fees are charged per flight and do not, passengers-per-day is
highest exactly where the fee share is worst, so the ranking was not merely
imprecise at the short end — it was close to inverted. This is the rule the
rival AI stopped using in AE-039 for the same reason
(docs/AE042_BUG055_ROOT_CAUSE.md: CASE B, with CASE A as its cause and CASE E
at fleetless homes).

**Fix layer:** Core, the session read model only. `marketOpportunities` now
puts markets that pay for the airframe they need ahead of those that do not,
using `CompetitorAISystem.airframeDayValue(basis: .profit)` — the estimator
AE-040 corrected and AE-041 shipped for rivals — less the airframe's lease
and the crew and route payroll the economy charges. **The ranking itself is
unchanged**: among markets that pay, the order is still passengers per
incumbent. The gate reorders rather than deletes, so a home where nothing
pays still gets advice and no player is stranded. `MarketOpportunity` carries
the airframe it was judged on and the monthly figure, and the Next Moves card
names them. No tuning value, fee, fare, demand parameter, rival behaviour or
save format was touched.

**Measured after.** Homes given advice that loses money or cannot be flown:
**21 of 93 → 9 of 93**, and the nine that remain are BUG-056, not this. The
AE-041 campaign, script unchanged and only the advice different: **28 of 30
collapses → 0 of 30**. Following the advice for 730 days over 30 seeds at
four homes: mean cash at New York $343.6M → $469.4M, Stockholm $282.2M →
$386.2M, Barcelona $222.8M → $255.7M, Singapore $432.4M → $471.0M. The three
curated starts and Munich — the worlds the AE-039 and AE-041 twins and the UI
journeys are pinned on — are **unchanged**.

**Regression cover:** `NextMovesTests` (six tests): every recommended market
pays for its aircraft at seven homes; the five measured traps are gone from
the advice and still listed honestly in the route sheet; the curated starts'
advice is unchanged; a recommendation names a flyable airframe; a home where
nothing pays still gets advice; and a New York campaign that follows Home's
advice through real commands for 500 days ends active, with no
administration and more cash than it started with.
**Status:** FIXED — TESTED (457 of 457, locally and in CI run 135) and
OBSERVED: the New York journey's frames show the card offering Mexico City and
Miami with the airframe named and a positive month, Toronto gone, and the
player solvent and debt-free at day 435, five days past where the old advice
ended the game (docs/AE042_FINAL_REPORT.md §12).

---

## BUG-056 — The aircraft market recommends the largest airframe whatever the route is for

**Severity:** P2. **Found:** 2026-09-03, AE-042. **Re-measured:** 2026-09-04,
AE-043 — smaller and differently shaped than first recorded.

**Repro (MEASURED, `ae-advice market`).** The aircraft market (`FleetView`)
sorts by **seats, descending**, defaults to a lease, and does not hide
era-locked types, so a startup-era player scrolls past **seven unbuyable rows**
to reach the first one they can take: a 184-seat narrowbody at $790k a month.
`AircraftShopSheet()` takes no arguments — no route ever reaches it.

**What is really wrong, on six months of real ledger per row (AE-043):**

| Kind | Homes | Evidence |
| --- | --- | --- |
| The first buyable row **cannot fly the recommended route** — a runway-class block at the home airport | **4** — BGO, BLL, NCE, VCE | `routeEligibility`, exact |
| The first buyable row **loses money in the ledger** | **2** — FRA −$248k/mo, KEF −$311k/mo | six months flown |
| Estimator said the row was wrong and the ledger says it was fine | 5 — HAM, DUB, EDI, GOT, PMI | false positives |

So **6 of 93 homes**, not the 9 first recorded, and half of it is a
flyability problem rather than an economic one. Reykjavík is the one home
where a smaller aircraft is worth a fortune: **−$311k on the 184-seat
narrowbody against +$283k on a 90-seat regional jet**, a $594k a month swing.

**Root cause.** Two surfaces that never consult each other: the recommendation
is judged on an airframe and the market is sorted without reference to any
route. Compounded by the checklist teaching `acquireAircraft` **before**
`openRoute`, so the first purchase happens when no route exists at all.

**Why AE-043 did not fix it.** The fix was built — a pinned "recommended for
this route" row above an untouched market — and then withheld, because the
aircraft it pinned is **worse in the ledger at six of the seven homes where
the comparison is possible**. `CompetitorAISystem.airframeDayValue` takes
`passengersPerDay` as an input that does not vary with the aircraft, while the
simulation's captured demand rises with the capacity offered, so the estimator
is biased against large aircraft by construction: forecast error −2% to −9% on
small airframes and **+13% to +99% on large ones** on the same pairs. No
ranking of airframes can be built on it (TD-033).

**Fix shape.** Blocked on TD-033. Once the estimator's demand forecast
responds to the service offered, Option C from
docs/AE043_AIRCRAFT_SELECTION_DECISION.md is implemented and measured and can
be restored. The four runway-blocked homes need no estimator at all and could
be addressed separately.

**Re-evaluated (AE-044, 2026-09-04): PARTIALLY FIXED, and re-blocked.**
TD-033 is resolved — the estimator's demand now responds to the aircraft, the
frequency and the incumbents, and is the demand engine's own allocation. On
the aircraft market's default sort the modelled dangerous count across the 93
homes falls **9 → 7**, and the estimator's airframe picks agree with the
ledger at **8 of 13** controlled markets rather than 4
(docs/AE044_FINAL_REPORT.md §7–8).

It is still not enough to build the pinned recommendation on:

- **The economic half is blocked on TD-035.** The estimate prices the
  airframe's *maximum* rotations while every caller opens routes at *two*.
  Priced at the frequency the game actually flies, the estimator's ordering
  agrees with the ledger at **11 of 12** markets; priced as production prices
  it, at **4 of 12**. Both halves of the estimate describe an operation the
  game does not fly.
- **The four runway-blocked homes are unchanged** (BGO, BLL, NCE, VCE). That
  half was never estimator-dependent — `routeEligibility` is arithmetic — and
  can be fixed on its own at any time.
- **The UI is untouched.** `AircraftShopSheet()` still takes no arguments,
  still sorts by seats descending, still lists seven unbuyable rows first.

**Status:** OPEN — reproduced, root-caused, re-measured twice; the estimator
blocker (TD-033) is resolved, the aircraft market is not. Now blocked on
TD-035, not TD-033. Not forced closed.
