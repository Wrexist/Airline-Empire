# Airline Empire — Domain Model

> Phase 1 document. Defines the entities, their ownership, identity, and
> relationships. Field lists are the *architectural* shape — exact stored
> properties are finalized per implementation phase, but ownership boundaries
> and identity rules here are binding.

## 1. Identity

**[RULE] Every entity has a typed ID** — `AirlineID`, `AircraftID`,
`AirportID`, `RouteID`, `FlightID`, … — a wrapper over a stable raw value.
Runtime-created entities (aircraft, routes, flights, airlines) use a
monotonic per-save counter (`EntityIDAllocator`, part of `GameState.meta`),
**never UUID/random**, so IDs are deterministic and replay-stable.
Content-defined entities (airports, aircraft *types*, event definitions) use
stable string codes from content files (`"ARN"`, `"A320-200"`).

**[RULE] Cross-entity references are by ID only.** No entity value embeds
another entity; joins happen through `GameState` lookups. This keeps the
state tree a tree, keeps copies cheap, and makes serialization trivial.

## 2. Entity catalog

### Content entities (immutable, in `ContentCatalog`, not in `GameState`)

| Entity | Identity | Sketch |
|--------|----------|--------|
| `AirportSpec` | IATA-style code | name, city, country, region, lat/lon, timezone offset rule, runway class, slot capacity/day, terminal capacity, fee schedule, base demographics (population, business index, leisure/tourism index, cargo index), seasonality profile ref, weather-risk class |
| `AircraftTypeSpec` | type code | manufacturer, model, category (regional/narrow/wide/…), seat capacity envelope, range km, cruise speed, fuel burn curve, list price, lease rate, maintenance profile, crew requirement, reliability baseline, runway-class requirement, comfort baseline |
| `EventSpec` | event code | trigger conditions, effect descriptors, duration/severity ranges (Phase 11) |
| `SeasonalityProfile` | code | monthly demand multipliers per segment |
| `Tuning` | singleton | named balance constants (demand elasticity, fuel base price, loan rates, reputation weights, …) |
| `ScenarioSpec` | code | starting airport, cash, year, difficulty modifiers, seed policy |

### Runtime entities (mutable, in `GameState`)

| Entity | Owned by | Sketch |
|--------|----------|--------|
| `Airline` | `GameState.airlines` | name, brand, kind (player/AI + AI personality), home airport, cash reference (via ledger account), fleet (IDs), routes (IDs), reputation components, service config, staff aggregates, loans, strategy state (AI-only slice) |
| `Aircraft` | `GameState.aircraft` | typeRef, owner airline, ownership (owned/leased+terms), age, condition, maintenance state, assignment (routeID?), location (airport or in-flight ref), utilization stats, book value |
| `Route` | `GameState.routes` | airline, origin, destination, schedule (departures/week pattern), assigned aircraft IDs, ticket price per segment class, historical performance window |
| `Flight` | `GameState.flights` | route, aircraft, phase (scheduled→boarding→departing→enRoute→arriving→turnaround→ready / disrupted), times (scheduled + actual, SimTime), passenger count by segment, per-flight economics snapshot |
| `Airport` (runtime slice) | `GameState.world.airports` | slot allocations by airline, current disruption state, congestion level — *only* what changes at runtime; static data stays in `AirportSpec` |
| `Ledger` / `Transaction` | `GameState.ledger` | per-airline account balances; append-only categorized transactions (bounded detail retention + monthly rollups) |
| `Loan` | inside `Airline` | principal, rate, term, schedule, origin |
| `WorldState` | `GameState.world` | fuel price, macro cycle phase, season/date-derived indices, active `WorldEvent` instances |
| `WorldEvent` | `GameState.world.events` | specRef, scope (global/region/airport/airline), severity, remaining duration, applied-effect record |
| `ProgressionState` | `GameState.progression` | milestones reached, achievements, unlock set, mission/challenge states |
| `RNGState` | `GameState.rng` | serialized substream states |

### Aggregates, not entities **[RULE]**

Passengers, individual staff members, and individual maintenance tasks are
**quantities/records, not entities with identity**. A flight has
`passengers: SegmentCounts`; an airline has staff *pools* with headcounts,
wage levels, morale/training indices; maintenance is aircraft state, not a
work-order entity. Rationale: performance goal §11 of ARCHITECTURE.md and no
gameplay decision requires individual identity. (A future expansion may
promote one — that is a Phase 24 decision, and the seam is the aggregate
type.)

## 3. Relationship rules

- `Airline 1—N Aircraft` (via owner), `Airline 1—N Route`, `Route 1—N Flight`
  (live only), `Route N—N Aircraft` (assignment; an aircraft serves ≤1 route
  at a time — multi-route rotations are a possible later feature behind the
  assignment abstraction).
- A `Flight` is created by the scheduler shortly before departure and removed
  after completion into aggregated route history — live-flight population
  stays bounded (**[RULE]**: `GameState.flights` holds only active/imminent
  flights).
- Route history, financial statements, and analytics series are **bounded
  rolling windows + rollups**, never unbounded logs (**[RULE]**).
- Slots: `Airport` runtime slice records per-airline slot holdings;
  route creation validates slot + runway + range eligibility.

## 4. Invariants (enforced at command boundary + debug preconditions)

- Every ID referenced anywhere resolves (no dangling refs after any command
  or tick — checked by a debug-only `GameState.validateIntegrity()` used in
  tests).
- An aircraft is in exactly one place: at an airport, or on exactly one live
  flight.
- Ledger balances equal the sum of their transactions/rollups.
- Slot allocations at an airport never exceed capacity.
- Money, capacities, and counts are never negative except explicitly signed
  quantities (cash may go negative only through the modeled overdraft/debt
  path, not arithmetic accident).
- Clock never goes backwards; all `actual` times ≥ their `scheduled`
  counterparts' creation time.

## 5. Commands (initial set — grows per phase)

`FoundAirline`, `BuyAircraft`, `LeaseAircraft`, `SellAircraft`,
`OpenRoute`, `CloseRoute`, `ModifyRoute` (schedule/price/aircraft),
`SetServiceConfig`, `TakeLoan`, `RepayLoan`, `SetMarketingSpend`,
`RespondToEvent` — each with a validator producing `CommandRejection`
reasons a UI can show verbatim.

**[RULE] AI airlines issue the same commands through the same validators.**

## 6. Events (initial taxonomy — grows per phase)

Lifecycle (`flightDeparted`, `flightArrived`, `flightDisrupted`,
`aircraftDelivered`, `maintenanceCompleted`), finance (`transactionPosted`,
`loanPaymentDue`, `bankruptcyWarning`), market (`fuelPriceChanged`,
`competitorOpenedRoute`, `worldEventStarted/Ended`), progression
(`milestoneReached`, `achievementUnlocked`).

Events carry IDs + primitive payloads (Codable, small, no entity embedding).
