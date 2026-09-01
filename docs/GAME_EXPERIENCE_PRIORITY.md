# Game experience priority list — AE-033 audit

> The ranked output of the full runtime audit (map harvest + player
> journey + screen-by-screen). Every item carries how it was found.
> Evidence labels: **MEASURED** (numbers from instrumentation),
> **OBSERVED** (seen in decoded CI frames), **READ** (from code, not yet
> seen at runtime). Companions: `PLAYER_JOURNEY_RUNTIME_AUDIT.md` (the
> journey evidence), `MAP_P0_PERFORMANCE_REPORT.md` (the perf evidence).

## How to read the ranking

P0 = breaks the core experience. P1 = a player would complain. P2 = a
reviewer would notice. P3 = polish. The two AE-034 P0s (drag rebuild
cost, label churn) were fixed this phase and live in the perf report,
not here.

## P1

*(none open — the P0/P1 class found by the baseline was the map
interaction cost, fixed and verified this phase; the journey audit found
no other P0/P1.)*

## P2

- **EXP-01 · HOME · Post-checklist direction.** REPRO: finish the 5-step
  checklist. ROOT CAUSE: DashboardView swaps the checklist out and
  nothing answers "what should I do next"; stat tiles answer "how big am
  I". IMPACT: the game's strongest guidance surface goes silent exactly
  when the player first has freedom. FIX: a single "next best move" card
  fed by the existing opportunity model (the map coach already ranks
  markets). VALIDATION: journey test extended past first revenue,
  screenshot of Home after checklist completion. (READ; the scripted
  journey ends before this state, so no frame exists.)
  **IMPLEMENTED (first-session phase)**: `NextMovesCard` — the
  idle-aircraft warning plus the top two `marketOpportunities`, opening
  the same guided route sheet the checklist used; the flight journey
  test now drives to first landing and asserts the checklist→card
  handover. **OBSERVED (run 93, KEY-09)**: checklist retired, Next Moves
  card with two ranked markets on screen, $66k month-to-date beside it —
  the state exists and reads as designed.
- **EXP-02 · ROUTES/FLEET · Summary strip outweighs a 1-row list.**
  REPRO: KEY-04/KEY-07. ROOT CAUSE: the 7-metric strip renders at full
  weight regardless of fleet size. IMPACT: early-game screens read as
  chrome over emptiness (~60 % dead space). FIX: collapse the strip to
  its 2–3 non-degenerate metrics until the list exceeds ~3 rows.
  VALIDATION: re-screenshot KEY-04/07. (OBSERVED)
  **IMPLEMENTED (first-session phase)**: both strips gate their
  aggregate columns behind `count > 3`. **OBSERVED (run 93, KEY-04/07)**:
  both strips now four metrics, the dead-space chrome gone.

## P3

- **EXP-03 · MAP · Edge-clipped labels.** "Langnes (Tro…" (KEY-82),
  "BELA…" country label (KEY-51), bottom label under the tab bar.
  ROOT CAUSE: airport labels clamp to the viewport only when their
  marker is on-screen; country labels never clamp. FIX: clamp or cull
  labels whose text rect crosses the safe-area edge. (OBSERVED)
- **EXP-04 · MAP · World-zoom letterbox.** At 1× with the coach card up,
  a large empty field sits above the world band (KEY-71). FIX: bias
  vertical centering by the coach card's height. (OBSERVED)
- **EXP-05 · WORLD · Bottom half empty** (KEY-24). FIX: surface one live
  fact per card (next storm, closest rival move) instead of static
  descriptions. (OBSERVED)
- **EXP-06 · SHEETS · No header fade at XXL type** (KEY-97). (OBSERVED)
- **EXP-07 · MAP · y-clamp pan absorbs the finger silently** — the zoom
  limits have resistance+spring, vertical pan does not
  (`MAP_RUNTIME_BASELINE.md` §4, TECH_DEBT TD-023). (READ)

## Game feel: what exists vs. what is missing

What already exists (READ from `Feedback.swift`, `GameController.swift`,
`RootView.swift` — architecture is real; runtime firing not screenshot-
provable):

- Semantic audio cues with per-cue haptics, player-caused cues never
  rate-limited; ambience bed driven by focus/airborne/speed/solvency;
  music director with milestone ducking.
- A celebration overlay for era changes, milestones, achievements,
  capabilities, missions — deliberately narrow ("celebrating everything
  celebrates nothing").

What is missing, in priority order (each is a *reaction to a player
decision*, per the design rule — no ambient random effects):

1. **First-revenue moment.** The first ticket money is the loop's proof
   and today it is a number changing on Home. The celebration overlay
   already exists; `firstTicketRevenue` is an audio first-time moment but
   not a visual one.
2. **Route opening reacts on the map.** The route line simply exists on
   the next frame. A one-time draw-in of the new arc (a settle-triggered
   animation, not a per-frame cost) would make the decision visible.
3. **Assignment closes the loop.** Assigning an aircraft flips a chip in
   Routes; the map shows nothing until un-pause. The aircraft appearing
   at its gate on assignment would connect the two screens.

These are AUTHORED as designs only — nothing here is implemented, and
each must ride the existing settle/celebration machinery rather than add
per-frame work (see `MAP_PERFORMANCE_TARGETS.md` invariants).
