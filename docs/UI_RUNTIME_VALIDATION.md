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

## 3. Screen coverage

| Screen | State |
| --- | --- |
| New game | 👁 observed (it is pinned dark in either appearance) |
| Home | 👁 observed, 🧪 onboarding card asserted |
| Map — world zoom | 👁 observed |
| Network — Routes empty | 👁 observed, 🧪 layout asserted |
| Network — Fleet empty | 👁 observed, 🧪 layout asserted |
| Aircraft market | 👁 observed |
| Finance | 👁 observed, 🧪 renders |
| World | 👁 observed, 🧪 renders |
| Route detail, aircraft detail, sheets, game over, settings | 📖 only |
| iPad regular-width shell | 📖 only — never run |
| Dynamic Type at accessibility sizes | 📖 only — never run |
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

**Status: the dark appearance is NOT YET VALIDATED.** The guard is now
correct; nothing has yet passed through it. Any claim about how this app looks
in dark mode remains 📖 until a run says otherwise.

## 5. What running the app has found

Four findings, none of which any compiler or Core test could see:

| | Found by | Class |
| --- | --- | --- |
| BUG-035 — a third of the Network tab was dead space | 👁 the first screenshot | a control in the wrong place |
| The generic currency sign read as a broken glyph | 👁 a screenshot, shown to a person | a decision right in intent and wrong on screen |
| A test drove the wrong control | 👁 the "after lease" screenshot showed a stepper had moved | a query that matched by label |
| BUG-036 — map chrome illegible in light appearance | 👁 the map screenshot | an agreement between a fixed-dark canvas and adaptive materials |

The third is not an app defect, and is listed because it is the same shape:
`label BEGINSWITH "Lease"` matched the **"Lease term: 60 months"** stepper, so
the test decremented the term, leased nothing, and reported that the app had
silently failed. Without the screenshot the finding would have been filed
against the app.

## 6. What this document does not claim

- No performance figures. Nothing has been profiled.
- No accessibility findings. Nothing has been measured.
- No iPad findings. The regular-width shell has never been run.
- No claim that any screen *looks good*. Rendering is not design review.
