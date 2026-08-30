# Apple Validation — handoff for the first Mac/Xcode session

**Status of this document: §2 has now been executed; nothing else has.** On
2026-08-28, CI run 33213797384 compiled the app with `xcodebuild` on a
`macos-26` runner — `** BUILD SUCCEEDED **`, Xcode 26.6, iPhoneSimulator 26.5
SDK. Everything from §3 onward (simulator, walkthrough, Instruments,
accessibility, signing) is still *pending*, and the app target's honest status
is:

> **COMPILED · NOT APPLE-RUNTIME-VALIDATED**

A compiler proves the code type-checks and links. It proves nothing about what
appears on a screen, which is the whole of §3 to §5 below.

What *is* proven, on Linux: the simulation core (`AirlineEmpireCore`) builds
clean in debug and release, its full test suite passes, the simulation scales
linearly with network size, and the App↔Core data contracts are covered by tests
(`ScreenContractTests`, `PlayerJourneyTests`). What is *not* proven: that
SwiftUI compiles, renders, or behaves correctly on a device. Those are
different claims and this project does not conflate them.

---

## 1. Generate the Xcode project

```sh
brew install xcodegen
cd AirlineEmpireApp
xcodegen generate          # reads project.yml → AirlineEmpire.xcodeproj
open AirlineEmpire.xcodeproj
```

`project.yml` declares an iOS 17 application target named `AirlineEmpire`,
device family `1,2` (iPhone + iPad), sources in `Sources/`, and a local
SwiftPM dependency on `../AirlineEmpireCore`. `GENERATE_INFOPLIST_FILE` is on
because the target configures itself through `INFOPLIST_KEY_*` build settings
rather than a checked-in `Info.plist`.

## 2. Build — done, 2026-08-28

`.github/workflows/ci.yml` does this on every commit that touches the app or
the core, so it need not be redone by hand; run 33213797384 was the first and
it passed with no source changes. The paragraph below is kept for the local
case, and because its expectation was worth recording: it predicted
SDK-specific errors, and there were none.

Expect first-build errors to be **Apple-SDK-specific**, not logic errors:
SwiftUI API availability, `#if os(iOS)` gaps, toolbar/navigation API
differences, and Swift 6 actor-isolation diagnostics that only the real
compiler can raise. The Core APIs the views call have been verified to exist
with the right signatures and access levels by inspection (see §6), so
unresolved-symbol errors against `AirlineEmpireCore` would be surprising —
investigate rather than paper over.

Fix compile issues **in the App layer**. Reaching into Core to satisfy a view
is almost always the wrong layer; the one legitimate case so far was an access
level (`BUG-001`).

Target: **zero new warnings.**

## 3. Run the simulator

`⌘R` on an iPhone 15 (or later) simulator, then an iPad simulator.

## 4. What to test — the walkthrough

This is the same journey `PlayerJourneyTests.firstSessionReachesProfitableOperations`
proves at the Core level. Runtime validation is checking that the *UI* honours
it.

1. Launch → New Game screen appears.
2. Name an airline, pick a curated start, pick a difficulty, note the seed.
3. Found the airline → Dashboard appears with the **onboarding card** showing
   "Get an aircraft" as the next step.
4. Fleet → Acquire → buy a **used** aircraft (new ones are orders with a
   delivery lead time; the shop says so).
5. Dashboard → onboarding advances to "Open your first route" and shows two
   demand-ranked suggestions. Tap one → the route sheet opens **pre-filled**.
6. Open the route → Routes tab lists it with an "no aircraft" warning badge.
7. Route detail → **Aircraft** card → "Assign an aircraft" → pick the idle
   aircraft. (This path did not exist until BUG-002; verify it works.)
8. Set speed 1× → the map shows the aircraft moving; the feed narrates
   departures/arrivals.
9. Advance to a month boundary → a statement closes; Finance shows the bar
   chart and category rows.
10. Confirm the feed shows **only your** airline's business plus world news
    and rivals' collapses — never a rival's statement or loan (BUG-004).
11. While running at 4×, submit an impossible command (buy an aircraft you
    cannot afford) → an alert must appear (BUG-005: this used to fail
    silently).
12. Dashboard shows a **"Yesterday"** digest card once a day has closed; tap **Why?** for the category breakdown.
13. Settings → Save now → **Save and quit to menu** → Continue → load the
    save → the game resumes with the same date, cash, and network.
14. Background the app (⌘⇧H) and return → autosave fired, pumping resumed.
15. Play until collapse (or force it) → Game Over screen → **"Start a new
    airline"** returns to the menu (BUG-003: this used to be a dead end).

## 4b. What the 2026-08-29 UI pass added to the walkthrough

`docs/UIUX_FORENSIC_AUDIT.md` rebuilt most of the client. The §4 script still
holds; these are the claims it does not yet cover, each one a `[device]`
prediction in the audit:

1. **Five tabs render as five** — Home, Map, Network, Finance, World, with no
   *More* item. This is BUG-009's fix and the single most important thing to
   look at first.
2. **Network's segmented switch** moves between Routes and Fleet without
   losing a pushed detail screen.
3. **iPad** shows a sidebar (`NavigationSplitView`), not a phone tab bar, in
   both orientations and in Slide Over. (§5's older note that the app is
   `TabView`-only, with no sidebar, describes the state before this cohort.)
4. **The map**: coastlines draw, home is ringed in amber, the view opens on
   the player's own airport, pinch *and* drag both work (they are composed
   with `SimultaneousGesture` — the old code attached two `.gesture`
   modifiers, the second replacing the first), the zoom buttons and
   fit-to-network behave, and a tapped airport can open a route.
5. **Frame cost**: the map model is cached per tick now. Profile a large
   network at 16× and confirm the Canvas is not the bottleneck.
6. **Swift Charts** lays out inside its card at every Dynamic Type size.
7. **Solvency**: drive an airline below the overdraft floor and confirm the
   banner escalates, the countdown counts, and fast-forward auto-pauses once
   and says why.
8. **Rejections**: with a sheet open (aircraft market, route sheet, loan
   desk), attempt something the simulation refuses. The control should already
   be disabled with the reason under it; if one slips through, the alert must
   appear *over* the sheet and the sheet must keep its inputs.
9. **Accessibility**: VoiceOver over the map summary, the 44pt audit on the
   `.caption`-sized bordered buttons, and Dynamic Type at XXL on the
   progression and route screens.

## 5. Known Apple-specific validation gaps

Everything here is unproven on Apple platforms and must be checked by hand:

| Area | Why it is unknown on Linux |
|---|---|
| ~~SwiftUI compilation~~ | **Answered.** CI run 33244671402, 2026-08-29, `** BUILD SUCCEEDED **`. Note what a parse does *not* buy: the run before it found five type errors `swiftc -parse` cannot see |
| Rendering and layout | No renderer; no device, no size classes |
| iPad layout | `TabView` only — no sidebar/split layout authored yet |
| `Canvas` map performance | `MapModel` math is tested; drawing cost is not |
| Gestures | Drag/magnify/tap on the map are unexercised |
| `@Observable` update behaviour | Observation registration is compile- and runtime-dependent |
| Actor hops / MainActor | Static review only; no TSan, no real scheduler |
| Scene phase + autosave | `scenePhase` transitions cannot be simulated here |
| Accessibility | Labels authored; VoiceOver, Dynamic Type, contrast unverified |
| Haptics and sound | Not implemented at all |
| Signing, entitlements, App Store | Never attempted |

## 6. What was verified statically (so you can skip re-deriving it)

- Every Swift source in `AirlineEmpireApp/` passes `swiftc -parse`.
- Every Core symbol the App references was checked against the package:
  command initializers and argument labels, read-model field names, enum case
  arities in `switch` patterns, catalog accessors, and hard-coded content
  codes (`STV`, `LNW`, `BCM`, `SGM` all exist in `airports.json`).
- All 15 player-facing commands are reachable from some screen (audited by
  enumeration, not assumption — this is how BUG-002 was found).
- Screen data contracts are covered by `ScreenContractTests`: for Dashboard,
  Route detail, Fleet, Finance, Map, and the World screens, the read models
  supply every field the view renders, on a real mid-game world.
- No network dependency exists anywhere in Core or App (offline-first).
- Concurrency hygiene: no `DispatchQueue`, `@unchecked Sendable`, detached
  tasks, timers, or mutable global state in the App; all `Task` creation is
  in the `@MainActor` composition root (`GameController`).

The full picture of what is proven versus assumed is in
`docs/LINUX_QA_AUDIT.md` — read it before deciding where to spend the first
hours of Xcode time.

## 7. Expected test results

Run before touching anything, to establish that the checkout is sound:

```sh
cd AirlineEmpireCore
swift test                    # expect: all tests pass, 0 failures
swift build -c release        # expect: clean
swift run -c release ae-bench # expect: numbers in the table below
```

Most recent Linux run (2026-08-27, Swift 6.0.3, debug tests / release bench):

| Metric | Result |
|---|---|
| Core test suite | **253 tests, all passing** (the per-tick integrity assert dominates and is compiled out in release) |
| Release build | clean, no warnings |
| 8 airlines × 25 routes, 1 game-year (200 aircraft, 200 routes) | 3.02 s on a fast container, 13.9 s on a slow one — same commit, same entity counts |
| Save size at that scale | 605 KiB |
| Save encode / decode | ~0.05 s / ~0.03 s |

On macOS the same commands should pass; absolute timings will differ with
hardware. A *failure* here means the checkout or toolchain is wrong — fix that
before starting Xcode work.

**Treat the bench seconds as relative, not absolute.** The same commit
measured 3.02 s and 13.7 s for the 200-route case a few hours apart in this
Linux container, with identical entity counts — the machine's available CPU
changed, the code did not. Verified by benching the unchanged commit
back-to-back against the modified tree (13.71 s vs 14.03 s: noise). So use
the bench to compare *two builds on one machine in one sitting*, which is
what catches a real regression; never to certify an absolute budget. The
only budget that matters is measured on a device, and that is Apple work
(§8, Instruments).

## 8. Release checklist (Phase 23 — none of it done)

Since 2026-08-28, several of these have machinery behind them rather than only
a checkbox: CI compiles the app on a macOS runner
(`.github/workflows/ci.yml`), `.github/workflows/ios-testflight.yml` archives,
signs and uploads a build, and the store listing lives in `/store` with its
own validator. What that machinery has never done is *run* — see
[`RELEASE_PIPELINE.md`](RELEASE_PIPELINE.md), which tracks exactly which paths
have been executed. The rows below stay unticked until someone ticks them from
a run.

- [ ] Clean build from a fresh clone, release configuration
- [ ] Zero warnings
- [ ] Run on a physical iPhone and iPad
- [ ] Airplane-mode run: the game must be fully playable offline
- [ ] Cold launch time measured
- [ ] Instruments: Time Profiler on a large world; Allocations over a long run
- [ ] Memory ceiling checked on the oldest supported device
- [ ] Accessibility: VoiceOver pass, Dynamic Type at largest size, contrast
- [ ] Save/restore across an app update (install over a previous build)
- [ ] App icon, launch screen, screenshots — **the icon and screenshots do not
      exist**; the slot and the brief do (`AirlineEmpireApp/Resources/README.md`,
      `docs/ASO.md` §5–6)
- [ ] Bundle identifier, version, build number — pinned in `project.yml`
      (`com.airlineempire.game`), with the build number resolved from App Store
      Connect at release time (`scripts/asc/next-build-number.mjs`)
- [ ] Signing and provisioning
- [ ] Privacy manifest — written and bundled
      (`AirlineEmpireApp/Resources/PrivacyInfo.xcprivacy`): nothing collected,
      nothing tracked, no required-reason APIs, each claim derived from the code
- [ ] App Store metadata, age rating, description (written: `/store`,
      `docs/ASO.md`, `docs/APP_STORE_CONNECT.md` §6–7; never pushed)
- [ ] `RELEASE_CHECKLIST.md` and `KNOWN_LIMITATIONS.md` written from the
      results of the above

## 9. Rule for this document

Update it with what actually happened, and never mark a step done that was not
run. "Linux validated" and "Apple validation pending" are different words on
purpose.
