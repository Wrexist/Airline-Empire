# Airline Empire — Aircraft & Fleet System (Phase 5, as built)

## Entities

- **`AircraftTypeSpec`** (content): 14 fictional types across 6 categories
  (turboprop → largeWidebody), anchored to GAME_BALANCE §3. Validated at
  catalog load (positive figures, index ranges, lease-vs-price plausibility).

  **Corrected 2026-08-30 (AE-029).** This entry previously claimed "±15%
  per-type personality (cheaper-thirstier vs pricier-frugal)". The shipped
  catalog does not have that. Measured across all 14 types, the largest
  within-category spread in fuel burn per seat-km is **4.5%** (narrowbody) and
  most categories are under 2%. There is no cheaper-thirstier/pricier-frugal
  axis: within a class, the more expensive type is generally also the one with
  more seats, more range, and equal-or-better efficiency. Types are separated
  by **size and reach**, not by economic character.

  The real economic axis is **between** categories and it is large: a turboprop
  burns roughly **72% more fuel per seat-km than a large narrowbody**, and
  regional jets are the thirstiest per seat in the catalog. Small aircraft buy
  reach and short fields; the fuel bill per passenger is the price. This is
  what `SeatEfficiencyBand` surfaces in the market.

  One type is near-dominated: **NA160** loses to **MR180** on seats, range,
  cost per seat and burn per seat. Its remaining niche is a lower *absolute*
  price, which is a real reason for a cash-constrained new airline to buy one
  — and the only one.

  Not rebalanced. `AircraftContentTests` pins both findings as characterization
  tests, so introducing the intended personality later fails a test and prompts
  this paragraph to be rewritten with it, rather than the two silently
  disagreeing again.
- **`Airline`**: id, name, kind (player/ai — same rules), home airport,
  founded time. **Cash is not a field** — balances live in the `Ledger`.
- **`Aircraft`**: type ref, owner, `AircraftOwnership`
  (owned(bookValue) / leased(rate, termRemaining)), `AircraftStatus`
  (ordered(deliveryAt) / active / inMaintenance(until)), location,
  assignedRoute (used from Phase 6), ageDays, condition 0…1,
  totalFlightHours.
- **`Ledger`**: authoritative per-airline balances + bounded categorized
  transaction trail. `post(...)` is the single money mutation path
  (ARCHITECTURE §5). Categories so far: initialCapital, aircraftPurchase,
  aircraftSale, leasePayment, leasePenalty, maintenance.

## Commands (validators reject with stable codes; state untouched on reject)

| Command | Semantics |
|---|---|
| `FoundAirlineCommand` | unique name, known home, ≥0 capital, one player airline; posts initialCapital |
| `BuyNewAircraftCommand` | full list price on order; `ordered` until `deliveryLeadDays` pass; delivered at home base |
| `BuyUsedAircraftCommand` | age 1–22y; deterministic used-market condition by age; immediate delivery; price = depreciation curve × condition factor |
| `LeaseAircraftCommand` | term 6–144 months; first month due at signing; immediate delivery |
| `SellAircraftCommand` | owned + active + unassigned only; proceeds = used price − 10% sale friction |
| `ReturnLeasedAircraftCommand` | leased + active + unassigned; 2-month penalty while term remains; free at term end (month-to-month holdover) |

## Systems

- **`FleetSystem` (daily):** ages airframes, decays condition
  (`dailyConditionDecay`), delivers due orders, completes checks (condition
  → 1.0), and triggers a maintenance check when condition <
  `maintenanceConditionThreshold` — grounding the aircraft for
  `maintenanceCheckDays` and posting the check cost (age-scaled
  hours-equivalent of the type's reserve rate). Maintenance bills even into
  negative balances: deferred maintenance is not a player option; surviving
  the bill is the gameplay (bankruptcy pressure lands in Phase 8).
- **`FleetBillingSystem` (monthly):** lease billing (term counts to 0 then
  month-to-month) and owned book-value depreciation — recomputed each month
  from the curve (idempotent, no drift): geometric `annualDepreciationRate`
  toward a `residualValueFraction` floor.
- **`GamePipeline.standard()`** is the canonical ordered pipeline; systems
  append as phases land.

## Economics (all constants in `tuning.json → fleet`)

- Depreciation 8%/yr geometric, floor 25% of list.
- Used price = depreciated value × (0.7 + 0.3 × condition);
  used-market condition = 1 − 0.02/yr (floor 0.55) — deterministic, no RNG:
  buyers know what they get; scatter would add noise, not decisions.
- Sale friction 10% — with the condition discount this makes buy-then-sell
  strictly lossy (fleet-flipping exploit test in `DisposalTests`).
- Reliability = baseline − 0.1×(1−condition) − 0.003×ageYears, floored at
  0.85 (recovery is designed; nothing becomes unflyable garbage).

## Kernel changes this phase

- `Command.validate(state:catalog:)` and `SimContext.catalog`: commands and
  systems consult content through the engine's catalog
  (`SimulationEngine(state:systems:catalog:)`, default `.empty` for
  kernel-only tests).
- `GameState` gains `airlines`, `aircraft`, `ledger` slices (+ ordered-ID
  accessors, integrity checks for dangling owners / out-of-range condition /
  negative book values). **Save format v3.**

## Test coverage (18 new; 100 total)

Founding + all validation rejections; order→delivery timing (off-by-one
checked both sides); insufficient funds leaves zero trace; used-age bounds;
lease signing + exactly-one monthly billing across a month boundary; lease
term floor/ceiling; sale friction beats flipping; sell/return rejections
(leased, ordered, foreign, assigned); early-return penalty vs free
expiry return; condition decay → check trigger → grounded → restored, paid;
book depreciation curve ±2% and floor equality; reliability degradation and
floor; mid-order/mid-lease save→load→continue hash equality; ledger balance
== transaction-trail sum.
