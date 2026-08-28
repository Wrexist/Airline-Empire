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

**2026-08-28 (release pipeline and store listing).** Everything the Apple
layer needs that can be built without Apple:
- CI now compiles the app. `.github/workflows/ci.yml` runs `xcodegen` +
  `xcodebuild` on a macOS runner alongside the Linux core tests, so "does the
  SwiftUI shell compile" stops being a question only a Mac can answer (D-014).
  It does not close B-002 — rendering, gestures, accessibility, Instruments and
  signing still need a device.
- `.github/workflows/ios-testflight.yml` archives, signs, exports and uploads a
  build, split across cheap and expensive runners for a measured reason.
- The store listing is now versioned content in `/store` (D-012), with a
  validator that enforces Apple's limits offline, `docs/ASO.md` for why each
  word is the word, and a metadata deploy workflow that dry-runs by default.
- `scripts/asc/` — dependency-free Node tooling (D-013) with 26 tests.
- App-side: privacy manifest, asset catalogue with an empty icon slot, pinned
  bundle id, version, build number and export-compliance declaration.
- Still blocking a submission, none of it fixable from Linux: the app icon,
  the screenshots, and three `REPLACE_ME` values only the account holder can
  supply. AE-024 records all of it.

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

**2026-08-27 (BUG-006 — the economy's biggest defect).** Found while
producing a screen-by-screen dump of a real game to answer "how does it
look": the onboarding card read "≈2,610,001 travellers/day". Root cause:
`populationThousands` held raw people, so every demand pool was exactly
1000x too large (~1,600x real capacity) and every route ran capacity-pinned
at 100% load regardless of fare — pricing, the game's central economic
decision, had no downside. Fixed by dividing all 80 populations by 1000; no
tuning constant, formula, or capacity touched. Price now moves volume and
profit has an interior optimum at ~1.6x reference. Baseline economics at
default pricing are unchanged, which is why all 251 tests passed before and
after — and why the battery never caught it. New guards:
`BalanceTests.pricingHasRealConsequencesEndToEnd` (verified to fail on the
old data with all four diagnostics) and
`ContentQualityTests.airportPopulationsAreInThousands`. Onboarding now
reports capturable passengers, not raw market mass. Documented as F-006;
F-001 marked root-caused.

**2026-08-26 (evening digest).** `DailyDigestModel` closes PRODUCT_REVIEW
#9 and PLAYER_JOURNEY §1 step 4: yesterday's money by category, flights,
and news, derived from the ledger ring and event log — no new persisted
state, save format still v10, and honest (`isComplete`) when a very large
network out-posts the ring. Dashboard renders a "Yesterday" card with a
Why? breakdown; category labels unified app-wide. 6 tests.

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
