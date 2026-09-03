# UI runtime validation

**What has actually been run, and what has only been read.**

Every interface claim in this project before AE-031 was authored, not
observed: nothing could boot the app, so "validated" meant "the code compiles
and 412 Core tests pass". This document exists so that distinction is never
blurred again. It records only what a booted simulator has done.

| Mark | Means |
| --- | --- |
| 🧪 | **Asserted** by a UI test against a booted simulator. |
| 👁 | **Observed** — a screenshot from a real render, looked at. |
| 📖 | **Read only** — source, docs, or reasoning. The old standard. |

---

## 1. The harness

`AirlineEmpireUITests` (`AirlineEmpireApp/UITests/`) boots an iPhone
simulator in CI, drives the game, and attaches a screenshot at each step.
Screenshots named with the `KEY-` prefix are also downscaled and base64'd
into the job log, because the result-bundle artifact needs a GitHub
credential the agent doing the interface work does not have (TD-020).

Twenty journeys and two measurements, one device, portrait, across three
shards (run 135). That is the whole of it — small, and worth not overstating:
one simulator, one screen size, and nothing on a physical device.

**The week control (2026-09-03).** Under `-AEUITestSunriseWeek`, which
every journey launches with, the speed bar carries a second control beside
the sunrise, "Advance seven mornings" — seven of the same engine calls a
player's seven taps make, with one screen refresh at the end instead of
seven simulator settles. `advanceMornings(until:)` takes a week whenever
at least seven days remain before its target date and single mornings
after that, so no journey lands past the date it asked for. Before it,
the two long journeys tapped the sunrise about ninety and a hundred and
ten times, each tap several seconds of settling; run 123's UI step took
45 minutes with both on one simulator clone. The player never sees the
control, and the measurement pass opts out of the flag so its numbers
stay comparable with the ones already recorded.

**Three shards (2026-09-03), MEASURED.** The UI job is a three-way
matrix and the split is written down rather than left to xcodebuild:
the campaign journeys on one runner, the economy journeys on another,
both with no simulator cloning at all, and the Munich arrival beside the
shell on a third with two clones and the measurement pass. Three runs
established it:

| Run | Arrangement | Result |
| --- | --- | --- |
| 123 | one job, xcodebuild's own distribution, 2 clones | green in 48 min — three classes (39 min between them) on one clone, the fourth finished and left the other idle for 25 |
| 125 | one job, 3 parallel workers | failed — two of three test runners died before connecting ("Timed out waiting for AX loaded notification"), the survivor starved, seven journeys lost to launch and query timeouts |
| 126 | two named shards, 2 clones each | arrival + shell green in 22 min; campaign + economy starved at 30 min — three journeys on "Timed out while requesting launch progress" and "Timed out while evaluating UI query" |
| 127 | three named shards, no cloning on the two launch-heavy ones | campaign class **186.6 s** (1,225 s in run 123), UI step 6 min 17 s, one real assertion failure; economy shard **green**, UI step 12 min 02 s. No starvation on either: not one launch or query timeout in the whole log |
| 129 | the same three shards, with the two harness costs below fixed | **green — all 19 journeys and both measurements**, and the whole run 28 min 41 s wall clock against run 123's 48. Campaign 6/6 in 909.9 s; economy 4/4 in 457.8 s; the Munich arrival **439.2 s**; the shell class 585.5 s across its clone |
| 131 | main, the AE-040 merge (0579b9f) | UI shards green (arrival 445.3 s; the shell class 640 s across its clone); the Core job red on a time limit — `regionalRivalKeepsMoneyInTheStandardCast` past 300 s on the parallel runner, the same code green in run 130 |
| 132 | AE-041 (a2e8681), dispatched by hand | campaign 6/6 (23 min 50 s), economy 4/4 (17 min 19 s), Core 451/451 in 28 min 09 s — and then the Core job's release build cancelled by the job's 30-minute limit; the arrival + shell shard starved: "Timed out while synthesizing event" on the Munich journey's first search-field tap on day 1, two shell tests on AX/query timeouts, `testDetailScreensAndSettingsRender` 523 s against 101 s in run 131. No product change is on that path before day 61. Core timeout raised to 45 (measured, docs/AE041_PROFIT_VS_REVENUE_REPORT.md §11.1); one redispatch |
| 133 | AE-041 with the core timeout at 45 (489f8fd) | **green — all 19 journeys and both measurements, Core 451/451 in 26 min 40 s with the release build clean, 28 min 33 s wall clock.** Campaign 6/6 in 802.1 s (the regional-era journey 674.5 s); economy 4/4 in 560.8 s; the Munich arrival **475.1 s**; the shell class 8/8 across its clone. The HORIZON-KEY frames looked at and unchanged from run 131 (report §8.1) |
| 134 | AE-042 (23f9b75) | **all three shards failed at "Build for the simulator"** in 76-113 s — `DashboardView.swift`, exit 65. One line: `opportunities.contains(\.paysForItsAirframe)`, a key path handed to the unlabeled `contains(_:)`, which takes an *element*, not a predicate. `swiftc -parse`, the only compiler check a Linux session has, accepts it. `scripts/check-app-symbols.mjs` grew a rule for that class (verified by reintroducing the defect); it runs on the 1x runner in milliseconds. One redispatch |
| 135 | AE-042 with the compile fix (2026ab7) | **green — 20 journeys and both measurements, Core 457/457 in 24 min 51 s with the release build clean (48 s, inside the 45-minute limit).** Campaign 6/6 in 856.0 s; economy **5/5** in 1,109.3 s (the new `testNewYorkAdviceIsWorthFollowing` 558.9 s); arrival + shell 9/9 on the re-run, the Munich arrival **471.9 s**. Attempt 1's arrival shard failed `testARivalComesToMunich()` at 64.7 s — *"the home picker's search field never appeared"*, the same step run 132 lost — but the shell clone was healthy this time (`testDetailScreensAndSettingsRender` 104.2 s against 101 s in run 131), so a single tap that did not take rather than shard-wide starvation. Not the product's: the screen predates any `GameState`, and the same helper founded New York on the economy shard in the same run. One re-run of that shard confirmed it. The AE042-* frames and Munich's KEY-HZ frames looked at (docs/AE042_FINAL_REPORT.md §12) |

What the runners cannot take is simultaneous app launches: the shard
whose second class was a single long journey passed, the shard with ten
launch-heavy tests across two clones did not. So the launch-heavy
classes now get a runner each, and only the pair that proved itself
keeps two clones. Runner speed varies about 1.6× between runs (run 126's
shell class took 818 s where run 123's took 505 s), so any budget has to
survive that.

**The week control, MEASURED.** The Munich arrival went from 981 s
(run 123) to **495 s** (run 126) to **439.2 s** (run 129) and stayed
green — half that journey was simulator settling between sunrise taps.

**Where the remaining time is, run 129 (MEASURED).** The three UI shards
are 19 min 25 s, 16 min 17 s and 19 min 08 s of test step, and the run
finishes in 28 min 41 s. Two things account for nearly all of what is
left, and neither is a shard arrangement:

- **The campaign journey itself: 765.7 s of the campaign shard's
  909.9 s.** It is no longer paying for sunrise taps — 24 single
  mornings and 4 week jumps in the whole journey — but for **1,907
  individual UI interactions** at about 0.4 s each, and its two largest
  single waits are only 34 s and 14 s. No split takes that shard below
  roughly a quarter of an hour; only a shorter journey would.
- **Simulator boot and install, 5–8 min per shard.** On the economy
  shard 8 min 13 s passed between xcodebuild resolving its destination
  and the runner saying "Running tests"; the tests themselves were
  457.8 s. This is `test-without-building` — nothing is compiling in
  that window — so it is runner cost, not test cost, and it is paid once
  per shard. Cloning a second simulator adds roughly four minutes more,
  which is why only one shard clones.

Total macOS work is about 69 minutes over three runners, so a perfectly
balanced three-way split lands near 23 minutes. Going materially below
that needs a fourth macOS shard — at 10× billing, a cost decision, not a
technical one — or a shorter campaign journey. Neither is taken here.

**Two harness costs run 127 exposed, MEASURED.** Neither was an
assertion about the app, and the shard split is what made both legible:

- `foundAirline` opened by asking `waitForTab("Home")` — four
  accessibility queries over the founding screen's hierarchy — to decide
  whether a relaunch had come back into a playing shell. On run 127's
  runner that first poll took **41 s** (t = 9.24 s to t = 50.62 s in the
  log; the cell query 12 s, the static-text query 12 s more) to conclude
  what one query for the new-game screen's own button answers at once.
  The cheap question is asked first now.
- The "World seed" disclosure is the last row of a long scroll, just
  above the pinned Found bar, so the tap has to scroll it into view.
  XCUITest computed the hit point from the frame mid-scroll — `Computed
  hit point {210, 738} after scrolling to visible` for a row that had
  settled about thirty points higher — tapped the gap above the pinned
  bar, and the disclosure never opened. 👁 The failure frame
  (`KEY-SEED-FIELD-MISSING`, run 127 shard 1) still reads "World seed >"
  with the chevron unturned, which is what proves it was the tap and not
  the field. The tap is confirmed and repeated up to three times now;
  the second needs no scroll, so it lands where the row is. The
  assertion behind it is unchanged.

## 2. Test inventory

| Test | Asserts |
| --- | --- |
| `testSectionPickerSitsUnderTheNavigationBarNotInDeadSpace` | the BUG-035 shape: the section picker within the top 30%, the empty state below and close to it, and clear of the tab bar |
| `testDarkAppearanceRendersEveryTab` | the game shell reports dark, then every tab renders |
| `testLightAppearanceMapForComparison` | the game shell reports light; captures the map for comparison |
| `testAcquireAircraftThenOpenARoute` | a lease reaches the fleet, and an opened route reaches the board |
| `testFoundingAnAirlineReachesEveryTab` | all five tabs reachable, each renders content |
| `testHomeGuidesANewPlayerToTheirFirstAircraft` | Home carries the only signpost to the market |
| `testNoScreenShowsTheOldCurrencyGlyph` | no label on any tab contains the generic currency sign |
| `testDetailScreensAndSettingsRender` | aircraft detail, route detail and Settings each render content only that screen has (AE-032) |
| `testAudioEngineStartsAndEveryCueDecodes` | the AVAudioEngine runs and every cue buffer decoded — proves the pipeline starts, not that anything was heard (AE-032) |
| `testAccessibilityTextSizeKeepsTheShellUsable` | at accessibility Dynamic Type, every tab stays tappable and the lease action reachable (AE-032) |
| `testColdLaunchBaseline` | cold launch, measured — a baseline, not a budget (AE-032) |

## 3. Screen coverage

| Screen | State |
| --- | --- |
| New game | 👁 observed (it is pinned dark in either appearance) |
| Home, Map, Network, Finance, World in dark | 👁 observed via the forced route |
| Home | 👁 observed, 🧪 onboarding card asserted |
| Map — world, regional and local zoom | ⚠️ **the AE-031 claim here was false** — see §7: the three "zoom level" screenshots were one image. Re-covered in AE-032 with the camera's zoom published and asserted at each level |
| Network — Routes empty | 👁 observed, 🧪 layout asserted |
| Network — Fleet empty | 👁 observed, 🧪 layout asserted |
| Aircraft market | 👁 observed |
| Finance | 👁 observed, 🧪 renders |
| World | 👁 observed, 🧪 renders |
| Route detail, aircraft detail, Settings, route sheet | 👁 observed + 🧪 (AE-032, runs 61–66) |
| Game over | 📖 only — needs a bankruptcy path or a debug hook |
| iPad regular-width shell | 👁 all five tabs + 🧪 (AE-032, runs 63/66); detail journey blocked by market-sheet tap flakiness |
| Dynamic Type at AccessibilityL | 👁 Home, Network, market + 🧪 tabs tappable (AE-032) |
| VoiceOver order, contrast ratios | 📖 only — never measured |

## 4. Appearance: the guard that did not guard

Worth writing down at length, because it is the most instructive failure in
this phase and the correction is not obvious.

AE-032 set `XCUIDevice.shared.appearance = .dark`, captured five screens,
named them `dark-home`, `dark-map`, and so on — and every one rendered light.
The test passed, because all it asserted was that content existed. **That is
worse than having no dark coverage: it manufactures evidence.**

The first fix was to have `RootView` publish the appearance it actually
rendered as an accessibility identifier, and fail before capturing anything if
it disagreed. Sound in principle, wrong in placement: the check ran on the
new-game screen, which `NewGameView` pins to dark with
`.preferredColorScheme(.dark)` because it is a presentation surface. So the
answer there is "dark" whatever the simulator is doing. The dark test passed
for the wrong reason and captured light screens named dark *again*; the light
test failed with a message that refuted itself — *"Asked for light appearance;
the app reports light."*

The working version asks the question where the answer can vary — after the
game is running — and re-launches up to three times, because a simulator
appearance switch is a system-wide animation with no completion to wait on.

### What the working guard then reported

That the simulator does not switch. `XCUIDevice.shared.appearance = .dark`,
three launches, up to six seconds of settle each — and the shell still renders
light on the CI runner. **That is why every earlier "validated in dark mode"
claim in this repository was false.** The mechanism never worked; only the
checking was new.

Waiting longer is not a fix, so the choice was between no dark coverage at all
and coverage of a slightly weaker claim. The weaker claim was taken
deliberately: a launch argument (`-AEUITestDarkAppearance`) that the shipping
binary reads and uses to pin its own colour scheme.

**The two claims are not the same, and the difference is recorded in the
filenames.** The system route is always tried first and its screenshots are
named `dark`; the fallback's are named `darkforced`. What `darkforced` proves:
the app renders correctly in dark. What it does not prove: that the app
follows the system appearance setting. Naming the route is what stops the
weaker evidence being read as the stronger — which is the exact failure this
guard exists to prevent, and which it had already permitted twice.

**Status: 👁 the dark appearance has been rendered and looked at**, via the
forced route, on Home, Map, Network, Finance and World. Black ground, dark
cards, legible text, accents holding. Whether the app *follows the system
setting* is still 📖 — untested, because the runner cannot test it.

## 5. What running the app has found

Four findings, none of which any compiler or Core test could see:

| | Found by | Class |
| --- | --- | --- |
| BUG-035 — a third of the Network tab was dead space | 👁 the first screenshot | a control in the wrong place |
| The generic currency sign read as a broken glyph | 👁 a screenshot, shown to a person | a decision right in intent and wrong on screen |
| A test drove the wrong control | 👁 the "after lease" screenshot showed a stepper had moved | a query that matched by label |
| BUG-036 — map chrome illegible in light appearance | 👁 the map screenshot | an agreement between a fixed-dark canvas and adaptive materials |
| Every airport label vanished from the map | 👁 a map screenshot with cities and countries on it and not one airport code | a refactor that reordered two steps with a hidden dependency |

The fifth is the sharpest of them. The refactor that let country labels avoid
airport labels moved the label *placement* ahead of `drawAirports` — which was
where the projection lived. The placer then ran against an empty list and
produced nothing, silently, on every frame. It compiled, nine UI tests passed,
and the only thing in the world that could have caught it was a person looking
at a picture of the map and noticing an absence.

The third is not an app defect, and is listed because it is the same shape:
`label BEGINSWITH "Lease"` matched the **"Lease term: 60 months"** stepper, so
the test decremented the term, leased nothing, and reported that the app had
silently failed. Without the screenshot the finding would have been filed
against the app.

## 6. What this document does not claim

- Cold launch is now measured (`testColdLaunchBaseline`); nothing else is.
  Map rendering, zoom latency and scroll hitching remain unprofiled.
- Dynamic Type is sampled at one accessibility size; VoiceOver order and
  contrast remain unmeasured (contrast of the *fixed* palette pairs was
  computed from source in AE-032 — a READ-level claim, recorded in
  CURRENT_PHASE, not a render measurement).
- iPad has one opt-in CI job (`app-ipad`, workflow_dispatch) driving the
  shell journey at regular width; until its screenshots have been looked at,
  no iPad claim stands.
- No claim that any screen *looks good*. Rendering is not design review.

## 7. AE-032: the run that audited the auditors

The phase's first act was to decode run 59's screenshots (main, c387dde) and
*look*, before changing anything. Three of the findings were about the
evidence system itself:

- **BUG-039.** The zoom test's "world / regional / local" screenshots were
  byte-identical (the map opens framed near the clamp; pinching in moved
  nothing), and its "zoomed back out" frame was **the Finance screen** — the
  wide synthetic pinch had pressed the tab bar. The test passed, the audit
  recorded zoom coverage, and none of it had happened. The camera's zoom is
  now in the canvas's accessibility value, every zoom step is asserted
  against it, and a pinch that moves nothing is an `XCTSkip` that says so.
- **BUG-038.** The route-opening journey tapped the From picker believing it
  was a destination, then a button labelled "Open" that has never existed.
  Underneath the broken proof sat a real flaw: the commit row lived below
  all ~40 candidate rows. The commit now rides the sheet's bottom edge, and
  the journey drives stable identifiers with a causality check at each step.
- **The lease mis-tap, photographed.** `MARKET-DID-NOT-CLOSE` shows a
  **"Buy used (8y)?"** dialog after the test tapped the lease action: the
  list was still settling and the tap landed one row up. The harness now
  settles after scrolling and refuses to confirm any dialog that is not
  titled "Lease?". The same screenshot also showed BUG-037 — "Need
  110000000 for this offer" — Core's rejection messages printing raw cents.

One correction to §1's premise: the result-bundle artifact is *not* out of
reach. `get_workflow_run_logs_url` hands back a signed URL that downloads the
full log zip with no credential, so every screenshot of a run is decodable —
the 2.6 MB log-tail cap that ate the early checkpoints (TD-020) has a
workaround, and AE-032 read all twenty frames of run 59 with it.

## 8. AE-032, closed: the frozen world, and what the runner cannot do

**BUG-040.** The deepest finding of the phase, found only because the
journey finally reached the state the game is for. The simulation pump was
armed solely by a scene-phase change — which fires at launch, on the menu,
where no session exists — and nothing armed it when a game was founded or
loaded. The clock therefore never ran: runs 64 and 65 both photographed an
aircraft assigned to a route, 16× selected, and the date still at day one,
00:00. Every screenshot in this document taken before that fix shows a
frozen world that happened to look correct. Fixed where sessions are born;
`testTheClockActuallyRuns` (found → 16× → the Home date must change inside
a real minute) is the dedicated guard, deliberately independent of the
market sheet.

**The runner's tap synthesis is the flakiest thing in this project now.**
Across runs 61–66 every leg of the economic journey went green at least
once — lease (61, 64, 66), route open (61, 64), assignment with its
Unassign proof (64), detail screens (61, 65) — and a different leg failed
each time: a tap one row off, a row reported un-hittable, one run's failure
frame showing the **iOS Settings app** where ours should be. These are
recorded as automation limitations, not app defects: each failure's frame
shows a healthy app. That upgrade landed: **run 69 was the first fully green run in the
project's history** — 14 of 14 UI tests including the complete flight
journey — and its frames show the aircraft en route Arlanda (Stockholm) →
Heathrow (London) at 16×, the clock at January 2. An aircraft in the air is
👁 observed and 🧪 asserted. The tap flakiness note above stands as history
and as a warning for future journey legs.

The iPad job's five-tab shell journey is green (runs 63, 66); its detail
journey shares the market-sheet flakiness above and is not yet green.
