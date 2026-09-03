# The fee economy — baseline (AE-040)

> Phase 0 and Phase 1 of AE-040. §1–§5 are READ from source on
> 2026-09-02 before anything was changed; §6 onward is MEASURED by
> `ae-fee-baseline`, a new headless executable that flies single routes
> through the real pipeline and reads the ledger back. Labels:
> READ (from code), MEASURED (numbers from the real engine), OBSERVED
> (seen in a decoded CI frame), TESTED, NOT VALIDATED.

## 1. Current model (READ)

Airport charges are content on `AirportSpec` (`airports.json`): a
`movementFee` (Money) and a `passengerFee` (Money) per airport. They are
charged in exactly one place, `FlightOpsSystem.arrive`, when a flight
lands:

```
fees = origin.movementFee
     + destination.movementFee
     + destination.passengerFee × flight.passengers
```

posted as one ledger transaction in category `.airportFees` and added to
`route.economicsThisMonth.feesCents`. That is the whole pipeline. There
is no landing fee distinct from the movement fee, no handling charge, no
slot rent, no parking, no per-aircraft-size term, no origin passenger
charge, and no monthly airport charge.

Facts about the charge, each READ from `FlightOpsSystem.arrive`:

- **Per one-way flight**, at arrival. A round trip pays every airport's
  movement fee twice (once as origin, once as destination) and each
  airport's passenger fee once, on the passengers landing there.
- **Independent of the aircraft.** A 68-seat turboprop and a 422-seat
  widebody pay the same movement fee at the same airport.
- **Independent of distance.** The fee is the same for an 80 km hop and a
  10,000 km sector.
- **Cancelled flights pay nothing** (they never arrive). Delayed flights
  pay the same as on-time ones.
- **Ferry flights pay movement fees** (both ends) and no passenger fee
  (they carry none). A ferry is a real flight with real costs.
- **Rival and player flights run the same code.** The only owner-dependent
  branches in `arrive` are the player's three capabilities (fuel hedging
  caps the fuel price at 105% of base; efficient turnarounds shorten the
  turnaround by 15%; the network operations centre is in dispatch, not
  arrival). None touches the fee line.

### The fee data (READ from `airports.json`, 94 airports)

| Runway class | Airports | Movement fee | Passenger fee |
| --- | --- | --- | --- |
| small | 1 (TOS) | $900 | $10 |
| medium | 5 | $900–$1,600 | $9–$17 |
| large | 45 | $1,000–$2,300 | $9–$26 |
| veryLarge | 43 | $1,200–$2,800 | $10–$28 |

The fee rises with airport size and region wealth: JFK $2,800 / $28,
LHR $2,600 / $27, CDG $2,500 / $26, MUC $2,200 / $23, ARN $1,400 / $18,
IST $1,700 / $15, the African and South Asian hubs $1,000–$1,300 / $9–$12.
The ratio between the most and least expensive movement fee is 3.1×; the
spread of passenger fees is 3.1× as well.

### The fare (READ from `DemandSystem.referenceFare`)

```
referenceFare = 35 + 0.085 × distanceKm      (dollars, one way)
```

The player's guided route sheet and the AI both open at the reference
fare (the AI at its archetype's factor: low-cost 0.85, premium 1.25,
regional 1.0, conservative 1.05, expansionist 0.95). So a 350 km flight
sells at about $65, an 1,100 km flight at about $129, a 3,000 km flight
at about $290, a 9,000 km flight at about $800.

## 2. Cost taxonomy (READ)

| Cost | Charged | Scales with | Ledger category | In route P&L? |
| --- | --- | --- | --- | --- |
| Movement fee, origin | per arrival | nothing (airport only) | airportFees | yes |
| Movement fee, destination | per arrival | nothing (airport only) | airportFees | yes |
| Passenger fee, destination | per arrival | passengers landed | airportFees | yes |
| Fuel | per arrival | burn/km × km × world fuel price | fuel | yes |
| Crew | per arrival | block hours × (cockpit × $180 + cabin × $45) | crewCosts | yes |
| Onboard service | per arrival | passengers × tier ($4 / $9 / $18) | passengerService | **no** |
| Maintenance check | when condition < 0.75 | 60 h × type rate × (1 + 0.045 × age) | maintenance | **no** |
| Lease | monthly per aircraft | type lease rate | leasePayment | no (airline) |
| Depreciation | monthly, book value only | 8%/yr of list | none (capital) | no |
| Payroll | monthly | $40k × aircraft + $15k × routes | salaries | no (airline) |
| Overhead | monthly | $150k | overhead | no (airline) |
| Loan interest | monthly | annuity | loanInterest | no (financing) |
| Slots | never | — | — | — (capacity only, no money) |
| Exceptional | fire sale haircut, lease penalty, administration write-off | — | aircraftSale / leasePenalty | no |

So the taxonomy asked for in the brief maps as: **fixed per flight** =
two movement fees; **per passenger** = the destination passenger fee and
the service cost; **per aircraft, periodic** = lease, payroll,
depreciation, maintenance checks; **per airport** = the two content
numbers; **slot related** = nothing; **fixed per route** = the $15k/month
payroll line, airline-level.

`Route.RouteMonthEconomics.directOperatingProfit` is **revenue − fuel −
fees − crew**. Maintenance and onboard service are real ledger costs the
route screen does not attribute to the route; the AI's profit estimator
(§3) does.

## 3. Data flow (READ)

```
airports.json ─► AirportSpec.movementFee / passengerFee
                       │
FlightOpsSystem.boarding: passengers = min(seats, remaining demand)
FlightOpsSystem.departure: ticketRevenue = fare × passengers ─► ledger, route.revenueCents
FlightOpsSystem.arrive:    fuel, fees, crew, service ─► ledger (4 categories)
                           fuel, fees, crew ─► route.economicsThisMonth
                       │
StatementRollupSystem (month boundary): ledger accumulators ─► MonthlyStatement
                       (operatingRevenue / operatingExpenses / financingCost / capital),
                       route.economicsThisMonth ─► economicsLastMonth
                       │
ReadModels: RouteCard.thisMonthBreakdown, RouteVerdict drivers
            (.fees(shareOfRevenue) fires when fees > 30% of revenue)
Competition / Finance screens: the statement's byCategory
                       │
CompetitorAISystem.airframeDayValue(basis:):
   .revenue  = min(entrant pool, seats × 2 × rotations) × referenceFare × factor   (shipped)
   .profit   = revenue − fuel − movement fees × flights − passenger fees × carried/2
               − crew − maintenancePerFlightHour × block hours − service         (withheld)
   retrench: closes the route with the worst economicsLastMonth.directOperatingProfit
```

Two different profit definitions exist in the same system:

- the **ledger / route** one: revenue − fuel − fees − crew (per route),
  with maintenance, service, lease, payroll and overhead at airline level;
- the **estimator** one: revenue − fuel − fees − crew − maintenance
  (charged per block hour at the type's full rate) − service.

## 4. Existing assumptions (READ)

1. **A movement costs the same whatever lands.** The content has one
   number per airport. `docs/GAME_BALANCE.md` §4 anchors "airport /
   handling ≈ ¤3.2k per flight" for a 180-seat narrowbody at 78% load;
   that figure at the anchor fixture's $1,400 / $16 works out to
   $1,400 + $1,400 + $16 × 140 = **$5,040**, 58% above its own anchor —
   the fixture was never reconciled to §4, only required to be
   profitable (`anchorRouteIsProfitableAtReferenceFare`).
2. **Passengers pay at arrival only.** One passenger charge per segment,
   at the destination. Symmetric over a round trip.
3. **The fare is linear in distance with a $35 base.** Short routes sell
   for little; the base covers a $35 floor at zero distance.
4. **Maintenance is a periodic check, not a per-hour charge.** Condition
   falls 0.0006/day plus 0.00035 per flight hour; a check at 0.75 costs
   60 hours' worth of the type's `maintenancePerFlightHour`. The
   estimator charges the full per-hour rate every hour.
5. **Rivals and the player share every formula.** Asserted structurally
   (`aiPlaysByPlayerRules`) and READ in `arrive`.
6. **The regional archetype's fare factor is 1.0, its fleet turboprops
   then regional jets, its geography the home region, its starter the
   cheapest preferred type bought used at twelve years** (NA-70 Fjord,
   68 seats, 1,450 km, $620/h maintenance, 2.05 kg/km).
7. **The route verdict flags fees above 30% of revenue** as the dominant
   driver of a loss.

## 5. Known evidence (as previously recorded, not reinterpreted)

| Evidence | Label | Where |
| --- | --- | --- |
| SwiftJet's JFK–ORD (68-seat turboprops, 1,180 km) lost about $277k a month at 100% load | MEASURED (AE-039) | tasks/BUGS.md "Finding — New York's arrival" |
| SwiftJet's ORD–YYZ lost about $953k a month | MEASURED (AE-039) | tasks/TECH_DEBT.md TD-029 |
| KEY-48 (run 122): LHR–CDG, 347 km, "Losing money — airport fees take 96% of the revenue", −$17k so far, −$94k last month, 100% load, 2×/day, one narrowbody | OBSERVED | docs/HORIZON_AUDIT.md §8 |
| Under the profit basis SwiftJet has zero viable candidates from any home it can reach | MEASURED (AE-039, `ae-rival-scan --profit --horizon`) | docs/HORIZON_AUDIT.md §4 |
| Under the profit basis three of fifteen archetype runs cross the 60% margin line (64–65%) | MEASURED (AE-039, `BalanceTests`) | TD-030 |
| The anchor route (MET–COS, 1,100 km, MR180, 2×/day, $129) has positive direct operating profit | TESTED | `FinanceTests.routePnLBreakdownIsExplainable` |
| The estimator on ARN–LHR estimates $52.6k/day against $65.8k/day booked at two rotations (80%) | TESTED (AE-039) | `AirframeDayProfitTests` |
| Contested anchor-market margins stay under 25%; archetype margins under 60%; ten-year world stable | TESTED | `BalanceTests` |

## 6. The route battery (MEASURED, `ae-fee-baseline`)

`swift run -c release ae-fee-baseline --csv --rotations 2 --months 12`
and the same at `--rotations max`. One airline, one leased airframe, one
route at the reference fare, seed 2039, a January ramp and then twelve
months averaged; every figure is the ledger's. Fuel averaged $628/t.
Runs took under a second each. Widebodies are era-locked for a player
airline, so the long-haul rows come from `--ai premium` (same code path,
§7). Full CSVs: the session scratchpad (`fee-2-year.csv`,
`fee-max-year.csv`); the tables below are the same numbers.

### 6.1 Two rotations a day (the AI's opening frequency), average month

| Route | km | Type | Seats | Load | Revenue | Fees | Fees / revenue | Fees / direct costs | Fuel | Crew | Service | Maint. | Lease | Direct profit | All-in margin |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| LHR–CDG | 347 | NA70 | 68 | 100% | $504k | $793k | **157%** | 88% | $53k | $53k | $70k | $10k | $175k | −$394k | −170% |
| LHR–CDG | 347 | AV90 | 88 | 100% | $657k | $860k | 131% | 88% | $74k | $43k | $92k | $8k | $315k | −$320k | −143% |
| LHR–CDG | 347 | MR180 | 180 | 100% | $1.35M | $1.15M | 85% | 89% | $88k | $51k | $189k | $10k | $740k | +$64k | −80% |
| JFK–BOS | 300 | NA70 | 68 | 100% | $475k | $789k | **166%** | 89% | $46k | $48k | $71k | $6k | $175k | −$408k | −182% |
| JFK–BOS | 300 | MR180 | 180 | 100% | $1.27M | $1.13M | 89% | 90% | $76k | $46k | $188k | $10k | $740k | +$17k | −89% |
| MUC–VIE | 355 | NA70 | 68 | 100% | $509k | $627k | 123% | 86% | $54k | $53k | $70k | $10k | $175k | −$226k | −135% |
| CDG–AMS | 399 | NA70 | 68 | 100% | $535k | $758k | 142% | 87% | $61k | $57k | $70k | $10k | $175k | −$341k | −149% |
| ARN–HEL | 398 | NA70 | 68 | 100% | $535k | $441k | 82% | 79% | $60k | $57k | $70k | $10k | $175k | −$24k | −90% |
| ARN–GOT | 394 | NA70 | 68 | 98% | $524k | $393k | 75% | 77% | $60k | $57k | $69k | $10k | $175k | +$14k | −85% |
| IST–ATH | 552 | NA70 | 68 | 100% | $637k | $482k | 76% | 76% | $84k | $74k | $70k | $10k | $175k | −$3k | −73% |
| ORD–YYZ | 700 | NA70 | 68 | 100% | $723k | $709k | 98% | 79% | $105k | $87k | $69k | $13k | $175k | −$177k | −88% |
| ORD–YYZ | 700 | MR180 | 180 | 100% | $1.93M | $1.01M | 52% | 81% | $172k | $78k | $184k | $15k | $740k | +$668k | −25% |
| CGK–SIN | 884 | NA70 | 68 | 100% | $830k | $553k | 67% | 71% | $130k | $104k | $68k | $16k | $175k | +$43k | −51% |
| CGK–SIN | 884 | MR180 | 180 | 100% | $2.28M | $800k | 35% | 72% | $221k | $93k | $187k | $15k | $740k | +$1.17M | +1% |
| BCN–LHR | 1,147 | NA70 | 68 | 100% | $998k | $657k | 66% | 69% | $169k | $130k | $68k | $19k | $175k | +$43k | −42% |
| BCN–LHR | 1,147 | MR180 | 180 | 100% | $2.71M | $961k | 35% | 71% | $283k | $113k | $184k | $20k | $740k | +$1.36M | +8% |
| JFK–ORD | 1,187 | NA70 | 68 | 100% | $1.02M | $771k | 75% | 72% | $175k | $134k | $68k | $19k | $175k | −$57k | −51% |
| JFK–ORD | 1,187 | AV90 | 88 | 100% | $1.34M | $836k | 63% | 71% | $245k | $98k | $88k | $16k | $315k | +$157k | −35% |
| JFK–ORD | 1,187 | MR180 | 180 | 100% | $2.76M | $1.11M | 40% | 74% | $290k | $115k | $183k | $20k | $740k | +$1.24M | +3% |
| ARN–LHR | 1,462 | MR180 | 180 | 100% | $3.22M | $905k | 28% | 65% | $356k | $136k | $182k | $24k | $740k | +$1.83M | +21% |
| MUC–IST | 1,547 | MR180 | 180 | 100% | $3.37M | $824k | 24% | 62% | $377k | $144k | $182k | $24k | $740k | +$2.03M | +26% |
| JFK–LAX | 3,974 | MR180 (1×) | 180 | 100% | $3.73M | $560k | 15% | 47% | $479k | $165k | $90k | $29k | $740k | +$2.53M | +39% |
| SIN–HND | 5,299 | MR180 (1×) | 180 | 100% | $4.77M | $509k | 11% | 38% | $628k | $212k | $88k | $34k | $740k | +$3.42M | +49% |
| LHR–JFK | 5,541 | MR300 (1×, AI) | 298 | 100% | $6.94M | $625k | 9% | 32% | $1.07M | $280k | $247k | $115k | $2.0M | +$4.96M | +34% |
| TOS–ARN | 1,116 | NA70 | 68 | 21% | $205k | $275k | 134% | 49% | $164k | $127k | $14k | $19k | $175k | −$361k | −378% |

"Direct profit" is the route screen's number (revenue − fuel − fees −
crew). "All-in margin" also takes service, maintenance, the lease, payroll
($55k) and overhead ($150k) — the airline's whole month on one route.

### 6.2 Maximum rotations the operating day allows, average month

| Route | km | Type | Rot./day | Load | Revenue | Fees | Fees / revenue | Direct profit | All-in margin |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| LHR–CDG | 347 | NA70 | 5 | 100% | $1.10M | $1.72M | 157% | −$857k | −128% |
| LHR–CDG | 347 | MR180 | 6 | 100% | $3.81M | $3.24M | 85% | +$180k | −35% |
| JFK–BOS | 300 | NA70 | 6 | 100% | $1.30M | $2.15M | 166% | −$1.11M | −132% |
| JFK–BOS | 300 | MR180 | 6 | 100% | $3.32M | $2.96M | 89% | +$45k | −42% |
| CDG–AMS | 399 | MR180 | 6 | 100% | $3.26M | $2.49M | 76% | +$411k | −30% |
| ARN–HEL | 398 | NA70 | 5 | 70% | $827k | $885k | 107% | −$318k | −99% |
| ORD–YYZ | 700 | NA70 | 4 | 100% | $1.26M | $1.24M | 98% | −$309k | −66% |
| ORD–YYZ | 700 | MR180 | 4 | 100% | $3.75M | $1.97M | 52% | +$1.29M | −1% |
| CGK–SIN | 884 | MR180 | 4 | 100% | $3.92M | $1.38M | 35% | +$2.01M | +18% |
| JFK–ORD | 1,187 | AV90 | 3 | 100% | $1.93M | $1.21M | 63% | +$227k | −23% |
| JFK–ORD | 1,187 | MR180 | 3 | 100% | $4.04M | $1.63M | 40% | +$1.82M | +14% |
| ARN–LHR | 1,462 | AV90 | 3 | 100% | $1.96M | $836k | 43% | +$601k | −3% |
| ARN–LHR | 1,462 | MR180 | 3 | 100% | $4.02M | $1.13M | 28% | +$2.27M | +27% |
| MUC–IST | 1,547 | MR180 | 3 | 100% | $4.21M | $1.03M | 24% | +$2.53M | +32% |
| IST–ATH | 552 | MR180 | 5 | 100% | $3.72M | $1.49M | 40% | +$1.78M | +11% |

Flying the aircraft harder does not change the fee share — it is a
per-flight ratio — and a full schedule loses 6–25% of its rotations to
delay cascades and expiry (a tight day at LHR–CDG flew 249 of 280
scheduled NA70 flights), which is a separate finding (§8).

### 6.3 What the numbers say

1. **Fees are the largest direct cost on every route under 1,600 km,
   for every aircraft.** 62–90% of fuel + fees + crew at short and medium
   range; 38–47% at 4,000–5,500 km. Fuel, the cost the design doc expects
   to lead (25–35% of operating cost), is 4–12% of revenue on the short
   routes.
2. **The fee share is a per-flight ratio, and it is worst for the
   smallest aircraft.** On the same pair the 68-seat turboprop's fee share
   is 1.7–1.9× the 180-seat narrowbody's (LHR–CDG 157% vs 85%; JFK–ORD
   75% vs 40%; ORD–YYZ 98% vs 52%), because the two movement fees are the
   same money spread over 68 seats instead of 180. Split the fee: on
   JFK–ORD the NA70 pays $551k a month in movement fees and $187k in
   passenger fees; the MR180 pays $551k and $496k. Per seat flown the
   turboprop's movement fee is 2.65× the narrowbody's.
3. **The turboprop has no route in the battery that pays for itself.**
   Direct profit is at best +$43k a month (CGK–SIN, BCN–LHR) and after
   service, maintenance and the lease every NA70 row is negative
   (−42% to −378%). The regional jet clears its lease only on JFK–ORD at
   three rotations and ARN–LHR/MUC–IST at three. The narrowbody clears
   everything from about 900 km up.
4. **Short haul is fee-bound for everyone.** Under 400 km, even the
   narrowbody's fees are 66–89% of revenue at 100% load, because the
   destination passenger fee alone ($26–28 at LHR, CDG, JFK) is 40–45%
   of a $60–69 fare, before the two movement fees.
5. **Long haul is fee-light.** 9–15% of revenue at 4,000–5,500 km; a
   widebody at 34–36% all-in margin.
6. **Load is not the problem.** Every losing short route above is at
   100% load. The three Nordic pairs (ARN–HEL, ARN–GOT, TOS–ARN) are
   demand-limited as well, and their fees exceed revenue too.

### 6.4 The reference route, line by line (MEASURED against the design)

`docs/GAME_BALANCE.md` §4 gives the per-flight P&L the economy was to be
tuned against: a 180-seat narrowbody, 1,100 km, 78% load (140 pax), fare
$129, revenue ≈ $18.1k. The anchor fixture (`DemandFixtures`, fees
$1,400 / $16) flown at the reference fare gives per one-way flight:

| Line | Design anchor | Game (anchor fixture, per flight) | Ratio |
| --- | ---: | ---: | ---: |
| Revenue | $18.1k | $18.1k (140 × $129) | 1.0 |
| Fuel | $4.9k (27%) | $2.4k (3.35 kg/km × 1,100 km × $0.65) | 0.49 |
| Crew | $2.3k | $1.0k (1.64 h × $585) | 0.42 |
| Airport / handling | $3.2k | **$5.0k** ($1,400 + $1,400 + 140 × $16) | **1.58** |
| Maintenance reserve | $2.4k | ≈ $0.2k (a 60-hour check every ~630 flight hours) | 0.1 |
| Ownership | $3.1k | $6.2k ($740k lease over 120 flights) | 2.0 |
| Overhead share | $1.3k | $1.7k | 1.3 |
| **Total cost** | **$17.2k** | **$16.5k** | 0.96 |
| Operating margin | ~5% | ~9% | — |

The total lands near the design and the composition does not: fees
carry 1.6× their designed weight, ownership 2×, while fuel, crew and
maintenance carry a half, a half and a tenth. The anchor test only
requires a positive result, so nothing ever compared the lines. On the
real network the fee weight is heavier still — LHR, CDG and JFK charge
$2,500–$2,800 per movement against the fixture's $1,400.

## 7. Player parity (MEASURED)

`--ai regional` founds the airline as an AI of that archetype (the
competitor system removed from the pipeline so it cannot add routes) and
flies the same schedule. Every line of every route came back identical
to the player run, to the cent: LHR–CDG NA70 revenue $474k / fees $745k
/ fuel $48k / crew $49k, ARN–LHR MR180 $3.07M / $861k / $329k / $129k,
JFK–ORD NA70 $980k / $739k / $162k / $128k. The fee code has no owner
branch; the only player-only branches in the flight system are the three
capability perks (fuel hedging, efficient turnarounds, network operations
centre), none of which a new airline holds. **A player opening a
turboprop route at a hub pays exactly what SwiftJet pays**, and the route
sheet that offers the route says nothing about fees.

## 8. Findings beside the question (MEASURED, not acted on here)

- **Widebodies are era-locked for the player** (`progression.lockedCategory`)
  and not for AI airlines: the premium archetype leased an MR300 on day one.
  The design says AI plays by player rules; progression locks are the
  documented exception.
- **No aircraft can fly a round trip longer than about 8 hours one way**:
  the scheduler needs the whole round trip inside an 18-hour operating
  day, so LHR–SIN (10,900 km) has zero rotations for every type in the
  catalog. Very-long-haul is unreachable, not unprofitable.
- **A full schedule loses rotations to cascades.** At the operating day's
  maximum, 6–25% of scheduled flights did not fly (delay → next leg
  cannot board → expiry after four hours cancels it). At two rotations
  the loss is 5–10%.
- **The demand forecast under-reads thin Nordic pairs** at the AI's
  viability floor: ARN–GOT forecast 136 passengers a day (below the
  140 floor) against 249 carried at 98% load; ARN–HEL 163 against 262.
