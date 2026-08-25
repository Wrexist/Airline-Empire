# Airline Empire — Aircraft & Fleet System (Phase 5, as built)

## Entities

- **`AircraftTypeSpec`** (content): 14 fictional types across 6 categories
  (turboprop → largeWidebody), anchored to GAME_BALANCE §3 with ±15%
  per-type personality (cheaper-thirstier vs pricier-frugal). Validated at
  catalog load (positive figures, index ranges, lease-vs-price plausibility).
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
