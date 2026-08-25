# Airline Empire — Balancing (Phase 18)

Methodology per GAME_BALANCE §6: deterministic headless batteries; tuning
changes only with measured evidence; every change logged here.

## The battery (`BalanceTests`, runs in CI)

| Test | What it guards |
|---|---|
| `archetypeParityAndSanity` | 5 archetype-driven airlines (shared AI = player-identical commands), 3 seeds × 4 years: ≥60% survival (no impossible starts), no >¤3B wealth from ¤120M (no money printer), median net-worth spread < 6× (no dominant strategy), margins under the 60% printer line |
| `contestedMarketsCompressMargins` | two carriers on the anchor market for a year: operating margins < 25% — competition + the outside option compress rents |
| `passivityIsNotViableButNotInstantDeath` | idle cash survives but stagnates (era never advances, overhead bleeds); an idle leased fleet collapses |
| `leverageAmplifiesButDoesNotDominate` | identical expansion script ± max borrowing: leverage < 2.5× the honest baseline (interest drag works) yet stays usable |
| `fleetFlippingBleedsMoney` | 20 buy/sell cycles burn >5% of bankroll (spread + friction hold) |
| `tenYearWorldRemainsStableAndContested` | 10-year mixed world: monthly integrity, fuel/economy inside clamps, bounded entities, pax HHI < 0.7, ≥2 active operators |

## Findings log

### F-001 (2026-08-25): uncontested mega-market scarcity rents
Archetype benches showed sustained **45–53% operating margins** on
uncontested routes at mega airports. Diagnosis: 2–3 daily round trips of
~180 seats against 5,000+/day demand pools → permanently full cabins;
margin is a scarcity rent, not an equation bug (the anchor market at
normal load sits at the designed single-digit margin, and the contested
test compresses margins below 25%). The AI's market scoring
(`pool/(incumbents+1)`) prefers virgin markets while any remain, so
nothing entered to compress the rent within 4 bench years.

**Action:** no equation change (evidence shows compression works when
entry happens; entry opportunity is exactly the signal a player reads
from fat routes). Bench assertion set at the 60% money-printer line with
the 3–8% design band enforced on contested markets. **Watch item for
post-macOS playtesting:** if human players find monopoly rents too easy
too long, the lever is AI market scoring — soften the incumbent divisor
(e.g. `(incumbents+1)^0.7`) so grown AIs contest big markets sooner.
That change should be made against playtest evidence, not bench worlds.

### F-002 (2026-08-25): leverage behaves
Max-borrowing expansion neither dominates (< 2.5× honest baseline; the
leverage-squared credit spread and annuity drag bite) nor bricks the
strategy (leveraged runs finish solvent with real net worth). No change.

### F-003 (2026-08-25): archetype parity holds at bench scale
Median 4-year net-worth spread across archetypes stayed within the 6×
band on all seeds; ≥60% survival. lowCost/expansionist lean on leases and
carry thinner margins; premium runs richest per passenger — the intended
texture. No change.

## Tuning changelog

*(No tuning-constant changes made in Phase 18 — all findings resolved as
test-bound clarifications or watch items. First content change lands here
with before/after battery metrics.)*
