# Game experience priority list — AE-033 audit, AE-037 and AE-038 updates

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

## P0

- **RIV-01 · WORLD · No rival ever met the player.** MEASURED (AE-037,
  `ae-rival-probe`): five years from three curated starts, zero contested
  player markets, zero rivals with a second route, three of five rivals
  collapsed. ROOT CAUSE: BUG-042 (an idle aircraft always joined the one
  full route) and BUG-043 (the cast founded at the five most populous
  airports, all in Asia). **FIXED** at the source; rivals now build hub
  networks in the player's region and fight each other. Rival-initiated
  entry into a pair the player already flies remains unreached (TD-026).
- **RIV-02 · ROUTES/HOME · A contested market's consequences had no
  cause on screen.** MEASURED: entering London–Paris under two incumbents
  drew a fare cut and an extra rotation the next morning, thirty-two
  frequency increases, a settled third of the market and a monthly loss —
  and not one event. **FIXED** (BUG-044): `MarketCompetition` standing /
  share / edge on the route, `CompetitionSummary` headline on Home and the
  World hub, `marketEntered` / `marketLeft` in the feed, the market-move
  record (save v12). **OBSERVED** (runs 112–116: KEY-40, 42–48,
  50–53 — `docs/RIVAL_PRESSURE_AUDIT.md` §8).
- **RIV-03 · HOME · The guided route sheet could open empty.** OBSERVED
  (run 116, `FEB-ROUTE-SHEET-STUCK-1` against `KEY-32`): a suggestion tap
  produced a sheet with nothing picked, and the campaign opened an
  unflyable route from it. **FIXED** (BUG-045): item-driven presentation.
  **OBSERVED** (run 117, `KEY-32b`: the suggested Paris and Istanbul routes
  on the board, nothing else).

- **RIV-04 · WORLD · The world never moved first.** MEASURED (AE-038,
  `ae-rival-scan`, 240 campaigns): rivals entered a pair the player flew
  at one of eight homes, because a contested pair scored half per
  incumbent. **FIXED**: `DemandSystem.poolAvailableToEntrant` — the
  engine's own split — in the AI's market scoring; 30 → 95 world-initiated
  entries across the same campaigns. **OBSERVED** (run 119, KEY-R2:
  "SwiftJet entered your … market yesterday" on Home two days after
  founding in New York; KEY-R3/R4/R7 the split, the why, the response).
  AE-039 found that entry to be an artefact of the passenger ranking —
  see RIV-07.
- **RIV-05 · ROUTES · The frequency advice named the wrong cost.**
  MEASURED (AE-038): "another rotation needs another aircraft" on a pair
  where the one aircraft had a rotation to spare. **FIXED** (BUG-046);
  **OBSERVED** (run 119, KEY-R4 and R7).
- **RIV-06 · HOME · Two wordings the New York frames found.** The pair in
  the rival's orientation (BUG-047) and a month-old entry outranking the
  live fight (BUG-048). **FIXED**, **OBSERVED** (run 120, KEY-R2, KEY-R4).
- **RIV-07 · WORLD · The world could not reach the curated European
  starts.** MEASURED (AE-039): the horizon was not the cause — at 24, 48
  and 93 airports the rivals reached the same pairs as at 16 — the
  passenger ranking was. **FIXED** in the ranking (airframe-day revenue):
  Munich reached on day 61 in every seed, Singapore in year two.
  Stockholm and Barcelona still not within two years (TD-026's residual
  is now an economy question: TD-029, TD-030). **OBSERVED** (run 121,
  KEY-HZ2 … HZ6: PacificBlue arrives on Munich–Istanbul on 3 March).
- **RIV-08 · ROUTES · Fare advice named the costly answer.** MEASURED
  (AE-039): matching a cheaper rival bought share and cost money; another
  rotation earned more. **FIXED** (BUG-049), **OBSERVED** (run 121,
  KEY-HZ5-response-line).

- **ECON-01 · WORLD/ROUTES · A movement cost the same whatever landed.**
  MEASURED (AE-040, `ae-fee-baseline`): the 68-seat turboprop's airport
  fees were 1.7–1.9× the narrowbody's as a share of revenue on the same
  pair; no turboprop route in the world paid for its lease; the regional
  archetype had no market from its European home; the player paid the
  same (parity to the cent). **FIXED** (BUG-051: the movement fee scales
  with seats, anchored at 180) and the AI's estimator brought to the
  ledger's maintenance rule (BUG-052). Before/after:
  docs/BALANCING.md F-007. **OBSERVED** (run 123, KEY-HZ5: the fee
  row's new caption "Each flight pays $2,249 at Munich and $1,738 at
  Istanbul for a 184-seat aircraft, plus $15–$23 per passenger landed.");
  KEY-48's narrowbody fee line unchanged as designed. A turboprop route's
  fee line is NOT VALIDATED on screen (no journey flies one).

- **ADV-01 · HOME · The game's own advice could bankrupt the player.**
  MEASURED (AE-042, `ae-advice`): `marketOpportunities` ranked markets by
  the passengers a starter service would capture and by nothing else, so at
  **21 of the 93 homes a player can pick** the first suggestion lost money
  after the airframe it needed or could not be flown. Manchester was told to
  fly London — 243 km, 96% of revenue in airport fees, −$1.18M a month in six
  months of real ledger, ranked #42 of 45 from that home; London was told to
  fly Paris, ranked #44 of 44. AE-041's scripted New York campaign following
  that advice collapsed in 28 of 30 seeds. ROOT CAUSE (BUG-055): the
  eligibility filter asked whether an aircraft could fly a market, never
  whether the market could pay for the aircraft; the fare rises with distance
  and the movement fees do not, so a passenger ranking sorts by fee share
  descending. **FIXED**: markets that pay for their airframe come first, the
  passenger order among them is unchanged, and the recommendation names the
  airframe it was judged on. 21 of 93 → 9 of 93 dangerous, the New York
  campaign 28 of 30 collapses → 0 of 30, the curated starts unchanged.
  **OBSERVED** (docs/AE042_FINAL_REPORT.md §10). The residual nine are
  BUG-056: the aircraft market sorts by seats whatever the route is for.

## P1

*(TD-026's economy residual — Stockholm and Barcelona unreached — is
re-measured after AE-040 in docs/AE040_FEE_ECONOMY_REPORT.md §9; TD-031
holds the reference P&L reconciliation.)*

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

- **EXP-08 · HOME · The record of the game’s biggest moments is
  write-only.** REPRO: run 102 KEY-30 offers a mission on 10 January
  ("Carry 500 passengers in Africa · $250k"); the Core twin completes it
  on day 11; KEY-31 on 20 January shows no trace of it anywhere — the
  MISSIONS section is simply gone. ROOT CAUSE: the Home feed renders
  `recentEvents.suffix(14)` — the last fourteen **events**, not fourteen
  days — and with flights arriving daily a completion rolls off within a
  simulated week. The celebration overlay carries the moment live and
  nothing carries it afterwards; milestones persist, missions,
  completions and statements do not. IMPACT: a player who advances
  several days between visits — which the sunrise control actively
  encourages — can finish a mission, be paid for it, and never see that
  it happened. FIX: keep a short *notable* history (statements,
  missions, era changes, capability completions) that ages by simulated
  days rather than by event count, or surface it on the Progression
  screen where the mission lived. VALIDATION: the campaign now watches
  Home morning-by-morning and photographs the completion the day it
  lands (`advanceMorningsUntilHomeSays`). (READ + OBSERVED, run 102.)

## P3

- **EXP-03 · MAP · Edge-clipped labels.** "Langnes (Tro…" (KEY-82),
  "BELA…" country label (KEY-51), bottom label under the tab bar.
  ROOT CAUSE: airport labels clamp to the viewport only when their
  marker is on-screen; country labels never clamp. FIX: clamp or cull
  labels whose text rect crosses the safe-area edge. (OBSERVED)
  **PARTIALLY FIXED (First Month phase)**: country-label and
  under-tab-bar cases OBSERVED fixed (run 95 KEY-51); one torn airport
  label survives the full-containment cull (run 95 KEY-82, FM-03 in
  FIRST_MONTH_RUNTIME_AUDIT §5 — suspected text-width under-estimate).
- **EXP-04 · MAP · World-zoom letterbox.** At 1× with the coach card up,
  a large empty field sits above the world band (KEY-71). FIX: bias
  vertical centering by the coach card's height. (OBSERVED)
  **INVESTIGATED, DEFERRED** — chrome-coupled camera bias vs counted
  invariants; reasons in FIRST_MONTH_RUNTIME_AUDIT §3.
- **EXP-05 · WORLD · Bottom half empty** (KEY-24). FIX: surface one live
  fact per card (next storm, closest rival move) instead of static
  descriptions. (OBSERVED)
  **FIXED** — live lines per card from real state; OBSERVED with data in
  run 95 KEY-15 ("Biggest rival: PacificBlue, 1 route").
- **EXP-06 · SHEETS · No header fade at XXL type** (KEY-97). (OBSERVED)
  **PARTIALLY FIXED** — always-on bar background landed; default material
  still ghosts at XXL (run 95 KEY-97), thickened to `.thickMaterial`
  (AUTHORED, next run).
- **EXP-07 · MAP · y-clamp pan absorbs the finger silently** — the zoom
  limits have resistance+spring, vertical pan does not
  (`MAP_RUNTIME_BASELINE.md` §4, TECH_DEBT TD-023). (READ)
  **FIXED in code** — diminishing give past the clamp + spring-back on
  release, the zoom limits' shape. AUTHORED; geometry simulator-honest,
  feel is a device question (never claimed).

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
