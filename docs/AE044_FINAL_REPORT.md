# AE-044 FINAL REPORT — THE DEMAND THE AIRCRAFT ACTUALLY SELLS

2026-09-04. Fixing TD-033: make `airframeDayValue` respond to the capacity
and service offered.

Companion documents, in the order they were written:
docs/AE044_DEMAND_ESTIMATOR_AUDIT.md (Phase 1, READ),
docs/AE044_AIRFRAME_VALUE_AUDIT.md (Phases 2–5 and 14, MEASURED),
docs/AE044_ROOT_CAUSE.md (Phase 6),
docs/AE044_ESTIMATOR_DECISION.md (Phases 7–9).

---

## 1. Executive summary

- **Was TD-033 real?** **Yes**, and larger than recorded. Reproduced in one
  command on the first attempt.
- **Exact root cause?** **CASE G.** `CompetitorAISystem.airframeDayValue`
  took `passengersPerDay` as a **caller-supplied constant** while computing
  capacity, revenue and every cost from the **airframe**. Past the seat cap
  every airframe therefore earned identical revenue and paid a larger
  cabin's costs, so the estimator was structurally certain that a bigger
  cabin is worse. Five separate divergences, all of them that one mistake.
- **Was a fix shipped?** **Yes.** One authoritative demand allocation —
  `DemandSystem.serviceDemand` — asked the estimator's question, used by the
  player's Next Moves and the rivals' market choice through one shared entry
  point, `CompetitorAISystem.airframeDayEstimate`.
- **Did aircraft-specific demand prediction improve?** **Yes, decisively.**
  The demand bias on 162–184-seat airframes went from **−8.3% to −0.0%**;
  airframe ordering agreement with the ledger went **4/13 → 8/13**; and the
  derived figure is now the engine's *own* allocation to within its own
  rounding (±2 passengers on ~500).
- **Is BUG-056 closed?** **No — PARTIALLY FIXED, and re-blocked.** The
  estimator can now rank airframes, but on the configuration production
  actually flies it still does not, because of a **second** mismatch this
  phase found and did not fix: the estimate prices the airframe's maximum
  rotations while every caller opens routes at two (**TD-036**).

**One thing did not come free.** `BalanceTests.archetypeParityAndSanity`
now fails: the archetype net-worth spread is 6.044 against a `< 6.0` guard
(baseline 5.772). The guard is not weakened here and the failure is not
hidden — §10 and §13 have the measurement, and §18 recommends what to do
about it. The full suite is **469 tests, 1 failure** on a quiet container:
that one.

## 2. Baseline

MEASURED. `ae-demand`, a new executable written for this phase: it holds a
market, a fare, a day, a seed and the world constant, varies one thing, flies
the result through the real pipeline with the competitor system removed, and
reads February back from the route's closed month. Estimates are taken on
day 0, before anything flies.

Hamburg–London, 745 km, each airframe at its own maximum rotations:

| Airframe | Seats | Rot | Est. pax (old) | Est. pax (new) | Actual pax | Est. value/day (old) | (new) | Actual value/day | Old error | New error |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| NA70 | 68 | 3 | 1,105 | 1,170 | 398 | 7,088 | 7,088 | 7,622 | −7% | −7% |
| KT72 | 74 | 3 | 1,105 | 1,162 | 410 | 8,258 | 8,258 | 8,328 | −1% | −1% |
| AV90 | 88 | 4 | 1,105 | 1,254 | 688 | 15,421 | 15,421 | 15,946 | −3% | −3% |
| KT95 | 95 | 4 | 1,105 | 1,250 | 736 | 17,042 | 17,042 | 17,415 | −2% | −2% |
| NA160 | 162 | 4 | 1,105 | 1,256 | 1,195 | 27,717 | 37,985 | 36,424 | **−24%** | **+4%** |
| MR180 | 180 | 4 | 1,105 | 1,260 | 1,284 | 23,338 | 33,865 | 37,034 | **−37%** | **−9%** |
| PA184 | 184 | 4 | 1,105 | 1,266 | 1,298 | 22,065 | 32,978 | 37,403 | **−41%** | **−12%** |

**The old estimate's passenger column is a constant.** That is TD-033 in one
column: seven airframes from 68 to 184 seats, one number. The ledger's is
not: it runs 398 → 1,298, because the aircraft enters the engine's demand
split twice (its cabin, and the frequency it can fly) and the boarding step
a third time (the per-flight seat cap).

The relationship is **not** linear — 2.7× the seats buys 3.3× the
passengers on this pair because the small airframes are capacity-bound and
the large ones demand-bound, and above ~160 seats it flattens hard (162 →
184 seats, +14%, buys +9% passengers). No fix assumes proportionality; the
test suite pins that it must not (SERVICEDEMAND-02).

## 3. Demand model audit

Full trace in docs/AE044_DEMAND_ESTIMATOR_AUDIT.md.

**Real path.** `demandPool` per direction → `allocate` splits it per segment
by `u / (outsideOption + Σu)` where `u = exp(sensitivity × (1 − fare/ref)) ×
quality` and `quality = schedule(dailyRoundTrips) × comfort(spec) ×
operations × reputation` → `FlightSchedulingSystem` materialises
`min(dailyRoundTrips, rotationsPerAircraft × aircraft)` round trips →
`FlightOpsSystem` boards `min(seats, remaining directional demand)` per
flight → ledger.

**Estimator path (before).** Rival: one direction's `demandPool` →
`poolAvailableToEntrant` at a constant `representativeStarterQuality` →
`airframeDayValue`. Player: both directions' `expectedCapturedPassengers` at
the same constant, **no incumbents** → `airframeDayValue`.

**Shared primitives.** `demandPool`, `referenceFare`, the exponential price
utility, the outside option, `roundTripsPerAircraftPerDay`, the seat cap,
and every fee/fuel/crew/maintenance rate. **Not shared: the offer quality
and the incumbent term** — the two things that make demand depend on the
aircraft.

**Divergences** (audit §4): D1 quality is a constant, not the service being
priced · D2 demand priced at 2 rotations, capacity and costs at the maximum
· D3 rival path passes one direction's pool for a two-directional day · D4
rival path passes *available pool* where *captured share* is meant (a factor
of 2.34 per direction, accidentally half-cancelled by D3) · D5 player path
ignores incumbents entirely · D6 player path omits the reputation term the
rival path applies · D7 no existing primitive gives an entrant's captured
passengers with incumbents.

## 4. Root cause

**CASE G — multiple factors, all of them the same mistake.** Cases A, B, C
(player path), D (twice) and E (rival path) all hold with evidence; F holds
but is a separate, pre-existing error that does not produce the size bias.
Full table and evidence: docs/AE044_ROOT_CAUSE.md §1.

The mechanism, stated once: with `passengersPerDay` fixed across airframes
and `carried = min(passengersPerDay, flights × seats)`, every airframe past
the crossover receives **identical revenue** and pays **strictly more** fuel,
fees, crew, maintenance and service. The estimator's preference is
monotonically decreasing in seats. That is a proof, not a correlation, and
it matches the sign of every AE-043 row.

Ruled out by measurement, so untouched: fee/fuel/crew/maintenance rates
(every flight-scaled line within 4% of the ledger), the fare formula,
`airframeDayValue`'s arithmetic below `carried`, and the demand engine
itself.

## 5. Fix decision

Full design: docs/AE044_ESTIMATOR_DECISION.md.

**Changed.** (1) `DemandSystem` now has one segment-share expression —
`utility` and `share` — used by `allocate`, `expectedCapturedPassengers`,
`poolAvailableToEntrant` and the new primitive, so "one demand model" is a
property of the code. (2) `offerQualityTerms` gained a spec-and-frequency
entry point and the route-based one is now a wrapper over it. (3)
**`DemandSystem.serviceDemand`** — new: what one airframe at one frequency
at one fare against these incumbents would capture, both directions, and the
seats to put them in. (4) **`CompetitorAISystem.airframeDayEstimate`** —
new: derives the passengers and then calls the unchanged
`airframeDayValue` at the **same** rotation count. Both production callers
go through it.

**Not changed.** The rival ranking basis (revenue) · the horizon (16) ·
`minViableDailyDemand` = 140 and the `poolAvailableToEntrant` quantity it
gates on · Next Moves' ranking · `representativeStarterQuality` · the fare
formula, fee levels, aircraft prices, capacities, ranges · the estimator's
maximum-rotation assumption (§13, TD-036) · the tourism boost.

**Kept pure.** `serviceDemand` and `airframeDayEstimate` read state, mutate
nothing, create no flights, write no ledger entries and consume no RNG
(SERVICEDEMAND-09 pins it).

## 6. Before / after

MEASURED over 77 route-airframe combinations, each flown for a month
(13 markets × up to 7 era airframes), estimate and operation both at the
airframe's maximum rotations.

| | Old | New |
| --- | ---: | ---: |
| passenger prediction bias, 162–184 seats | −8.3% | **−0.0%** |
| passenger prediction bias, 68–95 seats | +13.7% | +15.5% |
| **aircraft-size bias (spread between the two classes)** | **22.0 pts** | **15.5 pts** |
| value bias, 162–184 seats | −46.6% | −24.0% |
| value bias, 68–95 seats | +11.6% | +16.8% |
| value bias spread | 58.2 pts | 40.8 pts |
| **airframe ranking agreement with the ledger** | **4/13** | **8/13** |
| dangerous first recommendations, 93 homes, aircraft market's default sort | 9 | **7** |
| dangerous first recommendations, 93 homes, cheapest-airframe rule | 6 | 7 |
| dangerous first recommendations, 93 homes, best-airframe rule | 0 | 0 |

**The systematic aircraft-size bias in the demand term is gone** — that was
the phase's stated target and it is met exactly (−8.3% → −0.0%).

**What is left is not a demand bias.** The 68–95-seat class is over-read by
15.5% because `airframeDayValue` assumes every scheduled rotation flies and
4–23% do not, driven by **schedule slack, not aircraft size**: at 96–100%
flown-flight completion the residual is +0% to +5%; at 77–85% it is +20% to
+45%. Correcting the demand moved six rows from demand-bound to
capacity-bound and so exposed more of it. Measured and recorded as
**TD-035**; the brief lists partial rotations and random operational events
as legitimate approximations.

**The estimator is now the engine's allocation, not an approximation of
it.** 336 day-by-day comparisons against `DemandSystem.allocate` on live
routes: ratio 0.9999–1.0133, and on day 1 (before world drift) 23 of 24 rows
inside the [0, 2) passenger band the engine's own per-direction flooring
predicts. Pinned by SERVICEDEMAND-05.

## 7. AE-043 regression

The seven homes where both candidate aircraft can fly the route, plus the
four where the market's first row cannot, plus MAN (newly flagged) and the
JFK–ORD control. Ranked the way the product ranks airframes — a month less
the airframe's lease and payroll — with each airframe flown for a month.

| Home | Old estimator's pick | New estimator's pick | Ledger's best | Old | New |
| --- | --- | --- | --- | :---: | :---: |
| FRA–LHR | NA160 | **MR180** | MR180 | ✗ | **✓** |
| HAM–LHR | KT95 | **NA160** | NA160 | ✗ | **✓** |
| DUB–CDG | KT95 | KT95 | NA160 | ✗ | ✗ |
| EDI–CDG | AV90 | **KT95** | KT95 | ✗ | **✓** |
| GOT–LHR | AV90 | KT95 | MR180 | ✗ | ✗ |
| PMI–LHR | KT72 | KT72 | AV90 | ✗ | ✗ |
| KEF–LHR | AV90 | AV90 | AV90 | ✓ | ✓ |
| BLL–LHR | KT72 | KT72 | KT72 | ✓ | ✓ |
| NCE–LHR | AV90 | **KT95** | KT95 | ✗ | **✓** |
| BGO–LHR | KT72 | KT72 | AV90 | ✗ | ✗ |
| VCE–LHR | KT95 | KT95 | KT95 | ✓ | ✓ |
| MAN–CDG | KT95 | NA160 | MR180 | ✗ | ✗ |
| JFK–ORD (control) | MR180 | MR180 | MR180 | ✓ | ✓ |
| **agreement** | | | | **4/13** | **8/13** |

All five remaining disagreements pick a **smaller** airframe than the ledger
pays best on — the signature of TD-035, not of TD-033.

**The AE-043 examples specifically.** Hamburg: the old estimator named a
95-seat KT95 and the ledger's best is a 162-seat NA160; the new estimator
names NA160. Dublin: old KT95, ledger NA160, new KT95 — still wrong, but by
one size class rather than by inverting the question. The AE-043 table only
ever compared the market's PA184 against the advice's KT95 and never priced
the NA160 that actually wins both pairs.

## 8. AE-042 regression

`ae-advice sweep --homes all --seed 2030`, 93 homes, three acquisition rules,
baseline against after. The verdict classes are AE-042's, unchanged.

| Acquisition rule | | SAFE | VIABLE | MARGINAL | DANGEROUS | UNFLYABLE |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| biggest (the aircraft market's own default sort) | before | 8 | 58 | 17 | **9** | 1 |
| | after | 8 | 60 | 17 | **7** | 1 |
| cheapest (the trusting player) | before | 8 | 44 | 34 | **6** | 1 |
| | after | 8 | 43 | 34 | **7** | 1 |
| best | before | 8 | 70 | 14 | **0** | 1 |
| | after | 8 | 67 | 17 | **0** | 1 |

On the market's default sort, FRA, GOT and HAM stop being flagged (the
ledger agrees: HAM and GOT pay well on a PA184; FRA is within $65k of
break-even and now reads marginally positive) and MAN–CDG starts being
flagged. Manchester's recommendation itself moved, from MAN–CAI to MAN–CDG,
because MAN–CDG now clears the gate — the *ranking* is untouched; what
changed is which markets pass the pays-for-its-airframe gate that orders
qualifying markets ahead of the rest.

**New York and the curated starts are intact.** `NEXTMOVES-03` (ARN, BCN,
SIN, MUC recommend exactly the markets they did) and `NEXTMOVES-06` (a
player who follows Home's advice from New York for 500 days does not
collapse) both pass unchanged. The rival scan below shows the player alive at
the end of **50 of 50** campaigns with **0 collapses and 0 administrations**,
as in AE-042.

## 9. Rival regression

`ae-rival-scan 730 2030-2039 ARN,BCN,MUC,JFK,SIN` — 50 two-year campaigns,
identical seeds and script both sides. **The ranking basis stays revenue and
the horizon stays 16.**

| | baseline | after |
| --- | ---: | ---: |
| campaigns | 50 | 50 |
| world-initiated entries onto the player's pairs | **20** | **20** |
| — Munich IST–MUC, PacificBlue, **day 61** | 10 of 10 seeds | **10 of 10 seeds** |
| — Singapore CGK–SIN, PacificBlue | 10 of 10 (days 509–551) | **10 of 10 (days 495–523)** |
| airframe the entering rival opened with | NA160 ×20 | **NA160 ×20** |
| player-initiated entries | 4 | 1 |
| rival exits from player pairs | 0 | 0 |
| rival openings | 990 | 982 |
| — SOUND | 962 (97.2%) | 960 (**97.8%**) |
| — LOSS-MAKING, STILL FLOWN | 0 | 1 |
| — BAD OPENING | 0 | 0 |
| — CLOSED AFTER EARNING | 28 | 21 |
| idle rival airframes at the end | 239 | 237 |
| airframes gone within 30 days of arriving | 2 | 4 |
| collapses | 0 | 0 |
| administrations | 0 | 0 |
| player active at the end | 50 of 50 | 50 of 50 |

**AE-041's decision is not invalidated.** Both curated arrivals survive with
the same rival and the same airframe; Munich is still day 61 in every seed —
the arrival the app photographs. Opening soundness improves slightly
(97.2% → 97.8%) and seven fewer earning routes are closed.

The regional archetype survives: `regionalRivalKeepsMoneyInTheStandardCast`
passes, and the archetype battery's regional median moves −0.5% (§10).

## 10. Long-run balance

`BalanceTests`, the shipped Phase 18 battery. Archetype net-worth medians
after four years from $120M, five archetypes at five homes.

| Archetype | baseline (3 seeds) | after (3 seeds) | baseline (9 seeds) | after (9 seeds) | Δ (9 seeds) |
| --- | ---: | ---: | ---: | ---: | ---: |
| premium | $478.6M | $494.4M | $441.3M | $464.7M | **+5.3%** |
| conservative | $325.1M | $326.3M | $325.1M | $326.3M | +0.4% |
| regional | $218.1M | $218.9M | $217.6M | $216.5M | −0.5% |
| expansionist | $82.9M | $81.8M | $74.4M | $74.0M | −0.6% |
| lowCost | $0 | $0 | $0 | $0 | — (dead in both; pre-existing) |
| survivors | — | — | 36/45 | 36/45 | unchanged |
| **spread (best ÷ worst positive)** | **5.772** | **6.044** | **5.931** | **6.283** | |

**`archetypeParityAndSanity` fails: 6.044 against a `< 6.0` guard.** It is
the only failing assertion in the suite and it is a product assertion, so it
was **not** weakened, and the change was not withheld either. The measurement
that decides what to do next:

- The movement is **confined to one archetype**: premium +5.3%, everything
  else within ±0.6%, survival identical, nothing died, nothing appeared.
- The premium archetype improves for a reason the fix makes correct:
  `poolAvailableToEntrant` on an empty pair returns the whole pool
  **regardless of the entrant's fare**, so the old estimator told a
  1.25-fare archetype it would carry exactly as many passengers as a
  0.85-fare one. The new one charges it the share its fare actually costs —
  and premium then picks better markets.
- **The guard's headroom was already 1.2%** on unmodified code at nine seeds
  (5.931 against 6.0), and its own sampling noise is larger than that: the
  same unmodified code reads 5.772 at three seeds and 5.931 at nine, a 2.7%
  swing. The instrument cannot resolve a 5% effect at the 6.0 line.
- Every other balance assertion passes: no money printer (the $3B line),
  margins under 60% on the large-passenger runs, the survivability floor,
  `contestedMarketsCompressMargins`, `leverageAmplifiesButDoesNotDominate`,
  `passivityIsNotViableButNotInstantDeath`, `fleetFlippingBleedsMoney`,
  and `tenYearWorldRemainsStableAndContested`.

Against the brief's own watch-list for Phase 13 — runaway fleet growth,
starvation of smaller aircraft, regional archetype disappearance, excessive
rival expansion, excessive route profitability, collapse spikes, altered
world activity, unexpected aircraft concentration — **none occurred**: rival
openings 990 → 982, entering airframe NA160 in 20 of 20 both sides, idle
airframes 239 → 237, collapses 0 → 0, regional median −0.5%.

The threshold decision is a balance decision and this phase was explicitly
forbidden to make one. §18 recommends it as the next phase's first act.

## 11. Performance

MEASURED on the session container (4 cores), release builds, same machine
and same moment for both sides.

| | baseline | after | Δ |
| --- | ---: | ---: | ---: |
| `marketOpportunities(limit: 8)` from ARN | 0.371 ms | 0.427 ms | +15% |
| `marketOpportunities(limit: 8)` from JFK | 0.430 ms | 0.508 ms | +18% |
| `candidateMarkets` per rival decision, horizon 16 (shipped) | 984 µs | 1,235 µs | +26% |
| — at horizon 32 | 1,206 µs | 1,780 µs | +48% |
| — at the whole world (94) | 1,380 µs | 2,119 µs | +54% |
| 10 campaigns × 730 days × 5 homes (rival decision loop, end to end) | 70.98 s | 70.45 s | −0.7% (noise) |

`marketOpportunities` is rebuilt per tick for the map, so its budget is the
one that matters; 0.5 ms is two orders of magnitude under the 14 ms that
made it expensive before (docs/MAP_ARCHITECTURE.md §11). The +15–18% is one
`demandPool` pair and one incumbent-utility pass per candidate airframe
instead of one per market; the route table is indexed by market **once per
call** rather than scanned per candidate, which is why it is not worse. No
caching was added.

The rival's candidate evaluation costs +26% per decision at the shipped
horizon (984 → 1,235 µs, both measured alone on this container). Its own test
bound is 20,000 µs for the whole world and the whole world now costs 2,119
µs. A rival decides once a week, so the end-to-end campaign runtime does not
move at all: 70.98 s → 70.45 s over 10 campaigns × 730 days, which is inside
the noise.

**One timing in an earlier full-suite run was contention, not cost.**
`aRivalDoesNotBuyAnAirframeAndRetrenchAWeekLater` reported 958 s against a
300-second limit in a run where a release build was compiling on the same
four cores. Measured alone it takes **9.99 s after the change and 10.19 s
before** — 30× under its limit either way — and it does not fail in the
clean run. Swift Testing measures a time limit as wall clock across a
469-test parallel suite, the same category AE-043 recorded on the New York
campaign. **No time limit was changed.**

## 12. UI validation

**Visible recommendations changed.** `NextMovesCard.airframeLine`
(App/Screens/DashboardView.swift:676) prints `bestAirframe` and
`monthlyAfterAirframe`. At Hamburg it read *"Best on a 95-seat KT-95
Skylark — about $121k a month after its lease"* and now reads *"Best on a
162-seat NA-160 Bris — about $491k a month"*; the ledger's best there is the
NA160. At Manchester the recommended **market** changed (MAN–CAI → MAN–CDG)
because MAN–CDG now clears the pays-for-its-airframe gate.

**NOT VALIDATED at runtime in this session.** The evidence loop for this
project is parse → push → CI → simulator → screenshot → LOOK, and the
simulator half runs on the macOS CI runner, which this container is not.
What *is* established here: the four homes the UI journeys photograph (ARN,
BCN, SIN, MUC) recommend exactly the markets they did before
(`NEXTMOVES-03`), so the journeys' screens address the same content. The
airframe line's *text* at those homes is not pinned by any test and is not
verified. **This is the phase's one unvalidated surface.**

## 13. Bugs found

| ID | Priority | Root cause | Player impact | Status |
| --- | --- | --- | --- | --- |
| TD-033 | — | `airframeDayValue` took `passengersPerDay` as a caller constant while costing the airframe | The recommendation could not rank aircraft; it preferred the smallest cabin that cleared the seat cap, whatever the market | **RESOLVED** |
| TD-035 | — | The estimator assumes every scheduled rotation flies; 4–23% do not, driven by schedule slack | Small, tightly-scheduled airframes over-valued by 15%; five of thirteen ordering errors | **OPEN** (new) |
| TD-036 | — | The estimate prices the airframe's maximum rotations; every caller opens routes at two | On production's own configuration the airframe ordering agrees with the ledger 4/13; matched to the flown frequency it is 11/12 | **OPEN** (new) |
| — | — | The player's economics ignored incumbents entirely: the same $22,065/day with 0 and with 3 carriers on the pair while the ledger swung +$37,403 → −$9,439 | A contested market read exactly as valuable as an empty one | **fixed here** (part of TD-033) |
| — | — | `BalanceTests.archetypeParityAndSanity` sits 1.2% under its own guard on unmodified code, and its 3-vs-9-seed sampling noise is 2.7% | none (test-only) | **OPEN**, §18 |

**A note on numbering.** A parallel session, also labelled AE-044, merged
`main` a few hours before this branch and took **TD-034** for a different
finding (one Core test is half the suite's CI time). This phase's two new
entries are therefore **TD-035** and **TD-036**; nothing here contradicts that
work, and its time-limit changes are merged into this branch.

## 14. Bugs fixed

**TD-033 only.** Confirmed by: the mid-class demand bias going to −0.0%
(§6), the estimate reproducing `DemandSystem.allocate` to within its own
rounding across 336 comparisons (§6), ordering agreement 4/13 → 8/13 (§7),
and twelve regression tests that encode the rule rather than the examples.

BUG-056 is **not** fixed and is not claimed to be (§16).

## 15. Validation matrix

| Class | What |
| --- | --- |
| **READ** | The real demand pipeline and both estimator paths, traced line by line (docs/AE044_DEMAND_ESTIMATOR_AUDIT.md). The five divergence points. |
| **MEASURED** | Phase 2 capacity, Phase 3 frequency, Phase 4 competition, Phase 5 line-by-line and ordering, Phase 14 bias, all through `ae-demand` against real flown months · 336 allocation comparisons · 93-home sweep × 3 acquisition rules, before and after · 50 rival campaigns before and after · archetype battery at 3 and 9 seeds, before and after · `marketOpportunities` and campaign timings before and after. |
| **TESTED** | 12 new tests (`ServiceDemandTests`), 1 updated (`HorizonTests` HORIZON-05, rewired to the new derivation with its meaning unchanged). Full Core suite re-run on a quiet container: **469 tests, 1 failure** — `archetypeParityAndSanity` (§10, real, reported, not weakened). An earlier run also tripped a 300 s time limit; that was a release build compiling on the same four cores and did not recur (§11). |
| **COMPILED** | `swift build -c release` clean; all eight executables build. |
| **RUNTIME VALIDATED** | Every measurement above runs the real `GamePipeline.standard()`. |
| **OBSERVED** | Nothing. No screenshot was taken in this session. |
| **AUTHORED** | The five AE-044 documents; the `ae-demand` executable; the TD-035/TD-036 entries. |
| **NOT VALIDATED** | The changed Next Moves airframe line on a simulator (§12). The 9-seed archetype figures are from a temporary edit and are not a shipped test. The archetype spread's behaviour at samples larger than 9. |

## 16. BUG-056 re-evaluation

**B — PARTIALLY FIXED.** The estimator half is repaired; the exact remaining
issue is recorded.

- The **four runway-blocked homes** (BGO, BLL, NCE, VCE) are unchanged and
  were never estimator-dependent: `routeEligibility` is arithmetic, and the
  aircraft market's first buyable row still cannot fly the recommended route
  at all. This half of BUG-056 needs no estimator and could be fixed on its
  own.
- The **economic half** is better and not solved. On the market's default
  sort the modelled dangerous count falls 9 → 7 and the estimator's picks now
  agree with the ledger at 8 of 13 markets rather than 4. But on the
  configuration production actually flies — the estimate priced at maximum
  rotations, the route opened at two — the agreement is still 4/13, because
  both halves of the estimate describe an operation the game does not fly
  (TD-036).
- The **UI half** is untouched and unmeasured this phase: `AircraftShopSheet()`
  still takes no arguments, still sorts by seats descending, still shows
  seven unbuyable rows first.

**BUG-056 stays OPEN**, re-blocked on TD-036 rather than TD-033. It is not
forced closed.

## 17. Release impact

- **Economic credibility** — improved, materially. The estimator is now the
  simulation's own demand allocation rather than a parallel approximation,
  provable to ±2 passengers.
- **Recommendation credibility** — improved for market choice (the player's
  economics now respond to competition at all) and improved-but-incomplete
  for aircraft choice. The monthly figure printed beside a recommendation is
  still the *mature* month, not the player's first (TD-036).
- **Aircraft-choice credibility** — better, not yet trustworthy. Do not
  build a pinned aircraft recommendation on it until TD-036 is decided.
- **Rival credibility** — unchanged to slightly better: both curated
  arrivals intact on the same days with the same airframe, opening soundness
  97.2% → 97.8%.
- **Player fairness** — improved: the advice no longer prices a contested
  market as an empty one.
- **Regression risk** — moderate and known. One balance assertion fails
  (§10) and must be resolved before this can merge green. The demand change
  touches the shared estimator, so the rival scan and the recommendation
  battery must be re-run after any follow-up.

**No claim of release readiness is made.**

## 18. ONE recommended next master prompt

### AE-045 — TD-036: the service the estimate is actually pricing

**Not AE-045-as-BUG-056**, and not TD-035 either. The evidence points at
one constraint and it is the same one twice.

The strongest measured fact in this phase is not the fix; it is §7's third
row: **priced at the frequency the game actually flies, airframe ordering
agrees with the ledger at 11 of 12 markets; priced as production prices it,
at 4 of 12.** That single mismatch is worth more than everything AE-044
recovered, it re-blocks BUG-056 on its own, and it is the reason the
recommendation's monthly figure describes a month the player will not have.

It also carries the balance decision that AE-044 must not make. The
archetype spread is 6.283 at nine seeds against a `< 6.0` guard whose
headroom on unmodified code was 1.2% and whose sampling noise is 2.7%. That
guard has to be settled — with measurement, as its own decision, not as a
side effect — and the phase that changes what the estimator prices is the
phase that will move it again.

The phase should: measure what frequency a route actually settles at under
`manageRoutes`' own load rule, for both the rival and a player following the
advice; decide on evidence between pricing `initialRoundTrips`, pricing the
settled frequency, and making the caller pass its intent; re-run the AE-044
ledger tables, the 93-home battery and the 50-campaign rival scan; and
resolve the archetype-spread guard with a measured threshold or a better
instrument, documenting the previous limit, the measured work and the
reason — never by widening it to fit.

TD-035 is the next-strongest constraint and should follow, not lead: it is
worth 15 percentage points of small-airframe bias, but its effect is second
order until the estimate is pricing the right service at all.
