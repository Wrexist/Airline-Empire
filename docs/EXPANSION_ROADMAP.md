# Airline Empire — Post-Launch Expansion Architecture (Phase 24)

Planning horizon: three years post-1.0. Ordered by player value per unit
of architectural risk, and grounded in seams that exist in the shipped
code — not speculation. Nothing here bloats v1.

## Year 1 — deepen the network game

1. **Hub connections** (deferred by D-010; the headline content update).
   Seam: the demand engine's pool split gains a spill term — unserved
   demand on A→C routes flows through B when the player banks schedules.
   Passengers stay aggregates (DOMAIN_MODEL rule); conservation asserted
   like `demandIsConserved`. Adds the designed hub-designation decision
   (GAME_DESIGN §4.14) and the "watch the bank flow" beat. No save-shape
   risk beyond one migration (hub designation on Airline).
2. **AI fleet lifecycle + market contest tuning.** New-aircraft orders,
   retirement of geriatric airframes, and the F-001 incumbent-divisor
   lever (BALANCING.md) — one revision of `CompetitorAISystem`, battery
   re-run before/after.
3. **Mission variety.** `MissionKind` is a closed enum built to grow:
   downturn survival contracts, storm-season reliability challenges,
   competitor-collapse land-grabs — each keyed to existing world events.
4. **Revenue management** (backlog AE-015): advance/late fare buckets as
   the real capability rule-change; touches DemandSystem's price term and
   the route card.

## Year 2 — widen the world

5. **Cargo.** The reserved seams: `Demographics.cargoIndex` (shipped in
   content), `AircraftTypeSpec` capability flags, `TransactionCategory`
   extensibility, demand segments as enum. Cargo = third demand segment +
   freighter variants + per-airport cargo terminals. Largest single
   expansion; one save migration (cargo slices).
6. **Alliances & codeshares.** Builds on the Airline entity symmetry
   (player/AI share every rule): alliance = shared network reach in the
   offer-attractiveness term + slot swaps. Requires the AI relationship
   layer — design first, it is the riskiest system socially (balance).
7. **Deeper airports.** Terminal investment, gate ownership, use-it-or-
   lose-it slots with a secondary market — extends `AirportRuntime`,
   whose lazy per-airport shape was chosen for exactly this.

## Year 3 — scale and expression

8. **Subsidiaries / regional brands** (Era V "empire" seam in
   PROGRESSION): multiple AOCs under one holding, using the existing
   multi-airline machinery — the player literally operates a second
   `Airline` entity; commands already take an `AirlineID`.
9. **Scenario worlds & eras.** `ScenarioSpec` is content: historical
   starts (deregulation, oil crisis) are new scenario + tuning + content
   files, zero engine work. Seeded-challenge sharing UI on top of the
   existing seed determinism.
10. **iCloud save sync** — only with a real conflict design (the
    versioned envelope + generation model gives last-writer-wins a
    fighting chance, but design first; PERSISTENCE §7 stands until then).

## Architectural stances reaffirmed for all of it

- New gameplay = new system + state slice + content + commands/events
  (ARCHITECTURE §12) — every item above maps to that recipe.
- Save migrations per shape change; content is append-only once shipped.
- Nothing enters the engine that the battery and determinism suites can't
  hold: every expansion lands with its own battery scenarios.
