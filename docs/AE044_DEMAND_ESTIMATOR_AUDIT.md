# AE-044 §1 — The demand pipeline, read end to end

Phase 1. **READ** unless a line says MEASURED. No production code changed
while this document was written.

Companion to docs/AE043_AIRCRAFT_RECOMMENDATION_AUDIT.md §3, which recorded
the symptom (TD-033) without tracing the mechanism.

---

## 1. The real demand pipeline

The path a passenger takes from a population figure to a ledger line. Every
step is in `AirlineEmpireCore/Sources/AirlineEmpireCore`.

### 1.1 `DemandSystem.update` — daily, once per market

`Systems/DemandSystem.swift:21`

1. Group every **served** route by unordered airport pair.
2. For each pair, **for each of the two directions independently**:
   - `demandPool(from:to:date:economicIndex:tourismBoost:catalog:)` →
     `SegmentDemand(business:leisure:)`. Gravity on √(pop × pop), distance
     attenuation, business/leisure weights, the destination's seasonality
     for the month, weekday factors, the world economic index. **Directional**:
     the leisure term is `origin.leisureIndex × destination.tourismIndex`,
     so ARN→PMI and PMI→ARN are different numbers.
   - `allocate(pool:from:to:routeIDs:)`.

### 1.2 `allocate` — the logit split

`Systems/DemandSystem.swift:55`

For every route on the pair, an attractiveness per segment:

```
u_business(route) = exp(priceSensitivityBusiness × (1 − fare/refFare)) × quality(route)
u_leisure (route) = exp(priceSensitivityLeisure  × (1 − fare/refFare)) × quality(route)
```

and then the share, per segment, against the outside option:

```
served = pool.business × u_b / (outsideOptionWeight + Σ u_b)
       + pool.leisure  × u_l / (outsideOptionWeight + Σ u_l)
```

`Int(served.rounded(.down))` lands on `route.demandOutboundToday` /
`demandInboundToday`, and the same number on `remaining*Today`.

**A route with no assigned aircraft has `quality == nil` and attracts
nothing** — it is not in the denominator either.

### 1.3 `offerQualityTerms` — what "quality" is

`Systems/DemandSystem.swift:118`

```
schedule    = (min(dailyRoundTrips, scheduleQualityTripCap) / scheduleQualityReferenceTrips) ^ scheduleQualityExponent
comfort     = comfortBase    + comfortWeight    × spec.comfortBaseline        // FIRST ASSIGNED AIRCRAFT
operations  = operationsBase + operationsWeight × (completionRate/2 + punctuality/2)
reputation  = airline.reputation.demandMultiplier(...)
quality     = schedule × comfort × operations × reputation
```

Standard tuning: cap 6, reference 4.0, exponent 0.35, comfortBase 0.85,
comfortWeight 0.3, operationsBase 0.7, operationsWeight 0.3,
outsideOptionWeight 1.0, priceSensitivity 1.2 / 2.2.

So **the aircraft enters the demand split twice**: through `comfort`
(its cabin) and through `dailyRoundTrips` (how often it flies — capped
by what one airframe of that type can rotate in a day, §1.4).

A brand-new route has `completionRate == 1.0` and `punctuality == 1.0`
(`Domain/Route.swift:97`), so `operations` starts at 1.0 and decays toward
~0.95 as cancellations and delays accumulate.

### 1.4 `FlightSchedulingSystem.update` — the day's flights

`Systems/FlightSchedulingSystem.swift:13`

```
capacityPerAircraft = roundTripsPerAircraftPerDay(distanceKm, spec, ops)
                    = operatingDayMinutes / (2 × (flightMinutes + turnaroundMinutes))
totalTrips          = min(route.dailyRoundTrips, capacityPerAircraft × usableAircraft)
flights             = 2 × totalTrips                       // one each way
```

`operatingDayMinutes` is 1080. So the frequency the demand engine reads
(`route.dailyRoundTrips`) and the capacity the day actually offers are
linked but not identical: a route set to 6× on an airframe that can only
rotate 3× flies 3.

### 1.5 `FlightOpsSystem` — boarding, and the capacity cap

`Systems/FlightOpsSystem.swift:41`

```
sold = min(spec.seats, max(0, remainingDirectionalDemand))
remaining -= sold
```

Boarding is **per flight, per direction, from the day's remaining
directional demand**. Revenue is posted at departure, `passengers × ticketPrice`.

Cancelled flights (disruption, closed airport, strike, unavailable airframe)
board nobody and their demand is simply not carried that day.

So, for one airframe on one pair:

```
carried/day ≈ Σ_directions min( allocatedDemand(direction), flightsFlown(direction) × seats )
```

### 1.6 Costs and the ledger

`FlightOpsSystem.arrive` posts fuel, movement fees, passenger fees, crew;
`FleetSystem` books maintenance checks; `EconomySystem` books lease,
payroll, overhead. `airframeDayValue`'s `.profit` basis mirrors the first
group plus maintenance and onboard service.

---

## 2. The estimator pipeline

There are **two** callers, and they build the demand input differently.

### 2.1 Rival AI — `CompetitorAISystem.candidateMarkets`

`Systems/CompetitorAISystem.swift:220`

```
entrantQuality = representativeStarterQuality(tuning) × airline.reputation.demandMultiplier
pool           = demandPool(from: origin, to: destination, date, economicIndex)   // ONE DIRECTION
incumbents     = every route on the pair
passengers     = poolAvailableToEntrant(pool, fareRatio: profile.priceFactor,
                                        quality: entrantQuality, incumbents, …)
score          = airframeDayValue(distanceKm:, passengersPerDay: passengers, spec:, …)
```

### 2.2 Player Next Moves — `GameState.airframeResult`

`Session/MarketOpportunities.swift:104` (called from `marketOpportunities`
and `marketCandidates`)

```
quality  = representativeStarterQuality(tuning)                       // no reputation term
outbound = expectedCapturedPassengers(demandPool(o→d), fareRatio: 1, quality)
inbound  = expectedCapturedPassengers(demandPool(d→o), fareRatio: 1, quality)
pool     = outbound + inbound                                          // BOTH DIRECTIONS
for spec in candidateSpecs:
    perDay = airframeDayValue(distanceKm:, passengersPerDay: pool, spec:, basis: .profit)
    monthly = perDay × 30 − spec.leaseMonthly − payroll
best = argmax(monthly)
```

`pool` is computed **once per market** and reused for **every** candidate
airframe. That is the loop TD-033 is about.

### 2.3 `airframeDayValue` itself

`Systems/CompetitorAISystem.swift:322`

```
rotations = rotationsPerDay ?? roundTripsPerAircraftPerDay(distanceKm, spec, ops)   // the MAXIMUM
flights   = rotations × 2
carried   = min(passengersPerDay, flights × spec.seats)
revenue   = carried × referenceFare(distanceKm) × fareRatio
.profit  → revenue − fuel − movementFees − passengerFees − crew − maintenance − service
```

The arithmetic below `carried` was reconciled against the ledger in AE-040
and re-validated in AE-042. It is not in question here.

### 2.4 `representativeStarterQuality`

`Systems/DemandSystem.swift:210`

```
schedule   = (2.0 / 4.0) ^ 0.35 = 0.7846      // TWO round trips, always
comfort    = 0.85 + 0.3 × 0.55  = 1.0150      // a mid-comfort cabin, always
operations = 0.7  + 0.3 × 0.8   = 0.9400      // "as-yet-unproven", always
                                 = 0.7486
```

**Not one of the three terms depends on the airframe being priced.**

---

## 3. Shared primitives

| Primitive | Simulation | Estimator |
| --- | :---: | :---: |
| `demandPool` | ✔ | ✔ |
| `referenceFare` | ✔ (route fare set against it) | ✔ |
| exponential price utility | ✔ `allocate` | ✔ inside `expectedCapturedPassengers` / `poolAvailableToEntrant` |
| outside option in the denominator | ✔ | ✔ |
| offer quality = schedule × comfort × ops × reputation | ✔ `offerQualityTerms` | ✖ **`representativeStarterQuality`, a constant** |
| incumbent utilities in the denominator | ✔ | rival path ✔ / player path ✖ |
| `roundTripsPerAircraftPerDay` | ✔ scheduler | ✔ capacity + cost terms |
| per-flight seat cap | ✔ `FlightOpsSystem` | ✔ `min(pax, flights × seats)` |
| both directions | ✔ | player path ✔ / rival path ✖ |
| fuel / fee / crew / maintenance / service rates | ✔ | ✔ (AE-040) |

So the economy is shared. **The demand allocation is not.**

---

## 4. Divergence points

Numbered so §6 and docs/AE044_ROOT_CAUSE.md can refer to them.

### D1 — Offer quality is a constant, not the service being priced

The simulation's share depends on `schedule(dailyRoundTrips)` and
`comfort(spec)`. The estimator uses `representativeStarterQuality` — 2
round trips and a 0.55 cabin — **for every airframe on every market**.

Consequence: two airframes on the same pair receive **the same**
`passengersPerDay`. Their estimated revenue can then differ only through
the `min(pax, flights × seats)` cap, and once an airframe is big enough to
clear that cap, every larger airframe earns *exactly the same revenue* and
pays *strictly more* fuel, fees, crew and maintenance. **The estimator is
monotonically biased toward the smallest airframe that clears the cap.**

### D2 — The demand is priced at 2 rotations, the capacity and costs at the maximum

Inside one call: `passengersPerDay` describes a 2×/day service
(`representativeStarterQuality`), while `rotations`, `flights`, `carried`,
fuel, fees, crew and maintenance all describe a service flying
`roundTripsPerAircraftPerDay` — 3× to 6× on the short pairs where the
recommendation lives. The two halves of one estimate describe **different
operations**.

### D3 — The rival path passes one direction's pool for a two-directional day

`candidateMarkets` computes `demandPool(from: origin, to: destination)` —
outbound only — and hands it to a formula whose `flights = rotations × 2`
covers both directions.

### D4 — The rival path passes *available pool*, not *captured passengers*

`poolAvailableToEntrant` returns, by its own documented contract, the pool
in **pool units** — `pool × (out + e) / (out + e + Σ rivals)` — so that an
empty pair returns the *whole* pool. The share an offer actually wins is
`pool × e / (out + e + Σ rivals)`. At the standard tuning the two differ by
`(out + e)/e = 1 + 1/0.7486 = 2.34×`.

D3 and D4 partially cancel (÷2 against ×2.34), which is why the rival AI
has looked approximately right: net ≈ **+17%** on an uncapped airframe.
They cancel by accident, not by construction, and not at all on an airframe
where the cap binds.

### D5 — The player path ignores incumbents entirely

`airframeResult` calls `expectedCapturedPassengers` with no rival term, so
a pair with three carriers is priced as an empty one. (`MarketOpportunity`
carries an `incumbents` count for display, and `marketOpportunities`
divides its *ranking* score by `1 + incumbents`, but the **economics**
handed to the player are computed as though the market were empty.)

### D6 — The estimator's own reputation term is inconsistent

The rival path multiplies `representativeStarterQuality` by the airline's
reputation multiplier; the player path does not.

### D7 — `expectedCapturedPassengers` and `poolAvailableToEntrant` cannot be composed

They are the two halves of one expression, but both collapse the
business/leisure segments to a single `Double`, so
`expectedCapturedPassengers(pool: poolAvailableToEntrant(...))` is only
approximately the logit share with incumbents; it is exact only when the
two segments happen to share a fare ratio *and* the rival mix is identical
in both. There is no existing primitive that gives an entrant's captured
passengers **with incumbents** exactly.

---

## 5. Current assumptions the estimator makes

Stated so §8 (approximation boundaries) can say which are deliberate.

| # | Assumption | Deliberate? |
| --- | --- | --- |
| A1 | Every scheduled rotation flies (no cancellations, no delay cascade) | Yes — recorded on TD-033/AE-040 |
| A2 | The airframe flies its maximum rotations | Yes — `airframeDayValue` answers "what is an airframe *day* worth" |
| A3 | Today's pool stands for every day (no seasonality path, no economic drift) | Yes |
| A4 | The fare is the reference fare × `fareRatio`, forever | Yes |
| A5 | Incumbents keep today's fares and schedules | Yes |
| A6 | Demand does not respond to the aircraft (D1) | **No — this is TD-033** |
| A7 | Demand does not respond to the frequency (D1/D2) | **No** |
| A8 | Demand covers one direction while capacity covers two (D3) | **No** |
| A9 | Available pool ≡ captured passengers (D4) | **No** |
| A10 | The player faces no competition (D5) | **No** |

---

## 6. Known approximation errors

MEASURED. `ae-fee-baseline --pairs HAM-LHR --types KT95,PA184 --seed 2030`,
one measured month (February) of real flying, route opened at the airframe's
maximum rotations:

| Airframe | Seats | Rotations | Estimator forecast pax/day | Ledger pax/day | Error | Estimator profit/day | Ledger profit/day |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| KT95 | 95 | 4 | 865 | 736 | **−15%** | 17,009 | 17,414 |
| PA184 | 184 | 4 | 877 | 1,298 | **+48%** | **6,596** | **37,402** |

Note the forecast is *nearly identical* for the two airframes (865 vs 877 —
the whole difference is the 0.50 vs 0.58 cabin, and only because
`ae-fee-baseline` reads the flown route's quality; the shipped callers use
the constant and would give both **exactly** the same figure). The ledger
differs by 76%.

This reproduces TD-033 §2 and AE-043 §3 in one command.

---

## 7. Candidate reuse path

The engine already contains every term. What is missing is one function that
assembles them for a *hypothetical* service instead of a flown one.

1. **Extract the segment share.** `allocate`, `expectedCapturedPassengers`
   and `poolAvailableToEntrant` all compute
   `u / (outsideOption + u + Σ rivals)` with the same exponential utility.
   One private helper, three call sites, no behaviour change — this is what
   makes "one demand model" checkable rather than asserted.

2. **Extract offer quality for a hypothetical offer.**
   `offerQualityTerms(route:state:catalog:)` reads `dailyRoundTrips` and the
   first assigned aircraft's `comfortBaseline` off a flown route. The same
   four terms computed from `(spec, roundTripsPerDay, operations,
   reputation)` answer the estimator's question, and `offerQualityTerms`
   can then be a thin wrapper over it — so the two can never drift.

3. **Add the one primitive that does not exist (D7):** an entrant's
   captured passengers **with** incumbents, per segment, over **both**
   directions, for a **named airframe at a named frequency**.

4. **Have `airframeDayValue` derive its passengers from (3) at the same
   rotation count it prices capacity and costs at**, closing D1, D2, D3, D4,
   D5 and D6 together, because they are all the same mistake: the demand
   term and the capacity term describing different operations.

`representativeStarterQuality` stays — it is the right answer to a question
that is still asked (what a market is worth before any airframe is chosen,
which is what `marketOpportunities` *ranks* on) — but it stops being the
input to an airframe comparison.

---

## 8. What this document does not claim

- It does not claim the fee, fuel, crew, maintenance or service arithmetic
  is wrong. AE-040 reconciled it and AE-042 re-validated it; §6 shows the
  estimator landing within 3% of the ledger on KT95, where the cap binds and
  the demand error cannot express itself.
- It does not claim a size of fix. The batteries in Phases 2–5 decide that.
- It does not classify the root cause. That is docs/AE044_ROOT_CAUSE.md,
  after the measurements exist.
