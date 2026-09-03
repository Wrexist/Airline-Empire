# AE-041 — Economic credibility of rival openings

What "a credible rival" means in this phase, how each opening was
classified, and the two things the measurement found that were not
strategy at all.

Labels: READ, MEASURED (`ae-rival-scan`, this session), TESTED, AUTHORED,
NOT VALIDATED.

## 1. The definition (AUTHORED before measuring)

A rival's opening is credible when the rival's own ledger says the
market was worth opening — not when the entry count is high, and not
merely when the AI's estimate was positive. Five questions, each with a
measurement:

| Question | Measurement | Where |
| --- | --- | --- |
| Does the route earn? | the route's closed-month direct operating profit at +30, +90, +180 days and on the last day | `⇒ RIVAL LEDGER` for entries on the player's pairs; the opening classifier for every rival route |
| If it loses at first, is there a reason? | the same months, read in order | ledger lines |
| Does the rival retreat? | rival routes closed, with the last closed month before closure and what the route was flying | `✗ CLOSED …` lines |
| Does it acquire capacity rationally? | airframes acquired and gone again within thirty days while the airline lived | `airframes gone within 30 days of arriving` |
| Does the estimate match the ledger? | the AI's own `airframeDayValue` (profit basis) at the rotations opened, beside the first full month | `opened with … at 2x opened: profit N/day` |

Classifications, applied by the scan to every rival opening from its
own later months:

| Class | Rule |
| --- | --- |
| SOUND | earning at +90 days (or +180 if sampled later) and still flown on the last day |
| TEMPORARILY LOSS-MAKING BUT STRATEGICALLY EXPLAINABLE | earned in sampled months, one losing month at the last sample, still flown — recorded as "loss-making, still flown" and read by hand |
| ESTIMATOR ERROR | the estimate's sign disagrees with the ledger's for the life of the route |
| BAD OPENING | closed after never earning a closed month |
| CLOSED AFTER EARNING | earned, then closed after a losing month |
| CLOSED BEFORE A FULL MONTH | gone before it had a closed month with revenue |
| UNKNOWN | too young to judge (opened in the last two months) |

Not every loss is a bug, and not every loss is "strategic": the class
is decided by the months, and a class that recurs in most campaigns is
investigated by name.

## 2. The verdicts (MEASURED, 150 campaigns per configuration)

| | A · revenue / 16 (shipped) | B · revenue / 24 | C · profit / 16 | D · profit / 24 |
| --- | ---: | ---: | ---: | ---: |
| Rival openings | 2,999 | 2,912 | 2,547 | 2,707 |
| SOUND | 2,759 | 2,754 | 2,543 | 2,704 |
| Loss-making, still flown | 2 | 12 | 3 | 3 |
| Closed after earning | 92 | 0 | 0 | 0 |
| Bad opening (never earned, closed) | 0 | 0 | 0 | 0 |
| Closed before a full month | 143 | 143 | 0 | 0 |
| Too young | 3 | 3 | 1 | 0 |
| Entries on the player's pairs, all SOUND | 59 | 59 | 30 | 30 |
| Airframes disposed of within 30 days (25-campaign sample, seeds 2030–2034) | 25 | — | — | — |

No configuration produced a BAD OPENING, and no rival opened a route
and immediately collapsed. The estimator's sign disagreed with the
ledger on one pair, Paris–Zurich for the turboprop (§4): ESTIMATOR
ERROR on the pessimistic side, which the revenue basis ignores and the
profit basis obeys.

## 3. BUG-054 — the conservative rival bought, then retrenched (MEASURED, fixed)

The 143 "closed before a full month" are one scenario in 143 of 150
campaigns: Crown Meridian, the conservative archetype at Tokyo. Seed
2039, Stockholm start, `--follow "Crown Meridian"`:

| Day | What the ledger shows | What the AI did |
| --- | --- | --- |
| 58 | cash $23.0M, February statement: costs $1.6M, runway 14.8 months | opened Tokyo–Beijing with its fifth airframe |
| 59–71 | March statement: costs $4.0M, runway 5.7 → 6.1 months | — |
| 72 (decision slot) | runway 6.10 ≥ the archetype's 6.0 | **bought a sixth AV90 for $19.9M; cash $4.3M, runway 1.09 months** |
| 78 | Tokyo–Beijing: 74 flights, 95% load, +$734k in the month under way; its closed month (two days of February) −$29k on $0 revenue | — |
| 79 (decision slot) | runway 1.30 < 1.5 | **retrench: closed Tokyo–Beijing** (the minimum closed-month result — a partial month with no revenue — read as the worst loss-maker) **and sold the airframe bought on day 72**; cash back to $23.2M |

Two rules in `CompetitorAISystem` combined: the growth step measured
the runway before the outlay and not after, so a conservative airline
spent itself from six months of cash to one in a single slot; and the
retrench step ranked routes by their last closed month whether or not
that month had been flown. The fix (TESTED, `RivalCredibilityTests`):

- `acquireAircraft` takes a cash floor — the archetype's own expansion
  runway in months of the latest statement's costs — and a lease
  signing or a used purchase that would leave less than that waits for
  a richer month. The loan path (taken only when the purchase is not
  affordable outright) is as it was. Three variants were measured on
  seeds 2030–2034 × five starts: a floor at the retrench line stopped
  the route closures and left one buy-and-sell a campaign, because the
  next statement's costs rose and pulled the runway back under the line
  (25 disposals in 25); the archetype's threshold with the loan sized
  to hold it left none (0 in 25) but slowed the premium archetype's
  leveraged growth enough to move the seed-2039 London–Berlin fight the
  campaign twin and journey are pinned on (Aurora's answer 22 days
  after the invasion instead of the next morning); the archetype's
  threshold with the loan path unchanged left one in 25 and every twin
  where it was. The third shipped.
- `retrench` picks the worst loss-maker among routes with a closed
  month of revenue.

Measured on the fixed build over the full 150 campaigns: closed before
a full month 143 → 0, airframes disposed of within thirty days about
one a campaign → 12 in 150 (all on the unchanged loan path), rival
routes closed 235 → 67, openings SOUND 92.0% → 97.5%, world-initiated
entries unchanged (59: Munich day 61 in 30 of 30, Singapore days
509–551 in 29 of 30), Crown Meridian in the seed-2039 cast ending with
three routes (two before); the regional rival's fleet from Paris
9.0–9.3 → 8.9–9.0 and its margin −7/−8% → −9%: the 4-month archetype
waits a little longer for each turboprop. Table:
docs/AE041_PROFIT_VS_REVENUE_REPORT.md §7.1.

## 4. The regional rival's Paris–Zurich (MEASURED, not a bug)

SwiftJet opens Paris–Zurich on day 3 in 88 of 150 revenue-basis
campaigns: 490 km, the pair that sells the most per turboprop day from
Paris. The profit estimate says −$1.4k a day; the ledger says +$93k to
+$105k a month at +90 days and about the same at +180 — the estimator's
entrant pool under-reads a thin pair the route then fills (AE-040's
known limitation of the demand forecast). In the second year (days
364–686, median 490) the route is closed after a losing month by the
retrench rule, flying 20 rotations with three aircraft at 92% load and
−$90k to −$178k. Classified CLOSED AFTER EARNING: a marginal market the
revenue ranking chose because it sells, held for a year, dropped when
the airline needed cash. Not irrational; not the profit basis's choice
either (it opens Lyon, Munich, Nice). At horizon 24 the regional rival
opens Warsaw, Bergen and Oslo instead and the pair is never chosen.

## 5. Estimate versus ledger on the entered pairs (MEASURED)

| Pair | Aircraft | Estimate at the 2 rotations opened | First full month (+30 days, at the rotations then flown) | Ratio, per day | Reading |
| --- | --- | ---: | ---: | ---: | --- |
| Munich–Istanbul, 1,547 km | NA160 | $44.3–44.6k/day | $1.5–1.6M at 4× (≈ $50–53k/day) | 1.1–1.2× | the route grew past the estimate's rotations |
| Stockholm–Istanbul, 2,177 km | NA160 | $70.5–71.9k/day | $1.6–1.8M at 4× (≈ $53–60k/day) | 0.75–0.85× | load 95%; the estimate assumes every rotation flies (AE-040 limitation) |
| Jakarta–Singapore, 884 km | NA160 | $20.8–21.7k/day | $119–187k at 4–5× (≈ $4–6k/day) | 0.2–0.3× | a partial first month (opened days 509–551, the month closes mid-ramp); +90 days $1.2–2.0M at 11–13× |

The estimate is the same scale as the ledger on every entered pair, and
on the profit basis it is the *reason* for the entry: Stockholm–Istanbul
keeps $70k an airframe day where Munich–Istanbul keeps $44k, and the
ledger confirms the order ($2.7M against $1.9M a month a month on).

## 6. What credibility does not settle

The profit basis's openings are 99.8–99.9% sound against the shipped
basis's 92.0% before the fix — but 235 of the 240 non-sound revenue
openings were BUG-054 (143) and one thin turboprop pair (92), and the
fix removes the first entirely without changing the basis. The
remaining difference between the bases is which markets they open, not
whether the markets earn: every entry on a player's pair earned, on
every basis. Credibility therefore does not choose the strategy; the
curated-start coverage does (docs/AE041_PROFIT_VS_REVENUE_REPORT.md §4).
