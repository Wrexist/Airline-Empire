# Rivals that come to you — AE-038 audit

The question: does the world ever move first? AE-037 gave the player every
screen a contest needs and photographed every state the game had — and
every one of them was the player's doing (TD-026). This phase read the
rival decision loop, scanned hundreds of campaigns for a contest the
player did not start, drove the one it found as a deterministic scenario,
and photographed what the player sees.

Labels: READ (from source), MEASURED (headless engine), OBSERVED (a CI
frame, looked at), AUTHORED, TESTED, NOT VALIDATED.

## 1. The rival decision loop (READ)

`CompetitorAISystem`, daily cadence, one decision per airline per seven
days, staggered by airline id (`(dayIndex + id) % 7 == 0`):

```
WORLD STATE            cash runway from the last statement; idle airframes;
                       each route's load, seats flown, last month's P&L
      ↓
RIVAL ARCHETYPE        AIProfile: fare factor (0.85× … 1.25×), preferred
                       aircraft, leasing vs buying, debt comfort, expansion
                       runway, and for `regional` a home-region-only rule
      ↓
MARKET EVALUATION      from where the idle airframe sits: the 16 nearest
                       airports (`candidateMarketLimit`), eligible for the
                       airframe, with slots for two rotations, scored
      ↓
DECISION               1 survive (runway < 1.5 months: close the worst
                       loss-maker, shed idle metal) → 2 employ idle metal
                       (thicken a hot route that cannot fly its frequency,
                       else open the best-scoring market) → 3 manage
                       (answer a >12% undercut per archetype; +1 rotation on
                       load > 0.82 up to 20; −1 on load < 0.35; close at one
                       rotation and a loss) → 4 acquire when runway allows
      ↓
CONSEQUENCE            ordinary commands through their own validators; the
                       demand engine splits each pair by fare and quality
                       the next morning; `world.marketMoves` records entries
                       and exits (AE-037)
      ↓
PLAYER VISIBILITY      `marketEntered` / `marketLeft` on the player's pairs
                       in the feed; the Home headline; the route's
                       competition section; the World hub; Competitors
```

The seven questions, READ:

1. **Can rivals select markets independently?** Yes — every decision slot
   with an idle airframe scores the sixteen nearest airports to where it
   sits and opens the best one.
2. **Can they enter a market the player already flies?** Yes in principle:
   nothing excludes a contested pair. Until this phase the score halved
   per incumbent (`pool / (n + 1)`), so a contested pair had to be worth
   twice any open one in the same sixteen to win.
3. **Can they react to player success?** Not to the player's success as
   such: scoring reads the demand pool and the count of incumbents, not
   their loads or profits. They react to a full aircraft of their *own*
   (frequency +1) and to a fare more than 12% under theirs.
4. **Can they react to market demand?** Yes — the pool is seasonal and
   follows the economic index; load drives frequency both ways.
5. **Can they retreat?** Yes — a route at one rotation, under 35% load and
   losing money closes; the survival rule closes the worst loss-maker.
6. **Can they fail?** Yes — the same administration and collapse path as
   the player (`EconomySystem`); AE-037 measured two to three of five
   collapsing in five years before its fixes.
7. **Are proactive actions happening but invisible?** Rival openings at
   the player's airports are frequent (nine to twelve per two-year
   campaign, MEASURED below) and visible on Competitors and, when a rival
   adds two in a month, as the Home headline. Entries *into the player's
   pairs* are the rare thing, and when they happen they were already
   fully visible: AE-037's feed rule, Home headline and route section all
   fire (MEASURED §4). The player never saw one because it never happened
   where the player was.

## 2. The scan (MEASURED, `ae-rival-scan`)

`swift run -c release ae-rival-scan 730 2030-2059 ARN,BCN,MUC,SIN,JFK,GRU,DXB,JNB`
— 240 two-year campaigns, the probe's player script (guided first route,
the boom-region reaction, February's expansion, one aircraft and one
market a month while cash allows). Every rival move on the player's
network, classified by who started the contest:

| Home | Campaigns | World-initiated entries | Player-initiated entries | Rival exits from the player's pairs | Rival openings at the player's airports |
| --- | --- | --- | --- | --- | --- |
| ARN Stockholm | 30 | 0 | 0 | 0 | 278 |
| BCN Barcelona | 30 | 0 | 0 | 0 | 217 |
| MUC Munich | 30 | 0 | 0 | 0 | 153 |
| SIN Singapore | 30 | 0 | 0 | 0 | 208 |
| JFK New York | 30 | **30** (every seed: SwiftJet, JFK–ORD, day 17) | 0 | 4 (days 416–661) | 120 |
| GRU São Paulo | 30 | 0 | 30 (the guided first route is a pair a rival already flies) | 0 | 179 |
| DXB Dubai | 30 | 0 | 3 | 0 | 126 |
| JNB Johannesburg | 30 | 0 | 0 | 0 | 0 |
| **Total** | **240** | **30** | **33** | **4** | **1,281** |

Also across the 240: 872 rival frequency increases on the player's pairs
(all on New York–Chicago), 49 rival collapses (32 of them in the Munich
campaigns), and not one rival price cut on a player's pair — the
incumbents' answer is capacity, not fare, because the scripted player never
undercuts.

**Finding.** Before this phase the world came to the player at exactly one
of eight homes, and there on one pair: New York–Chicago, entered on
day 17 of every seed by SwiftJet, the regional rival based at Chicago.
Not because New York is the only home a rival can see — from Singapore
five rivals have the player's home in their candidate set — but because
the halving made a contested pair worth less than any open one, and
JFK–ORD is the only pair large enough to win at half value.

### 2.1 The same 240 campaigns with the entrant scoring (MEASURED)

`DemandSystem.poolAvailableToEntrant` in place of `pool / (n + 1)` (§5),
nothing else changed:

| Home | World-initiated entries before → after | Which pairs, and when |
| --- | --- | --- |
| ARN Stockholm | 0 → 0 | no rival's candidate set contains Stockholm |
| BCN Barcelona | 0 → 0 | SwiftJet at Paris can see Barcelona; the player's pairs from it are smaller than Paris's open alternatives |
| MUC Munich | 0 → 0 | three rivals can see Munich; same reason |
| SIN Singapore | 0 → 0 | five rivals can see Singapore; same reason |
| JFK New York | 30 → 30 | SwiftJet, JFK–ORD — now on its **first** decision (day 3) rather than its third (day 17) |
| GRU São Paulo | 0 → **60** | Aurora Atlantic (premium, based Rio) takes GIG–GRU on day 4; PacificBlue (low-cost, based Buenos Aires) takes EZE–GRU two days after the player opens it (day 33) — every seed |
| DXB Dubai | 0 → **5** | PacificBlue (low-cost, based Riyadh), DXB–RUH, five seeds |
| JNB Johannesburg | 0 → 0 | one rival can see it; the pairs are too small |
| **Total** | **30 → 95** | three of eight homes, on the region's largest pairs |

Player-initiated entries fall from 33 to 3: São Paulo's February expansion
onto Buenos Aires now finds PacificBlue arriving *after* the player instead
of before. What else moved, across the 240: rival frequency increases on
the player's pairs 872 → 1,549; rival price cuts on the player's pairs
0 → 30 (all PacificBlue's low-cost answer on São Paulo–Buenos Aires);
rival openings at the player's airports 1,281 → 1,251; rival collapses
49 → 60 (New York 10 → 21 — the cast there fights harder and two of it
fail more often; Munich's 32 are unchanged); rival exits from the
player's pairs 4 → 1. The ten-year five-rival world test (HHI < 0.7,
at least two operators alive) and every other Core test pass with the
change: 433 of 433.

**What the scoring did and did not do.** Where a rival could already see
a large pair the player flew, it now comes for it at once. Where no rival
can see the player's home — Stockholm, the curated first start — nothing
changes, because the candidate horizon is still the sixteen nearest
airports to the rival's base. That horizon is the residual of TD-026 and
is left alone here: widening it is a change to where every rival flies,
not to how it weighs a contest, and this phase measured rather than
redesigned.

## 3. Player-initiated versus world-initiated (MEASURED)

| Event | Initiator | Player impact | Player visibility | Validation |
| --- | --- | --- | --- | --- |
| Player opens London–Paris under two incumbents (AE-037) | player | share settles at a third, route loses money, one rival retreats day 248 | route section, Home, World hub, Competitors | OBSERVED runs 112–117 |
| Guided first route from São Paulo is a pair a rival already flies | player (by the guide) | contested from day 1 | route section | MEASURED (scan: every GRU seed) |
| SwiftJet opens New York–Chicago on the player's first route, day 17 | **world** | share 100% → 48% in a month → 42% by day 90; rival climbs 2 → 20 rotations by day 240 | feed event, Home headline "SwiftJet entered your JFK–ORD market yesterday", route section | MEASURED (`RivalsComeToYouTests`), OBSERVED run RUN_NUMBER |
| Rival openings at the player's airports (about five per campaign) | world | none on the player's pairs; presence | Competitors; Home when two in a month | MEASURED (scan), OBSERVED AE-037 KEY-46 |
| SwiftJet leaves New York–Chicago, seed 2040 day 521 | world | the pair is the player's again | Home headline, feed | MEASURED (scan); not photographed — see §6 |

## 4. The scenario (MEASURED, `RivalsComeToYouTests`, seed 2030, New York)

One leased narrowbody on the guided first route JFK–ORD, two rotations at
the reference fare, then nothing but sunrises:

| Day | What happens | Player share of the pair | Route, last full month |
| --- | --- | --- | --- |
| 17 | SwiftJet (regional, based ORD) opens ORD–JFK at $136, 2×/day — the same fare | 100% (no split yet) | — |
| 18 | Home: `rivalEnteredYourMarket` — "SwiftJet entered your JFK–ORD market yesterday."; the feed carries `marketEntered` | | |
| 47 | SwiftJet at 3×/day | 48%, even, edge schedule (they fly more often) | $1.4M |
| 60 | 4×/day | 46% | $1.3M |
| 90 | 6×/day | 42% | $1.2M |
| 240 | 20×/day, the cap | 42% | $1.3M |
| 365 | still there | 42% | $1.3M |

The player's aircraft stays full throughout: the consequence is the
growth the pair no longer offers — the demand allocated to the player's
route halves — not a loss on the route.

**The response (MEASURED, same twin, decided on day 47):**

| Response | Share at day 90 | Route profit per month, days 90–360 | Verdict |
| --- | --- | --- | --- |
| nothing | 42% | $1.1–1.4M | the baseline |
| one more rotation on the aircraft already there (2× → 3×) | 46% | $1.7–2.1M | **worth half again the route** |
| fare −10% | 47% | $0.85–1.1M | worse than nothing |
| both | 50–51% | $1.3–1.6M | share, not money |

The route screen's frequency advice used to say "another rotation needs
another aircraft on this route"; on this pair the one narrowbody had a
third rotation in it (BUG-046, fixed: the model now carries the spare
rotations the scheduler's arithmetic allows).

## 5. The extension (AUTHORED, TESTED, MEASURED)

`DemandSystem.poolAvailableToEntrant` — the demand engine's own split
applied to one hypothetical extra offer against the incumbents' actual
fares and quality, in pool units. An open pair scores exactly what it did
before; a pair with one incumbent at the reference fare scores two thirds
of its pool instead of half (`EntrantPoolTests`); incumbents with no
aircraft attract nothing, as in the allocator. `CompetitorAISystem.bestMarket`
uses it in place of `pool / (n + 1)`. Deterministic, seeded, the same rules
for everyone, no reference to the player anywhere. Balance consequences
in §2 (the after-scan) and §7 (the ten-year world test).

## 6. Frames inspected

FRAMES_SECTION

## 7. Bugs found

BUGS_SECTION

## 8. Unresolved

UNRESOLVED_SECTION
