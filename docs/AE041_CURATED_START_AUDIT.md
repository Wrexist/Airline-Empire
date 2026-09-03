# AE-041 — Curated start audit

The five starts, each answered separately, under the shipped
configuration (revenue / 16) and the alternative the prompt named
(profit / 24), with the other two where they differ. Every figure is
MEASURED with `ae-rival-scan` (seeds 2030–2059, 730 days; `--horizon`
diagnostics on seed 2039 at day 730) unless labelled otherwise.

## 1. Stockholm (ARN)

| | Revenue / 16 (shipped) | Profit / 24 |
| --- | --- | --- |
| Which rival can reach the player's market? | none within two or five years. PacificBlue (low-cost, Istanbul) is the only rival whose airframe can reach Stockholm on a pair the player flies (ARN–IST, 2,177 km); Aurora Atlantic (premium, London) sees ARN–LHR at rank 27 of its list; SwiftJet's turboprop is out of range (1,450 km against 1,462 to London, 1,539 to Paris) | **PacificBlue, ARN–IST** |
| Why it selects it | it does not: Stockholm is Istanbul's 22nd-nearest airport, outside sixteen; and inside the sixteen, on the revenue basis, Vienna sells more per airframe day (ARN would score 107,591 against the winner's 114,945 at day 730, CASE A) | Stockholm is inside 24, and 2,177 km at $187 keeps $70–72k an airframe day, third in Istanbul's list after Berlin and Milan |
| Entry day | — | 187 in 27 seeds, 201 in two, 229 in one |
| Rival aircraft | — | NA160, 162 seats; two aircraft by +30 days, three by +90 |
| Rival fare | — | $187 (0.85 × reference) against the player's reference fare |
| Rival frequency | — | 2×, then 4× at +30 days, 6× from +90 days |
| What the player loses | nothing from the world; the pair stays the player's alone | share 38–39% of the pair's passengers a month on, at 99% load — the player's two rotations stay full; last month $2.4–3.1M |
| Does the route stay rational? | — | yes: the rival's ledger $1.6–1.8M at +30 days, $2.2–2.5M at +90, $1.4–2.3M at +180, $1.7–2.9M on day 730, every month positive, 30 of 30 SOUND |
| If the player does nothing | the campaign continues uncontested on ARN–IST | the player keeps 38–39% at full load; the rival grows to six rotations; in two of five five-year seeds PacificBlue collapses in year four or five (days 1,282 and 1,770) and the pair is the player's again |
| If the player responds | — | NOT MEASURED in a twin (no twin exists for a configuration that does not ship); the Munich twin's finding — another rotation keeps the money, a fare cut keeps the share — is the same mechanism |
| On the rendered UI | the campaign journey from Stockholm (seed 2039) shows no rival entry; its fight is the one the player picks, London–Berlin | NOT VALIDATED: no journey was built for a configuration that does not ship |

**Root cause of the silence on the shipped basis:** CASE A at horizon
16 (outside Istanbul's sixteen), and inside a wider list the revenue
basis still prefers the nearer, larger pairs. The profit basis is the
only measured ranking that puts a 2,177 km pair above them, and it needs
the horizon to see it. Range rules out SwiftJet; Aurora at London ranks
Stockholm 19th–23rd of its scored world on either basis.

## 2. Barcelona (BCN)

| | Revenue / 16 | Profit / 24 |
| --- | --- | --- |
| Rival able to reach the player's market | none within two or five years, on any basis | none |
| Candidate availability | BCN–IST from Istanbul: **would win** — at day 730 it scores 123,167 against the inside winner's 114,945 — but Barcelona is Istanbul's 26th-nearest airport (CASE A). BCN–LHR from London: rank 20, would lose to Munich (160,981 vs 186,275). BCN–CDG from Paris: inside SwiftJet's sixteen (rank 16), scores 44,035 against Zurich's 51,312 (CASE B) | BCN–IST: rank 26 of 24, would win (70,403 vs Lyon's 64,205). BCN–LHR: inside, 76,401 vs Madrid's 83,808 (CASE B). BCN–CDG: inside, 8,101 vs Gothenburg's 11,282 |
| Range | every European rival's airframe reaches Barcelona | same |
| Why the player's market does not rise | two places outside the only list in which it would win, on both bases; the AE-039 sweep at 48 and 93 airports found no entry within two years either, because a wider list also admits Cairo, Istanbul, Madrid ahead of it at the start, and by the time Barcelona is the best market left the rival has nothing idle to place | same |
| Five years | 0 of 5 on either basis (AE-039 measured 3 late entries at 16 on the passenger ranking; none now) | 0 of 5 |

**Root cause:** the horizon by two places from the one rival that would
choose it, on either basis — the opposite of Stockholm, which the
revenue basis would not choose at any horizon. Not forced: a horizon
of 26+ for the sake of one start is what this phase was told not to
do, and the AE-039 sweep shows it would not deliver an entry in two
years anyway.

## 3. Munich (MUC)

| | Revenue / 16 (shipped) | Profit / 16 | Profit / 24 |
| --- | --- | --- | --- |
| Entry | PacificBlue, MUC–IST, day 61 in 30 of 30 | day 187 (1), 201 (28), 215 (1), 30 of 30 | none in two years; none in five |
| Why | Munich is Istanbul's ninth-nearest airport and the third-best seller per airframe day after Berlin and Milan | on the profit basis Prague and Lyon keep more; Munich is fifth | Stockholm, Palma, Prague, Amsterdam and the rest keep more; at day 730 MUC–IST is the best market PacificBlue can see (IN REACH, 65,656) but its airframes go to thickening its routes |
| Rival aircraft, fare, frequency | NA160 at $142 (player $167), 2× → 4× at +30 days → 8–9× with three aircraft | the same at day 201 | — |
| Player a month on | share 39%, load 100%, last month $1.9–2.0M; trailing on fare with a rotation to spare (the twin) | share 39% (the twin under profit: entry day 201, same split) | — |
| Rational? | 30 of 30 SOUND: $1.5–1.6M at +30, $2.4M at +90, $2.5–2.6M at +180, $1.7–3.1M on day 730 | 30 of 30 SOUND | — |
| Player does nothing / responds | the Munich twin, unchanged: another rotation keeps the money, a fare cut keeps the share; the advice line says so (BUG-049) | the twin's assertions on timing fail (entry ≤ 120) and the feed event is missing the next morning (§3.1) | — |
| On the rendered UI | OBSERVED at AE-039/040 (runs 121–129, KEY-HZ1…HZ6); unchanged by this phase's fix — the twin's entry day, fares, share and headline are the same on the fixed build (TESTED) | — | — |

### 3.1 A finding under the profit basis: the feed event at day 201

`MunichHorizonTests` under profit / 16 records the entry on day 201
with the Home headline correct and `feedEventNextMorning` false: the
`marketEntered` event is no longer in `eventLog.recent` the next
morning. The log is a 512-event ring (`BoundedEventLog.defaultCapacity`),
and by day 201 a busier world produces more than 512 events in a day,
so a rival's entry can roll off the feed before the player's next
visit. On the shipped basis the entry is on day 61 and the event is
present (the twin passes). Not a strategy result — a feed-window
limitation the same shape as EXP-08 (docs/GAME_EXPERIENCE_PRIORITY.md);
recorded in tasks/TECH_DEBT.md as TD-032. NOT VALIDATED on screen.

## 4. Singapore (SIN)

| | Revenue / 16 (shipped) | Profit (either horizon) |
| --- | --- | --- |
| Entry | PacificBlue (low-cost, Jakarta), CGK–SIN, days 509–551 (median 537) in 29 of 30 | none in two years; none in five |
| Why | Singapore is Jakarta's nearest airport; on the revenue basis Kuala Lumpur, Shanghai, Saigon sell more, so it comes in year two once they are taken | on the profit basis the 884 km pair at $94 keeps $21k an airframe day, last of eleven from Jakarta (Bangkok keeps $78k); at day 730 it is #11 of 11 |
| Rival aircraft, fare, frequency | NA160 at $94, 2× → 4–5× at +30 days → 11–13× at +90 → 20× (the cap) at +180 with one or two aircraft | — |
| Player a month on | share 37–39%, load 100%, last month $1.0–1.3M | — |
| Rational? | 29 of 29 SOUND: $119–187k in the partial first month, $1.2–2.0M at +90, $1.1–2.5M at +180, $1.4–2.5M on day 730 at 99–100% load | — |
| Player does nothing | the rival climbs to twenty rotations on the pair within six months; the player's two rotations stay full (the pair has 2,700–3,200 passengers a day) | — |
| On the rendered UI | NOT VALIDATED: no journey plays Singapore; the read model is the one photographed at Munich | — |

Also from Manila: Aurora Atlantic (premium) sees SIN–MNL inside its
list at rank 7 and loses to Osaka on either basis (CASE B).

## 5. New York (JFK)

| | Every configuration |
| --- | --- |
| Entry | none: the scripted player has no routes to enter by the second year |
| The player's fate | in 28 of 30 seeds the scripted player collapses on day 430: New York–Chicago on day 1 ($59M cash), then on day 31 a used narrowbody ($50M) and a lease and the two markets the Next Moves card names — New York–Boston at $61 and New York–Toronto at $85 — and −$811k a month until administration (fire sale, one aircraft) and collapse (`--player`, seed 2030; 28 of 30 in every configuration) |
| Why those two markets | `GameState.marketOpportunities` ranks by captured passengers over incumbents; Boston (300 km; the demand engine forecasts 1,758 passengers a day for one aircraft at two rotations) and Toronto (589 km; 1,772) lead any list from New York. `ae-fee-baseline`, PA184 at two rotations, three months: Boston revenue $1.29M a month, fees $1.15M (89%), direct operating profit $16k, −$1.17M after the $790k lease; Toronto $1.81M revenue, direct $439k, −$747k after everything; Chicago $2.78M revenue, direct $1.24M, +$47k after everything |
| The rival side | the cast around New York is healthy: SwiftJet (regional, Chicago) 3.9 routes, fleet 15, +$4.7M a month, +12% margin; nobody collapses; once the player has left New York–Chicago there is no player pair for a rival to enter, so nothing is recordable as an entry |
| Does profit ranking remove useful world pressure at New York? | there is none to remove on either basis: 0 entries in all four configurations. AE-039 already found the AE-038 New York arrival to be a passenger-ranking artefact (the turboprop lost $277k a month on the pair) |
| Does it prevent irrational entries? | the revenue basis makes none at New York either |
| Economic credibility of the cast | SOUND openings only (§2 of the credibility document); the one economically irrational actor at New York is the scripted player following the game's own guidance |
| On the rendered UI | the AE-038 New York frames (run 119–120) photographed the first month, before this collapse; NOT VALIDATED past day 61 |

**BUG-055 (P1, recorded, not fixed here):** the player's Next Moves
ranking is the passenger ranking the rival AI abandoned in AE-039 for
the same defect, and from New York it sends the player to two fee-bound
pairs that cannot pay for an aircraft. The fix — rank the player's
opportunities by `CompetitorAISystem.airframeDayValue` on the revenue
basis with the fleet's own airframe, the rule the rivals use — re-pins
the February picks of every campaign twin and journey (Munich's
MUC–IST among them), which is a phase of its own with the journeys
re-photographed; see the report's recommendation.

## 6. Summary

| Start | Shipped (revenue / 16) | Profit / 24 | Binding constraint |
| --- | --- | --- | --- |
| Stockholm | not reached (2 y, 5 y) | reached, day 187, sound | ranking (revenue never prefers it) *and* horizon (rank 22) |
| Barcelona | not reached | not reached | horizon by two places from the one rival that would choose it, on either basis; not worth a horizon of 26 |
| Munich | day 61, sound | never (2 y, 5 y) | ranking: on profit, other pairs keep more; horizon 24 makes it worse |
| Singapore | year two, sound | never | ranking: the 884 km pair keeps the least per airframe day from Jakarta |
| New York | no entry — the scripted player is gone | same | the player's guidance (BUG-055), not the rival strategy |
