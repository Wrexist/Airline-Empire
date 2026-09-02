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

**Every start, thirty campaigns each (MEASURED, `ae-rival-scan --rivals`):**

| Start | Regional rival | Alive before → after | Routes (losing) | Fleet | Fees / revenue | Direct profit / month | Collapses in the cast |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Stockholm | Paris | 28 → 30 | 1.7 (1.7) → 4.0 (0.3) | 3.0 → 9.2 | 103% → 61% | −$1.09M → +$1.08M | 2 → 0 |
| Barcelona | Paris | 26 → 30 | 1.6 (1.6) → 4.0 (0.4) | 2.8 → 9.3 | 104% → 61% | −$1.07M → +$1.02M | 4 → 0 |
| Munich | Paris | 24 → 30 | 1.5 (1.5) → 3.9 (0.3) | 2.7 → 9.0 | 102% → 60% | −$0.96M → +$1.11M | 6 → 0 |
| New York | Chicago | 12 → 30 | 1.2 (0.4) → 3.9 (0.0) | 3.1 → 15.2 | 66% → 42% | +$0.05M → +$4.72M | 18 → 0 |
| Singapore | Bangkok | 30 → 30 | 3.0 (0.0) → 3.0 (0.0) | 12.6 → 22.2 | 49% → 25% | +$2.92M → +$10.55M | 0 → 0 |

Its own operating margin from Paris is still about −6% (routes earn;
nine leases, payroll and overhead on four routes do not yet); from
Chicago +12%, from Bangkok +30%.

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
| Long-run balance battery (archetype parity, ten-year world, contested margins) | pass | pass | — | TESTED (450 tests) |
| Expansionist fleet after two years (Stockholm cast) | 28 | 40 (the cap) | BUG-053 | MEASURED |
| World-initiated entries, 150 campaigns, shipped ranking | 60 | 60 (Munich 30, Singapore 29, one more at Munich) | 0 | MEASURED |

The cast around the regional rival, Stockholm start: low-cost fees
36% → 34%, premium 38% → 36%, conservative (regional jets) 42% → 25%
with margin 22% → 39%, expansionist (regional jets) 32% → 19% with
margin 11% → 22% and a fleet that now reaches the 40-airframe cap in two
years (28 before) — the last because of BUG-053, found by this phase's
re-run of the full suite: a rival holding an airframe it could not place
returned from its decision slot before managing routes or growing, and
SwiftJet's fourth turboprop at Osaka had nowhere to go, so it never
answered a 40% undercut (`aiRespondsToUndercutting`). Fixed in the
decision loop (a slot that placed nothing goes on), the suite is green at
450 and the scans above are from the fixed build. Collapses across the
150 campaigns: 30 → 0.

## 9. Profit-ranking re-evaluation (TD-030)

**WITHHELD.** Re-measured on the corrected economy across the same 150
campaigns (`ae-rival-scan --profit --rivals`):

1. *Does profit ranking now allow the regional archetype to function?*
   Yes: alive in 150 of 150, fleet 13–23, margin 0% (Paris) to +31%
   (Bangkok), net worth $125M–$219M — better than under the shipped
   basis from Paris ($125M against $93M).
2. *Does Stockholm become reachable?* No: 0 world-initiated entries in
   30 campaigns at the shipped horizon of sixteen. AE-039 measured it as
   reachable on this basis only at a horizon of 24.
3. *Does Barcelona become reachable?* No: 0 of 30.
4. *Does it improve rival economics?* For the regional archetype, yes
   (above). For the rest, within a few points of the shipped basis.
5. *Does it preserve long-term balance?* Not measured: the archetype
   battery and the ten-year world were run on the shipped basis only,
   and nothing ships on the profit basis.

Against that, the shipped basis reaches more player markets: 60
world-initiated entries across the 150 campaigns (Munich 30,
Singapore 29) against 31 on the profit basis (Munich 30, Singapore 0).
So the reason for withholding has changed — from "the regional archetype
cannot function on it" (no longer true) to "it reaches fewer player
markets at the shipped horizon" — and the combination AE-039 measured
(profit basis at a horizon of 24, which reached Stockholm on day 187 of
every seed) is now worth a phase of its own, with the balance battery
run on that basis before anything ships. RECOMMENDED FOR A FUTURE PHASE
as the evaluation; not shipped here.

## 10. Screenshots inspected

FRAMES_SECTION

## 11. Bugs found

| ID | Priority | Root cause | Player impact | Status |
| --- | --- | --- | --- | --- |
| BUG-051 | P1 | the movement fee scaled with nothing | a player's turboprop or regional jet paid a narrowbody's movements; no turboprop route in the world paid for itself | FIXED, TESTED (`FeeEconomyTests`), MEASURED |
| BUG-052 | P2 | the AI's estimator charged maintenance hourly; the ledger charges checks | AI only: the profit ranking saw an empty world | FIXED, TESTED |
| TD-031 | debt | the reference P&L never reconciled line by line; short haul fee-bound for every aircraft | short hub pairs lose money for everyone at the reference fare | recorded |

## 12. Testing

- **Core:** 450 tests, all passing (`swift test`, 1,596 s on this
  container), up from 441: nine new in `FeeEconomyTests` (scale,
  once-per-arrival posting and category, two types on one pair, the
  maintenance estimate against two years of checks, the whole estimate
  against a year, the archetype's markets from Paris, the archetype in
  the standard cast, long haul, the fee terms on the route card). No test
  weakened; one new test's authored bound (a 60% fee share) was replaced
  before the second run by the claims the fix makes (routes earn, the
  network keeps money) and the measured 60–62% is reported.
- **UI:** 19 journeys, unchanged in intent; the new fee-terms caption
  appears on the route screen in the existing frames. CI_RESULT
- **Campaign scans:** 150 campaigns before (five starts × thirty seeds,
  the pre-fix binary from a worktree at the last commit), 150 after on
  the shipped basis, 150 after on the profit basis — 450 two-year
  campaigns; plus 40 single-route years × 2 frequencies × before/after
  = 160 route-years, and 88 homes × 3 types of candidate evaluation
  before and after.
- **Balance batteries:** `archetypeParityAndSanity` (3 seeds × 5
  archetypes × 4 years), `tenYearWorldRemainsStableAndContested`,
  `contestedMarketsCompressMargins`, `leverageAmplifiesButDoesNotDominate`,
  `fleetFlippingBleedsMoney`, `pricingHasRealConsequencesEndToEnd` — all
  green on the shipped basis; not run on the profit basis.
- **CI:** CI_RUNS

## 13. Validation matrix

| Claim | READ | MEASURED | TESTED | COMPILED | RUNTIME VALIDATED | OBSERVED | AUTHORED | NOT VALIDATED |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Fee pipeline: two movements + arrival passenger fee, once per arrival, one category | ✓ | ✓ (memo-level) | `feesArePostedOncePerArrival` | ✓ | ✓ (headless) | — | — | — |
| Movement fee independent of aircraft (before) | ✓ | ✓ (40 routes, 542 candidates) | — | — | — | KEY-48 (run 122, before) | — | — |
| Seat scale anchored at 180; narrowbody unchanged to the cent | ✓ | ✓ (route battery before/after) | `movementFeeScalesWithSeats`, `smallAircraftPayLessPerMovement` | ✓ | ✓ | — | — | — |
| Estimator maintenance 9.8× the ledger (before), within 1.5% after | — | ✓ | `expectedMaintenanceMatchesTheLedger` | ✓ | ✓ | — | — | — |
| Whole estimate within a fifth of the ledger | — | ✓ (3% of revenue) | `estimateMatchesTheLedgerOnActualPassengers` | ✓ | ✓ | — | — | — |
| Regional archetype has markets from Paris | — | ✓ (11 of 16) | `regionalArchetypeHasViableMarketsFromParis` | ✓ | ✓ | — | — | — |
| Regional rival keeps money in the standard cast | — | ✓ (30 campaigns) | `regionalRivalKeepsMoneyInTheStandardCast` | ✓ | ✓ | — | — | — |
| Long haul not subsidised | — | ✓ | `longHaulIsNotSubsidised` | ✓ | ✓ | — | — | — |
| Player parity | ✓ | ✓ (to the cent) | (structural: no owner branch) | — | ✓ | — | — | — |
| The fee row's reason on the route screen | — | — | `routeCardCarriesTheFeeTerms` | parse + symbols | — | FRAMES_OBSERVED | ✓ | — |
| Long-run balance (archetype battery, ten-year world) | — | — | ✓ (450 green) | ✓ | ✓ | — | — | — |
| Regional-jet archetypes' margin shift is acceptable play | — | ✓ (+12–17 pts, under the 60% line) | — | — | — | — | — | ✓ a playtest question |
| The profit ranking's safety | — | ✓ 150 campaigns (functions; reaches fewer markets) | — | — | — | — | — | balance battery on that basis not run; not shipped |

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

- **Economy credibility:** improved, specifically. A 68-seat aircraft
  no longer pays a 180-seat aircraft's landing charges; fee shares by
  aircraft size now sit together (medians 0.43 / 0.40 / 0.38 for
  turboprop / regional jet / narrowbody, from 0.82 / 0.64 / 0.38). What
  is *not* improved and is now written down: the reference P&L's lines
  are still out of proportion with the design (TD-031) and short haul at
  hubs is still fee-bound for everyone.
- **AI credibility:** the regional archetype functions — 30 of 30 alive
  in the Stockholm cast with a positive network month, from 28 of 30 all
  losing — and the AI's profit view of the world now predicts the ledger
  within a few percent of revenue instead of charging ten times the
  maintenance. The two regional-jet archetypes grew 12–17 margin points;
  the balance line still holds them.
- **Player fairness:** unchanged in principle (parity was exact before
  and after) and better in practice: a player who buys the small aircraft
  the game offers first now faces the same fee-per-seat as the rivals'
  narrowbodies, and the route screen tells them what each end charges.
- **Campaign depth:** more regional-aircraft routes in the world's
  networks (SwiftJet's fleet 3 → 9 in two years from Stockholm); whether
  that reads as a busier, more credible cast to a player is NOT VALIDATED.

## 16. ONE recommended next master prompt

**AE-041 — Profit versus revenue rival strategy, with the horizon at 24.**

- **WHY NOW:** the one thing AE-039 could not ship — the profit basis —
  was withheld for a reason this phase removed (the regional archetype
  now functions on it: 150 of 150 alive, fleet 13–23) and one it did
  not (it reaches fewer player markets at the shipped horizon: 31
  world-initiated entries against 60). AE-039 measured that the profit
  basis at a horizon of 24 reaches Stockholm on day 187 of every seed,
  the one curated start no shipped configuration reaches. The question
  is now a clean strategy question — which basis, at which horizon,
  reaches the most player markets while keeping every battery green —
  and every tool to answer it exists (`--profit`, `--limit`, `--rivals`,
  the archetype battery).
- **EVIDENCE:** this report §9; docs/HORIZON_AUDIT.md §4 (C at 24: 30
  Stockholm entries); docs/REGIONAL_ARCHETYPE_AUDIT.md §5.
- **OUT OF SCOPE:** fee levels and the reference P&L (TD-031), the fare
  formula, new competitive UI, any player-targeting logic, notable
  history on Home (EXP-08) and the UI journey runtime (both real, both
  smaller than a rival strategy that decides whether the curated starts
  ever meet the world).

Not chosen: *Stockholm and Barcelona economy ordering* (that is this
prompt, stated as the outcome rather than the mechanism); *notable
history on Home* (P2, no new evidence); *UI journey runtime reduction*
(52 minutes at the step cap on a slow runner — real, and the cheaper
fix is a fixture for the Munich journey, worth doing inside whichever
phase next touches the journeys); *release-readiness validation* (not
until the world can reach the curated starts).
