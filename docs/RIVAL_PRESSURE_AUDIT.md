# Rival pressure — audit (AE-037 "Make the world push back")

> Can the player see the competition? Evidence ledger for the phase.
> Labels: MEASURED (numbers from the engine) / OBSERVED (seen in decoded
> CI frames) / READ (from code) / AUTHORED / COMPILED / TESTED /
> RUNTIME VALIDATED / NOT VALIDATED. Companions: `docs/AI.md` (the
> competitor architecture, updated), `tasks/BUGS.md` BUG-042 … BUG-044,
> `tasks/TECH_DEBT.md` TD-026 … TD-028.

## 1. What competitors actually do (READ)

`CompetitorAISystem`, one decision slot per rival per seven days,
priority-ordered: survive (close the worst loss-maker, shed idle metal when
cash runway < 1.5 months) → employ an idle aircraft (thicken a hot route,
else open the best market from where the aircraft sits, among its sixteen
nearest airports, scored `pool / (incumbents + 1)`) → tune (answer a fare
more than 12 % under its own by archetype policy; push frequency by one a
week above 82 % load up to twenty; trim below 35 %; close a loser at one
rotation) → grow (lease or buy used when the runway allows). Failure is
real: administration, then collapse, through the same solvency path as the
player. Five archetypes set fare position, service tier, fleet class,
financing and geography.

## 2. What the player could see before this phase (READ)

| Rival behaviour | In Core | Event emitted | Reaches the feed | On a screen | Player can respond |
| --- | --- | --- | --- | --- | --- |
| Opens a route | yes | `routeOpened` (no airline) | **no** — a rival's private business (BUG-004's rule) | Competitors: route count; airport browser: "rival services"; map: grey line | yes, blind |
| Enters *your* pair | yes | same | **no** | route detail lists the rival (state only) | yes, blind |
| Cuts or raises a fare | yes | **none** | — | route detail: current fare, "% under you" | yes, blind |
| Adds or drops frequency | yes | **none** | — | route detail: current "×/day" | yes, blind |
| Closes a route / leaves your pair | yes | `routeClosed` (route already deleted → unattributable, BUG-007) | **no** | rival simply disappears from the list | — |
| Administration / collapse | yes | `airlineEnteredAdministration` / `airlineCollapsed` | yes | feed line; Competitors "collapsed" badge | — |
| Reputation moves | yes | none | — | Competitors: "rep 76%" | indirectly |
| Your share of a contested market | computed daily (`demandOutboundToday` per route) | — | — | **nowhere** | — |
| Who is winning a contested pair, and why | derivable | — | — | **nowhere** | — |

Home carried nothing about rivals. The World hub's live line was "Biggest
rival: PacificBlue, 1 route" — live, and never about the player. The map's
Rivals overlay hint counted shared *airports*, at which no demand is shared.

## 3. Measure before fixing (MEASURED, `ae-rival-probe`)

A new executable, `swift run -c release ae-rival-probe [seed] [days] [home]
[PAIR:fareRatio] [--save path]`, replays the seed-2039 campaign the Core
twin proves, keeps the airline growing on a plain monthly policy, and diffs
every rival's routes, fares, frequencies, fleet, status and reputation each
day. The visibility column applies `GameState.isFeedEvent` to the events the
day actually emitted.

### 3.1 The campaign as shipped — two years from Stockholm, Barcelona, Singapore

| Fact | Stockholm | Barcelona | Singapore |
| --- | --- | --- | --- |
| Rival routes opened in two years | 5 (one each) | 5 | 5 |
| Rival routes opened after week one | **0** | **0** | **0** |
| Rival actions touching a player market | **0** | **0** | **0** |
| First contested player market | never | never | never |
| Rivals collapsed by year two | 2 of 5 | 2 of 5 | 2 of 5 |
| Largest single-route fleet | 16 aircraft on DEL–BOM (needs 10) | 16 | 17 |
| Rival actions with a feed-visible event | 6 of 172 | 6 | 4 of 213 |
| Rival actions emitting **no event at all** | 94 (every fare and frequency move) | 94 | 94 |

Five years from Stockholm: still zero contested markets; three of five
rivals collapsed; the two survivors flew one route each with 22 and 12
aircraft.

Two structural causes, both READ from the code and confirmed by the
numbers:

1. **BUG-042.** `employ` preferred a "hot" route (lifetime load > 0.82)
   with no check that it could use another aircraft. A trunk route pinned at
   full load is hot forever; once frequency hit the cap of twenty, every new
   airframe joined it and never flew. Leasing archetypes then collapsed
   under bills for parked aircraft.
2. **BUG-043.** The cast was founded at the world's five most populous large
   airports — Tokyo, Jakarta, Delhi, Shanghai, Seoul. An AI expands only from
   where its aircraft sit, among sixteen nearest airports. No rival was ever
   within reach of a European start; the Singapore start's "so do your
   rivals" blurb was contradicted by the Jakarta rival avoiding the one
   pair the player flew.

### 3.2 After the two fixes — the same campaigns

| Fact | Stockholm | Barcelona | Singapore |
| --- | --- | --- | --- |
| Rival routes opened in two years | 20 | 20 | 17 |
| Routes per surviving rival at day 730 | 2–5 | 2–5 | 1–5 |
| Rival routes opened **at a player airport** | 8 | 5 | 7 |
| Rival–rival contested pair | CDG–LHR from day 4 | same | — |
| First contested *player* market | never | never | never |
| Collapses by year two | 1 (the Paris regional) | 0 | 0 |

Rivals now build hub networks (Istanbul, London, Paris for a Stockholm
player) and rival-versus-rival price wars happen on day 11 — but no rival
ever enters a pair the player already flies. The scoring halves a market
per incumbent and, with 94 airports, an open candidate always remains
(TD-026). Widening the candidate radius from 16 to 40 airports was measured
and changed nothing on this point; it was not kept.

**Product consequence, stated plainly:** in this game's design as built,
competition on the player's own pairs is **player-initiated** — the player
flies to a rival's hub and takes it on, or does not. That is the design's
own list ("fight, flank or cede"); the world does not start the fight.

### 3.3 The fight — the competitive arc that exists (MEASURED, seed 2039, Stockholm)

The player's first guided route is Stockholm–London; a rival is based at
London and one at Paris, and both fly London–Paris from days 3–4. On 1
February the scripted player enters London–Paris at $57 (0.88× the $65
reference) under Aurora Atlantic (premium, $74/4×) and SwiftJet (regional,
$65/3×).

| Day | Rival | Action | Player impact | Visibility before this phase |
| --- | --- | --- | --- | --- |
| 3 | SwiftJet | opened CDG–LHR at your airport, $65 2× | none yet | filtered |
| 4 | Aurora Atlantic | opened LHR–CDG at your airport, $81 2× | none yet | filtered |
| 11 | Aurora Atlantic | fare cut $81→$74 (answering SwiftJet) | none yet | **no event** |
| 31 | *player* | enters LHR–CDG at $57 2× | share that morning 38 % | — |
| 32 | Aurora Atlantic | fare cut $74→$71 **and** frequency 4×→5× | share 38 %, their fare 125 % of yours | **no event** |
| 38–192 | both | frequency +1 per week each, to 20×/day | share settles at 33 % (an exact third) | **no event** ×32 |
| 59 | — | first era arrives (day 59, unchanged by the fight) | — | — |
| 60–245 | — | route full every day, loses $81k–$97k every month | the consequence | route detail: fares/frequencies as state, no share, no standing |
| 248 | SwiftJet | closes CDG–LHR | share jumps to 51 % | filtered (unattributable) |
| 511 | SwiftJet | collapses (plain campaign) / survives (fight campaign) | its markets reopen | feed |

The player's route is full and losing: at $57 a narrowbody on a 346 km pair
cannot cover airport fees — the fees driver the existing `RouteVerdict`
already names. Nothing before this phase could say the other half: that two
rivals were answering with capacity, that the split had settled at a third,
or that one of them had given up.

## 4. The invisible systems, prioritised (READ + MEASURED)

| Behaviour | Exists | Player affected | Player could see | Player could understand | Priority | Done |
| --- | --- | --- | --- | --- | --- | --- |
| Rival response to your entry (fare, frequency) | yes | yes — share and revenue | no | no | **P0** | route detail: standing, share bar, per-rival share and offer; response named |
| Your share of a contested pair | yes | yes | no | no | **P0** | `MarketCompetition.playerShareToday`, on the route and in Competitors |
| Rival enters your pair | yes (rare, TD-026) | yes | no | no | **P1** | `marketEntered` event → feed; record → Home headline |
| Rival leaves your pair | yes | yes (share up) | no | no | **P1** | `marketLeft`; Home headline "pulled out … yours again" |
| Rival builds at your airport | yes (from day 3) | no (no shared demand) | map line only | no | P2 | Competitors: "shares N airports … presence, not a fight"; moves list |
| Rival collapse frees markets | yes | indirectly | feed line | partly | P2 | record notes collapse on the exit line |
| Which rival matters most | derivable | yes | "biggest rival" by route count | no | P2 | `biggestRival` by shared markets, then airports |
| Rival fare/frequency history since your entry | no state | yes | no | no | P3 | TD-027, not built |

## 5. The player competition model (AUTHORED, TESTED)

Everything is a derivation of the snapshot — no estimate of what a rival
might do, and the demand engine's own arithmetic throughout.

- **`MarketCompetition`** (per player route): the rivals on the pair with
  fare, ratio to yours, rotations, reputation, whether it is their hub, and
  their share of today's demand; the player's share; the even split for the
  carriers that carried demand; a **standing** (alone / too early / leading
  / even / trailing, margin ±15 % around even); and the **edge** — the
  attractiveness term separating you from the strongest rival by the most,
  computed from `DemandSystem.offerQualityTerms` (schedule, comfort,
  operations, reputation — the engine's own factors, now exposed) and the
  price-utility term. Nothing under 0.05 in log-terms is offered as a reason.
- **`CompetitionSummary`** (network): contested / leading / trailing counts;
  every rival as a `RivalStanding` (shared markets, markets where you trail,
  shared airports, routes entered and left in thirty days); the rival that
  touches you most; recent moves on your pairs and at your airports; and
  one **headline** by priority — the most recent move on your pair (entered
  or left), else trailing somewhere, else the biggest rival expanding at
  your airports, else an ongoing fight, else leading everywhere, else
  nothing.
- **`world.marketMoves`**: the record that makes "changed" sayable. 64
  entries, every airline, written by the open/close commands and by
  collapse. Save v12 with `MigrationV11AddMarketMoves`.
- **Events** `marketEntered` / `marketLeft`, admitted to the player's feed
  only on the player's own pairs.

Tests: `CompetitionTests` (11 — cast rule, second-market rule, record,
bound, collapse exits, feed admission, alone, invaded, headline order,
trailing headline, persistence and migration) and
`RivalPressureCampaignTests` (the arc above, asserted end to end).

## 6. The deterministic campaign twin (MEASURED, `RivalPressureCampaignTests`)

```
RIVAL-PRESSURE seed 2039: rivalAtMyAirport day 3 · invasion day 31 · rivals 2
 · response day 32 (Aurora Atlantic $74/4x → $71/5x) · week-later share 0.36
 · standing even · edge fare(playerAhead: true) · march route profit −$90k
 · rival max trips 20 · retreat day 248 · retreat headline true
 · era day 59 · contested@60 1 · biggest@60 SwiftJet
```

The first-era twin is unchanged in what matters: era day 59, mission on
day 11, four profitable routes, $17.3M cash; January's statement moved from
$2.0M to $2.1M with the new cast's slot and demand geography.

| State | Core | UI journey step | Frame |
| --- | --- | --- | --- |
| COMP-01 first competing route | day 31, two incumbents | route sheet From: LHR, "Paris" → "2 airlines already fly it" → fare slider → open | KEY-40, KEY-41, KEY-42 |
| COMP-02 rival expands into a meaningful market | day 3–4, LHR–CDG at the player's London | Competitors card: "shares 1 airport with you" / moves list | KEY-46 |
| COMP-03 economic competition | share 36 % at day 38, route full, −$90k in March | route detail a week on: standing sentence, share bar | KEY-44 |
| COMP-04 rival changes strategy | day 32: fare cut + frequency | route detail on entry vs a week later | KEY-42 → KEY-44 |
| COMP-05 rival retreat | day 248, headline `rivalLeftYourMarket` | Home from the day-249 save | KEY-47, KEY-48 |
| COMP-06 World screen live | contested 1, biggest rival named, day 60 | World hub + Competitors after the fight | KEY-45, KEY-46 |
| COMP-07 late-game density | day 1825: 12 player routes, 14 rival routes, 5 rivals alive | Home / World / Competitors / map from the day-1825 save | KEY-50 … KEY-53 |

Saves for COMP-05 and COMP-07 are written by the probe from the real
engine and opened through the game's codec under `-AEUITestLoadSave`
(TD-028) — a rival's retreat lands on day 248 and the late game is ~1,800
sunrise taps away.

## 7. Screens (AUTHORED; frames per §8)

- **Home** — `RivalPressureCard`: the summary's headline, tappable to the
  route or the Competitors screen; renders nothing when the headline is nil,
  which is every day of a quiet early game. No news feed.
- **Route detail** — the competition section now leads with the standing
  sentence ("An even fight — 36% of today's passengers against 2 rivals,
  mostly because your fare is lower"), a share bar in livery colours, each
  rival's rotations / reputation / share / fare and "their hub" badge, and
  the named response when you trail ("Answer with frequency: another
  rotation needs another aircraft on this route").
- **World hub** — the Competitors card's badge is "losing N" / "N contested"
  / "N flying" and its live line is Home's headline or the rival that
  shares most with you.
- **Competitors** — a position strip (contested / leading / losing / flying),
  contested routes as links with their standing and share, and rivals ordered
  by pressure on you: shared markets and whether you trail, shared airports
  as "presence, not a fight", this month's openings and droppings, and up to
  three recent moves near you from the record.
- **Feed** — "Aurora Atlantic entered your LHR–CDG market" / "… pulled out
  of LHR–CDG — the market is yours again", linking to the route; only on
  your pairs.
- **Map** — the Rivals overlay's hint counts contested routes and how many
  you are losing; drawing is untouched (no per-frame work, no new labels).

## 8. Frames inspected

*To be filled from the CI run that carries this branch.* Every KEY frame
above is listed with what it showed and what it did not; nothing here is
OBSERVED until then.

## 9. Bugs found

BUG-042 (rival thickens a full route forever), BUG-043 (cast never near the
player), BUG-044 (every rival move on the player's market invisible) — all
in `tasks/BUGS.md`. TD-026 (rivals never initiate on the player's pair),
TD-027 (no route opening date, no offer history), TD-028 (save fixtures).

## 10. Remaining unknowns

- Whether a human reads "An even fight — 36% … mostly because your fare is
  lower" as an answer to *what do I do* (the response line only appears when
  trailing). NOT VALIDATED.
- Rival-initiated entry into a player pair has never been observed on any
  seed or home measured (TD-026). The Home headline `rivalEnteredYourMarket`
  is TESTED against a scripted rival, not seen in a plain campaign.
- Late-game density here is what the simulation produces after five years
  (14 rival routes, 12 player routes). Whether the Competitors screen holds
  up at eight rivals with forty aircraft each is READ from the layout, not
  observed.
- The map's Rivals overlay still colours airports; whether contested *routes*
  should read differently on the map is a design question deferred with the
  render architecture protected.
