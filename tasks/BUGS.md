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
