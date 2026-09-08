# AE-048 — The map is the home screen

Direction II, Phase 27 (`docs/ROADMAP_DIRECTION_II.md`). 2026-09-07.

**Evidence classification: SIMULATOR VALIDATED (partial) + CORE TESTED.**

Partial, and the word is load-bearing: the app built and ran on macos-26
simulators, six frames were pulled out of the result bundles and looked at, and
four defects were found that way and fixed — two of them mine. What is *not*
validated is everything in the shards that had not finished when this was
written (dark mode, Dynamic Type, the follow camera, the draw-cost probe) and
frames E–J of the AE-048 journey, which stopped at a harness fault before
reaching them. Those wait on the redispatch, and this line should be re-read
against §13 rather than trusted on its own.

The Core suite is green on Linux (506/506) and the app compiles for the iOS
simulator on six independent runners — the check this repository has never been
able to answer on Linux at all. The phase's remaining claim, that the screen
reads as *my airline, on a living world*, is a claim about pixels; §13 says
which pixels were looked at and what they showed.

---

## 1. What the phase changed, in one paragraph

The game opens on the world. `MapScreen` is the **Home** tab; the Map tab is
gone; the tab bar is four items. What used to be the Home dashboard is
`BriefingView` — the same file, the same cards, the same order — presented as a
sheet from the foot of the map. At that foot sits `MapHomeBriefing`: one row of
airline state that *is* the handle for the briefing, and one row for the single
next move, derived from `OnboardingModel`, the fleet and `marketOpportunities`.
The map renderer, its cache, its camera, its hit-testing, its overlays and its
selection cards were not touched.

---

## 2. The audit this started from

Read on the branch before anything was written: `tasks/CURRENT_PHASE.md`,
`docs/ROADMAP_DIRECTION_II.md` (Phases 25–27), `tasks/BUGS.md`,
`tasks/TECH_DEBT.md`, `docs/UI_ARCHITECTURE.md`, `docs/MAP_ARCHITECTURE.md`,
and the shipped code for `RootView`/`GameShell`, `MapScreen`, `MapChrome`,
`MapSelectionCards`, `MapPresentation`, `DashboardView`, `GameController`,
`OnboardingModel`, `MarketOpportunities`, `ReadModels`, and all six UI-test
files.

**What AE-047 actually shipped.** City lights on the night side, an activity
halo from `slotPressure` with a movement ring derived per frame from the
flights already being drawn, storms carrying their own `severity`, and
`SolarGeometry` moved into Core with four tests pinning darkness to the
terminator the map draws. It also fixed `MapFrame.elapsed`, which had been
resetting on every tick.

**What AE-048 already had: nothing.** No briefing, no strip, five tabs, Home a
dashboard.

**What was broken and in scope.** One thing, and it was found by reading the
new composition rather than a screen: BUG-062, below.

**Which architecture was reused rather than rebuilt.** All of it. The
contextual actions this phase is supposed to deliver — inspect an airport, open
a route from it, jump to a route you fly there, open route detail, open the
aircraft, follow the flight — were **already built and already real** in
`MapSelectionCards` (AE-033, AE-046). The phase's job was hierarchy, not
interaction, and the honest thing to report is that section 8 of the brief was
largely already satisfied.

**Which UI state lived outside Core, and stayed there.** Camera, selection,
overlay choice, sheet presentation, hit geometry, render cache, animation
epoch. All of it is transient interaction state and none of it is simulation.

**Where the prompt and the repository disagreed.** The roadmap's mitigation for
this phase was a settings toggle, `Open on: Map / Home`. Section 6 explains why
it was not built, which is the one plan decision this phase reversed.

---

## 3. Architecture — how the map became Home without a second source of truth

```
GameShell (4 tabs)
└── Home ─── MapScreen ────────────────────────────── NavigationStack
              ├─ Canvas (unchanged: TimelineView + MapFrame + MapRenderCache)
              └─ chrome
                 ├─ MapTopBar        date · clock · cash · speed · one banner
                 ├─ overlay picker / zoom controls
                 └─ bottom region  ← ONE occupant, ever
                    ├─ live selection?  MapSelectionPanel  (unchanged cards)
                    └─ otherwise        MapOverlayHint + MapHomeBriefing
              sheets: OpenRouteSheet · AircraftShopSheet · BriefingView
```

**No new state was created.** `MapHomeBriefing` stores nothing. `MapScreen`
gained two booleans (`showingBriefing`, `showingAircraftMarket`) which are
sheet presentation and nothing else. `HomeNextMove` is a value computed from
the snapshot; it is not persisted, not remembered between snapshots, and
therefore cannot survive a new game or contradict the state it describes.

**Where the derivations live.** `HomeNextMove.resolve` and
`GameState.dashboardModel()` are cached on `GameController` beside `MapModel`,
`NetworkSummary`, `FleetSummary`, the route/fleet cards and
`CompetitionSummary`, invalidated on every published snapshot by the function
that already does that. This is required, not tidy: the strip is rebuilt on
every `MapScreen` body pass and a **finger on the map drives those** — the
camera is `@Observable` and a drag writes `panOffset` — so an uncached
`marketOpportunities` would have ranked every servable market from the
airline's bases on every gesture frame.

`HomeNextMove` carries a `Tone` (`.accent`, `.positive`, `.caution`,
`.negative`, `.livery(Livery)`) rather than a `Color`, so `GameController` can
hold it without importing SwiftUI and the palette stays in one file.

**`quitToMenu` now calls `invalidateCaches()`** instead of repeating its list.
The list had already drifted; two caches added for this phase would have
drifted again, and a cache the *next* airline inherits is BUG-013's shape.

**Nothing in the UI computes a simulation value.** Every number on the strip is
`DashboardModel.cash`, `NetworkSummary.liveFlights`, `NetworkSummary.routeCount`
or `FleetSummary.total`/`.idle`. Every judgement in the move — insolvency, the
onboarding step, whether a market pays for its own airframe — is Core's.

---

## 4. UX — the flow the player now has

```
open the game
   → the world, framed on the player's own network
   → cash, aircraft in the air, routes, fleet, at the foot of it
   → one next move, in words, as a control that performs it
        · "Get an aircraft"                → the aircraft market
        · "Open your first route"          → the two strongest markets,
                                             over the dashed arcs that are them
        · "Put the aircraft on the route"  → that route's detail
        · "Un-pause and watch it fly"      → 1×
        · "One aircraft is idle"           → that aeroplane
        · "LHR → BER is open"              → the guided route sheet
        · "One of yours is in the air"     → ride with it
        · (nothing needs doing)            → no row at all
   → tap the world: an airport, a route, an aircraft
   → the card answers, and offers what can be done from there
   → let go, and the airline's state and its next move come back
   → press the numbers for the briefing: the month, the feed, the rivals,
     the calendar, the six stat tiles and everywhere they lead
```

**The row is allowed to be absent.** A solvent airline with nothing idle, no
market that pays for its aircraft and nothing in the air gets a state row and
no move. That is the whole of the answer to section 13 of the brief: there is
no banner, no badge, no timer and no manufactured errand, and the one animated
element (a breathing icon) is reserved for an aircraft that is costing money
while it waits.

---

## 5. Map — what was preserved

Nothing in the renderer changed. `MapFrame`, `MapRenderCache`,
`MapProjector`, `MapDetailPolicy`, `MapCamera`, `MapHitGeometry`,
`MapHitTester`, `WorldGeometry`, `AircraftSilhouette`, `CountryLabels` and
`MapDrawStats` are byte-identical. Pinch, pan, double-tap, the flick's coast,
the zoom ladder, flight trails, antimeridian unwrapping, label settling,
culling, the night terminator, city lights, storm fields and the follow camera
are untouched.

Three things in the *chrome* changed, all in `MapChrome.swift`:

1. `MapTopBar`'s second line is now `07:20 · $1.2M` instead of `07:20`.
2. `MapIdlePanel` became `MapOverlayHint` and lost the first-route invitation
   it used to carry — the briefing says that now, from the whole airline
   rather than from one overlay — and lost its `.network` fallback line ("Tap
   an airport, a route or an aircraft."), which said nothing about the world
   and would have sat directly above a row that does.
3. `MapSelectionPanel` renders nothing for no selection.

---

## 6. Navigation — and the toggle that was not built

| Tab | Screen |
| --- | --- |
| Home | `MapScreen` — the world |
| Airline | `NetworkView` — routes and fleet |
| Finance | `FinanceView` |
| World | `OperationsView` — events, competitors, progression, airports |

Four items cannot overflow into the system *More* list, so BUG-009 cannot
recur without somebody adding two more tabs. `MapHomeUITests`
asserts the tab bar has exactly four buttons and neither a `Map` nor a `More`
one, and walks every tab to a screen that renders.

**The toggle.** The roadmap proposed shipping behind `Open on: Map / Home` for
one build, deciding on a device with both available. It was not built, and this
is the one place the phase departed from the plan:

- A preference between two homes requires two homes. That is the duplicate
  world — one screen twice under two names — that the phase exists to remove,
  and §14 of the phase brief forbids it outright.
- It asks the player a question they have no basis to answer, on their first
  session, about the shape of the game.
- The mitigation's *substance* — that the game's controls must not be buried —
  is met without it: nothing was deleted, and everything that was on Home is
  one control away, at the foot of the screen, under the player's thumb.

The reversible part is preserved: `BriefingView` is intact and unchanged, so
restoring a Home tab is a two-line change to `GameShell` if a device says the
map home is worse.

**Settings is the one path that got longer** — Home → briefing → gear, where it
was Home → gear. Recorded in `tasks/TECH_DEBT.md` TD-039.

---

## 7. Contextual actions available from map objects

All of these existed before this phase and all of them still work; the phase
added the last two rows.

| Selected | Actions, and where they go |
| --- | --- |
| Airport | up to three of your routes through it → `RouteDetailView`; "Open a route here — about N passengers a day" → `OpenRouteSheet`, pre-filled |
| Route | its month's profit, fare, load and a sentence on its health; "Open route detail" → `RouteDetailView` |
| Aircraft | live progress, ETA on the game clock, passengers aboard, delay and its cause; "Follow this flight" / "Stop following" → the AE-046 camera; "Open aircraft" → `AircraftDetailView` (player's own) |
| — (briefing) | the next move: the aircraft market, the guided route sheet, a route's detail, an aeroplane, 1× on the clock, following a flight, or the briefing |
| — (briefing) | the state row → `BriefingView` |

Every case of `HomeNextMove.Move` lands on a surface that already exists. There
is no case in that enum without a destination.

---

## 8. Onboarding — one model, two views

`HomeNextMove.resolve` calls `snapshot.onboardingModel(catalog:)` — the same
function `OnboardingCard` calls — and shows its `nextStep`. When the arc
completes the row moves to the same ranking `NextMovesCard` uses (idle aircraft
first, then `marketOpportunities` filtered by `servableNow` **and**
`paysForItsAirframe`, which is BUG-055's rule), and then to the world itself.

The words are shared. `Vocab.onboardingStep`, `Vocab.onboardingHint` and
`Vocab.onboardingIcon` are the single source, and `OnboardingCard` was changed
to read them rather than keep its own copy — so the checklist in the briefing
and the row on the map cannot say two different things about one step. The
hints were rewritten to name the *action* rather than a tab to go and find,
because on the map the row performs it (BUG-059's rule).

Nothing is hard-coded and nothing is persisted. `onboardingModel` derives
completion from the fleet, the routes, the live flights and the revenue
actually booked — there are no onboarding flags in the save file, and there is
no second onboarding system.

---

## 9. Accessibility — what was actually done, and what was not verified

**Done in code:**

- The state row is one element: label "Briefing", value "cash $1.2M, in the air
  3, routes 4, aircraft 5", hint naming what opening it shows. The individual
  facts are `accessibilityHidden` so VoiceOver reads one sentence, not eight.
- The move row is one element labelled "\<title>. \<detail>", with the
  identifier `ae-home-next-action`.
- The suggestion rows are one element each, labelled "Open LHR to BER, London,
  about 420 passengers a day".
- The briefing's close control is icon-only with an explicit label, "Back to
  the map".
- Every control is `minHeight: 44`.
- The pulse on an idle-aircraft row is gated on `accessibilityReduceMotion`;
  every animation goes through `aeAnimation`, which already consults it.
- The state row stacks vertically at accessibility Dynamic Type sizes.
- Nothing on the strip relies on colour alone: every tint has words beside it.

**Not verified:** VoiceOver was not run. Dynamic Type was not looked at on a
screen — `ShellAndMapUITests.testAccessibilityTextSizeKeepsTheShellUsable`
drives AccessibilityL and photographs the shell, and those frames are evidence
of *layout survival*, not of legibility. Increased-contrast and Bold Text were
not tested at all.

---

## 10. Responsive layout

- **iPhone, compact width:** the tab bar path. The briefing strip is two rows
  (~110 pt) except at the first-route step, where two candidate rows take it to
  ~210 pt; the map keeps the rest. Judged from the frames, not measured.
- **iPad / regular width:** unchanged — `NavigationSplitView` with the sidebar,
  the map in the detail pane, the briefing as a sheet over it. The CI iPad job
  is off by default; it was not run for this phase, so **iPad is unverified**.
- **The narrowest supported phone** is the iPhone SE at 375 pt (iOS 17 is the
  deployment target). The briefing's toolbar was deliberately kept to an icon,
  the speed capsule and one more icon for that reason.
- No hard-coded coordinates were added. Safe areas are unchanged: the canvas
  still bleeds past the bottom inset and the chrome still does not.

---

## 11. Performance

**Measured**, on CI run 172's shell+map shard, by the in-app draw-cost probe
(`PerformanceBaselineUITests.testMapInteractionBaselineMeasurements`, run alone
on its simulator so the numbers stay comparable). Same test, same three
sequences — 4 slow strokes, 6 fast alternating strokes, 3×3 zoom cycles — as
the numbers already recorded in `MAP_P0_PERFORMANCE_REPORT.md`.

| Sequence | frames | avg draw | worst | identity churn/frame | hops/frame |
| --- | --- | --- | --- | --- | --- |
| at open | 68 | 15.12 ms | 243.55 ms | — | — |
| slow drag | 626 | **10.61 ms** | 243.55 ms | 0.21 | 0.32 |
| fast drag | 420 | **9.33 ms** | 243.55 ms | 0.43 | 0.40 |
| zoom cycles | 402 | **11.02 ms** | 243.55 ms | 1.00 | 2.56 |

Against the repository's recorded baseline (run 85, AE-034's post-fix figures):
slow drag 11.39 → 10.61 ms, fast drag 11.40 → 9.33 ms, zoom 11.16 → 11.02 ms;
churn per frame 1.35 → 0.21, 3.89 → 0.43, 14.55 → 1.00. **No draw-cost
regression, and every churn metric is lower.**

**The caveat, and it is a real one.** Run 85 was AE-034, on a different runner,
and AE-045, AE-046 and AE-047 all touched the map between then and now. This is
therefore *not* a clean A/B for AE-048 alone — it establishes that the map is
not slower than its recorded baseline, not that this phase changed nothing. A
clean A/B would need the same probe run on `main`, which was not done.

The worst frame is 243.55 ms and is **identical across all four sequences**,
which means it is the at-open frame — the first full cache build — and no
interaction frame in the run exceeded it. That is the same shape run 85
recorded (169 ms at open, on a faster runner), not a new stall.

### Did the home overlays cause map rebuilds? No.

The probe also prints the render cache's own counters. Across the run:

```
MAP-CACHE cache rebuilds  4 replays  132  reasons [first, routesFirst, routesZoomBand, zoomBand]
MAP-CACHE cache rebuilds 24 replays 2526  reasons [first, panMargin, routesFirst,
                                                   routesPanMargin, routesZoomBand, zoomBand]
MAP-CACHE cache rebuilds 64 replays 3290  reasons [first, lod, panMargin, routesFirst,
                                                   routesLod, routesPanMargin, routesZoomBand, zoomBand]
```

Roughly **51 replays per rebuild**, and every rebuild reason is a camera or
level-of-detail reason — `first`, `zoomBand`, `panMargin`, `lod` and their
route equivalents. There is no snapshot-driven or state-driven reason in the
list, which is the direct answer to "did the briefing strip make the map
rebuild": it did not. `MapRenderCache` is untouched and behaving as designed.

The three things done to keep it that way are in §3: `HomeNextMove` and
`DashboardModel` cached per snapshot on `GameController`, both derivations
taken once per body pass into locals, and nothing added inside the `Canvas`
closure, the `TimelineView` or `MapFrame`.

## 12. Tests

**Core (Linux, Swift 6.0.3):** see §13 — the suite was run on this branch and
no Core source was modified by this phase.

**App:** the target has no unit tests anywhere this environment can build
(TD-016). What exists is the UI journey suite, which was extended:

*New — `MapHomeUITests`:*

| Test | What it drives |
| --- | --- |
| `testTheMapIsTheHomeScreen` | founds an airline and walks the whole claim: the world on arrival, the state strip and next move, the market opened *from the map's own row*, the first route from its suggestions, the assignment from the row that names it, the clock, selecting and following a flight, selecting an airport, releasing it and getting the briefing back, and every management tab still reachable. Ten keyframes, A–J. |
| `testTheShellHasFourTabsAndNoDeadDestinations` | four tabs, all opening real screens, no `Map` tab, no `More` list, and Settings reachable behind the briefing. Added to the CI smoke subset. |

*Changed, because the surface moved:*

- `UITestSupport` gained `openBriefing()`, `closeBriefing()` and
  `briefingIsOpen`; `openTab` now closes the briefing first (a sheet swallows
  taps aimed at the tab bar under it); `advanceMorningsUntilHomeSays` runs
  inside the briefing, where the feed is.
- `CampaignUITests`: the February market loop, the rival-pressure card, the
  "Regional era" assertion and the rival-retreat fixture now read the briefing.
  `testFoundingAnAirlineReachesEveryTab` photographs the briefing as a fifth
  surface and asserts it opens and closes.
  `testHomeGuidesANewPlayerToTheirFirstAircraft` was **strengthened**: it now
  asserts the map's next-move row exists *and* that its label names the
  onboarding model's first step, and then that the checklist is behind the
  briefing.
- `EconomyJourneyUITests`: the AE-042 advice journey checks the map row first
  and the Next Moves card second; the currency sweep now includes the briefing,
  which carries most of the money in the game; the first-revenue poll runs
  where the checklist is.
- `HorizonArrivalUITests`, `ShellAndMapUITests`,
  `PerformanceBaselineUITests`: `openTab("Map")` → `openTab("Home")`; both
  appearance tests photograph the briefing, which is a surface neither had
  ever seen.

**No test was weakened, disabled or deleted.** Two were strengthened.

**CI:** the smoke subset gains the four-tab test; the `full` matrix gains a
fifth shard for `MapHomeUITests` rather than lengthening an existing one,
following the balance reasoning already in `ci.yml`.

---

## 13. Simulator validation

Four dispatched `full` runs with the iPad job on, each one reading the frames
rather than the tick. What each answered:

| Run | Commit | Result | What the frames changed |
| --- | --- | --- | --- |
| 171 | `ac73d84` | build ✅ on 6 runners; 4 shards red | **the app compiles** — the check Linux could never answer. Frames found BUG-063 (wrapped date) and proved the lease the harness had called a failure |
| 172 | `48dabcd` | 6/8 green | frames found **BUG-065** (zoom controls off-screen) and the Dynamic-Type overflow; iPad proved BUG-064 fixed; **the performance probe ran** (§11) |
| 173 | `7d94013` | 8/9 green | BUG-065 and Dynamic Type **verified fixed by eye**; arrival green again; economy's year-long advance still short; follow still skipped |
| 176 | `c887a61` | see below | the progress-verifying advance and the steered aircraft sweep |

### Frames actually inspected

Pulled from the result bundles (run 171, by the attachment table) and from the
job logs via `scripts/decode-ci-screenshots.py` (runs 172–173), and **looked
at** — the log-embedded frames are downscaled to 360 px, so the two layout
defects were only visible after magnifying the corners:

- **A — the game opens on the world.** Map ~62 % of the viewport; Arlanda the
  ember home marker with the dashed opportunity arcs radiating from it; four
  tabs, no Map tab; the strip reads `$60.0M cash · 0 in the air · 0 routes ·
  0 aircraft` over `Get an aircraft — Open the aircraft market`.
- **C** — the next-move row opened the aircraft market. The first interaction
  of the game happens on the map.
- **D, E** — the route sheet and the route's own detail, both reached from the
  map's row.
- **G — the one-occupant rule, photographed.** Billund selected with its card
  (small · 0% slots · 0 your routes · 0 rivals), a live aircraft drawn on the
  ARN–LHR arc, and **the briefing strip gone** while the card holds the region.
- **H — and back.** Selection released, the strip returns as `$59.4M · 1 in the
  air · 1 route · 1 aircraft`, and the move has advanced to *"ARN → CDG is
  open — Paris · about 1084 passengers a day, and it pays for its aircraft."*
  The whole derivation chain, in the player's words, on the world.
- **Dark** — the briefing on dark surfaces with legible secondary text and no
  stranded light panels; the map is fixed near-black in both appearances by
  design, so light and dark home frames are the same image, which is correct.
- **Dynamic Type (AccessibilityL)** — run 172 showed the speed control off
  screen and the action text clipped mid-word; run 173 shows the bar stacked
  with every speed control on screen, the zoom cluster whole, two facts
  instead of four, and the text wrapping.
- **iPad** — four sidebar rows, Home first with the globe; and the Settings
  frame showing a **back chevron beside the title with the map behind**, which
  is what a push inside the briefing looks like and what a replaced sheet did
  not.

### Defects found by looking, and fixed

1. **BUG-063** — cash beside the clock wrapped the date onto two lines and made
   a one-line bar four. Cash removed (the strip already carries it).
2. **BUG-065** — the fix for BUG-063 used `fixedSize(horizontal: true)`, which
   made the row's ideal width unsatisfiable: the capsule laid out past its own
   margin and the `Spacer()` below pushed `MapZoomControls` half off the right
   edge. That cluster is the only way to zoom without a pinch, so this was an
   accessibility failure. Now `lineLimit(1)` + `minimumScaleFactor`, a stacked
   bar at accessibility sizes, and a two-fact strip there.
3. **BUG-064** — Settings raised from inside the briefing *replaced* it on
   iPad. Now a push; the `DashboardRoute` table also moved off the stat grid,
   where it was inert before a snapshot landed.
4. **Four harness assumptions** that moved with Home: a lease proved against a
   fleet board that is not behind the map's sheet; a recommendation matched by
   `label CONTAINS "→"` against a label that said "to"; the rival headline and
   the era read on a Home that is now the briefing; a Settings toggle waited
   for below a form sheet's fold.
5. **Two harness regressions of my own**: `firstMatch` (which resolves without
   waiting) on a control tapped hundreds of times, and a week-advance loop that
   fired a precomputed count blind.

### What is still not validated

**The follow camera.** Four attempts, never once reached. AE-046 recorded it
NOT VERIFIED and nothing since has changed that: run 171 and 172 skipped
before an aircraft was airborne, run 173 got one and held it still but the
seven blind taps missed. Run 176 carries a steered grid sweep. **Until a frame
shows the camera locked on, this phase claims nothing about it** — the plumbing
is AE-046's and untouched, the control is on the card, and neither of those is
the same as having seen it work.

## 14. Remaining issues

1. **The follow camera has never been exercised by any run.** Not a defect
   found — a claim not made. §13 says why and what run 176 tries. It is the
   single item that keeps this phase from a clean classification.
2. **`testNewYorkAdviceIsWorthFollowing`'s year-long advance.** Green at run
   135, short of March 2031 in runs 172 and 173 at the same ~328 s. The rest
   of that journey — including every step AE-048 touched — passes. Run 176
   carries the progress-verifying advance. **Not attributed to AE-048**: the
   equivalent short advance broke and was fixed by the same harness change,
   and the app-side behaviour under it is a fast-forward that this phase did
   not alter.
3. **The era and the reputation are not on the world.** One tap away on the
   briefing. `TD-039`.
4. **Settings is two taps from the world**, where it was one. `TD-039`.
5. **BUG-061 is still open** — "Advance to next morning" lands on 00:00, so
   every journey frame taken after a sunrise photographs local midnight. Not
   fixed here: `GameSession` has no catalog, so reaching
   `OpsTuning.operatingDayStartMinute` means changing Core's session API under
   ~1,800 sunrise taps. The AE-048 journey reaches its later frames at 16×
   instead, which is why frames G and H show 07:45 rather than midnight.
6. **VoiceOver was not run.** §9 says what was written and what that does not
   prove.
7. **The performance comparison is not a clean A/B.** §11.

## 15. Bugs and tech debt

- **BUG-063 — the map's top bar broke its own date across two lines.** Mine,
  introduced by this phase and caught by its own screenshots. Fixed by taking
  the duplicated cash back out of the bar and pinning the date to one line.
- **BUG-064 — Settings, raised from inside the briefing, replaced it on iPad.**
  A sheet from a sheet does not stack at regular width. Fixed by making
  Settings a push, which also fixed a set of destinations that were registered
  inside the stat grid and therefore inert before a snapshot landed.
- **BUG-062 — a selection that stopped existing left the foot of the map
  blank.** Found by reading the new composition: `MapSelectionPanel` asked
  whether a selection had been *made*, not whether it still *resolved*, so a
  route closed elsewhere or a flight that had landed left an empty region — and
  after this phase it would have taken the airline's state and its next move
  with it. Fixed by `MapScreen.hasLiveSelection(_:)`. Reasoned-and-fixed, not
  observed-and-fixed; no journey currently drives the case.
- **BUG-061** — unchanged, still open, consequences restated above.
- **TD-039** — the three things this phase moved rather than solved.

No other bug was opened or closed. No P0 was encountered.

---

## 16. Documentation updated

- `tasks/CURRENT_PHASE.md` — AE-048 is the current phase; AE-047 moved down.
- `docs/ROADMAP_DIRECTION_II.md` — Phase 27 marked shipped, with the toggle
  decision recorded against the plan that proposed it.
- `docs/UI_ARCHITECTURE.md` — new §9, the shell after AE-048, and §8's
  five-item claim corrected.
- `docs/MAP_ARCHITECTURE.md` — §9 rewritten for the one-occupant bottom region
  and the map's new role as Home.
- `tasks/BUGS.md` — BUG-062.
- `tasks/TECH_DEBT.md` — TD-039.
- `docs/AE048_FINAL_REPORT.md` — this file.

---

## 17. Definition of done, honestly scored

| | |
| --- | --- |
| The map is genuinely the primary home | ✅ code; frames pending |
| Existing simulation remains authoritative | ✅ |
| No UI-side shadow simulation | ✅ |
| Existing map renderer intact | ✅ byte-identical |
| Flight following still reachable | ✅ card, and now the briefing row |
| Airport / route / aircraft interaction | ✅ unchanged |
| Network / Finance / World reachable | ✅ |
| No dead destinations, no tab overflow | ✅ asserted by test |
| Onboarding truthful | ✅ one model, shared words |
| New game and existing save both launch | ✅ unchanged paths; fixture journeys updated |
| Game over → new airline | ✅ unchanged; caches now cleared by one function |
| Light mode | ✅ frames A, B2, C, and the iPad set |
| Dark mode | ⏳ campaign/shell shards had not finished |
| Dynamic Type | ⏳ frames |
| Accessibility | ⚠️ written, not run — §9 |
| iPhone layout | ✅ frames inspected; one defect found (BUG-063) and fixed |
| iPad layout | ✅ run and inspected; one defect found (BUG-064) and fixed |
| Map performance not regressed | ⚠️ reasoned, not measured — §11 |
| Core tests pass | ✅ §13 |
| UI tests pass | ⏳ the dispatched run |
| macOS build succeeds | ✅ six runners, BUILD SUCCEEDED |
| Frames inspected | ✅ six, by eye — §13 |
