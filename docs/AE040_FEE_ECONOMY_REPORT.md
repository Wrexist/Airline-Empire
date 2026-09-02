# AE-040 FINAL REPORT — THE FEE ECONOMY AND THE REGIONAL ARCHETYPE

2026-09-02. Branch `claude/rival-pressure-visibility-2ouiny`. Companion
documents: docs/FEE_ECONOMY_BASELINE.md (Phase 0–1, parity),
docs/FEE_ECONOMY_ESTIMATOR_AUDIT.md (Phase 2), docs/REGIONAL_ARCHETYPE_AUDIT.md
(Phase 3, 9), docs/FEE_ECONOMY_FIX_DECISION.md (Phase 5–6),
docs/BALANCING.md F-007. Labels: READ, MEASURED, TESTED, COMPILED,
RUNTIME VALIDATED, OBSERVED, AUTHORED, NOT VALIDATED.

## 1. Executive summary

**Was TD-029 real?** Yes, and it was not the archetype's fault. MEASURED:
the 68-seat turboprop's airport fees were 1.7–1.9× the 180-seat
narrowbody's as a share of revenue on the same pair, no turboprop route
in a forty-route battery paid for its lease, and the regional archetype's
own evaluation from its European home (Paris) found all sixteen
candidates losing on money alone. The player paid exactly the same.

**The actual root cause** — two formulas applied to the wrong thing, not
a level to tune:

1. The airport's movement fee was charged per movement with no term for
   the aircraft: a 68-seat cabin paid what a 422-seat one paid (CASE B,
   wrong scale; BUG-051).
2. The AI's profit estimator charged maintenance at the type's hourly
   rate where the ledger books a 60-hour check per 500–650 flight hours,
   9.8× the ledger (CASE D; BUG-052). This is what turned the profit
   ranking's view of the archetype's world from "few markets" to "none".

**Was a production change shipped?** Yes, two, both formula not level:
the movement fee is quoted for a 180-seat movement and charged in
proportion to seats (`AirportSpec.movementFee(for:ops:)`, new tuning
constant `movementFeeReferenceSeats = 180`, integer cents), used by the
flight system and the estimator alike; and the estimator's maintenance
line is the fleet system's own check rule integrated
(`FleetEconomics.expectedMaintenancePerDay`). The 180-seat narrowbody
pays exactly what it paid, so the anchor economy and every battery
calibrated on it are untouched by construction. No fee level, fare,
horizon, ranking basis, archetype or player branch changed; no
save-format change. Plus one explainability line (Phase 13): the route
screen's fee row now carries the charges behind it.

## 2. Scope decision

AE-039 closed with one recommended next prompt and the evidence for it:
SwiftJet's JFK–ORD lost about $277k a month at full load and ORD–YYZ
about $953k; under the profit basis the regional archetype had zero
viable candidates anywhere; three archetype runs crossed the 60% margin
line on that basis; and CI run 122's KEY-48 showed a player route with
"airport fees take 96% of the revenue". The question this phase was
asked was whether the fee model is wrong, wrongly applied, or right and
incompatible — and to measure before changing anything.

## 3. Baseline economics (MEASURED, `ae-fee-baseline`, average month over a year, 2 rotations)

| Route type | Route | Aircraft | Revenue | Airport fees | Fee/revenue | Operating profit (all-in) | Validation |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| short (347 km) | LHR–CDG | NA70 68 seats | $504k | $793k | 157% | −$857k (−170%) | MEASURED |
| short | LHR–CDG | MR180 180 seats | $1.35M | $1.15M | 85% | −$1.08M (−80%) | MEASURED |
| short (300 km) | JFK–BOS | NA70 | $475k | $789k | 166% | −$865k (−182%) | MEASURED |
| medium (700 km) | ORD–YYZ | NA70 | $723k | $709k | 98% | −$636k (−88%) | MEASURED |
| medium (1,187 km) | JFK–ORD | NA70 | $1.02M | $771k | 75% | −$522k (−51%) | MEASURED |
| medium | JFK–ORD | MR180 | $2.76M | $1.11M | 40% | +$83k (+3%) | MEASURED |
| medium (1,462 km) | ARN–LHR | MR180 | $3.22M | $905k | 28% | +$677k (+21%) | MEASURED |
| long (3,974 km) | JFK–LAX | MR180 (1×) | $3.73M | $560k | 15% | +$1.45M (+39%) | MEASURED |
| long (5,541 km) | LHR–JFK | MR300 298 seats (AI) | $6.94M | $625k | 9% | +$2.39M (+34%) | MEASURED (one month) |

Fees were the largest direct cost on every route under 1,600 km for
every aircraft (62–90% of fuel + fees + crew); fuel, the cost the design
expects to lead, was 4–12% of revenue on short routes. The forty-route
table: docs/FEE_ECONOMY_BASELINE.md §6.

## 4. Root cause (ranked)

1. **The movement fee did not scale with the aircraft.** MEASURED (fee
   share 1.7–1.9× between the two types on the same pair; per seat flown
   the turboprop's movement fee 2.65× the narrowbody's; 40 profitable
   turboprop candidates of 542 worldwide, 0 from Paris). READ (one
   number per airport, no aircraft term in `arrive`). Fixed.
2. **The estimator's maintenance definition.** MEASURED (9.8× over forty
   routes; every other line within 4–8%). READ (hourly rate versus
   periodic check). Fixed.
3. **The fee level, and the reference P&L never reconciled line by
   line.** MEASURED (fees 1.6× the design anchor on the anchor fixture,
   ownership 2×, fuel and crew ½, maintenance ⅒; total within 4%).
   Recorded as TD-031, not changed.
4. **Short-haul fares against hub passenger fees.** MEASURED ($26–28
   per passenger at LHR/CDG/JFK against a $60–69 fare under 400 km).
   Part of TD-031, not changed.

Ruled out: double counting (READ: one posting per arrival, TESTED),
wrong timing (READ), player/rival asymmetry (MEASURED to the cent).

## 5. Regional archetype

**Can it survive?** MEASURED in the Stockholm cast (thirty seeds, two
years): before, 28 of 30 alive with 1.7 routes each, all losing, fleet 3,
fees 103% of revenue, direct −$1.09M a month, net worth $29M; after, 30
of 30 alive with 4.0 routes (0.3 losing), fleet 9.3, fees 61%, direct
+$1.04M a month, net worth $92M.

**Can it profit?** Yes on 800–1,700 km pairs; not under 400 km at hubs
(cause 4).

**How many viable markets exist?** By its own evaluation: turboprop 40 →
374 of 542 candidates worldwide, at 28 → 80 of 88 homes; from Paris 0 →
11 of 16, from Chicago 0 → 7. Regional jet 294 → 504.

**What changed?** Only the fee scale and the estimator's maintenance
line. Its fleet, fare, geography and decision loop are as they were.

OTHER_HOMES_SECTION

## 6. Player parity

Identical to the cent (MEASURED): the same route flown by an AI airline
of the regional archetype books the same revenue, fees, fuel and crew as
the player's. The fee code has no owner branch; the player's three
capability perks (fuel hedging, efficient turnarounds, network
operations centre) do not touch the fee line and no new airline holds
them. A player opening a turboprop route at a hub paid — and pays — what
SwiftJet pays. Before this phase that was a route that could not profit
anywhere; the route sheet said nothing about fees. Now the route screen
says what each end charges the aircraft's size and each passenger
(Phase 13).

## 7. Estimator versus ledger (MEASURED, forty routes, $/day, actual passengers)

| Metric | Estimate | Actual | Error | Cause |
| --- | ---: | ---: | ---: | --- |
| Revenue | 1,753,430 | 1,753,499 | 0% | — |
| Fuel | 237,027 | 219,540 | +8% | scheduled rotations that do not fly (5–10%) |
| Airport fees | 982,611 | 941,536 | +4% | the same, on the movement part |
| Crew | 117,360 | 109,044 | +8% | the same |
| Onboard service | 142,195 | 142,200 | 0% | — |
| Maintenance (before) | 180,458 | 18,411 | +880% | hourly rate vs periodic check — structural |
| Maintenance (after, ARN–LHR, two years) | $545k | $537k | +1.5% | one check's granularity |
| Whole estimate (after, JFK–ORD NA70, a year) | $5,633/day | $6,716/day | −3% of revenue | unflown rotations, fuel walk |

## 8. Before / after

| Metric | Before | After | Change | Validation |
| --- | ---: | ---: | ---: | --- |
| Profitable regional candidates (NA70, world) | 40 of 542 at 28 homes | 374 at 80 homes | +334 | MEASURED |
| Profitable regional candidates (AV90) | 294 of 747 at 69 homes | 504 at 86 | +210 | MEASURED |
| NA70 fee/revenue, median over candidates | 0.82 | 0.43 | −0.39 | MEASURED |
| MR180 fee/revenue | 0.38 | 0.38 | 0 | MEASURED |
| JFK–ORD NA70, fees / month | $771k (75%) | $413k (40%) | −$358k | MEASURED |
| JFK–ORD NA70, direct profit / month | −$57k | +$301k | +$358k | MEASURED |
| LHR–CDG NA70, fees | $793k (157%) | $428k (85%) | still a loser (cause 4) | MEASURED |
| LHR–JFK MR300, fees | $625k (9%) | $930k (11%) | +$164k on the movement part | MEASURED |
| Estimator maintenance / ledger | 9.8× | 1.02× | — | TESTED |
| Estimator error on actual passengers, $/day | −3.3k to −17k | −0.6k to −5.3k | — | MEASURED |
| Stockholm cast: regional rival alive | 28/30 | 30/30 | +2 | MEASURED |
| Stockholm cast: regional routes losing | 1.7 of 1.7 | 0.3 of 4.0 | — | MEASURED |
| Stockholm cast: regional fees/revenue | 103% | 61% | −42 pts | MEASURED |
| Stockholm cast: conservative margin (regional jets) | 22% | 39% | +17 pts | MEASURED |
| Stockholm cast: expansionist margin (regional jets) | 11% | 23% | +12 pts | MEASURED |
| Stockholm cast: collapses (30 campaigns) | 2 | 0 | −2 | MEASURED |
| Long-run balance battery | pass | BALANCE_RESULT | | |

CAMPAIGN_RESULTS_SECTION

## 9. Profit-ranking re-evaluation (TD-030)

PROFIT_RANKING_SECTION

## 10. Screenshots inspected

FRAMES_SECTION

## 11. Bugs found

| ID | Priority | Root cause | Player impact | Status |
| --- | --- | --- | --- | --- |
| BUG-051 | P1 | the movement fee scaled with nothing | a player's turboprop or regional jet paid a narrowbody's movements; no turboprop route in the world paid for itself | FIXED, TESTED (`FeeEconomyTests`), MEASURED |
| BUG-052 | P2 | the AI's estimator charged maintenance hourly; the ledger charges checks | AI only: the profit ranking saw an empty world | FIXED, TESTED |
| TD-031 | debt | the reference P&L never reconciled line by line; short haul fee-bound for every aircraft | short hub pairs lose money for everyone at the reference fare | recorded |

## 12. Testing

TESTING_SECTION

## 13. Validation matrix

VALIDATION_SECTION

## 14. Remaining debt

- **TD-031** — the reference P&L reconciliation (fee level, fuel, crew,
  maintenance cadence, lease rates); short haul under 400 km stays
  fee-bound for every aircraft; the arrival passenger fee against the
  short-haul fare.
- **Regional jets at 88 seats now pay 49% of a narrowbody's movements**,
  and two archetypes that fly them (conservative, expansionist) gained
  12–17 margin points in the Stockholm cast. Correct by the rule, and a
  shift the battery's 60% line still bounds; whether their networks
  should grow faster is a playtest question, NOT VALIDATED.
- **The estimator still assumes every scheduled rotation flies** (5–10%
  high on per-flight costs) and prices fuel at the day it asks.
- **The demand forecast under-reads thin Nordic pairs** at the viability
  floor (ARN–GOT 136 forecast against 249 carried).
- **No aircraft can fly a round trip longer than about eight hours one
  way**; widebodies are era-locked for the player and not for rivals.

## 15. Release impact

RELEASE_IMPACT_SECTION

## 16. ONE recommended next master prompt

NEXT_PROMPT_SECTION
