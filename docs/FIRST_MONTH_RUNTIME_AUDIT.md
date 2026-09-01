# The first month — runtime audit (AE-034 "The First Month")

> The phase's evidence ledger. Everything here is labeled: MEASURED /
> OBSERVED / READ / AUTHORED / NOT VALIDATED. Companions:
> `PLAYER_JOURNEY_RUNTIME_AUDIT.md` (the first session, already audited),
> `GAME_EXPERIENCE_PRIORITY.md` (the ranked backlog this phase draws from).

## 1. The boundary, before this phase

KNOWN (OBSERVED in decoded CI frames, runs 84–91): founding, the market,
leasing, route opening, assignment, the first flight airborne and at 16×,
first landing and first revenue (the checklist retiring), every tab in
light/dark/XXL type, the map at every tier.

UNKNOWN (READ only — the code paths exist, no automation had ever driven
them): a month-end closing; a `MonthlyStatement` on screen; the Finance
tab with real numbers (every frame of it says "No month has closed yet");
the "First profitable month" milestone celebration; Home the morning
after a close. Also never rendered: an era change, game over, an
antimeridian route, late-game density (TD-021) — **explicitly out of this
phase's scope** except as the frames volunteer them.

## 2. How month-end is reached (READ, the scenario design)

- `StatementRollupSystem` (cadence `.monthly`) drains the ledger's month
  accumulator into a `MonthlyStatement`, emits `.statementClosed`, and
  rolls route economics. `firstProfitableMonth` is reached when the
  latest statement's `netProfit > 0` (`ProgressionSystem.checkMilestones`).
- The journey drives it with a real product control: "Advance to next
  morning" simulates synchronously to the next midnight
  (`GameSession.advanceToNextMorning`), so 31 taps carry 2030-01-01 to
  2030-02-01 through the full engine — flights, billing, reputation —
  with **no wall-clock dependence and no test-only scaffolding**. The
  loop exits on the calendar (February appearing in Home's header), never
  on elapsed time.
- Profitability is deliberately not asserted: whether one leased
  narrowbody on one route clears its lease in month one belongs to the
  balance (`GAME_BALANCE.md`), not to a UI test. The test's contract is
  the *statement* — a "Jan 2030 statement" header and a "Net profit"
  line; the milestone overlay is photographed when it appears.

New test: `testTheFirstMonthClosesWithAStatement` (AUTHORED; frames
pending the phase's CI run). Exported keyframes: `10-before-month-end`,
`11-home-after-month-end`, `12-finance-first-statement`,
`13-route-after-month`, `14-first-profitable-month` (opportunistic).

## 3. EXP items worked alongside (each labeled)

- **EXP-03 — edge-clipped labels. AUTHORED, fix at three root causes.**
  (1) Re-projected label memory never re-checked bounds between settles —
  "Langnes (Tro…" (run 85 KEY-82) was a label mid-slide across the edge;
  memory now culls at the placer's own keep boundary (±12 pt, the L4
  hysteresis rect), so the exit rule is one rule. (2) Country labels had
  no bounds check at all — "BELA…" (run 84 KEY-51); `placeCountries` now
  refuses boxes that cross the legible bounds, and the reproject path
  culls the same way. (3) The canvas deliberately bleeds under the tab
  bar, and label placement used the full canvas — labels could be
  *placed* into the covered strip; placement now subtracts the bottom
  safe-area occlusion (`MapFrame.bottomOcclusion`), geometry untouched.
- **EXP-04 — world-zoom letterbox. INVESTIGATED, DEFERRED with reasons.**
  The band's vertical position is the camera's y-clamp centring the world
  in the canvas. Biasing it by the coach card's height would couple
  chrome layout into camera math whose invariants are counted and
  CI-asserted, to improve a transient state (world zoom + coach card,
  pre-first-route only). Judged not worth the coupling; recorded here so
  it is a decision, not an oversight.
- **EXP-05 — World tab. AUTHORED.** The hub cards now carry one live fact
  each where real state exists: the current world event by name ("Now:
  …", from `world.activeEvents` via `Vocab.worldEvent`) and the biggest
  rival with its route count. Derived per render from the snapshot;
  nothing invented, nothing stored.
- **EXP-06 — XXL sheet header. AUTHORED.** The market sheet's navigation
  bar background is now always visible (`.toolbarBackground(.visible)`),
  so scrolled card text cannot bleed through the header band the run-84
  KEY-97 frame photographed. A surface, not a decoration.
- **EXP-07 / TD-023 — pan edge. AUTHORED / OBSERVED IN SIMULATOR only.**
  The vertical clamp is now the same shape as the zoom limits: past the
  edge the camera follows at a diminishing fraction (bounded at 0.04
  world-height, so the void never shows) and `commitPan` springs back on
  release, exactly as `commitZoom` does. What CI can verify: geometry,
  bounds, the spring landing on the clamped centre. What it cannot:
  whether the resistance *feels* right — that is a device question and is
  not claimed (see §6).

## 4. Frames inspected (runs 94 and 95, OBSERVED)

| Frame | What was actually looked at |
| --- | --- |
| KEY-10-before-month-end | Home on 2030-01-31: month-to-date accumulated, checklist long gone, Next Moves ranking live. |
| KEY-11-home-after-month-end | 2030-02-01 00:00. "Last month **$959k** ↗" tile populated (was an em-dash for the whole project's history), month-to-date reset to $0, reputation 60 % → 75 %, net worth held at $60.0M. Time visibly passed and the outcome is on the surface. |
| KEY-14-first-profitable-month | The celebration overlay, caught live: star icon, "First profitable month — The airline made more than it spent this month." The new detail line renders; no confetti, no interruption. |
| KEY-12-finance-first-statement | The whole answer stack: forecast card now reads "Last month made money — there is no burn to run out of" (green, prose); the monthly net-profit chart shows one ~$959k January bar; "JAN 2030 STATEMENT" lists per-category rows (Airport fees −$953k, Crew −$141k, Leases −$790k…), Net profit below the fold. Period, profit and cash are all distinguishable at a glance. |
| KEY-13-route-after-month | ARN–LHR detail on Feb 1: "Last full month **$1.9M**", load 100 %, punctuality/completion 98 %, "Where the money went" with This-month vs Last columns, and the honest morning-after line "Too new to judge — the first flights have not landed yet." |
| KEY-15-world-after-month | The World hub with something to say: "Biggest rival: PacificBlue, 1 route" live line, progression badge at 17 % to next era. No world event was active — the events line is honestly absent. |
| KEY-51 / KEY-82 / KEY-97 | EXP re-checks, §5. |

## 5. Defects found (from the frames)

- **FM-01 (fixed in-phase, test-side).** The statement assertion searched
  "Jan 2030 statement" while `AESectionHeader` renders uppercased — run
  94 failed on it with the statement demonstrably on screen (KEY-11's
  populated tile). One cycle spent; run 95 green.
- **FM-02 (fixed in-phase).** Spec-bar labels wrapped mid-word at XXL
  type ("Rang / e", run 94 KEY-97) — fixed 62 pt column became a minimum.
  OBSERVED fixed in run 95's KEY-97.
- **FM-03 (open, P3).** One torn edge label survives: run 95's KEY-82
  still shows "Langnes (Tron" cut at the right edge *after* the
  full-containment cull — while the under-tab-bar and country-label
  cases (KEY-51) are OBSERVED fixed. Working hypothesis: the placer's
  estimated text width (chars × 6.4 + 10) under-measures the rendered
  string at this size, so a box passes containment while its glyphs
  overflow it. Next step is measuring the rendered width from the frame
  pixels before touching the estimate. Not worth a third cycle this
  phase; recorded in GAME_EXPERIENCE_PRIORITY.
- **FM-04 (improved, residual open, P3).** XXL sheet header: the default
  visible toolbar material still let card text ghost through (run 95
  KEY-97); strengthened to `.thickMaterial` — AUTHORED, rides the next
  run.

## 6. Device validation still required

Unchanged from the backlog, restated so this phase cannot be misread as
closing them: pan/zoom feel and the new edge resistance (iPhone in hand,
rapid pan into the top/bottom clamp; expected: visible give and a clean
spring, no jitter), ProMotion pacing, haptics, audio audibility, battery
of the 30 Hz ambient cap (TD-022), VoiceOver order, TestFlight signing.
