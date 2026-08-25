# Airline Empire — Game Balance

> Phase 2 document. The *reference economy* — the anchor numbers and ratios
> every economic system tunes against — plus the balancing methodology.
> All values ship in `Tuning` content, never as code literals. Phase 18
> owns systematic stress-testing; phases 7–8 must reproduce the reference
> scenarios below as automated economy tests.

## 1. Balance philosophy

1. **Anchored realism, tuned for drama.** Real-world *ratios* (fuel ≈ 25–35%
   of operating cost, load-factor breakeven ≈ 65–80%) keep intuition
   transferable; absolute values are game-tuned for pace.
2. **Margins are thin by design.** Airlines earn ~3–8% operating margin when
   run well. Wealth comes from scale and smart cycles, not from any route
   printing money. A route above ~20% sustained margin is a red flag to
   investigate (competition should erode it).
3. **Every strategy pays somewhere, none pays everywhere.** LCC, premium,
   regional-niche, hub-connector must each be viable in the right
   geography — and wrong in the wrong one. Phase 18's matrix tests this
   explicitly.
4. **Evidence over intuition.** Tuning changes cite a measured sim result
   (this doc §6) and land as content diffs with changelog entries.

## 2. Reference world anchors

- Currency: game-dollars (¤), Int64 cents internally. Era-III reference year.
- Fuel: base ¤0.65/kg, volatile band ×0.6–×2.2 across cycles/shocks.
- Interest: base rate 4–6% by cycle phase; credit spread 0–12% by rating.
- Inflation: none in v1 (era-static prices; cycles move demand and rates,
  not the price level — simpler mental model, revisit post-launch).

## 3. Reference aircraft classes (content anchors)

| Class | Seats | Range km | Speed km/h | Price ¤M | Lease ¤k/mo | Burn kg/km |
|-------|------:|---------:|-----------:|---------:|------------:|-----------:|
| Turboprop regional | 70 | 1,500 | 510 | 22 | 180 | 2.1 |
| Regional jet | 90 | 2,800 | 830 | 42 | 320 | 2.9 |
| Narrowbody | 180 | 5,500 | 840 | 105 | 750 | 3.4 |
| Large narrowbody | 220 | 6,300 | 845 | 128 | 900 | 3.9 |
| Widebody | 300 | 11,500 | 900 | 290 | 2,050 | 6.8 |
| Large widebody | 410 | 14,000 | 910 | 415 | 2,900 | 8.9 |

(Individual types in content vary ±15% around class anchors with
personality: cheaper-thirstier, pricier-frugal, etc.)

## 4. Reference route P&L (the canonical test scenario)

**"Metroburg–Costport"**: 1,100 km, narrowbody (180 seats), 2×/day, mixed
business/leisure market, fare ¤129 economy average, 78% load.

Per flight: revenue ≈ ¤18.1k. Costs ≈ fuel ¤4.9k (27%) + crew ¤2.3k +
airport/handling ¤3.2k + maintenance reserve ¤2.4k + ownership ¤3.1k +
overhead share ¤1.3k ≈ ¤17.2k → **~5% operating margin.**
Breakeven load ≈ 74%. Phase 8 ships this as an automated test with ±10%
tolerance; drift outside tolerance fails the build (tuning changes update
the fixture *with* a changelog entry).

## 5. Curve shapes (design intent; equations finalized in Phases 7–9)

- **Price→demand share:** logit-style share among competing offers on an
  attractiveness score; segment elasticity: leisure steep (≈ −1.4 around
  reference fare), business shallow (≈ −0.7). Whole-market size mildly
  price-stimulated (cap ≈ +25% at deep discounts) — no infinite induction.
- **Reputation→demand:** multiplier ≈ ×0.8 (poor) to ×1.25 (excellent),
  moving slowly (weeks): strong enough to matter, never a death spiral —
  floor guarantees a recovery path (recovery is designed, GAME_DESIGN §5).
- **Frequency/schedule quality:** diminishing returns; beyond ~4/day on
  short-haul, share gains flatten hard (prevents frequency-spam dominance).
- **Aging:** maintenance cost ≈ ×1 at delivery → ×1.9 at 20 years (concave
  early, convex late); reliability declines ~0.3pp/year unchecked.
- **Event severity:** rate-limited majors: at most 1 global + 1 regional
  major active concurrently in the baseline tuning; weather is seasonal-
  regional noise with forecast lead ≥ 1 game-day for groundable severity.

## 6. Balancing methodology (binding for every tuning change)

1. **Headless strategy battery** (built Phase 18, seeded from Phase 8's sim
   tools): scripted archetype players (aggressive LCC, premium builder,
   hub-spammer, do-nothing, loan-max, min-price, max-price…) run multi-year
   worlds across seeds.
2. **Metrics dashboard per run:** survival rate, net-worth curves, margin
   distributions, market-share Herfindahl, bankruptcy causes, route-margin
   outliers, AI health.
3. **Red flags:** dominant strategy (one archetype > others across most
   seeds/geographies), degenerate exploit (unbounded profit loops),
   impossible starts (archetype-independent failure), dead mechanic
   (usage never correlates with outcomes), AI runaway or collapse-cascade.
4. Change one anchor at a time → re-run battery → record in changelog
   (`docs/BALANCING.md`, created Phase 18) with before/after metrics.

## 7. Known-risk registry (watched from first implementation)

- Loan-max snowball (borrow → expand → borrow): countered by credit spreads
  + delivery lead times; test explicitly.
- Reputation death spiral: countered by floor + decay-toward-performance.
- Hub spill double-counting inflating demand: connection demand must be
  conserved (a passenger counted once), asserted in tests.
- Fleet flipping (buy/sell arbitrage): spread between buy and sell prices +
  transaction friction; test with a flipper archetype.
- Slot squatting by player or AI: use-it-or-lose-it slot rule from first
  slot implementation.
