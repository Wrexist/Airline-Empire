# Fleet Operations & Maintenance — implementation and evidence

## Result

The Fleet tab now opens on an actionable **fleet health board**: the aircraft
that want a decision (idle, condition closing on a check, a lease ending), then
the ones that simply cannot fly today (in a check, on order, with the date they
return), each a compact row that links to that aircraft's own screen and
actions. The full sortable/filterable fleet list remains below, unchanged.

Nothing about the simulation changed. The only Core edits are a new pure read
model plus two extractions that keep one definition of the scheduler's rotation
allotment and the condition decay the fleet system already applied.

## Audit before implementing

Audited at `765da1c` on `codex/ae049-aircraft-configuration`, before any change.
Existing unrelated edits were preserved.

| Area inspected | Existing authoritative behavior | Decision |
|---|---|---|
| `FleetList` (FleetView.swift) | Summary strip from `FleetSummary`, one idle-aircraft prompt, filter bar, sortable rows, aircraft detail with sell/return/assign. BUG-059's prompt counted idle aircraft but named only the first. | Replace the single prompt with a grouped board; keep summary, filters and rows. |
| `FleetSystem` | Daily: ages, decays condition, delivers orders, completes checks (condition → 1.0), grounds when condition < 0.75 and posts the check cost. | Do not change. Quote the same cost; estimate the check interval from the same constants. |
| `FleetEconomics` | `maintenanceCheckCost` (age-scaled), `expectedMaintenancePerDay`, reliability, depreciation, sale value. | Add `conditionPerDay` and `daysUntilCheck`; refactor `expectedMaintenancePerDay` onto `conditionPerDay` (identical arithmetic). |
| `FlightSchedulingSystem` | `roundTripsPerAircraftPerDay` and the internal flight-time math; `AircraftConfigurationPreview` re-derived the per-aircraft rotation split. | Extract `rotationsPerDay`/`blockHoursPerDay`; the aircraft preview now calls them, so the board and the forecast cannot disagree about how often an airframe flies. |
| `FleetCardModel` / `FleetSummary` | Card carries status, ownership, condition, reliability; summary carries counts, utilisation, value, lease bill. | Build the board on `fleetCards` so a board row and a list row cannot describe one aircraft differently. |
| `FleetFilter` / `AircraftRole` / `AssignmentEligibility` | Existing status/ownership/category filter and eligibility mirror. | Reuse; the board does not re-derive eligibility. |
| Persistence / migrations | v13 current; aircraft status, condition and ownership are already persisted. | No persisted shape changed. The board is derived, so save/load is unchanged. |
| Tests | `FleetTests`, `FleetIntegrityTests`, `FleetPlanningTests`, `SummaryModelTests`, `AssignmentEligibilityTests`. | Add `FleetBoardTests` for ranking, availability vs inspection, quotes and determinism. |

### What the audit found and did not add

- Maintenance is **triggered by condition, not by the player** — so the board
  must not offer a "do the check now" action it cannot honour. It reports the
  quote and the estimated interval instead.
- There is no stored cost on an in-check aircraft (the cost lives in a bounded
  event log), so an in-check row shows the return date, not a made-up figure.
- Replacement forecasts and batch economic commands would need new authoritative
  work; they are not promised here (docs/NEXT_SCREEN_REVAMPS_2026-09-15.md §2).

## Core read model

`AirlineEmpireCore/Sources/AirlineEmpireCore/Session/FleetBoard.swift`

- `FleetBoard` groups the fleet into `needsDecision`, `unavailable` and `flying`,
  counts each issue, and ranks rows: idle → condition low → lease ending →
  reliability down → in check → on order → working, then by soonest check.
- `FleetBoard.Row` embeds the fleet card, an `Availability` (available / in a
  check until / on order until), the assigned route pair, the actionable
  `issues`, an estimated `checkDueInDays` and the exact `checkCost` quote.
- `FleetAttentionThresholds` classifies (low condition 0.80, reliability 0.93,
  lease ending 3 months, check soon 14 days) — design constants that never feed
  the engine.

`FleetEconomics.conditionPerDay` and `daysUntilCheck` give the check estimate
from the same daily decay and wear-per-flight-hour the engine applies;
`FlightSchedulingSystem.rotationsPerDay`/`blockHoursPerDay` give the flying rate
from the same arithmetic that materialises the schedule.

## Screen

`AirlineEmpireApp/Sources/Screens/FleetView.swift`

- `FleetHealthBoard` — a grouped panel between the summary and the list: a
  "needs a decision" group and an "unavailable" group, each capped at four rows
  with the remainder left to the list, plus a total quote for checks due soon.
- `FleetHealthRow` — one comparable row: type, where it is (route, idle, check
  date or delivery date), issue chips carrying the numbers, and — when a check
  is close — its quoted cost. It reflows to a single column at accessibility
  sizes and relies on the List's own chevron.
- `FleetSummaryRow` gained "Needs a decision", "Condition low" and "Leases
  ending" in its detail disclosure.

The filter bar keeps its place directly under the summary; the board sits below
it. Empty fleets, filters that match nothing, the sort menu and every existing
identifier (`ae-fleet-row`, `ae-fleet-statistics`, `ae-fleet-status-filter`, …)
are unchanged.

## Validation

**Core.** `FleetBoardTests` covers: idle ranks first and is the only decision;
in-check and on-order are unavailable, not decisions, and carry no check
estimate; low condition and worn reliability are inspection concerns;
lease-ending fires only near the term; a fresh aircraft is healthy; the check
quote equals `FleetEconomics.maintenanceCheckCost` and flying shortens the
interval; due-soon counts and costs only inside the window; and the board is
deterministic and does not mutate the state.

**Runs.** Branch validation
[35058638895](https://github.com/Wrexist/Airline-Empire/actions/runs/35058638895):
the 141-test focused Core suite (which includes the nine new `FleetBoardTests`)
and the release build with warnings as errors, then the iPhone journeys (airport,
passenger and fleet), the iPad journeys and both hosted capture suites.

The **full** Core suite then ran on the same revision through `ci.yml`
([35060979947](https://github.com/Wrexist/Airline-Empire/actions/runs/35060979947)):
**574 tests passed** (573 in the parallel run plus the isolated campaign test),
and the release build was clean with warnings as errors. This covers the two
extractions — `FlightSchedulingSystem.rotationsPerDay` used by
`AircraftConfigurationPreview`, and `FleetEconomics.conditionPerDay` used by
`expectedMaintenancePerDay` — against the whole simulation, not only the fleet
filters.

## Frames inspected, and what looking found

- **Full page, light and dark, 393 pt** (`FLEET-03-board-*`): summary, filter,
  the two board groups with their issue chips, and the full list below.
- **iPad, regular width** (`FLEET-08-iPad-*`, `KEY-FLEET-01-board` on the iPad
  shell).
- **Large Dynamic Type** (`FLEET-07-AX5-*`, `KEY-FLEET-AX-board`): one-column
  board rows; the device frame confirms a board row and the filter are both
  reachable at AccessibilityL.

Two real layout defects were found by looking and fixed:

1. Each board row drew its own chevron *and* the List drew one for the link, so
   every row showed two. The row's own chevron was removed.
2. At accessibility sizes the chips sat beside the category icon in an HStack
   and were squeezed into one syllable a line ("unas-signed", "Condi-tion").
   The row now stacks vertically at those sizes and the chips were shortened.

One cosmetic limitation remains and is recorded rather than claimed clean: at
the largest accessibility size (AX5) the longest chip, "Condition · 77%", still
wraps its label across two lines. The text stays legible and the control stays
tappable; it is the one hosted stress frame that is not pixel-perfect.

### Screenshot evidence map

| Requested evidence | Evidence |
|---|---|
| Actual iPhone screenshot | `KEY-FLEET-01-board`, `KEY-FLEET-02-aircraft`, `KEY-FLEET-03-filter-idle` (iPhone simulator, dark) |
| Full-page native capture | Hosted `AX-COMPONENT-FLEET-03-board-light` / `-dark`, 393 pt |
| Light and dark | Hosted `FLEET-03-board-*` and `FLEET-08-iPad-*`; device `KEY-FLEET-AX-*` in light |
| Large Dynamic Type | Hosted `FLEET-07-AX5-*` (375 pt); device `KEY-FLEET-AX-board` / `-reachable` |
| iPad | Device `KEY-FLEET-01-board` on the iPad shell; hosted `FLEET-08-iPad-*` |

Local exports are under `build/ae-run-35058638895` on the machine that ran the
review; the GitHub run retains the `airport-review` artifact with the source
PNGs, manifests and logs.

## Next recommendation

From `docs/NEXT_SCREEN_REVAMPS_2026-09-15.md`, the next slice is **Finance —
Profit, Cash Flow & Commitments**: align period labels, group operating
performance, cash movements and recurring commitments, names the decisions
behind the largest expenses, and keep the existing loan and solvency flows. Any
new statement or ledger breakdown must come from Core; do not confuse cash change
with profit or imply money is reserved when it is not.
