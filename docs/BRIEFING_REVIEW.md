# Home Briefing — implementation and evidence

## Result

The briefing now reads as one decision hierarchy instead of ten cards in a
fixed order:

1. **Needs you now** — the solvency alarm kept at the very top, then every
   other thing that is costing money (idle aircraft, routes with no aircraft,
   routes losing this month) as a row with its reason and a link to the thing
   it is about, plus the single rival fact. Absent entirely when nothing is
   wrong, which is a real answer.
2. **How the airline is doing** — the live strip and the six numbers, each of
   which opens the screen that explains it.
3. **Next opportunity** — the first-session checklist while it runs, the
   ranking that replaces it, the next era, and what is coming up.
4. **The story so far** — yesterday with its why, and the operations feed.

The urgent order is now a Core read model (`BriefingModel`), so it cannot be
re-derived differently by a view. Home stays the map; the briefing is still the
sheet raised from the foot of it.

## Audit before implementing

Audited at `8c6373d` on `codex/ae049-aircraft-configuration`, before any
change. Existing unrelated edits were preserved.

| Area inspected | Existing authoritative behavior | Decision |
|---|---|---|
| `BriefingView` | Header, solvency/rescue, onboarding **or** Next Moves, rival pressure, next era, pulse, stat grid, yesterday, coming up, feed — one scroll, order hard-coded in the body. | Regroup under four headings; keep every subview and identifier. |
| `HomeNextMove` (map) | The map home's single next row, resolved by priority: solvency danger → onboarding step → idle aircraft → paying market → follow a flight → start the clock. | Leave it as the map's one row; the briefing's urgent stack is the fuller version of the same questions. |
| `SolvencyModel` | `.healthy` / `.watch` (overdrawn or under three months of runway) / `.danger` (below the floor, countdown running). | One insolvency alert; `.watch` already folds runway in, so no second runway alert. |
| `NetworkSummary` / `FleetSummary` / `DashboardModel` | Live flights, load factor, month to date, losing/idle routes; idle/utilisation; cash, net worth, counts, reputation. | Compose them; never recompute. |
| `OnboardingModel` | The first-session arc and its next step. | Expose the next step on the briefing model so the arc's place is explicit. |
| `DailyDigestModel`, `UpcomingCard`, `EventRow`, `CompetitionSummary.Headline` | Yesterday, the forward calendar, the feed and the rival pick. | Keep as the history/opportunity sections; no new derivation. |
| Persistence | Nothing new. | No save change; the briefing is derived per snapshot and cached like the other read models. |

### What the audit found

- The **order was the view's**, not a model's, and it mixed urgency with
  history: the pulse sat below yesterday's digest for four phases ("how is my
  airline doing right now" two scrolls under "how did it do yesterday").
- Two guidance surfaces existed (`HomeNextMove` on the map, the onboarding /
  Next Moves cards in the briefing) with no shared priority, so the map and the
  briefing could point at different things.
- The empty feed said "Quiet skies. Open a route to get moving." even to an
  airline with routes — a pre-existing line that the new history section made
  more visible. It now says the feed is empty rather than that the airline is.

## Core read model

`AirlineEmpireCore/Sources/AirlineEmpireCore/Session/BriefingModel.swift`

- `BriefingModel.alerts` — `insolvency` (critical when below the floor, warning
  when close), `idleAircraft`, `groundedRoutes`, `losingRoutes`, sorted by
  severity then by a documented rank. Each alert carries the state, not the
  words; the reasons live in `Vocab`.
- `BriefingModel.performance` — the `DashboardModel`, `NetworkSummary` and
  `FleetSummary` composed (not copied), so every figure is the one the screen it
  opens will show.
- `BriefingModel.firstSession` — the onboarding arc's next step while it runs.

`GameController.briefingModel` caches it for one published snapshot, alongside
the map model and the other derived values.

## Screen

`AirlineEmpireApp/Sources/Screens/BriefingView.swift`

- `needsYouNow` — the solvency banner and rescue offer, then the alert rows
  (`AENextStepLabel`, tints from severity, the idle row breathing only when
  critical), then `RivalPressureCard`.
- `howItIsGoing` — the pulse and the stat grid under one heading.
- `nextOpportunity` — `OnboardingCard` or `NextMovesCard`, `NextEraBriefing`,
  `UpcomingCard`.
- `theStorySoFar` — `DigestSlot` and the operations feed.

Every existing identifier is unchanged (`ae-next-moves`, `ae-rival-pressure`,
`ae-stat-reputation`, `ae-next-era-guidance`, `ae-briefing-close`).

## Validation

**Core.** `BriefingModelTests`: no airline has no briefing; the first-session
step leads while the arc runs and moves on as it progresses; an idle aircraft
(warning) sorts above a losing route (watch); insolvency is critical and first;
a healthy assigned fleet has nothing to nag about; the composed performance
equals the summaries it composes; and the model is deterministic and does not
mutate the state.

**Runs.** Branch validation
[35115793948](https://github.com/Wrexist/Airline-Empire/actions/runs/35115793948):
the 232-test focused Core suite and the release build with warnings as errors,
then the iPhone journeys (airport, passenger, fleet, finance, campaign and
briefing), the iPad journeys and both hosted capture suites.

The **full** Core suite then ran on the same revision through `ci.yml`
([35121091740](https://github.com/Wrexist/Airline-Empire/actions/runs/35121091740)):
**593 tests passed** (592 in the parallel run plus the isolated campaign test),
and the release build was clean with warnings as errors.

### A measured harness finding

Run [35109891089](https://github.com/Wrexist/Airline-Empire/actions/runs/35109891089)
finished every UI step green and was then **cancelled by the job's 45-minute
cap** while it was completing. Five phases of screens have grown the
single-job UI suite past the limit the workflow was written with. The branch
workflow's native cap is raised to **75 minutes**, with the measurement
recorded in the file. Splitting the iPhone and iPad journeys into separate jobs
would halve the wall time at the cost of a second 10x macOS runner; that is
left as a deliberate choice rather than taken silently.

## Frames inspected, and what looking found

- **Full page, light and dark, 393 pt** (`BRIEF-01-hierarchy-*`): the four
  ranks, the three alert rows with their reasons and links, the pulse and stat
  grid under one heading, next moves and the next era, coming up, yesterday and
  the feed.
- **iPad, regular width** (`BRIEF-08-iPad-*`).
- **Large Dynamic Type** (`BRIEF-07-AX5-*`, `KEY-BRIEF-AX-urgent`).
- **Device, dark** (`KEY-BRIEF-01-hierarchy`, `KEY-BRIEF-02-linked-alert`,
  `KEY-BRIEF-03-order`): the hierarchy on a phone, the idle alert opening the
  aircraft it is about, and the section order asserted by frame position.

Two staging defects were found by looking and fixed: the evidence fixture put
the idle aircraft on order (so the idle alert never appeared), and its
forced loss was smaller than a month of revenue (so the losing alert never
appeared). Both are test-fixture corrections, not product changes.

### Screenshot evidence map

| Requested evidence | Evidence |
|---|---|
| Actual iPhone screenshot | `KEY-BRIEF-01-hierarchy`, `KEY-BRIEF-02-linked-alert`, `KEY-BRIEF-03-order` |
| Full-page native capture | Hosted `AX-COMPONENT-BRIEF-01-hierarchy-light` / `-dark`, 393 pt |
| Light and dark | Hosted `BRIEF-01-hierarchy-*`, `BRIEF-08-iPad-*`, `BRIEF-07-AX5-*` |
| Large Dynamic Type | Hosted `BRIEF-07-AX5-*`; device `KEY-BRIEF-AX-urgent` |
| iPad | Hosted `BRIEF-08-iPad-*`; device on the iPad shell |
| An urgent row links to its action | `KEY-BRIEF-02-linked-alert` (the idle alert opens the aircraft) |

Local exports are under `build/ae-run-35115793948` on the machine that ran the
review; the GitHub run retains the `airport-review` artifact with the source
PNGs, manifests and logs.

## Next recommendation

From `docs/NEXT_SCREEN_REVAMPS_2026-09-15.md`, the next slice is **World Events
& Competition** (#6): separate current disruption from forecast, show the
player's real exposure, and make route comparisons and rival moves easier to
scan while keeping the working affected-route and market-share information. Its
Core note is explicit — any new impact estimate must use actual
operational/economic logic, and no rival intentions or guaranteed disruption
savings may be invented.

With six of the seven revamps done, the remaining screen after that is the
**Aircraft Market comparison** (#7), whose Core work requires holding route,
fare and frequency constant and using the shared allocation — and which must
not label the existing fit rank "most profitable."
