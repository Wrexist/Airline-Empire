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

Commit `713fb49`, [run 34979181451](https://github.com/Wrexist/Airline-Empire/actions/runs/34979181451):

- 100 focused Core tests passed, including all six new route-planning tests.
- Release build passed with warnings treated as errors.
- Native iOS app and test targets built successfully.
- The iPhone route journey passed: creation, assignment, fare editing,
  confirmation, saved feedback, aircraft comparison, Competition and History.
- The iPad attempt failed in the pre-existing aircraft market acquisition
  setup: the app terminated during repeated scrolling, before route management
  opened. No iPad route pass is claimed for this run. A focused saved-campaign
  iPad journey and isolated simulator run follow.
- Hosted light/dark captures of all five sections and the AX5 planner passed.
- Existing aircraft hosted captures remained in the native review suite.
- Local symbol resolution, UTF-8 source checks and diff checks passed.

The long Campaign and Horizon journeys were updated and compiled; these longer
campaigns were not rerun in this focused validation. No physical-device or
TestFlight deployment is claimed.

## Recommended next feature

Airports & hubs: carry this visual system into airport profiles, making your
presence, local demand, competitors, slots and fees clear. Once that foundation
is in place, add lounges and ground-service investments with authoritative
costs and benefits. This connects aircraft configuration and route planning to
where the airline chooses to expand.
