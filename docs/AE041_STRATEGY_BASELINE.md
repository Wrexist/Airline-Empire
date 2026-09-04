# AE-041 — Profit versus revenue: the strategy baseline

The four configurations the phase compared, measured on the same seeds,
homes, script and duration, before any production behaviour changed.
Every number here is MEASURED unless labelled otherwise; nothing was
edited by hand.

Labels: READ (from source), MEASURED (headless engine, `ae-rival-scan`),
TESTED (a test in the suite), AUTHORED (written, not yet validated),
NOT VALIDATED.

## 0. Method

**Tool.** `swift run -c release ae-rival-scan 730 2030-2059 ARN,BCN,MUC,JFK,SIN --rivals`
with `--profit` for the profit basis and `--limit 24` for the wider
horizon (docs/HORIZON_AUDIT.md §3.1 used the same flags). The scan plays
the scripted entrepreneur campaign — the guided first route, the
boom-region reaction, February's two Next-Moves markets, then one
aircraft and one market a month while the cash is there — and reads the
world back day by day. This phase extended the scan (tooling only,
nothing in the simulation): every world-initiated entry is followed
through the rival's own ledger at +30, +90 and +180 days and at the end
(`⇒ RIVAL LEDGER`); every rival opening anywhere is classified by its own
later months (`rival openings N: SOUND … BAD OPENING …`); rival routes
opened and closed, idle rival airframes, airframes disposed of within
thirty days of arriving, and the scripted player's own fate are counted
(`--player` narrates it; `--follow NAME` narrates one rival; `--openings`
lists every opening in order).

**Configurations.** The shipped one and three alternatives, nothing
else — no fifth configuration was needed to answer the question (§8):

| Key | Ranking basis (`CompetitorAISystem.rankingBasis`) | Candidate horizon (`candidateMarketLimit`) |
| --- | --- | ---: |
| A | revenue — what one airframe day sells (shipped) | 16 (shipped) |
| B | revenue | 24 |
| C | profit — the same less the flight system's costs | 16 |
| D | profit | 24 |

**Held constant.** Seeds 2030–2059 (thirty). Homes Stockholm (ARN),
Barcelona (BCN), Munich (MUC), New York (JFK), Singapore (SIN). 730
days. The entrepreneur scenario's cast (five rivals, one per archetype,
placed by `WorldSetup.createCompetitors`), starting cash, tuning and
content as shipped at commit 0579b9f (AE-040 closed). 150 campaigns per
configuration, 600 in all, run twice (the second run with the opening
classifier; the entry counts, days and markets were identical, as the
engine is deterministic).

**Machine.** This session's Linux container, four cores, the four
configurations run in parallel. One campaign alone takes ~7 s; in
parallel 6.0–6.9 s of CPU each.

## 1. World-initiated entries into the player's pairs

| Start | A · revenue / 16 | B · revenue / 24 | C · profit / 16 | D · profit / 24 |
| --- | --- | --- | --- | --- |
| Stockholm | 0 of 30 | 0 of 30 | 0 of 30 | **30 of 30** — PacificBlue (low-cost, Istanbul), ARN–IST, day 187 in 27 seeds, 201 in two, 229 in one |
| Barcelona | 0 | 0 | 0 | 0 |
| Munich | **30 of 30** — PacificBlue, MUC–IST, day 61 in every seed | 30 of 30, day 61 | 30 of 30 — days 187 (1), 201 (28), 215 (1) | 0 |
| New York | 0 | 0 | 0 | 0 (the scripted player collapses; §7) |
| Singapore | **29 of 30** — PacificBlue (Jakarta), CGK–SIN, days 509–551 (median 537) | 29 of 30, same days | 0 | 0 |
| **Total** | **59** | **59** | **30** | **30** |
| Curated starts reached | 2 (Munich, Singapore) | 2 | 1 (Munich, four months later) | 1 (Stockholm) |

Every entry, in every configuration, was by the low-cost archetype with
a 162-seat NA160 at 0.85 × the reference fare, opened at two rotations.

The horizon alone changes nothing on the revenue basis (A = B on every
count above), as AE-039 found. On the profit basis the horizon decides
*which* start is reached: at 16 Istanbul's list holds Munich and the
rival reaches it fifth (after Berlin, Milan, Prague and Lyon, day 201);
at 24 the list holds Stockholm, whose 2,177 km pair keeps more per
airframe day than anything nearer, and the rival takes it third (day
61 in a Munich campaign where nobody flies it; day 187 in the Stockholm
campaign, where the player's incumbency shrinks the entrant's pool and
the rival goes elsewhere first). At 24, Munich falls behind Palma,
Prague, Amsterdam and the rest and is never opened — not within two
years, and not within five (§4). The opening orders, seed 2039 from
Istanbul (`--openings`):

| Basis / horizon | PacificBlue's markets in order |
| --- | --- |
| A revenue / 16 | BER d5 · MXP d19 · **MUC d61** · PRG d173 · FCO d187 · WAW d229 · CAI d285 |
| C profit / 16 | BER d5 · MXP d19 · PRG d61 · LYS d173 · **MUC d201** · HAM d257 |
| D profit / 24 | BER d5 · MXP d19 · **ARN d61** · PMI d201 · PRG d215 · AMS d257 |

## 2. What the entries did, and what they cost the rival

Every world-initiated entry was followed through the rival's own ledger.
All 178 of them (59 + 59 + 30 + 30) are classified SOUND: the route
earned in every closed month sampled and was still flown on day 730.

| Entry | AI estimate at opening (profit basis, at the 2 rotations opened) | +30 days | +90 days | +180 days | Day 730 | Player a month on |
| --- | ---: | --- | --- | --- | --- | --- |
| A · Munich–Istanbul, day 61 | $44–45k/day ($1.3M/month) | direct $1.5–1.6M on $3.0M, load 97%, 4×, 1 aircraft | $2.4M on $5.5–5.6M, load 85–86%, 8×, 3 aircraft | $2.5–2.6M on $6.8–6.9M, load 74%, 9× | $1.7–3.1M on $6.0–7.5M, load 62–67%, 9× | share 39%, load 100%, last month $1.9–2.0M |
| C · Munich–Istanbul, day 201 | $43–44k/day | $0.5M on $1.0M, load 97%, 4×, 2 aircraft | $2.5M on $5.4M, load 80%, 9× | $1.7–2.2M on $6.5M, 67% | $1.9–3.0M on $6.0–7.3M | share 39% |
| D · Stockholm–Istanbul, day 187 | $70–72k/day ($2.1–2.2M/month) | $1.6–1.8M on $2.7–2.9M, load 95%, 4×, 2 aircraft | $2.2–2.5M on $5.7–5.9M, 69–70%, 6×, 3 aircraft | $1.4–2.3M on $5.3–5.6M, 59–62% | $1.7–2.9M on $5.0–7.1M, 54–61%, 6× at $187 | share 38–39%, load 99%, last month $2.4–3.1M |
| A · Jakarta–Singapore, days 509–551 | $21–22k/day ($624–650k/month) | $119–187k on $364–516k, load 98%, 4–5×, 1 aircraft | $1.2–2.0M on $2.8–5.1M, 98–99%, 11–13× | $1.1–2.5M on $2.7–6.1M, 99–100%, 20× | $1.4–2.5M on $3.3–6.0M, 99–100%, 20× at $94 | share 37–39%, load 100%, last month $1.0–1.3M |

The estimate is the same scale as the first full month on every pair
(the +30-day month is at four rotations, the estimate at two), and the
route then grows past it; the rival keeps building for the rest of the
campaign. Whatever the basis, the market a rival came to was one worth
coming to.

## 3. Every rival opening, judged by its own ledger

Not only the player's pairs: every route any rival opened in the 150
campaigns, classified on its own later months (SOUND: earning at +90 or
+180 days and still flown; BAD OPENING: closed after never earning;
CLOSED AFTER EARNING: earned, then closed after a losing month; CLOSED
BEFORE A FULL MONTH: gone before it had flown a closed month).

| | A · revenue / 16 | B · revenue / 24 | C · profit / 16 | D · profit / 24 |
| --- | ---: | ---: | ---: | ---: |
| Rival openings | 2,999 | 2,912 | 2,547 | 2,707 |
| SOUND | 2,759 (92.0%) | 2,754 (94.6%) | 2,543 (99.8%) | 2,704 (99.9%) |
| Loss-making, still flown | 2 | 12 | 3 | 3 |
| Closed after earning (a losing month after earning ones) | 92 | 0 | 0 | 0 |
| Closed before a full month | 143 | 143 | 0 | 0 |
| Too young to judge | 3 | 3 | 1 | 0 |
| Rival routes closed, any reason | 235 | 143 | 0 | 0 |
| Rival collapses | 0 | 0 | 0 | 0 |
| Idle rival airframes on day 730 (all campaigns) | 746 | 747 | 710 | 702 |

The two revenue-basis blemishes are each one thing:

- **143 closed before a full month** — in 143 of 150 campaigns the
  conservative archetype (Crown Meridian, Tokyo) opened its third route,
  flew it full, and closed it three weeks later. Diagnosed with
  `--follow "Crown Meridian"` (docs/AE041_ECONOMIC_CREDIBILITY.md §3):
  on day 72, with a six-month cash runway, its growth step bought a used
  airframe that left it one month of cash; on its next slot, day 79,
  the retrench rule fired, closed the worst "loss-maker" by last closed
  month — the new route, whose closed month was two days of costs and no
  revenue while it was flying at 95% load and $734k in the month
  under way — and sold the airframe it had bought a week before. That
  is BUG-054, fixed in this phase; the profit basis simply never put
  the conservative on that cash path in these seeds.
- **92 closed after earning** — SwiftJet (regional, Paris) opening
  Paris–Zurich on day 3 in 88 campaigns (Paris–Nice in 4): the market
  that sells the most per turboprop day from Paris, which the profit
  estimate puts at −$1.4k/day and the ledger at +$93–105k a month for a
  year (the estimate under-reads the pool on a thin pair; the AE-040
  limitation). It is closed in the second year (days 364–686, median
  490) after a losing month, by the retrench rule, at 20 rotations and
  three aircraft. At horizon 24 the regional rival finds Warsaw, Bergen
  and Oslo instead and Paris–Zurich is not opened.

On the profit basis the three loss-making-but-flown routes are
TerraLink's Jakarta–Bali and Colombo–Delhi in a losing month at +180
days after profitable ones — a fluctuation, not a wrong opening.

## 4. The cast, and the regional archetype

Two years, thirty seeds, averages over the 30 campaigns from each start
(margin = the rival's own operating margin on its latest statement):

| | A · revenue / 16 | B · revenue / 24 | C · profit / 16 | D · profit / 24 |
| --- | --- | --- | --- | --- |
| Regional rival alive (150 campaigns) | 150 | 150 | 150 | 150 |
| Regional from Paris (ARN/BCN/MUC starts): routes (losing), fleet, direct/month, net worth, margin | 4.0 (0.3–0.4), 9.0–9.3, +$1.02–1.11M, $92–93M, −7 to −8% | 4.0 (0.4–0.5), 12.1, +$2.31–2.33M, $122M, +2% | 3.0 (0.3), 13.1, +$1.99–2.00M, $125M, −1% | 4.2 (1.1–1.2), 14.2–14.3, +$3.07–3.10M, $139M, +6% |
| Regional from Chicago (New York start) | 3.9 (0.0), 15.2, +$4.72M, $157M, +12% | same | 2.0 (0.0), 15.9, +$3.66M, $152M, +10% | 2.0, 15.9, +$3.68M, $152M, +10% |
| Regional from Bangkok (Singapore start) | 3.0 (0.0), 22.2, +$10.55M, $215M, +29% | same | 3.0, 22.7, +$10.99M, $219M, +30% | same as C |
| Low-cost margin, European starts | −4 to −6% | −6 to −7% | −4 to −7% | −3 to −8% |
| Premium margin, European starts | 32% | 32% | 32% | 31–32% |
| Conservative margin | 38% | 38% | 42% | 42% |
| Expansionist margin | 21–22% | 21–22% | 21% | 21% |
| Rival openings at the player's airports, five starts | 261 / 168 / 190 / 177 / 232 | 228 / 120 / 229 / 177 / 232 | 212 / 212 / 186 / 120 / 147 | 247 / 127 / 246 / 120 / 147 |
| Rival frequency increases on the player's pairs | 749 (MUC 227, SIN 522) | 745 | 201 (MUC) | 119 (ARN) |
| Rival price cuts on the player's pairs | 0 | 0 | 0 | 0 |

The regional archetype is healthy on every basis (AE-040's fix holds);
the profit basis gives it a bigger fleet and a better margin, and at
horizon 24 more losing routes (1.1–1.2 of 4.2: the wider list admits
1,200–1,450 km pairs its estimator likes and its ledger does not). The
conservative archetype's margin rises four points on the profit basis;
nothing crosses the battery's 60% line (§6).

## 5. Five years

Twenty campaigns (seeds 2030–2034 × Munich, Singapore, Barcelona,
Stockholm), 1,825 days, the shipped basis against profit / 24; profit /
16 on Stockholm and Barcelona only (ten campaigns):

| | A · revenue / 16 | D · profit / 24 | C · profit / 16 (ARN, BCN) |
| --- | --- | --- | --- |
| World-initiated entries | 10 — Munich day 61 (5 of 5), Singapore days 509–537 (5 of 5); Stockholm 0, Barcelona 0 | 5 — Stockholm day 187 (5 of 5); Munich 0, Singapore 0, Barcelona 0 | 0 |
| Player-initiated entries | 5 (Munich) + 1 (Singapore) | 1 (Singapore) | 5 (Barcelona) |
| Rival collapses in years 3–5 (rivals founded minus rivals alive at the end) | **11** in 20 campaigns (PacificBlue on the Munich pair on days 1,070 and 1,556 of two seeds; SwiftJet on Paris–Munich on days 1,225 and 1,405; the rest away from the player's pairs) | **7** in 20 (PacificBlue on the Stockholm pair on days 1,282 and 1,770) | 6 in 10 |
| Rivals alive at day 1,825 (mean of 5) | 4.45 | 4.65 | 4.4 |

Munich is not reached in five years on profit / 24, and Stockholm not
on revenue. Both worlds lose rivals in the out-years — the shipped
basis more — which the ten-year battery tolerates (at least two
operators) and no configuration in this phase changes.

## 6. Balance batteries

Run in a separate worktree with only the two lines that define the
configuration changed (`rankingBasis = .profit`;
`candidateMarketLimit` in tuning.json), debug build, on a quiet machine
(a first attempt under the four-way scan load hit the battery's 600 s
and 900 s time limits, which measures the machine, not the world):

| Configuration | `archetypeParityAndSanity` (3 seeds × 5 archetypes × 4 years) | `tenYearWorldRemainsStableAndContested` | The other five | Wall clock |
| --- | --- | --- | --- | --- |
| A · revenue / 16 (shipped) | pass | pass | pass | (the CI suite; 450 green at AE-040) |
| C · profit / 16 | **pass** (483 s) | **pass** (824 s) | pass | 14 min 0 s |
| D · profit / 24 | **fail** — three archetype runs at 65.5%, 65.5% and 65.2% operating margin against the 60% line (524 s) | time limit (900 s) exceeded at 922 s under a concurrent scan and test build; re-run alone in §6.1 | pass | 15 min 23 s |

AE-039 withheld the profit basis partly because three archetype runs
crossed the 60% margin line; after AE-040's fee scale that is no longer
so. The battery is not what separates the configurations now.

### 6.1 Profit / 24 battery

The margin failure is the AE-039 finding back at the wider horizon: with
24 candidates and the profit ranking, three of the fifteen archetype
runs (three seeds × five archetypes over four years) keep only their
best markets and cross the battery's money-printer line at 65%. At
horizon 16 on the same basis every run is under it. That is stop
condition 5 for profit / 24 on its own, before the coverage result in
§1 is even weighed. The ten-year world's time limit was a machine
measurement (the profit / 16 run of the same test took 824 s on a
quiet machine, against a 900 s limit); its re-run alone is recorded in
docs/AE041_PROFIT_VS_REVENUE_REPORT.md §11.

## 7. The scripted New York player

In 28 of 30 New York campaigns — in every configuration — the scripted
player ends the two years collapsed (`--player`): it opens New York–
Chicago on day 1 with $59M, on day 31 buys a used narrowbody and leases
another and opens the two markets the Next Moves card names, New York–
Boston ($61) and New York–Toronto ($85), and bleeds at −$811k a month
until administration and collapse on day 430. `ae-fee-baseline` flies
the same pairs with the same aircraft at two rotations: Boston keeps
$16k a month of direct operating profit on $1.29M of revenue (fees 89%
of it) against a $790k lease; Toronto $439k against the same lease;
Chicago $1.24M. The card ranks markets by passengers captured, the rule
the rival AI stopped using in AE-039 for the same reason; a player who
follows it from New York opens two fee-bound pairs that cannot pay for
an aircraft. Recorded as BUG-055 (docs/AE041_CURATED_START_AUDIT.md
§5); no rival can enter a market the player has left, so New York
measures the cast, not the arrival.

## 8. Why no fifth configuration

The prompt allowed one with a reason. The evidence gave none: horizon
size does nothing on the revenue basis (A = B), and on the profit basis
the horizon only trades Munich for Stockholm — 16 reaches Munich late
and 24 reaches Stockholm and loses Munich for five years. A profit
horizon between them (Stockholm is Istanbul's 22nd-nearest airport) would
be tuned to one curated start, which is the thing this phase was told
not to do.

## 9. Runtime

| Configuration | 150 campaigns, CPU seconds (four in parallel) | Per campaign |
| --- | ---: | ---: |
| A · revenue / 16 | 1,036 | 6.9 s |
| B · revenue / 24 | 1,012 | 6.7 s |
| C · profit / 16 | 916 | 6.1 s |
| D · profit / 24 | 905 | 6.0 s |

The profit basis is a little faster because its rivals open fewer routes
and fly fewer flights; the wider horizon costs nothing measurable at the
campaign level. Candidate evaluation cost is unchanged from AE-039
(`HorizonTests.evaluatingAHorizonIsCheap`, §12 of the report).

## 10. After BUG-054's fix (MEASURED)

The shipped configuration re-run on the fixed AI over the same 150
campaigns: 59 entries (Munich 30 on day 61, Singapore 29 on days
509–551), all SOUND and alive on day 730; rival openings 2,982 of which
2,907 SOUND (97.5%, from 92.0%), 0 closed before a full month (from
143), 67 closed after earning (from 92), 7 loss-making still flown, 1
too young; rival routes closed 67 (from 235); airframes gone within
thirty days 12 in 150 campaigns (from one a campaign); idle rival
airframes 714 (from 746); rival collapses 0; the regional rival alive
150 of 150 with 4.2–4.3 routes from Paris on a fleet of 8.9–9.0 (from
9.0–9.3) and a margin of −9% (from −7/−8%); the scripted New York
player collapsed in 28 of 30 (BUG-055, unchanged). Wall clock 18 min
26 s for the 150, one process beside the test suite.
