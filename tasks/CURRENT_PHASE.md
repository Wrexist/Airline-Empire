# Current Phase

**AE-023 — Linux-first continuation (V3 prompt).** No Mac is available;
Apple-layer work is prepared, never claimed.

## Status ladder

- `AirlineEmpireCore` — **LINUX VALIDATED.** Builds debug + release clean,
  full suite green, release benchmark inside budget.
- `AirlineEmpireApp` — **COMPILED · NOT APPLE-RUNTIME-VALIDATED.** As of
  2026-08-28 the target builds under Xcode 26.6 for the iOS 26.5 simulator SDK
  on a CI runner (`** BUILD SUCCEEDED **`, CI run 33213797384) — so SwiftUI
  compiles and every Core API the views call resolves for real, not merely by
  inspection. What is still unproven is everything a compiler cannot answer:
  rendering, layout, iPad size classes, `Canvas` map performance, gestures,
  `@Observable` update behaviour, actor hops, scene-phase autosave,
  accessibility, haptics and signing. `docs/APPLE_VALIDATION.md` remains the
  list, and it still needs a device and a person.

## Session log

**2026-08-29 (continuation — the last of the audit list).** Four things the
remediation pass had left:

- **The feed is tappable.** UI-011 was marked "Fixed" on the strength of
  naming and world-event links; that overclaimed, because the finding was
  about the *tap*. A feed line about a route or aircraft you own now opens it,
  and a line about something already closed or sold resolves to no link rather
  than a dead end. The audit row has been corrected rather than quietly
  amended.
- **Formatting is locale-correct.** Every number went through
  `String(format: "%.1f")`, which prints `3.5` to a player who writes `3,5`.
  That is a defect today, for a French or German player of an English app, and
  distinct from translating anything. All numeric formatting is `FormatStyle`
  now. `¤` and the ISO game date stay fixed on purpose.
- **Livery (D-015, save v11).** Deferred earlier because it is airline state
  and costs a format bump — which is precisely why it was worth doing
  properly. v10 is what TestFlight wrote to a real phone, so this is the first
  migration here that runs on somebody else's data, and it is tested for what
  would cost a player their game rather than for decodability. The map now
  draws each carrier in its own colours, which is the first time a rival there
  has been distinguishable from any other rival.
- **The stale docs.** `PRODUCT_REVIEW` still scored UX as "Authored,
  unvalidated" and listed fixed issues; `TODO` predated the compile.

285 tests green, release build clean, and the app compiles.

**Still open, and honestly:** localization (zero — the strings, not the
numbers), audio (none, and it needs sound design rather than code), a starter
aircraft on the apron per `PLAYER_JOURNEY` §1, reputation-change events, and
hub connections (D-010). None of it is blocked on this environment; all of it
is a choice about what to build next.

**2026-08-29 (the UI/UX forensic audit, and acting on it).** A complete
product-and-UX pass over the whole repository produced
`docs/UIUX_FORENSIC_AUDIT.md` — the baseline every future UI decision is
measured against — and then the audit's own action list was worked.

The framing finding: an exceptional simulation wearing a thin client. The
Core/app seam holds everywhere (views format, Core calculates), so the
client's problems were entirely presentation and interaction, never truth —
and almost every fix was *showing the player something the snapshot already
held*. This month's route economics, the insolvency countdown, era gate
thresholds, capability costs and completion dates, aircraft reliability and
hours, today's demand pool: all computed, none displayed.

Five P0s, closed: six tabs overflowed into the system *More* list, burying
Finance and the World hub including the only path to saving (BUG-009); a new
route reported ¤0 for its whole first month because only the closed month was
published; the first flight departing and landing rendered nothing at all,
which is the promised payoff of the first five minutes; the one rejection
alert was mounted beneath the sheets that raise nearly every rejection and
absent from the menu entirely, so a failed save load reached nobody; and the
failure journey — `SolvencySystem`'s daily countdown to administration — had
no interface whatsoever.

Nine P1s and most of the P2/P3 list followed. Two more real defects surfaced
while fixing: a capability Start button whose only possible outcome was a
refusal (BUG-010), and a finance chart that drew its zero line in a different
place for every bar (BUG-011).

Core gained four additive, pure files — `EraGate`, `MissionMath`,
`AdvisoryModels`, and this-month route economics — each built so the screen
and the simulation ask the *same* arithmetic rather than two copies of it.
**276 tests green** (up from 257), release build clean under
`-warnings-as-errors`, save format still v10.

The app **compiles** — CI run 33244671402, `** BUILD SUCCEEDED **` on
`macos-26` with Xcode 26.6. It took two runs, and the first is worth recording:
`swiftc -parse` on Linux answers syntax only, and five type errors were
invisible to it — an `==` against an enum case carrying a payload, a
synthesised internal initialiser the app could not reach, a missing `Hashable`,
a `List(selection:)` overload, and an unused binding fatal under
`-warnings-as-errors`. Two of them sat in code fixing P0s. The lesson is the
old one this project already knows and this session had to relearn: *parsed*
and *compiled* are different claims, and only the second can be made from a
green macOS job.

The status ladder moves exactly one rung: **COMPILED · NOT
APPLE-RUNTIME-VALIDATED**. The `[device]` predictions in the audit — the tab
overflow first among them — still need a screen.

**2026-08-29 (the app ran on a phone, and BUG-008).** The first TestFlight
build reached a physical iPhone — and crashed on the first screen after
founding an airline. `DashboardView` asked for *yesterday's* digest on day 0,
which is day −1, which tripped `GameCalendar`'s before-epoch precondition. Two
fixes, one layer each: Core refuses a day that cannot exist (nil, like it
already does for an unknown airline), and `SimTime.previousDayIndex` makes
"there is no yesterday" representable. The suite missed it because every
digest test advanced the clock first, so day 0 — the only day a player is
guaranteed to see — was the one day never exercised; the regression tests were
verified by removing the guard and watching them crash. 257 tests green.

The rest of the game got the same pass: `AECard`, `StatTile`, `SpeedControl`
and the empty states are glass now, so every screen inherited it from the
design system rather than being rewritten one at a time. Motion tokens
(`AEMotion.selection/content/screen`) replace ad-hoc durations; stat and money
values roll their digits instead of swapping (`contentTransition(.numericText)`),
which is what makes a dashboard readable at 16×; the ops feed slides new events
in; whole-screen changes crossfade; the speed control is one capsule with a
sliding selection rather than four blinking buttons; and the World tab is a hub
with four described destinations rather than a list of bare nouns.

Onboarding rebuilt in the same session: it was a `Form` that read like the
Settings app, and it is now a dusk-lit screen with Liquid Glass
(availability-gated to iOS 26, `.ultraThinMaterial` below), a decision-shaped
hierarchy (name → where → how hard → fly), start cards carrying real signals
from `airports.json` instead of one line of prose, and the found button pinned
where it can always be reached. The app's status ladder is unchanged:
**COMPILED · RUNS ON DEVICE**, and still not runtime-validated beyond the
first screens.

**2026-08-28 (first real archive, and Apple's first verdict).** Release run
33216345773 signed and exported a real `.ipa` on a macOS runner — signing, the
App Store Connect API key, the build-number resolver and the export options all
work against the live Apple account. Apple refused the bundle at validation
with error **90474**: an iPad build must declare all four interface
orientations, because shipping for iPad opts into Slide Over and Split View.
Fixed by splitting the orientation key per device in `project.yml` (iPhone
keeps three; upside-down on a phone is a mis-rotation, not a feature). The
rejection is now a 1x-runner check — `scripts/asc/check-bundle-config.mjs`,
verified to reproduce the failure against the exact manifest Apple rejected.

**2026-08-28 (first full green CI).** All three jobs of run 33213797384
passed: the core suite (253 tests, 8m), the release build with
`-warnings-as-errors` (clean — the zero-warnings target is now machine-
enforced), the release tooling's own 31 tests, and the macOS app compile.

**2026-08-28 (the app compiled).** CI run 33213797384 built
`AirlineEmpireApp` with `xcodebuild` on a `macos-26` runner: XcodeGen
generated the project from `project.yml`, the local `AirlineEmpireCore`
package linked, and the build succeeded in 53 seconds. Blocker **B-002** is
half closed — the compile question no longer needs a Mac in the room; the
runtime questions still need a device.

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
- `scripts/asc/` — dependency-free Node tooling (D-013) with 30 tests.
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
