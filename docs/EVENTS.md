# Airline Empire — Events & Living World (Phase 11, as built)

## Principle

Events are **systemic**: they emerge from state + seeded randomness under
rate limits, and their effects flow through the systems that own each
domain. The economy cycle and fuel walk (Phase 8), competitor failures
(Phase 8/10), and delay cascades (Phase 6) were already living-world
mechanics; Phase 11 adds the exogenous layer on the same principle — no
detached popup theater, and every event creates decisions (reroute, wait,
discount, ground) rather than a pure toll.

## Event population (`WorldEvent` in `WorldState.activeEvents`)

`WorldEventSystem` (daily, first in the pipeline): expiry → start
announcements → rate-limited triggering, all deterministic (sorted
iteration, per-purpose RNG substreams, cooldown ledger in
`world.eventCooldowns`).

| Kind | Trigger | Effect (where applied) | Duration |
|---|---|---|---|
| `fuelShock` | 0.25%/day, ≥45-day major cooldown, one at a time | fuel walk's reversion target ×(1+severity 0.3–0.9) (`WorldSystem`); hard clamp band unchanged | 30–90 d |
| `storm(region)` | 0.4%/day × region weather-risk factor (0.5–2.2 from airport `weatherRisk`) | +30%×severity dispatch disruption on flights touching the region (`FlightOpsSystem`) | 1–3 d, **1-day forecast lead** (`worldEventForecast`) |
| `airportClosure` | escalation of a ≥0.85-severity storm: region's most exposed big airport | boarding blocked at the airport → flights expire as cancellations; ops resume cleanly after | ≤2 d |
| `tourismBoom(region)` | 0.2%/day, one at a time | destination-region leisure demand ×1.35 (`DemandSystem`) | 60–120 d |
| `strike(airline)` | service reputation < 0.35 → 2%/day, 180-day per-airline cooldown | that airline boards nothing (expiry cancels); competitors unaffected | 2–4 d |

Caps: ≤2 concurrent regional events; majors respect a shared cooldown; the
event array is permanently small (expiry is tested over 5 years).

The strike is the flagship feedback loop: neglect service → reputation
drops → workforce walks → cancellations → punctuality/reliability drop →
demand penalty. Purely systemic, fully player-preventable.

## Player/AI symmetry

Effects hit everyone identically: an AI's airline can be struck, its region
stormed, its market boomed. AI retrench/expansion logic reacts to the
resulting economics with no special knowledge.

## Verified by tests (8 new; 169 total)

Five-year generation run: storms occur, events end, concurrency caps hold,
population bounded; storm forecasts always precede their start; injected
fuel shock lifts prices >1.3× a calm twin; airport closure grounds the
route (cancellations accrue, nothing completes) and ops resume after;
strike stops exactly one airline; tourism boom measurably lifts route
demand grants; 2-year full-pipeline dual-run determinism and mid-events
save/restore continuation.

Save format v9.
