# Airline Empire — World & Airport System (Phase 4, as built)

## Split of responsibilities

- **`AirportSpec`** (content, immutable, in `ContentCatalog`): identity
  (code/name/city/country), `WorldRegion`, coordinates, fixed UTC offset
  (no DST by design), `RunwayClass` (small→veryLarge, Comparable), daily
  slot capacity, daily terminal capacity, movement + passenger fees
  (`Money`), `Demographics` (population, business/leisure/tourism/cargo
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

`Resources/airports.json` (80 airports, all 9 regions), `seasonality.json`
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
