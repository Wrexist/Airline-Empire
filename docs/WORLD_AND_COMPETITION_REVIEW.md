# World Events & Competition — implementation and evidence

## Result

Both World surfaces now answer the question the screen is for before they
describe the world.

**World events** leads with the player's own exposure, then splits the
disruption into what is here and what is coming — because those two are acted
on differently:

1. **Your exposure** — how many of the player's routes are in a path and how
   much flying that is, as counts (`5 of your routes are in a path — 10 round
   trips a day`), each route opening the route it names. Says
   `None of your routes are in a path.` when there are none, which is a real
   answer rather than an empty card.
2. **Happening now** — the events that have started, severity and effect line
   on each.
3. **Forecast** — the events that have not, with the same body.

**Competitors** now leads with the player's fights and the news near them
instead of a cast list:

1. **Overview** — the four network figures, unchanged.
2. **Where you are fighting** — every contested pair as a comparison: the
   standing, a share bar of today's passengers by carrier, the strongest rival
   beside the player, the single attractiveness term that separates them, and —
   when behind — the response the simulation's own arithmetic supports.
3. **What rivals did near you** — one prioritised list of rival moves: the
   player's own markets first, then an airport they serve, then a pair the
   player later joined; newest first inside a rank.
4. **The rivals**, as characters, without the per-card copy of the moves that
   made the news hard to scan.

Nothing estimates what a rival will do next. Every figure is a derivation of
`MarketCompetition` — the demand engine's own split from this morning, its own
attractiveness terms, and the scheduler's spare rotations.

## Audit before implementing

Audited on `codex/ae049-aircraft-configuration` before any change. Existing
unrelated working-tree edits were preserved and never staged.

| Area inspected | Existing authoritative behavior | Decision |
|---|---|---|
| `WorldEventsView` | One `ForEach` over `activeEvents`; every event card already carried severity, timing (`Until … · N days left`), the effect line and the player's affected routes with links. | Keep the card body; add the exposure summary and split started from unstarted. |
| `CompetitorsView` | Overview strip (contested/leading/losing/rivals) and one link per contested pair, plus rival cards that each repeated every move. | Keep the strip; turn each link into a comparison; hoist the moves into one prioritised list. |
| `CompetitionSummary` (`Competition.swift`) | `contested`, `recentMoves` (most recent first), `headline`, `RivalStanding` — all pure derivations. | Reuse; add a stable screen priority to `recentMoves`; no new state. |
| `MarketCompetition` | Per-route share, `evenShare`, `marketDemandToday`, `edge` (`Edge` = fare/schedule/reputation/comfort/operations), `strongestRival`, `spareRotationsToday`. | Read them directly for the comparison; invent nothing. |
| `Vocab.worldEventEffect`, `Vocab.severity` | The simulation's own effect text and severity band. | Reuse; the exposure card claims counts, never disruption or savings. |
| `MissionMath.touchesRegion` | The single definition of "a route is in a region's path". | Reuse for exposure so the summary and the per-event cards cannot disagree. |
| Persistence | Nothing new. | No save change. |

### What the audit found

- The order was the view's, and it mixed "what is happening to me" with "what
  the world is doing": the affected routes were only readable inside each event
  card, so a five-route airline had to read five cards to learn it was exposed
  five times.
- A started storm and a four-days-away boom sat in one list in event-id order,
  so the thing to act on now and the thing to plan for read identically.
- Per-rival cards repeated the same move list once per rival, and the "what
  rivals did" ordering was strictly by date — a move at an airport the player
  passes through outranked a move on the player's own pair if it was newer.

## Core

`AirlineEmpireCore/Sources/AirlineEmpireCore/Session/Competition.swift`,
`CompetitionSummary.recentMoves`:

- Sorted for a screen rather than strictly by date: rank by relevance
  (`.onPlayerMarket` → `.atPlayerAirport` → `.beforePlayerJoined`), then newest
  first, then by position in the bounded record, then deterministically by
  airline/pair. Moves only reach the list when they touch the player.
- The relevance ranking is a pure function of the snapshot; no new stored
  state and no new estimate.

No other Core behavior changed. The demand split, the edge terms and the spare
rotations were already models; this phase only gave them a screen.

## Screen

`AirlineEmpireApp/Sources/Screens/OperationsView.swift`

- `WorldEventsView`: `exposureCard(onNow:forecast:)` + `sectionHeader(_:_:id:)`;
  the layout is exposure → `Happening now` → `Forecast`.
- `CompetitorsView`: `whereYouAreFighting`, `contestedRow`, `shareBar`,
  `shareLabels`, `rivalMoves`, `moveRow`; `rivalCard` no longer takes the
  summary and no longer renders moves.
- `AirlineEmpireApp/Sources/DesignSystem/Vocabulary.swift`: `Vocab.edge(_:)`
  (the "why" clause) and `edgeClause` made internal.

New identifiers: `ae-events-exposure`, `ae-event-exposed-route`, `ae-events-now`,
`ae-events-forecast`, `ae-contested-markets`, `ae-contested-route`,
`ae-rival-moves`, `ae-rival-move`. Existing identifiers (`ae-rival-card`,
`ae-fleet-row`, …) are unchanged.

### A measured harness finding

Run [35136273799](https://github.com/Wrexist/Airline-Empire/actions/runs/35136273799)
rendered both screens correctly and still failed every new device journey. The
`AX hierarchy after failure` dump showed why: an `accessibilityIdentifier`
applied to a **container** propagates to every descendant and **overwrites** the
identifiers the children set for themselves. The exposed-route links and the
contested-market link were present — `5 of your routes are in a path`, the
CDG–ARN comparison — but every one of them was addressed as the panel
(`ae-events-exposure` / `ae-contested-markets`), so `ae-event-exposed-route` and
`ae-contested-route` matched nothing.

The fix is the pattern the fleet board already used: mark the panel
`.accessibilityElement(children: .contain)` before its identifier, so the panel
is a container and each child keeps its own. The same run also caught a real
Core defect: two moves recorded in the same instant (a rival entering and
leaving in one tick) tie-broke to array order, so an exit could read as an
arrival. Same-instant ties now break by recording order, with a test.

## Validation

**Core.** `CompetitionPriorityTests`: a move on the player's own market leads a
newer move at one of their airports; same-rank moves stay newest first; two
moves recorded in the same instant list the one recorded last first and the
headline reads as the exit.

**Screen tests.** `AccessibilitySurfaceReviewTests.testWorldEventsAndCompetitionAtAccessibleSizes`
renders both screens with a storm on now, a boom forecast, a contested pair with
a real split, and staged moves on the player's market and at one of their
airports, at 393 pt and 834 pt in light and dark plus an AX5 frame.
`WorldAndCompetitionUITests` is the device journey: current/forecast/exposure,
the comparison and prioritised moves, and the comparison at the largest text.

**Runs.** Branch validation
[35140628926](https://github.com/Wrexist/Airline-Empire/actions/runs/35140628926):
the focused Core suite — **248 tests passed** — and the release build with
warnings as errors, then the iPhone journeys (airport, passenger, fleet,
finance, campaign, briefing and world/competition), the iPad journeys and both
hosted capture suites. All green.

The **full** Core suite then ran on the same revision through `ci.yml`
([35146386250](https://github.com/Wrexist/Airline-Empire/actions/runs/35146386250)):
**595 tests passed**, and the release build was clean with warnings as errors.

## Frames inspected, and what looking found

- **World events, 393 pt, light and dark** (`WORLD-01-events-393-*`): the
  exposure card reading `1 of your routes is in a path — 2 round trips a day`
  with its route link, then the started storm under **Happening now** and the
  boom under **Forecast**, each with severity, timing and effect.
- **Competitors, 393 pt, light and dark** (`WORLD-02-competition-*`): the
  overview strip, the CDG–ARN comparison with its share bar (`You 33%` /
  `Aurora Atlantic 34%`) and `even · 33%`, then the moves in priority order —
  the two market entries before the airport-level move and the
  walked-into market last.
- **iPad, regular width** (`WORLD-01-events-834-*`, `WORLD-02-competition-834-*`):
  the same content in a single wide column with no stretched rows.
- **Large Dynamic Type** (`WORLD-07-AX5-*`): the comparison and the move list
  wrap without truncation.
- **Device, dark** (`KEY-EVENTS-01-now-forecast-exposure`,
  `KEY-COMP-01-comparison`, `KEY-COMP-02-moves`, `KEY-COMP-AX`): the five
  exposed routes on a real phone, the comparison opening a route, and the
  prioritised moves with the player's own market tinted and the airport-level
  move muted.

Two staging defects were found by looking, not by the assertions: the device
fixture's airport code was written the wrong way round (fixed in the fixture),
and the same-instant move ordering. Both are corrections to test staging and
Core ordering, not invented product behavior.

### Screenshot evidence map

| Requested evidence | Evidence |
|---|---|
| Actual iPhone screenshot | `KEY-EVENTS-01-now-forecast-exposure`, `KEY-COMP-01-comparison`, `KEY-COMP-02-moves` |
| Full-page native capture | Hosted `WORLD-01-events-393-light` / `-dark`, `WORLD-02-competition-393-light` / `-dark` |
| Light and dark | Hosted `WORLD-01-*`, `WORLD-02-*` at 393 pt and 834 pt |
| Large Dynamic Type | Hosted `WORLD-07-AX5-dark` / `-light`; device `KEY-COMP-AX` |
| iPad | Hosted `WORLD-01-events-834-*`, `WORLD-02-competition-834-*`; device on the iPad shell |
| A contested pair links to its route | `KEY-COMP-01-comparison` (the comparison row opens LHR–CDG) |

The GitHub runs retain the `airport-review` artifact with the source PNGs,
manifests and logs; local exports are under `build/ae-run-35140628926`.

## Next recommendation

From `docs/NEXT_SCREEN_REVAMPS_2026-09-15.md`, the last slice is **Aircraft
Market comparison** (#7). The screen already has purchase terms, route
selection, filters and new/used/lease options — historical notes claiming no
route matching are stale. The revamp is to compare a small shortlist for one
actual route: runway/range fit, capacity, availability, immediate payment and
recurring terms, keeping the existing purchase-and-assignment flow.

Its Core constraint is specific: comparable economics must hold route, fare and
frequency constant and use the shared allocation, and the existing fit rank must
not be relabelled "most profitable" — `FleetPlanning.swift` describes fit as a
ranking, not a profit forecast.
