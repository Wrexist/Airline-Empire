# Airline Empire — Technical Debt Register

Known debt, tracked honestly. Nothing here is "acceptable"; each item carries
a resolution path.

---

## TD-001 — Agent environment cannot build or test Swift
**Severity:** ~~Critical~~ RESOLVED 2026-08-25 — Swift 6.0.3 installed via GitHub mirror (D-009); `swift test` verified. Residual: iOS app target still needs macOS (B-002, structural).
**Introduced:** Pre-existing environment condition, recorded Phase 0
(2026-08-25).
**Description:** The remote Linux agent environment has no Swift toolchain and
the network policy denies `download.swift.org`, so one cannot be installed
in-session. `xcodebuild` is impossible on Linux regardless.
**Resolution path:** Owner allowlists swift.org and adds a toolchain setup
script, or implementation phases run on macOS. Tracked as task AE-001 and
blocker B-001 in `/docs/PROJECT_AUDIT.md` §4.

---

*(No code exists yet, so no code-level debt. New entries are added the moment
debt is knowingly incurred, not discovered later.)*
