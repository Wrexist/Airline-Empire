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

*(Historical note: bugs found and fixed test-first inside a phase are
recorded in that phase's COMPLETED.md entry, not here — this register is
for bugs that escape a phase.)*
