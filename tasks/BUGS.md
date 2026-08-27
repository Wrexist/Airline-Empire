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

*(Historical note: bugs found and fixed test-first inside a phase are
recorded in that phase's COMPLETED.md entry, not here — this register is
for bugs that escape a phase.)*
