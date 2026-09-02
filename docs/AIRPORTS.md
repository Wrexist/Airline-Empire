# Airline Empire — World & Airport System (Phase 4, as built)

## Naming (owner decision, AE-032)

Airports are the **real world's**: each city carries its real biggest
airport — real IATA code, real name in the `"City Fieldname"` convention
("Stockholm Arlanda", "London Heathrow") that `Vocab.airportDisplay` renders
as "Arlanda (Stockholm)". An airport whose common name is just its city
("Frankfurt", "Manchester") sets name == city and displays as the city
alone. Fourteen secondary-city airports were added in the same pass
(Landvetter, Flesland, Manchester, Edinburgh, Lyon, Hamburg, Düsseldorf,
Málaga, Venice, Billund, Calgary, Brisbane, Guangzhou, Sapporo). Airlines,
liveries and aircraft remain fictional — only the geography is real.

## Split of responsibilities

- **`AirportSpec`** (content, immutable, in `ContentCatalog`): identity
  (code/name/city/country), `WorldRegion`, coordinates, fixed UTC offset
  (no DST by design), `RunwayClass` (small→veryLarge, Comparable), daily
  slot capacity, daily terminal capacity, movement + passenger fees
  (`Money`; the movement fee is quoted for a 180-seat movement and a
  landing aircraft pays it in proportion to its seats —
  `movementFee(for:ops:)`, AE-040, see the fee note below), `Demographics` (population **in thousands** — see the unit
  note below, business/leisure/tourism/cargo
  indices 0…1), seasonality profile reference, `WeatherRisk`.
- **`AirportRuntime`** (state, in `GameState.world`): per-airline slot
  allocations only. Entries exist lazily — an untouched airport costs zero
  bytes in a save — and are removed when empty.
- **`SeasonalityProfile`** (content): 12 monthly leisure-demand multipliers.
  Contract (enforced by test): yearly mean stays within 0.85–1.15 so
  profiles redistribute demand across the year rather than inflate it.
- **`Tuning`** (content): world balance constants (currently
  `minRouteDistanceKm = 80`).

## Content pipeline

`Resources/airports.json` (94 airports, all 9 regions), `seasonality.json`
(11 profiles), `tuning.json` → `ContentCatalog.loadBundled()` →
construction-time validation that **throws with a complete problem list**:
duplicate/empty codes, invalid coordinates, non-positive capacities,
negative fees, invalid demographics, impossible UTC offsets, dangling
seasonality references, malformed profiles. Broken content cannot reach
gameplay; the loader test makes it a build failure.

World fiction per GAME_DESIGN.md §8: real cities and geography, fictional
airport names/codes.

## Geometry

`Geo.distanceKm` — haversine on the mean Earth radius, **quantized to whole
km** at the API boundary so libm last-ulp platform differences can't leak
into gameplay state (docs/SIMULATION_ARCHITECTURE.md §2). Tested against
real-world anchors (±3%), symmetry, identity, antipodes, and date-line
crossing.

## Route eligibility (static-world checks)

`catalog.routeEligibility(from:to:aircraftRangeKm:aircraftRunwayRequirement:)`
returns *all* applicable reasons (not just the first):
`unknownAirport`, `sameAirport`, `belowMinimumDistance`,
`beyondAircraftRange`, `runwayTooSmall(airport:has:needs:)` — checked at
both ends. Dynamic constraints (slot availability, aircraft state) belong
to the systems that own that state (Phases 5–6).

## Slots

`WorldState.allocateSlots/releaseSlots` with typed `SlotError`s; capacity is
shared across airlines per airport; failed operations leave state untouched;
negative holdings are an integrity violation caught by the engine's debug
sweep. Use-it-or-lose-it slot policy (GAME_BALANCE §7) attaches in Phase 6
when routes consume slots.

## Determinism note (kernel addition this phase)

`EntityID`/`ContentCode` now conform to `CodingKeyRepresentable`, so
entity-keyed dictionaries encode as string-keyed JSON objects; with
`.sortedKeys` this keeps populated saves byte-deterministic (regression
test: `worldStateSurvivesSaveDeterministically`). Save format bumped to
**v2** (pre-release refusal policy documented in SaveFormat).

## Lookup & queries

`airport(_:)`, `airports(in region:)`, `distanceKm(_:_:)`,
`nearestAirports(to:limit:)` (deterministic tie-break by code),
`orderedAirportCodes` as the canonical deterministic iteration order.

## Unit note: `populationThousands` (added 2026-08-27)

The field holds **thousands of people**: Reykjavik is `230`, London is
`14800`. It once held raw people, which made every gravity-model demand
pool exactly 1000x too large and rendered ticket pricing a free variable —
see `tasks/BUGS.md` BUG-006 and `docs/BALANCING.md` F-006. Because the
demand curve itself was correct, no unit test caught it; the defect only
showed when capacity truncated demand in the full pipeline.

Two guards now exist and must not be weakened:
`ContentQualityTests.airportPopulationsAreInThousands` (bounds every value
to a plausible metro range and asserts the largest market pool stays within
reach of real fleet capacity) and
`BalanceTests.pricingHasRealConsequencesEndToEnd` (a fare rise must cost
passengers, and profit must have an interior optimum).

## Fee note: what a movement costs (added 2026-09-02, AE-040)

`movementFee` is the charge for one movement of the **reference cabin**
(`OpsTuning.movementFeeReferenceSeats`, 180 seats — the narrowbody the
economy is anchored on). A flight pays each end's movement fee scaled by
its aircraft's seats over that number, in whole cents, plus the arrival
airport's `passengerFee` per passenger landed
(`FlightOpsSystem.arrive`). So at Heathrow ($2,600 quoted) a 68-seat
turboprop pays $982 per movement, an MR-180 $2,600, a 298-seat widebody
$4,304. Until AE-040 every aircraft paid the quoted fee, and the 68-seat
turboprop could not clear its fees on any route in the world
(docs/FEE_ECONOMY_BASELINE.md, docs/FEE_ECONOMY_FIX_DECISION.md). The
passenger fee is unchanged. Player and rival flights pay the same.
