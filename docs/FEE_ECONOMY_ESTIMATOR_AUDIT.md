# Estimator versus ledger (AE-040, Phase 2)

> `CompetitorAISystem.airframeDayValue(basis: .profit)` — the AI's
> forecast of what one airframe day keeps on a market, measured in AE-039
> and withheld (TD-030) — against what the ledger actually books for the
> same route, aircraft, fare and frequency. Every number MEASURED with
> `ae-fee-baseline --rotations 2 --months 12` (forty routes, one leased
> airframe each, seed 2039, twelve months averaged, all in the session
> scratchpad as `fee-2-year.csv`); the estimator's lines are its own
> arithmetic on the same inputs.

## 1. Method

For each route the tool reads the ledger's average month and asks the
estimator two questions:

- **with the passengers the month actually carried** (per day), so only
  the cost arithmetic is compared;
- **with the demand engine's own forecast** (`expectedCapturedPassengers`
  on the day after the run), so the demand error can be seen separately.

The booked side is the route's closed month (revenue, fuel, fees, crew)
plus the statement's onboard service and maintenance for the same
airline, which has nothing else. The estimator assumes every rotation
flies; the ledger records what did.

## 2. The comparison, per day, actual passengers (MEASURED)

| Metric (40 routes summed, $/day) | Estimate | Actual | Ratio | Cause |
| --- | ---: | ---: | ---: | --- |
| Revenue | 1,753,430 | 1,753,499 | 1.00 | — (same passengers, same fare) |
| Fuel | 237,027 | 219,540 | 1.08 | timing: 5–10% of scheduled flights do not fly |
| Airport fees | 982,611 | 941,536 | 1.04 | same 5–10% on the movement part; passenger part exact |
| Crew | 117,360 | 109,044 | 1.08 | same |
| Onboard service | 142,195 | 142,200 | 1.00 | — |
| **Maintenance** | **180,458** | **18,411** | **9.8** | **structural mismatch** (§3) |

Per route the pattern is the same: fuel, fees and crew 4–10% high, all
of it the unflown rotations; service and revenue exact; maintenance
eight to twelve times the ledger's. Examples:

| Route | Type | Fuel est / act | Fees est / act | Crew est / act | Maintenance est / act | Flown |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| LHR–CDG | NA70 | 1,844 / 1,740 | 27,203 / 26,057 | 1,830 / 1,727 | 2,521 / 315 | 94% |
| JFK–ORD | NA70 | 6,307 / 5,738 | 27,232 / 25,352 | 4,830 / 4,393 | 6,655 / 628 | 90% |
| JFK–ORD | MR180 | 10,307 / 9,547 | 38,135 / 36,597 | 4,095 / 3,792 | 6,650 / 641 | 92% |
| ARN–LHR | MR180 | 12,695 / 11,719 | 30,968 / 29,750 | 4,836 / 4,468 | 7,853 / 803 | 92% |
| SIN–HND | MR180 | 23,006 / 20,633 | 17,752 / 16,725 | 7,761 / 6,981 | 12,603 / 1,121 | 89% |

The net effect on the estimator's profit: $3,100–$3,600 a day too low
on a 350 km turboprop route, $8,000–$10,000 on a 1,200–1,500 km
narrowbody route, $12,000–$17,000 on long haul — almost all of it the
maintenance line.

## 3. The maintenance mismatch, classified

**Estimator:** `flights × blockHours × spec.maintenancePerFlightHour`
— the type's rate ($620/h for the NA70, $950/h for the MR180) charged
for every hour flown.

**Ledger:** `FleetSystem` charges nothing per hour. Condition falls by
0.0006 a day and 0.00035 per flight hour; when it drops below 0.75 the
aircraft goes for a three-day check that costs 60 hours' worth of the
same rate, times an age factor. At two rotations on a 1,200 km route
(5.4 block hours a day) the condition falls 0.0025 a day, so a check
comes every ~100 days, i.e. every ~540 flight hours, and costs 60 hours
— the ledger's effective rate is **60 / 540 ≈ 11% of the type's rate**.
At three rotations on a 1,462 km route it is ~9.5%.

This is **outcome 5 in the brief's list: two systems using incompatible
definitions**, not rounding, not double counting. The ledger is the
game's truth — it is what the player and every rival pay, and the balance
battery is calibrated on it — so the estimator is the layer that is
wrong *as a predictor of the ledger*. Separately, the ledger's own level
is a tenth of the design anchor's "maintenance reserve ≈ ¤2.4k per
flight" (docs/FEE_ECONOMY_BASELINE.md §6.4); that is a calibration
finding about the whole economy and is recorded as debt, not changed here.

**What it does to the withheld profit ranking:** on JFK–ORD with a
turboprop the estimator charges $200k a month of maintenance the ledger
would book as $19k, so it sees a market that the ledger would call
marginal as a heavy loser. The AE-039 sweep's finding that the regional
archetype has "zero viable candidates" on the profit basis was the sum
of two things: the fee structure (real, in the ledger) and this
overstatement (in the estimator only).

## 4. The demand side (MEASURED, for completeness)

With its own forecast instead of the actual passengers the estimator is
seat-capped on every hub pair (forecasts of 1,000–3,000 a day against 136–
360 seats), so the forecast error only shows on thin pairs: ARN–GOT
forecast 136/day (under the 140 floor) against 249 carried; ARN–HEL 163
against 262; TOS–ARN 20 against 63. The forecast is one day's pool on the
date asked, and the AI asks on its decision day; it is conservative on
thin Nordic pairs and never optimistic in this battery.

## 5. Verdict

| Layer | Verdict |
| --- | --- |
| Ledger fees, fuel, crew, service | correct as specified; the estimator matches them within the unflown-rotation share |
| Ledger maintenance | correct as specified (periodic check); a tenth of the design anchor's level — calibration debt, not a defect of this phase |
| Estimator maintenance | **wrong as a predictor of the ledger**: 9.8× — charges the type's hourly rate the ledger never charges hourly |
| Estimator flight count | approximation: assumes every scheduled rotation flies; 5–10% high on every per-flight cost |
| Estimator demand | conservative on thin pairs, exact on seat-capped ones |

Decision for the fix phase (docs/FEE_ECONOMY_FIX_DECISION.md): the
estimator's maintenance line must be the ledger's own arithmetic ahead
of time — the check cost spread over the flight hours a check lasts —
the same way its fuel and crew lines already are the flight system's.
