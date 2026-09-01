# The next decision — audit (AE-036)

> What the game tells a player about what to do next, and whether its own
> suggestions are actionable. Labels: MEASURED / OBSERVED / READ /
> AUTHORED / NOT VALIDATED. Raised by AE-035's two findings; companion to
> `FIRST_ERA_RUNTIME_AUDIT.md`.

## 1. The opportunity pipeline (READ, from the implementation)

```
PLAYER STATE   fleet, bases (home + any airport with ≥3 routes, capped 5),
               era, cash, routes already served
      ↓
GENERATION     GameState.marketOpportunities(catalog:limit:)
               every (base × airport) pair not already served
      ↓
FILTERING      • per-aircraft eligibility, never a chimera of best range
                 with least-demanding runway (`routeEligibility`)
               • candidateSpecs = the fleet's own types, or — for an
                 airline with no aircraft yet — this era's buyable types
               • a pair no candidate can fly is DROPPED unless the player
                 owns nothing at all
               • demand pool must be > 0
      ↓
RANKING        capturable passengers ÷ (1 + incumbents) — a contested
               market is worth less than an open one of the same size;
               deterministic ties on codes
      ↓
PRESENTATION   Home "Next moves" (top 2 servable), map demand overlay,
               onboarding suggestions — all from this one ranking
      ↓
PLAYER ACTION  the guided route sheet (pre-picked) or the free-form sheet
```

**Where an infeasible route can enter.** Not through the recommendation
path: everything the game *suggests* is filtered by fleet eligibility
(READ, `MarketOpportunities.swift` lines 124–130). The gap is the
free-form route sheet, which lists **every** airport by demand
(`marketCandidates`) — correctly, because browsing the world is not the
same as being advised — and the commit bar did not object.

So AE-035's "Finding B" is corrected: the pipeline did not recommend
Addis Ababa. The AE-035 campaign *script* chose it alphabetically, and
the product defect it exposed is one layer down — the sheet let the
route be opened with no warning that nothing could fly it.

## 2. The dead route, root-caused

| Question | Answer | Evidence |
| --- | --- | --- |
| Why was it ranked highly? | It wasn't ranked at all — `marketCandidates` sorts by demand and Addis Ababa has demand; the *recommender* never proposed it | READ |
| Why did it pass filters? | The free-form sheet has no feasibility filter by design | READ |
| Why was range not surfaced? | The row said "No aircraft you own can serve it — range or runway"; the commit bar said nothing | READ |
| Why could it be opened? | `OpenRouteCommand` validates slots and money, not fleet capability — deliberately: a route may precede its aircraft | READ |
| Why did it stay inactive? | No owned airframe could be assigned; it sat unflown for two simulated months | MEASURED (Core twin) |
| Root-cause layer | **UI communication**, not Core generation | READ |

**Fix (AUTHORED, pending frames).** `MarketOpportunity.servableByEra`
distinguishes the two kinds of impossible using the same
`routeEligibility` arithmetic the ranking uses:

- **Fly now** — an owned aircraft can serve it (unchanged).
- **Requires an aircraft you can buy** — "Nothing in your fleet can
  serve it — the market sells aircraft that could."
- **A later era's route** — "Beyond this era's aircraft — a route for a
  later fleet."

and the commit bar warns before an unservable route is opened ("it will
wait, unflown, until you acquire an aircraft that can"). It **warns; it
does not block** — opening a route ahead of its aircraft stays a legal
strategic choice, which is the difference between guidance and autoplay.

## 3. Mission value matrix (MEASURED, campaign seed 2039)

| Mission | Player action required | Reward (before) | Reward (after) | Economic context | Progression value | Conclusion |
| --- | --- | --- | --- | --- | --- | --- |
| Carry 500 passengers in Africa (boomRush, unserved region) | lease an aircraft + open a route into a new region — the largest operational change the early game offers | **$20k** | **$250k** | January $2.0M, February $5.4M net; a single lease is $790k/month; a used narrowbody $53.7M | none directly (no era requirement mentions missions) | reward was **symbolic**; floored |

**Why it was symbolic (READ).** Reward = `$40/pax × target`, and target
= 0.6 × the player's daily seats *into that region* × boom days, floored
at 500. A region the airline already serves scales the target with its
capacity; a region it does **not** serve has zero seats, so the target
bottoms out at the floor — 500 × $40 = $20k. The mission asking for the
biggest change necessarily paid the least.

**Fix (MEASURED).** `boomRushRewardFloor` = $250k in tuning, applied in
`ProgressionSystem` when the per-pax reward falls below it. Per-pax
scaling above the floor is untouched, so a large in-region boom still
pays more. The campaign twin asserts the floor and re-measured the whole
arc unchanged (era still day 59, mission still completed day 11).

**Not changed, deliberately.** Missions remain *offers* — "ignoring one
costs nothing" is on the screen (OBSERVED, KEY-30) and no era
requirement depends on them. Making them mandatory would convert a
strategic invitation into a chore.

## 4. What the player can answer, and where

| Question | Where it is answered | Validation |
| --- | --- | --- |
| What should I do next? | Home "Next moves": idle-aircraft warning, top two servable markets with demand and competition | OBSERVED (AE-034 run 93 KEY-09) |
| What am I progressing toward? | Progression era card: "To reach Regional", with per-requirement rows and standings ("0 of 3", "Not yet") | OBSERVED (run 97 KEY-30) |
| Which mission is worth reacting to? | Mission row: objective, progress bar, reward, days left | OBSERVED (run 97 KEY-30); reward now meaningful (MEASURED) |
| Can I act on this market now? | Route sheet row + commit caution (three states) | AUTHORED, frames pending |
| What would unlock a locked opportunity? | "the market sells aircraft that could" / "a later fleet" | AUTHORED, frames pending |
| What do capability programs do, and when? | Progression: four programs, each explained, each badged "National era" | OBSERVED (run 97 KEY-30) |

## 5. Unresolved

- The Progression screen ranks nothing: it lists requirements but never
  says which action would move the most. Deliberate for now — the game
  should not play itself — but "which of these three is closest" is a
  fair question it does not answer. (PRODUCT INFERENCE.)
- Mission → progression coupling is nil: completing one pays cash and
  nothing else. Whether missions should feed era progress is a design
  question, not a defect. (READ.)
