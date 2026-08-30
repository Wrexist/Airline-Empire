# Current Phase

**AE-028 — UI/UX polish, information density, design system (MASTER PROMPT 4).**
2026-08-30.

Foundation: a type scale by role (`AEType`), containers below a card
(`AEPanel`, `AEMetricStrip`), a button ladder (`AEButtonRole`), and — the
load-bearing change — network and fleet aggregates moved into Core so Home, the
Routes board and the Fleet board cannot answer the same question differently.

Screens: Home leads with the pulse rather than yesterday; Route Detail follows
§13's decision hierarchy and explains *why* a route earns or loses; Route
Creation shows competition; Finance answers the operating question and names
its best and weakest route; World events show severity. Card fatigue reduced
across five screens.

Three bugs found and fixed: BUG-027 (live flights counted the whole world),
BUG-028 (a save warning followed the player into the next game), BUG-029 (dead
route links on the Finance tab). One component defect found by reading the code
against its own documentation — `AEMetricStrip` could not wrap.

**Nothing in this phase has been seen rendered.** Core is tested and the app
compiles on macOS CI; layout, contrast, Dynamic Type and whether any of it
looks right are unverified. See the ladder below.

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

**2026-08-29 (the continuous audio layer, and a feel audit — AE-AUDIO-01).**
The previous phase built the *discrete* half of the audio system. This phase
built the continuous half, which was genuinely absent, and then audited how the
game feels to touch.

- **`SoundscapeDirection.swift` (Core, pure).** `AmbienceDirector` derives the
  world bed from focus, airborne count, speed, selection and solvency; the rule
  it enforces is that **the game gets richer as the airline grows, never
  louder**, so scale moves movement and never level. Pause keeps the bed and
  drops activity to 15%. 16x is deliberately *quieter* than 4x. A failing
  airline recedes rather than alarms. `MusicDirector` is a five-state machine
  with written precedence — a milestone outranks a crisis, because a player who
  achieves something while failing still achieved it.
- **Music ships, honestly.** Four sustained pads at 22.05 kHz. Drones, not a
  score: no melody, no rhythm, no development. That is a deliberate ceiling —
  a pad can be made tolerable for an hour by construction, a tune cannot. Two
  crossfading decks, equal-power, because two linear ramps dip in the middle.
- **`AudioSettings` (Core).** The settings *rules* are testable now: mute beats
  everything, unmuting restores the mix rather than a default, a fresh install
  cannot come up silent because a missing key read as `false`, and non-finite
  volumes fail to silence rather than to full.
- **A moment-to-moment audit across seven screens** found nine real defects and
  ten pieces of deferred redesign. Two screens were stating things that were
  not true: the dashboard drew a green up-arrow beside a dash for a whole
  game-month, and the route sheet promised a demand ranking it did not do and
  a passenger figure it did not show. Three actions in the game — fare,
  frequency, service tier — emitted nothing at all, because they emit no
  `SimEvent` and `submit` relies on one. Buying an aircraft left the sheet
  open. Both empty states issued instructions and offered no way to follow
  them.
- **BUG-018**, found hunting my own code: `applyMusic` re-derives on every
  snapshot and called the engine's same-track path, which **cancelled any fade
  in flight** — so every crossfade died 250 ms in and the game would have been
  stuck between two tracks at almost full volume, permanently.

**358 Core tests green** (331 before), app builds on macOS CI.

**What is not proven: all of it, audibly, and all of the feel work visually.**
The deferred redesign is recorded in `docs/UIUX_FORENSIC_AUDIT.md` §18 rather
than hidden, and AE-027 is the task. The status ladder does not move.

**2026-08-29 (audio, haptics and game feel — MASTER PROMPT 3).** The game had
no sound at all. It has a complete semantic audio language now.
`docs/AUDIO_ARCHITECTURE.md` and `docs/AUDIO_ASSET_MANIFEST.md` are the full account.

- **The policy is in Core, so it is tested.** `AudioDirection.swift` maps
  `SimEvent` to `AudioCue` and then ranks, deduplicates, rate-limits,
  aggregates and caps a batch — purely, from events, state, speed and a
  caller-supplied clock. 22 tests cover the properties that actually decide
  whether an audio system feels premium or exhausting: that twenty departures
  in one quarter-second at 16x become **one** sound, that a cooldown can never
  mute a bankruptcy warning, that a busy batch drops the quiet cues rather
  than the loud ones, and that the same batch always sounds the same.
- **Silence is a tool, by test.** `dayStarted`, `weekStarted`, `monthStarted`,
  `seasonChanged`, `wakeFired` and `commandApplied` map to no sound at all.
- **The first times survive a save (BUG-013).** "Your first flight has landed"
  is seeded from `RouteStats`, which is persisted — so loading a mature
  airline cannot replay the beginning of the game at somebody. Verified in
  both directions by sabotage.
- **54 original assets**, synthesised by `scripts/audio/generate.py` from
  additive synthesis and swept filtered noise on one pitch set. No samples, no
  licences, nothing that belongs to anyone else — and not the work of a sound
  designer. The loudness hierarchy is deliberate: an era change peaks at 0.80,
  a tab tap at 0.11.
- **The engine is dumb on purpose.** One `AVAudioEngine`, two mixers, eight
  voices, every buffer decoded at launch, category trim baked into the samples
  so a play costs one `scheduleBuffer`. Session category `.ambient` with
  `.mixWithOthers`: the game never interrupts the podcast a player already has
  on, and it obeys the silent switch.
- **Money trouble is audible before it is fatal.** `SolvencyModel.stage` was
  already computed every refresh for the auto-pause and had no voice; crossing
  into `watch` and into `danger` now sound, on the *transition* only, and
  deliberately not gated on the auto-pause preference — that setting is about
  time control, not about whether the game tells you it is failing.
- **Music is deliberately absent**, with the six-track brief written and no
  dead toggle in Settings (TD-008).

**Game feel, beyond sound.** The audit's real find: twenty-two tap targets
used `.buttonStyle(.plain)`, which on iOS gives *no* press feedback at all —
every card, row and pill in the app was visually inert under the finger. One
design-system `AEPressStyle` now gives all of them a small scale and dim,
Reduce-Motion aware. That is most of why the interface felt weightless.

**Four bugs found by reading rather than by playing** — one of which would
have been a crash on the first sound of every session: the audio graph wired
its player nodes with `format: nil` before decoding anything, so the engine
inferred the hardware's stereo format for mono buffers, and
`scheduleBuffer` raises an uncatchable Objective-C exception on a mismatch
(BUG-017). Nothing in a compile can see that, and no Linux test can reach it.
The other three: the haptics setting
only worked on two of seven screens (BUG-014); the celebration banner was
about to fire a second haptic on top of the director's for every era,
milestone and mission (BUG-015); and per-play node volume would have ducked a
long sound under a later tap (BUG-016).

**330 Core tests green** (308 before), app builds on macOS CI.

**What is not proven: all of it, audibly.** This environment has no speaker
and cannot run a simulator. The policy is tested and the assets measure
correctly; whether the game *sounds* good is unknown, and TD-006 / AE-026 say
so. The status ladder does not move.

**2026-08-29 (the world map overhaul — MASTER PROMPT 2).** The map was four
files' worth of dots on a 260-point outline; it is now the screen the rest of
the game points at. `docs/MAP_ARCHITECTURE.md` is the full account. In short:

- **Renderer decided, not defaulted.** One SwiftUI `Canvas` inside a
  `TimelineView`, chosen against SpriteKit, Metal, MapKit and a web map, each
  rejected in writing with a reason. No new dependencies. Immediate mode is the
  point: a view per airport is what makes a SwiftUI map fall over, and the
  whole world is a few thousand primitives.
- **Cartography.** 631 coordinate pairs across 24 landmasses (was 260/16),
  a 30° graticule, and a palette built for a premium strategy game rather than
  for looking like a road atlas.
- **A model that knows things.** `MapModel` gained airport tiers, regions,
  hubs, slot pressure and weather risk; routes gained load factor, health and
  livery; flights gained origin, destination, progress, delay and category.
  All derived from state Core already had — the map shows what the simulation
  already knew and never computed anything of its own.
- **Live aircraft, honestly.** Markers interpolate between snapshots as client-
  side prediction only. Nothing they do re-enters the simulation, the clock is
  Core's, and at `.paused` the timeline stops entirely rather than drifting.
- **Original aircraft art.** Four planforms authored as unit-box paths — no
  copyrighted planform, no airline branding, no livery copied from a real
  carrier.
- **Overlays that answer questions.** Five, each with the question it answers
  written next to it: network, opportunity, profitability, competition,
  disruption. Route health is drawn with dash pattern and weight as well as
  colour, so it survives colour blindness and greyscale.
- **One ranking of "where should I fly next".** The onboarding card and the map
  opportunity overlay were about to hold two copies; `MarketOpportunities` in
  Core is the one, with a test asserting both callers agree.

**BUG-012**, found by hunting my own new code: a Tokyo–LA arc crossed the date
line and drew a line back across the entire world. Fixed in Core, because the
projection is what owes the guarantee — `MapMath.unwrap` carries a whole-world
offset across the seam and `worldOffsets` says which copies to draw. Seven
tests.

**Performance**, measured, and worth recording because the first number was
bad: `mapModel` is rebuilt every tick, and at late-game scale (8 airlines, 200
routes, 200 aircraft, 403 live flights) it cost **15.42 ms** — of which
`marketOpportunities` alone was 13.93 ms, scanning every airport the player
touches against all eighty. Restricting origins to actual *bases* (home, plus
anywhere with three or more routes, capped at five) is both the better product
answer and an **8.6x** win: **1.79 ms**. `ae-map-bench` is the harness.

**308 Core tests green** (257 at the start of the session), release build clean
under `-warnings-as-errors`.

**The map compiles.** CI run 33247689097 built the whole app target with
`xcodebuild` on `macos-26` / Xcode 26.6, `Sources/Map/` included. It took two
runs. The first failed on a single error that stopped the module before one
function body was type-checked: `RouteDraft` had been declared at the bottom
of the old `Screens/MapView.swift`, which the overhaul deleted, and the
airport browser presents the same sheet. Reading the new files for the
*classes* of error this project has already hit found four more the next run
would have raised — a non-`Comparable` enum compared with `<=`, an
`Equatable` where `aeAnimation` wants `Hashable`, two `switch` expressions
whose branches were implicit members (the shape this toolchain refused once
already today), and an `if case` used as an expression — plus one product
bug: the map's empty-state card built a route suggestion with an empty city
name.

**What is still not proven:** everything about how it *looks*. A compiler
says the code is well-typed; it says nothing about whether the projection
reads at each zoom, whether labels avoid each other on a real screen, whether
drag and pinch cooperate, or whether 30fps holds with 400 flights on real
silicon. `ae-map-bench` times the *model*, on Linux, on a server CPU. TD-003
is that list; AE-025 is the task. The status ladder does not move.

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
