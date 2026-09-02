# Current Phase

**AE-037 — Rival pressure. (Make the world push back.)**
2026-09-01.

The brief: the Core has competitors, price competition and reputation —
can the player *see* any of it? Measure first. `ae-rival-probe` (new
executable) replays the seed-2039 campaign and diffs every rival's state
day by day, and the answer was worse than "invisible": from Stockholm,
Barcelona and Singapore alike, **no rival ever entered a player market in
five years, and no rival ever opened a second route.** Two structural
causes, both fixed at the source with one guard each (BUG-042: an AI's
idle aircraft always joined its one full route, sixteen airframes on a
pair that could use ten, three of five rivals collapsing under bills for
parked metal; BUG-043: the cast was founded at Tokyo, Jakarta, Delhi,
Shanghai and Seoul, and an AI only expands from where its aircraft sit).
With both in, rivals build real hub networks — Istanbul, London, Paris for
a Stockholm player — and fight each other by day 11. They still never
enter a pair the player already flies: the scoring halves a market per
incumbent and an open one always remains. Recorded as TD-026, not
rewritten: competition on the player's pairs is player-initiated, which
the design lists as intended.

So the phase measured the fight that exists. Entering London–Paris under
two incumbents at 0.88× reference: the premium rival cut its fare and added
a rotation **the next morning**, both climbed to twenty rotations a day
over four months, the player held an exact third of the market at full
load and lost ~$90k every month, and the regional rival gave up on day
248. Of those rival moves, the feed carried **none** — price and frequency
commands emit no event, and a rival's route events were (correctly)
filtered as its private business (BUG-044, P0 by this phase's ranking).

**Shipped:** `world.marketMoves` (save v12, migrated), `marketEntered` /
`marketLeft` events admitted to the feed only on the player's own pairs,
`MarketCompetition` and `CompetitionSummary` — standing against an even
split, the dominant attractiveness term as the *why* from the demand
engine's own factors, and one prioritised headline. Route detail leads its
competition section with the standing sentence, a share bar and the named
response; Home carries one rival fact only when there is one; the World
hub's badge and line are about the player; Competitors is ordered by
pressure with contested routes as links; the map hint counts contested
routes. `RivalPressureCampaignTests` is the deterministic twin of the UI
journey's fight; two probe-written saves (day 249, day 1825) let the
retreat and the late game be photographed. Core: 415 → 427 tests, all
green on Linux; release builds clean with warnings as errors. Evidence:
`docs/RIVAL_PRESSURE_AUDIT.md`.

**Observed (runs 112–113, 138 frames decoded and read):** the route
sheet's "2 airlines already fly it" for London–Paris from London; the
route screen's standing sentence, share bar, per-rival share and the
named response ("An even fight — 51% of today's passengers against 1
rival, mostly because they fly more often" / "Answer with frequency");
Home's one rival fact on three worlds ("SwiftJet pulled out of CDG–LHR
yesterday — the market is yours again", "One of your routes is contested
— an even fight so far", "SwiftJet added 2 routes this month, at
airports you serve"); the World hub's "1 contested" badge and line; the
Competitors screen's position strip, contested-route link and
pressure-ordered rivals; the map hint. Three defects the frames found are
fixed (a grounded rival read as sharing an airport; the morning of entry
read as "losing at 0%"; a rival's expansion outranked the player's own
fight on Home). UI: 17 of 18 journeys green in run 113, the campaign
stopping on its own identifier query with the card in frame; run 114
(16 of 18 green, KEY-43 now showing the player's own fight leading Home)
was cut by the macOS job's 45-minute cap with the campaign and the
flight journey still running — both "failures" carry the cancellation's
timestamp. The cap is 60 minutes, CI now prints assertion texts from the
result bundle, and the campaign carries on past a failed card query so
KEY-44 … 46 get photographed. Run 115 (53 minutes, 17 of 18 green,
flight journey back to green): the World hub's "1 contested" line and
the Competitors screen during the fight (SwiftJet's two openings at
Paris, Aurora's at London, LHR–CDG even at 31%) are OBSERVED; the one
red was the journey opening Stockholm–London instead of London–Paris
(row query matched the first LHR row; fixed to require both codes).
Run 116 (36 minutes, 17 of 18 green): KEY-44 OBSERVED on London–Paris
— "An even fight — 31% … mostly because they fly more often", SwiftJet
at 4×/day a week after entry — so every COMP state is now photographed
from the live campaign or a save. Its one red found BUG-045: the guided
route sheet from Home could present before its suggestion landed and
open empty, and the campaign opened Stockholm–Tokyo from it (bare all
spring). Fixed with item-driven presentation; `NextMovesServabilityTests`
pins that the card's ranking was never the problem. Core 430/430 on
Linux; run 117 dispatched.

---

# Previous Phase

**AE-033 — The command map. (Immersion & professional UX pass.)**
2026-08-31.

The brief, from design review of run 69's frames: the map renders correctly
but reads as a diagram — information density too high when zoomed out, all
airports visually equal, routes mute about economics, chrome heavy. The
instruction that governs every choice here: *"Do not add random visual
effects everywhere. The goal is a clean command map where the world becomes
richer as you zoom in."*

What already existed (verified before adding anything): route health
colours/dashes, frequency-weighted stroke widths, the double ember home
ring, moving aircraft with trails interpolated between ticks, and the
camera framing home on open. The gaps were density, hierarchy accents,
route glow, and any sense of planetary time.

**Shipped in this pass:**
- **Density ladder tightened.** Label reveal thresholds are now
  major ≥ 2.8×, regional ≥ 5.0×, small ≥ 8.0× (global hubs always), and
  the label budget starts at 6 at world zoom — the world view shows only
  the hubs and the player's own network.
- **Airport hierarchy.** Global hubs carry a second faint ring (the ◎
  read); the selected airport breathes — an animated pulse ring driven by
  the canvas clock; home keeps its unique double ember ring.
- **Route glow.** Player routes get a soft under-stroke halo so the
  airline's own network reads as alive against competitor lines.
- **Day/night terminator.** Two soft fills (α 0.14 + 0.10 inset 6° toward
  the dark pole) sampled from the game clock — subsolar longitude at 15°/h,
  declination by day-of-year. Cartoon astronomy, drawn under everything.
- **"Network" tab → "Airline"** (icon now `airplane`), with the onboarding
  hints and all UI-test drivers renamed to match.

**Deliberately not done, and why:** weather cells and city lights (effect
noise, the exact thing the brief warns against); shrinking the tab bar
(system-controlled); renaming the sunrise control (it is *advance to next
morning*, an action — a Day/Night label would misdescribe it); map-mode
redesign (the overlay picker already has five modes; relabelling without a
design is churn); camera-on-open (already frames home).

**Render verification (runs 73–74, looked at, not assumed):**
- Density ladder **OBSERVED** — the world view labels only the global hubs
  (MEX, GRU, DEL, HND, CGK) and the player's home; regional and local
  zooms reveal the full "Arlanda (Stockholm)" ladder exactly as designed.
- Terminator **OBSERVED and measured** — a pixel-brightness profile along
  a fixed latitude of run 73's world frame shows the night band centred
  on longitude 0 at the game's 00:00, with the two-pass dusk ramp
  (medians 48 → 43 → 41) and a width matching the terminator equation at
  that latitude. Run 74's in-flight frames show the January arctic night
  correctly darkening northern Scandinavia. Subtle by intent: on the dark
  ocean it is a measured ~15% dim, not a hard edge.
- "Airline" tab **OBSERVED** in light and dark with the airplane icon;
  every tab-navigation test passed under the new name.
- Route glow and moving aircraft **OBSERVED** — run 74's flight journey
  went green and photographed the aircraft mid-route Arlanda → Heathrow
  at 16× on the player-blue haloed line.
- Selection pulse **NOT OBSERVED** — it animates on a selected airport
  and no automated frame selects one; the drawing code is exercised by
  every map render, but the pulse itself awaits a human eye or a new
  journey leg. Recorded so a future still is not misread either way.
- Run 73: 12/14 UI tests; run 74: 13/14. The only failures were the
  documented lease-tap flakiness (four attempts, healthy market in every
  attempt frame; the identical helper leased successfully inside run
  74's flight journey minutes later). Core 414/414 in both runs.

---

# Previous Phase

**AE-032 — Visual truth. (Verify the verifier, then observe what was never
observed.)**
2026-08-30.

The brief: close the gap between what the project claims works and what has
been seen working. Method: decode every CI run's screenshots (the full logs
are downloadable without a credential — `scripts/decode-ci-screenshots.py`),
look at them, fix what the frames show, and label every claim OBSERVED /
ASSERTED / READ / NOT VERIFIED. Eight CI runs (59–66+) each taught something.

**The defining finding — BUG-040, P0: the game has never run.** The
simulation pump was armed only by a scene-phase *change*, which fires at
launch on the menu — where no session exists, so the guard returned — and
nothing armed it again when a game was founded or loaded. Selecting 16×
highlighted the control and moved nothing; runs 64 and 65 photographed an
aircraft assigned to a route with the clock still at day one, 00:00, minutes
later. Every screenshot of every phase before this was of a frozen world
that looked correct. Fixed at the source (`startNewGame`/`loadGame` call
`setPumping(true)`; the scene handler keeps suspend/resume and gains
`initial: true`); `testTheClockActuallyRuns` is the dedicated guard, and it
passed in run 67 — the closing frame shows Home at **2030-01-03**, the first
photograph of a running world in this project's history.

**The evidence system had been lying, and was fixed first (BUG-038/039):**
the zoom test's three "levels" were byte-identical frames and its zoom-out
frame was the Finance screen; the route journey tapped the From picker as a
destination and a button that never existed. The camera now publishes its
zoom for assertion; every journey step proves causality before the next.

**Product fixes, each confirmed against rendered frames:** BUG-037 (Core
rejections printed raw cents — `Money.compact`), BUG-038's UX half (the
route commit sat below ~40 candidate rows; now a bottom bar), BUG-036
visually confirmed fixed, chips/Home header/metric strip at accessibility
type sizes, the market sort segment truncation, and airports said the way
people say them — "Sjövik (Stockholm)" — on the map, route sheet and
browser, with graceful city/code fallback (observed on iPhone and iPad).

**Observed for the first time:** aircraft detail, route detail, Settings,
all five tabs dark and light, six genuinely distinct map zoom/pinch frames,
Dynamic Type at AccessibilityL, and the iPad regular-width shell (sidebar +
map, five tabs green in runs 63/66). **Asserted:** the audio pipeline starts
with all ~54 cues decoded; cold launch 2.61 s median; camera zoom via
buttons, double-tap and pinch; the full lease→route→assign chain (each step
green in at least one run). **Run 69 closed the loop:** the first fully green
CI run in the project's history — 414 Core tests on the 94-real-airport
world and 14 of 14 UI tests, the complete flight journey included. The
frames show the aircraft en route Arlanda (Stockholm) → Heathrow (London)
at 16×. The iOS 26 runner's tap synthesis remains the flakiest part of the
harness (runs 61–66 each saw a different journey leg miss; one failure
frame was the iOS Settings app) — recorded as a warning for future legs. Still not verified:
system-appearance following, game over, VoiceOver order, audio audibility,
hardware anything, antimeridian routes (TD-021).

Core: 414/414 on Linux, release clean. Benchmarks: 1 game-year 1.65 s
(small) / 13.6 s (large); map model 2.2 ms/call on a 200-route world; saves
≤ 605 KiB. See docs/UI_RUNTIME_VALIDATION.md §7 and docs/UI_FULL_AUDIT.md §5.

---

# Earlier

**AE-031 — The app runs. (Premium game feel, phase 1.)**
2026-08-30.

The brief asked for immersion and polish. The audit said the binding
constraint was not design: four consecutive phases had shipped interface work
and every one ended "authored, not observed", because `project.yml` declared a
single target and CI built against `generic/platform=iOS Simulator`, which
never boots anything.

So this phase built the missing thing. `AirlineEmpireUITests` is the first
target that runs the app rather than compiling it; CI boots a real simulator,
drives the first minute of the game, and keeps a screenshot of every step.
Because artifacts need a credential the agent doing the work does not have,
the screenshots are also base64'd into the job log, downscaled.

**It paid for itself immediately.** The first screenshot showed BUG-035: a
third of the Network tab was dead space and the Routes/Fleet picker floated
40% down the screen, in the state every new game starts in. One SwiftUI
default caused both gaps — a compact empty state centres in a parent it does
not fill, and `safeAreaInset` then anchors to the content's top edge rather
than the container's. Fixed and re-confirmed by screenshot.

It survived four UI phases because it appears *only* in the empty state: a
list fills its parent and has nowhere to float to, so every screen anybody
would think to check looked right.

Also now visually validated: AE-029's market work renders as intended —
aircraft roles, seat-efficiency bands, the trade sentence, the era-lock
explanation.

**Not done, and owed:** the full screen-by-screen audit covers only what has
been seen. Home, Map, Finance and World are proven to load and render content
but have not been looked at. The app has been observed in exactly one
appearance — light — which is not the one `DESIGN_SYSTEM.md` is written about.
See `docs/UI_FULL_AUDIT.md`, which marks every finding by whether it was
observed, asserted, or merely read.

---

# Earlier

**AE-029 — Fleet and aircraft experience (MASTER PROMPT 5).**
2026-08-30.

The audit found the phase's shape immediately: most of what §9–§15 asks for had
landed in AE-028, and what was actually broken sat underneath it. Both
assignment pickers — the one place the game's central loop is completed — were
re-deriving Core's eligibility rules and getting them wrong in three separate
directions at once (BUG-032). Three refusal mappings had been switching on
strings Core has never emitted, so the copy for the two most confusing refusals
in the fleet flow was unreachable (BUG-033).

Load-bearing change: `AssignmentEligibility` in Core, mirroring
`AssignAircraftToRouteCommand.validate` beside the validator itself, with a
test that drives every aircraft against every route and asserts the two agree.
Both screens render it; neither decides anything. Ineligible pairings are shown
with their reason rather than omitted.

Also: `AircraftRole` and `SeatEfficiencyBand` (§10) — the market printed fuel
burn per seat to three decimals, a number nobody can rank, and banding it
surfaced that a turboprop burns ~72% more fuel per seat-km than a large
narrowbody. `FleetFilter` in Core (§17, §37), tested for partitioning the fleet
rather than losing rows.

**Content audit (§38, §39), not acted on deliberately.** `docs/AIRCRAFT.md`
claimed "±15% per-type personality"; the catalog's largest within-category
fuel-per-seat spread is 4.5% and most are under 2%. Types separate by size and
reach, not by economic character. NA160 is beaten by MR180 on seats, range,
cost per seat and burn per seat — its only remaining niche is a lower absolute
price. Both pinned by characterization tests rather than rebalanced, per §38.

Four bugs found and fixed: BUG-032, BUG-033, BUG-034 (an aircraft in a
maintenance check described as idle). Three tech debt entries added: TD-014,
TD-015, TD-016.

**Nothing in this phase has been seen rendered.** 408 Core tests pass, up from
381; the app compiles on macOS CI and has never been launched.

---

# Earlier

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

Five bugs found and fixed: BUG-027 (live flights counted the whole world),
BUG-028 (a save warning followed the player into the next game), BUG-029 and
BUG-030 (dead navigation links on three entry paths), and BUG-031 (derived
caches keyed on the tick, so a paused player's own command changed nothing on
screen — found by CodeRabbit, and older than this phase). One component defect
found by reading the code against its own documentation: `AEMetricStrip` could
not wrap.

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

**2026-08-31 (AE-034 — map performance, measure→fix→verify).** The
baseline probe (run 84) measured the two P0s: every gesture event rebuilt
the entire scene (16.84 ms avg / 256 ms worst during drags) and labels
re-decided placement per frame (3.92 identity changes/frame while
panning). Fixed at the root: `MapRenderCache` (geometry built once per
deliberate cause, replayed under one affine transform per frame, every
rebuild counted by reason) and label placement memory (decisions at
settle points, reprojection between, enter/keep hysteresis). Run 85, same
workload: slow-drag avg 11.39 ms (−32 %) at +81 % frames drawn, fast-drag
11.40 ms (−48 %), worst frame anywhere now the map-open build (169 ms);
churn 1.35 (−66 %) and hops 0.40 (−77 %) during slow drag. Zoom-cycle
hops/frame rose 8.72 → 10.20 (re-decisions per fewer frames — stated, not
hidden). 414/414 Core, map baseline test green both runs; 12 map frames
visually inspected, no cache defect classes found. Full evidence:
`docs/MAP_P0_PERFORMANCE_REPORT.md`; architecture:
`docs/MAP_INTERACTION_ARCHITECTURE.md`; audits:
`docs/PLAYER_JOURNEY_RUNTIME_AUDIT.md`,
`docs/GAME_EXPERIENCE_PRIORITY.md`.

## Next

One verification rides the next CI run: the campaign journey's February,
which must end with four routes and none of them bare before March can be
asked whether the era arrived (FE-05). Its diagnostics — `FEB-*`,
`BARE-*`, `KEY-32b-network-after-february`, and the mission-completion
morning `KEY-30b` — are there to name the failing step rather than the
failing assertion. After that,
`docs/GAME_EXPERIENCE_PRIORITY.md` is the ranked backlog (EXP-08 is the
newest entry); remaining Apple-runtime validation is enumerated in
`docs/APPLE_VALIDATION.md`.

**2026-09-01 (first-session phase, post-#11).** The audit's ranked top of
the backlog, landed as one pass: `NextMovesCard` takes over Home when the
checklist retires (EXP-01 — idle-aircraft warning + top two
`marketOpportunities`, same guided-route flow); the Fleet and Routes
summary strips gate their aggregate columns behind four rows (EXP-02 —
averages over three rows are the rows); the celebration overlay now says
what each milestone *means* (`Vocab.milestoneDetail` — "Your first flight
has landed — the first ticket revenue is in the bank"), and the four
digit-coded milestones got real titles. The flight journey test drives to
first landing and asserts the checklist→Next-Moves handover, capturing
the post-checklist Home for the first time. Validation: next CI run.

**2026-09-01 (AE-034 "The First Month" — the never-seen states, seen).**
Runs 94/95: a new journey drives the real engine to 2030-02-01 with 31
sunrise taps (synchronous day simulation, zero wall-clock dependence) and
the frames photographed every state the project had only ever READ: the
month-end close, "Last month $959k" on Home, the "First profitable month"
celebration with its detail line, the JAN 2030 STATEMENT with per-category
rows and the green no-burn forecast, the route's month ($1.9M last full
month, 98% punctuality), and the World hub's live lines with real data.
The first month is PROFITABLE through the real economy. 17/17 UI, 414/414
Core, counter assertions held. EXP-03 partially fixed (two of three cases
observed fixed; FM-03 records the survivor), EXP-04 deferred with reasons,
EXP-05 fixed and observed, EXP-06 improved (residual ghosting, thickened),
EXP-07 implemented (feel not claimed). Evidence:
docs/FIRST_MONTH_RUNTIME_AUDIT.md.

**2026-09-01 (AE-035/AE-036 — the first era, and the next decision).**
The Core twin (`FirstEraCampaignTests`) proves the campaign deterministic
before a simulator ever runs it: seed 2039 reaches the Regional gate on
day 59 with statements of $2.0M and $5.4M, one boom on day 8, its mission
completed day 11, four profitable routes and $17.3M cash. AE-036 corrected
AE-035's own premise from the code: the recommender never proposed the
unflyable route — it filters by fleet eligibility — so the defect was one
layer down, in the free-form sheet's silence at the commit. Fixed with
`MarketOpportunity.servableByEra`, which distinguishes "nothing in your
fleet can serve it — the market sells aircraft that could" from "beyond
this era's aircraft — a route for a later fleet", and a commit caution
that **warns without blocking**. Both are now OBSERVED (run 102, KEY-38 and
KEY-39: the caution reads "No aircraft of this era can fly this — it will
wait, unflown, for a later fleet" with "Open this route" still enabled).
The symbolic mission reward was root-caused rather than patched — an
unserved region has zero seats, so the per-pax target bottoms out at the
500-passenger floor and paid $20k against multi-million-dollar months —
and fixed with `boomRushRewardFloor` ($250k) in tuning; OBSERVED on
KEY-30. **Not yet observed: the era transition itself.** Run 102's
scripted campaign reached March with a smaller airline than the twin
builds on the same seed (four aircraft, three routes, two idle), so the
gate correctly read "2 of 3" — the game's arithmetic is right and the
shortfall is the journey's (FE-05). Two silent skips in the script that
made this undiagnosable now retry, photograph every miss, and assert
their effect. New finding EXP-08: the Home feed keeps the last fourteen
*events*, not fourteen days, so a completed mission leaves no trace on
Home within a simulated week. Evidence:
docs/FIRST_ERA_RUNTIME_AUDIT.md, docs/DECISION_EXPERIENCE_AUDIT.md.
