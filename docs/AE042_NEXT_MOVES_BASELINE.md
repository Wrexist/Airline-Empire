# AE-042 — What following Next Moves is worth, measured

The baseline, taken before any production change. Everything here is
**MEASURED** from the real engine unless a line says otherwise: the
recommendations are exactly `GameState.marketOpportunities` narrowed the way
`NextMovesCard` narrows it, the estimates are the flight system's own
arithmetic ahead of time (`CompetitorAISystem.airframeDayValue`), and the
ledger figures come from routes that actually flew.

Architecture in docs/AE042_RECOMMENDATION_PIPELINE.md; the decision in
docs/AE042_BUG055_ROOT_CAUSE.md.

## 0. Method

**Tool.** `ae-advice` (new, `AirlineEmpireCore/Sources/AEAdvice`), three modes:

| Mode | What it does |
| --- | --- |
| `audit` | Founds an airline at a home and prints what Home recommends, priced: rotations, passengers carried, revenue, direct result, fee share, and the month's result after the aircraft the route needs. Then ranks every market from that home by the same measure, so the recommendation's own position is visible. |
| `follow` | Plays the trusting player — take the top recommendation, lease the aircraft it needs, open it at the reference fare at two round trips, assign, and come back next month — and reads the ledger back. |
| `sweep` | The first recommendation from every home a player can pick, classified. |

Nothing in the tool changes the simulation. `--rank keeps` and `--rank safe`
are counterfactuals computed inside the tool over production's own candidate
set; production behaviour is `--rank passengers`, the default.

**Which aircraft the player is assumed to lease.** READ: the aircraft market
(`FleetView`) defaults to sorting by **seats, descending**, and to the
**lease** deal. So the first row a new player sees is the largest airframe
their era allows — `PA184`, 184 seats, $790k a month. `--acquire biggest`
models that and is the faithful setting; `--acquire cheapest` (the smallest
flyable type) is reported beside it as the opposite bound.

**"After the aircraft."** A route's own thirty-day direct operating result,
less the airframe's monthly lease and the crew payroll it carries
(`payrollPerAircraftMonthly`). Airline overhead is *not* charged against it,
so the figure is generous to the recommendation. The only load-bearing
boundary in this document is **zero**: at or below it the route cannot pay for
the aircraft it needs. The bands above it (MARGINAL under one month's lease
of headroom, VIABLE under three, SAFE beyond) are descriptive labels for
reading tables, not thresholds anything depends on.

**Held constant.** Scenario `entrepreneur` ($60.0M starting cash, five
rivals), start year 2030, seeds 2030–2059, the shipped catalog and tuning at
commit 60c1520.

## 1. The three curated starts, and New York

Seed 2030, day 0, the two markets Home offers, flown on the market's default
airframe (PA184).

| Start | Rec | Market | km | pax/day | Fee share | Month after the aircraft | Verdict | Its rank among that home's markets by the same measure |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| **Stockholm** (curated) | #1 | ARN–LHR London | 1,462 | 1,117 | 28% | **+$1.8M** | VIABLE | 5 of 42 |
| | #2 | ARN–CDG Paris | 1,539 | 987 | 28% | **+$1.6M** | VIABLE | 6 of 42 |
| **Barcelona** (curated) | #1 | BCN–LHR London | 1,147 | 1,910 | 35% | **+$1.0M** | VIABLE | 10 of 42 |
| | #2 | BCN–CDG Paris | 858 | 1,852 | 43% | **+$825k** | VIABLE | 12 of 42 |
| **Singapore** (curated) | #1 | SIN–CGK Jakarta | 884 | 3,372 | 35% | **+$1.2M** | VIABLE | 15 of 18 |
| | #2 | SIN–KUL Kuala Lumpur | 297 | 2,083 | **68%** | **−$598k** | **DANGEROUS** | **18 of 18 — last** |
| **New York** (picked) | #1 | JFK–ORD Chicago | 1,187 | 3,354 | 40% | **+$858k** | VIABLE | 18 of 22 |
| | #2 | JFK–YYZ Toronto | 589 | 2,926 | **63%** | **−$214k** | **DANGEROUS** | 21 of 22 |

Two readings, both MEASURED:

1. **The traps are real and they are the second recommendation.** Kuala
   Lumpur loses $598k a month and Toronto $214k, on the aircraft the market
   leads to. Neither can be rescued by a different airframe: the best
   startup-era airframe for Kuala Lumpur still loses $242k a month, and for
   Toronto $174k.
2. **Even the good recommendations rank near the bottom.** Chicago is #18 of
   22 from New York; Jakarta #15 of 18 from Singapore. The recommendation is
   not merely missing the best market, it is sampling from the wrong end.

On the smallest flyable airframe instead (`--acquire cheapest`), the same two
markets read: Chicago +$18k a month (MARGINAL), Toronto −$224k, Jakarta
+$147k, Kuala Lumpur −$242k. The trap survives every aircraft choice; the
"good" recommendation nearly vanishes.

## 2. Every home a player can pick (MEASURED, `sweep`, seed 2030, 93 airports)

The **first** recommendation only, flown on the market's default airframe:

| | Production ranking | Same candidates, traps gated out |
| --- | ---: | ---: |
| SAFE | 7 | 8 |
| VIABLE | 50 | 58 |
| MARGINAL | 15 | 17 |
| **DANGEROUS** (loses money after its aircraft) | **20** | 9 |
| **UNFLYABLE** (no era airframe can fly it) | **1** | 0 |
| Homes with no qualifying market at all | — | 1 (Nadi) |

**21 of 93 pickable homes — 23% — are given a first recommendation that
either loses money or cannot be flown.** Mean great-circle distance of the
recommendations, by class: DANGEROUS 658 km, MARGINAL 799 km, VIABLE
1,660 km, SAFE 2,348 km. The relationship is monotonic: the shorter the
recommended route, the worse it is, because the fare falls with distance
while the two movement fees do not.

The twenty dangerous ones are the game's most recognisable city pairs:

```
AMS→LHR  369 km  −$1.3M/mo      LHR→CDG  347 km  −$1.3M/mo
BOS→JFK  300 km  −$1.4M/mo      MAN→LHR  243 km  −$1.5M/mo
CDG→LHR  347 km  −$1.3M/mo      HND→KIX  432 km  −$577k/mo
DUB→LHR  449 km  −$1.1M/mo      SFO→LAX  544 km  −$412k/mo
DUS→LHR  501 km  −$1.3M/mo      YYZ→JFK  589 km  −$214k/mo
EDI→LHR  534 km  −$1.2M/mo      YUL→JFK  537 km  −$177k/mo
… and BGO, BLL, FRA, GOT, HAM, KEF, KIX, PMI
```

Worked examples:

- **Manchester.** Home's first suggestion is London, 243 km, 1,589
  passengers a day. Fees are **96% of revenue** — the figure AE-039
  photographed on KEY-48 — and the route loses **$1.5M a month** after its
  aircraft. It ranks **#42 of 45**. The second suggestion, Paris, also loses
  money. Meanwhile Lagos ($3.1M/mo), Istanbul ($3.0M) and New York ($3.0M)
  are available and unmentioned.
- **London.** The first suggestion is Paris, 347 km, 4,346 passengers a day,
  fees 85% of revenue, **−$1.3M a month**, ranked **#44 of 44 — dead last**.
  The second, Istanbul, is the best thing on the list (+$2.5M, #8 of 44).
- **Nadi.** Both suggestions — Tokyo 7,132 km and Sydney 3,170 km — are
  beyond every startup-era airframe. `servableNow` is `false` for both, so
  `NextMovesCard`'s servable filter finds nothing and falls back to showing
  the unservable list anyway. The player is offered two routes no aircraft
  they can buy could fly. (No market from Nadi pays for its aircraft in this
  era at all: the best, Auckland, loses $897k a month. That is a content and
  economy fact, not a ranking one.)

## 3. Does the ledger agree? (MEASURED, `ae-fee-baseline`, six months flown)

The estimate is only worth ranking on if reality agrees. Seven recommended
pairs, PA184, the scheduler's own rotations, six months flown through the
real pipeline; "after everything" is the ledger's own bottom line including
lease, payroll and airline overhead:

| Pair | km | Fee share, est. → ledger | Estimate after the aircraft | **Ledger, after everything** | Sign agrees |
| --- | ---: | ---: | ---: | ---: | :---: |
| MAN–LHR | 243 | 96% → 81% | −$1.5M | **−$1.18M** | ✓ |
| LHR–CDG | 347 | 85% → 85% | −$1.3M | **−$1.38M** | ✓ |
| SIN–KUL | 297 | 68% → 66% | −$598k | **−$684k** | ✓ |
| JFK–YYZ | 589 | 63% → 63% | −$214k | **−$494k** | ✓ |
| JFK–ORD | 1,187 | 40% → 40% | +$858k | **+$521k** | ✓ |
| ARN–LHR | 1,462 | 28% → 28% | +$1.8M | **+$1.05M** | ✓ |
| LHR–IST | 2,488 | 18% → 18% | +$2.5M | **+$1.98M** | ✓ |

The sign agrees on all seven, and the estimate is **optimistic by $0.3M–0.8M
a month** — chiefly because it does not charge airline overhead and assumes
every scheduled rotation flies (the AE-040 limitation). A market the estimate
calls dangerous is therefore dangerous in the ledger too, with margin to
spare. That is the direction an eligibility gate needs.

One divergence recorded rather than smoothed: on SIN–KUL the estimator's
*demand forecast* is pessimistic (1,232 passengers a day forecast against
1,934 actually carried), so its per-day direct figure has the wrong sign
(−$21.2k forecast, +$10.3k booked). The verdict is unchanged — the route still
fails to pay for its aircraft by $684k a month in the ledger — but the
forecast error is real and is recorded in docs/AE042_RECOMMENDATION_AUDIT.md.

## 4. Following the advice, campaign by campaign (MEASURED, `follow`)

Four homes × 30 seeds. The trusting player takes the top recommendation each
month, leases the aircraft it needs, opens the route at the reference fare
and assigns it.

### 4.1 On the smallest flyable airframe, 500 days

| Home | Collapsed | Routes opened | Cash, $60.0M → | Worst month | First route, after its aircraft |
| --- | ---: | ---: | ---: | ---: | ---: |
| New York | 0 of 30 | 5 | **$45.5M** | −$1.1M | +$18k |
| Stockholm | 0 of 30 | 17 | $69.3M | $0 | +$252k |
| Barcelona | 0 of 30 | 17 | $58.3M | −$359k | +$67k |
| Singapore | 0 of 30 | 17 | $57.1M | — | +$147k |

Nobody collapses inside 500 days, and that is worth stating plainly rather
than rounding into the bug. What the New York player does instead is stall:
five routes against seventeen elsewhere, **$14.5M of cash burnt**, and a worst
month of −$1.1M. Across all 120 campaigns, **354 of 1,290 recommendations
followed (27.4%) were markets that cannot pay for their aircraft.**

### 4.2 On the market's default airframe, 730 days

(filled in from the run below)

## 5. The counterfactuals

Two alternatives, computed over production's own candidate set — same
origins, same already-served exclusion, same eligibility, same positive-pool
requirement — so that only the ordering differs.

**`keeps`: rank by what the market keeps after its aircraft.** Corrects every
trap, and pushes every home to its longest reachable route: New York →
Lisbon and London (5,405 and 5,541 km, one rotation a day, 368 of 1,965
passengers carried); London → Dubai and New York; Singapore → Tokyo. All
+$2.7M to +$3.1M a month. Safe, but it makes every start recommend the same
shape of route, at one rotation a day near the airframe's range limit, and it
sells a fifth of the demand it names.

**`safe`: keep the existing order, drop only what cannot pay.** Measured at
seed 2030:

| Start | Production | Gated |
| --- | --- | --- |
| Stockholm | LHR, CDG | **LHR, CDG — unchanged** |
| Barcelona | LHR, CDG | **LHR, CDG — unchanged** |
| Munich | LHR, CDG | **LHR, CDG — unchanged** |
| Singapore | CGK, **KUL −$598k** | CGK, **BKK +$2.7M** |
| New York | ORD, **YYZ −$214k** | ORD, **MEX +$2.3M** |
| London | **CDG −$1.3M**, IST | **IST +$3.3M**, CAI +$2.5M |
| Manchester | **LHR −$1.5M**, **CDG −$517k** | **CAI +$2.8M**, IST +$3.8M |

It leaves the advice alone exactly where the advice was already sound — the
three curated starts and Munich, which the AE-039/041 twins and journeys are
pinned on, do not move at all — and replaces only the traps. The replacements
are 884–3,744 km at one to four rotations, not a single shape.

## 6. What the gate does not fix

Under the gate, 9 of 93 homes still get a first recommendation that loses
money **on the airframe the market's default sort leads to**, while paying
handsomely on the right one:

| Home | Recommendation | pax/day | On the default airframe | On the best airframe |
| --- | --- | ---: | ---: | --- |
| Reykjavík | KEF–LHR 1,896 km | 264 | PA184 **−$703k** | AV90 **+$141k** |
| Bergen | BGO–LHR 1,042 km | 452 | KT95 **−$270k** | KT72 **+$279k** |
| Billund | BLL–LHR 790 km | 442 | KT95 **−$406k** | KT72 **+$111k** |
| … and DUB, EDI, FRA, GOT, HAM, PMI | | | | |

Every one is a thin market where the answer is a small aircraft and the
market's first row is the largest one. The recommendation never names an
airframe and the market never asks what the route is for; the two surfaces
disagree, and the player pays for it. Recorded as a separate defect
(BUG-056), because it is the acquisition surface's, not the ranking's.
