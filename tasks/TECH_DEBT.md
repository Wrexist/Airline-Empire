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
**Severity:** P3 (a deliberate omission, recorded so it is not mistaken for an
oversight).
**Introduced:** audio architecture, 2026-08-29.
**Description:** the game ships no score and no music toggle. The reasoning is
in `docs/AUDIO_ARCHITECTURE.md` §11: this phase can synthesise effects to a
shippable standard but cannot compose and produce releasable music, and a
mediocre loop is worse than silence for a game that wants to sound expensive.
What exists is the brief — six tracks, their states, lengths and character —
in `docs/AUDIO_ASSET_MANIFEST.md` §5. What does not exist is any code that selects
between them; the selection is derivable from `SolvencyModel.stage`, route
count and era, all of which Core already publishes, but none of it is written.
**Resolution path:** commission the six tracks against §5, then add the
crossfading selector to `Feedback` and a `Music` toggle to Settings. Not
before: a switch controlling nothing is a dead control.

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
