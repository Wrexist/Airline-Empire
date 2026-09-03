# AE-041 — Profit versus revenue: the rival strategy test

**Question.** Can rivals rank markets by airframe-day *profit*, with a
candidate horizon of 24, without breaking world activity, economic
balance or the player's experience — and is that better than the
shipped airframe-day *revenue* at sixteen?

**Answer.** No, and the shipped configuration stays. Measured across
600 two-year campaigns (four configurations × thirty seeds × five
curated starts) and twenty five-year ones: profit / 24 reaches
Stockholm on day 187 of every seed and never reaches Munich or
Singapore, in two years or five; the shipped revenue / 16 reaches
Munich on day 61 and Singapore in year two and never Stockholm. Every
rival entry on every basis earned by the rival's own ledger. Profit / 24
also fails the archetype battery's margin line (three runs at 65%).
What the profit basis did better — never opening a market it later
closed — turned out to be one AI bug (BUG-054, 143 of 150 campaigns)
and one thin turboprop pair, and the bug is fixed on the shipped basis.
The phase's production change is that fix; the ranking and the horizon
are untouched.

Labels: READ (from source), MEASURED (headless engine), TESTED (a test
in the suite), COMPILED, RUNTIME VALIDATED, OBSERVED (a rendered frame,
looked at), AUTHORED, NOT VALIDATED.

Companions: docs/AE041_STRATEGY_BASELINE.md (every number of the
matrix), docs/AE041_CURATED_START_AUDIT.md (the five starts),
docs/AE041_ECONOMIC_CREDIBILITY.md (the classifications and BUG-054).

## 1. What was read (READ)

`CompetitorAISystem` (the decision loop: survive, employ, tune, grow;
`candidateMarkets`, `airframeDayValue` on both bases, `rankingBasis`),
`AITuning` and tuning.json (`candidateMarketLimit` 16), `AIProfile`
(archetype thresholds, fare factors, fleets), `WorldSetup.createCompetitors`,
`AirportSpec.movementFee` and `FleetEconomics.expectedMaintenancePerDay`
(AE-040's corrections), `BalanceTests` (the batteries), `HorizonTests`,
`MunichHorizonTests`, `RivalPressureCampaignTests`, `ae-rival-scan` and
`ae-rival-probe` (the `--profit`, `--limit`, `--rivals`, `--horizon`
flags), `ae-fee-baseline`, docs/HORIZON_AUDIT.md, docs/AE040_FEE_ECONOMY_REPORT.md,
docs/REGIONAL_ARCHETYPE_AUDIT.md, docs/AI.md, docs/GAME_EXPERIENCE_PRIORITY.md,
tasks/TECH_DEBT.md, tasks/CURRENT_PHASE.md.

Decision record before measuring: the shipped behaviour is revenue / 16;
all four configurations were already measurable with the scan's flags
and no production change; a fair comparison needs the same seeds, homes,
script and duration and the same balance batteries run on each basis
(AE-040 had run them on the shipped basis only); an unfair one would
count entries without following the rival's ledger, or tune a horizon
to one city. What had to be added was measurement only: the scan
follows every entry and every opening through the rival's own months.

## 2. Scope decision

AE-040 closed with the profit basis functioning economically and
withheld on one remaining count (fewer player markets at sixteen) and
one unmeasured one (the battery on that basis). The phase asked the
question the evidence left open, on the tools that already existed,
and changed production only for a bug the measurement found.
EVIDENCE-BASED DECISION.

## 3. Baseline matrix (MEASURED)

Seeds 2030–2059, homes Stockholm, Barcelona, Munich, New York,
Singapore, 730 days, the shipped cast and script; 150 campaigns per
row. Balance = `BalanceTests` on that basis and horizon.

| Configuration | Horizon | World-initiated entries | Curated starts reached | Economic credibility | Balance | Validation |
| --- | ---: | ---: | ---: | --- | --- | --- |
| Revenue (shipped) | 16 | 59 (Munich 30 on day 61; Singapore 29 on days 509–551) | 2 | all 59 entries SOUND; 2,759 of 2,999 rival openings SOUND — the 240 others are BUG-054 (143) and the regional rival's Paris–Zurich held a year then dropped (92), plus 5 | pass (the CI suite) | MEASURED, TESTED |
| Revenue | 24 | 59 (the same days) | 2 | all SOUND; 2,754 of 2,912 (the 143 of BUG-054 remain; Paris–Zurich is no longer chosen) | not run — identical outcomes to the shipped row, not a candidate | MEASURED |
| Profit | 16 | 30 (Munich 30 on days 187–215) | 1 | all SOUND; 2,543 of 2,547 openings SOUND, no closures | **pass** — archetype parity 483 s, ten-year world 824 s | MEASURED, TESTED |
| Profit | 24 | 30 (Stockholm 30 on days 187–229) | 1 | all SOUND; 2,704 of 2,707, no closures; the regional rival carries 1.1–1.2 losing routes of 4.2 | **fail** — archetype parity: three runs at 65.5 / 65.5 / 65.2% against the 60% line; ten-year world re-run alone in §11 | MEASURED, TESTED |

Five years (twenty campaigns, seeds 2030–2034 × four starts): revenue /
16 reaches Munich 5 of 5 (day 61) and Singapore 5 of 5, Stockholm and
Barcelona 0; profit / 24 reaches Stockholm 5 of 5 (day 187) and nothing
else. Rivals lost in years three to five: 11 of 100 on revenue / 16, 7
of 100 on profit / 24 — both worlds lose a rival or two late, the
ten-year battery tolerates it, and nothing here changes it.

## 4. The winning strategy: the shipped one (EVIDENCE-BASED DECISION)

**Decision A — keep revenue / 16.** Scored on the prompt's seven
criteria:

| Criterion | Revenue / 16 | Profit / 24 | Profit / 16 |
| --- | --- | --- | --- |
| World activity | 59 entries, two starts; 2,999 openings; 749 rival frequency moves on the player's pairs | 30 entries, one start; 2,707 openings; 119 frequency moves | 30, one start (Munich, four months late) |
| Economic credibility | every entry SOUND; openings 92% SOUND before the fix, the rest one bug and one thin pair | 99.9% SOUND | 99.8% SOUND |
| Curated-start coverage | Munich (day 61), Singapore (year two) | Stockholm (day 187) | Munich (day 201) |
| Archetype health | regional alive 150 of 150, four routes, −7% margin from Paris; conservative 38% | regional 150 of 150, 4.2 routes with 1.1 losing, +6%; conservative 42% | regional 150 of 150, 3.0 routes, −1% |
| Long-run stability | ten-year battery pass; 11 of 100 rivals lost by year five | archetype battery **fails** on margin; 7 of 100 lost by year five | both batteries pass |
| Performance | 6.9 s a campaign | 6.0 s | 6.1 s |
| Player clarity | the Munich arrival on day 61, photographed in runs 121–129, unchanged | a Stockholm arrival on day 187 — never built, because the configuration does not ship — and the feed misses late entries (TD-032) | the Munich twin's timing and feed assertions fail |

Why profit / 24 lost: it covers one curated start where the shipped
basis covers two, it removes the one world-initiated event the app can
show, it crosses the battery's margin line, and its credibility
advantage is not a property of the basis (§6). Why profit / 16 lost:
it keeps Munich but four months later and loses Singapore, for no
coverage gain. Why revenue / 24 is not a change: the same world as
sixteen on every count.

**What changed in production:** nothing in the ranking or the horizon.
`CompetitorAISystem.rankingBasis` stays `.revenue` for the scan and
probe to flip; `candidateMarketLimit` stays 16. The one production
change is BUG-054's fix in the decision loop (§10), measured on the
shipped configuration before and after (§7).

## 5. Curated start results (MEASURED; docs/AE041_CURATED_START_AUDIT.md)

**Stockholm.** Not reached on the shipped basis (CASE A at sixteen;
inside a wider list the revenue basis still prefers Vienna). Reached
only by profit / 24: PacificBlue, NA160, ARN–IST, day 187, $187 against
the player's reference fare, 2× then 4× then 6× with three aircraft;
the rival earns $1.6–2.9M a month throughout; the player keeps 38–39%
at 99% load. Not shipped, so NOT VALIDATED on screen.

**Barcelona.** Not reached by anything: BCN–IST would win from Istanbul
on either basis and Barcelona is Istanbul's 26th airport, two places
outside 24; BCN–LHR and BCN–CDG are inside their lists and lose. A
horizon of 26 for one city is what the phase was told not to do, and
AE-039's sweep at 48 and 93 found no entry in two years anyway.

**Munich.** Shipped: PacificBlue, MUC–IST, day 61 in 30 of 30, $142
against $167, sound in every month; unchanged by the fix (the twin's
day, fares, share and headline identical, TESTED). Profit / 16: day
201. Profit / 24: never.

**Singapore.** Shipped: PacificBlue from Jakarta, CGK–SIN, days
509–551 in 29 of 30, $94, climbing to twenty rotations at 99–100% load,
sound. Profit: never — the 884 km pair keeps the least per airframe day
of anything from Jakarta.

**New York.** No entry in any configuration, because in 28 of 30 seeds
the scripted player has collapsed by day 430: it opened the two markets
the Next Moves card names, New York–Boston ($61) and New York–Toronto
($85), which lose $1.17M and $747k a month after the lease. BUG-055,
P1, root-caused in the player's opportunity ranking (passengers, the
rule the rivals dropped in AE-039), fix designed, not applied here
because it re-pins every campaign twin and journey (§16). The cast at
New York is healthy and its openings sound; the strategy question has
no New York evidence either way.

## 6. Economic credibility (MEASURED; docs/AE041_ECONOMIC_CREDIBILITY.md)

| Scenario | Estimate (profit basis, at the 2 rotations opened) | Ledger | Outcome | Classification | Validation |
| --- | ---: | ---: | --- | --- | --- |
| Munich–Istanbul, revenue / 16, day 61 (30 seeds) | $44.3–44.6k/day | +30 d: $1.5–1.6M/month at 4×; +180 d: $2.5–2.6M at 9×; day 730: $1.7–3.1M | flown to the end, three aircraft | SOUND ×30 | MEASURED, TESTED (Munich twin) |
| Stockholm–Istanbul, profit / 24, day 187 (30) | $70.5–71.9k/day | +30 d: $1.6–1.8M at 4×; +90 d: $2.2–2.5M at 6×; day 730: $1.7–2.9M | flown to the end; PacificBlue collapses in year four or five in 2 of 5 five-year seeds | SOUND ×30 | MEASURED |
| Jakarta–Singapore, revenue / 16, days 509–551 (29) | $20.8–21.7k/day | partial first month $119–187k; +90 d: $1.2–2.0M at 11–13×; day 730: $1.4–2.5M at 20× | flown to the end | SOUND ×29 | MEASURED |
| Munich–Istanbul, profit / 16, day 201 (30) | $43.4–44.2k/day | +30 d: $0.5M at 4×; +90 d: $2.5M at 9× | flown to the end | SOUND ×30 | MEASURED |
| Tokyo–Beijing, Crown Meridian, day 58 (143 of 150 revenue campaigns) | $37.8k/day | 74 flights at 95% load, +$734k in its first three weeks | **closed on day 79 by retrench after a $19.9M purchase on day 72**; the airframe sold | BAD — BUG-054, fixed | MEASURED, TESTED (`RivalCredibilityTests`) |
| Paris–Zurich, SwiftJet's turboprop, day 3 (88 of 150) | −$1.4k/day | +$93–105k/month for a year at 20× | closed days 364–686 after a losing month | ESTIMATOR ERROR (pessimistic) then CLOSED AFTER EARNING; not a bug, AE-040's forecast limitation | MEASURED |
| Every other rival opening, all four configurations (10,000+) | — | earning at +90/+180 days | flown | SOUND (2,759 / 2,754 / 2,543 / 2,704) | MEASURED |

The AI estimate matches the ledger's scale on every entered pair; on
the profit basis it is the reason for the entry and the ledger confirms
the order (Stockholm keeps more than Munich, $2.7M against $1.9M a
month, a month on).

## 7. Before / after (MEASURED)

The shipped configuration, 150 campaigns, before and after BUG-054's
fix (the "after" run is in §7.1; the 25-campaign sample, seeds
2030–2034 × five starts, is in docs/AE041_ECONOMIC_CREDIBILITY.md §3):

| Area | Before | After | Change | Validation |
| --- | --- | --- | --- | --- |
| Ranking basis, horizon | revenue, 16 | revenue, 16 | none | READ |
| World-initiated entries, 150 campaigns | 59 (Munich 30 day 61, Singapore 29) | §7.1 | | MEASURED |
| Rival routes closed before a full month | 143 | §7.1 | | MEASURED |
| Rival airframes gone within 30 days of arriving | 25 of 25 campaigns sampled (one each) | 1 of 25 (a leveraged purchase; the loan path is unchanged by design) | −24 | MEASURED |
| Rival openings SOUND | 2,759 of 2,999 (92.0%) | §7.1 | | MEASURED |
| Conservative archetype, seed 2039 Stockholm cast, day 150 | 2 routes, Tokyo–Beijing closed on day 79 | 3 routes, Tokyo–Beijing flown | | TESTED |
| Regional rival from Paris (25-campaign sample) | 4.0–4.2 routes, fleet 9.4–10.0, margin −8/−9% | 4.0 routes, fleet 8.2–8.4, margin −8/−10% | the 4-month archetype waits a little longer per turboprop | MEASURED |
| Munich twin (seed 2030) | entry day 61, $142 vs $167, share 0.39, headline and feed | identical | none | TESTED |
| Core tests | 450 | §11 | +1 (`RivalCredibilityTests`) | TESTED |
| Balance battery on the profit basis | not run (AE-040) | run at 16 (pass) and 24 (margin fail) | measured | TESTED |
| TD-030 | withheld, re-evaluate | closed: decided on evidence | | AUTHORED |

### 7.1 The 150-campaign after-measurement (MEASURED)

The same 150 campaigns (seeds 2030–2059 × five starts, 730 days) on
the fixed AI, shipped configuration:

| | Before | After | Change |
| --- | ---: | ---: | ---: |
| World-initiated entries | 59 — Munich 30 (day 61), Singapore 29 (days 509–551, median 537) | 59 — Munich 30 (day 61), Singapore 29 (days 509–551, median 537) | 0 |
| Entries SOUND by the rival's ledger, alive on day 730 | 59 | 59 | 0 |
| Rival openings | 2,999 | 2,982 | −17 |
| SOUND | 2,759 (92.0%) | 2,907 (97.5%) | +148 |
| Closed before a full month (BUG-054) | 143 | 0 | −143 |
| Closed after earning (Paris–Zurich and the like) | 92 | 67 | −25 |
| Loss-making, still flown | 2 | 7 | +5 |
| Rival routes closed, any reason | 235 | 67 | −168 |
| Rival airframes gone within 30 days of arriving | one per campaign in the 25-campaign sample | 12 in 150 (the unchanged loan path) | ≈ −140 |
| Idle rival airframes on day 730 | 746 | 714 | −32 |
| Rival collapses | 0 | 0 | 0 |
| Regional rival from Paris: routes (losing), fleet, direct/month, net worth, margin | 4.0 (0.3–0.4), 9.0–9.3, +$1.02–1.11M, $92–93M, −7/−8% | 4.2–4.3 (0.2–0.4), 8.9–9.0, +$0.89–0.92M, $89M, −9% | slower by one turboprop; alive 150 of 150 either way |
| Regional rival from Chicago / Bangkok | 15.2 / 22.2 airframes, +12% / +29% | 14.5 / 21.0, +12% / +29% | |
| Conservative / premium / expansionist / low-cost margins (European starts) | 38 / 32 / 21 / −4 to −6% | 37–38 / 32 / 21 / −4 to −6% | |
| Rival frequency increases on the player's pairs | 749 | 748 | −1 |
| Scripted New York player collapsed | 28 of 30 | 28 of 30 | 0 (BUG-055) |
| CPU per campaign (one process, beside the test suite) | 6.9 s (four in parallel) | 7.4 s | not comparable; both under 8 s |

The fix removed what it was meant to (the 143 early closures and the
buy-and-sell behind them) and touched nothing the player sees: the same
59 entries on the same days at the same fares.

## 8. Screenshots inspected

(§8 is filled from the CI run.)

## 9. Bugs found

| ID | Priority | Root cause | Player impact | Status |
| --- | --- | --- | --- | --- |
| BUG-054 | P2 | the AI's growth step measured the runway before the outlay and not after, and retrench ranked routes by a closed month they had not flown | a rival opens a route, flies it full, closes it three weeks later and sells the airframe it just bought — in 143 of 150 campaigns the same rival, the same fortnight | FIXED — TESTED (`RivalCredibilityTests`), MEASURED after |
| BUG-055 | P1 | `GameState.marketOpportunities` ranks by captured passengers over incumbents — the passenger ranking the rival AI dropped in AE-039 | from New York the Next Moves card names two fee-bound pairs; the scripted player who follows it collapses on day 430 in 28 of 30 seeds | OPEN — root-caused, MEASURED, fix designed (§16) |
| TD-032 (debt, not a bug of this phase's behaviour) | P2 | the feed is a 512-event ring; a busy world posts more than that in a day | a rival's entry on day 201 is on Home's headline and gone from the feed by morning (measured under the profit basis; NOT VALIDATED on the shipped basis's later entries) | RECORDED |

## 10. Bugs fixed

**BUG-054.** Fix: `CompetitorAISystem.acquireAircraft` takes a cash
floor — the archetype's own expansion runway in months of the latest
statement's costs — and a lease signing or used purchase that would
leave less waits for a richer month; the loan path (taken only when the
purchase is unaffordable outright) is unchanged; `retrench` chooses the
worst loss-maker among routes with a closed month of revenue. Two
variants were measured on the way: a floor at the retrench line stopped
the closures and left one buy-and-sell per campaign (the next
statement's costs pulled the runway back under the line); a floor at
the archetype's threshold with the loan sized to it left none but
slowed the premium archetype's leveraged growth enough to move the
seed-2039 London–Berlin fight (the rival-pressure twin's answer came 22
days after the invasion instead of within 7) — so the loan path was
restored as it was. Regression cover:
`RivalCredibilityTests.aRivalDoesNotBuyAnAirframeAndRetrenchAWeekLater`
(no rival route with a real schedule closes in the first 150 days, no
rival airframe goes within a month of arriving, Tokyo–Beijing is still
flown). Validation: TESTED; MEASURED on 25 campaigns (§7) and 150
(§7.1); the Munich twin unchanged; docs/AI.md rules 1 and 4 updated.

## 11. Testing

**Core (this container, Swift 6.0.3, debug).** `swift test`: 451
tests, 450 passed, 1 hit its time limit — `tenYearWorldRemainsStableAndContested`
at 1,898 s against a 900 s limit, run in parallel with the other
suites and a 150-campaign scan on four cores (31 min 40 s wall clock
for the suite). Re-run alone on the same build: §11.1. The suites the
phase touches, run by themselves on the fixed AI: 15 tests passed
(`RivalCredibilityTests`, `RivalPressureCampaignTests`,
`RivalPressureFixtureTests`, `MunichHorizonTests`,
`FirstEraCampaignTests`, `CompetitorAITests`; 5 min 6 s), and 29 with
`HorizonTests`, `AirframeDayProfitTests` and `FeeEconomyTests` beside
them.

**Batteries on the alternatives** (worktree, two lines changed):
profit / 16 — `BalanceTests` 7 of 7 passed (14 min 0 s; archetype
parity 483 s, ten-year world 824 s); profit / 24 — 5 of 7, archetype
parity failed on margin (65.5 / 65.5 / 65.2% > 60%), ten-year world
time-limited under load and re-run alone in §11.1.

**Campaign scans:** 600 two-year campaigns for the matrix, run twice
(1,200), plus 150 after the fix, 75 for the three fix variants, 50
five-year campaigns and the diagnostics (seed 2039 horizon reads for
four configurations, `--player`, `--follow`, `--openings`): about
1,500 campaigns in all.

**UI journeys:** §8 (the CI run).

### 11.1 The two slowest tests, and the time limits

Two Core tests carry wall-clock limits that the parallel runner can
breach under load with the code unchanged: `tenYearWorldRemainsStableAndContested`
(15 minutes) and `regionalRivalKeepsMoneyInTheStandardCast` (5
minutes). READ from the CI history before this phase pushed anything:
run 130 (commit b59c0ca, the AE-040 branch) passed all 450 with the
ten-year world finishing at 1,552 s of suite time; run 131 — the same
code merged to main as 0579b9f, this phase's base — **failed** with the
regional-rival test over its 300 s limit ("SWIFTJET after two years
from ARN: 4 routes, 4 earning" printed, then the limit), the ten-year
world passing at 1,570 s. Main was red on a time limit before AE-041
changed a line.

On this container, each test run by itself with nothing else on the
machine (MEASURED):

| Test (limit) | Pre-fix build (0579b9f) | Fixed build | Profit / 24 build |
| --- | ---: | ---: | ---: |
| `tenYearWorldRemainsStableAndContested` (900 s) | **858.6 s**, pass | **902.3 s**, over by 2.3 s | 874.7 s, pass |
| `regionalRivalKeepsMoneyInTheStandardCast` (300 s) | 128.3 s | 121.8 s | — |

The fixed cast keeps the routes it used to close, so the ten-year
debug simulation carries about 5% more flights and takes 5% longer;
on this container that is the whole of the limit's headroom. The
regional test is unchanged. On the CI runner the base commit's
ten-year world passed inside 900 s with unknown headroom (it finished
at 1,552 and 1,570 s of suite time in runs 130 and 131), and the
5-minute test — unchanged in cost — already crossed its limit there
once in two runs. Neither limit was touched by this phase; the CI run
in §8 is the measurement of whether the fixed world fits the runner,
and a limit set without headroom is recorded as a harness finding, not
hidden by a wider one.

## 12. Performance

The strategy did not change, so no strategy-related performance
measurement was required beyond what the matrix produced: campaign CPU
time per configuration (revenue / 16 6.9 s, revenue / 24 6.7 s, profit /
16 6.1 s, profit / 24 6.0 s, four running in parallel; MEASURED) and the
candidate evaluation cost in `HorizonTests.evaluatingAHorizonIsCheap`:
1,495 µs per evaluation at 16 candidates, 1,827 µs at 32, 1,998 µs at
94 (debug build, this container, the full suite running beside it;
AE-039 measured 1,660 / 2,030 / 2,340 µs on a quieter machine — the
same shape). BUG-054's fix adds one `usedPrice` and one comparison to a weekly
decision. Nothing runs per frame; nothing in the app calls the AI.

## 13. Validation matrix

| Claim | Label |
| --- | --- |
| The shipped behaviour, the four configurations, the batteries' assertions, the decision loop | READ |
| Entries, days, markets, rival ledgers, opening verdicts, cast health, five-year runs, runtimes, the New York collapse, the Crown Meridian narration, the fee baseline | MEASURED |
| BUG-054's fix; the Munich, horizon, campaign, AI, fee-economy and balance suites on the shipped basis; the batteries on the profit basis | TESTED |
| The Core package on Linux, debug and release | COMPILED (§11) |
| The app | RUNTIME VALIDATED / OBSERVED per §8 |
| BUG-055's fix shape, TD-032's fix shape, the report's readings of why a basis chose a market | AUTHORED |
| Any Stockholm arrival on screen; Singapore's arrival on screen; the feed on a late entry under the shipped basis; New York past day 61 on screen | NOT VALIDATED |

## 14. Remaining debt (ranked)

1. **BUG-055** — the player's Next Moves ranking sends the New York
   player to two fee-bound pairs; a player who follows the game's own
   guidance from a curated start collapses. P1, root-caused, not fixed
   here (it re-pins every campaign twin and journey).
2. **TD-026, narrowed** — Stockholm and Barcelona are not reached within
   two years on the shipped basis, by measured ranking and geography;
   the only configuration that reaches Stockholm loses two starts and a
   battery. No cheap lever remains; the honest lever is TD-031's
   economics, which decide which pairs keep money.
3. **TD-032** — the feed window can drop a rival's entry in a day in a
   busy world; the Home headline survives, the feed does not.
4. **Late-game rival collapses** — both bases lose a rival or two in
   years three to five (11 and 7 of 100); tolerated by the ten-year
   battery, not investigated here.
5. **The estimator on thin pairs** — pessimistic by $100k a month on
   Paris–Zurich for a turboprop (AE-040's known limitation, measured
   again).
6. **TD-031** — untouched, as required; short-haul fee/fare balance is
   what makes BUG-055's pairs losers.

## 15. Release impact

- Economic credibility: improved on the shipped basis — the one
  recurring irrational rival act (a route closed while full, an
  airframe sold a week after purchase) is gone; every entry the world
  makes on a player's pair earns. MEASURED.
- Rival credibility: unchanged in what the player sees (Munich, day 61,
  the same fares and split). TESTED; OBSERVED per §8.
- Player fairness: unchanged; rivals and player use the same commands
  and costs. The New York guidance defect (BUG-055) is a fairness issue
  against the player and remains open.
- Campaign depth: unchanged; Stockholm and Barcelona remain quiet
  starts for the world.
- Technical risk: low — twelve lines in the AI decision loop, no save
  change, no tuning change; the scan tooling grew (tooling only).
- Not release-ready: the repository has no device evidence, BUG-055 is
  open at P1, and the curated European starts are two of five reached.

## 16. ONE recommended next master prompt

**AE-042 — The player's Next Moves rank like the rivals do (BUG-055),
and the New York start.**

WHY NOW: this phase's binding constraint on "economically credible
airlines" was not the rival strategy — every rival entry earned on
every basis — but the player's own guidance, which still ranks markets
by passengers and from New York names two pairs that lose $1.17M and
$747k a month after the lease. In 28 of 30 seeds the scripted player
following it is bankrupt by day 430; no world-initiated pressure can
reach a player who is gone, and no release can ship a curated start
whose first advice is ruinous. The fix is one ranking rule the
codebase already has (`airframeDayValue`, revenue basis), and its
blast radius — the February picks of every campaign twin and journey —
is exactly why it needs a phase with the journeys re-photographed
rather than a side change here.

EVIDENCE: docs/AE041_CURATED_START_AUDIT.md §5; `ae-rival-scan 730 2030 JFK --player`
(collapse day 430, cash −$2.2M, administrations 1);
`ae-fee-baseline --pairs JFK-BOS,JFK-YYZ,JFK-ORD --types PA184 --rotations 2 --months 3 --seed 2030`
(Boston direct $16k on $1.29M with fees at 89%; Toronto $439k; Chicago
$1.24M; the $790k lease); `GameState.marketOpportunities` scoring by
`pool / (1 + incumbents)`; the AE-039 finding that the same rule sent
rivals to the same pairs.

OUT OF SCOPE: the rival ranking basis and horizon (decided here), the
fee levels and reference P&L (TD-031), the fare formula, the demand
system, new competitive UI, TD-032's feed window (worth doing inside
this phase only if the re-photographed journeys meet a late entry).

Not chosen: *TD-031 reference P&L* (the whole-economy recalibration; it
would move the anchor BUG-055's fix does not need moved); *EXP-08 /
TD-032 notable history on Home* (real, P2, smaller than a P1 that
bankrupts a start); *rival arrival timing and history* (no new evidence
that timing is the problem — Munich's day 61 and Singapore's year two
are measured and sound); *UI test runtime* (28 minutes, no longer the
constraint); *device validation* (not until a curated start's first
advice stops being ruinous).
