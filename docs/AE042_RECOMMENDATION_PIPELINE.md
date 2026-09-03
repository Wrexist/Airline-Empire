# AE-042 — The recommendation pipeline, as built

What the game actually does between "the player opens Home" and "a route is
flying", traced through the source before anything was changed.

Everything in this document is **READ** (from the repository at commit
60c1520) unless a line says otherwise. Measurements live in
docs/AE042_NEXT_MOVES_BASELINE.md; the decision in
docs/AE042_BUG055_ROOT_CAUSE.md.

## 1. The path, end to end

| Step | Where | What it does |
| --- | --- | --- |
| 1. Rank markets | `GameState.marketOpportunities(catalog:limit:)` — `Session/MarketOpportunities.swift` | The single ranking. Returns `[MarketOpportunity]`, best first. |
| 2a. Before the first route | `GameState.onboardingModel(catalog:suggestionLimit:)` — `Session/OnboardingModel.swift` | `marketOpportunities(limit: 2).map(\.asFirstRouteSuggestion)`, shown while the `openRoute` checklist step is incomplete. |
| 2b. After the checklist | `NextMovesCard` — `App/Screens/DashboardView.swift` | `marketOpportunities(limit: 4)`, then `filter(\.servableNow)`, falling back to the unfiltered list when that is empty, then `prefix(2)`. |
| 2c. On the map | `MapModel` — `Session/MapModel.swift:505` | The same call, as the demand coach's overlay. |
| 3. The tap | `FirstRouteSuggestion` → `RouteDraft` → `OpenRouteSheet` — `App/Screens/RoutesView.swift` | Prefills origin and destination and the reference fare. |
| 4. The sheet's own list | `GameState.marketCandidates(from:catalog:)` | A second, differently ordered list for browsing from one origin (below). |
| 5. Acquisition | `App/Screens/FleetView.swift` (the market) | Independent of the recommendation. Defaults: sort by **seats descending**, deal type **lease**. |
| 6. Reality | `OpenRouteCommand`, `AssignAircraftToRouteCommand`, `FlightOpsSystem`, `EconomySystem` | The ledger. |

Two consequences of the shape are worth stating plainly:

- **One ranking, four surfaces.** The onboarding suggestions, the Next Moves
  card, the map coach and (indirectly) the AE-041 campaign scan all read
  `marketOpportunities`. A change there changes all of them at once — which
  is why the campaign twins and journeys are pinned on its output.
- **The recommendation and the aircraft never meet.** Nothing between step 1
  and step 5 carries an aircraft type. The route is chosen first, the
  aircraft second, and no code compares them beyond "can *something* fly it".

## 2. What `marketOpportunities` scores

```
score = pool / (1 + incumbents)
```

where `pool` is `DemandSystem.expectedCapturedPassengers` in **both**
directions at `fareRatio: 1.0` and `representativeStarterQuality` — the
passengers a representative starter service would capture per day. Ties break
on origin then destination code, so the ranking is deterministic.

**Origins.** The home airport, plus any airport where the player has three or
more routes, capped at the five largest by touch count.

**Excluded.** City pairs the player already serves (`Route.market`,
direction-free).

**The eligibility gate**, in full:

```swift
let candidateSpecs = ownedSpecs.isEmpty ? eraSpecs : ownedSpecs
let servable = candidateSpecs.contains { spec in
    catalog.routeEligibility(from: origin, to: code,
                             aircraftRangeKm: spec.rangeKm,
                             aircraftRunwayRequirement: spec.runwayRequirement).isEmpty
}
guard servable || ownedSpecs.isEmpty else { continue }
```

Three READ facts follow from those five lines:

1. With a fleet, only markets some **owned** aircraft can fly are scored.
2. With no fleet, `candidateSpecs` is the era's list, and the guard's second
   arm (`|| ownedSpecs.isEmpty`) passes **every** market with a positive
   pool — including ones no era aircraft can fly. `servableNow` still
   reports the era check, so on a fleetless airline the flag means "some
   aircraft this era permits could fly it", not "an aircraft I own could".
   `NextMovesCard` filters on that flag, so before the first purchase it is
   filtering on era-reachability.
3. Eligibility is a **boolean gate**, never a term in the score. Range and
   runway can exclude a market; they cannot rank one below another.

## 3. What the ranking knows, and what it does not

| Input | In the ranking? | Where it would come from |
| --- | --- | --- |
| Demand pool, both directions | **yes** — it is the whole score | `DemandSystem.demandPool` |
| Incumbents | **yes** — divides the score | `carrierCountByMarket()` |
| Distance | reported, not scored | `catalog.distanceKm` |
| Reference fare | reported, not scored | `DemandSystem.referenceFare` |
| Aircraft range, runway | boolean gate only | `catalog.routeEligibility` |
| Aircraft seats / capacity | **no** | `AircraftTypeSpec.seats` |
| Rotations an airframe can fly | **no** | `FlightSchedulingSystem.roundTripsPerAircraftPerDay` |
| Airport movement and passenger fees | **no** | `AirportSpec.movementFee(for:ops:)`, `.passengerFee` |
| Fuel, crew, maintenance, service | **no** | `FlightOpsSystem` / `FleetEconomics` |
| Acquisition price, lease rate | **no** | `AircraftTypeSpec.listPrice`, `.leaseMonthly`, `FleetEconomics.usedPrice` |
| Player cash, runway months | **no** | `ledger.balance`, `finance.byAirline` |
| Progression value | **no** | `EraGate` |

So the ranking answers **"which market has the most passengers per
incumbent?"** and nothing else. Fare enters only as a displayed figure;
cost, capacity and money never enter at all.

## 4. Where this differs from the rival AI

`CompetitorAISystem.candidateMarkets` walks a structurally similar list — a
horizon, gates, then a score — but the score is different, and the difference
is the one AE-039 shipped deliberately:

| | Player · `marketOpportunities` | Rival · `CompetitorAISystem` |
| --- | --- | --- |
| Candidate set | every airport from up to five bases | the sixteen nearest to the airframe |
| Gates | region (n/a), eligibility, already-served, positive pool | archetype region, eligibility, already-served, slots, `minViableDailyDemand` floor |
| Demand term | `expectedCapturedPassengers`, both ways | `poolAvailableToEntrant` against incumbents' real offers |
| Contested markets | `pool / (1 + incumbents)` | the demand engine's own split |
| **Score** | **passengers** | **`airframeDayValue`: passengers capped by the airframe's seats over the scheduler's rotations, at the archetype's fare** |
| Capacity, rotations | absent | central |
| Costs | absent | available on the `.profit` basis (measured, not shipped) |

AE-039 replaced the rivals' passenger ranking precisely because it "put every
short large pair ahead of every longer one for ever" (docs/HORIZON_AUDIT.md
§3.2). The player's ranking is the rule the rivals stopped using. Whether
that is BUG-055's cause is a measurement question, not a reading one, and it
is answered in docs/AE042_BUG055_ROOT_CAUSE.md.

## 5. Primitives already available for reuse

Nothing new needs building to price a market. All of these are `public` and
callable from the session layer:

- `CompetitorAISystem.airframeDayValue(distanceKm:passengersPerDay:spec:fareRatio:serviceTier:origin:destination:state:catalog:rotationsPerDay:basis:)`
  — revenue or profit for one airframe day, using the flight system's own
  fuel, seat-scaled movement fees, arrival passenger fee, crew, service and
  the fleet system's maintenance rule (AE-040 corrected the last two).
- `FlightSchedulingSystem.roundTripsPerAircraftPerDay(distanceKm:spec:ops:)`
- `DemandSystem.demandPool`, `.expectedCapturedPassengers`,
  `.poolAvailableToEntrant`, `.referenceFare`, `.representativeStarterQuality`
- `AirportSpec.movementFee(for:ops:)`, `.passengerFee`
- `FleetEconomics.usedPrice`, `.usedMarketCondition`, `.expectedMaintenancePerDay`
- `AircraftTypeSpec.leaseMonthly`, `.listPrice`, `.seats`, `.rangeKm`, `.runwayRequirement`
- `FinanceTuning.payrollPerAircraftMonthly`, `.overheadBaseMonthly`, `.payrollPerRouteMonthly`

A second economy is neither needed nor permitted.

## 6. The seven pipeline questions the phase asked

1. **Does it recommend markets that are reachable but economically
   dangerous?** Possible by construction — no cost term exists. MEASURED in
   the baseline.
2. **Viable but unaffordable?** Possible — no cash term exists.
3. **Profitable only after buying an aircraft the player cannot afford?**
   Possible — no acquisition term exists.
4. **Impossible to operate with the current fleet?** Not after the first
   purchase (the gate uses owned specs), but before it the gate's second arm
   admits everything, and `NextMovesCard` then filters on an era flag.
5. **Can routes be recommended before aircraft are accounted for?** Yes —
   that is the normal order. The onboarding checklist teaches aircraft first,
   but Home shows route suggestions from day 0, before any aircraft exists.
6. **Is there a second ranking that can drift?** Yes, one: the route sheet's
   `marketCandidates(from:catalog:)` sorts by raw `expectedDailyPassengers`
   with **no incumbent divisor** and returns every destination, servable or
   not, with `servableNow` / `servableByEra` flags for the UI to explain.
   The two lists can therefore disagree about order on contested pairs. Both
   are passenger-ranked, so the disagreement is narrow today.
7. **Is anything mutated?** No. Both functions are pure derivations over
   `GameState`; nothing is persisted and no command is issued.

## 7. What the player is told

`NextMovesCard` renders per market:

```
{ORIGIN} → {DEST} · {City}
≈{N} passengers/day · {D} km · {"no competition yet" | "{n} rival(s) already here"}
```

The card's heading is "Strong open markets from your bases" (or "Or grow the
network:" when an idle-aircraft warning is above it). The route sheet then
shows the reference fare, the distance and the demand figure again.

READ: no surface in that path states a cost, a fee, an aircraft, a monthly
result, or an affordability judgement. The word "Strong" is the only
qualitative claim, and it is a function of the passenger count alone.
