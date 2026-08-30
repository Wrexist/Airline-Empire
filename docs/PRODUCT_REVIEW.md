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
| UX / UI | **Rebuilt, compiled, unvalidated on a device** | Reassessed 2026-08-29 by `docs/UIUX_FORENSIC_AUDIT.md`, which found the screen set complete and the *product* thin: five P0s including a tab bar that overflowed into the system More list, a route P&L that read ¤0 for a month, a first flight that produced no feed line, rejections raised beneath the sheets that caused them, and a failure journey with no interface at all. All P0s and P1s addressed; the app now compiles on macOS (CI 33244671402). Rendering still needs a device |
| Visual quality | **Improved, art direction still not started** | Coastlines under the map, liveries per carrier, an identity accent instead of the system blue, celebration moments, a painted launch screen. Still no custom art of any kind: no aircraft silhouettes, no airport imagery, SF Symbols throughout (audit §9) |
| Audio & feel | **Built and tested as policy; never heard** | Added 2026-08-29 across two phases. 54 semantic cues + 4 music beds, all original and procedurally generated; the *decisions* (priority, dedup, cooldown, 16x aggregation, ambience response, music state, settings resolution) live in Core and carry 50 tests. Every tap target gained a press state. What is entirely unknown is whether any of it sounds good: this environment has no speaker and cannot run a simulator (TD-006, task AE-026) |
| Accessibility | **Baseline plus, unaudited** | Labels/44pt/semantic colours authored; explicit Reduce Motion; a map summary for VoiceOver over an otherwise opaque `Canvas`. The 44pt and Dynamic Type audits need devices |
| Onboarding | **Core built + UI authored** (2026-08-26) | Guided first-route beat: `OnboardingModel` read model (checklist + demand-ranked route suggestions) tested in Core; Dashboard card + prefilled route sheet authored. Runtime validation pending macOS. The audit's remaining gap against `PLAYER_JOURNEY` §1 is that the player starts with **no aircraft** — the script opens with a leased turboprop on the apron, which makes the first decision "where do I fly" rather than "how do I shop" |
| Replayability | **Good** | Seeded worlds, archetype casts, era variety; scenario presets missing (fixed this phase — see below) |

## Ranked issues

> **Status note, 2026-08-29.** Items 1 and 2 below are largely superseded.
> The app **compiles** (CI run 33244671402, `xcodebuild` on macOS), and the
> UI/UX forensic audit rebuilt most of the client. What has *not* changed is
> the honest part of item 1: nothing here has been seen to render. Read the
> two entries as history plus the updates inside them.

### Critical (release-blocking)
1. **The app has never been compiled or run** (B-002). Everything UI is
   unvalidated. → First macOS session: compile, fix, run the core flow.
   **Update 2026-08-26:** the Linux-side risk reduction is now done — all
   sources parse, every Core API call is verified, screen data contracts
   and full player journeys are covered by Core tests, and three P1
   journey defects invisible to unit tests were found and fixed (BUG-003
   game-over dead end, BUG-004 rival financials in the player feed,
   BUG-005 silent command rejection). The Xcode handoff is
   `docs/APPLE_VALIDATION.md`. The claim remains **not Apple-runtime
   validated** — that cannot change without a Mac.
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
9. ~~Weekly/evening digest aggregation (CORE_LOOP §3)~~ → **Built
   2026-08-26.** `DailyDigestModel` derives yesterday's money by category,
   flights flown/cancelled, and the day's news from the ledger's
   timestamped ring and the event log — no new persisted state, save
   format still v10. It reports `isComplete: false` rather than
   under-counting when a very large network out-posts the ring. Dashboard
   renders it as a "Yesterday" card with a **Why?** breakdown. 6 tests.
   Runtime validation pending macOS like the rest of the UI.
10. iPad sidebar layout not authored (TabView only). → macOS queue.

### Low
11. ~~Milestone celebration moments~~ → **Built 2026-08-29.** Eras, milestones,
    achievements, completed programs and missions raise a brief non-blocking
    overlay with success haptics. The *map flourish* specifically is not built.
12. Fictional-name polish pass on airport/city naming consistency.
13. Reputation-change events for the feed (state is visible; no events).
    Still true, and now the clearest remaining explainability gap: the
    reputation screen says what each component *is* and what moves it, but
    nothing tells the player when one actually moved.

### Added by the 2026-08-29 audit and still open
14. **No starter aircraft.** `PLAYER_JOURNEY` §1 opens with one on the apron.
15. **The type scale is applied, not yet adopted everywhere.** `AEType` names
    eleven roles and the shared components use it; several hundred original
    `.font(...)` call sites in feature screens still name system sizes. They
    are being converted as each screen is reworked rather than mechanically,
    because a blind sweep would change every screen's proportions with nobody
    able to look at the result (`docs/DESIGN_SYSTEM.md` §10).
16. **Localization: zero.** ~700 string literals; numeric formatting is now
    locale-correct, the strings are not (audit UI-036).
17. **Audio is built but unheard.** The cue vocabulary, the director, the
    engine and 58 generated assets all exist (`docs/AUDIO_ARCHITECTURE.md`);
    what is missing is a device it has ever been played on, and an authored
    score behind the four generated beds (TD-006, TD-009).
18. **Hub connections** — still descoped to the first content update (D-010),
    and still the missing mid-game transformation.

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


---

## AE-029 addendum — fleet and aircraft (2026-08-30)

**The central loop had a dead end in it.** Opening a route and assigning an
aircraft is the game's core action, and both pickers that complete it were
offering pairings Core would refuse: no range check, no runway check. A player
following the intended first-hour path — found airline, buy aircraft, open
route, assign — could hit a refusal that reads as their mistake and is not.
Fixed (BUG-032); it is the most player-visible thing in this phase.

**Two refusals had unreachable copy.** "This airport cannot take your aircraft"
and "wait for your flights to land" were both written and both unreachable,
because the app switched on strings Core has never emitted (BUG-033). The
market's most common refusal — trying to buy an aircraft class the era does not
allow — had no mapping at all.

**The market now says what an aircraft is for.** It showed a category and a
fuel figure to three decimals. It now shows a role, a sentence naming the
trade, and an efficiency band — which surfaced the fact the numbers were
hiding: regional aircraft are the *most* expensive per passenger to fly, not
the cheapest. That inverts what a new player would assume from the price tag,
and it is the single most useful thing the screen now tells them.

**Fleet scales.** Filtering by status, ownership and type, tested for
partitioning rather than losing rows.

**Unchanged, and still the top of the list:** nothing has been seen rendered.
Four phases have now shipped a visual system, a map, audio and a fleet UI that
no one has looked at. This phase's own asset audit found that at world zoom —
the level a player spends most time in — aircraft do not use their category
silhouettes at all, which nobody had noticed because nobody has watched the
map. That is not a bug; it is evidence about how much is being taken on trust.
