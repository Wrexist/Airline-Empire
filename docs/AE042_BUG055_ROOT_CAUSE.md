# AE-042 — BUG-055, root cause

Written after the baseline (docs/AE042_NEXT_MOVES_BASELINE.md) and before any
production change, as the phase required. Facts are separated by how they
were obtained.

## 1. READ — what the code does

1. `GameState.marketOpportunities` scores every candidate market as
   `pool / (1 + incumbents)`, where `pool` is the passengers a representative
   starter service would capture per day in both directions at the reference
   fare. That score is the whole ranking.
2. No cost, capacity, fee, rotation, acquisition, lease or cash term exists
   anywhere in the function.
3. Aircraft enter only as a boolean gate: `routeEligibility` (range, runway,
   minimum distance) against owned specs, or against the era's specs when the
   fleet is empty. A market is admitted or excluded; it is never ranked lower
   for needing a bigger aircraft than the route can pay for.
4. When the fleet is empty the gate's second arm (`|| ownedSpecs.isEmpty`)
   admits **every** market with a positive pool, including markets no
   era-legal airframe can fly. `NextMovesCard` then filters on `servableNow`
   and, finding nothing servable, falls back to displaying the unservable
   list.
5. `OnboardingModel.suggestions`, `NextMovesCard`, the map's demand coach and
   the route sheet's prefill all read this one ranking.
6. AE-039 removed exactly this rule from the rival AI, for exactly this
   reason: ranking by passengers "put every short large pair ahead of every
   longer one for ever" (docs/HORIZON_AUDIT.md §3.2). The player kept it.

## 2. MEASURED — what that produces

| Measurement | Result | Where |
| --- | --- | --- |
| Pickable homes whose **first** recommendation loses money after the aircraft it needs, or cannot be flown | **21 of 93 (23%)** | baseline §2 |
| Mean distance of dangerous recommendations vs safe ones | **658 km** vs **2,348 km** | baseline §2 |
| London's first recommendation, by economic rank among its own markets | **#44 of 44 — last** (Paris, −$1.3M/month, fees 85% of revenue) | baseline §2 |
| Manchester's first recommendation | **#42 of 45** (London, −$1.5M/month, fees **96%** of revenue) | baseline §2 |
| Singapore's second recommendation (a curated start) | **#18 of 18 — last** (Kuala Lumpur, −$598k/month) | baseline §1 |
| New York's second recommendation | **#21 of 22** (Toronto, −$214k/month) | baseline §1 |
| Ledger agreement with the estimate, seven pairs flown six months | **sign agrees 7 of 7**, estimate optimistic by $0.3–0.8M/month | baseline §3 |
| AE-041's scripted New York campaign, re-run this phase | **28 of 30 seeds collapse**, cash −$2.0M to −$2.9M | `ae-rival-scan 730 2030-2059 JFK --player` |
| Recommendations followed that cannot pay for their aircraft, 120 campaigns | **354 of 1,290 (27.4%)** | baseline §4.1 |

## 3. INFERRED — the mechanism

The reference fare rises with distance; the two movement fees are charged per
flight and do not. A short pair therefore maximises passengers per day (many
rotations, high frequency, dense city pairs) while minimising revenue per
movement — so the passenger-ranked list is sorted, in effect, by *fee share
descending*. That is why the ranking is not merely imprecise at the short end
but close to inverted: the markets it likes best are the ones the economy
punishes hardest. This is the same mechanism AE-039 documented for rivals,
seen from the player's side.

The inference is supported rather than assumed: the monotonic distance
ordering of the verdict classes (§2) and the fee shares measured on the
recommended pairs (96%, 85%, 68%, 63% at the dangerous end against 40%, 28%,
18% at the safe end) are both MEASURED.

## 4. The decision

**CASE B, with CASE A as its cause and CASE E at fleetless homes.**

- **CASE B — the eligibility filter is too weak.** It asks "can some aircraft
  fly this?" and never "can this pay for the aircraft it needs?". This is the
  primary fault: the traps are excluded by no gate at all.
- **CASE A — the ranking metric is why the traps surface first.** A
  passenger-only metric does not merely fail to rank the traps down, it ranks
  them top. Without this, a weak gate would rarely matter.
- **CASE E — at a fleetless home the filter admits the unflyable.** Nadi's
  two suggestions are 7,132 km and 3,170 km, beyond every startup airframe,
  and the card's servable-filter fallback shows them anyway.

**Not the primary cause, on the evidence:**

- **CASE C (acquisition cost ignored)** and **CASE D (cash ignored)** are true
  as READ facts, but the traps fail on their own operating economics before
  any question of who can afford them: Manchester–London loses $1.18M a month
  in the ledger no matter how the aircraft was paid for. Adding a cash term
  is not needed to remove them, and would make the ranking depend on the
  player's balance sheet — a larger change than the evidence demands.
- **CASE F (the UI oversells uncertain opportunities)** is partly true — the
  heading is "Strong open markets from your bases" and the only figures shown
  are passengers, distance and competition — but the wording is a symptom.
  Once the traps are gone the sentence is no longer false. One narrow
  exception is carried into the fix (§6).

## 5. Not a stop condition

Stop condition 10 asks whether the problem is really TD-031 (short-haul fee
and fare balance) or another economy defect out of scope. It is not, and the
distinction matters:

- The economy is doing what it is calibrated to do. Short-haul at hub fees is
  expensive; AE-040 measured it, TD-031 records it, and this phase changes
  none of it.
- The defect is that the **advice walks the player into it**. A game may
  contain unprofitable routes; it may not recommend them under a heading that
  says "strong".

No tuning value, fee, fare or demand parameter is touched by the fix.

Stop condition 2 (the estimator is materially inaccurate) is also cleared:
the estimate's sign matches the ledger on 7 of 7 sampled pairs and errs
generous, so a market it rejects is rejected with margin. The one divergence
found — the demand forecast under-reads Singapore–Kuala Lumpur — is recorded
in the audit and does not change that verdict.

## 6. AUTHORED — the fix, and why it is the smallest correct one

**Gate, then rank; do not replace the ranking.**

Three candidate designs were measured over production's own candidate set
before choosing (baseline §5):

| Design | New York | Manchester | The three curated starts | Verdict |
| --- | --- | --- | --- | --- |
| Rank by what a market keeps after its aircraft (`keeps`) | Lisbon, London | Lagos, Istanbul | **all change** | Corrects everything, but sends every home to its longest reachable route at one rotation a day, selling a fifth of the demand it names. A different game's advice. |
| Gate out what cannot pay, keep the order (`safe`) | Chicago, **Mexico City** | **Cairo, Istanbul** | **unchanged** | Removes every trap, leaves sound advice alone. |
| Add a cash/affordability term | not measured | | | Not required by the evidence (§4), and makes advice depend on the balance sheet. |

The gate wins on the rule the phase set: the smallest change that answers the
question. It leaves Stockholm, Barcelona and Munich — the starts the AE-039
and AE-041 twins and journeys are pinned on — **byte-identical**, and changes
only the homes where the advice was a trap.

**The rule.** A market qualifies when some airframe the player could operate
(their own types if they have any, the era's if not) that can actually fly the
pair would, on the flight system's own arithmetic, keep more than nothing
after the airframe's monthly lease and the crew it carries:

```
max over flyable candidate specs of
    airframeDayValue(.profit) × 30 − spec.leaseMonthly − payrollPerAircraftMonthly   >   0
```

Everything on the right already exists and is already trusted: the estimator
is the one AE-040 corrected and AE-041 shipped for rivals, and this phase
measured it against the ledger on seven pairs. No second economy is created.
The only boundary is zero, which is not a tuned threshold — it is the
definition of paying for itself.

**Ranking.** Unchanged: `pool / (1 + incumbents)`, ties on code.

**Never strand the player.** The gate reorders rather than deletes: qualifying
markets come first, and if a home has fewer than `limit` of them the rest of
the passenger-ranked list follows, so a Nadi player still sees the best
available and the onboarding checklist still has a first route to teach.
Nothing disappears from the route sheet, which lists every destination by
design.

**The one UI sentence (CASE F, narrowly).** Measurement showed a second,
distinct failure the gate does not fix: at 9 of 93 homes a market that pays
well on the right airframe loses money on the one the aircraft market's
default sort puts first (Reykjavík–London: **−$703k** a month on a 184-seat
narrowbody, **+$141k** on a 90-seat regional jet). The recommendation is
judged on an airframe and never names it. Carrying that airframe onto the
card is one sentence, corresponds exactly to real state, and closes the gap
between the advice and the acquisition screen. The wider defect — that the
market's default sort recommends the largest aircraft regardless of the route
— is recorded as **BUG-056** and not fixed here.

**What is explicitly not changed:** the rival AI and its ranking, every tuning
value, the fee model, the fare formula, the demand system, the save format,
`marketCandidates`' own order (the route sheet lists everything on purpose),
and the passenger-ranking score itself.
