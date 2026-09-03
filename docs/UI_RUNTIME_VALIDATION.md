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

Seven tests, one device, portrait. That is the whole of it — small, and worth
not overstating.

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
control; nothing else about the app changes. The UI step also asks
xcodebuild for three workers explicitly, since run 123 used two.

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
