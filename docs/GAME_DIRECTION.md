# Airline Empire — Game Direction

> The north star, decided by the project owner on 2026-09-06 and written down
> here so that every later phase can be **judged against it** rather than
> argued from scratch. `MASTER_PLAN.md` says what order things happen in;
> this says what they are for. Where a proposal and this document disagree,
> this document wins or it gets amended — deliberately, in writing.

---

## 1. What this game is

**A cozy builder about growing an airline, with a living world map at its
centre, played in twenty-to-forty-minute sittings.**

Five decisions, in the owner's own words, and what each one commits us to:

| Decision | What it commits us to |
| --- | --- |
| **Cozy builder / idle tycoon** at heart | The pleasure is *growth you can watch*, not optimisation under pressure. Calm surface, real depth underneath, available to those who want it. |
| **20–40 minute sessions** | Long enough to plan and see the plan pay off. Not a five-second check-in; not a two-hour spreadsheet. A session should have a beginning, a middle and a satisfying place to stop. |
| **Guided, with real consequences** | The game always says what is happening and what could be done about it. It never quietly punishes. But it can still be lost. |
| **A living world map** as the atmosphere | The map is not a screen in the app; it is the *place the game happens*. Aircraft to follow, airports that breathe, weather and night sweeping the globe. Worth leaving open. |
| **Build the big version** | No launch clock. Depth, content and polish all get their turn; nothing is rushed to a store deadline. |

## 2. The four pulls

The owner picked all four progression pillars, which is coherent — they are
four *different players' reasons* to open the app, and a cozy builder wants all
of them available at once:

1. **Painting the map.** Coverage is the score. More cities, more lines, a
   network that visibly becomes a shape.
2. **Unlocking aircraft and eras.** The catalogue is the ladder; the first
   widebody is a moment the game should mark.
3. **Net worth and empire.** Numbers going up, and being told where you stand
   — "third largest in Europe".
4. **Goals and contracts.** Era objectives (structural, always visible) and
   contracts you accept (optional, time-limited, with a real penalty).

**Design rule:** every feature should serve at least one of these four and
must not damage another. A feature that serves none is a feature for a
different game.

## 3. Stakes, exactly as decided

> "An option should exist that an investor can rescue you with strings before
> bankruptcy — but if you go bankrupt it's game over."

So the ladder is:

```
healthy → watch → danger (countdown running)
                     ↓
              INVESTOR OFFER  ── accept ──→ cash now, strings for a year
                     │                       (equity, forced route sales,
                     │                        a spending cap, a reputation hit)
                     └── decline / ignore ──→ administration (the existing
                                              fire sale, once) ─→ collapse
```

Bankruptcy stays terminal. The rescue is the *guided* half of "guided with
real consequences": nobody should lose an airline without having been offered
a way out and understanding what refusing it meant. What the game must never
do is take the airline away without warning — and it already does not
(`SolvencySystem`, `docs/GAME_DESIGN.md` §5).

## 4. Time

**Capped offline catch-up.** The world advances while the app is closed, up to
a cap, and the player is met with a report of what happened. This is what
makes a cozy builder rewarding to return to without making absence punishing
or making a week away into an empire.

The cap is a design number, not an implementation detail: it decides whether
leaving the game is a strategy. It is specified in `ROADMAP_DIRECTION_II.md`
Phase 29 and must be tuned against the balance battery, not guessed once.

## 5. What "cozy" means here, concretely

Cozy is not a colour palette. It is a set of promises the game keeps:

- **There is always a next step, and it is always pressable.** Naming a
  problem without offering the action is the one habit this project has
  already had to fix once (BUG-059). No screen states a problem and stops.
- **Nothing punishes absence.** No timers that expire against you, no daily
  streaks, no losing what you built because you did not open the app.
- **The calm surface is real, and so is the depth.** The simulation underneath
  is honest and detailed (AE-040…AE-044 exist because of that). Cozy governs
  *what the game asks of you*, never *what the game models*.
- **Failure is legible long before it is fatal.** Warnings escalate; the
  rescue exists; the countdown is visible.
- **The map rewards watching.** If a player leaves the app open on the map and
  simply looks at it for a minute, that minute should be pleasant.

## 6. What this rules out

Written down because a direction that forbids nothing decides nothing:

- **No hard real-time pressure.** No live events you must attend, no "log in
  within 4 hours or lose the contract".
- **No dark patterns.** No energy, no ads, no fear-of-missing-out mechanics.
- **No dumbing down of the simulation to look calm.** The answer to "this is
  complicated" is better presentation, never a worse model.
- **No permanent loss the player was not warned about**, and no loss at all
  before the rescue has been offered and refused.
- **No feature that only serves a hypothetical audience.** Four pulls, above.
  If it serves none of them, it waits.

## 7. Open, and blocking real work

These were asked and are not yet answered. Each one blocks or reshapes a phase,
and each is named where it bites in `ROADMAP_DIRECTION_II.md`:

1. **Aircraft naming — real or fictional?** Fictional today (`Pacifica
   PA-184`). Real names are far more evocative and carry trademark questions.
   Blocks the fleet-content phase.
2. **Art pipeline.** A living map and aircraft the player wants to look at need
   assets that cannot be produced in this environment. Commissioned, generated,
   or drawn in code? Decides how far Phase 26–27 can go.
3. **Music and ambience.** Audio exists (~58 cues); music does not.
4. **iPad.** A sidebar shell exists; iPad-native layouts do not.
5. **Notifications.** Compatible with cozy only if they are opt-in and never
   urgent.
6. **How long a full campaign should be.** Decides era pacing and the offline
   cap together.

## 8. Amending this document

It is a design document, not a contract. When the owner changes their mind, it
changes here first, in the same sitting, with the reason — so that a later
phase reading this never has to guess which of two contradictory instructions
was the recent one.
