# The horizon — AE-039 audit

AE-038 left one residual: from Stockholm, Barcelona and Munich the world
never moved first, and the suspicion was the rival candidate horizon —
the sixteen airports nearest to where a rival's airframe sits. This phase
measured that suspicion before changing it.

Labels: READ (from source), MEASURED (headless engine), OBSERVED (a CI
frame, looked at), AUTHORED, TESTED, NOT VALIDATED.

## 1. The horizon as implemented (READ)

`CompetitorAISystem.employ` opens a new market only from `aircraft.location`
of an **idle** airframe. New deliveries arrive at the airline's home, and
an assigned airframe's location alternates between its route's ends, so in
practice a rival expands from its home airport, and from a spoke only
when a closure leaves an airframe there.

The candidates are `catalog.nearestAirports(to: origin, limit:
tuning.candidateMarketLimit)` — `candidateMarketLimit` is 16 in
`tuning.json` — every other airport sorted by great-circle distance,
ascending, ties on code. Each candidate then passes, in order: the
archetype's home-region rule, `routeEligibility` for the airframe (range,
runway, minimum distance), "already flown by us", slots for two rotations
at both ends, and the viability floor (`minViableDailyDemand`, 140) on the
score, which since AE-038 is `DemandSystem.poolAvailableToEntrant`. The
highest score wins.

So a rival can come to a player's pair only when (1) one end of the pair
is where an idle rival airframe sits — its home, almost always — and (2)
the other end is among the sixteen nearest to that home, and (3) the
pair's score beats every open candidate in those sixteen.

`CompetitorAISystem.candidateMarkets` now exposes that evaluation — every
candidate with its verdict (`scored`, `regionExcluded`, `ineligible`,
`alreadyServed`, `noSlots`, `belowFloor`) and its rank in the distance
order — and `bestMarket` picks from it, so the diagnostic below and the
tests ask the AI itself.

## 2. The geographic baseline (MEASURED, `ae-rival-scan --horizon`)

For every pair the player flies, every rival whose home or idle airframe
sits at one end, evaluated over the whole world (`limit: 93`) against the
best it can see inside its sixteen. Seed 2039, the campaign script, at day
60 and day 365.

### Stockholm (ARN)

| Player pair | Rival at the far end | Rank of ARN from there | Verdict, day 60 | Verdict, day 365 |
| --- | --- | --- | --- | --- |
| ARN–LHR | Aurora Atlantic (premium, home LHR) | 27 | outside; would score 819 vs its winner AMS 2,650 | outside; 725 vs AMS 2,168 |
| ARN–LHR | SwiftJet (regional, at LHR) | 27 | ineligible: its turboprop reaches 1,450 km, the pair is 1,462 | same |
| ARN–CDG | Aurora Atlantic (at CDG) | 30 | outside; 714 vs MXP 2,013 | outside; 628 vs MXP 1,860 |
| ARN–IST | PacificBlue (low-cost, home IST) | 22 | outside; 648 vs FCO 2,290 | outside; 564 vs MXP 1,360 |
| ARN–CAI | PacificBlue (at CAI) | 32 | outside; 432 vs TLV 1,973 | outside; 376 vs RUH 1,798 |

**CASE E.** Stockholm is outside every relevant horizon (ranks 22–32 of
16) **and** every Stockholm pair scores a third to a half of what the
rival can still open uncontested from its hub. Widening the horizon
alone admits Stockholm to the list and loses the vote.

### Barcelona (BCN)

| Player pair | Rival at the far end | Rank of BCN | Verdict, day 60 | Verdict, day 365 |
| --- | --- | --- | --- | --- |
| BCN–LHR | Aurora Atlantic (home LHR) | 20 | outside; 1,661 vs AMS 2,650 | outside; 1,300 vs AMS 2,168 |
| BCN–LHR | SwiftJet (at LHR) | 20 | outside; 1,765 vs AMS 2,650 | — |
| BCN–IST | PacificBlue (home IST) | 26 | outside; 1,228 vs FCO 2,290 | outside; 935 vs MXP 1,360 |
| BCN–CAI | PacificBlue (at CAI) | 20 | outside; 974 vs TLV 1,973 | outside; 740 vs RUH 1,798 |
| BCN–MAD | SwiftJet (at BCN) | 2 | — | **CASE B**: inside, 1,020 vs its winner LHR 1,571 |

**CASE A leaning E.** Barcelona sits just outside the sixteen from London
(rank 20) and scores about two thirds of London's best open market; the
gap narrows with time as the hubs' best markets get taken.

### Munich (MUC)

| Player pair | Rival at the far end | Rank of MUC | Verdict, day 60 | Verdict, day 365 |
| --- | --- | --- | --- | --- |
| MUC–LHR | Aurora Atlantic (home LHR) | 13 | **CASE B**: inside, 1,455 vs BER 2,329 | inside, 1,490 vs MXP 1,944 |
| MUC–LHR | SwiftJet (at LHR) | 13 | **CASE B**: inside, 1,545 vs BER 2,329 | — |
| MUC–CAI | PacificBlue (at CAI) | 14 | **CASE B**: inside, 851 vs TLV 1,973 | inside, 865 vs RUH 1,798 |

**CASE B.** Munich is inside London's and Cairo's sixteen. The pairs lose
on score to Berlin, Milan, Tel Aviv, Riyadh — open markets of the same
size or larger. The horizon is not Munich's problem.

### New York (JFK), for comparison

| Player pair | Rival | Rank | Verdict, day 60 |
| --- | --- | --- | --- |
| JFK–ORD | SwiftJet (home ORD) | 3 | already flies it (entered day 3) |
| JFK–ORD | PacificBlue (home JFK) | 4 | inside, 2,064 vs MIA 3,471 |
| JFK–YYZ, JFK–BOS | PacificBlue, SwiftJet at JFK | 1–3 | inside, 2,500–2,640 vs MIA 3,471 / ATL 3,028 |

New York works because Chicago is the third-nearest airport to New York
and the pair is the largest either rival can see.

### Singapore (SIN)

| Player pair | Rival | Rank | Verdict, day 60 |
| --- | --- | --- | --- |
| SIN–CGK | PacificBlue (home CGK) | 1 | inside, 2,868 vs KUL 3,703 |
| SIN–MNL | Aurora Atlantic (home MNL) | 7 | inside, 1,471 vs HND 4,871 |

**CASE B.** Singapore is the nearest airport to Jakarta; the pair loses to
Kuala Lumpur.

## 3. The failure mode, classified (MEASURED)

| Start | Case | The evidence |
| --- | --- | --- |
| Stockholm | **E** — outside the horizon and outscored | ranks 22–32; scores at a third to a half of the rival's best open market at day 60 and still at day 365 |
| Barcelona | **A → E** — outside by a few places, outscored by a third | rank 20 from London, 26 from Istanbul |
| Munich | **B** — inside, outscored | ranks 13–14; Berlin, Milan, Tel Aviv, Riyadh score higher |
| Singapore | **B** — inside, outscored | rank 1 from Jakarta; Kuala Lumpur scores higher |
| New York | reached | rank 3; the largest pair in sight |

Range (CASE C) rules out one rival per European pair — SwiftJet's
turboprops reach 1,450 km — never all of them. Eligibility and slots
(CASE D) exclude nothing relevant.

## 3.1 The horizon sweep (MEASURED, `ae-rival-scan --limit`)

Thirty seeds, two years, the five starts that matter (the three curated
European ones, New York, Singapore), the shipped ranking, four horizon
sizes. World-initiated entries into the player's pairs:

| Start | 16 (shipped) | 24 | 48 | 93 (the whole world) |
| --- | --- | --- | --- | --- |
| Stockholm | 0 | 0 | 0 | 0 |
| Barcelona | 0 | 0 | 0 | 0 |
| Munich | 0 | 0 | 0 | 0 |
| New York | 30 | 30 | 30 | 30 |
| Singapore | 0 | 0 | 0 | 0 |

**The horizon size changes nothing.** Rival networks do change with it —
openings at the player's airports move (Stockholm 278 → 217 → 180 → 180),
collapses move (Munich 32 → 2 → 0 → 0) — but not one rival comes to a
European pair at any size, because a wider horizon adds *larger* open
markets ahead of the player's pair, never smaller ones behind it.

Over five years at the shipped horizon (five seeds): Stockholm 0, Munich
0, Barcelona 3 — SwiftJet on Barcelona–Paris in years three and four,
gone again within months. At 32 the same. Time does not bring the world
to Stockholm or Munich either.

## 3.2 What the ranking sees (MEASURED, `--horizon`, seed 2039, day 365)

From each rival home, every airport in the world scored by the AI's own
rule and sorted (° = outside the shipped sixteen, * = a pair the player
flies):

| Home | The ranking's head | Where the player's pair sits |
| --- | --- | --- |
| London (Aurora, 5,100 km airframe) | CAI° 3,515 · IST° 2,911 · MAD° 2,431 · AMS 2,168 · BCN° 2,048 · FCO° 2,015 · MXP 1,944 · FRA 1,915 · BER 1,863 · ZRH 1,703 · MAN 1,628 · LYS 1,540 · MUC* 1,490 | Munich #12 of 33; Barcelona #13; Stockholm #28 (725) |
| Istanbul (PacificBlue, 5,100 km) | DEL° 2,828 · LHR° 2,806 · CDG° 2,728 · BOM° 2,115 · DXB° 1,646 · RUH° 1,643 · MAD° 1,469 · MXP 1,360 · BCN° 1,339 · BER 1,317 | Stockholm #30 of 36 (564); Barcelona #18 (935) |
| Paris (SwiftJet, 1,450 km turboprop) | LHR 3,140 · MAD° 2,237 · FCO° 1,934 · MXP 1,860 · FRA 1,768 · ZRH 1,623 | Stockholm out of range |
| Tokyo (Crown Meridian, 2,750 km) | PEK 5,854 · TPE 3,650 · CTS 2,824 | three viable markets in the world |
| Jakarta (TerraLink, 2,750 km) | — | **no viable market at all** |

The rule ranks by passengers. A 370 km pair with 2,168 passengers
outranks a 1,462 km pair with 725 forever — though one airframe fills on
either (640 seats a day at two rotations on the longer, 1,280 at four on
the shorter) and the longer pair's fare is two and a half times the
shorter's. Every hub therefore works through its short large pairs
first, and a second-tier city a thousand kilometres away comes up
twelfth or twenty-eighth. Widening the horizon adds Cairo, Istanbul and
Madrid ahead of it.

**Root cause, classified.** Stockholm: CASE E, with the *ranking*, not
the distance list, as the binding half. Munich and Singapore: CASE B.
Barcelona: CASE A by four places, then CASE B. New York: reached because
Chicago is the largest pair either rival can see.

## 4. Alternatives considered

Three ways to let the world see a second-tier city, all measured on the
same 150 campaigns (30 seeds × Stockholm, Barcelona, Munich, New York,
Singapore, two years) unless stated:

| Strategy | Stockholm | Barcelona | Munich | Singapore | New York | Ten-year world | Balance battery |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **A. Fixed larger horizon** (24 / 48 / 93), passenger ranking | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 30 / 30 / 30 | (unchanged rule) | (unchanged rule) |
| **B. Adaptive horizon** | not built — every fixed size gave the same answer, so no size-selection rule could give a different one | | | | | | |
| **C. Rank by airframe-day profit**, 16 | 0 | 0 | 0 | 0 | 0 | passes | **fails**: three archetype runs at 64–65% operating margin against the 60% line |
| C at 24 | **30** (PacificBlue, ARN–IST, day 187 of the scripted campaign; day 201 of the UI campaign's) | 0 | 0 | 0 | 0 | passes | fails, as above |
| C at 32 | 0 | 0 | 0 | 0 | 0 | | |
| **D. Rank by airframe-day revenue**, 16 — shipped | 0 | 0 | **30** (PacificBlue, MUC–IST, day 61) | **30** (PacificBlue, CGK–SIN, days 509–551) | 0 | passes | passes |
| D at 24 | 0 | 0 | 30 | 30 | 0 | | |

Across the same 150 campaigns, the shipped basis against the passenger
ranking it replaces (AE-038's scoring, horizon 16): world-initiated
entries 30 → 59 (New York's 30 gone, Munich's 30 and Singapore's 29
arrived); rival openings at the player's airports 979 → 989; rival
collapses 60 → 30; rival frequency increases on the player's pairs
1,549 → 750 (Munich–Istanbul and Jakarta–Singapore are fought with fewer
rotations than New York–Chicago was).

**Why D and not C.** C is the AI's real question — where does this
airframe earn the most — and it reaches the curated first start. But it
answers the regional archetype's question with "nowhere": at hub movement
fees, no market in the world is profitable for a 70-seat turboprop at the
reference fare, so SwiftJet never opens a route, holds one idle airframe
for ever, and the cast loses a member. It also lets the archetypes that
do fly keep only their best markets, and three of fifteen archetype runs
cross the balance battery's 60% margin line (64–65%). Neither is a
horizon finding; both are economy findings, out of this phase's scope,
and the rule against weakening a test to go green settles the second. D
keeps every archetype flying, passes every battery unchanged, and brings
the world to Munich in every seed on day 61 and to Singapore in the
second year.

**Why not A.** The distance list was never the binding constraint. A
wider list adds larger open markets ahead of the player's pair, never
smaller ones behind it; in the five-year run at 32 even Barcelona's three
late entries vanished.

**Why no adaptive rule.** An adaptive horizon chooses a size; every size
chose the same markets. There is nothing for it to adapt.

## 5. What was changed

`CompetitorAISystem.candidateMarkets` scores each candidate that passes
the unchanged gates — archetype region, `routeEligibility` for the
airframe, not already flown, slots for two rotations, and the passenger
floor `minViableDailyDemand` on `DemandSystem.poolAvailableToEntrant` —
by `airframeDayValue(basis: .revenue)`: the passengers the demand engine
leaves an entrant, capped by the airframe's seats over the rotations the
scheduler's own day allows (`FlightSchedulingSystem.roundTripsPerAircraftPerDay`),
times the reference fare at the archetype's factor. The horizon stays the
sixteen nearest. Eligibility is untouched: nothing is considered that was
not considered before, and nothing is opened that the route validator
would refuse.

The profit basis is kept as the measured alternative — `airframeDayValue(basis: .profit)`
adds the fuel, movement and passenger fees, crew, maintenance and service
the flight system posts, and `AirframeDayProfitTests` checks it against a
real month's ledger (an estimate of $52.6k a day against $65.8k booked on
Stockholm–London at the same two rotations). The scan and probe take
`--profit` to re-measure it; nothing in the app or the simulation sets it.

What the change did to the world (§4's sweeps): the AE-037 fight's
London–Paris is no longer flown by any rival on day 31 (the 350 km pair
sells less per airframe day than anything else in London's sixteen), so
the campaign's fight is now London–Berlin under Aurora Atlantic, which
answers the next morning with a cut to its premium floor and a rotation
($146/3× → $128/4×) and climbs to twenty, and the player holds 54% a week
on at a profit; New York–Chicago is no longer entered by SwiftJet, whose
turboprops lost $277k a month on it at full load — the AE-038 arrival was
an artefact of ranking by passengers.

## 6. Ten-year world

`tenYearWorldRemainsStableAndContested` (five rivals, ten years,
integrity every year, fuel and economy inside their clamps, flights under
3,000, aircraft under 300, HHI under 0.7, at least two operators alive)
passes on the shipped basis, as do `archetypeParityAndSanity` (three
seeds × five archetypes over four years: no net worth over $300M, every
margin under 60%, survivors at least 60%, archetype spread under 6×) and
`contestedMarketsCompressMargins`. Under the profit basis the ten-year
test also passes and the archetype battery does not (§4).

## 7. Performance

Measured numbers only. Every figure is on this session's Linux
container, which runs about eight times slower than it did at the start
of AE-038 (the same binary and campaign took 3 s then and 23 s now), so
the absolute times are only comparable with each other.

**Whole campaigns, release build, one core** (`ae-rival-scan`, seed 2039
from Stockholm; the AI's evaluation is a small part of a day that also
schedules, flies, allocates demand and posts every flight):

| Build | 730 days | 1,825 days |
| --- | --- | --- |
| passenger ranking, horizon 16 (before) | 23.2 s | 60.5 s |
| revenue ranking, horizon 16 (shipped) | 23.1 s | 57.6 s |
| revenue ranking, horizon 32 | — | 59.0 s |
| revenue ranking, horizon 93 (the whole world) | — | 65.4 s |
| profit ranking, horizon 16 | 16.6 s | — |

The ranking change costs nothing measurable at the campaign level; the
whole world as a horizon costs 14% over five years; the profit basis is
faster because rivals open fewer routes and fly fewer flights.

**One candidate evaluation** (`HorizonTests.evaluatingAHorizonIsCheap`,
debug build, Aurora Atlantic from London at day 60, 200 runs): 1.66 ms
at 16 candidates, 2.03 ms at 32, 2.34 ms at 94. A rival evaluates once
a week when it has an idle airframe; five rivals over seven days is under
two milliseconds of debug-build work per simulated day at the shipped
horizon. The airframe-day value itself is a dozen multiplications on top
of the entrant pool the AE-038 scoring already computed. Nothing runs
per frame; nothing in the app calls the AI.

Early, mid and late game: the evaluation's cost scales with the routes
on the candidate pairs (the incumbent scan), not with the game's age; the
five-year campaigns above are the late-game figure.

## 8. Frames

FRAMES_SECTION

## 9. Bugs

| ID | Priority | Root cause | Player impact | Status |
| --- | --- | --- | --- | --- |
| BUG-049 | P2 | the fare advice had one sentence and ignored the spare rotation the model already carried | told the player the answer that costs money and not the one that makes it | FIXED, TESTED (`MunichHorizonTests`); frame pending CI |
| Finding: New York's arrival | — | ranking by passengers sent a turboprop operator into a pair it lost $277k a month on | the AE-038 world-initiated event was real on screen and irrational underneath; it no longer occurs | recorded in tasks/BUGS.md; twin and journey moved to Munich |
| Finding: London–Paris | — | no rival flies the fee-dominated 350 km pair once markets are ranked by what an airframe sells | the AE-037 campaign fight had no incumbent | the fight is London–Berlin; twin re-pinned, journey retargeted |
| TD-029 | debt | hub movement fees against a 70-seat cabin | the regional archetype has no profitable market anywhere | documented; economy decision |
| TD-030 | debt | the profit basis freezes TD-029's archetype and crosses the margin line | Stockholm reachable only this way | measured, withheld, re-measurable with `--profit` |

## 10. Remaining limits

- **Stockholm and Barcelona are still not reached within two years on the
  shipped basis.** Stockholm needs the profit basis at a horizon of 24;
  Barcelona was reached by nothing measured here. The geography is not
  the reason: from Istanbul, Stockholm is a viable, rankable market on
  every basis — it loses on what it sells per airframe day to Berlin,
  Milan, Madrid and Barcelona itself. That is an economy ordering, and
  the next lever is TD-029's fee structure, not the candidate list.
- **The regional archetype loses money on everything it flies** (TD-029),
  under every ranking. The shipped ranking keeps it flying as before.
- **New York no longer produces a world-initiated event.** No rival can
  see New York–Chicago as its best-selling market; the AE-038 frames
  remain true of the build they were taken on and false of this one.
- **The cast is no quieter.** Rival openings at the player's airports are
  unchanged (979 → 989 across 150 campaigns); collapses halved (60 → 30).
  Whether a player reads the pairs the rivals now pick as more credible
  than the short hub pairs they picked before is NOT VALIDATED.
- **Day 61 is early.** Munich's rival arrives two days after the Regional
  era. Whether that reads as the world responding or as bad luck is a
  question for a human play session, NOT VALIDATED here.
