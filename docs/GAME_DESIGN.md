# Airline Empire — Game Design Bible

> Phase 2 document. The definition of what Airline Empire *is*. Implementation
> phases build these systems; anything not serving a player decision listed
> here gets cut, not built. Companions: `CORE_LOOP.md`, `PROGRESSION.md`,
> `GAME_BALANCE.md`, `PLAYER_JOURNEY.md`.

## 1. Core fantasy

**"I am running an airline — and I built this entire network."**

The player is founder-CEO of an airline: chooses where to fly, what to fly,
what to charge, and what kind of airline to be — then watches a living world
respond. The emotional payload is *ownership of a growing network*: the map
slowly filling with routes that exist because of the player's decisions, each
with a history the player remembers ("my first transatlantic", "the route
that nearly bankrupted me").

Not the fantasy: spreadsheet homework, twitch reflexes, waiting for timers,
or paying to skip waiting. The game respects the player's intelligence and
their time.

## 2. Design pillars

Every feature must serve at least one pillar; features serving none are cut.

1. **Meaningful choices under constraint.** Money, aircraft, slots, and
   reputation are always scarcer than ambitions. Every screen ends in a
   decision, not a report.
2. **A living, reactive world.** Competitors expand and retreat, fuel spikes,
   seasons swing, storms ground fleets. The world moves whether or not the
   player does — but never unfairly: every consequence is traceable.
3. **Explainability.** Any number a player sees can be opened up: why this
   route lost money, why demand fell, why reputation dipped. No mysterious
   modifiers. (This pillar is why the ledger and demand breakdowns are
   architectural requirements, not UI garnish.)
4. **The network is the hero.** The map is the primary lens: progress is
   *visible geography*, not a level counter.
5. **Depth that arrives gradually.** Systems unlock as the airline grows;
   the first hour is one aircraft and one route, the fiftieth is a
   multi-hub scheduling and positioning puzzle. Complexity is opt-in-by-
   growth, never front-loaded.

## 3. The player: decisions at each timescale

- **Minute-to-minute (session texture):** react to events (delay, storm,
  competitor undercut); tweak a price; inspect a route's performance; assign
  a newly delivered aircraft; skim the ops feed; pan the map and watch
  flights move.
- **Daily loop (simulated day, the game's heartbeat):** flights run, cash
  flows, punctuality accrues. Player mostly *observes and nudges*; the game
  plays well at 4× with occasional pauses.
- **Weekly strategic loop:** the decision layer — open/close routes,
  reprice, order/lease aircraft, adjust service tiers, take/refinance loans,
  respond to competitor moves, plan around the season ahead.
- **Monthly/era loop:** hub establishment, fleet-type strategy (commonality
  vs. fit), market entries, capability programs (research), positioning
  (budget vs. premium), reading market cycles.

## 4. System specifications

Each system: purpose → player decisions → key mechanics → interactions.
(Quantitative anchors in `GAME_BALANCE.md`; equations land in their
implementation phases' docs.)

### 4.1 Airline creation
- **Purpose:** identity + difficulty + replay seed.
- **Decisions:** name/livery color, home airport (= starting market:
  a big-hub start is rich but competitive, a regional start is safe but
  small), starting scenario (era/cash/difficulty), fixed seed or random.
- **Mechanics:** scenario defines starting cash, one owned or leased
  starter aircraft, home slots. Seed shown on the save (determinism is a
  feature: challenge runs shareable by seed).

### 4.2 Headquarters & staff (aggregate)
- **Purpose:** overhead that scales with ambition; a lever for efficiency.
- **Decisions:** staffing levels per function (ops, service, maintenance
  crews — aggregate pools), wage posture (pay above/below market moves
  morale → punctuality/service), training investment.
- **Mechanics:** headcount requirements derive from fleet/routes; understaffing
  creates delays and service penalties, overstaffing burns cash. No
  individual-person management (DOMAIN_MODEL aggregates rule).

### 4.3 Fleet
- **Purpose:** the core capital decision; aircraft are the airline's identity.
- **Decisions:** buy vs. lease (cash vs. flexibility), type commonality
  (maintenance/crew discounts vs. right-sizing), new vs. used (price vs.
  reliability/fuel burn), cabin configuration (density vs. comfort tier),
  when to retire/sell.
- **Mechanics:** aircraft age → maintenance cost and reliability drift;
  residual value declines; delivery lead times for new orders (used market
  is immediate but worse condition). Utilization tracked — an idle aircraft
  is a burning lease.

### 4.4 Airports & slots
- **Purpose:** geography as strategy; scarcity that shapes networks.
- **Decisions:** which markets to enter; paying up for congested hub slots
  vs. secondary airports; hub designation (see 4.14).
- **Mechanics:** runway class gates aircraft types; slot capacity per day is
  finite and competed for; fees scale with airport tier; airports carry
  demographics (business/leisure/tourism/population) driving demand.

### 4.5 Routes & scheduling
- **Purpose:** the atomic strategic object; the thing the player "owns".
- **Decisions:** open/close, frequency per week, aircraft assignment,
  departure banking at hubs, ticket price per cabin.
- **Mechanics:** eligibility = range + runway + slots; frequency drives
  schedule quality (demand share) and aircraft/crew requirements; each route
  keeps a rolling P&L the player can open (pillar 3).

### 4.6 Flights (operations)
- **Purpose:** make the simulation *visible*; source of operational truth.
- **Mechanics:** full lifecycle (scheduled → boarding → departing → enRoute →
  arriving → turnaround → ready; disruption branches: delayed, cancelled,
  diverted). Punctuality/cancellations feed reputation; delays cascade
  through an aircraft's day (the reason schedule padding is a real decision).
- **Decisions:** implicit via scheduling tightness, spare-aircraft policy,
  and disruption responses (swap aircraft, cancel, compensate).

### 4.7 Passengers & demand
- **Purpose:** the market being served; the system every other system feeds.
- **Mechanics:** per-market (city-pair) daily demand pools split
  business/leisure, from demographics × season × economy × events ×
  stimulation (service/frequency can grow a market slightly). Airlines'
  offers on a market split the pool by attractiveness: price vs. reference
  fare, schedule quality, reputation, comfort, punctuality. Unserved demand
  partially spills to connections via hubs, else evaporates.
- **Decisions:** which demand to chase (thin business routes vs. dense
  leisure trunks), stimulate vs. skim.

### 4.8 Pricing
- **Purpose:** the sharpest strategic dial; where positioning becomes real.
- **Decisions:** per-route fare vs. a per-airline fare posture with route
  overrides (default: airline-level % posture + optional per-route override —
  micromanagement stays optional, pillar 5); cabin price ratios.
- **Mechanics:** price sensitivity differs by segment (leisure elastic,
  business less so); sustained low prices reposition brand perception
  (see 4.10); reference fares emerge from market distance/competition.

### 4.9 Finance
- **Purpose:** the survival system; makes ambition risky rather than free.
- **Decisions:** loans (size/term; rates scale with leverage & reputation),
  lease vs. buy mix, dividend/retention (late game), emergency measures
  (sale-leaseback, fleet fire-sale).
- **Mechanics:** full ledger with categories; monthly statements; credit
  rating from leverage + profitability history; missed obligations →
  administration (see failure, §5). Fuel is the volatile line item —
  hedging unlocks late as a capability.

### 4.10 Reputation & service quality
- **Purpose:** the long-memory system; converts operations into demand.
- **Mechanics:** multi-component, slow-moving: punctuality, service,
  comfort, reliability(cancellations/baggage), value perception. Components
  decay toward current performance (good history buys grace, not immunity).
  Reputation multiplies demand attractiveness and gates premium pricing;
  value perception ≠ luxury — a reliable cheap airline earns *value* renown.
- **Decisions:** service tier per cabin (catering/seat pitch/amenities cost
  per pax), compensation policy on disruptions, positioning consistency
  (premium prices with budget service backfires — the feedback loop is the
  game teaching positioning).

### 4.11 Competitors (AI)
- **Purpose:** pressure, drama, and a mirror — the world must contest every
  good idea.
- **Mechanics:** 4–8 AI airlines per world, same rules/commands as player,
  distinct personalities (aggressive LCC, legacy premium, regional
  specialist, opportunist, conservative flag carrier). They enter/exit
  markets, price-respond, grow hubs, get into trouble, and can fail
  (collapse = event + market opportunity).
- **Decisions (player-side):** fight (price war, frequency war), flank
  (secondary airports, niches), or cede.

### 4.12 Events & living world
- **Purpose:** exogenous texture + tests of resilience; stories.
- **Mechanics:** systemic where possible (fuel shocks, economic cycle turns,
  strikes brewing from low morale, weather by region/season, airport
  closures, tourism booms, competitor collapses). Events have warnings where
  fair (storm forecast ≈ a day ahead), durations, and end. Every event
  creates a decision (reroute? discount? ground?) — never a pure toll.
- **Cadence cap:** major events rate-limited; the baseline game must be
  readable (GAME_BALANCE §5).

### 4.13 Research / capabilities
- **Purpose:** directed long-term investment; unlocks that change *how* you
  play (pillar: no +2% towers).
- **Mechanics:** capability programs bought with money + time (not a
  separate currency): e.g. Efficient Ops (faster turnarounds), Revenue
  Management (advance-purchase fare split), Fuel Hedging, Codeshare-ready
  Ops (late-game network reach), Heavy Maintenance In-house. 2–3 active max.
- **Decisions:** sequencing capabilities against strategy.

### 4.14 Hubs
- **Purpose:** the mid-game transformation: from lines on a map to a *network*.
- **Mechanics:** designating a hub (investment + staff) unlocks connecting
  itineraries: spill demand flows through banked schedules, multiplying
  effective demand on spokes. Hub quality = slots + bank timing + terminal
  investment.
- **Decisions:** where, when, how many; bank structure vs. rolling hub.

### 4.15 Progression, achievements, missions
See `PROGRESSION.md`. Milestones gate systems (pillar 5); achievements
celebrate playstyles; missions = optional targeted challenges (e.g. "make
the island route profitable within 2 seasons") generated from world state.

### 4.16 Disasters & disruptions
Weather groundings, tech failures (reliability-driven), strikes
(morale-driven). **No fatal-crash simulation** — disruption drama without
tragedy theater; "incidents" stay operational (diversion, grounding,
inspection). This is a deliberate tone decision.

### 4.17 Seasonality & market cycles
Monthly demand multipliers per market profile (ski, summer-sun, city-break,
business-flat); world economy runs a slow multi-year cycle (boom → downturn)
telegraphed through indicators, shifting business demand and loan rates.
Strategy question each cycle: expand into the downturn (cheap aircraft,
weak competitors) or fortify?

## 5. Difficulty, failure, and recovery

- **Difficulty = scenario, not sliders mid-game:** starting cash/market,
  competitor aggressiveness, economic volatility. Presets: Founder (gentle),
  Entrepreneur (standard), Magnate (harsh), plus custom.
- **Failure states:** cash < 0 beyond overdraft → *administration*: forced
  restructuring mini-state (creditors take a cut, fleet trimmed, reputation
  scarred) — painful but playable **once per era**; a second collapse is
  game over (score screen + "what went wrong" trace, honoring pillar 3).
- **Recovery is designed, not accidental:** sale-leaseback, route triage
  view, emergency loan at punitive rates. Losing should teach, not delete.

## 6. Replayability

Seeded worlds; home-airport variety (each start is a different puzzle);
personality-mixed competitor casts; scenario presets ("Island nation",
"Deregulation era", "Oil crisis start"); achievements tied to playstyles;
determinism enables seed-sharing and self-imposed challenges.

## 7. Explicit non-goals (v1)

Cargo, alliances/codeshares (beyond the late capability hook), staff
individuals, real-world airline/airport licensing (fictional-but-plausible
world data), multiplayer, monetization mechanics that sell time or power.
Premium single-purchase posture; any monetization design lands Phase 22+
without violating the no-pay-for-power rule.

## 8. Tone & fiction

Plausible fictional Earth: real geography, fictional airline/airport names
derived from real cities (licensing safety; keeps the map emotionally real).
Optimistic-professional tone; aviation romance (liveries, tail numbers,
inaugural-flight moments) without simulationist jargon walls.
