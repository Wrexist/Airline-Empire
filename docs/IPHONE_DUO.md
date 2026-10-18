# iPhone Duo support

Status, 18 October 2026: **runs edge to edge on the iPhone Duo simulator.** CI run
39133562645 built with Xcode 27.1 / iOS 27.1 SDK (0 errors), created an iPhone Duo
simulator on iOS 27.1 and launched the game on the outer display: content left of the
status bar, the tab bar vertical on the right, founding → every tab passed. The three
failures were test-harness assumptions (fixture not generated; lease helper relied on
a sheet title the 27.1 SDK hides while scrolling on the short display), fixed after.

iPhone Duo is Apple's foldable (iOS 27, A20 Pro). Two displays, both 3x:

| Display | Pixels | Points | Shape |
|---|---|---|---|
| Outer, 5.4" | 1398 × 2034 | 466 × 678 | short phone |
| Inner, 7.6" | 1878 × 2670 | 626 × 890 | near-square, can report regular width |

Source: [apple.com/iphone-duo/specs](https://www.apple.com/iphone-duo/specs/),
[developer.apple.com/iphone-duo/prepare](https://developer.apple.com/iphone-duo/prepare/).

## What the SDK decides

| Built with | On iPhone Duo |
|---|---|
| iOS 26 SDK (Xcode 26.x, every build up to 1.2.1) | Centred window, empty space around it |
| iOS 27 SDK | Most of the inner display |
| iOS 27.1 SDK (Xcode 27.1) | Edge to edge; tab bars and toolbars can turn vertical |

So the one change that makes the game "for iPhone Duo" is building with
Xcode 27.1. GitHub's `xcode-27` runner image has it
(`/Applications/Xcode_27.1.app`, a preview image).

## What changed in this branch

1. `HubScreen` no longer reads `UIScreen.main.bounds`. The hub inspector now
   opens based on the **window** size (`AEOrientation.windowSize`), through
   the same `HubChromeMode` the dashboard already uses.
2. `HubChromeMode` gives a wide window the iPad layout only from 700 pt of
   height (iPad mini landscape is 744). The Duo's inner display on its side
   (890 × 626) gets the slim landscape chrome; the iPad layout's right column
   would overlap at 626.
3. `AEOrientation.lockLandscape()` locks only phone-narrow windows (shortest
   side under 520 pt). The inner display ignores orientation locks anyway and
   has room for the hub either way up.
4. `HubSceneController` reframes the camera on a size change of more than
   8 %, not only on aspect: folding outer → inner on its side is 1.455 →
   1.422, the same ratio at nearly twice the size. A construction site being
   watched stays in frame through the fold.
5. `GameShell` keeps its tab bar on any iPhone, even at regular width. The
   old size-class switch to a sidebar rebuilt every tab on a fold, losing
   the map camera, selection and any half-drawn route. iPad is unchanged.
6. `FoldableLayoutReviewTests` hosts the shell, Finance and Settings at all
   four Duo window shapes, and pins the `HubChromeMode` each one gets.
7. CI: `ci.yml` takes `xcode: 27.1` (the phone app job runs on `xcode-27`)
   and `duo: true` (new `app-duo` job: Xcode 27.1, finds or creates an
   iPhone Duo simulator, runs the Duo tests plus the shell, map and hub
   journeys, prints `DUO-*` and `KEY-*` screenshots into the log).
8. `ios-testflight.yml` takes `xcode: 27.1`: full validation, the Duo lane
   and the archive all use Xcode 27.1.

## Already fine (checked)

- No `UIDevice.current.orientation`, no hard-coded screen heights, no
  `scaledToFill` hero images in the app.
- The map and hub lay out from `GeometryReader` sizes and safe areas, so a
  vertical tab bar on the side is a safe-area change, not a break.

## Still to do

1. Dispatch `ci.yml` with `suite=compile xcode=27.1 duo=true`; fix anything
   Xcode 27.1 rejects; read the `DUO-*` screenshots.
2. In Xcode 27.1's iPhone Duo simulator (Device Hub): fold and unfold with a
   sheet open, mid-route-creation and inside the hub. The game state must
   survive each transition.
3. Ship the next version with `ios-testflight.yml xcode=27.1`.
4. App Store screenshots: outer 1398 × 2034, inner 2007 × 2853 (portrait).
   Optional now; **required from April 2027** for apps built with the 27.1
   SDK. Add both sizes to `scripts/store-art/showcase.cjs`.
5. Featuring nomination: say "optimized for iPhone Duo, all poses".
