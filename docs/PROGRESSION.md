# Airline Empire — Progression

> Phase 2 document. How the game grows with the player. Implemented in
> Phase 12; gates referenced by earlier phases must exist as data flags from
> their first implementation.

## 1. Progression philosophy

Progression is **capability and scale, not numbers**. The player never grinds
XP; the airline's real growth (fleet, network, reputation, capital) *is* the
progression. Milestones are recognitions with unlocks attached — each unlock
changes *what kinds of decisions exist*, honoring the design pillar "depth
arrives gradually" and the rule that every unlock meaningfully changes
gameplay.

## 2. Eras (the macro arc)

| Era | Identity | Entered by (milestones) | What unlocks (examples) |
|-----|----------|------------------------|-------------------------|
| I. Startup | one aircraft, survival | game start | core loop only: routes, pricing, lease/buy, small narrowbodies |
| II. Regional carrier | a name in the region | 3 profitable routes for a season + first owned aircraft | used widemarket, marketing, staff posture, second airport base, loans beyond starter line |
| III. National airline | network, not lines | positive annual profit + N destinations + reputation floor | **hub designation**, capability programs, new-aircraft orders, cabin configuration |
| IV. International | crossing oceans | hub operating + credit rating floor | long-haul types, international market entry, seasonal scheduling, fuel hedging program |
| V. Empire | shaping the market | multiple hubs + market-share threshold | multi-hub banking, fleet-family strategy tools, subsidiary/franchise hook (Phase 24 seam), prestige projects |

Era gates use *demonstrated competence* (profitable season, reputation
floor), not raw money — buying your way past learning is impossible.
Gates telegraph themselves in-UI ("2 of 3 requirements met").

## 3. Milestones & achievements

- **Milestones** (linear-ish, per era): first flight, first profitable week,
  first owned aircraft, 100k passengers, first hub bank, first transocean
  route, first million-profit month… Each fires a celebration moment
  (map flourish, livery moment) — progress must be *felt* (map = hero).
- **Achievements** (parallel, playstyle): e.g. *Value Legend* (top value
  perception 3 seasons), *Storm-proof* (season with 99% completion in a
  high-weather region), *David* (out-share an aggressive LCC on their hub),
  *Purist* (Era IV with a single aircraft family). Achievements are
  seed-fair (attainable in any world).
- **Missions/challenges** (generated, optional): world-state-derived targeted
  goals with rewards in cash/reputation ("Tourism boom in Costa del Este:
  carry 20k extra passengers this season"). Declining is free — missions are
  offers, never chores.

## 4. Capability programs (the "research" system)

Money + calendar-time investments, max 2–3 concurrent, no separate currency.
Each is a rule-change, not a stat bump:

| Program | Effect (rule change) |
|---------|---------------------|
| Efficient Turnarounds | −turnaround minutes → more rotations/day possible |
| Revenue Management | fares split into advance/late buckets (new pricing dial) |
| Fuel Hedging | lock fuel price for N months (new finance dial, cycle play) |
| In-house Heavy Maintenance | maintenance cost curve flattens for chosen family; groundings shorter |
| Ground Experience | boarding faster + service floor at owned bases |
| Network Ops Center | disruption recovery options (preemptive swaps, rebooking) |

Sequencing them against strategy *is* the mid-game decision layer.

## 5. Pacing targets (validated in Phase 18 sim runs)

- Era I → II: ~2–4 played hours (Founder difficulty ~2, Magnate ~4+).
- Era II → III: +4–8h; III → IV: +6–10h; IV → V: open-ended optimization.
- No dead zones: every era has at minimum one new system, one new aircraft
  class, and one new pressure (competition intensity, cycle exposure) —
  checked against simulated runs, not vibes.
- Late game difficulty comes from scale + market saturation + cycles, never
  from inflating old numbers.

## 6. Anti-patterns (binding)

No unlock that is strictly "bigger number, same decision"; no gate on
content the tutorialized loop already taught; no progression currency
disconnected from the airline's real economy; no daily-login mechanics.
