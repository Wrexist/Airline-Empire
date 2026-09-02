# Airline Empire — Routes & Flight Operations (Phase 6, as built)

## Route model

`Route`: airline, origin/destination, distance (fixed at opening from world
geometry), `dailyRoundTrips` (target frequency), one-way `ticketPrice`,
sorted `assignedAircraft`, `RouteStats` (completed/cancelled/delayed
counters → completionRate & punctuality, consumed by Phase 9).

**Slots:** a route *holds* `2 × roundTrips` daily movements at each endpoint
from open to close (allocated in `OpenRoute`, adjusted by `SetRouteFrequency`
deltas, released by `CloseRoute`). Congestion is therefore a real strategic
constraint: opening/frequency commands reject with `route.noSlots` when an
airport is full. Only routes allocate slots, so squatting without service is
structurally impossible today; a use-it-or-lose-it rule generalizes this
when other allocators appear.

## Commands

`OpenRoute` (eligibility: airports exist, distinct, ≥ min distance, no
duplicate market per airline, 1–20 trips, positive fare, slots both ends),
`CloseRoute` (rejects while flights are airborne; cancels ground-phase
flights, unassigns aircraft, releases slots), `SetRoutePrice`,
`SetRouteFrequency` (slot delta checked), `AssignAircraftToRoute` (ownership,
delivered, unassigned, range ≥ route distance, runway class both ends),
`UnassignAircraft` (not mid-flight; removes its scheduled flights).

## Scheduling (`FlightSchedulingSystem`, daily)

Deterministic materialization: routes in sorted order, aircraft in sorted
order, arithmetic departure times. Per route: flight time = cruise time +
overhead; round-trip block = 2 × (flight + turnaround); per-aircraft daily
capacity = ⌊operating day / block⌋; trips = min(target, capacity × usable
aircraft), distributed round-robin, flown back-to-back from 06:00. An
assigned aircraft that is elsewhere gets a real **ferry flight** to the
origin (full costs, no passengers) — no teleportation. Mixed-type routes
time to the first assigned aircraft's type (revisit if mixed fleets prove
common).

## Flight lifecycle (`FlightOpsSystem`, every tick)

`scheduled → boarding → enRoute → turnaround → removed`, entirely
simulation-driven:

- **Boarding** starts `boardingMinutes` before departure only when the
  airframe is free, airworthy, and present — a late inbound cascades
  naturally into the next leg.
- **Dispatch** at departure rolls the aircraft's current reliability
  (type baseline − wear − age, floored): disruptions delay (uniform
  45–240 min, re-rollable) or cancel (`cancellationShareOfDisruptions`).
- **Expiry:** a scheduled flight that couldn't board within
  `scheduledFlightExpiryMinutes` (4h) of its slot cancels — found by the
  Phase-6 test suite as a stale-flight leak (grounded aircraft's flights
  piling up, then burst-flying on return); expiry-as-cancellation is the
  honest operational outcome.
- **Arrival** posts categorized costs (fuel = burn × distance × world fuel
  price; movement fees both ends, each scaled by the aircraft's seats over
  the 180-seat reference cabin (AE-040), + per-pax fee at the arrival end;
  crew = block hours × cockpit/
  cabin rates), applies flight-hour wear + hours, then turnaround; completion
  updates `RouteStats`. Live-flight population stays bounded (flights are
  removed when done; history lives in stats + ledger).

## Determinism & integrity

All sweeps in sorted-ID order; RNG confined to `flightOps.*` substreams;
full-pipeline dual-run and mid-flight save/restore-continuation tests pass.
Integrity sweep extended: flights reference live routes/aircraft,
`activeFlight` back-references resolve, one live flight per airframe
(exclusivity asserted per tick in tests).

## Deliberate scope notes

Passengers are 0 until Phase 7 (demand allocation) — flying currently burns
money, which is correct: revenue arrives with demand. Weather/world-event
disruptions layer onto the same dispatch mechanism in Phase 11. Save v4.
