# Direction II — the cozy living world (phases 25–33)

> The detailed plan for the direction set in `GAME_DIRECTION.md`, written
> before any of it is built. Companions: `MASTER_PLAN.md` (the authoritative
> phase table and the rules every phase obeys), `EXPANSION_ROADMAP.md` (the
> Phase-24 architecture study this reuses), `ARCHITECTURE.md` §12 (what a new
> gameplay system consists of).
>
> Every phase below names the **seam it lands on in the shipped code**, not a
> hoped-for one. Where a phase depends on an unanswered question, that is
> stated in the phase rather than assumed away.

---

## 0. How this plan is ordered, and why

The owner asked for all four work areas — feel and polish, simulation depth,
content and variety, first-hour clarity — and for the big version. So the
question is not *what*, it is *what first*. Three rules decided the order:

1. **The centrepiece comes first.** The map was chosen as the game's
   atmosphere and is the furthest from being one. Everything else — where the
   first hour happens, where prompts live, what a session feels like — reads
   differently once the map is alive, so doing it first stops the other work
   being done twice.
2. **Core work interleaves with app work.** Phases 28–30 are simulation
   phases and can proceed while an app phase is blocked on an art or naming
   answer. This is deliberate scheduling slack, not padding.
3. **The largest depth item goes last of the near set.** Hub connections
   (Phase 33) is the roadmap's headline and is *also* a map feature — banks of
   flights converging on a hub is a thing you watch. Building it before the
   map can show it would waste half of it.

| Phase | Title | Layer | Depends on | Blocked by |
| --- | --- | --- | --- | --- |
| 25 | Follow a flight | App | AE-045 camera | — |
| 26 | Airports that breathe, weather you can see | App + small Core read model | 25 | Art answer (partially) |
| 27 | The map is the home screen | App | 25, 26 | — |
| 28 | The investor rescue | Core + App | — | — |
| 29 | Capped offline catch-up | Core + App | — | Cap value (design) |
| 30 | Goals that pull: era objectives and contracts | Core + App | — | Campaign length (design) |
| 31 | The first hour, on the new home | App | 27 | — |
| 32 | The fleet you want | Content + App | — | Naming + art answers |
| 33 | Hub connections | Core + App | 26, 27 | — |

Phases 25–27 are one continuous piece of work and could be read as one phase
in three shippable parts; they are separated because each has its own
definition of done and each is independently valuable if the next is delayed.

---

## Phase 25 — AE-046: Follow a flight

**The player-visible thing.** Tap an aircraft on the map and ride with it: the
camera locks on, the card becomes a live flight tracker — where it is, who is
aboard, when it lands, whether it is late and why — and the world moves under
it. Touch the map and you take the camera back.

**Why first.** It is the single cheapest delight in the whole plan. AE-045
rebuilt the camera as a *pure function of the frame's date* and rebuilt flight
interpolation on a continuous game clock; a follow camera is one more term in
a function that already exists, and the smooth motion it needs was the bug
that was just fixed. The seam is warm.

### Design rules

- **Following is a mode, not a modal.** Everything else on the map keeps
  working; the chrome does not take over the screen.
- **The finger always wins.** Any pan or pinch releases the lock, using the
  same `interruptMove()` rule a camera move already obeys.
- **It must survive the flight ending.** A followed flight lands, and the
  camera has to do something honest — hold at the destination airport and say
  the flight arrived, not snap to the world or follow a ghost.
- **Reduce Motion:** following still works; the camera stops easing and simply
  tracks.

### Implementation

| Piece | Where | Note |
| --- | --- | --- |
| Follow target | `MapCamera` | `followed: FlightID?` + a per-frame centre override that resolves the flight's interpolated position at the frame's date. Same evaluated-never-stepped rule the move obeys. |
| Release on touch | `MapView.dragGesture` / `zoomGesture` | Already call `interruptMove()`; clear the follow target there. |
| Live flight facts | `MapModel.MapFlight` (Core) | Add `passengers`, `scheduledArrival: SimTime`, `distanceKm`, and `delayCause` (derived, see below). ~15 lines + read-model tests. |
| Delay cause | `MapModel` build (Core) | `FlightOpsSystem` already boosts disruption from `state.world.activeStorm(in:at:)` over either endpoint. The cause is *derivable at read-model time* from the same call — no new state, no save migration. |
| The card | `MapSelectionCards.MapFlightCard` | Becomes the tracker: progress, ETA on the game clock, passengers aboard, delay and its cause, a Follow toggle, and the existing link into the aircraft. |
| Zoom behaviour | `MapCamera` | Following at world zoom is pointless; entering follow eases to a regional zoom unless the player is already closer in. |

### Data and save impact

None. Every new field is read-model, derived per tick from state that already
exists. No migration.

### Tests

- Core: `MapPresentationTests` — a flight en route through a storm reports the
  cause; passengers and scheduled arrival match the `Flight` they came from;
  a ferry reports zero passengers.
- App: the camera cannot be unit-tested here (no simulator). The UI-test
  journey gains a follow step that asserts the map's accessibility value
  reports a followed flight — the same probe pattern `zoom %.1fx` already uses.

### Risks

- **Following at 16× is a blur.** Mitigation: entering follow at 16× is
  allowed but the card says the speed; consider easing the camera rather than
  the world. To be judged on a device.
- **A followed flight disappearing mid-frame** (arrival, cancellation) —
  handled explicitly above; it is the one real correctness case here.

### Done when

You can tap an aircraft over the Atlantic, watch it cross, see the ETA count
down against the game clock, be told it is forty minutes late because of a
storm over Istanbul, and take the camera back by touching the map. Confirmed
on a device, because none of that sentence can be verified in this
environment.

---

## Phase 26 — AE-047: Airports that breathe, weather you can see

**The player-visible thing.** The map stops being a diagram. Airports glow
with the traffic they are actually handling and pulse when a flight leaves or
lands. Storms are visible fields that drift, and the airports under them show
it. The night side of the world carries city lights.

### Design rules

- **Every visual signal is driven by a real number.** No decorative animation
  that means nothing — a pulse is a departure, a glow is traffic, a shadow is
  night. This is the map's existing rule (`MAP_ARCHITECTURE.md` §2) and the
  reason the map is trustworthy.
- **Your airline reads differently from everyone else's.** Player activity in
  the livery colour, rivals quieter — as routes already are.
- **It must cost nothing when nothing is happening.** The map's per-frame
  budget is measured and defended (`MAP_PERFORMANCE_TARGETS.md`); these
  effects are O(visible airports), never O(world).

### Implementation

| Piece | Where | Note |
| --- | --- | --- |
| Activity glow | `MapFrame.drawAirports` | Steady component from `MapAirport.slotPressure` (already in the read model: the fraction of daily movements claimed) and `playerRouteCount`. |
| Departure / arrival pulse | `MapFrame` | Derived **app-side, per frame** from flights already interpolated: progress under ~0.03 is a departure at `origin`, over ~0.97 an arrival at `destination`. An expanding ring with a short life. No Core change. |
| Hub weight | `MapFrame` | `isPlayerHub` and `competitorHubCount` exist and are unused visually. |
| Storm fields | `MapFrame.drawEventRegions` | Exists but is faint and static: give storms a soft moving field, mark affected airports, and use the same `delayCause` Phase 25 adds so the map and the card agree. |
| City lights | `MapRenderCache` (night layer) | Airport positions weighted by `prominence`, drawn only on the night side of the existing terminator. Content already carries every position — **no new art assets**. |
| Motion budget | `MapDrawStats` | The probe already measures draw cost and label churn; these effects must be measured under it before and after, on the CI runner. |

### Data and save impact

None.

### Tests

Core: none needed (no model change beyond Phase 25's). App: the draw-cost
probe must show the pulse layer within budget on the CI simulator run —
`PerformanceBaselineUITests` already drives and reads exactly this.

### Risks

- **Prettiness that costs frames.** The mitigation is the existing probe: this
  phase does not ship without a before/after number.
- **The line between alive and busy.** A map that pulses constantly is noise.
  Pulses are short, subtle, and only for the player's own flights at world
  zoom; rivals' appear closer in.

### Partially blocked

City lights, storm fields and glow are all code-drawn and need no assets. Any
*illustrated* treatment (painted terrain, aircraft art) waits on the art
answer in `GAME_DIRECTION.md` §7.

### Done when

Leaving the app open on the map for a minute is pleasant, and everything that
moves means something. Judged by eye, on a device, against the screenshots
that started this direction.

---

## Phase 27 — AE-048: The map is the home screen

**The player-visible thing.** The game opens on the world. The dashboard
becomes a briefing that lives *over* the map — the day, the money, the one
thing worth doing next — and the map is what you return to between decisions.

### Why it is a phase and not a tweak

Today Home is a dashboard and the map is tab two; the map is where the game's
atmosphere is and the dashboard is where its prompts are, which is exactly
backwards for the direction chosen. But it can only happen after 25–26,
because promoting a map nobody wants to watch is a downgrade.

### Design rules

- **Nothing on the dashboard is lost, only moved.** Next moves, the money, the
  events feed, rival pressure — all of it still reachable in one gesture.
- **The map keeps its whole surface.** The briefing is a pull-up, not a
  permanent panel over the Atlantic.
- **The tab bar keeps five tabs** or drops to four, but Home and Map do not
  both survive as separate world views.

### Implementation

`GameShell` tab set and default selection; `DashboardView` decomposed so its
cards can be presented over `MapScreen`; the map's existing selection panel
and the briefing must share one bottom region without fighting each other
(`MapSelectionPanel` already occupies it). `MapChrome` gains the briefing
handle. No Core change.

### Risks

**This is the phase most likely to make the game worse.** A beautiful map with
the game's controls buried is a worse game than an ugly map with them to hand.
Mitigation: it ships behind a settings toggle for one build (`Open on: Map /
Home`), and the decision is made on a device with both available — not
argued from a diagram.

---

## Phase 28 — AE-049: The investor rescue

**The player-visible thing.** Before the airline dies, somebody offers to save
it, and the offer has terms you can read. Take it and live with them; refuse
it and take the consequences the game already models.

### Design

The mechanism largely **exists** (`SolvencySystem`): sustained deep overdraft
triggers administration once — a fire sale of unassigned owned aircraft, a
reputation scar, a creditor haircut — and a second failure collapses the
airline. What is missing is the *choice*, which is the whole of what the owner
asked for.

```
danger stage reached (countdown running, `daysUntilAdministration`)
   → investor offer generated, once per airline per administration count
   → player accepts:  cash injection now
                      strings: an equity share of future profit for N months,
                               a forced sale of the K most valuable routes,
                               a spending cap (no purchases above X),
                               a reputation hit smaller than administration's
   → player declines: nothing changes; the countdown runs; administration
                      lands exactly as it does today
   → bankruptcy after administration: terminal, unchanged
```

### Implementation

New state on `Airline` (`rescue: RescueTerms?` — active strings and their
expiry) with a **save migration**; two commands (`AcceptInvestorRescue`,
`DeclineInvestorRescue`) with validators; a `SimEvent` for the offer and for
each string expiring; enforcement in the existing systems that already gate
spending (`FleetSystem`, `EconomySystem`) rather than a new gate; a read model
so the UI can state every term in words before the player commits; and the
advisory surface (`Advisories.swift`) to raise it where the solvency warnings
already appear.

### Tests

Core, and this phase is mostly Core: the offer appears exactly once per
descent into danger; declining reproduces today's administration behaviour
byte for byte (a determinism assertion against the existing tests); accepting
restores solvency and applies every string; strings expire on time; a rescued
airline that fails again still collapses. Plus a balance-battery re-run: the
rescue must not turn the 50-campaign survival rate into a formality — if
nobody can lose, the stakes the owner asked for are gone.

### Risks

**Balance.** A rescue that is strictly good makes danger meaningless. The
strings have to hurt enough that a competent player would rather not need one.
That is a tuning question with a measurement (`ae-bench`, the battery), not a
judgement call.

---

## Phase 29 — AE-050: Capped offline catch-up

**The player-visible thing.** Come back after a few hours and the world has
moved: "While you were away — 47 flights, $312k, a rival opened Stockholm–
Oslo, one aircraft went into maintenance."

### Design

The simulation is deterministic and tick-driven, and `GameSession.advance(ticks:)`
already chunks long fast-forwards so commands and autosaves land at boundaries.
Offline catch-up is therefore not a new simulation mode — it is *the existing
one, run once on return*, which is the reason this is affordable at all.

Three numbers are the whole design, and all three are decisions, not defaults:

1. **The cap** — how much game time a return may advance. Proposal: **one game
   week**, whatever the real absence was.
2. **The rate** — game minutes per real second while away. Proposal: **1×**, so
   a night away is a game day, not a season.
3. **What can happen** — the owner has not yet answered whether bad things may
   happen while away. Proposal: **yes, but nothing terminal** — the solvency
   countdown does not advance to administration offline, because losing an
   airline while not playing it is the one thing "cozy" certainly forbids.

### Implementation

Elapsed wall-clock is recorded at background (`saveOnBackground` already
fires) and read at foreground (`scenePhase` handling exists in
`AirlineEmpireApp`); the delta becomes ticks, clamped by the cap; the events
the catch-up produces are collected into a report model and presented once.
`GameController` owns the report; `EventFeed` already carries the events.

### Risks

- **Trust.** A player must be able to see *why* their cash changed. The report
  is not a summary, it is an account.
- **Save-clock abuse.** Device clock changes are the standard exploit; the fix
  is to clamp to the cap and never to trust a negative delta.

---

## Phase 30 — AE-051: Goals that pull

**The player-visible thing.** Two kinds of goal, always visible: the era
objectives that gate what comes next, and contracts that arrive, can be taken
or left, pay when finished and cost when failed.

### Design

Both halves have seams in the shipped code. `EraGate` already decides era
advancement from real thresholds (profitable routes, destinations, reputation,
fleet size); `MissionKind` is a closed enum with one case (`boomRush`) built to
grow, with `MissionMath`, deadlines, rewards and a baseline already modelled.
So this phase is mostly **surfacing what exists** and **adding cases to an enum
that was designed for it**.

- **Era objectives:** a permanent, readable list of what the next era needs and
  how far along you are. The numbers exist; the screen does not.
- **Contracts:** new `MissionKind` cases — a daily-service commitment on a
  named pair for N months, a regional passenger target, a completion-rate
  challenge during storm season, a land-grab when a rival retreats — each
  offered by an event, each with a penalty for failure.
- An offers inbox where offers arrive, expire, and can be declined without
  guilt.

### Blocked on

**How long a full campaign should be.** Era pacing and contract length are the
same tuning question, and answering it after building the contracts means
re-tuning them.

---

## Phase 31 — AE-052: The first hour, on the new home

Deliberately after Phase 27: the first hour happens on whatever the home
screen is, and rewriting it before the home screen changes is doing it twice.

Scope: the founding flow, the guided first route, the first aircraft, and the
first time the player is left alone. Every step is measured against one
question — *at ninety seconds, does the player know what they are doing and
why?* The pieces (onboarding model, first-route suggestion, next moves) all
exist and are individually good; what is missing is the whole read as one
sequence, on a device, by someone who has not seen it before.

---

## Phase 32 — AE-053: The fleet you want

Blocked on two answers (`GAME_DIRECTION.md` §7): **real or fictional aircraft
names**, and **the art pipeline**. Content expansion — more airframes per era,
better silhouettes, liveries the player shapes, a hangar view worth looking at
— is straightforward work that will be done badly if those two are guessed.

---

## Phase 33 — AE-054: Hub connections

The `EXPANSION_ROADMAP.md` headline: unserved A→C demand spilling through the
player's hub when schedules are banked. It is the deepest change here — a new
term in the demand pool's split, a hub designation on `Airline`, one save
migration — and it lands last of this set because it is also the most *visual*
depth feature the game can have: banks of flights converging and departing
together is exactly what a living map is for. Built before Phase 26, half its
value would be invisible.

---

## What this plan deliberately does not include

- **Cargo, alliances, deeper airports, subsidiaries, scenario worlds, iCloud
  sync.** All in `EXPANSION_ROADMAP.md` years 2–3, all still right, all after
  this set.
- **A store launch.** The owner chose the big version; release phases (23) stay
  where they are.
- **Real-money anything.** No decision has been made, and nothing here assumes
  one.

## How each phase finishes

Unchanged from `MASTER_PLAN.md`: Implement → Test → Build → Review → Fix →
Document → Update tasks. With one addition this direction makes necessary:

**Every app-layer phase states, in its final report, what was verified and
what was only authored.** This environment has no simulator and no device. A
phase whose whole point is how something *feels* cannot be signed off from
Linux, and the project's own history — four phases reported as "authored, not
observed", three controls that compiled and did nothing — is why that sentence
is in this plan rather than assumed.
