# Airline Empire — Economy (Phase 7: demand & pricing; Phase 8 extends)

## Demand model (as built, `DemandSystem`, daily)

For every **served market** (unordered airport pair with ≥1 route) and each
direction, the day's demand pool splits into business and leisure:

```
mass        = sqrt(popOrigin × popDestination)                [thousands]
attenuation = 1 / (1 + (distance/3000 km)^1.2)
base        = 0.55 × mass × attenuation

business = base × 0.35 × bizOrigin × bizDest × weekdayBiz[dow] × economy^1.5
leisure  = base × 0.65 × leisOrigin × tourDest × season(dest, month)
                × weekdayLeis[dow] × economy^0.8
```

- Weekday shape: business peaks Mon–Thu (1.2) and craters Saturday (0.5);
  leisure peaks Fri–Sun. Both average ≈ 1 over a week.
- Seasonality uses the **destination's** profile (yearly-mean-neutral by
  content contract).
- `economy` is `WorldState.economicIndex` (1.0 until the cycle driver lands
  in Phase 8/11); business swings harder than leisure by design.

## Offer competition (share allocation)

Each route serving the market is an offer. Per segment:

```
refFare  = 35 + 0.085 × distanceKm            (¤; ≈129 at 1,100 km — anchor)
A_seg    = exp(sensitivity_seg × (1 − price/refFare)) × quality
quality  = schedule × comfort × operations    (× reputation, Phase 9)
schedule = (min(trips, 6) / 4)^0.35           (hard diminishing returns)
comfort  = 0.85 + 0.30 × type.comfortBaseline
operations = 0.70 + 0.30 × (completionRate + punctuality)/2
served_i = pool_seg × A_i / (1 + Σ A_j)       ("1" = don't-travel option)
```

Sensitivities: business 1.2, leisure 2.2 (exponential/logit form —
**deliberately not a power law**: with constant-elasticity curves and
business elasticity < 1, monopoly revenue grows unboundedly with price; the
exponential form gives a finite optimum slightly above reference fare —
mild monopoly premium, sharp collapse beyond, competition erodes it. This
was caught during Phase 7 design and is pinned by
`revenueHasAnInteriorOptimum`).

The outside option makes total served demand price- and quality-elastic
(stimulation at low fares, shrinkage at high) while conserving passengers:
`demandIsConserved` asserts carried ≤ granted, always.

## Booking & revenue flow

Demand lands on each route as directional daily grants
(`demandOutbound/InboundToday` → `remaining…`). At **boarding**, a revenue
flight sells `min(seats, remaining)`; at **departure**, `pax × fare` posts
as `ticketRevenue`; a cancellation forfeits the flight's sold demand (no
rebooking — cancellations cost real revenue). Arrival adds the airport
fees — each end's movement fee scaled by the aircraft's seats over the
180-seat reference cabin, plus the arrival end's per-passenger fee
(AE-040, docs/AIRPORTS.md fee note) — and updates
`passengersCarried`/`seatsFlown` → route load factor.

## Calibration (verified by automated economy tests)

Anchor market (GAME_BALANCE §4): two 4M-metro cities 1,100 km apart, one
2-year MR180 at 2 round trips/day, fare ¤129 → 350–620 pax/day, load
55–92%, and **positive operating profit** (revenue − fuel − fees − crew −
maintenance). Curve tests: load monotonically falls with fare; revenue
optimum is interior; frequency gains are sublinear; equal offers split a
market ~50/50; a 95-vs-150 undercutter carries >1.3× the premium carrier;
July leisure demand to a summer-sun destination >2× January; economy index
moves business more than leisure.

## Determinism notes

Demand math uses `exp`/`pow` (libm); all persisted results quantize to
whole passengers (rounded down), making cross-platform last-ulp differences
gameplay-irrelevant. Full-pipeline dual-run hash equality is tested with
demand active.

## Phase 8 will add

Loans/interest/credit, monthly statements & rollups (bounded), overhead &
staff payroll, fuel-price dynamics, economic cycle driver, bankruptcy /
administration, and route-level P&L read models (the "why did this route
make money" breakdown).

---

## Phase 8 as built: finance & world economics

### World dynamics (`WorldSystem`, daily)
- **Fuel** (`fuelPricePerTon`, ¤650 base): mean-reverting geometric walk
  (θ=0.02, σ=0.012/day), clamped ×0.6–×2.2. Stored per tonne — per-kg cents
  quantized the walk to nothing (found by test, refactored).
- **Economy** (`economicIndex`): regime-switching drift — the cycle target
  flips boom(1.15)/downturn(0.85) with ~0.11%/day probability (mean regime
  ≈ 2.5 game-years), index drifts toward it with small noise. Readable,
  multi-year, seeded.

### Credit (`CreditMath`, `TakeLoan`/`RepayLoan`)
- Offered rate = 5% base + (2% + 10% × debtRatio²) spread; debt ratio =
  debt / (positive cash + owned fleet book value); refusal beyond 85%.
- Fixed annuity payments; monthly interest (P&L) and principal (capital)
  posted separately; rounding residues settle with the final payment.
  Early full payoff supported. Max 5 concurrent loans, terms 6–120 months.

### Airline economics (`EconomySystem`, monthly)
- Payroll: ¤40k/aircraft + ¤15k/route; overhead: ¤150k base. Posted as
  `salaries` / `overhead`.

### Statements (`StatementRollupSystem`, month boundary)
- The ledger accumulates signed cents per category at post time (never
  depends on the bounded transaction ring); the rollup drains it into a
  `MonthlyStatement`, keeps 24 months + lifetime totals per airline, and
  emits `statementClosed`. **Ordering rule:** the rollup runs before the
  month's new billings in the pipeline, so month-start charges (leases,
  payroll, loan service) belong to the month they open.
- Every category carries a compile-checked P&L classification
  (operatingRevenue / operatingExpense / financing / capital) — money can
  never silently mis-bucket.
- **Route P&L:** each route accumulates direct figures (revenue, fuel,
  fees, crew, passengers) for the current month; the rollup closes them
  into `economicsLastMonth` → `directOperatingProfit`, the number the route
  card explains. Fleet ownership and company overhead stay airline-level by
  design.

### Solvency (`SolvencySystem`, daily)
- Balance below −¤2M for 7 consecutive days → **administration**: unassigned
  owned aircraft fire-sell (70% of sale value) until solvent; creditors
  write off 30% of each loan (payments re-annuitized). One survival per
  airline.
- A second failure — or a hole the fire sale cannot fill — **collapses** the
  airline: routes close (slots freed, flights cancelled), fleet liquidates,
  loans die, status = `.collapsed`, event emitted. Applies to player and AI
  alike; Phase 10 layers AI-specific cleanup, Phase 12 the player game-over
  flow.

### Test coverage (14 new; 144 total)
Fuel band + variability over 2 years; economy visits boom and bust over 8
years; annuity math (incl. zero-rate); loan lifecycle to full amortization
with interest in a sane band; leverage raises rates then refuses; early
payoff; February statement fully populated and every cent classified;
24-month statement bound; route P&L breakdown ties out to fare×pax and is
positive on the anchor; doomed-airline administration and second-failure
collapse with full cleanup + world integrity after; healthy airline never
administers; finance-heavy save/restore determinism.
