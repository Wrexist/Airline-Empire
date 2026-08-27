# Apple Validation — handoff for the first Mac/Xcode session

**Status of this document: nothing in it has been executed.** All development
so far has run on Linux, where the Apple SDKs do not exist. Every step below
is *pending*, and the app target's honest status is:

> **AUTHORED · PARSED · STRUCTURALLY VALIDATED · READY FOR XCODE ·
> NOT APPLE-RUNTIME-VALIDATED**

What *is* proven, on Linux: the simulation core (`AirlineEmpireCore`) builds
clean in debug and release, its full test suite passes, the release benchmark
meets budget, and the App↔Core data contracts are covered by tests
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

## 2. Build

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

## 5. Known Apple-specific validation gaps

Everything here is unproven on Apple platforms and must be checked by hand:

| Area | Why it is unknown on Linux |
|---|---|
| SwiftUI compilation | No Apple SDK; only `swiftc -parse` (syntax) has run |
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

Most recent Linux run (2026-08-26, Swift 6.0.3, debug tests / release bench):

| Metric | Result |
|---|---|
| Core test suite | **251 tests, all passing** (~6 min; the per-tick integrity assert dominates and is compiled out in release) |
| Release build | clean, no warnings |
| 2 airlines × 5 routes, 1 game-year | 0.37 s |
| 4 airlines × 15 routes, 1 game-year | 1.39 s |
| 8 airlines × 25 routes, 1 game-year (200 aircraft, 200 routes) | **3.02 s** (budget 10 s) |
| Save size at that scale | 607 KiB |
| Save encode / decode | 0.04 s / 0.03 s |

On macOS the same commands should pass; absolute timings will differ with
hardware. A *failure* here means the checkout or toolchain is wrong — fix that
before starting Xcode work.

## 8. Release checklist (Phase 23 — none of it done)

- [ ] Clean build from a fresh clone, release configuration
- [ ] Zero warnings
- [ ] Run on a physical iPhone and iPad
- [ ] Airplane-mode run: the game must be fully playable offline
- [ ] Cold launch time measured
- [ ] Instruments: Time Profiler on a large world; Allocations over a long run
- [ ] Memory ceiling checked on the oldest supported device
- [ ] Accessibility: VoiceOver pass, Dynamic Type at largest size, contrast
- [ ] Save/restore across an app update (install over a previous build)
- [ ] App icon, launch screen, screenshots
- [ ] Bundle identifier, version, build number
- [ ] Signing and provisioning
- [ ] Privacy manifest — the app collects nothing and makes no network calls
- [ ] App Store metadata, age rating, description
- [ ] `RELEASE_CHECKLIST.md` and `KNOWN_LIMITATIONS.md` written from the
      results of the above

## 9. Rule for this document

Update it with what actually happened, and never mark a step done that was not
run. "Linux validated" and "Apple validation pending" are different words on
purpose.
