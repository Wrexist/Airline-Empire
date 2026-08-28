# AirlineEmpire iOS app shell

SwiftUI client of `AirlineEmpireCore` (all game logic lives in the package;
this target only presents snapshots and submits commands —
docs/UI_ARCHITECTURE.md).

## Status

**Authored on Linux, NOT yet compiled** — SwiftUI requires macOS/Xcode
(blocker B-002, docs/PROJECT_AUDIT.md).

Since 2026-08-28 the *compile* question no longer needs a Mac in the room:
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
