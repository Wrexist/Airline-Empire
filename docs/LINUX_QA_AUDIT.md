# Linux QA Audit — what is proven, and what is still unknown

Written 2026-08-26 at the close of the Linux-first phase (V3 prompt §37).
Its purpose is to be honest about the boundary between *verified* and
*plausible*, so the first Mac session knows where to look.

---

## 1. Player-journey gap hunting

Static review is not enough. Every command in the game had unit tests and a
correct implementation, and the game was still **unplayable** — the player
could buy an aircraft and open a route but had no way to connect them
(BUG-002). Gaps of that shape live between correct parts, so they are found
by walking sequences, not by testing units.

Method: enumerate every player capability, then for each ask the five
questions — can Core do it, is there a command, does the command validate,
does state update, does a read model expose the result, and **can the player
actually reach it and understand the outcome?**

### Gaps found and fixed

| ID | Gap | Where it hid |
|---|---|---|
| BUG-002 | No UI path to assign an aircraft to a route — the core loop could not be closed | Between two screens; both were individually complete |
| BUG-003 | Game over was a dead end: no new game, no other save, no menu | A state machine that only moved one way |
| BUG-004 | The feed showed rivals' statements and loans as the player's own money, and never rendered the administration warning at all | Events are emitted for every airline; the view rendered the raw stream |
| BUG-005 | Commands queued while unpaused were rejected silently — no alert, no event, nothing | The rejection existed in Core but had no delivery path out of the actor |

Three of the four are *information* failures rather than logic failures: the
simulation was right and the player could not see it. That is the
characteristic failure mode of a well-tested core behind an unvalidated
client, and it is worth expecting more of the same during runtime QA.

### Capability coverage (audited by enumeration)

All 15 player-facing commands are reachable from a screen. `FoundAirline` is
issued by the new-game flow via `beginScenario`; `ScheduleWake` is a kernel
command with no player surface, correctly.

Buy new · buy used · lease · sell · return lease · open route · close route ·
assign · unassign · set price · set frequency · set service tier · take loan ·
repay loan · start capability program — each has a UI entry point and a read
model that shows the result.

## 2. What is proven on Linux

- **Simulation correctness.** Full suite green; determinism verified by
  dual-run hashes, chunk invariance, and save/continue equality.
- **Long horizons.** A decade of continuous play keeps every bounded
  collection bounded, keeps the save within a small multiple of its
  first-year size, keeps the world alive without runaway wealth, ages fleets
  inside their domains, and stays **bit-identical across a decade** for a
  given seed. Five save/reload cycles over five years equal one unbroken run.
- **Player journeys.** New game → aircraft → route → assign → fly → revenue,
  verified through the real command surface and the read models the screens
  consume; plus unwinding every commitment, surviving save/reload mid-journey,
  and recovering from losses.
- **Screen data contracts.** Dashboard, Route detail, Fleet, Finance, Map and
  World screens can each be drawn from Core alone on a real mid-game world.
- **Content quality.** No strictly-dominated aircraft, no orphaned or
  unreachable content, unique identity, sane economics, ordered difficulty.
- **Offline-first.** Zero network references in Core or App.
- **Performance.** 3.02 s per game-year at 200 routes / 200 aircraft against
  a 10 s budget; linear scaling; 607 KiB saves.
- **Concurrency hygiene (static).** No `DispatchQueue`, `@unchecked`,
  detached tasks, timers, or mutable global state anywhere in the App; all
  nine `Task` sites are in the `@MainActor` composition root.

## 3. What remains unknown

Answering §37's questions without flattering the project:

**What can still break?** SwiftUI itself — none of it has ever compiled.
Layout, rendering, gesture handling, `@Observable` update propagation, scene
phase transitions, and actor hops under a real scheduler are all unverified.

**What player journey is untested?** Every journey is tested at the Core
level and none at the UI level. Specifically unexercised: navigation between
tabs, sheet presentation and dismissal, the map's drag/magnify/tap gestures,
and the alert path now used by BUG-005's rejections.

**What Core capability has no UI path?** None found by enumeration. But
enumeration proves a command is *referenced*, not that a player can find it —
discoverability is a runtime and playtest question.

**What UI screen has no stable data contract?** None; all six are covered.
The contracts assert presence and sanity, not that the numbers are the ones a
player would *want* — that is a design judgement.

**What save scenario is untested?** Save format migration from a *shipped*
build, since nothing has shipped. The v9→v10 migration is tested
synthetically. Also untested: interrupted writes on a real device filesystem
(fuzzed here, but not against iOS storage).

**What late-game scenario is untested?** Beyond ten years. Also: a player who
reaches the `empire` era with a very large fleet — the balance battery reaches
four years, the late-game suite ten, and neither drives a maximal network for
that long.

**What economic strategy is broken?** None found. F-001 (uncontested
scarcity rents) remains a documented watch item awaiting playtest evidence
rather than a tuning change.

**What AI behaviour is pathological?** None observed. Known thinness: AI
carriers never order new aircraft or retire old ones, so over very long runs
their fleets age without renewal (PRODUCT_REVIEW #5).

**What performance problem remains?** None measured on Linux. Unmeasured:
`Canvas` map drawing cost, SwiftUI view update cost with a large network, and
memory on a real device. Note that the *test suite* is slow (~4 min) because
of the per-tick integrity assert, which is compiled out in release — that is
intentional, not a performance defect.

**What Apple-specific issue is still unknown?** All of them. See
`docs/APPLE_VALIDATION.md` §5.

## 4. Standing recommendation

When the Mac arrives, do not start with polish. Run the walkthrough in
`APPLE_VALIDATION.md` §4 first and expect to find more BUG-004-shaped
problems — places where the simulation is right and the presentation is
wrong. Those are cheap to fix and expensive to ship.
