# The fee economy — fix decision (AE-040, Phase 5–6)

> Written before any production economy code was touched. Evidence:
> docs/FEE_ECONOMY_BASELINE.md (route battery, anchor comparison,
> parity), docs/FEE_ECONOMY_ESTIMATOR_AUDIT.md (estimator versus ledger),
> docs/REGIONAL_ARCHETYPE_AUDIT.md (candidate battery, campaigns).

## 1. Root cause

**CASE F — two causes, fixed separately.** Neither is a level to tune;
both are a formula applied to the wrong thing.

### Cause 1 — CASE B, wrong scale: the movement fee does not scale with the aircraft (MEASURED)

The two movement fees a flight pays are the same money whether a
68-seat turboprop or a 180-seat narrowbody lands. The evidence:

- On the same pair the turboprop's fee share of revenue is 1.7–1.9× the
  narrowbody's (LHR–CDG 157% vs 85%, JFK–ORD 75% vs 40%, ORD–YYZ 98% vs
  52%); per seat flown its movement fee is 2.65× (baseline §6.3).
- Across every scored candidate in the world (`ae-fee-baseline
  --candidates all --detail`, 542 turboprop, 747 regional-jet and 842
  narrowbody candidates), the median fee share is 0.82 for the NA70,
  0.64 for the AV90 and 0.38 for the MR180. Scale the movement fee by
  seats/180 and the medians become 0.43, 0.40 and 0.38 — size-neutral
  (archetype audit §3).
- In the ledger, no turboprop route in the forty-route battery pays for
  its lease; the narrowbody clears everything from ~900 km up on the
  same pairs (baseline §6.1).
- Player parity is exact (baseline §7): a player's turboprop pays the
  same.

The design says "anchored realism" (docs/GAME_BALANCE.md §1); real
airport landing charges are per tonne of aircraft weight, and passenger
charges per passenger. The game's passenger fee already scales with
what is carried; its movement fee is the one charge that scales with
nothing.

### Cause 2 — CASE D, estimator mismatch: the AI charges maintenance ten times what the ledger does (MEASURED)

`airframeDayValue(basis: .profit)` charges the type's
`maintenancePerFlightHour` for every hour; the ledger charges a 60-hour
check when condition falls below 0.75, which at real utilisation is one
check per 500–650 flight hours — an effective rate of ~10% of the type's
(estimator audit §3; 9.8× over forty routes). Every other estimator line
matches the ledger within the 5–10% of scheduled rotations that do not
fly. This is why the AE-039 profit basis saw the regional archetype's
world as empty: the fee structure (real) plus $180k a month of
maintenance per airframe that the ledger never books (not real).

### Ranked, with what each explains

| Rank | Cause | Label | What it explains |
| --- | --- | --- | --- |
| 1 | Movement fee independent of aircraft size | MEASURED | the regional archetype's losses in the ledger, the 1.7–1.9× fee share gap between types, TD-029 |
| 2 | Estimator maintenance at the hourly rate | MEASURED | the profit ranking's "zero viable candidates", most of TD-030's darkness |
| 3 | Fee level above the design anchor (1.6× on the reference route) and the reference P&L never reconciled line by line (fuel ½, crew ½, maintenance ⅒, ownership 2×) | MEASURED | why short haul is fee-bound for every aircraft; not the regional archetype's problem specifically |
| 4 | Short-haul fare: a $26–28 hub passenger fee against a $60–69 fare under 400 km | MEASURED | why nothing under 400 km clears its lease |
| — | Double counting, wrong timing, player/rival asymmetry | ruled out (READ, MEASURED) | — |

Causes 3 and 4 are calibration, not formula; they touch every airline
and the demand model, and they are recorded as debt (TD-031), not fixed
here.

## 2. Rejected alternatives

| Alternative | Verdict | Why |
| --- | --- | --- |
| **Global fee reduction** (all movement and passenger fees down) | rejected | Changes every airline's economics and the calibrated narrowbody anchor at once; does not touch the size gap (the turboprop would still pay 2.65× per seat); the anchor route already sits at a thin margin only because fees and ownership over-weight while fuel, crew and maintenance under-weight — cut fees alone and the anchor becomes a money printer. Cause 3 is real but it is a reconciliation job for the whole reference P&L, not a fee multiplier. |
| **Regional-only discount** (lower fees for the regional archetype) | rejected | Breaks player parity: a player flying the same turboprop on the same pair would pay more than SwiftJet. The brief forbids it and so does docs/AI.md's ground rule. |
| **AI-only compensation** (make the estimator ignore fees, or subsidise the archetype's candidates) | rejected | The ledger losses are real; an AI that opens routes it will lose money on collapses later (AE-037 saw exactly that). The estimator must predict the ledger, not flatter it. |
| **Arbitrary multiplier** (e.g. movement fee × 0.5 for turboprops) | rejected | A number chosen to make a scenario pass, with no unit behind it. The seat scale has one: the fee per movement is anchored at the reference 180-seat narrowbody and is proportional to what lands, so the calibrated class does not move. |
| **Scale by fuel burn as a weight proxy** | rejected | Burn/km is available, but it under-relieves the turboprop (NA70/MR180 = 0.61 against a real weight ratio near 0.3) and is not a number a player can see on the aircraft card. Seats are. |
| **Change the ledger's maintenance to the estimator's hourly rate** | rejected | Would add ~$180k a month per narrowbody to every airline and the player, cutting the anchor's all-in margin by roughly ten points; a whole-economy recalibration and out of this phase's scope. The ledger is the game's truth; the estimator predicts it. Recorded under TD-031. |
| **Fix only the estimator** | rejected as sufficient | Lifts the NA70's profitable candidates from 40 to 126 in the estimator's eyes, but the ledger would still lose money on them; the AI would open routes it cannot keep. |
| **Fix only the fee scale** | accepted, but not alone | Lifts NA70 candidates to 259 across 79 of 80 homes in the ledger's terms; the profit-basis ranking would still under-count them by the maintenance overstatement. |

## 3. Proposed fix

**Layer: Core simulation (one shared formula) and Core AI estimator.
Content: one new tuning constant. No save-format change.**

1. **Movement fee scales with seats, anchored at 180.**
   `AirportSpec.movementFee(for: AircraftTypeSpec, ops: OpsTuning)` =
   `movementFee × seats / ops.movementFeeReferenceSeats`, integer cents,
   `movementFeeReferenceSeats = 180` in `tuning.json`. `FlightOpsSystem.arrive`
   and `CompetitorAISystem.airframeDayValue` both call it. The passenger
   fee is untouched. The 180-seat MR180 pays exactly what it paid; the
   PA184 +2.2%, the NA160 −10%, the NA70 ×0.38, the AV90 ×0.49, the
   MR300 ×1.66, the AV420 ×2.34.
2. **The estimator's maintenance line is the ledger's rule ahead of
   time.** `FleetEconomics.expectedMaintenancePerDay(type:blockHoursPerDay:
   fleet:ops:)` = check cost × (daily condition decay + wear per flight
   hour × hours flown) / (1 − threshold), the same constants the fleet
   system uses; `airframeDayValue` uses it instead of the hourly rate.
   The ledger does not change.

Nothing else: no horizon change, no ranking-basis change (TD-030 is
re-measured, not shipped, in Phase 10), no fare change, no fee level
change, no player-specific or archetype-specific branch.

## 4. Expected impact (quantitative, predicted before implementation)

From the candidate battery's arithmetic under the new rules, and the
route battery's ledger months re-computed with the seat scale:

| Metric | Now (MEASURED) | Predicted after |
| --- | ---: | ---: |
| NA70 profitable candidates, estimator, world | 40 of 542 at 28 homes | 374 at 80 of 80 homes |
| AV90 profitable candidates | 294 of 747 at 69 homes | 504 at 86 of 86 homes |
| MR180 profitable candidates | 511 of 842 | 542 (maintenance line only) |
| NA70 median fee share of revenue | 0.82 | 0.43 (MR180 0.38, unchanged) |
| Regional archetype at CDG (its home from the European starts), NA70 | 0 profitable | 11 profitable, best PRG +$10.3k/day |
| Regional archetype at ORD (New York start), NA70 | 0 | 7, best DEN +$13.4k/day |
| JFK–ORD NA70, ledger month | fees $771k, all-in −$520k | fees ≈ $415k, all-in ≈ +$60k |
| LHR–CDG NA70, ledger month | fees $793k (157%) | fees ≈ $404k (80%) — still a loser: cause 4 |
| LHR–JFK MR300 (AI), ledger month | fees $625k (9%), margin 34% | fees ≈ $789k (11%), margin ≈ 32% |
| Anchor fixture MR180, any route | unchanged to the cent | unchanged to the cent |
| Estimator maintenance / ledger maintenance | 9.8× | ≈ 1.0× ± one check |

Not predicted: whether the regional archetype survives five years with
these markets (Phase 9 measures it), whether the profit ranking becomes
safe (Phase 10), whether the premium archetype's widebody margins fall
enough to matter (Phase 11).

## 5. Risks

| Area | Risk | How it is watched |
| --- | --- | --- |
| Long haul / widebodies | movement fees ×1.66–2.34 for the premium archetype's fleet; margins fall from the mid-30s | archetype battery (survival, margin < 60%), the long-haul rows of the route battery re-run |
| Hubs | no change per movement for narrowbodies; more small-aircraft routes may open at hubs and use slots | ten-year world (slots, HHI, flights bound) |
| Player economy | PA184 +2.2% on fees, NA160 −10%, turboprops and regional jets cheaper; the guided route sheet does not name fees | first-era campaign twins (era day, profits) re-run; UI journeys unchanged in intent |
| Rival expansion | rivals in small aircraft open more routes; the cast gets busier | `ae-rival-scan --rivals` before/after (openings at the player's airports, collapses) |
| Bankruptcy | fewer regional collapses expected; watch the premium archetype | scan collapses by archetype; balance battery survival ≥ 60% |
| Ten-year stability | more routes, more flights | `tenYearWorldRemainsStableAndContested` bounds |
| Route scarcity | short hub pairs stay fee-bound for everyone (cause 4 untouched) | recorded, not changed |
| Airport value | small-aircraft fees fall at every airport, big-aircraft fees rise; the airport's fee number keeps its meaning as "per 180-seat movement" | documented in docs/AIRPORTS.md |
| Determinism | integer cents, no floating fee math | dual-run hash tests unchanged |
| Save compatibility | no persisted field changes | save-format tests unchanged |
