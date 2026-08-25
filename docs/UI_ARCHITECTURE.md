# Airline Empire — UI Architecture

> Phase 1 document; Phases 14–17 implement it. Structural rules bind earlier
> (they shape `GameSession`'s public API in Phase 3).

## 1. Position in the system

The app target (`AirlineEmpire`) is a *client* of `AirlineEmpireCore` through
exactly one façade:

```swift
public protocol GameSessioning {           // implemented by GameSession
    var snapshots: AsyncStream<GameSnapshot> { get }   // state, ≤ once/frame
    var events: AsyncStream<SimEvent> { get }          // feed/toasts/haptics
    func submit(_ command: Command) async -> CommandResult
    func setSpeed(_ speed: SimSpeed) async             // pause/1x/2x/…
    func save(slot: SaveSlot) async throws
    // + new/load/list-saves lifecycle
}
```

**[RULE]** Views and view models never import engine internals; `GameSnapshot`
(an immutable value: `GameState` + memoized derived read models) and
`Command` are the entire vocabulary. Anything the UI needs twice gets a
derived read-model accessor on the snapshot — computed in Core, tested in
Core (e.g. `snapshot.routeProfitability(routeID)` — the *same* number the
economy used, which is what makes finances explainable).

## 2. App structure

- **Composition root** (`AirlineEmpireApp`): builds `GameSession`, services
  (haptics, audio, settings store), and injects them via environment.
- **Navigation shell:** adaptive — tab bar on iPhone, sidebar/split on iPad —
  over the primary areas: Home/Dashboard, Map, Fleet, Routes, Finances,
  Operations (airports, competitors, events), Progression, Settings.
  Navigation state is a value (`AppRoute` enum tree) so deep links from
  events/notifications ("tap → the delayed flight") are data, and testable.
- **Per-area view models:** `@Observable`, one per screen area, subscribing
  to snapshots and *projecting* (format, sort, filter, diff for animation).
  **[RULE]** View models contain zero game rules: no thresholds, no prices,
  no eligibility logic — they call snapshot read models. Formatting
  (currency, dates, deltas) is centralized in `Formatters`.
- **Design system** (Phase 14): `AETheme` tokens (type scale, spacing grid,
  colors, radii, elevation), component library (cards, stat tiles, badges,
  charts, list rows, sheets, empty states, confirmation flows). Charts built
  on Swift Charts. **[RULE]** Screens compose the component library; no
  ad-hoc styling in feature views.

## 3. Map (Phase 15 — summary of the architectural contract)

- Renderer: SpriteKit scene hosted in SwiftUI (decision point re-validated in
  Phase 15 against Canvas with a spike; the *contract* is renderer-agnostic).
- Input: `MapViewModel` translates snapshots into a `MapScene` model —
  airports (with LOD tiers), route arcs (styled by ownership/health/volume),
  live flights (positions interpolated from departure/arrival SimTimes and
  great-circle paths — presentation-only interpolation).
- **[RULE]** The map never queries the engine directly and never runs at
  simulation cadence; it renders the latest snapshot at display cadence with
  its own culling/clustering. Selection round-trips as IDs.

## 4. Update flow

```
SimulationActor → snapshot → MainActor view models → SwiftUI diff → screen
     ↑                                                        │
     └—————————— Command (async, with typed result) ←—————————┘
```

- Commands give immediate optimistic *feedback* (button states, spinners)
  but never optimistic *state* — the snapshot is the only truth the UI shows.
  Rejections surface as human-readable reasons from `CommandRejection`.
- Events drive transient UX (toasts, feed, haptics via `HapticService`,
  sound via `AudioService`) — both app-side services keyed off `SimEvent`
  types, with per-category user settings.

## 5. Platform & accessibility baseline (bind now, audited Phase 21)

- iPhone and iPad, portrait + landscape where layout permits; safe-area
  correct; Dynamic Type through the token system (no fixed font sizes —
  **[RULE]**); 44pt minimum touch targets; VoiceOver labels on all
  interactive elements; Reduce Motion honored by the animation layer
  centrally; color semantics never conveyed by hue alone (badges carry
  icons/text).
- Performance: snapshot→frame work is O(visible), not O(world); lists are
  lazy; map applies LOD (§3).

## 6. What the UI must make the player feel (contract with Phases 14–17)

Clarity over decoration; every number tappable to its explanation (ledger
category, demand breakdown); every action answers *what happened, why, what
changed, what next* (Phase 16 checklist); empty states teach; the map is the
emotional centerpiece — "I built this network".
