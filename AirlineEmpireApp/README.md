# AirlineEmpire iOS app shell

SwiftUI client of `AirlineEmpireCore` (all game logic lives in the package;
this target only presents snapshots and submits commands —
docs/UI_ARCHITECTURE.md).

## Status

**COMPILED, not yet run.** On 2026-08-28 this target built under Xcode 26.6
for the iOS 26.5 simulator SDK on a CI runner (`** BUILD SUCCEEDED **`, CI run
33213797384) — the first Xcode build in the project's history, and it needed
no source changes. It has still never been *run*: nothing has rendered, no
gesture has been received, no autosave has fired on a real scene-phase change.

The compile question no longer needs a Mac in the room:
`.github/workflows/ci.yml` runs `xcodegen generate` and `xcodebuild build` on
a macOS runner for any commit touching this target or the core package. Push a
branch and read the result. Everything else below still needs a device and a
person — a green compile says nothing about rendering, gestures, `@Observable`
behaviour, scene-phase autosave, or accessibility.

A first macOS session should still:
1. `brew install xcodegen && cd AirlineEmpireApp && xcodegen generate`
2. Open `AirlineEmpire.xcodeproj`, build, fix any compile issues.
3. Run on simulator; walk the new-game → route → fast-forward flow.

Until that run is green, phases 14–15 are "authored", not "done"
(tasks/TODO.md AE-023).

## Resources

`Resources/` holds the privacy manifest (nothing collected, nothing tracked —
each claim derived from the code) and the asset catalogue. **The app icon is
missing and blocks any App Store submission**; the slot and the brief are in
`Resources/README.md`. Release plumbing: `docs/RELEASE_PIPELINE.md`.

**Static integration audit passed (2026-08-26, Linux):** every source
file parses (`swiftc -parse`) and every Core API this target uses —
command initializers, read-model fields, enum case arities, catalog
accessors, hardcoded content codes — was verified against the package by
inspection. One cross-module compile blocker was found and fixed
(tasks/BUGS.md BUG-001). This raises confidence, but only an actual
Xcode build counts as COMPILED.
