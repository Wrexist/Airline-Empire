# AE-050: Route management

## Player experience

The aircraft screen's navy panels, outlined tabs, readable metrics and adaptive
layouts now extend to route details. Five sections separate each decision:

- Overview: geographic airport diagram, live flight status, booked profit,
  assignment controls, operational results and demand.
- Pricing & Schedule: draft base fare and daily round trips, current-plan
  comparison, forecast, confirmation and state-confirmed saved feedback.
- Aircraft: existing assignment and market actions, plus single-aircraft
  comparison using each owned aircraft's installed cabin and upgrades.
- Competition: existing market demand and rival analysis, including standing
  and response guidance from the existing simulation.
- History: the latest 50 confirmed planner changes and actual current/previous
  month direct operating economics. Route closure retains its confirmation.

The airport diagram plots real coordinates, nearby airports and the endpoints,
including routes crossing the date line. It is an airport diagram rather than a
terrain map. View on map opens the existing full world map.

## Commands and persistence

ApplyRoutePlanCommand validates both existing price and frequency commands
before changing either value or adjusting slots. It does not refill sold demand
or replace existing flights. Demand and scheduling update through their existing
systems. Reapplying the same plan does not add another history entry.

Route.planHistory is optional Codable state. Legacy saves decode without it.
Only changes made through the new planner are recorded in this history; legacy
single-setting commands remain compatible with other callers.

## Forecast model

RoutePlanPreview works on a value copy, applies the proposed slot changes and
runs the authoritative DemandSystem once. It then uses the same aircraft-level
estimator as the cabin screen to aggregate revenue, operating/aircraft costs,
seats, passengers, achievable rotations and load factor. This extraction avoids
repeating demand allocation for every assigned aircraft.

The model includes installed seats and cabin yield, upgrade service costs,
maintenance reserves, leases, fuel, movement charges and crew. It is a 30-day
steady-state estimate, excludes company overhead and future disruptions, and
can differ from actual scheduling/boarding order. Historical direct route
profit is explicitly labelled as a different measure.

Aircraft comparison models one eligible operational aircraft alone on the route;
it changes no assignments. The player makes actual assignment changes using
the existing controls. Price/frequency drafts survive section changes and are
calculated off the main actor after a short debounce.

## Validation

Six new Core tests cover atomic changes, slot rejection, demand preservation,
legacy decoding, persistence, estimator consistency and pure aircraft comparisons.
The existing 94-test focused regression set and release build are also run.
Native tests exercise route creation, assignment, pricing confirmation, saved
feedback, aircraft selection, Competition and History on iPhone and iPad.
Hosted captures cover all five sections in light/dark and the planner at AX5.
Campaign and Horizon test navigation now follows the new tabs and confirmation.

## Verified result (2026-09-15)

Application revision `3e2eb6d`; subsequent code changes affect validation only.

- [Core/iPhone run 34983032210](https://github.com/Wrexist/Airline-Empire/actions/runs/34983032210):
  100 focused Core tests, release build with warnings as errors, native build,
  fresh-airline iPhone route journey, and hosted light/dark/AX5 captures passed.
  The run's later simulator-preparation step failed because it attempted to
  shut down an already-shut-down device; the state check is now fixed.
- [Focused iPad run 34984654729](https://github.com/Wrexist/Airline-Empire/actions/runs/34984654729):
  native build and saved-campaign route journey passed, one test, zero failures.
  The test loads the existing simulation-generated rival-pressure-retreat save,
  changes and confirms the plan, selects an aircraft comparison, and opens
  Competition and History. Core/iPhone checks were intentionally not repeated.
- Local symbol resolution, UTF-8 source checks and diff checks passed.
- Visual review confirmed readable iPhone/iPad planner controls, market-reference
  fare, forecast figures, capacity warnings, aircraft cabin comparison, saved
  history and the iPad loss warning. One early hosted capture caught the normal
  forecast-loading state; the actual device journey captures show completed values.

An earlier fresh-airline iPad attempt (34979181451) terminated in the existing
market while scrolling for a lease, before route management opened. That market
setup failure is not claimed fixed by this feature; iPad route functionality is
verified from a saved campaign. Simulator preparation now checks actual device
states and shuts down other booted simulators before running iPad tests.

The long Campaign and Horizon journeys were updated and compiled; these longer
campaigns were not rerun in this focused validation. No physical-device or
TestFlight deployment is claimed.

## Recommended next feature

Airports & hubs: carry this visual system into airport profiles, making your
presence, local demand, competitors, slots and fees clear. Once that foundation
is in place, add lounges and ground-service investments with authoritative
costs and benefits. This connects aircraft configuration and route planning to
where the airline chooses to expand.
