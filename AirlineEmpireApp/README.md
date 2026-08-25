# AirlineEmpire iOS app shell

SwiftUI client of `AirlineEmpireCore` (all game logic lives in the package;
this target only presents snapshots and submits commands —
docs/UI_ARCHITECTURE.md).

## Status

**Authored on Linux, NOT yet compiled** — SwiftUI requires macOS/Xcode
(blocker B-002, docs/PROJECT_AUDIT.md). First macOS session must:
1. `brew install xcodegen && cd AirlineEmpireApp && xcodegen generate`
2. Open `AirlineEmpire.xcodeproj`, build, fix any compile issues
   (Core APIs are test-verified; view-layer syntax is not).
3. Run on simulator; walk the new-game → route → fast-forward flow.

Until that run is green, phases 14–15 are "authored", not "done"
(tasks/TODO.md AE-016/AE-017).
