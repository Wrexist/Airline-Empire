# AE-044 §2 — `airframeDayValue` against the ledger

Phases 2–5. Everything here is **MEASURED** through `ae-demand`, a new
executable that holds a market, a fare, a day, a seed and the world constant,
varies exactly one thing, flies the result through the real pipeline with the
competitor system removed, and reads February back from the route's own closed
month. Estimates are taken on day 0, before anything flies — the moment the
decision is actually made.

`ae-demand` changes no product behaviour. Its "corrected" column is a
hypothesis built only from the demand engine's public primitives, measured
here *before* anything in Core changed (Phase 9 then moves the validated
version into Core and the tool delegates to it).

Reproduce: `swift run -c release ae-demand <mode> --pairs … --types … --seed 2030`.

---

## 1. Phase 2 — offered capacity

One market, seven airframes from 68 to 184 seats, each flown at its own
maximum rotations. Seed 2030, February, no incumbents.

Hamburg–London, 745 km:

| Airframe | Seats | Rot | Shipped est. pax | Corrected est. pax | Ledger pax | Ledger load |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| NA70 | 68 | 3 | 1,105 | 1,170 | 398 | 100% |
| KT72 | 74 | 3 | 1,105 | 1,162 | 410 | 100% |
| AV90 | 88 | 4 | 1,105 | 1,254 | 688 | 100% |
| KT95 | 95 | 4 | 1,105 | 1,250 | 736 | 100% |
| NA160 | 162 | 4 | 1,105 | 1,256 | 1,195 | 96% |
| MR180 | 180 | 4 | 1,105 | 1,260 | 1,284 | 91% |
| PA184 | 184 | 4 | 1,105 | 1,266 | 1,298 | 91% |

**The shipped column is a constant.** That is D1 in one line: the airframe
does not appear in the demand estimate at all. The ledger is not a constant —
it rises with the seats offered, and it does so through *two* engine terms
(the aircraft's cabin in `offerQualityTerms`, and the per-flight seat cap in
`FlightOpsSystem`), not one.

**The relationship is not linear.** 68 → 184 seats is ×2.7; carried passengers
go ×3.3 (398 → 1,298) because the small airframes are capacity-bound and the
large ones are demand-bound. Above ~160 seats the curve flattens hard: 162 →
184 seats (+14%) buys +9% passengers. Doubling seats does **not** double
passengers, and no fix should assume it does.

## 2. Phase 3 — frequency

One market, one airframe, every valid frequency. Hamburg–London, KT95:

| Round trips | Scheduled flights/mo | Flown | Cancelled | Shipped est. pax | Corrected est. pax | Ledger pax |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 56 | 56 | 0 | 1,105 | 946 | 190 |
| 2 | 112 | 112 | 0 | 1,105 | 1,095 | 380 |
| 3 | 168 | 164 | 4 | 1,105 | 1,186 | 556 |
| 4 | 224 | 217 | 7 | 1,105 | 1,250 | 736 |

The shipped estimate does not move with frequency either. The corrected one
rises as `(trips / 4) ^ 0.35` — the engine's own `scheduleQualityExponent`,
not a curve invented here.

**The answer to the Phase 3 question** ("does the estimator need capacity per
day, or capacity per rotation + frequency?") is: **frequency, in the
simulation's own term `dailyRoundTrips`**, because frequency enters demand
through `offerQualityTerms.schedule` *and* capacity through
`roundTripsPerAircraftPerDay`. One number cannot carry both.

## 3. Phase 4 — competition

Hamburg–London, one airframe at its maximum rotations, against 0–3 identical
KT95 incumbents at the reference fare:

| Airframe | Incumbents | Shipped est. profit/day | Corrected est. profit/day | Ledger profit/day |
| --- | ---: | ---: | ---: | ---: |
| KT95 | 0 | 17,042 | 17,042 | 17,415 |
| KT95 | 1 | **17,042** | 17,042 | 17,124 |
| KT95 | 2 | **17,042** | 10,955 | 13,567 |
| KT95 | 3 | **17,042** | 2,395 | 7,197 |
| PA184 | 0 | 22,065 | 32,978 | 37,403 |
| PA184 | 1 | **22,065** | 7,263 | 14,495 |
| PA184 | 2 | **22,065** | −6,596 | 74 |
| PA184 | 3 | **22,065** | −15,263 | −9,439 |

The shipped **player** estimate is *literally the same number* whether the
pair is empty or has three carriers on it, while the ledger falls from
+$37,403 to −$9,439 a day. That is D5. (The rival path is not blind — it uses
`poolAvailableToEntrant` — which is why this has never shown up in a rival
battery.)

The corrected estimate tracks the fall and gets the sign right on 15 of 16
rows; the one miss is PA184 with two incumbents, where it says −6,596 and the
ledger says +74 — a route at break-even called marginally negative.

## 4. Phase 5 — is the corrected demand the *same* allocation the engine runs?

The strongest test available, and it does not need a ledger. `ae-demand
verify` opens a route, advances a day at a time, and compares the demand the
engine allocated that morning (`route.demandOutboundToday +
demandInboundToday`) with `DemandSystem.serviceDemand` evaluated for that same
date, at the route's own frequency, operations record and reputation, against
the same incumbents.

3 pairs × 3 airframes × {0, 1, 2 incumbents} × 14 days — **336 comparisons**:

| | estimate ÷ engine |
| --- | --- |
| minimum | 0.9999 |
| maximum | 1.0133 |

Two things account for the whole residual, and neither is a modelling
difference:

1. **The engine floors each direction** (`Int(served.rounded(.down))`), so it
   is between 0 and 2 passengers below the exact figure by construction.
2. **The reading is taken a day after the allocation.** The estimate is
   computed from the state at the end of the day the engine allocated at the
   start of, so it sees a day of `WorldSystem` drift in `economicIndex` and a
   day of change in the route's own completion and punctuality.

Isolating (2) by looking only at day 1 — before anything has flown, when
every route's operations record is the untouched 1.0 and the world has not
drifted — **23 of 24 rows fall inside the [0, 2) passenger band that
floor-rounding predicts**, and the 24th is 0.2 passengers below it.

This is the property the phase was asked for: the corrected estimator is not
an approximation of the allocation, it **is** the allocation, evaluated for a
service that has not been flown yet.

## 5. Phase 5 — the estimator's lines against the ledger

`airframeDayValue`'s `.profit` basis line by line against the ledger's own,
one airframe day, Hamburg–London on PA184 at 4 round trips — the row where the
shipped estimator is most wrong. `ae-demand lines --pairs HAM-LHR --types
PA184 --seed 2030`, dollars per day, February.

| Line | Shipped | Corrected | Ledger | Shipped err | Corrected err | Class |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| passengers | 1,105 | 1,266 | 1,298 | **−15%** | **−2%** | **demand** |
| revenue | 108,616 | 124,436 | 127,587 | −15% | −2% | demand |
| passenger fees | 23,750 | 27,210 | 28,530 | −17% | −5% | demand |
| service | 9,942 | 11,390 | 11,678 | −15% | −2% | demand |
| movement fees | 32,711 | 32,711 | 31,543 | +4% | +4% | timing |
| fuel | 13,429 | 13,429 | 12,943 | +4% | +4% | timing |
| crew | 5,694 | 5,694 | 5,491 | +4% | +4% | timing |
| maintenance | 894 | 894 | 0 | — | — | timing † |
| **profit** | **22,065** | **32,978** | **37,403** | **−41%** | **−12%** | |

Read down the table and the shape is unmistakable:

- **Every line that scales with passengers is wrong by exactly the demand
  error** — −15 to −17% shipped, −2 to −5% corrected. The passenger fee is a
  *cost* line and it is wrong for a *demand* reason: a route carrying 1,298
  passengers pays fees on 1,298, and the shipped estimate budgeted for 1,105.
  AE-040 reconciled the fee **rates** and they are not in question.
- **Every line that scales with flights is +4%, both before and after** —
  8 flights scheduled against 7.71 flown. That is §8's unflown rotations, and
  the demand fix neither causes nor cures it.
- Nothing anywhere is wrong for a rate reason.

**The first divergence is passengers.** † The fleet system's first
maintenance check falls outside a two-month window; AE-040 recorded the same
and it is unchanged here.

## 6. Phase 5 — ordering against the ledger

The product does not rank airframes on the day value; it ranks them on
`perDay × 30 − leaseMonthly − payroll` (`GameState.airframeResult`). This
table uses that measure. Twelve markets — the seven AE-043 comparison homes,
the four where the market's first row cannot fly the route, and the JFK–ORD
control — × seven era-legal airframes, each flown for a month.

Three configurations, because the answer depends on which service is being
priced:

| Configuration | Shipped agrees with ledger | Corrected agrees with ledger |
| --- | :---: | :---: |
| route flown at 2 round trips, estimate priced at maximum rotations — **what production does today** | 4/12 | 4/12 |
| route flown at 2, estimate priced at 2 | 11/12 | 11/12 |
| route flown at maximum rotations, estimate priced at maximum — **self-consistent** | 4/12 | **8/12** |

Three things follow, and they matter more than the headline:

1. **Correcting the demand term doubles ordering agreement (4/12 → 8/12)
   — but only when the estimate and the operation describe the same
   service.** In production's own configuration it changes nothing, because
   the estimate is priced for an operation the game does not fly.

2. **When every airframe is capacity-bound, the demand term is irrelevant.**
   At 2 round trips on these markets the seat cap binds for all seven
   airframes, so both estimators reduce to `capacity × fare − costs` and both
   are right 11/12. The demand term only decides anything once an airframe is
   large enough, or a market thin enough, that demand binds first — which is
   exactly the aircraft-comparison case BUG-056 is about.

3. **The right airframe genuinely depends on the frequency.** At 2 round trips
   the ledger's best airframe on Dublin–Paris is MR180; at maximum rotations
   it is NA160. That is not estimator error, it is the economy: at low
   frequency revenue scales with seats and the cheapest lease per seat wins;
   at high frequency demand binds and the cabin that fills wins.

## 7. Phase 14 — the bias table

Estimated carried passengers and estimated profit against the ledger, by
airframe class, over the 70 flown route-airframe combinations of §6
(self-consistent configuration). Positive = the estimator is too high.

| Airframe class | n | Old demand bias | New demand bias | Old value bias | New value bias |
| --- | ---: | ---: | ---: | ---: | ---: |
| small (68–95 seats) | 46 | **+12.8%** | +14.8% | +10.7% | +16.4% |
| mid (162–184 seats) | 24 | **−8.8%** | **−1.7%** | **−45.8%** | **−26.3%** |
| spread between classes | | **21.6 pts** | **16.5 pts** | **56.5 pts** | **42.7 pts** |

Read carefully:

- **The mid-class demand bias is essentially eliminated: −8.8% → −1.7%.**
  That is the whole of TD-033's mechanism, and it is gone.
- **The small-class bias is not a demand bias and the fix does not touch it.**
  It is entirely §8's unflown rotations: on 46 small-airframe rows the
  correlation between the residual and the route's flown-flight completion
  rate is the whole story — at 96–100% completion the residual is +0% to +5%,
  at 77–85% completion it is +20% to +45%.
- The corrected small-class bias is *larger* than the shipped one (+12.8 →
  +14.8) for a specific and non-alarming reason: raising the demand estimate
  moves six rows from demand-bound to capacity-bound, and capacity-bound rows
  are the ones §8's approximation over-reads. The fix did not make the
  estimator worse on those routes; it removed a compensating error that was
  masking a different one.
- The **value** bias is larger than the demand bias on every row because
  profit is a small difference of large numbers: on a 10% margin a −2%
  revenue error is a −25% profit error. That is leverage, not a second defect.

## 8. What is left, measured

`airframeDayValue` assumes every scheduled rotation flies. It does not. The
flown-flight completion rate over the 70 combinations:

| Rotations flown | Median completion | Range |
| ---: | ---: | --- |
| 2 | 97% | 92–100% |
| 3 | 94% | 77–98% |
| 4 | 87% | 81–98% |
| 5 | 84% | 78–94% |

The driver is **schedule slack, not aircraft size**: `roundTripsPerAircraft
PerDay` packs rotations into the 1,080-minute operating day, and a 45–240
minute delay on a schedule with 24 minutes of slack expires the next flight
(`scheduledFlightExpiryMinutes` 240). Gothenburg–London on a KT95 fits four
264-minute rotations into 1,080 minutes — 24 minutes of slack — and completes
81%; the same airframe on Hamburg–London has 208 minutes of slack and
completes 97%.

Because a larger cabin carries a longer turnaround, large airframes get fewer
rotations and therefore *more* slack, so this residual reads as a pro-small
bias in the estimator. It is pre-existing, it is present in the shipped
estimator too, and it accounts for all four of the ordering disagreements
that remain in §6 — every one of which picks a smaller airframe than the
ledger.

It is **not** in AE-044's scope: it is a schedule-realism model, not a demand
model, and building one means new constants. It is recorded as **TD-035**
with this measurement.

## 9. Classification of every discrepancy found

| Discrepancy | Class | Fixed here? |
| --- | --- | :---: |
| Demand does not vary with the airframe's cabin | demand | ✔ |
| Demand does not vary with the frequency offered | frequency | ✔ |
| Player path ignores incumbents entirely | competition | ✔ |
| Rival path passes one direction's pool for a two-directional day | demand | ✔ |
| Rival path passes *available pool* where *captured share* is meant | demand | ✔ |
| Player path omits the reputation term the rival path applies | demand | ✔ |
| Estimate priced at maximum rotations, route opened at two | frequency | ✖ — §6.3; recorded, not changed |
| Scheduled rotations that never fly | timing | ✖ — §8, TD-035 |
| Day-0 pool stands for the whole month (season, weekday, economy) | timing | ✖ — deliberate, ±13% on KEF–LHR |
| First maintenance check falls outside a two-month window | timing | ✖ — AE-040, unchanged |
| `Int(rounded(.down))` per direction | rounding | ✖ — 0.1–0.4%, harmless |
| Fee, fuel, crew rates | — | none found; ≤4% on every row |
