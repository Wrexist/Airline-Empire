# AirlineEmpire iOS app shell

SwiftUI client of `AirlineEmpireCore` (all game logic lives in the package;
this target only presents snapshots and submits commands —
docs/UI_ARCHITECTURE.md).

## Status

**Authored on Linux, NOT yet compiled** — SwiftUI requires macOS/Xcode
(blocker B-002, docs/PROJECT_AUDIT.md). First macOS session must:
1. `brew install xcodegen && cd AirlineEmpireApp && xcodegen generate`
2. Open `AirlineEmpire.xcodeproj`, build, fix any compile issues.
3. Run on simulator; walk the new-game → route → fast-forward flow.

Until that run is green, phases 14–15 are "authored", not "done"
(tasks/TODO.md AE-023).

**Static integration audit passed (2026-08-26, Linux):** every source
file parses (`swiftc -parse`) and every Core API this target uses —
command initializers, read-model fields, enum case arities, catalog
accessors, hardcoded content codes — was verified against the package by
inspection. One cross-module compile blocker was found and fixed
(tasks/BUGS.md BUG-001). This raises confidence, but only an actual
Xcode build counts as COMPILED.
