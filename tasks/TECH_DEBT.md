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

## TD-002 — Event-stream subscription task lingers across game restarts
**Severity:** P3 (bounded leak, rare path).
**Introduced:** Phase 14 (GameController.subscribe), recorded during the
AE-023 static integration audit (2026-08-26).
**Description:** Starting a second game within one app run replaces the
`GameSession` but never terminates the previous session's event
`AsyncStream` consumer task; it idles until the old stream terminates.
One idle task per restart, no unbounded growth per session.
**Resolution path:** Hold the subscription `Task` in GameController and
cancel it before creating a new session.
**RESOLVED 2026-08-26:** GameController now stores `eventTask`, cancels
it on re-subscribe, and clears `recentEvents` so a new game never shows
the previous game's feed. Static fix (parse-checked); exercised for real
in the macOS pass like the rest of the app target.

---

*(New entries are added the moment debt is knowingly incurred, not
discovered later.)*

---

## TD-003 — The map's rendering claims are compile-deep only
**Severity:** P1 for confidence, P0 for nothing — the code may be perfect; the
point is that nobody knows.
**Introduced:** map overhaul (MASTER PROMPT 2), 2026-08-29.
**Description:** `AirlineEmpireApp/Sources/Map/` (6 files, ~2,000 lines) is a
`Canvas` renderer, a camera, a hit-tester and a chrome layer. Everything about
it that matters is a runtime property: does the projection look right at each
zoom, do labels actually avoid each other on a 393pt-wide screen, does a
`SimultaneousGesture` of drag and magnify behave, does the 30fps timeline hold
403 flights on real silicon, does `DispatchQueue.main.async` from inside the
draw closure land before the next tap. A green macOS `xcodebuild` job proves
only that it compiles. Measured performance in this repo comes from
`ae-map-bench`, which times the **model**, on Linux, on a server CPU — it says
nothing about drawing.
**Resolution path:** `docs/APPLE_VALIDATION.md` gains a map section: simulator
at each zoom level, Instruments on a large save at 16x, VoiceOver over the
canvas, Reduce Motion, and a pass on the smallest supported screen. Until
then, no claim about how the map *looks* or *performs on device* is supported.

---

## TD-004 — Hit geometry is written from inside the draw closure
**Severity:** P2 (correct in practice, unusual by construction).
**Introduced:** map overhaul, 2026-08-29.
**Description:** `MapFrame` records the points it drew and `MapScreen` writes
them into `MapHitGeometry` from inside the `Canvas` renderer, so a tap
resolves against the frame the player actually saw rather than against a
recomputed layout. This is a side effect in a draw, which is not how SwiftUI
views usually behave. It is safe for one specific reason: `MapHitGeometry` is
a plain class and deliberately *not* `@Observable`, so writing it cannot
invalidate the view that produced it — observing it would be a redraw loop at
30 frames a second. The first version routed the write through
`DispatchQueue.main.async`. That compiled (CI run 33247689097) but bought
nothing: it cost a frame of staleness and leaned on the hop landing before the
next tap, to protect against a re-entrancy that cannot happen here.
**Resolution path:** if it ever misbehaves, compute the layout once per
snapshot outside the draw and have both the renderer and the hit-tester read
that, at the cost of doing projection work the frame will redo. Not done now
because it trades a real simplification for a hypothetical bug.

---

## TD-005 — Coastlines are hand-authored, at one level of detail
**Severity:** P3 (aesthetic ceiling, not a defect).
**Introduced:** map overhaul, 2026-08-29.
**Description:** `WorldGeometry.swift` carries 631 coordinate pairs across 24
landmasses, typed by hand. It reads well at world and regional zoom and gets
visibly coarse at local zoom, where a coastline is a few long straight lines.
Adding real Natural Earth data would fix the fidelity and cost a data pipeline,
a licence note, and a dependency the project has so far refused.
**Resolution path:** if local zoom becomes a place players spend time, import
Natural Earth 110m/50m as a generated Swift source at build time (no runtime
dependency, no network), keeping the hand-authored set as the low-detail LOD.

---

## TD-006 — Nothing in the audio system has been heard
**Severity:** P1 for confidence, P0 for nothing. The policy is tested and the
code compiles; whether the game *sounds* good is entirely unknown.
**Introduced:** audio architecture, 2026-08-29.
**Description:** `AirlineEmpireApp/Sources/Audio/` is an `AVAudioEngine`
graph, a voice pool, a haptic vocabulary and a settings bridge. Everything
about it that matters to a player is a runtime property: latency on a tap,
whether eight voices are enough, whether the category trims balance, whether
ambience is tolerable for an hour, whether the haptics read as weight or as
noise, whether `.ambient` behaves as expected against a podcast, and whether
any of the 52 synthesised assets are pleasant. This environment has no speaker
and cannot run a simulator. Core's policy is covered by 22 tests and the
assets are verified by measurement — format, peak, edges, ceilings — but
measurement is not listening.
**Resolution path:** task AE-026. `docs/APPLE_VALIDATION.md` gains an audio
section: every cue triggered once on device with the palette audible, a
16x fast-forward for spam, a save/load for BUG-013, a background/foreground
cycle, and an hour with ambience on. Until then no claim about how this sounds
is supported.

---

## TD-007 — The ambience beds are the weakest assets and the likeliest to be wrong
**Severity:** P3 (a setting that is off by default).
**Introduced:** audio architecture, 2026-08-29.
**Description:** `ambience_operations` and `ambience_world` are filtered noise
with a slow amplitude swell, crossfaded to loop seamlessly. A convincing
operations-room bed is a field-recording problem rather than a synthesis one,
and eight seconds of shaped noise is very likely to read as hiss rather than
as a place. They are off by default partly for the reason given in
`docs/AUDIO_ARCHITECTURE.md` §7 and partly because of this.
**Resolution path:** replace with recorded or professionally designed beds to
the brief in `docs/AUDIO_ASSET_MANIFEST.md` §4, or cut the feature. Cutting is a
legitimate outcome: the game is designed to be complete with ambience
disabled, and a bad bed is worse than none.

---

## TD-008 — There is no music, and the state machine for it is unbuilt
**Severity:** P3.
**Introduced:** audio architecture, 2026-08-29.
**Status: RESOLVED** by AE-AUDIO-01, later the same day. The selector this
entry called unwritten is `MusicDirector` in Core — five states derived from
speed, `SolvencyModel.stage` and whether a milestone is celebrating — driven
by `Feedback.applyMusic` with equal-power crossfades, and the `Music` toggle
and volume are in Settings.

Only the first half of the original complaint survives, and it has its own
entry: the four beds that exist are generated drones rather than a composed
score (TD-009). This entry is kept rather than deleted because the reasoning
it recorded — that a mediocre loop is worse than silence — is the reason the
milestone state deliberately has no track of its own.

---

## TD-009 — The music beds are drones, not a score
**Severity:** P3 (a deliberate ceiling, recorded so it is not mistaken for an
attempt that fell short).
**Introduced:** AE-AUDIO-01, 2026-08-29.
**Description:** four sustained pads ship — menu, planning, operating, crisis.
Each is two or three voices from the game's pitch set slowly detuning against
each other over a low noise floor. There is no melody, no rhythm, no chord
change and no development. That was chosen rather than attempted: a pad can be
made tolerable for an hour by construction, and a tune either develops (and
competes with the strategy) or repeats (and an hour of route planning becomes
an hour of the same eight bars). What ships is therefore the *floor* of what
music can be here, not an approximation of a score.
**Resolution path:** commission four tracks against `docs/AUDIO_ASSET_MANIFEST.md`
§5, which also lists two optional additions the state machine can already
carry. The states, crossfades, ducking and settings are built — adding a track
is dropping in a file with the right name.

---

## TD-010 — The soundscape's response curves are guesses
**Severity:** P2 (correct in structure, unvalidated in value).
**Introduced:** AE-AUDIO-01, 2026-08-29.
**Description:** `AmbienceDirector` is tested for its *properties* — that
growth moves movement and not level, that pause thins activity, that 16x is
not busier than 4x, that no combination exceeds full. Those hold. What is not
established is whether the specific numbers are right: 0.22/0.45/0.62 for the
three zoom levels, saturation at 24 airborne aircraft, ×0.15 for pause, ×0.75
for solvency danger. They were chosen to satisfy the properties and to sound
plausible on paper. Nobody has heard any of them, and the honest expectation is
that several will be wrong by a factor that only becomes obvious with a
speaker.
**Resolution path:** task AE-026. The numbers are all constants in one function
and are meant to be tuned there; the tests assert relationships rather than
values precisely so that tuning does not break them.

---

## TD-011 — The type scale exists; most call sites have not adopted it
**Severity:** P3 (a half-migrated token set is still better than none, but it
is not yet the single source of truth it claims to be).
**Introduced:** AE-028, 2026-08-30.
**Description:** `AEType` names eleven roles and the shared components
(`StatTile`, `AESectionHeader`, `AEBadge`, `AECompactMetric`, the button
styles) use it. Several hundred `.font(...)` call sites in feature screens
still name system sizes directly, so "restyle every metric label" remains only
partly a change one can make.
**Why it was not finished in one pass:** a mechanical sweep would have to guess
which `.caption` is a metric label, which is supporting prose and which is a
timestamp — they are indistinguishable at the call site, which is the whole
reason the tokens exist. Guessing wrong changes the proportions of every
screen, and there is no simulator here to look at the result. Converting a
screen at a time, while reworking it, is slower and correct.
**Resolution path:** convert with each screen's rework. The count of raw
`.font(` calls in `AirlineEmpireApp/Sources` is the progress metric; it was 291
when the scale was introduced.

---

## TD-012 — The summary read models are not wired into every screen that wants them
**Severity:** P3.
**Introduced:** AE-028, 2026-08-30.
**Description:** `NetworkSummary` and `FleetSummary` back Home's pulse, the
Fleet board header, the Routes board header and Finance's operating strip. What
remains is subtler than "the view does its own maths": the map's overlay hints
count `MapModel`'s *per-route health classification*, which is Core-computed, so
those views are counting Core's answers rather than inventing their own. That is
architecturally fine, and an earlier draft of this entry overstated it.

The real risk is narrower and was worth pinning down. `MapModel.health(of:)`
returns `.grounded` for `assignedAircraft.isEmpty`, and
`NetworkSummary.idleRoutes` counts exactly that population. Two Core functions,
one meaning, nothing connecting them — so the map's "N of your routes have no
aircraft" and the Routes board's "no aircraft: N" were two independent answers
to one question, free to drift the moment either definition was edited, with a
player having no way to tell which was wrong.

**Partly resolved 2026-08-30.** `SummaryModelTests.groundedAgreesWithIdle`
grounds a route and asserts the two agree; sabotaging either definition fails it
on both assertions. That is deliberately the cheap half — a test rather than a
refactor of view code nobody can see rendered. The duplication still exists; it
can no longer drift silently.
**Resolution path:** when the map chrome is next touched with a device
available, have the hints read the summary directly.

---

## TD-013 — Nothing checks that a value-based navigation link can resolve
**Severity:** P2 (three occurrences already: BUG-029, BUG-030 twice).
**Introduced:** pre-existing; named 2026-08-30.
**Description:** SwiftUI resolves `NavigationLink(value:)` against the
`navigationDestination`s declared by its host stack. A link whose type nothing
declares is silently inert — no warning, no crash, nothing visible in the file
that contains the link, and nothing a compile or a parse can catch. A shared
content view that gains a link therefore breaks every host that has not been
updated, and the breakage is invisible until somebody taps it.

Three have been found by hand so far. The audit that finds them is mechanical:
collect every `NavigationLink(value:)` and the type of its value, collect every
`navigationDestination(for:)`, and confirm each link type is declared by every
stack that can host that view.
**Resolution path:** a script in `scripts/` doing exactly that, wired into the
"App symbols resolve" CI job that already parses these files for AE types. The
hard part is the host graph — which stacks can push which views — so a first
version could simply require that any file containing a value link also
declares that type, or is documented as always hosted.


---

## TD-014 — Five aircraft types share one silhouette at one scale
**Severity:** P3.
**Introduced:** pre-existing; named 2026-08-30 while writing
`docs/AIRCRAFT_ASSET_BIBLE.md`.
**Description:** `AircraftCategory` has six cases; `AircraftSilhouette` draws
four planforms. `narrowbody` and `largeNarrowbody` share a shape *and* a scale,
as do `widebody` and `largeWidebody`. On the map that is correct — the
difference is 40 seats, which has no silhouette. In the market and on the
detail hero there is room to tell them apart and nothing does, so a player
comparing an MR180 against an MR220 sees the identical drawing at the identical
size beside two different seat counts. Five types share the narrowbody shape
and five the widebody; within those groups the artwork carries no information
at all.
**Resolution path:** a scale factor keyed on `AircraftCategory` rather than
`Planform`, applied only off-map. Not a fifth and sixth path — the shapes are
genuinely the same, only the size should differ. Needs a device to judge how
much difference reads without looking arbitrary.

---

## TD-015 — The fleet row uses an SF Symbol, not the silhouette
**Severity:** P3.
**Introduced:** pre-existing; named 2026-08-30.
**Description:** the market card and the detail header draw
`AircraftShape(category:)`; the fleet row draws `Vocab.categoryIcon`, a system
glyph that looks near-identical for a turboprop and a widebody. That is the
screen a player scans most often, and it is the one place the aircraft language
is not used.
**Resolution path:** swap the glyph for the silhouette. Deliberately not done
in AE-029: the row's spacing is already tight, and changing its leading element
without being able to look at the result is how a legible row becomes a
cramped one.

---

## TD-016 — The App target has no test that runs anywhere we build
**Severity:** P2 (it is the reason three separate defect classes stayed
invisible: BUG-029, BUG-030, BUG-033).
**Introduced:** pre-existing; named 2026-08-30.
**Description:** `AirlineEmpireCore` has 408 tests that run on Linux in CI.
`AirlineEmpireApp` has none that run anywhere. The macOS job compiles it,
which catches type errors and nothing else. So every app-layer contract —
that a rejection code maps to copy, that a navigation link resolves, that a
picker offers what the command accepts — is guarded only by review.

The pattern in this phase's bugs is consistent and worth stating: each was a
*string or type agreement* between the app and Core that no compiler checks.
Core-side tests can pin Core's half (`RejectionCodeContractTests`,
`AssignmentEligibilityTests` both do), which is genuinely useful and is not the
same as testing the app.
**Resolution path:** an `AirlineEmpireAppTests` target running under
`xcodebuild test` in the existing macOS job. The first three tests to write are
already known: every code in `Rejections.present` is one Core emits; every
`NavigationLink(value:)` type is declared by its host stack (TD-013); and
`Vocab` is total over each Core enum it words. None needs a simulator.

---

## TD-019 — Layout has no regression cover, on the one screen now known to break
**Severity:** P2.
**Introduced:** named 2026-08-30 (AE-031) alongside BUG-035.
**Description:** BUG-035 put a third of the Network tab into dead space and
floated its primary control mid-screen. It compiled, it parsed, 412 Core tests
passed, and the UI smoke test passed — because every one of those checks asks
whether an element *exists*, and none asks *where it is*.

XCUITest can answer that: `element.frame` is available, so "the section picker
sits in the top quarter of the screen" is directly expressible. It is not
written.

The general shape is worth stating, because it is the third distinct class of
defect this project has met that no compiler can see (after inert navigation
links and mismatched rejection codes): **a control that exists, is hittable,
and is in the wrong place.**
**Resolution path:** frame assertions on the handful of positions that carry
meaning — the section picker under the nav bar, the tab bar at the bottom, a
primary action inside the safe area. Not a general layout snapshot: those fail
on every deliberate change and get disabled within a month.

---

## TD-020 — The screenshot bridge is a log scrape
**Severity:** P3.
**Introduced:** 2026-08-30 (AE-031).
**Description:** CI base64s downscaled screenshots into the job log so the
agent doing the interface work can see them; artifacts need a credential it
does not have. It works — it found BUG-035 within minutes — but it is a
scrape: the log carries roughly 200 lines per screen, so only the last two or
three shots survive a practical `tail`, and adding screens quietly pushes the
earlier ones out of reach.
**Resolution path:** cap it deliberately rather than by accident — emit a
named subset (one per screen under review) at a smaller width, and let the
artifact remain the full-resolution record. Or, better, have the job fail the
build on a frame assertion (TD-019) so the screenshots become evidence for a
human rather than the primary check.
**Amended in AE-032:** the tail cap is defused, not fixed. A run's complete
logs are downloadable with **no credential** — the API's
`get_workflow_run_logs_url` returns a signed zip link — and
`scripts/decode-ci-screenshots.py` turns any job log into PNG files. Every
frame of runs 59 and 60 was recovered this way, including two that changed
the phase (the byte-identical zoom "levels", the Finance screen filed under
a map name). The scrape remains the delivery mechanism; it is no longer a
window that silently discards the early journey.

## TD-021 — One seed, one starting city, and no antimeridian route ever drawn
**Severity:** P3.
**Introduced:** named 2026-08-30 (AE-032).
**Description:** every UI journey founds the same airline in the same world:
Stockholm start, London as top suggestion. Nothing has ever rendered a route
crossing the international date line, so the classic world-spanning-line
defect class is unobserved — not absent, unobserved. The route sheet also
only offers markets near the start city that early aircraft can reach, so
the journey cannot organically produce one.
**Resolution path:** a UI-test launch argument that founds in a Pacific-rim
city (or loads a prepared save with a TKH-bound long-haul route), then the
map matrix's D case — photograph the date-line crossing at world and
regional zoom.

## TD-022 — The ambient map timeline stays at 30 Hz

The map's `TimelineView` ticks at 30 Hz when nothing is touching it — a
deliberate battery choice from the map overhaul. The AE-034 brief targets
60 FPS; after the render cache, gesture- and animation-driven invalidations
already redraw at event rate during interaction (where responsiveness is
felt), so the ambient cap now only limits idle flight motion. Raising it
doubles idle draw work for smoothness only a device can judge — so the
decision waits for hardware evidence (APPLE_VALIDATION §4, Instruments),
not a simulator number. Revisit with a measured device frame budget.

## TD-023 — Pan absorbs the finger at the world's edge

`MapCamera.clamp` hard-pins the centre during a drag, so dragging at the
map's y-limits eats finger motion silently and resuming reads as a jump
(MAP_RUNTIME_BASELINE §4). The zoom limits got resistance-and-spring
treatment (`pow(overshoot, 0.30)` + spring back); the pan limits should get
the same. Not done in AE-034: the P0s were measured problems, this one is a
READ-level polish item nobody has yet reproduced on a device. Do it with
eyes on a screen, not blind.

## TD-024 — Cache counter assertions await their first counted run

The render cache counts every rebuild by cause and the probe publishes
them, but run 85's log carries no counters (the test's forwarding regex
predated the `placements` token — fixed the same day). The structural
targets in `docs/MAP_PERFORMANCE_TARGETS.md` (D1: no rebuilds mid-drag;
L1–L3: placements ≈ settle events) should become CI assertions, with
bounds taken from the first run that actually prints MAP-CACHE lines —
pinning bounds before seeing one counted run would be inventing the
tolerance. One run of evidence, then assert.

**Resolved.** Run 87 delivered the counted run: 24 rebuilds / 312
replays / 14 placement runs across both drag sequences (168 frames),
placements matching settle events exactly in all three sequences. The
baseline test now asserts rebuilds ≤ 60, replays ≥ frames, and
placements ≤ 40 across the drags — 2–3x the measured deltas, tight
enough that per-event rebuilding cannot pass.


## TD-025 — The UI suite ran serially because it was one class

**Symptom.** A full UI run took **26 minutes** of wall clock (1,513 s of
test time in run 103) on a machine with cores to spare.

**Root cause.** XCUITest distributes work by test *class*. All eighteen
tests lived in `PlayerJourneyUITests`, so no xcodebuild flag could have
parallelised anything — there was only ever one unit of work.

**Fix.** The suite is four classes, balanced by measured duration:
`CampaignUITests` (456 s), `EconomyJourneyUITests` (474 s),
`ShellAndMapUITests` (485 s) and `PerformanceBaselineUITests` (113 s). CI
runs the measurement class **first and alone** with parallelism off, then
the other three on cloned simulators, three at a time.

**Why the measurements are separated.** Map rebuild/replay counts and cold
launch are the only figures this project treats as evidence. Measured
against three competing simulators they would not be comparable with
`docs/MAP_P0_PERFORMANCE_REPORT.md`, and a benchmark that is not
comparable is not a benchmark.

**The second cost, found by measuring the first attempt.** The
measurement pass spent **9 m 55 s running 113 s of tests** (run on
c77d651). `Build for the simulator` was a plain `build`, which does not
produce the test bundles, so every `xcodebuild test` compiled them again
— and splitting the suite into two passes paid that compile twice. The
build step is now `build-for-testing` and both passes are
`test-without-building`.

**Expected.** one build + ~113 s serial + ~485 s parallel. NOT VALIDATED
until a run reports it; the class durations above are MEASURED from run
103 and the 9 m 55 s overhead is MEASURED from the first attempt.


## TD-026 — Rivals do not enter a pair the player already flies

**Symptom.** MEASURED (AE-037, `ae-rival-probe`, five years from three
homes with the BUG-042/043 fixes in): no rival ever opened a route on a
pair the player was flying. Every player-rival contest in the game is the
player's doing.

**Root cause.** `CompetitorAISystem.bestMarket` scores candidates as
`demandPool / (incumbents + 1)`. Halving a market per incumbent means a
contested pair only wins against *every* open candidate among the sixteen
nearest airports — which, with 94 airports and five rivals of at most five
routes each, never happens except on the world's largest pairs
(London–Paris is contested rival-to-rival by day 4). The design accepts
contested markets at half value; it did not anticipate that there would
always be an open one.

**Why it is debt and not a bug here.** AE-037 was explicitly not to
rewrite the AI, and the demand engine's real split gives a second entrant
roughly two thirds of a monopolist's take, not a half — so the honest fix
is to score with `DemandSystem.expectedCapturedPassengers` against the
incumbents' actual offers, which is a scoring change with balance
consequences (`tenYearWorldRemainsStableAndContested`'s HHI bound, the
AI collapse rate). That is a phase's work, and it is the recommended next
one.

**Expected.** A rival entering the player's Stockholm–London when the
player is the only carrier on a large pair; the Home headline
`rivalEnteredYourMarket` firing in a plain campaign without the player
picking the fight. NOT VALIDATED.

**AE-039 (2026-09-02): the horizon half measured and dismissed.** At 24,
48 and all 93 airports the rivals reached exactly the same player pairs
as at 16 (docs/HORIZON_AUDIT.md §3.1): the distance list was never the
binding constraint, the passenger ranking was. Ranking by airframe-day
revenue (shipped) brings the world to Munich on day 61 and to Singapore
in year two; Stockholm and Barcelona are still not reached within two
years — Stockholm is reached only on the profit basis at a horizon of
24, which this phase measured and withheld (TD-030). What remains of
TD-026 is now an economy question, not a horizon one.

**AE-038 (2026-09-02): narrowed, not closed.** The scoring half is done:
`DemandSystem.poolAvailableToEntrant` replaces the halving, and across
240 scanned campaigns world-initiated entries rose from 30 (New York
only) to 95 (New York, São Paulo, Dubai) with every Core test green
(docs/RIVALS_THAT_COME_TO_YOU_AUDIT.md §2.1). What remains is the
**candidate horizon**: a rival scores only the sixteen airports nearest
to where its airframe sits, so it can only come to a pair whose far end
is one of its bases, and no rival base can see Stockholm at all. From
the curated European starts the world still does not move first within
two years. Fix shape: a demand-ranked horizon (the top N pairs by pool
from the base, within the airframe's range) beside or instead of the
nearest sixteen — a change to where every rival flies, to be measured
with `ae-rival-scan` and the ten-year world test before it is kept.

## TD-027 — The route record has no opening date

**Symptom.** "Since you arrived, Aurora added sixteen daily rotations" is
a sentence the game cannot say: `Route` has no `openedAt`, and rival
frequency and fare changes are not recorded anywhere (the market-move
record deliberately keeps entries and exits only, so that a fortnight of
weekly frequency pushes cannot roll the record over).

**Cost.** The route screen shows rivals' *current* offers and the split;
the UI journey photographs the day of entry and a week later to show the
change, but the screen itself cannot narrate it.

**Fix shape.** `Route.openedAt` (save bump) plus a per-route "offer at
your entry" snapshot for contested pairs — small state, one migration.
Worth doing when TD-026 makes rival responses a routine sight.

## TD-028 — Two save fixtures ride the UI test bundle

**What.** `AirlineEmpireApp/UITests/Fixtures/rival-pressure-retreat.json`
(day 249 of the seed-2039 fight campaign) and
`rival-pressure-late-game.json` (day 1825), ~400 KB each, written by
`ae-rival-probe --save` and loaded under `-AEUITestLoadSave`. They are how
COMP-05 and COMP-07 are photographed: a rival's retreat lands on day 248
and the late game is ~1,800 sunrise taps away.

**Debt.** Save format v12 is baked into the files. A future format bump
still loads them (the migration chain runs on load), but any change to
the campaign script, the cast rule or the AI makes them a *different*
world from the one `RivalPressureCampaignTests` measures. Regenerate with
`swift run -c release ae-rival-probe 2039 249 ARN LHR-CDG:0.88 --save …`
and `… 1825 …` whenever the twin's numbers move.

## TD-029 — The regional archetype has no profitable market at hub fees

**RESOLVED 2026-09-02 (AE-040):** the cause was BUG-051, the movement fee
not scaling with the aircraft, not the archetype. After the fix the
turboprop has 374 profitable candidates of 542 worldwide (40 before), 11
from Paris (0), and the regional rival is alive in 150 of 150 campaigns
with earning routes (docs/REGIONAL_ARCHETYPE_AUDIT.md §5).

**Symptom.** MEASURED (AE-039, `ae-rival-scan --horizon --profit`): with
markets scored by what an airframe day keeps after the flight system's
own costs, SwiftJet — the regional archetype, 70-seat turboprops at the
reference fare — has zero viable candidates from Paris, Chicago or
anywhere else in the world it can reach. The ledger agrees: its
New York–Chicago lost $277k a month at 100% load, Chicago–Toronto $953k.
Under the shipped revenue ranking it still flies (and still loses), as it
did under the passenger ranking; AE-037 saw it grounded or collapsed in
the late game.

**Cause.** `AirportSpec.movementFee` at large airports against a 70-seat
cabin; the archetype's preferred categories are turboprop and regional
jet, its geography its home region, its fare factor 1.0.

**Fix shape.** An economy decision: lower fees at smaller airports (the
catalog has few), a higher regional fare factor, or a different starter
type. Any of them changes the player's economics on the same routes.
Out of scope for a horizon phase.

## TD-030 — The profit ranking, measured and withheld

**Re-measured 2026-09-02 (AE-040):** on the corrected economy the
regional archetype functions on the profit basis (150 of 150 alive), but
at the shipped horizon the basis reaches fewer player markets than the
shipped one (31 world-initiated entries against 60 across 150 campaigns;
Singapore's arrival does not happen). Still withheld; recommended as a
phase of its own together with the horizon-24 measurement
(docs/AE040_FEE_ECONOMY_REPORT.md §9, §16).

`CompetitorAISystem.airframeDayValue(basis: .profit)` — the revenue
basis less the flight system's costs — reaches the curated first start:
with a horizon of 24, PacificBlue enters Stockholm–Istanbul on day 187 of
every scripted seed (docs/HORIZON_AUDIT.md §4). It is not shipped because
it freezes the regional archetype (TD-029) and puts three of fifteen
archetype runs over the balance battery's 60% margin line (64–65%), and a
test is not weakened to go green. The scan and probe carry `--profit` so
the measurement can be repeated once TD-029 is decided.

## TD-031 — The reference route P&L was never reconciled line by line

**Symptom.** MEASURED (AE-040, docs/FEE_ECONOMY_BASELINE.md §6.4):
docs/GAME_BALANCE.md §4 gives the per-flight P&L the economy was to be
tuned against (narrowbody, 1,100 km, 78% load: fuel $4.9k, crew $2.3k,
airport/handling $3.2k, maintenance $2.4k, ownership $3.1k, overhead
$1.3k on $18.1k of revenue, ~5% margin). The game's anchor fixture lands
near the total ($16.5k against $17.2k) with none of the lines in place:
fees 1.6× the anchor, ownership 2×, fuel ½, crew ½, maintenance ⅒
(the fleet system's checks book about $0.2k per flight against a
$2.4k reserve). The anchor test only requires a positive result.

**Cost.** Fees lead every cost line under 1,600 km for every aircraft and
short haul under 400 km is fee-bound for everyone (the arrival passenger
fee alone is 40–45% of a $60–69 fare at LHR, CDG or JFK); fuel, the cost
the design expects to lead and the one the world's fuel walk moves, is
4–12% of revenue on short routes, so fuel shocks under-bite. The
composition is what the batteries are calibrated on, so no single line
can be moved alone without moving the anchor's margin.

**Fix shape.** A reconciliation pass on the reference P&L as a whole —
fee level, fuel price or burn, crew rates, the maintenance check cadence,
lease rates — one anchor at a time against `BalanceTests`, with the
per-line test §4 promised (±10%). A whole-economy phase; AE-040 fixed the
fee *scale* (BUG-051) and left every level where it was.

**Also seen (MEASURED, AE-040):** no aircraft can fly a round trip longer
than about eight hours one way because the scheduler needs the whole
round trip inside the 18-hour operating day (LHR–SIN has zero rotations
for every type); a full schedule loses 6–25% of its rotations to delay
cascades and expiry; widebodies are era-locked for the player and not
for rivals.
