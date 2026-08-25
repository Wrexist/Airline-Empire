# Airline Empire — Competitor AI (Phase 10, as built)

## Ground rule

AI airlines are ordinary `Airline` entities that act **only** through the
same commands and validators as the player (`CompetitorAISystem.issue` runs
`validate` → `apply`; a rejection means the decision silently doesn't
happen). No private APIs, no free money, no phantom slots — asserted by
`aiPlaysByPlayerRules` and enforced structurally.

## Personalities (`AIProfile`)

Five archetypes; every behavioral parameter derives from the archetype:

| Archetype | Fare vs ref | Service | Shops for | Financing | Geography |
|---|---|---|---|---|---|
| lowCost | 0.85× | basic | used/leased narrowbodies (12y) | leases, borrows to 55% | anywhere |
| premium | 1.25× | premium | young large-narrow/widebodies (3y) | buys, ≤40% debt | anywhere |
| regional | 1.0× | standard | turboprops/RJs (12y) | buys, ≤40% | **home region only** |
| conservative | 1.05× | standard | mid-age narrowbodies (8y) | ≤20% debt | anywhere |
| expansionist | 0.95× | standard | whatever's cheap (14y) | leases, borrows to 70% | anywhere |

Price war responses differ: LCC undercuts back (floor 0.6× ref), premium
holds a 1.1×-ref floor and cedes the bottom, others match-plus-a-hair.

## Decision engine (`CompetitorAISystem`, daily cadence, staggered)

One decision slot per airline per `decisionIntervalDays` (7), offset by
airline ID — the market moves continuously, never in lockstep. Priority
order per slot:

1. **Survive** (cash runway < 1.5 months of costs, measured from the last
   statement or a structural estimate): close the worst loss-maker
   (negative closed-month direct P&L), shed idle metal (return leases,
   sell owned).
2. **Employ idle aircraft**: thicken a hot route (load > 0.82) it can
   serve, else open the best new market from where the airframe sits —
   candidates scored `demandPool / (incumbents + 1)`, gated by eligibility,
   slots, archetype geography, and a viability floor; fare = ref ×
   archetype factor.
3. **Tune the network**: respond to >12% undercuts per archetype policy;
   push frequency on >0.82 loads; trim on <0.35; close persistent losers.
4. **Grow** (runway ≥ archetype threshold, fleet < cap 40): lease or buy
   used per preference; if short of cash and within the archetype's debt
   comfort, take a loan sized to the purchase and buy.

Everything is deterministic: sorted iteration, no RNG in decisions (the
world's randomness reaches AI only through outcomes).

## World population (`WorldSetup.createCompetitors`)

Founds up to 8 fictional named competitors at the busiest large airports
(skipping the player's home), archetypes in rotation, each with capital and
a starter aircraft — all via commands. Failure is real: competitors flow
through the same administration/collapse path as the player (Phase 8), and
their slots/routes release back to the market.

## Verified by tests (9 new; 161 total)

Setup founds distinct competitors with fleets; most AIs operate revenue
routes within 60 days; archetype fare separation (LCC < premium); AI cuts
fares within ~3 weeks of a 40% undercut invasion; healthy AIs grow fleets
within 2 years, never past the cap; 3-year 5-AI world: integrity clean
every month, bounded flights, sane balances, >1000 completed flights;
dual-run determinism over 200 days; player-with-profile rejected.

## Deliberate scope notes

Hub development emerges from "thicken hot routes from where aircraft sit"
rather than an explicit hub planner — an explicit hub strategy joins the
Phase 12 capability work. Fleet replacement (retiring old airframes) rides
on retrench/maintenance economics for now; a proactive replacement rule is
a Phase 18 balance candidate. Marketing remains deferred (REPUTATION.md).
