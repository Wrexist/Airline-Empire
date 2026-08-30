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

---

## 7. As-built status (Phases 14–15, authored on Linux)

**Core side (test-verified, 195 tests):**
- Read models (`ReadModels.swift`): `DashboardModel`, `RouteCardModel`
  (with the exact P&L breakdown the detail screen shows),
  `FleetCardModel`, `FinanceModel` — every number a screen presents is
  computed and tested in Core.
- Map model (`MapModel.swift`): equirectangular `MapPoint` space,
  great-circle arcs (LON–NYC arcs north, verified), initial-course
  headings, per-snapshot `mapModel(catalog:)` with LOD prominence,
  player-network marking, closure flags, and airborne-flight positions
  interpolated by flight-time fraction (presentation-only).
- `GameSession.populateStandardWorld(competitors:)` bootstraps the
  competitor cast for the app's new-game flow.

**App side (`AirlineEmpireApp/`, authored, NOT compiled — B-002):**
XcodeGen manifest + 12 SwiftUI sources: composition root with scene-phase
autosave and a 4 Hz pump task; design tokens + component library (cards,
stat tiles, badges, money text, monthly bars, empty states, speed control);
screens: new game (curated starts, seed sharing, continue slots),
dashboard (digest header, stat grid, curated ops feed), routes (list →
detail with fare/frequency controls and the why-money breakdown → ≤4-tap
open-route sheet), fleet (status/swipe actions, era-aware aircraft market),
finance (statement rows, loan desk quoting the simulation's exact rate),
world (events, competitors, progression incl. capability starts, service &
reputation, save), map (zoomable Canvas rendering MapModel with LOD,
selection callouts, rotated live aircraft), game-over screen.

**Added 2026-08-26 (AE-023 Linux scope):** onboarding read model
(`OnboardingModel.swift`) — the PLAYER_JOURNEY §1 guided first-route beat
as a pure derived checklist (no persisted flags, zero save impact) with
demand-ranked, eligibility-checked first-route suggestions; tested in
Core. App side: Dashboard onboarding card (auto-hides when complete),
suggestion-prefilled OpenRouteSheet, and the RouteDetail "Aircraft"
assign/unassign section (BUG-002 fix — the loop was previously
uncloseable from the UI).

**Added 2026-08-26 (V3 Linux-first pass):**
- **Event audience** (`Session/EventFeed.swift`, decision D-011):
  `GameState.subjectAirline(of:)` resolves whose business an event is
  (entity events resolve through ownership); `isFeedEvent(_:for:)` decides
  feed visibility — own business, world news, and rivals' public fates.
  `GameSession.events(playerFeedOnly:)` filters at publish time, against
  the exact state that produced the event. The app subscribes filtered.
- **Rejection delivery** (D-011): `GameSession.rejections()` publishes the
  outcome of commands queued while the simulation is running — the only
  path by which such a failure can reach the player.
- **Session lifecycle:** `GameController.quitToMenu()` releases the
  session and cancels the pump, event, and rejection tasks, so the app can
  return to the menu (game over, or save-and-quit).
- **Contract tests:** `ScreenContractTests` asserts that Dashboard, Route
  detail, Fleet, Finance, Map, and World screens can be drawn from Core
  alone on a real mid-game world; `PlayerJourneyTests` drives complete
  journeys through the command surface. These are the Linux stand-in for
  simulator walkthroughs and are how BUG-003/004/005 were caught.

**Added 2026-08-26 (evening digest):** `Session/DailyDigest.swift` —
`GameState.dailyDigest(for:day:)` summarizes a game day (money by
category, net cash change, flights flown/cancelled, the day's news) purely
from the ledger's timestamped ring and the event log. No per-day
accumulation, nothing new persisted, save format unchanged. Because the
ring is bounded, the model carries `isComplete` and the UI states plainly
when a day is partial rather than showing a wrong total. The Dashboard
renders it as a "Yesterday" card with an expandable breakdown; it is
snapshot-derived, so fast-forward updates it instead of queueing modals.
`TransactionCategory` labels live in one place (`DigestCard.label(for:)`)
and are reused by the Finance statement rows.

**Open item (AE-023):** first macOS session generates the project
(`xcodegen`), compiles, fixes view-layer syntax issues, and validates the
new-game → route → fast-forward flow on simulator. Until then these phases
are *authored*, not done.


---

## 8. As-built after the forensic audit (2026-08-29)

`docs/UIUX_FORENSIC_AUDIT.md` measured the client against this document and
found the structural rules honoured and several of the *product* rules not.
What changed, against the rules above:

- **§2 adaptive shell — now built.** `NavigationSplitView` at regular width,
  a five-item `TabView` at compact. Six tabs overflowed into the system *More*
  list (BUG-009); Routes and Fleet merged into **Network**.
- **§2 navigation state as a value — mostly.** Typed destinations
  (`RouteID`, `AircraftID`, `AirportCode`, `DashboardRoute`) are values, every
  screen links by value, and **a feed line about something you own opens it** —
  §2's "tap → the delayed flight", with dead subjects (a closed route, a sold
  aircraft) resolving to no link rather than a dead end. What is still not
  built is a single app-wide route tree with a *bound* `NavigationPath`, which
  is what an external deep link — a notification, a URL — would need to push a
  screen from outside the view hierarchy.
- **§2 charts on Swift Charts — now true.** The hand-rolled `MonthlyBars`
  misplaced its own baseline (BUG-011).
- **§4 rejections surface as human-readable reasons — now reachable.** They
  are presented at `RootView`, and every sheet additionally pre-checks through
  `Command.validate`, which is what turns a rejection into a disabled control
  with a reason instead of an alert nobody sees.
- **§5 O(visible), not O(world) — now honoured.** `GameController` caches the
  map model and the route/fleet cards per simulation tick; screens previously
  rebuilt them inside `body`, four times a second.
- **§5 Reduce Motion honoured centrally — now explicit.** `aeAnimation`
  consults `accessibilityReduceMotion` rather than relying on SwiftUI's
  defaults.
- **§6 every number tappable to its explanation — now true on the
  dashboard.** Fleet, Routes, Reputation, Last month and Economy each open the
  screen that explains them.
- **Presentation vocabulary.** `Vocabulary.swift` is the single place model
  enums and progression codes become English. No screen calls
  `String(describing:)` or `rawValue` on a model type.

- **Formatting is locale-correct.** Every number goes through `FormatStyle`.
  It previously went through `String(format: "%.1f")`, which prints `3.5` to a
  reader who writes `3,5` — a defect for a French or German player in an
  English app, and unrelated to translating anything. The `¤` sign and the ISO
  game date stay fixed deliberately; `Format` says why.

**Still not built:** a bound `NavigationPath` for external deep links;
localization of the strings themselves.

The visual contract moved to its own document in AE-028 —
`docs/DESIGN_SYSTEM.md` — which records the type scale, the container ladder
(card / panel / nothing), the button roles, and the rule that derived numbers
live in Core rather than in view bodies.

Audio and haptics *are* built — see §9. Feedback is centralized through
`Feedback.emit` rather than inline `sensoryFeedback`, so a screen cannot bypass
the player's haptics setting by forgetting to check it (BUG-014). What remains
is validation, not architecture: nothing in this system has been heard or felt
on a device (`tasks/TECH_DEBT.md` TD-006).


---

## 9. Feedback (AE-AUDIO-01, 2026-08-29)

The client gained a fourth output alongside layout, colour and motion: **sound
and haptics**. Two rules bind it to the rest of this document.

**Views express intent, never mechanism.** A view says
`feedback.play(.routeOpened)`. It never names a file, a volume, a duration, or
whether the cue is also a haptic. This is the same seam as
`Format`/`Vocab`/`AETheme`: the screen states *what*, the design system decides
*how*.

**The decisions live in Core.** Which sounds a moment deserves, how a busy
quarter-second is thinned, what the world bed does at each zoom, which music
state the airline is in, and which settings switch wins are all pure policy in
`AudioDirection.swift`, `SoundscapeDirection.swift` and `AudioSettings.swift`.
The app layer is the hands. That placement is what makes 50 tests possible on
a machine with no speaker, and it is the same reasoning that put `MapModel` in
Core rather than in the renderer.

`docs/AUDIO_ARCHITECTURE.md` is the full account.

### Consequences for anything new

- A new screen gets press feedback for free: use `.buttonStyle(.aePress)`
  rather than `.plain`, which on iOS gives no press state at all.
- A new action that emits a `SimEvent` needs no view-side cue — the director
  voices it. An action that emits *no* event (there are three:
  fare, frequency, service tier) must confirm at the call site.
- `.sensoryFeedback` is not used anywhere and should not be reintroduced: it
  bypasses the player's haptics setting, which is how that setting came to be
  dead on five of seven screens (BUG-014).
- An empty state that instructs the player should carry the action —
  `EmptyStateView` takes one.

---

## 10. Read models own the rules (AE-029, 2026-08-30)

The App/Core seam described in §1 has one failure mode that has now produced
four defects, and it is worth stating as a rule rather than rediscovering.

**A screen that re-derives a rule Core owns will get it wrong, and quietly.**

| Defect | What a screen re-derived | How it was wrong |
| --- | --- | --- |
| BUG-027 | live flight count | counted every airline, every phase |
| AE-028 §9 | fleet average age | included aircraft still on order |
| BUG-032 | assignment eligibility | no range check, no runway check, hid maintenance |
| BUG-033 | refusal codes | switched on three strings Core never emits |

None crashed. None warned. None failed a test, because no test existed on the
seam. Each produced a game that disagreed with itself somewhere a player would
eventually look.

The pattern in all four is the same: **the app held a plausible-looking subset
of a rule that lives elsewhere.** A subset compiles. A subset runs. A subset is
right most of the time, which is what makes it survive review.

So the rule for anything derived:

1. **It lives in Core**, next to the authority it mirrors — the validator, the
   entity, the system. Not in a view, not in the controller.
2. **A test pins it to that authority.** Not a test that it returns sensible
   values; a test that it and the thing it mirrors reach the same verdict.
   `AssignmentEligibilityTests.blockersAgreeWithTheValidator` is the model:
   every aircraft against every route, model verdict against validator verdict.
3. **`Vocab` chooses the words, and only the words.** Phrasing can be rewritten
   without anyone re-deriving what causes what.
4. **The screen formats.** If a view body contains a comparison against a
   threshold, that threshold belongs in Core.

Established read models on this seam: `NetworkSummary`, `FleetSummary`,
`RouteVerdict`, `MapModel`, `AssignmentCandidate`, `FleetFilter`,
`AircraftRole`, `SeatEfficiencyBand`.

**The gap this leaves.** These tests pin *Core's* half. The app's half — that a
mapped code is a code Core emits, that a `NavigationLink(value:)` resolves,
that `Vocab` is total over the enum it words — is guarded by review alone,
because the App target has no test that runs anywhere we build. That is
`TD-016`, and it is the common cause behind BUG-029, BUG-030 and BUG-033.
