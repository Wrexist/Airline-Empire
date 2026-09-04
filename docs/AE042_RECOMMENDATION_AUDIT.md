# AE-042 — The recommendation audit: before, after, and what is still true

The change, what it did, and what it did not do. Companion to
docs/AE042_NEXT_MOVES_BASELINE.md (the measurements before) and
docs/AE042_BUG055_ROOT_CAUSE.md (the decision).

## 1. What changed

**Core — `Session/MarketOpportunities.swift`, two additions and no
replacement.**

1. `GameState.airframeResult(from:to:distanceKm:passengersPerDay:candidateSpecs:catalog:)`
   — the best airframe the airline could operate that can fly the pair, and
   what a month on it keeps after that airframe's lease, its crew and the
   route's own payroll. Every term comes from an existing public primitive:
   `CompetitorAISystem.airframeDayValue(basis: .profit)` (the estimator
   AE-040 corrected and AE-041 shipped for rivals),
   `AircraftTypeSpec.leaseMonthly`, and `FinanceTuning`'s two payroll lines.
   Nothing is re-derived; no second economy exists.
2. `marketOpportunities` walks its own passenger-ranked list and puts the
   markets that pay for their airframe first, stopping as soon as it has
   `limit` of them. A home with too few still receives the rest, so nothing
   is hidden and no player is left without a first route to open.

`MarketOpportunity` gains `bestAirframe`, `monthlyAfterAirframe` and the
derived `paysForItsAirframe`. `marketCandidates` — the route sheet's list —
carries the same three fields and keeps its own order, because the sheet
lists every destination on purpose.

**App — `Screens/DashboardView.swift`, one line of copy and one heading.**
Each recommendation now reads, under the passengers-and-distance line:

> Best on a 180-seat Meridian MR-180 — about $874k a month after its lease.

and where nothing from the player's bases pays for its own aircraft, the
heading says so rather than calling the least bad option strong.

**Unchanged:** the ranking itself (`pool / (1 + incumbents)`), every tuning
value, the fee model, the fare formula, the demand system, the rival AI, the
save format, and `marketCandidates`' ordering.

## 2. Before and after

### 2.1 The advice itself (MEASURED, seed 2030, market-default airframe)

| Home | Before | After |
| --- | --- | --- |
| Stockholm (curated) | LHR +$1.8M, CDG +$1.6M | **unchanged** |
| Barcelona (curated) | LHR +$1.0M, CDG +$825k | **unchanged** |
| Munich | LHR, CDG | **unchanged** |
| Singapore (curated) | CGK +$1.2M, **KUL −$598k** | CGK, **BKK +$2.7M** |
| New York | ORD +$858k, **YYZ −$214k** | ORD, **MEX +$2.3M** |
| London | **CDG −$1.3M**, IST | **IST +$3.3M**, CAI +$2.5M |
| Manchester | **LHR −$1.5M**, **CDG −$517k** | **CAI +$2.8M**, IST +$3.8M |
| Nadi | HND, SYD (neither flyable) | unchanged — nothing from Nadi pays; the card now says so |

### 2.2 Every home a player can pick (MEASURED, `ae-advice sweep`, 93 airports)

First recommendation, on the airframe the aircraft market lists first:

| | Before | After |
| --- | ---: | ---: |
| SAFE | 7 | 8 |
| VIABLE | 50 | 58 |
| MARGINAL | 15 | 17 |
| **DANGEROUS** | **20** | **9** |
| **UNFLYABLE** | **1** | **0** |
| **Homes given advice that loses money or cannot be flown** | **21 of 93 (23%)** | **9 of 93 (10%)** |

The nine that remain are not the same failure. Each pays well on the airframe
the recommendation names and loses on the larger one the market's default
sort offers first — BUG-056, §4.

### 2.3 The campaign BUG-055 was found on (MEASURED)

AE-041's scripted New York campaign, **unchanged**, with only the advice
different:

| | Before | After |
| --- | ---: | ---: |
| Seeds collapsed, of 30 | **28** | **0** |
| End state | administration and collapse, day 430, −$2.0M to −$2.9M | alive, $14.1M–$54.8M |

`ae-rival-scan 730 2030-2059 JFK --player`, run this phase on both builds.

### 2.4 Following the advice, 30 seeds × 4 homes × 730 days (MEASURED, `ae-advice follow`)

The trusting player takes the top recommendation each month on the market's
default airframe:

| Home | Collapses before → after | Mean cash at day 730, before → after |
| --- | ---: | ---: |
| New York | 0 → 0 | $343.6M → **$469.4M** (+37%) |
| Stockholm | 0 → 0 | $282.2M → **$386.2M** (+37%) |
| Barcelona | 0 → 0 | $222.8M → **$255.7M** (+15%) |
| Singapore | 0 → 0 | $432.4M → **$471.0M** (+9%) |

Stated plainly: this script does **not** collapse before the fix either. It
takes one recommendation a month, and the first is sound at all four homes;
the collapse in §2.3 needs the second recommendation, which is where the
traps were. What the fix buys this player is not survival but a materially
better airline.

## 3. Estimate against ledger (MEASURED, `ae-fee-baseline`, six months flown)

Recommendations the fixed ranking makes, flown for real. "After everything"
is the ledger's bottom line and includes the $150k a month of airline
overhead that the recommendation deliberately does not charge to one route.

| Pair | km | Airframe | Class | Ledger, after everything | Margin |
| --- | ---: | --- | --- | ---: | ---: |
| SIN–CGK | 884 | MR180 | narrowbody, short | **+$653k** | 17% |
| JFK–ORD | 1,187 | MR180 | narrowbody, medium | **+$545k** | 14% |
| ARN–LHR | 1,462 | MR180 | narrowbody, medium | **+$1.06M** | 26% |
| KEF–LHR | 1,896 | AV90 | regional jet, thin | **+$276k** | 15% |
| BGO–LHR | 1,042 | KT72 | turboprop, thin | **−$11k** | −1% |

And the pairs the gate now rejects, flown for real on the same basis (from
the baseline): MAN–LHR −$1.18M, LHR–CDG −$1.38M, SIN–KUL −$684k, JFK–YYZ
−$494k a month. The gate's sign matches the ledger on every pair sampled,
before and after.

**The one that does not clear:** BGO–LHR is estimated at +$264k a month after
its airframe and lands at −$11k after everything. About $150k of that gap is
airline overhead, which the estimate does not charge; the rest is the
estimator's known optimism on thin routes — it assumes every scheduled
rotation flies (AE-040's limitation) and its demand forecast under-reads a
thin pair. So the gate's boundary is soft by roughly a fifth of a million a
month on the thinnest markets: it reliably rejects routes that lose half a
million or more, and can pass one that lands near break-even. Recorded here
rather than papered over with a margin that no measurement supports.

## 4. What the fix does not fix

**BUG-056 — the aircraft market's default sort disagrees with the advice.**
At 9 of the 93 homes the recommended market pays on a small airframe and
loses on the largest one, which is what the market's default sort (seats,
descending) puts in the first row:

| Home | Market | pax/day | On the market's first row | On the airframe the advice names |
| --- | --- | ---: | ---: | ---: |
| Reykjavík | KEF–LHR | 264 | PA184 **−$703k** | AV90 **+$141k** |
| Bergen | BGO–LHR | 452 | KT95 **−$270k** | KT72 **+$279k** |
| Billund | BLL–LHR | 442 | KT95 **−$406k** | KT72 **+$111k** |
| Dublin, Edinburgh, Frankfurt, Gothenburg, Hamburg, Palma | | | negative | positive |

The recommendation now names its airframe, which is the part the ranking can
answer. The other half — a market that sorts by seats and never asks what the
route is for — belongs to the acquisition screen and is not touched here.

**Nadi, and homes where nothing pays.** One of the 93 has no market that
covers its own airframe in the startup era; the best loses $897k a month and
the two largest are beyond every era airframe's range. The card says so
instead of calling them strong. Whether such a home should be offered to a
new player at all is a content question, not a ranking one.

**The passenger ranking itself.** Among markets that pay, the order is still
passengers per incumbent, so the recommendation is still the *biggest* safe
market rather than the most profitable one. Ranking by value instead was
measured (baseline §5) and rejected: it sends every home to its longest
reachable route at one rotation a day. That trade is a design choice this
phase deliberately did not make.

## 5. Performance (MEASURED)

One `marketOpportunities` call, release build, this container, 200 runs:

| Home | Before | After |
| --- | ---: | ---: |
| New York, limit 4 | 0.267 ms | 0.301 ms |
| Stockholm, limit 4 | 0.233 ms | 0.253 ms |
| Nadi, limit 4 (worst case — nothing qualifies, so the whole list is priced) | 0.321 ms | 0.545 ms |

`ae-map-bench` at late-game scale (200 routes, 450 live flights): the whole
map model 1.86 → 2.00 ms per rebuild. The pricing stops as soon as `limit`
qualifying markets are found, so the typical cost is a few evaluations; the
worst case is a home where none qualifies. Nothing here runs per frame.
