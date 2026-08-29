# Audio and feedback architecture

How Airline Empire decides what to be heard doing, and what makes the noise.

Written at the end of MASTER PROMPT 3, when the game went from having no audio
at all to having a complete semantic sound language. Read `docs/AUDIO_ASSET_MANIFEST.md`
for the assets themselves and the briefs for replacing them.

**Status, stated the way this project always states it:** the policy is
**tested** (19 tests, Linux). The app layer is **built** (macOS CI,
`xcodebuild`, Xcode 26.6). None of it has been **runtime validated**, and
nobody has **heard** a single sound. See §12.

---

## 1. The audit this replaced

| Question | Answer before this phase |
| --- | --- |
| Audio code | None. Zero references to AVFoundation, AudioToolbox or any sound API in either target. |
| Audio assets | None. |
| Music | None. |
| Ambience | None. |
| Haptics | Seven scattered `.sensoryFeedback` call sites. |
| Did the haptics setting work? | **No.** Five of the seven ignored `preferences.haptics` entirely — the map's overlay picker, three sites in new-game, and the network switcher kept buzzing after the player turned haptics off. |
| Audio settings | None. |
| Event stream suitable for audio? | Yes, and better than expected — see §6. |

---

## 2. The design rule

**Silence is a tool.** Most of what the simulation emits maps to no sound at
all, and that is a decision rather than an omission: `dayStarted` fires every
game day, `commandApplied` fires for every command, and `weekStarted`,
`monthStarted`, `seasonChanged` and `wakeFired` all fire on a schedule nobody
asked about. A game that pinged at each would be unplayable inside a minute.
`AudioDirectionTests.routineEventsAreSilent` asserts it, so the silence cannot
be undone by accident.

What remains is a small vocabulary in which every sound means something, and
in which the loudest thing in the game is fifty times rarer than the quietest.

---

## 3. Layers

```
Core                          App
────                          ───
SimEvent  ─┐
GameState ─┼→ AudioDirector ─→ [AudioCue] ─→ Feedback ─┬→ AudioEngine → AVAudioEngine
SimSpeed  ─┘   (pure)                        (facade)  └→ HapticEngine → UIFeedbackGenerator
                                                 ↑
                                            Preferences
```

**`AudioDirection.swift` (Core)** decides *what deserves a sound*. It is pure:
events in, cues out, no clock of its own, no audio API, no UIKit. That is what
makes the interesting half of an audio system testable on a Linux box with no
speaker.

**`Feedback` (App)** is the only thing views talk to, and it is deliberately
dumb. It owns the engines, reads the settings, and plays what Core hands it.

**`AudioEngine` / `HapticEngine` (App)** are the hands.

A view says:

```swift
feedback.play(.routeOpened)
```

It never says `play("whoosh_3.wav")`. No view knows a filename, a volume, a
duration, or whether a cue is also a haptic — which is what makes it possible
to re-voice the entire game by editing two files.

### Why the policy is in Core

Three things it buys that a director inside a SwiftUI view could not have:

1. **Testability.** Priority, aggregation, cooldown, batching and the 16x
   policy are exercised by the same suite as the economy.
2. **Correct first-time moments.** See §6.
3. **It cannot drift from the feed.** Cues derive from the very `SimEvent`s the
   ops feed renders, so the game can never say one thing on screen and another
   in the speakers.

---

## 4. The event taxonomy

`AudioCue` has 54 cases across seven categories. Each carries a category, a
priority, a cooldown and an asset name.

| Category | Cues | Character |
| --- | --- | --- |
| `ui` | select, navigate, confirm, cancel, sheet open/close, toggle, error | The quietest family. Trimmed to 0.55 and mastered at 0.11–0.34. |
| `operations` | ordered, delivered, sold, lease returned, assigned, unassigned, maintenance ×2, departed, arrived, delayed, cancelled, 3 flurries | The busiest family, therefore the most rate-limited. |
| `routes` | opened, closed | The signature sound of the game. |
| `finance` | month profit/loss, loan taken/repaid, solvency warning | Restrained. No coins. |
| `world` | forecast, storm, strike, fuel shock, boom, airport closed, ended | Five distinct identities, by test. |
| `progression` | mission ×3, milestone, achievement, capability, era | The only family allowed to be beautiful. |
| `critical` | solvency danger, administration, collapse, game over | Never rate-limited, never cut. |

Plus four **first-time** cues (`firstRoute`, `firstDeparture`, `firstArrival`,
`firstRevenue`) which are treated specially throughout — see §6.

### Priority

`ambient < subtle < normal < important < critical`

Ordered so `>=` reads as "at least this important" and a batch sorts by simply
sorting the values.

The two rules that matter:

- A **critical** cue has a zero cooldown and is never dropped by the batch cap.
  A cooldown that muted a bankruptcy warning would be a cooldown that cost
  somebody their game.
- An **ambient** bed never interrupts anything and is the first thing silenced.

---

## 5. Simulation speed, and the anti-spam policy

The pump publishes four times a second. At 16x a busy network can depart twenty
aircraft inside one of those quarter-seconds. Twenty sounds is not information.

Two budgets, both on `SimSpeed`:

| Speed | Individual flight cues per batch | Total cues per batch |
| --- | --- | --- |
| paused | 0 | 4 |
| 1x | 3 | 4 |
| 4x | 1 | 3 |
| 16x | **0** | 2 |

Beyond the individual budget, flight cues **collapse into a flurry**:
`departureFlurry`, `arrivalFlurry`, `disruptionFlurry` — one wider, softer
sound that carries the whole minute. At 16x the individuals are suppressed
entirely and the flurry *is* the story.

The pipeline, in order, in `AudioDirector.cues(for:state:speed:now:)`:

1. **Map** events to cues, counting flights as it goes.
2. **Add first-time cues**, read from state rather than from events.
3. **Aggregate** — before the budget, so a flurry is never itself cut.
4. **Deduplicate**, keeping the first occurrence. One event kind, one sound.
5. **Rate-limit** by per-cue cooldown (UI 0.05s, routes/finance/progression
   0.5s, operations 2.5s, world 4s; critical and first-time cues exempt).
6. **Rank and cap** by priority, ties broken on the cue's own name so the same
   batch always sounds the same. Critical and first-time cues bypass the cap.

The cooldown clock is **real time, supplied by the caller**. That keeps the
director pure and lets tests hand it their own clock; the app passes elapsed
`ContinuousClock` seconds. Using simulation time would have been exactly
backwards — at 16x more sim-time passes per second, so a sim-time cooldown
would permit *more* sound the faster you played.

### State-derived cues, and why they are not events

Two cues are raised from *state* rather than from the event stream, because
the thing they describe is a threshold rather than a happening:

- **The four first-time moments** (§6).
- **`solvencyWarning` / `solvencyDanger`**, raised by `GameController` when
  `SolvencyModel.stage` crosses upward. Only a *transition* sounds: the stage
  is recomputed four times a second, and holding at `danger` for a game week
  must not be a week of warnings.

These are deliberately not tied to the auto-pause preference. That setting is
about whether fast-forward stops itself; entangling it with the warning would
have made a preference about time control silently also a preference about
being told the airline is failing.

**A note on revenue magnitude.** The phase brief asked for a distinction
between "small" and "significant" revenue. This implementation makes the
month's sound depend on its *sign* and nothing else, deliberately: the game's
currency is fictional and unpegged, so any absolute threshold for "significant"
would be a number invented to sound like a design decision. The mechanism that
already exists for genuine financial achievement is `milestoneReached`, which
Core emits against thresholds the simulation itself believes in. A magnitude
tier should be added only if it can be grounded in one of those.

### A player's own actions are never rate-limited

`Feedback.play(_:)` bypasses the director completely. The director exists to
thin out what the simulation emits on its own schedule; a sound the player's
finger asked for must always fire, because a swallowed tap reads as a dropped
input.

---

## 6. The continuous layer: ambience and music

`AudioDirection.swift` decides which *discrete* sounds a moment deserves.
`SoundscapeDirection.swift` decides what the game sounds like when nothing in
particular is happening. Both are pure Core policy for the same reason.

### The rule

**The game must not get louder as the airline grows. It must get richer.**

So scale moves *movement* — the density of activity in the bed — and never
*level*. `AmbienceDirector.mix` takes focus, airborne count, speed, selection
and solvency, and returns a `bed`, a `level` and a `movement`. A test asserts
that two aircraft and two hundred produce **the same level** and different
density, because that is the property, not the implementation.

| Input | Effect |
| --- | --- |
| Focus `away` | Silence. Not on the map, no bed. |
| Focus `world` → `regional` → `local` | Presence rises 0.22 → 0.45 → 0.62. The whole range is under 3×: no layer is ever loud. |
| Airborne count | Movement, saturating at 24 aircraft. Two versus twenty must be obvious; two hundred versus four hundred must not. |
| `paused` | Bed stays, movement drops to 15%. A paused world is still a world — and this is what makes unpausing feel like *starting* something. |
| `x4` | Movement ×1.15. |
| `x16` | Movement ×1.05 — deliberately **below** 4×. The discrete cues are already aggregating there; a busier bed on top is how fast-forward becomes exhausting. |
| Selection, at `regional` or closer | ×1.12. The one place the map is allowed to be more present. |
| Solvency `watch` / `danger` | ×0.9 / ×0.75. A failing airline **recedes**. Not a siren — the world going quiet is a more useful feeling. |

Speed never changes pitch. Pitching a loop up with the clock is the single most
arcade thing an audio system can do.

### Music

A five-state machine with written precedence:

```
menu  ←  no game
milestone  ←  something was just achieved   (outranks everything below)
crisis     ←  solvency in danger            (outranks the clock)
planning   ←  paused
operating  ←  running
```

A milestone during a crisis is still a milestone: a player who achieves
something while failing still achieved it. `watch` is deliberately *not* a
crisis — the crisis bed is for the administration countdown.

Transitions always crossfade, 0.6–4 s depending on the pair, and the crossfade
is **equal-power** (`sin`/`cos`) rather than linear: two linear ramps sum to a
dip in the middle, audible as a stumble on every transition.

The engine carries **two decks** because a crossfade needs the outgoing track
still sounding while the incoming one rises. The fade reads its target level
on every step, so a slider moved mid-transition is obeyed rather than ignored
for four seconds.

**The architecture is correct with an empty music library.** A state with no
track is silence, never a substituted track — `MusicState.milestone` ships that
way on purpose. See `docs/AUDIO_ASSET_MANIFEST.md` §5 for what does ship and
why it is four drones rather than a score.

### Where the map comes in

`MapScreen` reports focus and selection to `Feedback` on appear, on zoom-level
change and on selection change — *reported*, not applied, so a pinch does not
touch the audio graph on every gesture frame. The bed is then re-derived on the
next snapshot, from the same instant the discrete cues are drained.

---

## 7. Save, restore, and the first-time moments

This is the part the phase brief flagged as high-risk, and it is where the
design earns its keep.

**The stream is already correct.** `GameSession` seeds `deliveredEventCount`
from `state.eventLog.totalCount` at init, and `events()` yields no backlog. So
a session built over a restored state publishes nothing historical. Asserted
by `loadingPublishesNoBacklog`.

**The first times are the hard part**, because they are not events — they are
facts about the world that become true once. "Your first flight has landed" is
not a sound you can derive from a batch, because the batch that contained the
arrival is long gone by the time somebody reloads.

So they are read from **persisted state**: `RouteStats.flightsCompleted` and
`passengersCarried` are saved with the game. `AudioDirector.Milestones(state:)`
asks the airline's own books, and the director is constructed from the state
at session start. A mature airline therefore begins with all four already
true and can never be told it has just started.

They also **latch forward only**: closing every route does not re-arm "your
first route", which would make the sound a lie the second time anyone heard it.

Both directions are tested, and both tests were verified by sabotage:

- Making `init(state:)` forget the save fires all four first-time sounds at
  someone loading a played game.
- Making `Milestones(state:)` always report false silences them for a new one.

Session lifecycle, for completeness:

| Moment | What happens |
| --- | --- |
| New game / load | `subscribe()` clears the pending batch and calls `feedback.beginSession(state:)`, which stops everything sounding and builds a director seeded from that state. |
| Quit to menu | `feedback.endSession()` — director dropped, everything stopped. |
| Load without quitting | Same as new game: `subscribe()` runs on every session replacement, which is why the reset lives there and not only in `quitToMenu`. |
| Background | `applicationDidEnterBackground()` — ambience stopped, engine paused, session deactivated with `.notifyOthersOnDeactivation`. |

---

## 8. Settings

Persisted in `UserDefaults` through the existing `Preferences` object — not a
second copy, so the settings screen and the engine cannot disagree.

| Setting | Default | Why |
| --- | --- | --- |
| Sound effects | **on** | The game's voice. |
| Effects volume | 0.8 | |
| Ambience | **off** | A bed of air is the setting most likely to be unwanted on a commute and the one nobody thinks to look for. Opt-in; the game is designed to be complete without it. |
| Ambience volume | 0.5 | Further multiplied by 0.35 in code — the bed is meant to be barely there. |
| Haptics | on | |

Turning sound off **stops what is already playing**, rather than only the next
thing. Turning everything off **pauses the engine**, because a running
`AVAudioEngine` holds a render thread and an audio route whether or not it has
anything to play.

Nothing here touches the save file, so none of it can affect Core determinism.

---

## 9. Haptics

Sound says *what* happened. Haptics say *how much it mattered*. They are chosen
per cue rather than paired automatically, because pairing them everywhere is
what makes a phone feel like a toy.

| Weight | Cues |
| --- | --- |
| selection | UI select, navigate, toggle |
| light | UI confirm, sold, lease returned, route closed, unassigned |
| medium | **route opened**, aircraft ordered, assigned, first route, first departure |
| heavy | **aircraft delivered**, era advanced |
| success | first arrival, first revenue, mission/milestone/achievement/capability |
| warning | flight cancelled, disruption flurry, month loss, storm, strike, fuel shock, airport closed |
| error | UI error, administration, collapse, game over |
| **none** | everything else — every routine departure and arrival, every forecast, every month that merely went fine, sheet open and close |

The rule that keeps this honest: **nothing the simulation does on its own
schedule may vibrate the phone.** Flights depart every few game-minutes and
would turn a fast-forward into a massage.

Generators are held and `prepare()`d rather than built per event — a
`UIFeedbackGenerator` created at the moment of use fires late, which feels like
lag rather than feedback.

---

## 10. The engine

One `AVAudioEngine`. Two mixers (effects, ambience) so the two volume settings
are genuinely independent faders. Eight `AVAudioPlayerNode`s in a round robin.
Every buffer decoded once at launch, so **playing a cue after startup allocates
nothing**.

**Category trim is baked into the samples at load, not applied per play.** The
obvious alternative is `node.volume`, and it is wrong in a way worth recording:
a player node's volume applies to whatever it is *currently sounding*, not to
the buffer being scheduled. A UI tap landing on the node still two seconds into
an era swell would duck the swell to the tap's level — and with eight voices
that needs only eight sounds inside one tail, which a 16x flurry reaches
easily. Baking it means node volume is a constant 1, the mixer carries the
player's master setting (uniform across every sound at any instant, so
re-levelling a sounding node is harmless), and a play costs one
`scheduleBuffer`.

**The session category is `.ambient` with `.mixWithOthers`.** A strategy game
is played next to a podcast: the game never interrupts what the player already
has on, and it obeys the ring/silent switch. `.playback` would do the opposite
and is what makes games feel rude.

**Ambience cannot stack.** `startAmbience` is a no-op when the requested bed is
already the one playing, so calling it from `onAppear` — which is where a
stacking-loops bug always comes from — merely re-levels.

**Missing assets are surfaced, not swallowed.** A cue whose file will not load
is recorded in `unavailable` and reported in Settings, because a silent sound
is otherwise indistinguishable from a working one.

---

## 11. Assets

`AirlineEmpireApp/Resources/Audio/*.wav`, 54 files, mono 16-bit 44.1 kHz,
~5 MB. Flat, not in a subdirectory: XcodeGen adds `Resources/Audio` as a group
so the files land in the bundle root, which is what
`Bundle.main.url(forResource:withExtension:)` expects. A folder reference would
put them in a subdirectory and **every lookup would return nil, silently** —
which is why `scripts/audio/check-assets.py` exists and runs in CI.

The name for each cue lives in Core (`AudioCue.assetName`) so that "every cue
can be voiced" is a property a Linux test and a CI script can both check.

Full inventory, provenance and production briefs: `docs/AUDIO_ASSET_MANIFEST.md`.

---

## 12. Performance

Measured by `ae-map-bench` (release, Linux, server CPU) on the same late-game
world the map is benchmarked against — 8 airlines, 200 routes, 200 aircraft,
403 live flights:

| Call | Cost |
| --- | --- |
| `AudioDirector.cues`, first-times outstanding, empty batch | 0.02 ms |
| `AudioDirector.cues`, first-times done, empty batch | below 0.01 ms |
| `AudioDirector.cues`, 24 departures at 16x | below 0.01 ms |
| `AudioDirector.cues`, 24 departures at 1x | below 0.01 ms |
| *(for scale)* `mapModel`, same world | 1.72 ms |

The director runs on the same schedule as the map model — four times a second
— and costs roughly a hundredth of it. The first row is the one that needed
the `allSeen` early-out: without it, every refresh walks every route and every
live flight forever, to answer a question that can only change during the
opening hour.

On the app side, the costs that matter are structural rather than measured
here, because nothing here can run them:

- **Playing a cue allocates nothing.** All 54 buffers are decoded at launch;
  a play is one `scheduleBuffer` on a pre-attached node.
- **No player is ever constructed at runtime.** Eight voices, created once.
- **Category trim is baked at load**, so no per-play gain arithmetic.
- **Muting idles the graph** rather than leaving a render thread running.
- **Backgrounding releases the audio route** and stops ambience.

Bundle cost: 54 files, ~5.1 MB of uncompressed PCM. Deliberately not
compressed — decode cost at launch is the thing being avoided, and 5 MB is
small against an app that ships a world.

---

## 13. What is and is not proven

| Claim | Status |
| --- | --- |
| Cue mapping, priority, dedup, cooldown, aggregation, speed policy | **Tested** — Linux, two verified by sabotage |
| Ambience response to zoom, scale, speed, selection, solvency | **Tested** — including the bounding property: no input combination can push the bed past full |
| Music state machine, precedence, crossfade durations | **Tested** |
| Settings resolution and persistence | **Tested** — including that an empty store yields defaults rather than silence |
| Save/restore baseline and no-backlog behaviour | **Tested** |
| Every cue has an asset, within format and mix ceilings | **Tested** — `scripts/audio/check-assets.py`, in CI |
| App audio and haptic code compiles | **Built** — macOS CI, `xcodebuild`, Xcode 26.6 |
| Assets are valid mono 16-bit 44.1 kHz, non-silent, click-free | **Verified by measurement** |
| The game sounds good | **Not validated.** Nobody has heard any of it. |
| A crossfade sounds like a crossfade | **Not validated.** No music transition has ever been played. |
| The bed reads as "a busy network" rather than as noise | **Not validated**, and the least certain claim here. |
| Latency, mixing, ducking, engine behaviour on device | **Not validated.** |
| Haptics feel right | **Not validated.** |
| Ambience is tolerable for an hour | **Not validated**, and the least likely of these to survive contact with a listener. |

**50 audio tests in total** — 23 for the cue policy, 16 for the soundscape, 11 for settings. `tasks/TODO.md` AE-026 is the listening pass;
AE-027 is the deferred density work from the feel audit. Until somebody does it, no claim
about how this *sounds* is supported by anything.
