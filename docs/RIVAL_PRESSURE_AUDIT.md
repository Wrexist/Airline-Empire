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
| COMP-01 first competing route | day 31, two incumbents | route sheet From: LHR, "Paris" → "2 airlines already fly it" → open at the market fare | KEY-40, KEY-41, KEY-42 |
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

### Run 112 (commit 2f54fe3) — 67 frames decoded, every one looked at

Run 111 failed to compile the app (a duplicated accessor; fixed). Run 112
built, measured, and ran the UI suite: 16 of 18 journeys green; the
campaign and the retreat-save journey red, both for harness reasons the
frames explain. The late-game save journey passed.

| Frame | What it showed | Verdict |
| --- | --- | --- |
| KEY-40-contested-market-row | Route sheet, From: **LHR — Heathrow (London)**, "Paris" typed, one row: `CDG Charles de Gaulle (Paris) · ≈4,292 passengers/day · 347 km · fare ≈ $65 · 2 airlines already fly it` | **OBSERVED** COMP-01: the sheet says who is already there before anything is committed |
| KEY-41-fight-fare + KEY-MISSING-commit-bar | The Routes board on 1 Feb with **LHR–CDG $64 2×/day, no aircraft** already open, ARN–HND $729 beside it, ARN–LHR and ARN–CAI at 100% load | The fare-slider drag landed on the pinned commit bar under the keyboard and opened the route at the reference fare before the journey looked. Harness defect, fixed: the fight opens at the market fare; the undercut stays the Core twin's |
| KEY-50-late-game-home | Home on **2035-01-01, International era, $38.0M**: Next moves (one idle aircraft; ARN→MXP, ARN→FRA "no competition yet"), then the **RIVALS** card: *"One of your routes is contested — an even fight so far."*, then the pulse (95% load, 92% aircraft used) | **OBSERVED** COMP-07 Home: one competitive fact, no feed |
| KEY-51-late-game-world-hub | World hub: Competitors card badged **"1 contested"** with the live line *"One of your routes is contested — an even fight so far."*; World events "1 active · Now: Severe weather over East Asia"; Progression "60% to next era" | **OBSERVED** COMP-06: the hub's competitor line is about the player |
| KEY-52-late-game-competitors | Position strip **1 contested / 0 leading / 0 losing / 5 rivals flying**; "WHERE YOU ARE FIGHTING: LHR–CDG · even · 52%"; Aurora Atlantic (2 aircraft, 2 routes, rep 80%, *"You compete on 1 market."*) first; PacificBlue (20 aircraft, 4 routes, *"You share 4 airports but no city pair — presence, not a fight."*); SwiftJet 0 aircraft, 0 routes, rep 75% | **OBSERVED** COMP-06/07. Defect found: a grounded rival read as "shares 1 airport" (its home) — now "Grounded — flying nothing at the moment." |
| KEY-53-late-game-map-rivals | Map, Rivals layer, the player's eight-spoke Stockholm network in blue over grey rival lines, hint *"1 of your routes are contested; you hold your own on each."* | **OBSERVED** COMP-07 map; the hint's grammar fixed (singular). Drawing untouched, no clutter at this density |
| KEY-FEB-ROUTE-SHEET-STUCK-1 | The second Next Moves suggestion's sheet did not reach a commit (pre-existing FE-05 territory; the journey photographs and continues) | pre-existing; not this phase's |
| KEY-30, 30b, 31, 32, 38, 39 | The first-era states, unchanged by the new cast: mission offered, completed on Home, the era card, the Addis Ababa caution | **OBSERVED** again; the campaign's spine survives the fixes |
| KEY-01 … 24, 60 … 97, B0 … B3 | Every other journey's frames, unchanged | green, inspected for regressions: none |

**Retreat save (COMP-05).** The journey reached Home (no fixture-load
capture) and failed to find the card. `RivalPressureFixtureTests` now
proves the save's headline *is* `rivalLeftYourMarket` (SwiftJet, CDG–LHR,
one day ago), so the defect was the App's: the identifier sat on the
card's container, which XCUITest does not expose. Moved to the link.

### Run 113 (commit 996af96) — 71 frames decoded, every one looked at

17 of 18 journeys green, the retreat save and the late-game save among
them. The campaign reached the week-after Home and stopped on its own
identifier query (below).

| Frame | What it showed | Verdict |
| --- | --- | --- |
| KEY-41-fight-commit | The route sheet with **CDG selected**, "Service · Round trips per day: 2", and the pinned **Open this route** bar sitting directly above the keyboard — the geometry that swallowed run 112's slider drag | **OBSERVED**; the journey now commits here |
| KEY-42-contested-route-on-entry | **LHR–CDG on 1 Feb**, "Too new to judge"; Operations: 1 aircraft assigned; **WHO ELSE FLIES THIS**: *"You are losing this market — 0% of today's passengers against 2 rivals, mostly because they fly more often."*, the share bar in rival colours, `SwiftJet · their hub · 3×/day · reputation 69% · 52% of today · $65 · same as you`, `Aurora Atlantic · their hub · $74 · 16% over you` | **OBSERVED** COMP-01/03 — and a defect: the morning of entry is not "losing at 0%", it is too early. Fixed in Core (`tooEarly` until the route has an allocation or a flight); pinned in `CompetitionTests` |
| KEY-43-home-rival-pressure | **Home, 2030-02-09**: Next moves (2 idle aircraft; ARN→CDG, ARN→IST), then **RIVALS**: *"SwiftJet added 2 routes this month, at airports you serve."*, pulse 100% load, $1.3M month to date, routes 4 | **OBSERVED** COMP-02 — and a priority defect: a week into the London–Paris fight, the player's own contested pair should lead, not a rival's building elsewhere. Reordered: entered/left → trailing → fighting → expanding → leading |
| KEY-47-rival-retreat-on-home | **Home, 2030-09-07, Regional era, $41.4M**: **RIVALS** (green): *"SwiftJet pulled out of CDG–LHR yesterday — the market is yours again."* | **OBSERVED** COMP-05 |
| KEY-48-market-after-retreat | **LHR–CDG on 7 Sep**: "Losing money — airport fees take 96% of the revenue", last full month −$94k, load 100%, punctuality 97%; Today's market 4,677 wanting to fly; **WHO ELSE FLIES THIS**: *"An even fight — 51% of today's passengers against 1 rival, mostly because they fly more often."*, `Aurora Atlantic · their hub · 20×/day · reputation 81% · 49% of today · $71 · 25% over you`, and the named response *"Answer with frequency: another rotation needs another aircraft on this route"* | **OBSERVED** COMP-03/04/05 in one frame: the consequence (fees at 96%), the rival's answer (20 rotations against 2), the standing, the why, the lever |
| KEY-50 … 53 late-game | As run 112, with the map hint now singular | **OBSERVED** COMP-06/07 |
| KEY-BARE-ROW-TAP-0-1, GONE-0-2 | `assignAllBareRoutes` retry diagnostics; the fight route was assigned (KEY-42: 1 aircraft) | harness, pre-existing |

**The campaign's remaining red.** After KEY-43 the journey asserted the
card by identifier and stopped, with the card on screen in the frame. The
retreat journey's identical query passed, so the difference is the card's
variant (a destination-closure link versus a value link). The assertion
now accepts the card's **RIVALS** section header, a plain static text.

### Run 114 (commit 1ccfeea) — 69 frames decoded, every one looked at

Cancelled by the macOS job's 45-minute cap with the UI pass still
running: 16 of 18 journeys had passed, and the two reported as failed
carry the cancellation's own timestamp — the campaign at 1,099 s (run 113
stopped on its assertion at 839 s) and the flight journey at 447 s (171 s
and green in run 113). Every journey on that runner took 1.3–2× its run-113
time, so both were killed mid-flight, not failed on an assertion.
Core on CI: 429 tests passed.

| Frame | What it showed | Verdict |
| --- | --- | --- |
| KEY-42-contested-route-on-entry | LHR–CDG on 1 Feb, the two incumbents at their pre-response offers | **OBSERVED**; the frame that run 113 read "losing at 0%" from now carries the entry-day rule — the sentence is the too-early one |
| KEY-43-home-rival-pressure | **Home, 2030-02-09, $6.2M**: Next moves (2 idle aircraft; ARN→CDG, ARN→IST "no competition yet"), then **RIVALS**: *"One of your routes is contested — an even fight so far."*, pulse 100% load, $1.3M month to date, fleet 5, routes 4 | **OBSERVED** COMP-03/04: the reordered headline — the player's own fight now leads Home a week after entry, where run 113 led with SwiftJet's building |
| KEY-47, KEY-48 | The retreat save, as run 113 | **OBSERVED** again, green |
| KEY-50 … 53 | The late-game save, as run 113 | **OBSERVED** again, green |
| KEY-80-route-with-aircraft | ARN–LHR on 1 Jan, "Nobody. This market is yours alone — for now." under WHO ELSE FLIES THIS, the leased PA-184 assigned | **OBSERVED**; the uncontested wording of the same section |
| KEY-01 … 24, 60 … 97, B0 … B3 | Every other journey's frames | green, inspected for regressions: none |

What changed for run 115: the macOS job's cap is 60 minutes with the
measured step times in the workflow; a step prints each result bundle's
assertion texts into the log (the xcodebuild log names the test and its
duration and nothing else, which is why runs 113 and 114 could not say
*which* query failed); the campaign after KEY-43 tries the header, the
identifier and the headline's text, keeps a frame and the labels Home
exposes when none matches, and carries on to KEY-44 … 46 with the failure
recorded rather than stopping; the flight journey keeps one frame of the
map before it starts the clock. Frames KEY-44 … 46 (the route a week on,
the World hub and the Competitors screen during the fight) are still
pending; the same screens are OBSERVED from the retreat and late-game
saves.

### Run 115 (commit 2a71c04) — 85 frames decoded, every one looked at

Finished inside the 60-minute cap (53 minutes end to end). 17 of 18
journeys green, the flight journey among them (264 s; run 114's red was
the cap, as read). The campaign carried on past its one failed
assertion, which the new step names in the log: *"The route screen for a
contested pair does not say where the player stands"* — and its frame
says why: the journey opened the wrong route. Core on CI: 429 passed.

| Frame | What it showed | Verdict |
| --- | --- | --- |
| KEY-42-contested-route-on-entry | **LHR–CDG on 1 Feb**, "Too new to judge"; **WHO ELSE FLIES THIS**: *"Contested — the market has not split a day between you yet."*, `SwiftJet · their hub · 3×/day · reputation 69% · 52% of today · $65 · same as you`, `Aurora Atlantic · their hub · 4×/day · reputation 77% · 48% of today · $74 · 16% over you` | **OBSERVED** COMP-01: the entry-day rule on screen — no "losing at 0%", the incumbents' offers before they answer |
| KEY-43-home-rival-pressure | **Home, 2030-02-09**: **RIVALS** *"One of your routes is contested — an even fight so far."* between Next moves and the pulse | **OBSERVED** COMP-03: the player's own fight leads Home |
| KEY-44-NO-STANDING-QUERY / KEY-44 | **ARN–LHR on 9 Feb** — Stockholm–London, $532k this month, "Earning — aircraft are flying 100% full", 1,343 wanting to fly, *"Nobody. This market is yours alone — for now."* | Harness defect: the row query took any row containing LHR and the board sorts Stockholm–London first a week on. Fixed (both codes). The uncontested wording of the section, OBSERVED as a by-product |
| KEY-45-world-hub-with-competition | **World hub, 9 Feb**: Competitors badged **"1 contested"** with *"One of your routes is contested — an even fight so far."*; World events "1 active · Now: Tourism boom in Africa"; Progression "83% to next era" | **OBSERVED** COMP-06 during the fight, not from a save |
| KEY-46-competitors-screen | Position strip **1 contested / 0 leading / 0 losing / 5 rivals flying**; **WHERE YOU ARE FIGHTING: LHR–CDG · even · 31%**; **SwiftJet** (Regional, 4 aircraft, 3 routes, rep 71%) *"You compete on 1 market."*, "This month: opened 2 routes." — CDG–BCN 8 days ago, CDG–MUC 22 days ago, "an airport you serve"; **Aurora Atlantic** (Premium, 2 aircraft, 2 routes, rep 78%) *"You compete on 1 market."*, LHR–MUC 21 days ago | **OBSERVED** COMP-02 and COMP-06 in one frame: who, where, what they did and when, and the market the player shares with each |
| KEY-47, 48, 50 … 53 | The retreat and late-game saves, as runs 113–114 | **OBSERVED** again, green |
| KEY-80b-map-before-the-clock, 81, 82 | The flight journey's map before and during the clock; an aircraft in the air | green; run 114's red confirmed as the cap |
| KEY-01 … 24, 60 … 97, B0 … B3 | Every other journey's frames | green, inspected for regressions: none |

Still pending a run: **KEY-44 on the right route** — London–Paris a week
after entry, in the campaign. The same screen eight months on is
OBSERVED from the retreat save (KEY-48: the standing, the share, the
rival's twenty rotations, the response line).

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
