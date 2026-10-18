# Whole-game audit — 18 October 2026

**State.** Latest code is `main` @ `eb85cd4` (PR #51). App Store: **1.2.1 live since
16 Oct**. CI on `main` green, no open PRs. Four static audits (simulation, screens,
3D hub, release/CI) plus the iPhone Duo work on `claude/iphone-duo-support`.
No P0 crash found. Paths: `Core/` = `AirlineEmpireCore/Sources/AirlineEmpireCore/`,
`App/` = `AirlineEmpireApp/Sources/`. Minutes are estimates.

## 0. Do first

| # | What | Where | Min |
|---|---|---|---|
| 1 | Pin `ubuntu-24.04`: `ubuntu-latest` moves to Ubuntu 26 on 19 Oct and runs the App Store tooling | `app-store-metadata.yml`, `ios-testflight.yml:92,657`, `ci.yml:83,189,292` | 15 |
| 2 | Long-haul aircraft assigned to a route it can never fly: range passes, 0 round trips fit the 1,080-min day, costs keep billing | `Core/Simulation/RouteCommands.swift:279`, `Core/Session/AssignmentEligibility.swift:160`, `Core/Systems/FlightSchedulingSystem.swift:52` | 30 |
| 3 | Administration only sells *unassigned owned* aircraft, never returns leases — a normal fleet collapses the same day, no second chance | `Core/Systems/EconomySystem.swift:108-121` | 60 |
| 4 | Physical-device session: purchase/restore/grace/offline relaunch + hub performance (never done) | `tasks/RELEASE_CHECKLIST.md` §E | 90 |
| 5 | Confirm RevenueCat receives production purchases since 16 Oct | `docs/REVENUECAT_SETUP_2026-09-23.md:41` | 15 |

## 1. iPhone Duo

Done on the branch (`docs/IPHONE_DUO.md`): window-sized hub inspector, slim hub chrome
under 700 pt, landscape lock only on narrow windows, camera reframes on fold, shell keeps
its tab bar through a fold, Duo layout tests, `xcode: 27.1` + `duo` CI lanes, TestFlight
`xcode: 27.1`. **The app compiles with Xcode 27.1 / iOS 27.1 SDK** (run 39133562645).

| # | To do | Min |
|---|---|---|
| 1 | Read the Duo simulator lane result and `DUO-*` screenshots; fix what they show | 30 |
| 2 | Fold/unfold by hand in the Xcode 27.1 Duo simulator: open sheet, route draft, hub upgrade card | 30 |
| 3 | Merge the branch; ship the next version with `ios-testflight.yml xcode=27.1` | 15 |
| 4 | Store screenshots 1398×2034 (outer) and 2007×2853 (inner) in `scripts/store-art/showcase.cjs` — **required from April 2027** | 90 |
| 5 | Hub framing still reserves the right 24 % for a hidden inspector (`Core/Session/HubFraming.swift:52`); upgrade card covers its site in portrait (`App/Hub/HubScene.swift:378`); three size rules to unify (`HubChromeMode`, `HubFraming.swift:149`, hard-coded chrome heights) | 180 |

## 2. Gameplay and simulation bugs (P2)

| # | Bug | Where | Min |
|---|---|---|---|
| 1 | Demand rewards *requested* frequency, not trips flown; rivals raise frequency without capacity and hoard airport slots | `Core/Systems/DemandSystem.swift:210`, `CompetitorAISystem.swift:519` | 45 |
| 2 | Empty routes count as network: unlock eras, crash rival fares, inflate reputation for $15k/month | `Core/Domain/EraGate.swift:74`, `ReputationSystem.swift:49`, `CompetitorAISystem.swift:500` | 45 |
| 3 | Boom-rush mission progress drops to 0 when a route closes — mission can become unwinnable | `Core/Domain/MissionMath.swift:16-42` | 45 |
| 4 | Commands queued while running are not flushed on pause/save: double purchases, lost commands | `Core/Session/GameSession.swift:177,228` | 30 |
| 5 | Save loader never checks aircraft/airport codes exist; 21 force-unwraps → crash after a content rename (latent P0) | `Core/Persistence/SaveEnvelope.swift:79`, e.g. `FlightOpsSystem.swift:41` | 60 |
| 6 | Global `rankingBasis` flipped by a test while suites run in parallel (data race, flaky tests) | `Core/Systems/CompetitorAISystem.swift:330` | 30 |
| 7 | Event feed (512) and ledger (1,024) rings shared by all airlines push the player's own events out (TD-032) | `Core/Simulation/SimEvent.swift:87`, `Domain/Ledger.swift:6` | 120 |
| 8 | Rival estimator gaps TD-026/035/036: rivals misprice and never enter European starts | `Core/Systems/CompetitorAISystem.swift:217,353,632` | 300 |

## 3. Screen bugs (P2)

| # | Bug | Where | Min |
|---|---|---|---|
| 1 | Music stays silent after AirPods connect/disconnect until the app is backgrounded | `App/Audio/AudioEngine.swift:248`, `Feedback.swift:253` | 20 |
| 2 | Tapping a *rival's* route opens "Route closed" and advises lowering their fare | `App/Map/MapSelectionCards.swift:303` | 10 |
| 3 | Open a route → aircraft → its route: dead link (no `RouteID` destination) | `App/Screens/RoutesView.swift:914` | 5 |
| 4 | iPad: shell rebuilds on every Split View resize (iPhone fixed on the Duo branch) | `App/Screens/RootView.swift:223` | 45 |

## 4. 3D hub performance (risk on A12, 3 GB devices)

| # | Problem | Where | Min |
|---|---|---|---|
| 1 | Whole hub (≈46 USDZ) loads on the main thread every open, no cache | `App/Hub/HubAssetLibrary.swift:37`, `HubModels.swift:21` | 150 |
| 2 | Up to 300 people re-posed on the CPU every frame in the terminal shot | `App/Hub/HubCrowd.swift:285`, `HubDynamics.swift:1037` | 75 |
| 3 | No jet LOD; ~22 full jets + shadows ≈ 350k triangles vs 250k budget | `App/Hub/HubDynamics.swift:402`, `Core/Session/HubSnapshot.swift:302` | 120 |
| 4 | Idle turntable never stops: labels re-layout 60×/s forever, phone heats | `App/Hub/HubScene.swift:554` | 45 |
| 5 | Bloom on every device; hub switch renders two 3D views at once | `App/Hub/HubScene.swift:254`, `HubScreen.swift:41` | 45 |

Also: route pulses uncapped (240 entities at 60 routes, `HubDynamics.swift:835`, 20 min);
labels block pan/pinch (`HubScreen.swift:381`, 60 min); stuck spinner with no close button
if data is not ready (`HubScreen.swift:72`, 10 min).

## 5. Store, privacy, CI

| # | Item | Where | Min |
|---|---|---|---|
| 1 | Release Xcode not pinned: build 17 used runner default 26.6, validation 26.2 | `ios-testflight.yml:261`, `ci.yml:494` | 10 |
| 2 | Privacy policy omits Game Center (scores/achievements go to Apple) | `site/privacy.html:10` | 15 |
| 3 | Grace-period subscribers lose Pro when launching offline | `App/Monetization/Entitlements.swift:297-306` | 30 |
| 4 | Intro-offer sentence hard-codes the current offer shape (3.1.2 risk if changed) | `Entitlements.swift:453`, `PaywallContent.swift:163` | 30 |
| 5 | Paywall UI test flaky (`FreeTierUITests.swift:49`, TD-037) | — | 20 |

Also: restore says "no purchase found" to lapsed subscribers (`PurchaseFeedback.swift:92`, 20);
"Manage subscription" opens a web URL (`ProLock.swift:153`, 10); actions on Node 20 → v5 (15);
`aircraft-configuration.yml` still triggers on a dead branch (5).

## 6. Polish (P3)

- **Simulation:** flight contract pays $45k/aircraft/month for a week of normal flying (`ContractCommands.swift:30`); loan charges a full month on day one (`EconomySystem.swift:41`); boom-rush target assumes 150 seats (`ProgressionSystem.swift:210`); `weatherProof` gamed by closing routes (`:150`); cancelled flights keep sold demand (`FlightOpsSystem.swift:78`); storm breaks the regional-event cap (`WorldEventSystem.swift:63`); own sales/lease returns missing from feed (`FleetCommands.swift:282`); BUG-061 "next morning" lands at 00:00 (`GameSession.swift:216`).
- **Screens:** Reduce Motion ignored by card slides (`MapView.swift:513`); route/flight cards break at AX3+ (`MapSelectionCards.swift:287`); Game Center cancel shown as "unavailable" (`GameCenter.swift:86`); briefing: rival good news under "Needs you now", duplicate row IDs, idle count ignores ordered aircraft, market scan run twice (`BriefingView.swift:236,867,795,806`); raw Core error text (`RouteManagementView.swift:295`); small tap targets (`AirportManagementView.swift:70`); "1 days" (`AirportServiceEditor.swift:107`); rescue terms typed by hand (`RescueOfferCard.swift:13`); backups overwritten on every `.inactive` (`AirlineEmpireApp.swift:76`); import on main thread (`GameController.swift:611`); stale-frame refresh race (`GameController.swift:1149`); route rows not combined for VoiceOver (`RoutesView.swift:177`); coastline parse hitch (`WorldGeometry.swift:100`).
- **Hub:** labels overlap chrome (`HubScene.swift:664`); per-frame allocations (`HubScene.swift:668`, `HubCrowd.swift:299`).
- **Build:** 8 warnings on Xcode 27.1, incl. a Swift 6 isolation error-to-be in `App/Audio/Feedback.swift:303`.
- **Tests to add:** administration with an assigned fleet; zero-rotation route; queued command + pause; boom rush after a route closes; audio restart; rival route card; iPhone rotation keeping map state.

## 7. Not built yet

1. Hub Phase D (dedicated pier) and Phase E (hub designation, transfer centre, connecting demand) — `docs/HUB_PROGRESSION_PLAN.md` §5. ~4 h + ~15 h.
2. Hub step 5 SSAO, step 6 device performance pass + LODs, step 7 owner sign-off.
3. 18 listed hub models with no file and no slot (`App/Hub/HubSceneBuilder.swift:38-71`): terminal_pavilion, boxTruck, staff, metal detector, stanchions, pharmacy, gondola, café counter, trolley, electric cart, plant pot, barrier, wheel chock, GPU, apron mast, guardhouse, street lamp, path light.
4. Hub moments: audio, map status badge, Insights hub report, "while you were away".
5. Capped offline catch-up; route opening dates (TD-027); split the ten-year test out of the main CI job (TD-034).

## 8. Owner decisions

- Terminal congestion (§9.5), lounge → comfort reputation (§9.7), Game Center re-pointing (§9.8) — `docs/HUB_PROGRESSION_PLAN.md`.
- When to switch releases to Xcode 27.1 (needed for iPhone Duo).

## 9. Repo hygiene

- Main checkout `C:\Users\IsacC\Airline-Empire` is on dead branch `codex/ae049-aircraft-configuration`, 134 behind `main`. Its uncommitted app changes are already in `main`; **not** in `main`: launch-clip path fix (`store/launch/*`) and 13 untracked docs. Archive those, then switch to `main`.
- 38 of 41 remote branches are merged into `main`; delete them.
- Stale trackers: `tasks/TODO.md` (1.2.1 release done, AUD-04 done, old CI items), `RELEASE_CHECKLIST.md:50` ("Data Not Collected"), `store/release-plan.json` (PRE_ORDER), `TECH_DEBT.md` (TD-016 obsolete), `BUGS.md` (BUG-055 listed twice; BUG-056 UI half fixed).
