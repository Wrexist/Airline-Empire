# AE-044 §3 — Root cause of TD-033

Phase 6. Written before any production code changed. Every claim is
**MEASURED** and cited to docs/AE044_DEMAND_ESTIMATOR_AUDIT.md (READ, the
pipeline trace) or docs/AE044_AIRFRAME_VALUE_AUDIT.md (MEASURED, the
batteries).

---

## 1. Verdict

**CASE G — multiple factors, all of them the same mistake.**

Against the phase's own case list:

| Case | Holds? | Evidence |
| --- | :---: | --- |
| **A** — the estimator receives market demand *before* aircraft capacity allocation | **YES** | Audit §2.2: `marketOpportunities` computes one `pool` per market and reuses it for every candidate airframe. Value audit §1: the shipped forecast is the same 1,105 for a 68-seat turboprop and a 184-seat narrowbody. |
| **B** — the estimator receives capacity but does not run the real allocation model | **YES** | Audit §2.4: `representativeStarterQuality` is a constant — 2 round trips, a 0.55 cabin, unproven operations. The engine's `allocate` uses `offerQualityTerms`, in which the airframe appears twice (cabin, frequency). |
| **C** — the estimator ignores incumbent capacity | **YES, on the player path** | Value audit §3: the shipped player estimate returns *the same* $22,065/day with 0 and with 3 incumbents while the ledger goes +$37,403 → −$9,439. The rival path is not blind (D4/D5 in the audit). |
| **D** — the estimator ignores frequency | **YES, twice** | Value audit §2: the shipped forecast is 1,105 at 1×, 2×, 3× and 4×/day. And audit §4 D2: inside one call, demand is priced at 2 rotations while capacity, fuel, fees, crew and maintenance are priced at the airframe's maximum. |
| **E** — the estimator uses a different demand split | **YES, on the rival path** | Audit §4 D4: `poolAvailableToEntrant` returns `pool × (out+e)/(out+e+ΣR)` — pool *available* — where the engine awards `pool × e/(out+e+ΣR)`. A factor of `1 + 1/0.7486 = 2.34` per direction, partially cancelled by D3's missing second direction. |
| **F** — the estimator is correct but the ledger flies a different schedule | **PARTLY, and it is not the cause** | Value audit §8: 4–23% of scheduled rotations never fly, and §5: every flight-scaled line (fuel, crew, movement fees) is +4% for that reason — before *and* after the demand fix. It is a real second error, it is pre-existing, and it does not produce the aircraft-size bias. |
| **G** — multiple factors | **YES — this is the answer** | |

## 2. The single sentence

`CompetitorAISystem.airframeDayValue` takes `passengersPerDay` as a **caller-
supplied constant** while computing capacity, revenue and every cost from the
**airframe**. Every caller therefore computes the demand for one service and
the economics for another, and no caller computes the demand the engine would
actually allocate.

## 3. Why that produces exactly the observed bias

`carried = min(passengersPerDay, flights × spec.seats)`.

With `passengersPerDay` fixed across airframes:

- Below the crossover — where `flights × seats < passengersPerDay` — the seat
  cap binds, `carried` **is** the airframe's capacity, and the estimate is
  right for the wrong reason: it never consults the demand term at all. This
  is why AE-043 measured only −2% to −9% on 74–95 seat airframes.
- Above the crossover, every airframe receives **identical revenue** and pays
  **strictly more** fuel, fees, crew, maintenance and service. The estimator's
  preference is then monotonically decreasing in seats.

So the estimator is not merely noisy about large aircraft: past the crossover
it is *structurally* certain that a larger cabin is worse, whatever the market
is. That is a proof, not a correlation, and it matches the sign of every
AE-043 row.

## 4. Why AE-042 did not see it

An error in the *level* of a market's demand largely cancels when ranking
markets against each other with the airframe held fixed. It does not cancel at
all when ranking airframes against each other with the market held fixed,
because carrying capacity is precisely what an airframe is being judged on.
AE-043 §4 reached the same conclusion; this phase's §3 explains why in the
formula.

## 5. What is therefore *not* the root cause

Ruled out by measurement, so the fix does not touch them:

- **Fee, fuel, crew and maintenance rates.** Value audit §5: every
  flight-scaled line is within 4% of the ledger, before and after. AE-040
  reconciled these.
- **The fare formula.** Unchanged; the estimate and the ledger use the same
  `referenceFare`.
- **`airframeDayValue`'s arithmetic below `carried`.** AE-043 §3 already
  showed that fed the true passenger counts the same formula picks the right
  airframe; value audit §5 shows the same thing line by line.
- **`poolAvailableToEntrant` being wrong.** It is not wrong; it answers a
  different question ("how much of this market is still available to an
  entrant") correctly, and it is used correctly by the rival's viability
  floor. It was being used for a question it does not answer.
- **The demand engine.** Nothing in `DemandSystem.allocate` is at fault.

## 6. The fix this implies

One authoritative allocation, asked the estimator's question.

The engine already contains every term. What is missing is a function that
assembles them for a *hypothetical* service rather than a flown one, and a
guarantee that the demand term and the capacity term describe the **same**
service. Concretely:

1. Extract the segment-share expression `u / (outsideOption + u + Σ rivals)`
   so `allocate`, `expectedCapturedPassengers`, `poolAvailableToEntrant` and
   the new function provably share it.
2. Extract `offerQualityTerms` so it can be built from
   `(spec, roundTripsPerDay, operations, reputation)` as well as from a flown
   route — one implementation, two entry points.
3. Add the one primitive that does not exist: an entrant's captured
   passengers, **per segment**, over **both directions**, for a **named
   airframe at a named frequency**, against the **incumbents actually there**.
4. Have `airframeDayValue` derive its passengers from (3) at the same
   rotation count it prices capacity and costs at.

Steps 1–2 are refactors with no behaviour change. Step 3 is new. Step 4 is
the fix.

Validation that this is the *same* model and not a second one:
docs/AE044_AIRFRAME_VALUE_AUDIT.md §4 — over 60 day-by-day comparisons the
derived figure is within **0.1–0.4%** of the engine's own allocation, and the
residual is exactly the engine's two per-direction floor-roundings.

## 7. What the fix will not repair, and why that is correct

- **Unflown rotations** (value audit §8). A schedule-realism model, not a
  demand model; building one needs constants that do not exist. Recorded as
  **TD-035** with its measurement. This phase's brief lists "partial
  rotations" and "random operational events" as legitimate approximations.
- **The estimate pricing the airframe's maximum rotations while production
  opens routes at `initialRoundTrips` = 2** (value audit §6). Fixing the
  demand term does not decide which service should be priced, and changing
  that assumption moves every rival market ranking, so it is a separate
  decision with its own regression surface. `airframeDayValue`'s documented
  contract — what one airframe *day* is worth at the rotations the scheduler's
  day allows — is also the steady state the AI's own frequency loop converges
  to (`manageRoutes` raises frequency by one per decision while load > 0.82).
  Recorded as **TD-036**.
- **Season, weekday and economic drift after today** (audit §5 A3). Deliberate;
  worth ±13% on Reykjavík–London.
