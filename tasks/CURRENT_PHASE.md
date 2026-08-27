# Current Phase

**AE-023 — Linux-first continuation (V3 prompt).** No Mac is available;
Apple-layer work is prepared, never claimed.

## Status ladder

- `AirlineEmpireCore` — **LINUX VALIDATED.** Builds debug + release clean,
  full suite green, release benchmark inside budget.
- `AirlineEmpireApp` — **AUTHORED · PARSED · STRUCTURALLY VALIDATED ·
  READY FOR XCODE · NOT APPLE-RUNTIME-VALIDATED.** Every source passes
  `swiftc -parse`; every Core API it calls is verified; screen data
  contracts are covered by Core tests. SwiftUI has never compiled or run.

## Session log

**2026-08-26 (audit session).** Repository audit; BUG-001 (Core visibility
compile blocker) fixed; deprecated alert API modernized; force-unwraps
removed; per-render content/disk IO cached; `GENERATE_INFOPLIST_FILE`
added to project.yml.

**2026-08-26 (continuation).** BUG-002 fixed (no aircraft-assignment UI —
the core loop was uncloseable); TD-002 fixed (event-task cancellation);
onboarding beat built (Core `OnboardingModel` + Dashboard card).

**2026-08-26 (V3 Linux-first).** Systematic player-journey gap hunt:
- **BUG-003** (P1) fixed — game over was a dead end with no way to start
  another game; `quitToMenu()` + exits from Game Over and Settings.
- **BUG-004** (P1) fixed — the feed showed rivals' statements and loans as
  the player's own, and never rendered the administration warning at all.
  Core gained a pure event-audience classifier; the session filters at
  publish time (decision D-011).
- **BUG-005** (P1) fixed — commands rejected while the sim was running
  failed silently; `GameSession.rejections()` now delivers them (D-011).
- New Linux-side proof: `PlayerJourneyTests` (4), `EventFeedTests` (6),
  `ScreenContractTests` (6), `ContentQualityTests` (6).
- Content audit: no dead SKUs (F-005); runway ladder found nearly inert
  (F-004, documented for playtest, deliberately not "fixed").
- Offline-first re-audited: zero network references in Core or App.
- `docs/APPLE_VALIDATION.md` written — the full Xcode handoff.

**2026-08-26 (late-game + audit close).** `LateGameTests` (5): a decade of
play keeps every bounded collection bounded and the save within a small
multiple of year one; the world stays alive without runaway wealth; fleets
age inside their domains; **a decade is bit-identical for a given seed**;
five save/reload cycles over five years equal one unbroken run.
Subscription-lifecycle test added (§27). Swift 6 concurrency audit of the
App: clean. `docs/LINUX_QA_AUDIT.md` written — proven vs. unknown, with
§37's questions answered honestly.

## Next

Remaining work is Apple-runtime by nature (compile, simulator, rendering,
gestures, accessibility, Instruments, signing). It is enumerated in
`docs/APPLE_VALIDATION.md`; no further Linux-side P0/P1 is known.
