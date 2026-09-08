# Rival ownership and expansion correction

Measured 8 September 2026. Baseline: `a9037e4`. Candidate: the ownership, expansion and retrenchment changes in PR #22. Results are a controlled headless simulation, not physical-device playtesting.

## Findings

The expansionist continued leasing after it had aircraft it could not employ. In seed 11 it ended with 40 aircraft, 19 idle, paying $13.025M in monthly leases. The regional carrier similarly accumulated 22 idle aircraft in the nine-seed median.

Low-cost rivals sold cheap fares while financing every new aircraft through leases. In seed 11, day 180, route contribution was $6.55M but monthly leases alone were $7.64M. It kept expanding while losing money, then collapsed. All nine baseline low-cost runs collapsed.

## Changes and rejected intermediate

1. Keep managing the network, but do not acquire another aircraft while existing aircraft remain unassigned. Stop adding obligations when the latest closed month has negative net profit. Existing startup runway and debt limits remain.
2. Low-cost carriers buy inexpensive 12-year-old used aircraft; expansionists retain their leasing preference. Fares, service tiers, starting cash, aircraft prices, maintenance and debt limits are unchanged.

The first change alone kept all five types alive in three seeds, but low-cost median net worth was only $31.29M from $120M starting capital. That was insufficient. Combining both changes was then measured across nine seeds against the same baseline seeds.

The first integrated candidate (`4d918ab`) passed the stronger archetype guard but failed the unchanged seed-2039 credibility regression: PacificBlue bought an aircraft on day 54 and sold it on day 61. Its closed-month costs had tripled while its net cash generation remained positive. Low gross-cost reserves alone triggered liquidation.

Increasing expansion loan reserves did not remove that quick sale and reduced low-cost survival to 7/9; that variant was rejected. The final correction only retrenches on low reserves when recurring cash is negative or cash is already overdrawn. Recurring cash includes principal repayments and excludes loan proceeds and aircraft sales. The original borrowing formula remains. The seed-2039 quick-sale probe now reports none. Added focused cases preserve liquidation for principal-driven losses, negative cash, and losses disguised by new borrowing.

## Four-calendar-year results

Each archetype starts with $120M and an MR180, acquired according to its ownership preference. Homes match the existing balance battery: LHR, JFK, SIN, DXB and GRU. Seeds: 11, 22, 33, 44, 55, 66, 77, 88, 99. Each world advances 1,461 days from 2030-01-01 using the standard pipeline, with no player intervention or rescue subsidies.

| Archetype | Baseline median worth | Candidate median worth | Baseline survived | Candidate survived |
|---|---:|---:|---:|---:|
| Low cost | $0 | $202.97M | 0/9 | 9/9 |
| Premium | $465.43M | $489.80M | 9/9 | 9/9 |
| Regional | $216.65M | $259.56M | 9/9 | 9/9 |
| Conservative | $326.68M | $356.58M | 9/9 | 9/9 |
| Expansionist | $74.32M | $309.61M | 9/9 | 9/9 |

The smallest candidate low-cost outcome was $186.83M. Median idle aircraft fell from 22 to one for regional and 19 to one for expansionist. One unplaced aircraft can remain while the airline searches for work; it no longer buys dozens behind it. The highest/lowest archetype median ratio is about 2.41.

Terminal rows, including cash, fleet, idle aircraft, routes and the latest statement, are in [the CSV](validation/rival-balance-2026-09-08.csv). The probe prints monthly ledgers so a terminal figure can be traced back to costs:

```bash
cd AirlineEmpireCore
swift run -c release ae-rival-economy 11
```

The final candidate is labelled `candidate4` in the CSV. The existing CI balance test now requires all five medians to be positive and at least their starting capital. Existing survival, margin, wealth and spread bounds remain; no threshold was relaxed. The CI battery uses its existing 1,460-day duration, one day shorter than the calendar-year probe.

## Limits

These are five fixed benchmark homes and nine seeds, not proof of parity in every curated campaign or over unlimited time. Full Core and player-journey regressions must pass after integration. Existing save files retain their loans and leases; changing future AI decisions does not erase obligations, revive collapsed airlines or grant extra cash.
