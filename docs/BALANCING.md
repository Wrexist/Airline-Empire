# Airline Empire — Balancing (Phase 18)

Methodology per GAME_BALANCE §6: deterministic headless batteries; tuning
changes only with measured evidence; every change logged here.

## The battery (`BalanceTests`, runs in CI)

| Test | What it guards |
|---|---|
| `archetypeParityAndSanity` | 5 archetype-driven airlines (shared AI = player-identical commands), 3 seeds × 4 years: ≥60% survival (no impossible starts), no >¤3B wealth from ¤120M (no money printer), median net-worth spread < 6× (no dominant strategy), margins under the 60% printer line |
| `contestedMarketsCompressMargins` | two carriers on the anchor market for a year: operating margins < 25% — competition + the outside option compress rents |
| `passivityIsNotViableButNotInstantDeath` | idle cash survives but stagnates (era never advances, overhead bleeds); an idle leased fleet collapses |
| `leverageAmplifiesButDoesNotDominate` | identical expansion script ± max borrowing: leverage < 2.5× the honest baseline (interest drag works) yet stays usable |
| `fleetFlippingBleedsMoney` | 20 buy/sell cycles burn >5% of bankroll (spread + friction hold) |
| `tenYearWorldRemainsStableAndContested` | 10-year mixed world: monthly integrity, fuel/economy inside clamps, bounded entities, pax HHI < 0.7, ≥2 active operators |

## Findings log

### F-001 (2026-08-25): uncontested mega-market scarcity rents

> **ROOT-CAUSED 2026-08-27 by F-006** — the "capacity << pool" diagnosis
> below was the symptom of a 1000x unit error in airport populations, not
> an intended property of the economy. See F-006.
Archetype benches showed sustained **45–53% operating margins** on
uncontested routes at mega airports. Diagnosis: 2–3 daily round trips of
~180 seats against 5,000+/day demand pools → permanently full cabins;
margin is a scarcity rent, not an equation bug (the anchor market at
normal load sits at the designed single-digit margin, and the contested
test compresses margins below 25%). The AI's market scoring
(`pool/(incumbents+1)`) prefers virgin markets while any remain, so
nothing entered to compress the rent within 4 bench years.

**Action:** no equation change (evidence shows compression works when
entry happens; entry opportunity is exactly the signal a player reads
from fat routes). Bench assertion set at the 60% money-printer line with
the 3–8% design band enforced on contested markets. **Watch item for
post-macOS playtesting:** if human players find monopoly rents too easy
too long, the lever is AI market scoring — soften the incumbent divisor
(e.g. `(incumbents+1)^0.7`) so grown AIs contest big markets sooner.
That change should be made against playtest evidence, not bench worlds.

### F-002 (2026-08-25): leverage behaves
Max-borrowing expansion neither dominates (< 2.5× honest baseline; the
leverage-squared credit spread and annuity drag bite) nor bricks the
strategy (leveraged runs finish solvent with real net worth). No change.

### F-003 (2026-08-25): archetype parity holds at bench scale
Median 4-year net-worth spread across archetypes stayed within the 6×
band on all seeds; ≥60% survival. lowCost/expansionist lean on leases and
carry thinner margins; premium runs richest per passenger — the intended
texture. No change.

### F-004 (2026-08-26): the runway ladder is nearly inert

**Evidence.** Airport runway classes across the 80-airport dataset:
`veryLarge` 42, `large` 35, `medium` 2, `small` 1. Aircraft requirements
are turboprop→`small`, regionalJet→`medium`, narrowbody and
largeNarrowbody→`large`, widebody and largeWidebody→`veryLarge`. Since
eligibility is `airport.runwayClass >= aircraft.requirement`, reachability
is: turboprops 80/80, regional jets 79/80, narrowbodies 77/80, widebodies
42/80.

**Reading.** Only the widebody gate does real work. The design fantasy that
small fields *require* small aircraft (docs/AIRPORTS.md) is carried by
three airports out of eighty, so turboprops and regional jets justify
themselves almost entirely on capital cost and thin-route economics rather
than on airport access. That is a coherent game — small aircraft are the
low-capital entry rung — but it is not the game the runway ladder was
drawn for, and it makes the early fleet decision flatter than intended.

**Not changed.** Re-classing airports downward would reshape demand pools,
slot scarcity, and every AI network at once; the battery's current
calibration sits on this distribution. This is a content-design decision
for playtest, not an arithmetic defect. The lever, when wanted: move a
handful of low-population regional fields (not hubs) from `large` to
`medium`/`small` and re-run the battery, expecting turboprop utilization
and regional-route margins to rise.

### F-005 (2026-08-26): the aircraft roster carries no dead SKUs

Checked all 14 types pairwise across every axis a player can value —
seats, range, comfort, reliability, speed against burn, list price, lease,
maintenance, delivery lead, turnaround. **No type is strictly dominated.**
An earlier four-axis reading (seats/range/burn/price) suggested PA-228 was
dominated by MR-220; including comfort (0.60 vs 0.57) and delivery lead
(365 vs 420 days) shows the real trade — Pacifica sells denser, more
comfortable, thirstier airframes sooner; Meridian sells efficiency and
range. No content change. The invariant is now pinned by
`ContentQualityTests.noAircraftIsStrictlyDominated`.

### F-006 (2026-08-27): demand pools were 1000x too large — pricing was free

**The defect.** `AirportSpec.Demographics.populationThousands` held *raw
people*, not thousands: Tromso 80,000; Reykjavik 230,000; London
14,800,000; Tokyo 37,300,000 — real metro populations, exact. The gravity
model takes `sqrt(popA * popB)`, so every market pool came out exactly
**1000x** too large. Stockholm-London generated 863,647 passengers/day
against 540 seats/day of capacity: a ratio of ~1,600:1.

**Why it mattered.** Every route ran capacity-pinned at 100% load *no
matter what it charged*. Sweeping the fare on one MR-180 at 3x/day, before
the fix:

| Fare | Load | Passengers | Month P&L |
|---|---|---|---|
| 0.6x reference | 100% | 75,780 | ¤614k |
| 1.0x | 100% | 75,780 | ¤2.13M |
| 1.6x | 100% | 75,780 | ¤4.40M |
| 2.4x | 100% | 75,780 | ¤7.43M |

Identical passengers at every price; profit rising without bound. Pricing —
the central economic decision of the game — had no downside. The
exponential price utility was chosen in Phase 7 *specifically* to give an
interior revenue optimum (power-law was rejected for producing unbounded
monopoly revenue); the shipped content made that optimum unreachable, so
the model behaved exactly like the form that had been rejected.

**This root-causes F-001.** "Uncontested mega-market scarcity rents" was
recorded as a watch item with the diagnosis "capacity << pool". That was
the symptom. The cause was a unit error — the same class as the Phase 8
`tuning.json` cents bug, which was also 1000x.

**The fix.** All 80 airport populations divided by 1000, so the data now
matches the unit its field name declares. Nothing else changed: no tuning
constant, no formula, no capacity.

**After the fix**, same sweep:

| Fare | Load | Passengers | Month P&L |
|---|---|---|---|
| 0.6x | 100% | 75,780 | ¤614k |
| 1.0x | 99.5% | 75,380 | ¤2.12M |
| 1.3x | 92.8% | 70,355 | ¤3.00M |
| **1.6x** | 74.4% | 56,353 | **¤3.13M (optimum)** |
| 2.0x | 45.4% | 34,412 | ¤2.19M |

Price now moves volume, load factor responds, and profit has an interior
maximum — overprice and you fly empty seats.

**Why no other test moved.** At the *reference* fare demand (862/day) still
exceeds capacity (540/day each way), so default-fare load and revenue are
essentially unchanged (75,380 vs 75,780 passengers). The calibrated
baseline economy is undisturbed; what changed is that raising fares now
costs something. That is also why the battery never caught this: it never
ran a high-fare strategy. `BalanceTests.pricingHasRealConsequencesEndToEnd`
now does, through the full pipeline, and it fails on the old data with
exactly the diagnostics above.

**Watch next.** The profit optimum sits at ~1.6x the reference fare for an
uncontested mega-market. That is a monopolist's price and it should compress
toward the reference as rivals enter; F-001's counterweight now has real
teeth to apply. Worth re-measuring under contested conditions at playtest.

### F-007 (2026-09-02, AE-040): a movement cost the same whatever landed

**Evidence.** `ae-fee-baseline` (new; docs/FEE_ECONOMY_BASELINE.md) flew
forty single routes for a year each through the real pipeline. Airport
fees were the largest direct cost on every route under 1,600 km for
every aircraft (62–90% of fuel + fees + crew), and the share was a
per-flight ratio worst for the smallest cabin: on LHR–CDG the 68-seat
NA70's fees were 157% of revenue at 100% load against the MR180's 85%;
on JFK–ORD 75% against 40%. No turboprop route paid for its lease. The
regional archetype's own evaluation from Paris found all sixteen
candidates losing on money alone; worldwide its turboprop had 40
profitable candidates of 542 (docs/REGIONAL_ARCHETYPE_AUDIT.md). The
player paid the same to the cent.

**Reading.** `AirportSpec.movementFee` was charged per movement with no
term for the aircraft. Real landing charges follow aircraft weight; the
passenger fee already followed passengers. Not a level to tune — a scale
that was missing (BUG-051). Beside it, the AI's profit estimator charged
maintenance at the type's hourly rate where the fleet system books a
60-hour check per 500–650 flight hours: 9.8× the ledger (BUG-052,
docs/FEE_ECONOMY_ESTIMATOR_AUDIT.md).

**Action.** The movement fee is quoted for a 180-seat movement and
charged in proportion to seats (`OpsTuning.movementFeeReferenceSeats`,
integer cents), in the flight system and the estimator alike; the
estimator's maintenance line is the fleet system's check rule
integrated. No fee level moved; the MR180 pays exactly what it paid, so
the anchor economy and every battery calibrated on it are untouched by
construction. Rejected alternatives and risks:
docs/FEE_ECONOMY_FIX_DECISION.md.

**Not changed, recorded as TD-031.** The reference route P&L
(GAME_BALANCE §4) was never reconciled line by line: fees carry 1.6×
their designed weight, ownership 2×, fuel and crew a half, maintenance a
tenth; the total lands within 4% of the design. Short haul under 400 km
stays fee-bound for every aircraft (a $26–28 hub passenger fee against a
$60–69 fare).

## Tuning changelog

**2026-09-02 — movement fees scale with seats (F-007, AE-040).** New
`ops.movementFeeReferenceSeats: 180` in `tuning.json`; no existing
constant or airport value changed.

*Before / after, `ae-fee-baseline --rotations 2 --months 12`, average
month, seed 2039:*

| Route | Aircraft | Fees before → after | Fee share | Direct profit | All-in margin |
|---|---|---|---|---|---|
| LHR–CDG 347 km | NA70 | $793k → $428k | 157% → 85% | −$394k → −$30k | −170% → −97% |
| LHR–CDG | MR180 | $1.15M → $1.15M | 85% → 85% | +$64k → +$64k | unchanged |
| JFK–ORD 1,187 km | NA70 | $771k → $413k | 75% → 40% | −$57k → +$301k | −51% → −16% |
| JFK–ORD | AV90 | $836k → $539k | 63% → 40% | +$157k → +$454k | −35% → −13% |
| JFK–ORD | MR180 | $1.11M → $1.11M | 40% → 40% | +$1.24M | unchanged |
| ARN–LHR 1,462 km | AV90 | $666k → $439k | 43% → 28% | +$479k → +$707k | −10% → +5% |
| ARN–LHR | MR180 | $905k → $905k | 28% → 28% | +$1.83M | unchanged |
| LHR–JFK 5,541 km | MR300 (AI) | $625k → $930k | 9% → 11% | +$4.96M → +$5.62M* | 34% → 37%* |

\* the widebody month is a different month (twelve averaged against
one) — the movement part rose from $248k to $292k as designed (×1.66 on
fewer flights); the fee share rose two points.

*Candidate evaluation, the regional profile at every large-or-better
home, profit basis (`--candidates all`):*

| Type | Profitable candidates before → after | Homes with ≥ 1 |
|---|---|---|
| NA70 | 40 of 542 → 374 | 28 → 80 of 88 |
| AV90 | 294 of 747 → 504 | 69 → 86 |
| MR180 | 511 of 842 → 542 (the maintenance line only) | 80 → 84 |

*Estimator error on actual passengers (forty routes, $/day):* −3.3k to
−17k before → −0.6k to −5.3k after; what remains is the 5–10% of
scheduled rotations that do not fly and the fuel walk.

*Campaigns, five starts × thirty seeds, the regional rival:* alive 120 →
150 of 150; from Paris 1.7 routes all losing → 4.0 with 0.3 losing,
fees 103% → 61% of revenue, direct −$1.09M → +$1.08M a month. Cast
collapses 30 → 0. The regional-jet archetypes (conservative,
expansionist) gained 12–17 margin points; the expansionist now reaches
the 40-airframe cap in two years (28 before) after BUG-053 — an
unplaceable airframe had frozen a rival's route management and growth —
was found by the full-suite re-run and fixed. Battery: 450 tests green.



**2026-08-27 — airport populations corrected (F-006).** All 80 values in
`airports.json` divided by 1000 so `populationThousands` holds thousands,
not people. No tuning constant or formula changed.

*Before / after, uncontested STV-LNW, one MR-180 at 3x/day, 90 days:*

| Metric | Before | After |
|---|---|---|
| Load at reference fare | 100% | 99.5% |
| Passengers at reference fare | 75,780 | 75,380 |
| Load at 2x reference fare | 100% | 45.4% |
| Passengers at 2x reference fare | 75,780 | 34,412 |
| Profit-maximising fare | unbounded | ~1.6x reference |
| Full test suite | 251 passing | 251 passing |
| Release bench, 200 routes/200 aircraft/year | 13.64 s | 14.03 s (same sitting; noise — see PERFORMANCE.md caveat) |

Baseline economics at default pricing are materially unchanged; the change
restores the price mechanic. Pinned by
`BalanceTests.pricingHasRealConsequencesEndToEnd`.
