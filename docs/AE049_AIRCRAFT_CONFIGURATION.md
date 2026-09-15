# AE-049 — Aircraft configuration and upgrades

## Player experience

Fleet aircraft details now open with an aircraft overview, a section selector,
and a cabin editor styled after the supplied reference. Pacifica narrowbodies
have original generated product artwork. Other types retain their existing
category-specific aircraft illustration.

- Cabin Layout: an exact-count vector seat map, class counts, percentages,
  sliders and step controls, reset, a reviewable refit, and a route forecast.
- Upgrades: Wi-Fi, dining, seat comfort, and entertainment, with three levels.
- Operations: existing route assignment, route navigation, ownership and
  confirmed sale/lease return flows.
- Condition: actual condition, dispatch reliability, age, hours, and maintenance.
- History: the latest 50 refits and maintenance/delivery events still present
  in the simulation's recent event log.

The UI uses the existing navigation shell and adaptive design tokens. Cabin
controls reflow for narrow screens and accessibility text sizes; seat classes
have text labels as well as colors. Changes are drafts until confirmed, survive
section changes, and report success only when the resulting state arrives.

## Capacity rule

The reference's example totals 184 physical seats while its written requirement
says premium seats reduce capacity. The implementation treats the aircraft
specification's `seats` as economy-equivalent floor space:

| Class | Space per passenger | Yield relative to base fare |
| --- | ---: | ---: |
| First | 4 | 3.20 |
| Business | 2 | 1.85 |
| Premium Economy | 2 | 1.35 |
| Economy | 1 | 1.00 |

Economy fills the remaining space automatically. Every accepted layout uses
exactly the type's space budget. Sliders clamp before committing and Core
rejects malformed, negative, over-capacity or invalid upgrade values.

These are initial game balance constants, centralized in Core. The premium
classes increase average fare and comfort but reduce physical capacity. Both
business and leisure demand use the existing price-sensitivity model, so a
higher average fare can lose price-sensitive passengers.

## Simulation integration

- `Aircraft.configuration` and its history are optional Codable fields. Old
  saves decode as the original all-economy layout with baseline upgrades.
- `ConfigureAircraftCommand` is the only refit mutation. It checks ownership,
  airframe availability, layout validity and cash; posts installation charges
  to the existing maintenance ledger category; and records a bounded history.
- Refit charges: $250 per changed class-seat count, plus $120 per original
  capacity seat per equipment level added. Downgrades do not refund equipment.
- Each upgrade level adds 0.025 to comfort; premium cabin share adds up to 0.22.
  Comfort caps at 1. Existing unconfigured aircraft retain original behavior.
- Recurring upgrade costs per passenger per level: Wi-Fi $0.75, dining $2.00,
  seat comfort $0.50 and entertainment $0.75. These are added to the existing
  airline service-tier charge and posted by FlightOpsSystem.
- Boarding and flown-seat statistics use installed physical seats. Departures
  post the configured blended yield. Airport movement fees continue to depend
  on airframe size rather than cabin density.
- Demand retains the existing representative aircraft baseline and includes
  seat-weighted cabin improvements and fares from every assigned airframe.
  Demand is recalculated at the normal daily boundary, never refilled by a
  refit command.
- Reputation uses configured, seat-weighted fleet comfort. Expected happiness
  uses the four existing quality components (comfort, service, reliability and
  punctuality), with an explicit estimate label rather than a fabricated survey.

## Forecast meaning

The preview runs the authoritative DemandSystem on a value copy of the world,
then uses CompetitorAISystem's shared airframe-day cost estimator. It includes
fuel, airport fees, crew, onboard service, age-adjusted maintenance reserves,
and the aircraft's lease. It uses today's conditions for 30 days; excludes
company overhead, future disruptions and the one-time refit bill. Multi-aircraft
boarding order and daily scheduling can differ from the capacity-share estimate.
The UI states these limits. No second demand or economic engine exists in SwiftUI.
Forecasts are debounced off the main actor, refreshed on edits, installed changes
and game-day changes, and never consume RNG or mutate the live world.

## Validation

`AircraftConfigurationTests` cover packing/clamping, hostile values, legacy JSON,
refit billing and idempotence, no demand refill, persistence, availability/funds,
forecast purity and consistency, multi-aircraft demand, and actual flight seats
and revenue. `AircraftConfigurationUITests` exercise cabin editing, confirmation,
saved state, upgrades, and a light appearance with accessibility text.

A dedicated branch/manual macOS workflow runs focused Core regressions, builds
the app/test targets, and runs the aircraft screen journeys. Native results and
remaining limitations are recorded below after execution.

The existing assignment eligibility test also extracts its lazy optional fixture
before invoking `#require`; this preserves the test while avoiding a Swift Testing
macro expansion error on the Apple toolchain.
