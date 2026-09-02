# The regional archetype (AE-040, Phase 3)

> What SwiftJet is, what it can see, and what happens to it. §1 READ
> from `AIProfile`, `CompetitorAISystem`, `WorldSetup`; §2–§4 MEASURED
> with `ae-fee-baseline --candidates` (the AI's own evaluation, every
> large-or-better airport as a home) and `ae-rival-scan --rivals` (real
> two-year campaigns, five homes × thirty seeds). §5 is the before/after
> once the fix landed.

## 1. The archetype (READ)

| Property | Value | Where |
| --- | --- | --- |
| Fare | 1.0× the reference fare | `AIProfile.priceFactor` |
| Service | standard ($9 per passenger onboard) | `serviceTier` |
| Fleet | turboprops first, then regional jets; the cheapest type in those categories, bought used at 12 years (NA-70 Fjord: 68 seats, 1,450 km, 505 km/h, 2.05 kg/km, $620/h maintenance, $21M list); buys, never leases; borrows to 40% debt | `preferredCategories`, `usedAgeYears`, `prefersLeasing`, `acquireAircraft` |
| Geography | home region only — every candidate outside the region is `regionExcluded` | `homeRegionOnly` |
| Home | the third-busiest large-or-better airport in the player's region (five rivals: three placed in the player's region, busiest first, archetypes in enum order — low-cost, premium, **regional**); from Stockholm, Barcelona or Munich that is **Paris (CDG)**; from New York, **Chicago (ORD)**; from Singapore, **Bangkok (BKK)** | `WorldSetup.createCompetitors` |
| Opening frequency | 2 rotations a day | `AITuning.initialRoundTrips` |
| Frequency behaviour | +1 rotation when load > 0.82 (up to 20); −1 when load < 0.35; close a one-rotation route whose last closed month lost money | `manageRoutes` |
| Acquisition | when cash runway ≥ 4 months and fleet < 40: the cheapest preferred type, used; a loan if the debt ratio stays under 40% | `decide`, `acquireAircraft` |
| Retrenchment | runway < 1.5 months: close the worst loss-maker, sell idle metal | `retrench` |
| Price response | matches an undercut plus 2%, floor 0.8× reference | `priceResponse` |
| Candidate horizon | the sixteen nearest airports to where an idle airframe sits | `horizon` |
| Ranking | what one airframe day sells (revenue basis, shipped); the profit basis is measured and withheld (TD-030) | `airframeDayValue` |
| Viability floor | 140 passengers a day available to the entrant | `minViableDailyDemand` |

## 2. What it sees on day one (MEASURED, current rules)

`ae-fee-baseline --candidates all --types NA70,AV90 --csv`: an airline of
the regional profile founded at each of the 88 large-or-better airports,
its sixteen-airport horizon evaluated by the AI's own
`candidateMarkets` on the profit basis (revenue less the estimator's
fuel, fees, crew, maintenance and service).

| Type | Homes | Candidates scored | Profitable | Homes with ≥ 1 profitable | Median fee share of revenue |
| --- | ---: | ---: | ---: | ---: | ---: |
| NA70 (68 seats) | 88 | 542 | **40** | **28** | 0.82 |
| AV90 (88 seats) | 88 | 747 | 294 | 69 | 0.64 |
| MR180 (180 seats, for comparison) | 88 | 842 | 511 | 80 | 0.38 |

By region, NA70: Europe 8 of 31 homes with a profitable market, North
America 3 of 16, East Asia 0 of 9, Oceania 0 of 4. The archetype's
actual homes:

| Home | Type | In horizon | Region-excluded | Ineligible (range) | Below floor | Unprofitable | Profitable | Best candidate |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| CDG (Paris) | NA70 | 16 | 0 | 0 | 0 | 16 | **0** | PRG 852 km, −$10.9k/day, fees 71% |
| CDG | AV90 | 16 | 0 | 0 | 0 | 16 | **0** | PRG, −$2.2k/day, fees 59% |
| ORD (Chicago) | NA70 | 16 | 1 | 8 | 0 | 7 | **0** | DEN 1,426 km, −$4.6k/day, fees 56% |
| ORD | AV90 | 16 | 1 | 4 | 0 | 3 | 8 | MEX 2,719 km, +$30.3k/day, fees 23% |
| BKK (Bangkok) | NA70 | 16 | — | — | — | — | 1 | KUL 1,221 km, +$2.0k/day |
| LHR | NA70 | 16 | 0 | 0 | 0 | 16 | 0 | BLL 790 km, −$9.3k/day |
| MUC | NA70 / AV90 | 16 | 0 | 0 | 0 | 16 / 16 | 0 / 0 | WAW −$9.2k / FCO −$11.1k |
| ARN | NA70 | 16 | 0 | 0 | 1 | 15 | 0 | VIE 1,286 km, −$0.4k/day, fees 46% |

Rejection reasons, NA70 at CDG: none by region (all sixteen are
European), none by range, none by slots, none by the passenger floor —
**all sixteen are rejected on money**, with fees 59–157% of revenue.
From Chicago, half the horizon is out of the turboprop's 1,450 km range
(eight of sixteen), and the seven it can reach all lose.

Answers to the brief's questions, on the current rules:

1. **Does the archetype have profitable routes?** From its actual
   European home, none, with either type. From Chicago, none with the
   turboprop it buys first; eight with the regional jet it buys second.
   Worldwide the turboprop has 40 profitable candidates at 28 of 88 homes.
2. **Why not?** Fees. On its best candidates fees are 46–71% of revenue
   before fuel, crew, maintenance and service; the ledger agrees (the
   route battery's NA70 rows, docs/FEE_ECONOMY_BASELINE.md §6.1).
3. **Airport fees?** Yes — the movement part, which does not scale with
   the 68-seat cabin (docs/FEE_ECONOMY_FIX_DECISION.md §1, cause 1).
4. **Aircraft economics?** No. Fuel, crew and (ledger) maintenance for
   the NA70 are 4–17% of revenue on its candidates; per seat-km its fuel
   burn is 0.030 kg against the MR180's 0.019 — heavier, but not the
   term that decides.
5. **Fare calibration?** Not the archetype's problem specifically: at
   1.0× reference it prices like the player. Short-haul fares against
   hub passenger fees are a separate finding (cause 4).
6. **Utilisation?** No. The turboprop flies 5–6 rotations a day under
   400 km; at 2 rotations or at maximum the fee share is identical.
7. **Route selection?** No. Every one of its sixteen candidates loses;
   ranking cannot pick a winner that does not exist.
8. **Multiple factors?** Two: the fee scale in the ledger (real), and
   the estimator's maintenance overstatement (in the profit basis only,
   docs/FEE_ECONOMY_ESTIMATOR_AUDIT.md), which turned "few" into "none".

## 3. The same candidates under the proposed rules (MEASURED arithmetic, before implementation)

`--candidates all --detail` prints every estimator line per candidate;
the alternative rules are applied to those lines:

| Rule | NA70 profitable / homes | AV90 | MR180 | NA70 median fee share |
| --- | ---: | ---: | ---: | ---: |
| current | 40 / 28 | 294 / 69 | 511 / 80 | 0.82 |
| estimator maintenance at the ledger's rate | 126 / 57 | 364 / 79 | 542 / 84 | 0.82 |
| movement fee scaled by seats/180 | 259 / 79 | 429 / 84 | 511 / 80 | 0.43 |
| both | **374 / 80** | **504 / 86** | 542 / 84 | 0.43 |

At the archetype's homes, both rules: CDG NA70 11 profitable (best PRG
+$10.3k/day), ORD NA70 7 (DEN +$13.4k), BKK 3, LHR 13, MUC 8, ARN 10, BCN
14. The narrowbody's numbers move only on the maintenance line.

## 4. Two-year campaigns (MEASURED, `ae-rival-scan --rivals`, current rules)

SCAN_BEFORE_SECTION

## 5. After the fix

AFTER_SECTION
