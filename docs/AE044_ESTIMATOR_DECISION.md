# AE-044 §4 — What changed, what did not, and why

Phase 7–9. The design chosen after docs/AE044_ROOT_CAUSE.md and implemented
in the same phase. Read that first; this document assumes its verdict
(CASE G, dominated by "the demand term and the capacity term describe
different operations").

---

## 1. The shape of the fix

**One authoritative demand allocation, asked the estimator's question.**

The estimator no longer *receives* a passenger figure. It *derives* one, from
the demand engine, for the exact service it is about to cost.

```
before   airframeDayValue(distanceKm:, passengersPerDay: <caller's number>, spec:, …)
after    airframeDayEstimate(origin:, destination:, distanceKm:, spec:,
                             fareRatio:, reputationMultiplier:, incumbents:,
                             rotationsPerDay:, state:, catalog:, basis:)
             → rotations = roundTripsPerAircraftPerDay(…)
             → demand    = DemandSystem.serviceDemand(…, roundTripsPerDay: rotations, …)
             → value     = airframeDayValue(…, passengersPerDay: demand.capturedPerDay,
                                            rotationsPerDay: rotations, …)
```

The passenger figure and the rotation count now come from the same line. That
is the whole fix; everything below is what it took to make it true.

## 2. Four changes in Core

### 2.1 `DemandSystem` — the split, in one place (refactor, no behaviour change)

`allocate`, `expectedCapturedPassengers` and `poolAvailableToEntrant` each
carried their own copy of the exponential utility and the logit denominator.
They now share two internal helpers:

```swift
static func utility(fareRatio:quality:sensitivity:) -> Double   // exp(s × (1 − ratio)) × quality
static func share(offer:others:tuning:) -> Double               // u / (out + u + Σothers)
```

and one for the incumbents' summed utilities. This is what makes "one demand
model" a property of the code rather than a claim in a document: there is now
exactly one place where a market is split.

### 2.2 `DemandSystem.offerQualityTerms` — one implementation, two entry points

The existing `offerQualityTerms(route:state:catalog:)` reads
`dailyRoundTrips` and the first assigned aircraft's cabin off a *flown*
route. It is now a thin wrapper over

```swift
offerQualityTerms(spec:roundTripsPerDay:operationsScore:reputationMultiplier:tuning:)
```

so a pre-flight estimate and the demand engine cannot value the same offer
differently.

### 2.3 `DemandSystem.serviceDemand` — the primitive that did not exist (new)

> Given this airframe, at this frequency, at this fare, against these
> incumbents — how many passengers, in both directions, and how many seats
> are there to put them in?

It is `allocate` asked before the fact: the same pools, the same quality
terms, the same per-segment logit share, both directions, then the seat cap
`FlightOpsSystem` applies. Returns `poolPerDay`, `capturedPerDay`,
`seatsPerDay`, `carriedPerDay`, `loadFactor`.

Pure: reads `state`, mutates nothing, creates no flights, writes no ledger
entries, consumes no RNG.

Validated as *the same* allocation, not an approximation of it:
docs/AE044_AIRFRAME_VALUE_AUDIT.md §4 — 336 day-by-day comparisons, ratio
0.9999–1.0133, and on day 1 (before world drift) 23 of 24 rows inside the
[0, 2) passenger band the engine's own per-direction flooring predicts.

### 2.4 `CompetitorAISystem.airframeDayEstimate` — the entry point both callers use (new)

`airframeDayValue` is unchanged and still public: it is the arithmetic, and
`ae-fee-baseline` and `ae-rival-scan` deliberately feed it *measured*
passenger counts to separate demand error from cost error. What changed is
that nothing in the product calls it with a hand-made passenger figure any
more.

- `CompetitorAISystem.candidateMarkets` (rivals) scores through it.
- `GameState.airframeResult` (player Next Moves, route sheet) prices through it.

## 3. What each caller gained

| | Rival `candidateMarkets` | Player `airframeResult` |
| --- | --- | --- |
| demand varies with the airframe | **new** | **new** |
| demand varies with the frequency priced | **new** | **new** |
| demand covers both directions | **new** (was outbound only) | unchanged — it already did |
| demand is the captured share, not the available pool | **new** | unchanged |
| incumbents in the denominator | unchanged | **new** — it was blind to competition |
| the airline's reputation term | unchanged | **new** |

## 4. What deliberately did not change

Each of these was measured or considered and left alone.

| | Why |
| --- | --- |
| **The rival ranking basis** — airframe-day **revenue** | AE-041 measured four configurations over 150 campaigns and chose it. Untouched, and pinned by a test. |
| **The rival horizon** — 16 | AE-039. Untouched, and pinned by a test. |
| **`minViableDailyDemand` = 140, compared against `poolAvailableToEntrant`** | The floor asks "is this market big enough to be worth entering", which is what `poolAvailableToEntrant` answers, and 140 is calibrated against *that* quantity. Moving the floor to the new captured figure would have re-tuned a balance constant by implication. The floor is unchanged; only the **score** below it is. |
| **Next Moves' ranking** | Still `expectedCapturedPassengers` at `representativeStarterQuality`, divided by `1 + incumbents`. Only the economics under the ranking changed. The brief forbids changing the ranking, and AE-042's curated starts are pinned on it. |
| **`representativeStarterQuality`** | Still the right answer to the question it is asked — what a market is worth before any airframe is chosen. It simply stopped being the input to an airframe comparison. |
| **The fare formula, fee levels, aircraft prices, capacities, ranges** | Out of bounds, and measurement found nothing wrong with them: every flight-scaled line is within 4% of the ledger (value audit §5). |
| **`rotationsPerDay` defaulting to the airframe's maximum** | See §5. |
| **The tourism boost in the estimator's pool** | `allocate` applies the destination region's live event boost; neither caller ever has. Adding it would make rivals chase temporary booms and would change the estimate's level for a reason unrelated to TD-033. Left as a documented approximation. |

## 5. The one judgement call: which service to price

`airframeDayValue` prices the airframe's **maximum** rotations. Production
opens routes at `initialRoundTrips` = 2 (rivals) and at a UI default of 2
(the player). So the estimate describes a busier operation than the one that
is flown on day one.

Measured (value audit §6), against a ledger flown at 2 round trips, the
ordering agreement is 4/12 when the estimate is priced at maximum rotations
and 11/12 when it is priced at two.

**It was still not changed here.** Three reasons:

1. It is not TD-033. The demand term is what AE-043 measured wrong, and
   fixing the demand term is what this phase was asked for.
2. Maximum rotations is defensible and is the *documented* contract: the
   question `employ` asks is what one airframe **day** is worth, and it is
   also where the AI's own frequency loop converges — `manageRoutes` raises
   frequency by one per weekly decision while load stays above 0.82.
3. Changing it moves every rival market ranking at once — long routes gain
   relative to short ones, because at a fixed frequency revenue scales with
   distance while rotations no longer fall with it. That needs its own
   phase, its own rival scan and its own decision, exactly as AE-041 gave
   the ranking basis.

Recorded as **TD-036** with the 4/12-against-11/12 measurement, so the next
phase can act on evidence rather than rediscover it.

## 6. What the fix cannot repair

**Unflown rotations** (value audit §8). The estimator assumes every scheduled
rotation flies; 4–23% do not, driven by schedule slack rather than aircraft
size. It accounts for all four ordering disagreements that remain, every one
of which picks a smaller airframe than the ledger. Modelling it means a
cancellation/cascade model and new constants — a different phase. Recorded as
**TD-035**.

This is the boundary the brief asked to be preserved: the estimator
represents *expected economics*, not a second simulation. It does not
forecast season, weekday, economic drift, world events, fare changes,
competitor moves, or operational disruption after today, and it should not.

## 7. Why this is not a second demand model

The strongest available evidence, in order:

1. `DemandSystem.allocate` and `DemandSystem.serviceDemand` call the *same*
   `utility` and `share` functions and the *same* `offerQualityTerms`. There
   is one split in the codebase.
2. Given a flown route's own inputs, `serviceDemand` reproduces the engine's
   allocation to within the engine's own rounding (value audit §4).
3. `SERVICEDEMAND-05` pins (2) as a test, on four airframes and three
   competitive configurations, against a real day of the real pipeline.
4. `SERVICEDEMAND-10` pins that the player's recommendation and the rival's
   market score are literally the same function's output, so they cannot
   drift apart later.
