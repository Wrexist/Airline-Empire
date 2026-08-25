# Airline Empire — Reputation & Service Quality (Phase 9, as built)

## Model

`Reputation` per airline — five 0…1 components, all EWMA-drifting toward
what the airline *currently delivers* (rate 0.05/day ≈ weeks-scale memory;
value perception 0.02/day ≈ months). Never a permanent score: good history
buys grace, not immunity, and every hole is climbable (GAME_DESIGN §4.10).

| Component | Drifts toward | Source |
|---|---|---|
| punctuality | day's on-time share of completed flights | `DailyOps` counters fed by FlightOps |
| reliability | day's completion (non-cancellation) share | same |
| service | tier target (basic 0.35 / standard 0.60 / premium 0.85) | `ServiceTier` via `SetServiceTierCommand` |
| comfort | seat-weighted fleet comfortBaseline | fleet composition |
| valuePerception | 0.5 + (quality−0.5) − 0.75×(farePosition−1) | quality vs. `farePositionEWMA` (fare/reference ratio, unclamped EWMA) |

Blend: 25/25/20/15/15 → score → **demand multiplier 0.8 + 0.45×score**
(×0.8 dismal … ×1.25 excellent, neutral ≈ ×1.02), applied in the demand
engine's offer quality. Administration applies a ×0.85 scar to all
components (the lasting cost of failure beyond the fire sale).

## Service economics

Each carried passenger costs `serviceCostPerPax(tier)` (¤4/9/18), posted as
`passengerService` (operating expense, classified). Premium service is a
real tradeoff: the year-long test shows premium both costs visibly and
out-carries standard — the loop from GAME_DESIGN §4.10 (service → 
reputation → demand → revenue) is closed and measured.

## Feedback loops verified by tests

- Reliable ops build punctuality/reliability > 0.9/0.85 over a year;
  a worn airframe on a packed schedule stays visibly below those ceilings.
- Overpricing (2.5× reference) collapses value perception (< 0.35) while
  fair pricing sits ≈ 0.77 — the positioning teacher.
- A scarred airline persistently cedes share to an otherwise identical
  rival.
- Save/restore determinism holds with reputation active.

## Bug found by tests this phase

The shared `drift` helper clamps to 0…1 — correct for components, but it
silently pinned `farePositionEWMA` (a ratio ≥ 1 for premium pricing) at
exactly 1.0, neutering value perception. Fare position now updates
unclamped; the overpricing test pins the fix.

Save format v7. Marketing spend was deliberately deferred (design lists it
under finance): it belongs with brand positioning once competitors can
react to it (Phase 10+), not as a dead dial now — tracked in TODO.
