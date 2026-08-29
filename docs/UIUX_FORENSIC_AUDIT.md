# Airline Empire — UI/UX Forensic Audit

> **Master Prompt 01.** A complete baseline of the application from a UI/UX
> and product perspective: what exists, what works, what is missing, what is
> broken, and what needs improvement. Analysis only — this audit changed no
> application code.
>
> **Audited:** 2026-08-29, branch `claude/first-master-prompt-2yw459`, head
> `f771257`. Scope: the entire repository — 12 app sources (2,968 lines of
> SwiftUI), 49 Core sources (7,573 lines), 5 content packs, 30 docs, 8 task
> files, the release tooling and the store listing.

---

## 0. How to read this document

Every finding is tagged with how it was established, because this app has
compiled but has never been runtime-validated beyond its first screens
(`tasks/CURRENT_PHASE.md`), and an audit that blurs those two things is
worthless:

| Tag | Meaning |
|---|---|
| **[code]** | Verified by reading the source. True regardless of device. |
| **[device]** | A prediction about rendering/behaviour on a device, derived from the code plus how the framework behaves. Needs a screen to confirm. |
| **[design]** | A gap against this repository's own design documents. |

Priorities are the prompt's: **P0** critical (blocks or breaks the core
experience), **P1** high (a promised experience is missing or misleading),
**P2** medium (friction, inconsistency), **P3** low (polish).

---

## 1. Executive summary

Airline Empire has an exceptional simulation core wearing a thin, unfinished
client. The gap between the two is the single most important fact about this
product.

**What is genuinely strong.** The architecture is right, and it is right in
the way that matters for UX: every number a screen shows is computed in Core
and tested headlessly (`ReadModels.swift`, `MapModel.swift`, `DailyDigest.swift`,
`OnboardingModel.swift`). Views format; they do not calculate. That discipline
is why the finance screen can be trusted, why the route P&L is the *same*
arithmetic the economy used, and why an entire class of "the UI says one
thing and the game does another" bug simply cannot occur here. The design
system is small, opinionated and mostly consistent (`AETheme`, `AEMotion`,
`aeGlass`). The onboarding screen (`NewGameView`) is genuinely good product
design — a decision-shaped hierarchy, real data on the choice cards, the one
button that matters pinned where it can always be reached. Every player-facing
Core command has a UI entry point; there are no unreachable systems in the
command surface.

**What is wrong.** The client stops at "the data is on screen". It rarely
gets to "the player understands, and knows what to do next".

1. **The tab bar overflows.** Six tabs on iPhone means iOS shows four plus a
   *More* list. **Finance and World — the money screen and the entire
   progression, competitor, events and settings hub — are one level deeper
   than every other screen, inside a system list that ignores the app's
   design language entirely.** [device]
2. **The failure journey has no UI at all.** Core runs a silent
   `daysInsolvent` countdown to administration. The player is shown no cash
   warning, no countdown, no credit deterioration, no emergency toolkit —
   the first notice is a single line of feed text *after* the airline has been
   restructured. `PLAYER_JOURNEY.md` §6 specifies a warning cascade and a
   recovery toolkit; none of it exists. [code][design]
3. **A new route shows ¤0 for up to a month.** The route detail screen renders
   `economicsLastMonth` only. `economicsThisMonth` exists in Core and is never
   read. A player who opens their first route and goes looking for "is this
   working?" gets a P&L of all zeros through the exact window in which they
   are deciding whether this game is any good. [code]
4. **The map is not a map.** `AETheme.mapLand` is defined and never used.
   There are no coastlines, no landmasses, no context — dots and arcs on a flat
   navy rectangle. The design documents call the map "the emotional
   centerpiece" and "the primary lens". It is currently a scatter plot. [code]
5. **Failures are silent in the places failure is most likely.** The single
   rejection alert lives on `GameTabs` (`RootView.swift:53`). A rejection
   raised while a sheet is up (the aircraft shop, the loan desk, the route
   sheet — where nearly every rejectable command is issued) has nowhere to
   appear. And `loadGame`'s "Could not load this save" is set on a screen that
   has no alert at all, so a corrupt save fails **completely silently**. [code]
6. **Model vocabulary leaks onto the screen.** Players are shown
   `firstProfitableMonth`, `efficientTurnarounds`, `northAmerica`,
   `southeastAsia`, `Strike at airline #3`. [code]
7. **Time control exists on two of six screens.** Change speed from Routes,
   Fleet, Finance or World and you cannot — you must navigate back to Home or
   Map. Those four screens also never show the date, so the player cannot tell
   whether the world is even running. [code]

**The one-sentence verdict.** This is a finished, hardened, trustworthy
simulation with a client that has been *authored* rather than *designed
through* — the screens exist, the loop closes, and almost nothing in the app
yet does the work of making a player feel like a founder-CEO instead of a
person reading a correct table.

---

## 2. Application overview

### 2.1 Architecture

```
AirlineEmpireCore (SwiftPM, platform-free, 7,573 loc, 257 tests)
   Foundation  Money · SimTime · GameCalendar · SeededRandom · StableHash
   Domain      Airline · Aircraft · Route · Flight · Ledger · Loan ·
               Reputation · Progression · WorldState · WorldEvent · GameState
   Systems     Demand · FlightScheduling · FlightOps · Economy/Solvency ·
               Fleet · Reputation · WorldEvent · Progression · CompetitorAI
   Simulation  Command → SimulationEngine (tick) → SimEvent
   Session     GameSession (actor) · ReadModels · MapModel · OnboardingModel ·
               DailyDigest · EventFeed · ScenarioBootstrap
   Persistence SaveStore · Migrations · SaveEnvelope (v10)
   Content     ContentCatalog ← 5 JSON packs (80 airports, 14 aircraft,
               3 scenarios, tuning, seasonality)
        │
        │  snapshot (GameState value) ↓        ↑ Command
        │
AirlineEmpireApp (iOS 17+, SwiftUI, 2,968 loc, 12 files)
   App           AirlineEmpireApp (scene) · GameController (@Observable)
   DesignSystem  Theme (tokens) · Components (14 components)
   Screens       RootView · NewGameView · DashboardView · MapView ·
                 RoutesView · FleetView · FinanceView · OperationsView
```

**The seam is excellent.** `GameController` is the only bridge: it owns the
`GameSession` actor, pumps real time at 4 Hz while the scene is active,
publishes an immutable `GameState` snapshot, and forwards commands. It holds
zero game rules. `docs/UI_ARCHITECTURE.md`'s central rule — *views format,
Core calculates* — is honoured everywhere I looked, with one exception noted
in §11.

### 2.2 Navigation structure

```
RootView  (crossfaded, 3 states)
├── .newGame   → NewGameView            [no game loaded]
├── .gameOver  → GameOverView           [progression.gameOver]
└── .playing   → GameTabs (TabView ×6)
    ├── Home     DashboardView   ─ sheet → OpenRouteSheet
    ├── Map      MapScreen       ─ overlay → AirportCallout
    ├── Routes   RoutesView      ─ push → RouteDetailView
    │                            ─ sheet → OpenRouteSheet
    ├── Fleet    FleetView       ─ sheet → AircraftShopSheet
    ├── Finance  FinanceView     ─ sheet → LoanSheet
    └── World    OperationsView  ─ push → WorldEventsView
                                 ─ push → CompetitorsView
                                 ─ push → ProgressionView
                                 ─ push → SettingsView
```

Maximum depth is 2. Nothing is more than three taps from the tab bar. That is
a good shape — undermined by the tab overflow (UI-001).

### 2.3 State management

`@Observable GameController` in the SwiftUI environment; one immutable
snapshot; screens re-derive read models from it inside `body`. Simple, correct,
and one Observation registration for the whole app.

**Cost:** every screen recomputes its read models on every one of the ~4
snapshots per second. `DashboardView` calls `dashboardModel()` twice per
render (`:16` and again in `navigationTitle` at `:50`). `RouteDetailView`
builds the *entire* route-card array and the *entire* fleet-card array on every
frame to find one route (`RoutesView.swift:93`, `:186`). `MapScreen` rebuilds
the whole `MapModel` — 80 airports, every route's 25-point great-circle arc,
every live flight — four times a second, whether or not anything moved
(`MapView.swift:17`). See UI-016.

### 2.4 Data flow

```
GameSession (actor) ──pump(250ms)──► engine.advance ──► GameState
                                              │
     ┌────────────────────────────────────────┴──────────┐
     ▼                     ▼                             ▼
 snapshot           events(playerFeedOnly:)        rejections()
     │                     │                             │
     └─── GameController ──┴─────────────────────────────┘
                  │  snapshot · recentEvents(≤200) · lastRejection · speed
                  ▼
            SwiftUI screens (read models computed in body)
                  │
                  └── submit(Command) ──► GameSession
```

Two subtleties worth crediting: the event stream is **audience-filtered in
Core against the state that produced the event** (BUG-004/BUG-007), and
commands queued while the sim is running get their rejections delivered via a
dedicated stream (BUG-005) because `submit` cannot answer for them. Both are
the right fixes at the right layer.

### 2.5 Environment, build and settings

- **Deployment target** iOS 17.0; `TARGETED_DEVICE_FAMILY: "1,2"` (iPhone +
  iPad). Liquid Glass is availability-gated to iOS 26 with an
  `.ultraThinMaterial` fallback (`Components.swift:331`) — a clean single
  entry point, exactly the right structure.
- **Project generation** XcodeGen from `project.yml`; `.xcodeproj` is
  git-ignored and CI regenerates it, so the manifest cannot drift.
- **Info.plist** generated from `INFOPLIST_KEY_*`. Orientations declared per
  device (iPad needs all four for multitasking — Apple error 90474, already
  learned the hard way). Bundle id pinned. Export compliance declared.
  This file is unusually well-reasoned; its comments explain *why*, not what.
- **Resources** `PrivacyInfo.xcprivacy` (nothing collected, nothing tracked),
  `Assets.xcassets` with a single 1024×1024 `AppIcon`.
- **Settings the player can change:** service tier, and nothing else. There is
  no `@AppStorage`, no `UserDefaults`, no persisted preference of any kind in
  the app. [code]

---

## 3. Player journey map

### 3.1 The ideal journey (from `docs/PLAYER_JOURNEY.md`)

| Beat | Specified experience |
|---|---|
| First 5 min | Name, colour, one of three curated starts → map opens on home with a leased turboprop on the apron → one guided decision (two candidate routes with demand hints) → un-pause, watch it board, taxi, cross the map → first revenue posts visibly → first evening digest with its *why* |
| First session | Second route un-guided, first delay ripple, first price nudge, first weekly rollup, forward hook on exit |
| Early game | 3–5 routes, first owned aircraft, first competitor friction *explained in the feed*, first storm, first season turn |
| Mid game | Second base, **the hub decision**, capability sequencing, competitors as characters, first downturn |
| Late game | Long-haul, multi-hub banking, market-share duels, the network as an object |
| Failure | Cash crunch → **warning cascade** → **emergency toolkit** → survival with scars; administration once; second collapse → **score screen with cause chain and a new-game hook** |

### 3.2 The actual journey, step by step

| # | Step | Status | Note |
|---|---|---|---|
| 1 | Launch → New Game | **Works, well** | Masthead, name, three starts with real data chips, three difficulty pills with real numbers, seed in a disclosure, pinned Found button |
| 1a | Pick a livery colour | **Missing** | `GAME_DESIGN` §4.1 specifies it; no colour anywhere in the app |
| 2 | Found the airline | **Works** | Crossfades to the Dashboard |
| 2a | "Map opens on home" | **Missing** | Lands on the Dashboard; the Map tab opens on a hardcoded Europe centre (`MapView.swift:10`) regardless of where you started |
| 2b | "One leased turboprop on the apron" | **Missing** | You start with **nothing**. `ScenarioBootstrap` grants cash only. The first thing a new player must do is find a shop |
| 3 | Onboarding checklist appears | **Works, well** | Five real steps, next-step hint, demand-ranked suggestions |
| 4 | Get an aircraft | **Works, awkward** | Hint says "Fleet tab → Acquire" — correct, but the checklist step is not tappable, so the player reads an instruction instead of following a link (UI-011) |
| 4a | Understand what you can afford | **Missing** | The shop shows no cash balance and no affordability state (UI-006) |
| 5 | Open first route from a suggestion | **Works, well** | Sheet pre-fills origin, destination and reference fare |
| 6 | Route appears with "no aircraft" badge | **Works** | Clear, honest, correctly alarming |
| 7 | Assign the aircraft | **Works** | Route detail → Aircraft → Assign menu (BUG-002's fix) |
| 8 | Un-pause and watch it fly | **Partly** | The map animates the aircraft. But the Routes tab where you just were has no speed control, so you must go to Home or Map first (UI-004) |
| 8a | "The feed narrates: AE001 departed — 58 aboard" | **Missing** | `flightDeparted` and `flightArrived` render **nothing** (`DashboardView.swift:390`, `default: nil`). The single most-promised moment in the first five minutes — watching your first flight leave and land — produces no feed line at all (UI-003) |
| 9 | First revenue posts visibly | **Weak** | Cash rises in the header. There is no revenue event, no flash, no "+¤4,200 — AE001 landed" |
| 10 | First evening digest | **Works, well** | Yesterday's money by category with a **Why?** expander, flights flown/cancelled, the day's news, and honest about partial days |
| 11 | Read the route's P&L | **Broken for a month** | All zeros until the first month closes (UI-002) |
| 12 | First delay ripple / competitor undercut explained | **Missing** | `flightDelayed` renders "Flight delayed 12 min" with no route, no aircraft, no cause. No competitor-action events exist at all. `CORE_LOOP` §5 promises "load −12%: PacificBlue undercut fare by 18%" |
| 13 | First storm | **Partly** | Feed line + a World events list. No map indication of where the storm is, no list of *your* affected routes |
| 14 | Season turn | **Weak** | The season name sits in the dashboard subtitle; nothing announces a turn or what it means for your markets |
| 15 | Second base / hub | **Not implemented** | Descoped to the first content update (D-010). The mid-game transformation beat does not exist |
| 16 | Capability sequencing | **Present, illegible** | Raw enum names, no description, no cost, no duration, no progress (UI-008) |
| 17 | Cash crunch | **No UI whatsoever** | (UI-005) |
| 18 | Administration | **One feed line** | No screen, no explanation of what was sold, no toolkit |
| 19 | Game over | **Minimal** | Title, era, lifetime net profit, "Start a new airline". No score screen, no records, no cause chain, no network replay, no same-seed aftermath hook |
| 20 | Return next session | **Works** | Continue slots on the New Game screen with airline name, date and era |

### 3.3 Where the journey breaks, ranked

1. **Steps 17–19 (failure).** An entire designed act of the game has no
   interface. This is the biggest single hole in the product.
2. **Steps 8a–11 (the first flight and its consequences).** The hook beat.
   The flight flies, but the game does not narrate it, does not celebrate the
   first revenue, and shows a zeroed P&L when the player goes looking for
   meaning.
3. **Step 2b (no starter aircraft).** The journey document opens with an
   aircraft already on the apron for a reason: it makes the first decision
   *"where do I fly?"* rather than *"how do I shop?"*.
4. **Step 12 (causality).** Pillar 3 is explainability. The feed reports
   events without causes, and there is no competitor-action feed at all.

---

## 4. Screen inventory & analysis

16 screens plus one overlay. Every one, in full.

### 4.1 `NewGameView` — found an airline

| | |
|---|---|
| **Purpose** | Identity, difficulty, home market, seed; and resume an existing airline |
| **Shows** | Masthead; name field; continue slots (name, date, era); three curated starts with city, code, blurb and three real data chips (catchment, business/leisure lean, weather risk) from `airports.json`; three difficulty pills with blurb + starting cash + rival count + start year; seed disclosure |
| **Actions** | Type a name, pick a start, pick a difficulty, set a seed, Found, or load a slot |
| **Core** | `ContentCatalog` (airports, scenarios), `ScenarioBootstrap`, `SaveManager.slots()` |
| **Strengths** | The best screen in the app. Shape follows the decision, not the data model. The dusk backdrop makes it read as a product. Data on the cards instead of prose — market size and weather risk are the actual difficulty. The button names the airline it will found. Content and slots load once in `onAppear`, not per render. Full VoiceOver labels and hints |
| **Weaknesses** | No livery colour (`GAME_DESIGN` §4.1). No delete/rename for a save slot, and no distinction between the `auto` slot and a manual one. `preferredColorScheme(.dark)` is forced, so a light-mode player gets a hard flash into the light Dashboard on Found. Only three of 80 airports can ever be a home, hardcoded in `CuratedStart.all` — replayability is capped at three openings on a world of 80. A start's rivals and their archetypes are not previewed |
| **Missing** | Colour; slot management; "surprise me"; any preview of the world you are about to enter |

### 4.2 `GameOverView` — the airline collapsed

| | |
|---|---|
| **Purpose** | Close the run and offer another |
| **Shows** | Icon, "The airline has collapsed", airline name + final era, lifetime net profit, one button |
| **Actions** | Start a new airline |
| **Core** | `dashboardModel()`, `financeModel().lifetimeNetProfit` |
| **Strengths** | It exists and it is not a dead end (BUG-003). The scale+opacity transition gives the moment weight |
| **Weaknesses** | `String(describing: dashboard.era)` prints `empire`, lowercase, mid-sentence. One number is not a post-mortem. `PLAYER_JOURNEY` §6 asks for a score screen: network map replay, records (biggest year, best route), the cause chain, and a "start in this world's aftermath" hook. None of it is here, and most of it is *already in the snapshot* — 24 months of statements, every milestone, every achievement, the map model |
| **Missing** | The entire score screen. Also: the run's seed, so a player cannot re-run the world that beat them |

### 4.3 `DashboardView` — Home

| | |
|---|---|
| **Purpose** | Command centre: state at a glance, the digest, the feed, time control |
| **Shows** | Date + clock + season + era; cash + net worth; onboarding checklist (until complete); "Yesterday" digest; six stat tiles (Fleet, Routes, Reputation, Last month, Fuel /t, Economy); last 12 feed events |
| **Actions** | Speed control, advance-to-morning, expand the digest, tap a route suggestion |
| **Core** | `dashboardModel`, `onboardingModel`, `dailyDigest`, event stream |
| **Strengths** | The digest card is the best-designed piece of information in the app: the number, the badges, and a **Why?** that opens the category breakdown — and it is honest (`isComplete`) when a day is partial. Numeric-text transitions on money and the date make 16× readable instead of flickery. The feed slides new events in. Onboarding auto-hides when complete |
| **Weaknesses** | **No stat tile is tappable** — `UI_ARCHITECTURE` §6 requires "every number tappable to its explanation". "Economy 1.03" is an unlabelled index with no meaning attached. "Reputation 61%" does not say which of the five components moved. No feed event is tappable, so §2's "tap → the delayed flight" deep link is impossible (there is no `NavigationPath` anywhere in the app). No unread/attention badges on the tabs, though `activeEventCount` and `liveFlightCount` are computed and discarded. `dashboardModel()` is computed twice per render |
| **Missing** | Drill-downs; alerts; a forward hook ("your aircraft arrives Tuesday" — `deliveryLeadDays` is known and never surfaced); today-so-far vs. yesterday |

### 4.4 `MapScreen` — the world

| | |
|---|---|
| **Purpose** | "The network is the hero" — the primary lens |
| **Shows** | Airports (LOD by prominence), route arcs (player cyan/amber by profitability, rivals grey), live aircraft rotated to heading, an airport callout on tap |
| **Actions** | Pan, pinch, tap an airport, speed control |
| **Core** | `mapModel(catalog:)` — great-circle arcs, interpolated flight positions, closure flags |
| **Strengths** | The Core model is genuinely good: real great-circle geometry, correct headings, presentation-only interpolation, LOD prominence, player-network marking. Selection is a Core id round-trip. Sensory feedback on selection |
| **Weaknesses** | **There is no world.** `AETheme.mapLand` is declared and never referenced — no coastlines, no continents, no graticule, no labels except airport codes. Dots on navy. Nothing tells you which dot is home. **You cannot open a route from the map** — `CORE_LOOP` §6 specifies "≤ 4 taps *from the map*: select origin → destination → sheet → confirm"; the callout has no actions at all, so the map is read-only. Pan speed is scaled by `1/zoom` *and* a 0.05 constant (`MapView.swift:58`), so panning at low zoom is extremely slow and the gesture does not track the finger. `MagnifyGesture` and `DragGesture` are attached as two `.gesture` calls, the second of which replaces the first in SwiftUI unless composed — pan and zoom probably cannot both work [device]. No zoom buttons, so zoom is inaccessible to anyone who cannot pinch. Tap radius is a flat 28 pt in screen space with no zoom compensation, so at low zoom several airports overlap inside one tap target. No legend. No route selection — only airports are hit-tested |
| **Missing** | Land; a home indicator; route/flight selection; open-route-from-map; a "find my network" or reset-view control; storm/closure overlays; any pin, label or filter |

### 4.5 `AirportCallout` — map selection panel

| | |
|---|---|
| **Shows** | Name, code, city, country, slots used/capacity, runway class, CLOSED badge |
| **Weaknesses** | Runway class is printed raw (`spec.runwayClass.rawValue` → `large`). No demand data, no "you fly here", no rivals present, no fees, no distance from home — all of it in the catalog. **No actions**, so selecting an airport leads nowhere. No dismiss control (tapping empty space works, but nothing says so) |

### 4.6 `RoutesView` — the route board

| | |
|---|---|
| **Shows** | One glass row per route: pair, last-month profit, frequency, load factor, fare, "no aircraft" warning |
| **Actions** | Open route (toolbar +), tap through to detail |
| **Strengths** | The row is well-chosen: the four things that decide whether a route is healthy, plus a loud warning when it is not flying. Empty state is a real card with an instruction, not a bare label. `aeListRow` keeps `List`'s recycling and swipe machinery while looking like floating cards |
| **Weaknesses** | **No sort, no filter, no search.** At 30 routes this is an unordered wall (order is `orderedRouteIDs` — creation order). No totals row. `lastMonthProfit` is ¤0 for a route's whole first month, so a new player's board reads as a column of zeros. No swipe actions here, unlike Fleet. No aircraft count on the row unless it is zero. `CORE_LOOP` §6's "bulk actions (fleet-wide fare posture, pause route)" do not exist |

### 4.7 `RouteDetailView` — why this route makes or loses money

| | |
|---|---|
| **Shows** | Last-month breakdown (revenue, fuel, fees, crew, direct operating profit, passengers); Aircraft card; Operations (load, punctuality, completion, distance, assigned); Fare + market position + four percentage buttons + a frequency stepper; Close route |
| **Actions** | Assign/unassign aircraft, ±5/±10 % fare, ±1 frequency, close |
| **Strengths** | This is the explainability pillar realised — the exact figures the economy used, not a UI re-derivation. The ±% buttons are the right control for repricing (2 taps from the board, as specified). The "no aircraft" warning is repeated where it can be acted on |
| **Weaknesses** | **Zeros for a month** (`economicsThisMonth` exists in Core and is never read). The breakdown is four lines with no proportion — no bar, no share-of-revenue, no per-passenger unit economics. `farePosition` is shown as a percentage of reference with no indication of whether that is good; there is no demand curve, no "at this fare you are capturing ~X of the market", though `DemandSystem.expectedCapturedPassengers` is public and the onboarding already uses it. Today's demand (`demandOutboundToday`, `remainingOutboundToday`) is in the route and never shown. No competitor list for this city pair — the single most useful thing on a route screen in this genre. No trend: one month, no series. **Close route has no confirmation** and sits in a card labelled nothing (the code calls it `dangerZone`; the player sees an unlabelled card with a red button). No `aeScreenBackground()`, so this screen has a different background from every other screen [device]. The `card` parameter of `dangerZone` is unused |

### 4.8 `OpenRouteSheet` — open a route

| | |
|---|---|
| **Shows** | Two 80-item pickers, a frequency stepper, a fare slider with the market reference for the distance |
| **Strengths** | Pre-fills from an onboarding suggestion. Shows the reference fare live as distance changes — good, and it is Core's own function (BUG-001 made it public rather than duplicating the formula) |
| **Weaknesses** | **A raw `Form` — it does not look like this game.** Two 80-row pickers with no search, no grouping by region, no "near home", no distance shown in the row. **Nothing is validated until you tap Open**: no range check against your fleet, no runway check, no slot check, no cost preview, no expected demand, no estimated profit — all of which Core can answer *before* the command. **And the sheet dismisses unconditionally on Open** (`RoutesView.swift:322`), so a rejection destroys every input and the player rebuilds the form from scratch. Worse, the rejection alert is attached to `GameTabs`, underneath the sheet, so it may never appear at all [device]. `destination` defaults to a hardcoded `"LNW"`. `CORE_LOOP` §5 — "cost/commitment shown before confirm (no hidden totals)" — is unmet |

### 4.9 `FleetView` — the fleet

| | |
|---|---|
| **Shows** | Type name, status badge (location / on order / maintenance), age, condition, ownership + book value or lease rate, idle badge |
| **Actions** | Swipe → Unassign, or Sell / Return; toolbar → Acquire |
| **Strengths** | The row carries exactly the right five facts. Status and ownership are distinguished by icon + text as well as colour. Empty state teaches |
| **Weaknesses** | **No aircraft detail screen.** `FleetCardModel.reliability` and `.totalFlightHours` are computed in Core and never displayed anywhere. There is no utilisation figure, no maintenance schedule, no "which route is this on" (only `assignedRoute == nil` is used), no history, no name/registration — `GAME_DESIGN` §8 asks for "tail numbers, inaugural-flight moments". **Sell and Return are destructive, swipe-only, and unconfirmed** — a mis-swipe permanently sells an aircraft worth tens of millions with no dialog and no undo. Swipe is also the *only* path to those actions, which is poor discoverability and poor accessibility. No sort, filter, or grouping by type. No fleet totals (count, monthly lease burden, average age) |

### 4.10 `AircraftShopSheet` — the aircraft market

| | |
|---|---|
| **Shows** | A used-market age stepper, then 14 types: manufacturer + model, seats/range/burn, a delivery-lead note, and three price buttons (New / Used / Lease); locked types show a "later era" badge |
| **Strengths** | Era locking is visible rather than hidden. The delivery-lead sentence pre-empts "I bought it, where is it?". Used pricing recomputes live against the age stepper, using Core's own `FleetEconomics` |
| **Weaknesses** | **Your cash is not on this screen.** No affordability state, no disabled buttons, no "this leaves you with ¤X". **Three one-tap irreversible purchases per row, no confirmation, no summary** — the largest financial commitments in the game are a single unguarded tap, and the rejection (if you cannot afford it) is an alert attached to the view *behind* this sheet [device]. Lease term is hardcoded to 60 months with no control and no display of total commitment. No comparison: 14 types × 7 attributes and no table, sort, or filter. No per-seat economics, no "suitable for your routes", no cabin configuration (`GAME_DESIGN` §4.3). A locked type shows *nothing* — not even its stats or what era unlocks it, so the player cannot plan toward it. `List` in default style, so this sheet also does not look like the game |

### 4.11 `FinanceView` — the money story

| | |
|---|---|
| **Shows** | Cash, net worth, debt, leverage; a monthly net-profit bar chart; the latest statement by category with operating and net profit; loans with rate, term and payment |
| **Actions** | Borrow; pay off a loan |
| **Strengths** | Every cent classified and visible. Category names are shared with the digest via `DigestCard.label(for:)`, so one category never has two names. Leverage flags itself downward past 0.6 |
| **Weaknesses** | **The chart has a moving baseline.** In `MonthlyBars` each column is a `VStack` of `Spacer / positive bar / 1 pt line / negative bar / Spacer` inside an `alignment: .center` `HStack`. The content height varies with the bar, so the centred column puts the zero line at a *different y for every bar*. The chart is not merely unlabelled — it is **geometrically wrong**, and it is the finance screen (UI-007) [code]. No axis, no month labels, no values, no revenue/expense split — 24 bars and no way to know which month any of them is. The statement is one month; the series exists (24 months) and is only ever drawn as those bars. No cash-flow forecast, no runway ("at this burn you have 4 months"), which is the number that actually decides whether a player is in trouble. `RepayLoanCommand(loanIndex:)` is addressed **by array index** from a `ForEach(enumerated())` — if a loan is removed by the simulation between render and tap, the wrong loan is repaid [code]. "Pay off" is unconfirmed and shows no payoff amount |

### 4.12 `LoanSheet` — borrow

| | |
|---|---|
| **Shows** | Amount slider (¤1–200 M), term slider (6–120 months), and the exact offered rate, monthly payment and resulting leverage from `CreditMath` |
| **Strengths** | **The best-designed transactional surface in the app.** It quotes the simulation's own numbers live before you commit — precisely what `CORE_LOOP` §5 asks for. Every other sheet should look like this |
| **Weaknesses** | Total interest over the term is not shown. No affordability/serviceability warning. Dismisses unconditionally on submit like the others. A plain `Form` |

### 4.13 `OperationsView` — the World hub

| | |
|---|---|
| **Shows** | Four glass cards with icon, title and a subtitle saying what is inside |
| **Strengths** | Deliberately a hub with described destinations rather than a list of nouns. Whole-card tap targets, combined accessibility elements |
| **Weaknesses** | No live state on any card — no "2 active events", no "capability 40 % complete", no "mission expires in 6 days", though all three are in the snapshot. The label "World" for a hub whose fourth item is *settings and quitting the game* is a category error: saving and quitting do not belong behind a bolt icon |

### 4.14 `WorldEventsView`

| | |
|---|---|
| **Shows** | Active/forecast events, kind, "until day N" |
| **Weaknesses** | **"until day 4,271"** — a raw `dayIndex` presented to a player who has only ever seen `YYYY-MM-DD`. `Format.date` exists. Regions print as `northAmerica`. `Strike at airline #3` prints an internal id where an airline name belongs. No severity, no magnitude, no map link, and — the important one — **no statement of which of your routes this affects**, which is the only thing that turns an event into a decision (`GAME_DESIGN` §4.12: "every event creates a decision — never a pure toll"). No history of past events. `EmptyStateView` is placed inside a `List`, so the empty state renders as a list row with list insets rather than as a centred card [device] |

### 4.15 `CompetitorsView`

| | |
|---|---|
| **Shows** | Per AI airline: name, collapsed badge, aircraft count, route count, reputation, archetype |
| **Weaknesses** | Archetype prints raw (`profile.archetype.rawValue`). No cash, no size trend, no "routes we both fly" — head-to-head overlap is the reason this screen exists and it is absent. `GAME_DESIGN` §4.11 wants competitors to become *characters*; four badges make them a table. Collapsed rivals stay in the list forever with no separation. No empty state. No detail view |

### 4.16 `ProgressionView`

| | |
|---|---|
| **Shows** | Era; four capability programs with built / in-progress / Start; missions; milestones; achievements |
| **Weaknesses** | **The most illegible screen in the app.** Capabilities show `code.rawValue` — `efficientTurnarounds` — with **no description of what it does, no cost, no duration, and no progress or completion date for an in-progress one**, though `CapabilityProgram` carries `cost`, `startedAt` and `completesAt`. Start is an unconfirmed one-tap ¤12 M commitment. Milestones and achievements render as raw codes: `firstProfitableMonth`, `weatherProof`, `valueLegend`. **Nothing shows what the next era requires** — `ProgressionTuning` holds every gate (3 profitable routes → Regional; 8 destinations + 0.55 reputation → National; …) and none of it is on screen, so the game's macro arc is invisible. Missions show no progress against target and no live countdown. The Achievements section renders an empty header when there are none |

### 4.17 `SettingsView` (titled "Airline")

| | |
|---|---|
| **Shows** | Service tier picker; five reputation components with progress bars; Save now; Save and quit; a backup-recovery warning |
| **Strengths** | The reputation breakdown is good and honest. The backup-recovery notice is exactly the right kind of candour |
| **Weaknesses** | Three unrelated things in one screen with the navigation title "Airline" and the hub label "Service & settings". Service tier shows no cost per passenger and no effect on reputation, so the choice is uninformed. Reputation shows the five numbers but not *why* any of them moved. **"Save now" gives no confirmation** — it calls `saveOnBackground()`, which fires a detached `Task { try? await ... }` and **discards the error**; a failing save is indistinguishable from a succeeding one [code]. There are **no actual settings**: no sound, no haptics, no auto-pause (`CORE_LOOP` §2 specifies settable auto-pause), no confirmations, no units, no accessibility options, no about/credits, no privacy link, no reset |

---

## 5. Core system coverage

For each system: is there a UI entry point, is it discoverable, can the player complete the flow, are results clearly shown, and are there BUG-002-class gaps (a system with no way in)?

| System | Entry point | Discoverable | Completable | Results shown | Verdict |
|---|---|---|---|---|---|
| **Fleet** | Fleet tab | Yes | Yes | Partly — no detail screen; `reliability`, `totalFlightHours`, utilisation never shown | **Adequate** |
| **Aircraft market** | Fleet → Acquire | Yes | Yes | No — no cash, no affordability, no confirmation, locked types are blank | **Weak** |
| **Routes** | Routes tab, Dashboard suggestions | Yes | Yes | Partly — a month of zeros; no this-month; no competitors on the pair | **Weak** |
| **Flights** | Map + feed | Partly | n/a (automatic) | **No** — `flightDeparted`/`flightArrived` render nothing; delays have no cause, no route, no aircraft | **Weak** |
| **Airports** | Map tap only | **No** | n/a | Partly — slots and runway only; runway raw | **Weak — no airport list or browser exists** |
| **Finances** | Finance tab (**behind More**) | **No** | Yes | Partly — broken chart, one month, no forecast | **Weak** |
| **Reputation** | World → Service & settings | **No** | n/a | Partly — five values, no causes, no history | **Weak** |
| **Competitors** | World → Competitors | Partly | n/a | Partly — no overlap, no actions, archetype raw | **Weak** |
| **Events** | World → World events, feed | Partly | n/a | **No** — raw day index, raw regions, airline ids, no impact on *your* network | **Weak** |
| **Progression** | World → Progression | **No** | Yes | **No** — raw codes, no descriptions, no costs, no gates, no progress | **Poor** |
| **Missions** | World → Progression | **No** | n/a | **No** — no progress, no countdown, no map link | **Poor** |
| **Settings** | World → Service & settings | **No** | Partly | n/a | **Poor — there are no settings** |
| **Save/Load** | World → Service & settings; New Game | Partly | Yes | **No** — save success/failure is never reported; load failure is silent | **Weak** |
| **Solvency / administration** | **None** | — | — | One feed line, after the fact | **Missing entirely** |
| **Hubs** | **None** | — | — | — | **Not implemented (D-010, deliberate)** |
| **Staff / HQ** | **None** | — | — | — | **Not implemented in Core either** |

**BUG-002-class gaps** (a Core capability with no way in): none in the
*command* surface — every player command is reachable. But there are three
**information** gaps of the same severity, where Core computes something the
player needs and no screen shows it: the insolvency countdown (§UI-005), the
current month's route economics (§UI-002), and every era gate threshold
(§UI-008).

---

## 6. UX evaluation

**Information hierarchy.** Good on Dashboard and New Game, poor elsewhere.
Route detail leads with last month's breakdown rather than "is this route
working right now". Progression leads with era and then buries what era
actually means. Settings mixes a strategic choice (service tier), a report
(reputation) and a file operation (save) at equal weight.

**Clarity.** The digest, the loan sheet and the fare controls are clear.
Almost everything in the World tab is not: an event that ends "day 4271", a
capability called `efficientTurnarounds`, a strike "at airline #3".

**Feedback.** This is the weakest dimension in the app. There is exactly one
piece of feedback machinery — an alert titled "Not possible" with an OK
button — and it is mounted where the sheets that generate most rejections
cover it. There are no toasts, no inline validation, no success confirmations,
no progress indication for anything, no haptics beyond three `sensoryFeedback`
calls, and no sound at all. A player who taps Buy and has enough money sees
the fleet list change *if they go and look*; a player who does not have enough
money may see nothing whatsoever.

**Guidance.** Strong for the first five minutes (the onboarding card is
genuinely well made), then it stops dead. There is no second-session guidance,
no "what should I do next" at any later point, no hint system, no tips, no
help, no glossary. The moment the checklist completes, the game stops talking.

**Consistency.** Two visual languages coexist: the glass/dusk language of the
main screens, and raw `Form`/`List` in every sheet and every World sub-screen.
Section headings are `AESectionHeader` in one place and ad-hoc
`Text(...).font(.headline)` in fourteen others. Destructive actions are
swipe-only in Fleet and a button in Route detail.

**Friction budget** (`CORE_LOOP` §6):

| Target | Actual |
|---|---|
| Open a route ≤ 4 taps **from the map** | **Impossible from the map.** From Routes: 3 taps + two picker journeys |
| Reprice ≤ 2 taps from a route card | **Met** (row → ±5 %) |
| Nothing routine needs more than one screen | **Missed** — changing speed from four of six tabs requires leaving the tab |
| Bulk actions exist from Phase 14 | **Missing entirely** |

---

## 7. UI design evaluation

**Visual hierarchy.** Cards carry it well. Weak points: the six stat tiles on
Dashboard are all identical weight, so "Reputation" reads as loud as "Last
month"; the four Finance tiles do the same. The most important number on a
screen is rarely the biggest.

**Information density.** Sparse in the wrong places. Route detail is 30 lines
of content in a full-screen scroll. Fleet rows show 5 of ~12 known facts. The
aircraft market shows 3 of 14 aircraft attributes.

**Colour.** A small semantic set (accent/positive/negative/caution) used
consistently, and colour is correctly never the only carrier — badges pair
hue with text and usually an icon. But `AEBadge` is called with ad-hoc
`.purple`, `.indigo`, `.teal`, `.secondary` outside the token set at five call
sites, which is exactly the drift `AETheme` exists to prevent.
`AETheme.mapLand` is dead.

**Typography.** Semantic text styles throughout, so Dynamic Type should scale
— with four exceptions using `.system(size:)`: `RootView:74` (56 pt icon),
`Components:222` (34 pt icon) and `MapView:153`/`:167` (9 pt and 12 pt map
labels). The two icons are decorative and defensible; the **9 pt map labels
are below the 11 pt minimum and do not scale at all** [code].

**Spacing & layout.** A clean 4/8/16/24 grid, used consistently. Corner radius
is expressed as `AETheme.cornerRadius + 4` at nine call sites, which means the
real card radius is 18 and the token says 14 — the token is not the source of
truth it claims to be.

**Cards.** `AECard` is a good primitive. `AEChoiceCard` carries selection three
ways (tint, ring, checkmark), which is exactly right.

**Buttons & controls.** `SpeedControl` is the standout — one capsule with a
`matchedGeometryEffect` selection that slides, 44 pt targets, per-speed
VoiceOver labels, sensory feedback. It is the model the rest of the app should
follow. Elsewhere `.buttonStyle(.bordered)` at `.caption` size (Fleet
unassign, loan pay-off, fare buttons, digest Why?) produces targets that are
likely under 44 pt [device].

**Feedback & states.** Loading is a bare `ProgressView()` on five screens with
no context. Empty states exist and are well made — but only four of them, and
`WorldEventsView` puts one inside a `List`. There are **no error states** other
than the single alert, and **no disabled states anywhere in the app**: every
button is always enabled, whether or not the action can succeed.

**Animation.** `AEMotion`'s three named curves are the right abstraction, and
`contentTransition(.numericText())` on money and dates is the single best
polish decision in the codebase — it is what makes 16× readable. Missing:
nothing celebrates. A milestone, an era advance, a first profitable month, an
aircraft delivery — all of them arrive as one grey line in a feed.

**Haptics.** Three `sensoryFeedback(.selection, …)` calls (speed, map
selection, two onboarding pickers). Nothing on success, failure, delivery,
milestone or alarm. `UI_ARCHITECTURE` §4 specifies a `HapticService` keyed off
`SimEvent` with per-category settings; it does not exist. Neither does the
`AudioService` beside it.

---

## 8. Map analysis

The Core map model is the strongest unexploited asset in the project.

**Style.** Dark navy field, cyan player routes, grey rivals, white airport
dots. Coherent, and empty — no land, no water differentiation, no borders, no
graticule, no place names.

**Readability.** Airport LOD (`prominence > 0.35`, or served by the player, or
zoom > 3) and route LOD (rival lines thin below zoom 3) are sensible.
Airport codes draw at 9 pt with no collision avoidance — at zoom > 2.5 in
Europe, 26 airports will overlap into mush [device].

**Markers.** Radius `2 + prominence·3 + 1.5` gives a 2–6.5 pt dot. That is
below every touch and legibility guideline. Closed airports turn red; there is
no legend saying so.

**Routes.** Correct great-circle arcs — properly earned, with date-line
handling tested. Colour encodes ownership and last-month profitability. Width
does not encode frequency, though `dailyRoundTrips` is in the model.

**Flights.** Rotated `airplane` glyphs at 12/9 pt. Good. No trail, no
selection, no label, no tap target — you cannot tap your own aircraft.

**Zoom.** 1×–12×, pinch only. No buttons, no double-tap, no fit-to-network,
no reset, no minimum-zoom framing on the player's own airports.

**Interaction model.** Read-only. Tap an airport → a callout with facts and no
actions. This is the core failure of the screen: `GAME_DESIGN` pillar 4 makes
the map the primary lens, and `CORE_LOOP` §6 makes it the primary route-opening
surface, and it is currently a viewer.

**Performance.** The whole `MapModel` is rebuilt four times a second inside
`body` — 80 airports, a 25-point arc per route (player *and* every rival's),
and every flight interpolated. At mid-game scale that is thousands of
trigonometric evaluations per frame for a picture that changes very little.
Arcs are static geometry and should be built once per route, not per frame
[code/device].

**Immersion opportunities.** Land and coastline; a home marker; the network
drawn in with a sweep when you first open the tab; day/night terminator (every
airport already carries `utcOffsetMinutes`); weather overlays for active storms
(the events already carry regions); tapping a flight to follow it; a
"network at a glance" zoom that frames your own airports.

---

## 9. Asset audit

| Asset class | Exists | Missing / needs work |
|---|---|---|
| Aircraft | **Nothing** | 14 types with no silhouette, illustration, livery or even a category glyph. Every aircraft in the game is the same SF Symbol |
| Airports | **Nothing** | 80 airports with no imagery, no city photo, no terminal art, no category icon |
| Icons | SF Symbols only | Consistent and free, but the app has zero custom iconography — nothing about it looks like *this* game rather than a system app |
| UI assets | None | No textures, no dividers, no ornament; all surfaces are gradients and materials |
| Backgrounds | 2 gradients | `AEGameBackdrop` (system-colour gradient) and `AEDuskBackdrop` (dusk + ember). Both good; the dusk one is used on exactly one screen |
| Branding | App icon (1024², no alpha) + site cover | No wordmark in-app, no launch imagery (`UILaunchScreen_Generation: YES` = a plain generated screen), no colour identity beyond `Color.blue` as accent |
| Consistency | Good by default | Being SF Symbols throughout, nothing clashes — and nothing is memorable |

Two specific notes. The app icon is a detailed photographic scene, and
`AirlineEmpireApp/Resources/README.md` already flags the right question: does
it read at 60 pt? That must be tested on a home screen before submission.
Second, `AETheme.accent = Color.blue` — the system blue — is the accent of a
utility, not of a game about dusk skies and ember horizons. The dusk palette
already in `AETheme` is a far better identity and is used on one screen.

---

## 10. Technical quality

**SwiftUI quality.** Generally good. Clear view decomposition, `@ViewBuilder`
used correctly, no massive bodies, sensible use of `Group`/`ZStack`.

**Reusability.** 14 components in 436 lines, most reused. But `AESectionHeader`
is used once while fourteen screens hand-roll the same heading, and
`EmptyStateView` is used four times where at least eight screens need one.

**Component architecture.** The `aeGlass` availability gate is exemplary: one
function, one place to change when the deployment target rises.

**Duplication.** Low, and consciously managed — `DigestCard.label(for:)` is
deliberately shared with Finance so a category cannot have two names. Small
repeats: `RoundedRectangle(cornerRadius: AETheme.cornerRadius + 4, style:
.continuous)` is written out nine times and should be one token.

**Performance risks** [code, unmeasured on device]:
1. `MapModel` rebuilt at 4 Hz inside `body` (§8).
2. `RouteDetailView` computes all route cards *and* all fleet cards per frame
   to display one route (`RoutesView.swift:93`, `:186`).
3. `dashboardModel()` computed twice per Dashboard render.
4. `fleetCards`/`routeCards` recomputed per frame for list screens.
5. `MonthlyBars` recomputes `max` over the series inside `GeometryReader`.

None of these are wrong at 10 routes. All of them are O(world) per frame, and
`UI_ARCHITECTURE` §5 requires "snapshot→frame work is O(visible), not
O(world)".

**Memory.** Bounded and honest — `recentEvents` capped at 200, statements at
24 months, ledger and event log are rings. Good.

**Concurrency.** `GameController` is `@MainActor`; `GameSession` is an actor;
snapshots are `Sendable` value types. The pump task is cancelled on scene
change and on `quitToMenu`. One real defect: `saveOnBackground()` fires
`Task { try? await session.saveNow(...) }` and **swallows the error**
(`GameController.swift:98`), so a save failure is invisible on backgrounding
*and* when the player explicitly taps "Save now". `GameSession.lastSaveError`
exists in Core and is never read by the app.

**Correctness defects found by reading** [code]:
- `MonthlyBars` zero-line moves per bar (§4.11).
- `RepayLoanCommand` addressed by array index across a render boundary (§4.11).
- The rejection alert is unreachable from sheets and absent from `NewGameView`,
  so `loadGame` failure is silent (§4.1, §12).
- `startNewGame` failure paths are `assertionFailure`, which is a **no-op in
  release** — a content-load failure produces a button that silently does
  nothing (`GameController.swift:34`, `:51`).
- `MapScreen` attaches two `.gesture` modifiers; the later one replaces the
  earlier unless composed with `.simultaneously` — pan and zoom likely cannot
  coexist [device].

**Accessibility readiness.** Better than most codebases at this stage:
`accessibilityLabel`/`Hint`/`AddTraits(.isHeader)`/`accessibilityElement(children:
.combine)` are used deliberately, `SpeedControl` has per-speed spoken labels,
and colour never carries meaning alone. Gaps: the map `Canvas` has a single
label for the entire world and is completely opaque to VoiceOver (no per-airport
elements, no rotor, no alternative to pinch-zoom); several `.caption`-sized
bordered buttons are likely under 44 pt; 9 pt map text does not scale; and
Reduce Motion is only handled by SwiftUI's own defaults, with no explicit
`@Environment(\.accessibilityReduceMotion)` anywhere.

**Localization readiness.** **Zero.** Every string is a hardcoded literal;
there is no `String(localized:)`, no catalog, no `.strings`. Numbers are
formatted with `String(format:)` rather than `FormatStyle`, so grouping
separators, decimal separators and negative signs are all fixed to a
US-English convention — `Format.money` even hardcodes `−` (U+2212) and the
generic currency sign `¤`. Dates are `%04d-%02d-%02d`. Retrofitting this later
touches every one of the 12 app files.

---

## 11. Technical audit — architecture conformance

| Rule (`UI_ARCHITECTURE.md`) | Status |
|---|---|
| Views never import engine internals | **Honoured** |
| Views format, never calculate | **Honoured, with two exceptions**: `RoutesView.swift:165` computes a new fare from a percentage, and `MapProjector` does projection math. Both are defensible (one is a UI gesture, one is rendering), but the fare arithmetic is the kind that belongs in Core |
| Anything needed twice becomes a Core read model | **Honoured** |
| Formatting centralized | **Honoured** (`Format`) |
| Design tokens; no ad-hoc styling | **Mostly** — five ad-hoc badge colours, nine open-coded corner radii |
| Navigation state is a value (`AppRoute`) | **Not implemented.** No `NavigationPath` anywhere; deep links from events are impossible |
| Per-area `@Observable` view models | **Not implemented.** Screens read the controller directly. Simpler, and fine at this size — but it is why read models are recomputed in `body` |
| Adaptive shell: tab bar on iPhone, **sidebar/split on iPad** | **Not implemented.** `TabView` only; no `NavigationSplitView`, no size-class checks. Ships for iPad with a phone layout |
| No fixed font sizes | **4 violations** |
| 44 pt minimum targets | **Partly** — honoured in the design system, likely violated by `.caption` bordered buttons |
| Reduce Motion honoured centrally | **By framework default only** |
| Charts on Swift Charts | **Not used** — hand-rolled `MonthlyBars`, which is where the baseline bug lives |
| Every number tappable to its explanation | **Not implemented** |
| Empty states teach | **Where they exist** (4 of ~8 needed) |
| Haptics/audio services keyed off `SimEvent` | **Not implemented** |

---

## 12. Issue log

### P0 — critical

**UI-001 · The tab bar overflows on iPhone; Finance and World fall into *More*** [device]
`RootView.swift:38–51` declares six tabs. iOS shows four plus an automatic
*More* tab when a tab bar has more than five items. That buries the finance
screen — the survival system — and the entire World hub (events, competitors,
progression, missions, service tier, reputation, save, quit) behind a
system-styled list that ignores the app's design language. Two of the game's
six top-level areas are second-class, and the *only* way to save or quit the
game is through it.
*Fix direction:* five tabs at most. Fold Finance into Home as a section or a
prominent card, or merge Routes+Fleet into a single "Network" tab; move
save/quit out of the World hub entirely.

**UI-002 · A new route reports ¤0 for up to a full game month** [code]
`RoutesView.swift:118–133` and `RouteRow` render `economicsLastMonth` only.
`Route.economicsThisMonth` exists, is maintained by the economy every tick, and
is never read by any screen. A player who opens their first route and asks
"is this working?" is shown revenue ¤0, fuel ¤0, profit ¤0, 0 passengers —
through the exact window in which they decide whether the game rewards
attention. `CORE_LOOP` §5 promises consequence "within days".
*Fix direction:* lead with month-to-date, show last month beside it as the
comparable.

**UI-003 · The first flight is silent** [code]
`EventRow.description` (`DashboardView.swift:354–393`) has no case for
`flightDeparted` or `flightArrived`; they fall to `default: nil` and render
nothing. `PLAYER_JOURNEY` §1 step 3 — *"the feed narrates: AE001 departed —
58 aboard"* — is the promised payoff of the first five minutes, and it does
not happen. The first revenue posting is likewise unannounced.
*Fix direction:* render departures and arrivals for the player's own flights
with route, aircraft and load; consider throttling once the network is large.

**UI-004 · Rejections cannot be seen where rejections happen** [code/device]
The one alert in the app is attached to `GameTabs` (`RootView.swift:53`).
Almost every rejectable command is issued from a **sheet** presented above it
— the aircraft shop (insufficient funds, locked era), the route sheet (no
slots, too short, duplicate, out of range), the loan desk (over-leveraged).
An alert on the presenting view cannot appear over its own sheet. Worse, the
sheets **dismiss unconditionally on submit**, so the inputs are destroyed too.
And `NewGameView` has no alert at all, so `GameController.loadGame`'s
"Could not load this save" (`GameController.swift:72`) is **never shown to
anyone** — a corrupt save fails in total silence.
*Fix direction:* rejection presentation belongs at the `RootView` level (or in
each sheet); sheets should stay open and show the rejection inline until the
command is accepted.

**UI-005 · The failure journey has no interface at all** [code][design]
`SolvencySystem` runs a daily countdown: `daysInsolvent` accumulates below
`overdraftFloorCents`, and at `administrationGraceDays` the airline is
restructured — aircraft fire-sold, reputation scarred, loans haircut. Neither
`daysInsolvent` nor `administrationCount` is read anywhere in the app. There is
**no cash warning, no countdown, no credit signal, no auto-pause, no emergency
toolkit, and no administration screen**. The first notice the player receives
is one line in a feed *after* their fleet has been sold. `PLAYER_JOURNEY` §6
specifies a warning cascade, an emergency toolkit and "survival with scars";
`GAME_DESIGN` §5 says "losing should teach, not delete". Currently losing
neither teaches nor is visible.
*Fix direction:* a persistent solvency banner with the day count; auto-pause on
entering the danger window; an administration summary screen listing what was
sold and what was forgiven; a triage view.

### P1 — high

**UI-006 · Irreversible money decisions have no confirmation and no cost context** [code]
Buy / Lease in the aircraft shop, Sell / Return by swipe in Fleet, Close route,
Start capability (¤12 M), Pay off loan — all single unguarded taps. The
aircraft shop never shows your cash balance. `CORE_LOOP` §5: "cost/commitment
shown before confirm (no hidden totals)". There are no disabled states anywhere
in the app, so nothing signals affordability before the tap.

**UI-007 · The finance chart's zero line moves from bar to bar** [code]
`Components.swift:180–210`. Each column is `Spacer / +bar / line / −bar /
Spacer` inside a centre-aligned `HStack`, so column content height varies with
the bar and the centred column places the baseline at a different y for every
month. The chart is not just unlabelled — it misrepresents the data, on the
finance screen, in a game about money. No axis, no month labels, no values.
*Fix direction:* Swift Charts, as `UI_ARCHITECTURE` §2 already specifies.

**UI-008 · Progression is written in model vocabulary and hides its own rules** [code]
Capabilities render `code.rawValue` (`efficientTurnarounds`) with no
description, cost, duration or progress, though `CapabilityProgram` carries
`cost`, `startedAt` and `completesAt`. Milestones and achievements render as
raw codes (`firstProfitableMonth`, `weatherProof`). **No screen states what the
next era requires**, though every threshold is in `ProgressionTuning` — the
game's macro arc is invisible. Missions show no progress against target.

**UI-009 · The map has no world, and no actions** [code]
`AETheme.mapLand` is declared and never used: no coastlines, no landmasses, no
context. Nothing marks home. Tapping an airport yields facts and no actions, so
`CORE_LOOP` §6's "open a route ≤ 4 taps from the map" is impossible. Flights
and routes are not selectable. `GAME_DESIGN` pillar 4 — "the network is the
hero", "progress is visible geography" — is unmet by the screen that exists to
carry it.

**UI-010 · Time control and the date exist on two of six screens** [code]
`SpeedControl` appears on Dashboard and Map only. From Routes, Fleet, Finance
or World the player cannot pause, change speed, or skip to morning, and no
screen shows the date or whether the simulation is running. `CORE_LOOP` §6:
"nothing routine requires visiting more than one screen".

**UI-011 · Events, causes and consequences are never connected** [code]
`flightDelayed` renders "Flight delayed 12 min" — no route, no aircraft, no
reason. World events name a region and a raw day index but never say which of
*your* routes they touch. There are no competitor-action events at all, so
`CORE_LOOP` §5's worked example ("load −12 %: PacificBlue undercut fare by
18 %") has no mechanism behind it. Nothing in the feed is tappable, and there
is no `NavigationPath`, so deep links are structurally impossible.

**UI-012 · Save and load report nothing** [code]
`saveOnBackground()` discards the result (`GameController.swift:98`); "Save
now" therefore cannot fail visibly, and cannot succeed visibly either.
`GameSession.lastSaveError` exists and is never read. Load failure is silent
(see UI-004). `startNewGame`'s failure paths are `assertionFailure`, a release
no-op — a content-load failure yields a dead button.

**UI-013 · iPad ships with a phone layout** [code]
`TARGETED_DEVICE_FAMILY: "1,2"` with `TabView` only. No `NavigationSplitView`,
no `horizontalSizeClass` anywhere. `UI_ARCHITECTURE` §2 specifies an adaptive
shell with a sidebar on iPad. A route list at iPad width will be one row of
text across 1,000 pt.

**UI-014 · No celebration, no drama, no sound** [code]
Milestones, era advances, aircraft deliveries, first profitable months and
mission completions all arrive as one grey feed line. No haptics beyond three
selection taps; no audio at all; no `HapticService`/`AudioService` as
`UI_ARCHITECTURE` §4 specifies. For a game whose stated emotional payload is
ownership of a growing network, nothing ever marks growth.

### P2 — medium

**UI-015 · Two visual languages.** Every sheet (`OpenRouteSheet`, `LoanSheet`,
`AircraftShopSheet`) and four of five World sub-screens use raw `Form`/`List`
with no `aeScreenBackground()`, so half the app looks like Settings.
`RouteDetailView` also has no backdrop.

**UI-016 · Read models recomputed per frame.** `MapModel` at 4 Hz;
`RouteDetailView` builds every route card and every fleet card to show one
route; `dashboardModel()` twice per Dashboard render. O(world) per frame
against `UI_ARCHITECTURE` §5's O(visible) rule.

**UI-017 · No lists are sortable, filterable or searchable.** Routes, Fleet,
Competitors, the 80-airport pickers, the 14-aircraft market. At mid-game scale
every one of these becomes unusable.

**UI-018 · No aircraft detail screen.** `reliability` and `totalFlightHours`
are computed in Core and shown nowhere; there is no utilisation, no
maintenance view, no registration, no history.

**UI-019 · No airport browser.** 80 airports, reachable only by finding a
2–6 pt dot on the map. No list, no search, no comparison, and no way to see
demand, fees or competition before committing to a market.

**UI-020 · Raw enum vocabulary on screen.** `northAmerica`, `southeastAsia`,
`large` (runway), `empire` (era, lowercase mid-sentence), archetype raw values,
`Strike at airline #3` (an internal id where a name belongs), and "until day
4271" where a date belongs (`Format.date` exists).

**UI-021 · Loans addressed by array index across a render boundary.**
`FinanceView.swift:313` pairs `ForEach(enumerated())` with
`RepayLoanCommand(loanIndex:)`; if the simulation removes a loan between render
and tap, the wrong loan is repaid.

**UI-022 · Empty and loading states are incomplete.** `ProgressView()` with no
context on five screens. `WorldEventsView` puts an `EmptyStateView` inside a
`List` row. `CompetitorsView`, `ProgressionView` (Achievements) and the
statement card have no empty state or a bare sentence.

**UI-023 · There are no settings.** No sound, haptics, auto-pause (specified in
`CORE_LOOP` §2), confirmation, accessibility, about, credits, privacy link, or
reset. No `@AppStorage`/`UserDefaults` in the app at all.

**UI-024 · No forward hook.** `deliveryLeadDays` is known, aircraft on order
have a status, missions have deadlines, seasons turn — and no screen ever says
"your aircraft arrives Tuesday". `PLAYER_JOURNEY` §2 makes this the session-exit
beat.

### P3 — low

**UI-025** Only three of 80 airports can be a home (`CuratedStart.all`),
capping openings at three.
**UI-026** No livery colour (`GAME_DESIGN` §4.1).
**UI-027** `NewGameView` forces `.preferredColorScheme(.dark)`, so a light-mode
player gets a hard flash into a light Dashboard on Found.
**UI-028** `AETheme.cornerRadius` is 14 but every card writes `+ 4`; the token
is not the truth.
**UI-029** Five ad-hoc badge colours outside the token set.
**UI-030** `AESectionHeader` used once; fourteen hand-rolled headings elsewhere.
**UI-031** `Format.money` has no grouping separators below ¤10 k ("¤9999") and
hardcodes `¤` and U+2212.
**UI-032** Map airport codes at 9 pt with no collision avoidance.
**UI-033** No launch screen content — `UILaunchScreen_Generation: YES` yields a
blank field, wasting the first second of every session.
**UI-034** `dangerZone(_:player:)` ignores its `card` parameter; the destructive
card has no heading.
**UI-035** No save-slot management (rename, delete, multiple manual slots); the
`auto` slot is indistinguishable from any other.
**UI-036** Zero localization readiness (§10) — every string a literal.

---

## 13. Prioritized action list

**Sprint 1 — make the game playable and honest (P0)**
1. UI-001 Restructure to ≤ 5 tabs; move save/quit out of the World hub.
2. UI-004 Move rejection presentation to `RootView` **and** into each sheet;
   stop dismissing sheets on rejection.
3. UI-002 Show month-to-date route economics beside last month.
4. UI-003 Render `flightDeparted`/`flightArrived` for the player's flights;
   announce first revenue.
5. UI-005 Solvency warning banner + day countdown + auto-pause on entering the
   danger window + an administration summary screen.

**Sprint 2 — make actions safe and legible (P1)**
6. UI-006 Confirmation + cost context + disabled states on every money action;
   put cash on the aircraft shop.
7. UI-007 Replace `MonthlyBars` with Swift Charts; add axis, labels, values.
8. UI-008 Player-facing names, descriptions, costs, durations and progress for
   capabilities, milestones and achievements; show the next era's gates.
9. UI-012 Surface save success and failure; read `lastSaveError`; replace
   `assertionFailure` with a real error path.
10. UI-010 Put `SpeedControl` and the date on every primary screen.

**Sprint 3 — make the map the hero (P1)**
11. UI-009 Land and coastline; home marker; legend; tap-to-select a route or
    flight; **open a route from the map**; zoom controls and fit-to-network.
12. UI-016 Cache the map model and route arcs; stop rebuilding O(world) per
    frame.
13. UI-011 Causes on events; "affects N of your routes"; make feed rows tappable
    (introduce `AppRoute`/`NavigationPath`).

**Sprint 4 — depth and platform (P1–P2)**
14. UI-013 `NavigationSplitView` for iPad.
15. UI-018/019 Aircraft detail screen; airport browser with search and
    comparison.
16. UI-017 Sort/filter/search on every list; bulk actions.
17. UI-014 Celebration moments, `HapticService`, `AudioService`.
18. UI-015 One visual language: `aeScreenBackground()` and glass in every sheet.

**Sprint 5 — polish and readiness (P2–P3)**
19. UI-023 A real settings screen, including auto-pause.
20. UI-020 A player-facing vocabulary layer for every enum that reaches a
    screen.
21. UI-024 Forward hooks (deliveries, seasons, mission deadlines).
22. UI-036 Localization pass before the string count doubles.
23. Accessibility pass: map VoiceOver elements, 44 pt audit, Dynamic Type at
    XXL, explicit Reduce Motion.

**Never before the above:** hubs, new mission kinds, revenue management.
Adding systems to a client that cannot yet explain the ones it has makes the
product worse.

---

## 14. Recommendations for next prompts

Each of these is scoped to be a single focused session with a testable outcome.

- **Prompt 02 — Navigation & shell.** Restructure to ≤ 5 tabs; introduce
  `AppRoute`/`NavigationPath` as a value; move rejection presentation to the
  root; put time control and date on every screen; `NavigationSplitView` for
  iPad. (UI-001, 004, 010, 011, 013)
- **Prompt 03 — The failure journey.** Solvency banner and countdown,
  auto-pause policy, administration summary screen, route-triage view,
  emergency toolkit, and a real game-over score screen with the cause chain
  and a same-seed aftermath hook. (UI-005, §4.2)
- **Prompt 04 — Explainability pass.** Month-to-date route economics, tappable
  stat tiles that open their explanation, demand and competitor context on the
  route screen, Swift Charts for finance, cash-runway forecast. (UI-002, 007,
  and `UI_ARCHITECTURE` §6)
- **Prompt 05 — The map becomes the hero.** Land, home marker, legend,
  selection of routes and flights, open-route-from-map, zoom controls,
  fit-to-network, cached geometry, weather overlays, VoiceOver elements.
  (UI-009, 016, and accessibility)
- **Prompt 06 — Safe, informed transactions.** Confirmation and cost context on
  every money action; disabled states; sheets that survive rejection; the
  aircraft market as a comparable table with your cash on screen. (UI-006, 015)
- **Prompt 07 — Player-facing language.** A presentation vocabulary for every
  enum, milestone and achievement; capability descriptions with cost, duration
  and progress; era gates made visible; regions, runways and archetypes named
  in English. (UI-008, 020)
- **Prompt 08 — Feel.** `HapticService` and `AudioService` keyed off
  `SimEvent`; celebration moments for milestones, eras, deliveries and first
  profit; launch screen; empty/loading/error state completion. (UI-014, 022,
  033)
- **Prompt 09 — Art direction (Phase 17).** Aircraft silhouettes, category
  glyphs, an accent identity built from the dusk palette rather than system
  blue, map cartography, and the 60 pt icon test.
- **Prompt 10 — Accessibility, Dynamic Type and localization.** The 44 pt
  audit, XXL layout pass, map VoiceOver, explicit Reduce Motion, and the string
  catalogue before the string count doubles. (UI-036, §10)

---

## 15. Risks

| Risk | Severity | Note |
|---|---|---|
| **Everything visual is still unproven** | **High** | The app compiles and has reached the first screens on one device. Rendering, layout, gestures, size classes, Observation behaviour, scene-phase autosave, accessibility and performance are all unvalidated. Every `[device]` finding here — including UI-001 and the map gesture conflict — needs a screen to confirm, and there may be more that no amount of reading finds |
| **Tab overflow may hide half the game from every reviewer** | **High** | If UI-001 is confirmed, a first-time player and an App Review tester both meet a *More* list where the money screen should be |
| **Failure has no UI, and failure is the designed dramatic arc** | **High** | A player who loses without warning concludes the game is unfair, which is the exact opposite of pillar 2's "never unfairly: every consequence is traceable" |
| **The first five minutes under-deliver against their own script** | **High** | No starter aircraft, no flight narration, no celebration, and a zeroed P&L. This is the retention-critical window |
| **O(world)-per-frame rendering** | **Medium** | Fine at 10 routes, unmeasured at 100. Needs Instruments before any claim |
| **Map gestures may not compose** | **Medium** | Two `.gesture` modifiers; likely only the last applies. The map is the centerpiece |
| **Zero localization readiness** | **Medium** | Cost grows with every string added; cheapest now |
| **Destructive actions without confirmation** | **Medium** | Selling an aircraft by mis-swipe is unrecoverable and will generate support mail and one-star reviews |
| **Photographic app icon at 60 pt** | **Low–Medium** | Already flagged in the repo; needs a home-screen test |
| **Three curated starts cap replayability** | **Low** | On a world of 80 airports |

---

## 16. Conclusion

Airline Empire is two projects at very different stages of maturity sharing a
repository, and the honesty of its own documentation is one of its best
qualities — `CURRENT_PHASE.md` says "COMPILED · NOT APPLE-RUNTIME-VALIDATED",
and that is exactly right.

The simulation is finished work: deterministic, save-safe, explainable
end-to-end, 257 tests, a bug register that names root causes and fix layers
rather than symptoms. The architectural seam between Core and the client is
the reason a UI audit is even possible — every number a screen shows is a Core
read model, tested headlessly, so the client's problems are entirely problems
of *presentation and interaction*, never of truth. That is a very good place to
be in.

The client is at the stage where the data has been put on screen and the
product work has not yet started. Five things separate it from being a game
people love rather than a simulation people respect:

1. **The player must always know where they stand** — including, above all,
   when they are in trouble. Right now the game runs a silent countdown to
   the player's destruction.
2. **Every action must be safe to take and clear before it is taken** — cost,
   consequence, confirmation, and a failure the player can see and recover
   from.
3. **Every consequence must be traceable to its cause** — the pillar this
   project already believes in, implemented in Core, and not yet carried
   through to a single screen that lets you tap a number to find out why.
4. **The map must be the hero it is designed to be** — with a world under it,
   a home on it, and something to do from it.
5. **Growth must feel like something** — a first flight that is narrated, a
   milestone that is celebrated, a delivery that is anticipated.

None of that requires new simulation. Almost all of it is already computed and
sitting unread in the snapshot: this month's route economics, the insolvency
countdown, era gate thresholds, capability costs and completion dates, live
flight counts, active event counts, aircraft reliability and hours, today's
demand pool. The work ahead is not building systems. **It is showing the
player what the game already knows.**

---

*Audit performed 2026-08-29 against `f771257`. Analysis only — no application
code was modified.*
