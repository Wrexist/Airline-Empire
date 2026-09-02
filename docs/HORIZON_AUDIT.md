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

HORIZON_SWEEP_SECTION

## 4. Alternatives considered

ALTERNATIVES_SECTION

## 5. What was changed

CHANGE_SECTION

## 6. Ten-year world

TENYEAR_SECTION

## 7. Performance

PERF_SECTION

## 8. Frames

FRAMES_SECTION

## 9. Bugs

BUGS_SECTION

## 10. Remaining limits

LIMITS_SECTION
