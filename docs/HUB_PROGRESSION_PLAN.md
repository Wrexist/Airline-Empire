# Hub progression — the plan for step 2

> Written 2026-10-09 for the owner, after step 1 (upgrading the lounge and
> ground services from inside the 3D hub, `HUB_HANDOFF.md` §0c) shipped on
> `claude/kind-bardeen-ajulsw`. This is the plan for **new hub buildings**:
> what to build, in what order, and how to make the player *feel* their
> airline grow at each airport. Decisions the owner must take are collected
> in §9. Nothing here is built yet.

---

## 1. What we are aiming for

The owner's words: user experience, immersion, and that players *feel the
progression*. Judged against `GAME_DIRECTION.md` and `PROGRESSION.md`, that
means:

| Principle | Where it comes from | What it asks of every building |
|---|---|---|
| **Growth you can watch** | GAME_DIRECTION §1 (cozy builder) | Every purchase visibly changes the hub, and keeps changing it while it is built. |
| **Capability, not numbers** | PROGRESSION §1, §6 ("no bigger number, same decision") | Each building is a *rule change* or a *new decision*, never a bare +x %. |
| **Earned, telegraphed unlocks** | PROGRESSION §2 | Gated by era (demonstrated competence) and shown ahead of time ("2 of 3 met"). |
| **Nothing punishes absence** | GAME_DIRECTION §5 | Construction keeps going while the app is closed; nothing expires; no paid speed-ups. |
| **Always a pressable next step** | GAME_DIRECTION §5 (BUG-059) | The hub always says what to build next and why, with the button right there. |
| **The four pulls** | GAME_DIRECTION §2 | Each building serves map-painting, eras, net worth or goals — and the hub as a whole serves all four. |
| **No pay-to-win** | `ContentAccess.swift`, `PaywallContent.swift` | No money-for-time skips. Pro only matters through the existing era ceiling. |

## 2. What the simulation has today

The plan's effects plug into these mechanics:

- **Facilities:** two services, lounge and ground services, levels 0–2. They take effect at once.
  - Lounge: +4 comfort points per level, which adds at most +0.024 to the demand comfort term. It does not feed comfort reputation.
  - Ground services: −10 % technical disruption per level on departures. It does nothing against storms.
  - Price: $100–150k to build and $10–15k a month per level. That is about 0.2 % of a $35–90M starting balance, so it is a trivial purchase.
- **Maintenance:** every check takes 3 days at any airport (`FleetSystem.swift:41-53`), and the aircraft's location is never read.
  - A check that starts during the day leaves that day's flights scheduled. They cannot board, so they are cancelled and reliability reputation suffers.
- **Turnaround:** comes from the aircraft type alone.
  - The scheduler counts rotations from the spec turnaround (`FlightSchedulingSystem.swift:28`). So the *Efficient Turnarounds* programme only adds slack; it never adds a rotation. This is a gap against `PROGRESSION.md:129`.
- **Operating day:** 06:00 + 18 h for everyone. There is no crew base and no per-airport crew or fuel factor.
- **Slots:** a shared first-come pool per airport. There is no purchase, trade or expansion.
- **Terminal capacity:** has **no** simulation effect today. It only drives the hub KPI and alert.
- **Demand:** point-to-point only. There is no connecting traffic and no home-airport effect. Hub connections were descoped in D-010 and remain the planned headline update (`EXPANSION_ROADMAP.md` item 1, `GAME_DESIGN.md` §4.14).
- **Delayed-completion patterns already exist:**
  - Capability programmes: `startedAt`/`completesAt`, paid up front, completed daily.
  - Aircraft orders: delivered on a date.
- **Free tier:** the era ceiling is **Regional**. Free players never reach National-era systems. The facility command is not gated.
- **Game Center:** its achievement points already total 1,000, Apple's ceiling. New hub achievements mean re-pointing existing ones.
- **No facility events** exist; only a generic `commandApplied` is emitted.

## 3. The spine: hub status — an airport that grows with you

The single strongest progression device is **an identity for each hub that
levels up as you build it**. It is a recognition with unlocks attached, not
XP: the status is *derived* from what you built and fly, never bought.

| Status | How you earn it | What changes in the world | What it unlocks |
|---|---|---|---|
| **Station** | You fly here | Your jets visit; plain airport signage | Lounge, ground services (exist) |
| **Base** | Home airport, or 3 aircraft overnighting here + one building | Your logo on the terminal, liveried ground fleet | Maintenance hangar, crew base |
| **Hub** *(Era III)* | Hub designated (Transfer centre built) | Hub banner, your pier painted in livery, departure banks | Dedicated pier, terminal wing, transfer flows |
| **Gateway** *(Era IV)* | Hub + 2 world regions served from it + terminal wing | Wing in your colours, long-haul jets at your gates, night signage | Fuel farm, hotel, rail link |
| **Flagship** *(Era V)* | Home hub with every building at top level | Lit rooftop sign, HQ tower in the district, fireworks moment | Prestige projects |

Each step up is a **moment**:
- a camera fly-over
- a banner unveiling
- a record entry in `ProgressionState.record`
- a line in the session report: "Stockholm is now a Gateway"

The hub card always shows the next status and its requirements, with ticks ("Gateway: 2 of 3 — build a terminal wing"). The map gets a status badge on the airport, so painting the map includes "how built-up is each of my hubs".

## 4. The building roster

Every building:
- has a **site** in the diorama, visible from day one as a plot (§6)
- is built **over game time**
- shows the **same card** as step 1, plus a payoff estimate
- has a **level-specific look**

Prices are proposals scaled to the economy: starting cash is $35–90M and a good narrowbody route makes $0.5–1.8M a month. The balance battery tunes them before shipping (§8).

| # | Building | Era | Rule change (the decision it creates) | Hooks into | Look in the hub | Proposed price · upkeep · build time |
|---|---|---|---|---|---|---|
| 1 | **Lounge** (exists) | I | Comfort at this airport; propose it also feeds comfort reputation | `DemandSystem:205`, `ReputationSystem:41` | Roof pavilion → flagship (done) | Re-price (§9) |
| 2 | **Ground crew depot** (exists) | I | Fewer technical disruptions on departures here | `FlightOpsSystem:62` | Depot lot → electric fleet (done) | Re-price (§9) |
| 3 | **Maintenance hangar** L1 · L2 | II | *Where* your jets get serviced. Aircraft flying through this hub: <br>• start checks after the day's last flight, so no mid-day cancellations <br>• take 2 days (L1) or 1 day (L2) instead of 3 <br>• L2 costs 30 % less ("in-house heavy maintenance", PROGRESSION §4) | `FleetSystem:41-53`; schedule order | Hangar in your livery; **your actual jet in the bay during its check** | $8M · $120k/mo · 30 d → $20M · $250k/mo · 60 d |
| 4 | **Crew base** | II | A longer operating day for routes from here: 05:00–01:00 instead of 06:00–24:00, so **more rotations per aircraft**. Payroll rises; schedule choices change. | Scheduler window (`ContentCatalog:476`) | Crew hotel in the district, crew bus looping to the terminal | $4M · $90k/mo · 21 d |
| 5 | **Dedicated pier** L1 · L2 | III | Your own gates:<br>• slots *reserved for you* beyond the shared pool (4 then 8 movements a day), the answer to congested hubs (GAME_DESIGN §4: "paying up for congested hub slots")<br>• a shorter effective turnaround here, **used by the scheduler**, so it adds rotations | `WorldState.allocateSlots`, scheduler | A pier painted in your livery, your jets at branded jet bridges, your gate signs | $30M · $250k/mo · 90 d → $45M · $350k/mo · 120 d |
| 6 | **Transfer centre** (hub designation) | III | **Connecting passengers**: unserved demand A→C flows through this hub when your schedule connects A→B→C (the spill term reserved in D-010). The mid-game transformation from lines to a network. | `DemandSystem` pool split (new spill term), conservation tests | Transfer hall in the terminal cutaway with passengers walking pier to pier; departure **banks** visible as waves of jets | $25M · $200k/mo · 60 d |
| 7 | **Terminal wing** T1–T3 | III–IV | Brings in a **new pressure and its answer**: terminal load above 85 % starts to cost comfort for everyone; your wing exempts your passengers and adds comfort. A decision at busy hubs. | `HubSnapshot` load becomes a demand term | The terminal visibly lengthens, with your branding and more stands | $40M / $80M / $140M · 90–180 d |
| 8 | **Fuel farm** | IV | **Storage you fill**: buy fuel into your tanks at today's price, and departures from this hub draw it at the fill price. Cycle play against fuel shocks, a decision rather than a discount. Nothing expires. | `FlightOpsSystem:194` fuel bill | Tanks in your livery with **visible fill levels** | $10M · $60k/mo · 45 d (+ fills) |
| 9 | **Hotel** | IV | A steady income from hub passengers and layovers, and a cozy money-maker | `EconomySystem` monthly | Tower by the terminal, lit at night | $18M · income · 120 d |
| 10 | **Rail link** | IV | Air–rail itineraries: a nearby city without its own service feeds your routes here. Reuses the spill term from #6. | Demand spill | Station, trains arriving, people walking in | $35M · $150k/mo · 180 d |
| 11 | **Airline HQ / prestige** | V | Expression and status: the Flagship status requirement; landmark on the map. Light effect only (e.g. a service reputation floor). | Progression record, map | HQ tower in the district, rooftop sign | $120M · 365 d |
| 12 | **Cargo terminal** | — | Waits for the cargo expansion (roadmap year 2; `cargoIndex` is reserved) | — | Cargo sheds already exist as scenery | Later |

A note on 3, 4 and 5: they turn today's quiet frustrations into decisions. Mid-day cancellations from checks, an operating day you cannot stretch, and full slot pools at busy hubs all become things the player can act on.

## 5. Priorities

Ranked by **player value × how much progression it makes you feel ÷ engine
risk**. Most players are free, capped at the Regional era, so the first
wave must work for them.

| Priority | Phase | What | Why first | Size |
|---|---|---|---|---|
| **P0** | **A. The progression frame** | Build-over-time, construction stages, ceremonies, hub status, next-step card, locked plots, blueprint preview, hub history | It makes *every* building feel like progression, including the two that exist. It reuses step 1 almost entirely. | 1 PR, medium |
| **P1** | **B. Maintenance hangar** | #3 | It fixes a real pain (checks cancelling flights), it is free-tier, and seeing your own jet in your own hangar is a top immersion moment | 1 PR, medium |
| **P1** | **C. Crew base** | #4 | More rotations is a felt, free-tier gain; it adds a district building | 1 PR, small–medium |
| **P2** | **D. Dedicated pier** | #5 (and fixing the turnaround scheduling gap) | The first National-era hub building; it answers slot congestion | 1 PR, medium |
| **P2** | **E. Hub designation + transfer centre** | #6 | The design's headline mid-game beat; biggest gameplay change | Epic, 2–3 PRs, large |
| **P3** | **F. Terminal wing** | #7 | Needs care to balance as a new pressure; best after E | 1 PR, medium |
| **P3** | **G. Fuel farm, hotel** | #8, #9 | International-era depth and income | 2 PRs, small–medium each |
| **P4** | **H. Rail link, HQ / prestige** | #10, #11 | Late game; the rail link reuses E's spill term | 2 PRs |
| Later | Cargo terminal | #12 | With the cargo expansion | — |

## 6. The experience, beat by beat

This is what makes it *feel* like progression. Every phase must deliver all of it for its building.

1. **Anticipation — see the future.**
   - From the first visit, the hub shows every future site as a plot with a board: "Maintenance hangar — Regional era".
   - Locked plots carry the era badge and requirement, so players know what is coming.
   - They are greyed out and never nag.
   - The card's **blueprint preview** shows the next level as a translucent hologram on the site before you buy.
2. **Clear payoff.**
   - The card quotes the payoff in player terms, from the simulation's own estimators (the `AirportInvestmentPreview` approach). For example:
     - "Last month 14 flights were cancelled by mid-day checks on aircraft that pass through ARN. A hangar would have saved them."
     - "+2 rotations a day across your 6 aircraft here."
   - When no honest number exists, it says so.
3. **Commitment — a moment to order it.**
   - Build then Confirm, as in step 1, with the build time stated ("Opens in 30 days, around 14 March").
4. **Construction you can follow.** Stages tied to progress, persistent across sessions:
   1. Hoarding with your logo
   2. Diggers and trucks
   3. Crane and frame
   4. Cladding
   5. Reveal

   The tag shows "Crane up · 40 % · opens in 18 days". Workers and trucks animate on site. Coming back after time away, a "while you were away" note leads with construction news.
5. **Ceremony.** When it opens:
   - The camera flies to it, the hoarding drops, a pulse and a chime play, and a toast confirms it.
   - It goes into the progression record and the session report.
   - On a hub status change, the banner unveils too.
   - Ceremonies that finished while you were away play once the next time you open the hub, and can be skipped.
6. **Living proof.** Buildings *show* themselves working:
   - jets in the hangar bay during checks
   - crew buses at dawn
   - fill levels in the fuel tanks
   - transfer passengers between piers
   - departure banks

   Insights gains a **Hub report**: what each building did this month (checks shortened, cancellations avoided, rotations added, connecting passengers).
7. **The hub's own story.** A **hub timeline** ("ARN: first route 2027 · lounge 2028 · hangar 2029 · Hub 2030 · Gateway 2032"), built from the facility history that already exists, makes coming back to an old hub a cozy look back.
8. **Next step, always.** The hub card ends with the next sensible build and why ("Next: crew base — 6 of your 8 aircraft here run fewer than 4 rotations"). Its button is right there.

Audio: a construction ambience bed on the site while visible, a completion chime, and a status fanfare. The audio system already exists (~58 cues).

## 7. Technical shape

Following `ARCHITECTURE.md` §12: new system + state slice + content + commands/events.

- **State.** `Airline.hubBuildings: [AirportCode: [HubBuilding]]`, optional and Codable, so old saves decode with no migration (the facilities precedent).
  - `HubBuilding { kind, level, status: built | underConstruction(startedAt, completesAt) }`.
  - Lounge and ground services can move under it later, or stay where they are and be presented the same way.
- **Content.** `HubBuildingTuning` in `tuning.json`, per kind and level:
  - price
  - upkeep
  - build days, scaled by airport size class
  - era gate
  - effect parameters

  It is validated on load, with defaults for old bundles.
- **Command.** `BuildHubBuildingCommand`, with the same validation shape as `ConfigureAirportFacilitiesCommand`:
  - presence
  - open airport
  - cash
  - era (respects `progressionCeiling`)
  - one construction per site

  It pays up front and records history.
- **System.** `HubBuildingSystem`, run daily:
  - completes constructions and emits `.hubBuildingCompleted`
  - derives hub status and emits `.hubStatusRaised`
  - bills upkeep monthly through `EconomySystem`
- **Effects.** Each effect lives *inside the owning system*, like capability programmes:
  - hangar → `FleetSystem`
  - crew base and pier turnaround → `FlightSchedulingSystem`
  - reserved slots → `WorldState`
  - spill → `DemandSystem`
  - fuel farm → `FlightOpsSystem`
- **Read model.** `HubUpgradeOffer` (step 1) generalises to any building. It adds:
  - era lock and requirement text
  - construction progress
  - payoff estimate
  - stage

  The diorama site list grows by kind (`HubLayout.facilitySites`).
- **Determinism.** Everything is daily and seeded. The determinism and save/continue suites must stay green.
- **AI.** The engine stays symmetric (commands take an `AirlineID`). AI investment strategy is a later phase. When it comes, rival hangars at rival hubs are good competition you can *see*.

## 8. Quality bar per phase

Each phase is one PR, closed like the hub work so far:
- Core tests for the rule change, including the edge cases: a check starting at the hub versus elsewhere, saves mid-construction, and catch-up across a completion.
- **Balance battery** scenarios before and after. The target payback for efficiency buildings is 18–36 months at a typical hub; prestige buildings have none. There must be no money-printer: net worth stays under the $300M guard in 4 years.
- The release build with warnings as errors, and the full Core suite.
- `Hub view review` captures of the site at every stage and the ceremony, on iPad and iPhone.
- An update to `HUB_HANDOFF.md`.

## 9. Decisions for the owner

1. **Roster and order.** Approve §4 and §5, or reorder. Recommended: Phase A next, then the hangar and crew base.
2. **Build time.** New buildings take game days (recommended).
   - Should the lounge and depot also take time, briefly (7 and 14 days)? Recommended, for one consistent feel.
3. **Prices.** Accept the §4 bands as starting points for the battery.
   - Re-price the lounge and depot? Today they cost about 0.2 % of starting cash. Recommended: ×10, with upkeep ×5.
4. **Free versus Pro.** Recommended: everything up to the Regional era is free (lounge, depot, hangar, crew base, hub status up to Base). National-era buildings follow the existing era ceiling, so they are naturally Pro. There are no paid speed-ups, ever.
5. **Terminal congestion as a new pressure (#7).** Yes or no? It gives terminal capacity a real effect for everyone.
6. **Hub connections (#6).** Confirm it is in scope as the headline of this work.
7. **Lounge feeding comfort reputation.** Small balance change. Yes or no?
8. **Hub achievements.** Game Center is at its 1,000-point ceiling. Re-point to add 2–3 hub achievements (e.g. *Gateway*, *Fully built*), or keep hub moments in-game only?

## 10. Findings from the research, independent of this plan

These are worth fixing whatever is decided:

- **The *Efficient Turnarounds* programme never adds a rotation.** The scheduler uses the spec turnaround (`FlightSchedulingSystem.swift:28, 83, 100`). It only adds slack.
- **Maintenance checks cancel that day's flights.** The check starts after the day's flights exist (`FleetSystem` runs after `FlightSchedulingSystem`). Those flights fail to board and expire as cancellations, which hurts reliability reputation. A general fix would start checks at the end of the operating day. The hangar would then make checks shorter, not merely tidier.
- **Passenger fees** are documented as per departing passenger (`AirportSpec.swift:22`) but charged at the destination (`FlightOpsSystem.swift:215`).
- A misplaced comment at `EconomySystem.swift:29` ("Loan service" above facility billing).
