# iPhone Duo support

Status, 18 October 2026: **the app and its tests compile with Xcode 27.1 / iOS 27.1 SDK** (CI run 39133562645, 0 errors). Duo simulator lane and fold transitions pending.

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
5. `FoldableLayoutReviewTests` hosts the shell, Finance and Settings at all
   four Duo window shapes, and pins the `HubChromeMode` each one gets.
6. CI: `ci.yml` takes `xcode: 27.1` (the phone app job runs on `xcode-27`)
   and `duo: true` (new `app-duo` job: Xcode 27.1, finds or creates an
   iPhone Duo simulator, runs the Duo tests plus the shell, map and hub
   journeys, prints `DUO-*` and `KEY-*` screenshots into the log).
7. `ios-testflight.yml` takes `xcode: 27.1`: full validation, the Duo lane
   and the archive all use Xcode 27.1.

## Already fine (checked)

- No `UIDevice.current.orientation`, no hard-coded screen heights, no
  `scaledToFill` hero images in the app.
- The shell switches tab bar ↔ sidebar on `horizontalSizeClass`, not on
  device type. The map and hub lay out from `GeometryReader` sizes and safe
  areas, so a vertical tab bar on the side is a safe-area change, not a
  break.

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
