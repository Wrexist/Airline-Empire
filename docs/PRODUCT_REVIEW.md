# Airline Empire — Product Review (Phase 22, current-scope audit)

Reviewed 2026-08-25, covering phases 0–20 as built. Verdicts are against
the design bible and architecture, not against aspiration. UI-dependent
dimensions are assessed on authored code + Core read models and flagged.

## Scores

| Dimension | Verdict | Notes |
|---|---|---|
| Simulation | **Strong** | Deterministic, save-safe, chunk-invariant, 209 tests; every system emerged test-first with real bugs caught (RNG collapse, stale flights, EWMA clamp, fuel quantization) |
| Economy | **Strong** | Explainable end-to-end (ledger → statements → route P&L); calibrated to anchors; battery-verified; margins compress under competition |
| AI competitors | **Good** | Same-rules AI with distinct personalities; survives/fails honestly; gaps: no new-aircraft orders, no proactive fleet renewal, rarely contests distant markets (BALANCING F-001 watch item) |
| Living world | **Good** | Systemic events with fair forecasts; strike feedback loop closes; volume tuned conservative (readability first) |
| Progression | **Good** | Era gates + rule-changing capabilities + missions; thin in mission variety (one kind) and celebration surfaces (UI) |
| Persistence | **Strong** | Atomic, rotated, migrated, fuzz-tested; honest recovery reporting |
| Performance | **Strong** | 2.7× under budget at late-game scale, linear scaling, measured not guessed |
| UX / UI | **Authored, unvalidated** | Complete screen set consuming tested read models; zero compile/run validation (B-002) — nothing here counts until the macOS pass |
| Visual quality | **Deferred** | v1 tokens only; Phase 17 art direction not started |
| Accessibility | **Baseline only** | Labels/44pt/semantic colors authored; audit requires devices |
| Onboarding | **Core built + UI authored** (2026-08-26) | Guided first-route beat: `OnboardingModel` read model (checklist + demand-ranked route suggestions) tested in Core; Dashboard card + prefilled route sheet authored. Runtime validation pending macOS |
| Replayability | **Good** | Seeded worlds, archetype casts, era variety; scenario presets missing (fixed this phase — see below) |

## Ranked issues

### Critical (release-blocking)
1. **The app has never been compiled or run** (B-002). Everything UI is
   unvalidated. → First macOS session: compile, fix, run the core flow.
2. **No onboarding**: a new player lands on an empty dashboard with no
   guided first route. The first-five-minutes contract (PLAYER_JOURNEY §1)
   is the difference between a game and a simulator core. → macOS queue,
   design exists. **Update 2026-08-26:** built to the limit of Linux —
   Core `OnboardingModel` (derived checklist, no persisted flags, zero
   save impact; demand-ranked first-route suggestions) with 4 tests;
   Dashboard onboarding card + suggestion-prefilled OpenRouteSheet
   authored. Remains on this list only for its macOS runtime validation.

### High
3. **Hub connections not implemented.** GAME_DESIGN §4.14 and the demand
   spec promise connecting itineraries; v1 demand is point-to-point only.
   The mid-game "network transformation" beat is missing. Decision D-010:
   descoped from v1.0 to the first content update — implementing it under
   an unvalidated UI would be building on sand; the demand-engine seam
   (spill term) is reserved.
4. **Difficulty/scenario presets missing** (Founder/Entrepreneur/Magnate,
   GAME_DESIGN §5). → **Fixed in this phase**: scenario content +
   bootstrap + tests (see below).
5. **AI fleet lifecycle**: competitors never order new aircraft or retire
   geriatric ones; late-game AI fleets will age poorly over very long
   runs. → post-v1 with F-001's market-entry lever, one AI revision.

### Medium
6. Command-replay log promised in SIMULATION_ARCHITECTURE §2 was never
   built; determinism is instead verified by dual-run + save/continue
   equality, which covers the guarantee. → D-010 amends the doc (replay
   tooling deferred to QA needs).
7. `LocalAnalytics` service (ARCHITECTURE §8) superseded by statement
   series + route economics, which feed the charts. → D-010 amends.
8. Mission variety: one kind (boomRush). Seam is clean (`MissionKind`).
9. Weekly/evening digest aggregation (CORE_LOOP §3) is UI work; events
   and statements provide the data. → macOS queue.
10. iPad sidebar layout not authored (TabView only). → macOS queue.

### Low
11. Milestone celebration moments (map flourish) — Phase 16/17.
12. Fictional-name polish pass on airport/city naming consistency.
13. Reputation-change events for the feed (state is visible; no events).

## Release-blocking list (consolidated macOS queue)

1. Compile + validate app target (14/15) — includes fixing authored-code
   errors, simulator walkthrough of new game → route → fast-forward → save.
2. Onboarding beat (guided first route) + evening digest surface (16).
3. UX polish pass per Phase 16 checklist; haptics/sound services.
4. Art direction pass (17).
5. UI-surface adversarial QA (19b) + Instruments profiling (20b).
6. Accessibility audit on devices (21).
7. Release engineering (23): signing, clean-build, offline verification,
   store metadata, RELEASE_CHECKLIST.md.

Until that queue clears, the project is a **complete, hardened, tested
game core with an authored-but-unproven client** — exactly what it claims
to be in the task files, no more.
