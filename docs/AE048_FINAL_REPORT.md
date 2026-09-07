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

**No measurement was taken, and none is claimed.** `ae-map-bench` measures the
map model's build cost, which this phase did not touch, and
`PerformanceBaselineUITests` measures draw cost and label churn on a simulator
this environment cannot boot. The CI run that carries the `measure` flag is
shard 3; its numbers are the before/after this section should eventually hold.

What was done instead is to remove the cost the composition would otherwise
have introduced, by reasoning about where it would land:

- `HomeNextMove.resolve` and `dashboardModel()` are cached per published
  snapshot on `GameController`. Without that they would run on **every
  `MapScreen` body pass**, which a drag drives — `MapHomeBriefing` holds
  closures, so SwiftUI cannot treat it as unchanged and its `body` re-runs
  whenever the parent's does.
- `MapTopBar` computes its cash line once per pass rather than twice (once for
  the text and once for the animation key).
- `MapHomeBriefing.body` takes both derivations once into locals rather than
  referring to computed properties from three places.
- Nothing was added inside the `Canvas` closure, the `TimelineView`, or
  `MapFrame`. `MapRenderCache` is untouched, and the render path has no new
  dependency on home-screen state.

---

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

**Workflow:** `.github/workflows/ci.yml`, dispatched `suite: full, ipad: true`.
**Run:** 171 — `34092672265`, on `ac73d84`.
**Runners:** macos-26; iPhone simulator picked by the workflow (a plain
iPhone, preferred over Pro/Max), plus an iPad simulator at regular width.

### What was answered

| Job | Result |
| --- | --- |
| Core (Linux, swift test) | see §12 — 506/506 locally on this branch |
| Release tooling, store listing, bundle, app symbols, audio assets | ✅ all green |
| **`xcodebuild build-for-testing`, all six macOS jobs** | ✅ **BUILD SUCCEEDED** |
| map home shard | `testTheShellHasFourTabsAndNoDeadDestinations` ✅ 46 s; `testTheMapIsTheHomeScreen` ❌ (harness, see below) |
| economy shard | 3 ✅ / 2 ❌ (one launch timeout, one the arrow defect) |
| arrival shard | ❌ 1 (the rival headline moved into the briefing) |
| iPad shell | `testFoundingAnAirlineReachesEveryTab` ✅ 168 s; `testDetailScreensAndSettingsRender` ❌ (below the fold) |
| campaign, shell + map | still running when this was written; not claimed |

**The app compiles.** That is the check this repository has never been able to
answer on Linux, and it answered yes with every change of this phase in it, on
six independent runners.

### Frames inspected

Pulled out of the `.xcresult` bundles by name (the attachment table maps names
to payloads) and **looked at**:

- `KEY-AE048-A-map-home-on-arrival` — the game opens on the world. The map is
  ~62 % of the viewport; Arlanda is the ember home marker with the dashed
  opportunity arcs radiating from it; four tabs (Home ·globe·, Airline,
  Finance, World) and no Map tab; the briefing strip reads
  **"$60.0M cash · 0 in the air · 0 routes · 0 aircraft"** over
  **"Get an aircraft — Open the aircraft market — leasing keeps cash free early
  on."** Layers 1, 2 and 4 of the brief, in one frame.
- `KEY-AE048-B2-briefing-over-the-world` — the briefing sheet, light mode. The
  close chevron, the speed capsule and the gear all fit the bar; the header,
  the five-step checklist, the pulse strip, all six stat tiles and the
  operations feed are present and correctly laid out. Nothing was lost.
- `KEY-AE048-C-market-opened-from-the-map` — pressing the next-move row opened
  the aircraft market. The first interaction of the game happens on the map.
- `KEY-LEASE-ATTEMPT-1` — see below. It is the frame that settled the phase's
  most important question and the test's own diagnosis at once.
- iPad `90-aircraft-detail`, `91-route-detail`, `92-settings` — the sidebar
  carries exactly four rows, Home first with the globe; Settings renders.

### Defects found by looking, and fixed

1. **The top bar wrapped the date onto two lines.** Mine, introduced by this
   phase: putting the cash beside the clock widened that column past what the
   capsule had spare, so `2030-01-01` broke as "2030-" / "01-01" and the bar
   went from one line to four. Both frames A and the lease frame show it.
   **Fixed** by taking the cash back out — it is already on the briefing strip,
   bigger and labelled, so this was a second copy that cost a wrapped date —
   and by pinning the date to one line so nothing can wrap it again.
2. **`leaseAnAircraft` reported a failure over a success.** The helper proves a
   lease by waiting for the market to close *and* for a row on the fleet board
   behind it. Opened from the map there is no fleet board behind it. The frame
   it saved as `LEASE-ATTEMPT-1` shows cash $60.0M → $59.2M, **1 aircraft** on
   the strip, and the next move already advanced to "Open your first route"
   with ARN → LHR (≈1,117/day) and ARN → CDG (≈987/day) offered over the arcs
   that are them. The product did exactly what the phase claims; the harness
   asked the wrong surface. **Fixed** with a `LeaseProof` the caller chooses;
   the map's proof reads the fleet count out of the briefing strip's
   accessibility value, which is `FleetSummary` read back.
3. **Settings, raised from inside the briefing, replaced it on iPad.** The
   frame shows the Settings form sheet over the *map*, with the briefing gone —
   a sheet from a sheet does not stack at regular width. **Fixed** by making
   Settings a push inside the briefing's own navigation stack, which keeps one
   modal level and returns the player to the briefing rather than to the map.
   The destination table moved out of the stat grid at the same time, because
   registered there it was inert whenever the briefing had no snapshot yet —
   BUG-029's family.
4. **The iPad Settings assertion waited for a control below the fold.** The
   frame shows Settings rendered correctly with "Mute everything" just past the
   bottom edge of the form sheet. **Fixed** by scrolling to it, which is the
   stronger claim: it proves the list scrolls as well as that it drew.
5. **Two surfaces I had missed when moving Home.** `testNewYorkAdviceIsWorth-
   Following` looked for the recommendation by `label CONTAINS "→"` and my
   hand-written accessibility label said "ARN to LHR" — the advice was on
   screen and unfindable. `HorizonArrivalUITests` read the rival-entry headline
   on Home, which is now in the briefing. Both **fixed**; the first was caught
   by reading the code before CI reached it, the second by CI.

### Not caused by this phase

`testAcquireAircraftThenOpenARoute` died on "Timed out while launching
application via Xcode" — the runner never got the app up. That is TD-037's
class and is recorded, not fixed here.

### What the run did not answer

Dark mode, Dynamic Type, the follow camera and the performance probe are in the
campaign and shell+map shards, which had not finished. Frames E–J of the AE-048
journey were never reached, because it stopped at the lease. Both wait on the
redispatch.

---

## 14. Remaining issues

1. **The era and the reputation are not on the world.** Both are one tap away
   on the briefing; neither is on the map surface. `TD-039`.
2. **Two journeys now present a sheet from inside a sheet** (the guided route
   sheet over the briefing). It is what a player following that advice does,
   and it is one nesting level neither journey had. `TD-039`.
3. **Settings is two taps from the world**, where it was one from Home.
   `TD-039`.
4. **BUG-061 is still open.** "Advance to next morning" lands on 00:00, so
   every journey frame taken after a sunrise photographs the world at local
   midnight — which for a phase about a living map is exactly the wrong
   picture. It was not fixed here: `GameSession` has no catalog, so reaching
   `OpsTuning.operatingDayStartMinute` means changing Core's session API under
   ~1,800 sunrise taps this branch cannot run. `MapHomeUITests` works around it
   by reaching its later-state frames at 16× rather than by sunrise.
5. **iPad is partly verified.** The shell journey passed at regular width and
   its frames were inspected; the detail/Settings journey found BUG-064, now
   fixed. What has *not* been seen on iPad is the AE-048 journey itself.
6. **VoiceOver was not run.** §9 says what was written and what that does not
   prove.
7. **No performance number was measured.** §11.

---

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
