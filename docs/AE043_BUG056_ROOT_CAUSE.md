# AE-043 — BUG-056, reproduced and root-caused

Written after the pipeline read (docs/AE043_AIRCRAFT_SELECTION_BASELINE.md)
and before any production change. Facts are separated by how they were
obtained. The design comparison is in
docs/AE043_AIRCRAFT_SELECTION_DECISION.md.

## 1. Method

`ae-advice market` (new mode this phase) reproduces the shipped market's own
ordering rather than a convenient abstraction of it:

```swift
let rows = catalog.orderedAircraftTypeCodes
    .compactMap { catalog.aircraftTypes[$0] }
    .sorted { $0.seats > $1.seats }          // FleetView's default
let firstBuyable = rows.first { era.allowedCategories.contains($0.category) }
```

**This is a stricter model than AE-042 used, and it matters.** AE-042's
`--acquire biggest` chose the largest airframe *that can fly the route* — it
filtered by `routeEligibility` first. The shipped sheet has no route in scope
(baseline §7), so it cannot filter that way: it offers the largest era-legal
type, full stop. Modelling the real UI finds cases the earlier model could
not, and the count is worse than the one AE-042 reported. That correction is
in §3.

Held constant: scenario `entrepreneur`, seed 2030, day 0, the shipped catalog
and tuning at commit 71046d9. Economics are the shipped estimator
(`CompetitorAISystem.airframeDayValue`), the same one Core ranks on — no
second economy.

## 2. The reproduction (MEASURED)

Every home where Core names an airframe that pays and the market's first
buyable row does not:

| Home | Route | km | pax/day | Core names | Market row 1 (buyable) | Class |
| --- | --- | ---: | ---: | --- | --- | :---: |
| FRA | FRA–LHR | 653 | 1,720 | NA160, 162 seats, **+$17k**/mo | PA184 **−$158k** | A |
| HAM | HAM–LHR | 745 | 1,105 | KT95, 95 seats, **+$121k** | PA184 **−$168k** | A |
| DUB | DUB–CDG | 785 | 951 | KT95, 95 seats, **+$190k** | PA184 **−$386k** | A |
| **BLL** | BLL–LHR | 790 | 442 | KT72, 74 seats, **+$111k** | PA184 — **cannot fly it** | **D** |
| EDI | EDI–CDG | 869 | 719 | AV90, 88 seats, **+$322k** | PA184 **−$711k** | A |
| **NCE** | NCE–LHR | 1,041 | 691 | AV90, 88 seats, **+$387k** | PA184 — **cannot fly it** | **D** |
| **BGO** | BGO–LHR | 1,042 | 452 | KT72, 74 seats, **+$279k** | PA184 — **cannot fly it** | **D** |
| GOT | GOT–LHR | 1,068 | 704 | AV90, 88 seats, **+$568k** | PA184 **−$81k** | A |
| **VCE** | VCE–LHR | 1,150 | 661 | KT95, 95 seats, **+$403k** | PA184 — **cannot fly it** | **D** |
| PMI | PMI–LHR | 1,348 | 396 | KT72, 74 seats, **+$226k** | PA184 **−$902k** | A |
| KEF | KEF–LHR | 1,896 | 264 | AV90, 88 seats, **+$141k** | PA184 **−$703k** | A |

**11 of 93 pickable homes (12%).** Against Phase 2's classes: **seven are
class A** (the larger aircraft is actually worse) and **four are class D**
(impossible to use — in every case a runway-class block at the *home*
airport, which needs `medium` and PA184 needs `large`). **None** is class B,
C or E.

At every one of the eleven, **seven era-locked rows sit above the first
buyable one**, because `hidesLocked` is off by default (baseline §3).

### 2.1 Class D is worse than "loses money"

At Bergen, Billund, Nice and Venice the player who takes the market's default
leases a $790k-a-month aircraft that **cannot be assigned to the route the
game just recommended**. Bergen in full (MEASURED):

| Row | Type | Seats | On BGO–LHR |
| ---: | --- | ---: | --- |
| 1–7 | widebodies and large narrowbodies | 221–422 | era-locked |
| 8 | PA184 | 184 | **blocked** — runway at BGO is medium, needs large |
| 9 | MR180 | 180 | **blocked** — same |
| 10 | NA160 | 162 | **blocked** — same |
| 11 | KT95 | 95 | −$270k/mo |
| 12 | AV90 | 88 | −$164k/mo |
| **13** | **KT72** | **74** | **+$279k/mo** ← what Core names |
| 14 | NA70 | 68 | +$238k/mo |

The right answer is the **thirteenth row of fourteen**, and the three rows
that are actionable-looking and largest are all unusable.

## 3. The correction to AE-042's figure

AE-042 recorded "9 of 93". This phase measures **11 of 93** on the same seed
and catalog. The difference is entirely the model, not the game:

| | AE-042 | AE-043 |
| --- | --- | --- |
| What the player is assumed to buy | largest era-legal type **that can fly the route** | largest era-legal type, **route unknown** |
| Matches the shipped sheet? | no — the sheet has no route | **yes** |
| Homes exposed | 9 | **11** (adds NCE, VCE) |

NCE and VCE were invisible to the earlier model because it silently skipped
airframes that cannot fly the pair — the exact thing the real market does
not do. Nadi also shows a row-1 aircraft that cannot fly its suggestion, but
Nadi has no market that pays on any airframe (AE-042), so it is not a
BUG-056 case and is excluded from the eleven.

Recorded rather than quietly adopting the better-sounding number.

## 4. The mechanism (MEASURED, not inferred)

The per-airframe tables show it directly. On a thin route, every airframe
carries the **whole pool**:

**Reykjavík–London, 264 passengers/day:**

| Type | Seats | Rotations | Carried of pool | Month after its aircraft |
| --- | ---: | ---: | --- | ---: |
| PA184 | 184 | 2 | 264 of 264 | **−$703k** |
| MR180 | 180 | 2 | 264 of 264 | −$621k |
| NA160 | 162 | 2 | 264 of 264 | −$481k |
| KT95 | 95 | 2 | 264 of 264 | +$53k |
| **AV90** | **88** | 2 | **264 of 264** | **+$141k** |

Identical revenue at every size. The seats above the pool earn nothing and
still cost lease, fuel and **seat-scaled movement fees**. So on a thin route
the monthly result is monotonically *decreasing* in seats, and the market
sorts by seats *descending*.

**And the opposite is true where the pool is deep** — which is why this is
not simply "the sort is backwards":

**New York–Chicago, 3,354 passengers/day:**

| Type | Seats | Carried of pool | Month after its aircraft |
| --- | ---: | --- | ---: |
| PA184 | 184 | 1,104 of 3,353 | +$858k |
| **MR180** | **180** | 1,080 of 3,353 | **+$874k** ← Core names |
| NA160 | 162 | 972 of 3,353 | +$734k |
| AV90 | 88 | 528 of 3,353 | +$208k |
| NA70 | 68 | 272 of 3,353 | +$18k |

Here capacity is the binding constraint, more seats mean more revenue, and
the market's first row is within 2% of the best. The same holds at Stockholm,
Barcelona, Singapore, Munich, London and Manchester (MEASURED): row 1 is
either the best airframe or within 2% of it.

**The dividing line is whether the airframe's daily capacity saturates the
pool.** Above it, bigger is better; below it, bigger is pure cost. That is a
property of the *route*, and the market is never told the route.

### 4.1 No existing sort option fixes it (MEASURED)

The first buyable row under each of the four shipped sorts, startup era:

| Sort | First buyable | Verdict |
| --- | --- | --- |
| Seats ↓ (default) | PA184 | wrong at all eleven |
| Range ↓ | PA184 | wrong at all eleven |
| Fuel/seat ↑ | MR180 | wrong at all eleven — per-seat burn favours the biggest cabins |
| Price ↑ | NA70 | right-ish on thin routes, wrong on thick ones (+$18k at JFK against +$858k) |

**No static ordering of the catalog can be correct**, because the correct
answer is a function of the route. Changing the default sort is therefore not
a candidate fix; it only moves which homes are wrong.

## 5. The decision

**CASE C, with CASE B as its cause and CASE D as what the player actually
experiences. CASE F applies in that all three are one defect seen from three
sides.**

- **CASE C — the aircraft market has no concept of route suitability
  (primary).** It cannot have one: every sort key is a static property of the
  spec, and §4.1 shows no arrangement of static keys is right for both thin
  and thick routes.
- **CASE B — route context is lost entering the market (the cause).**
  `AircraftShopSheet()` takes no arguments and is reachable only from
  Fleet → Acquire (baseline §1). There is no route to be suitable *for*.
  Worse, the checklist teaches `acquireAircraft` **before** `openRoute`
  (baseline §6), so at the first purchase a route does not yet exist.
- **CASE D — the recommendation names an airframe and no purchase surface
  shows it.** AE-042 put `bestAirframe` on `MarketOpportunity` *and* on
  `MarketCandidate`, and the only reader in the app is `NextMovesCard`
  (baseline §5). `FirstRouteSuggestion` — the shape the onboarding card
  uses, which is what is on screen while the player buys their first
  aircraft — has no airframe field at all.

**Explicitly not CASE E.** The larger aircraft is not economically superior
at any of the eleven: it loses money at seven and cannot fly the route at
four. The recommendation is right and the market is wrong.

**Explicitly not "the recommendation is wrong".** Core's named airframe pays
at all eleven, and §4 shows it is the maximum over flyable era-legal types by
construction.

## 6. Which stop conditions were tested

| Stop condition | Verdict |
| --- | --- |
| 1. The market is not the root cause | Does not hold — §4.1 shows no market ordering is right and §5 locates the cause in the market's missing route context |
| 2. Fixing it requires changing the economy | Does not hold — nothing in §2 needs a tuning change; the estimator already ranks these correctly |
| 3. The recommended aircraft is itself wrong | Does not hold — §5, it pays at all eleven |
| 5. The change removes legitimate player choices | **Live risk.** The fourteen rows must survive the fix; §7 |
| 8. New York becomes unsafe | To be re-measured after the fix (Phase 8) |

## 7. What the fix must and must not do

From the measurements, not from taste:

- It must put **the airframe Core already named** in front of the player at
  the moment of purchase. That value exists, is authoritative, and is
  currently computed and thrown away.
- It must **not re-sort the catalog globally**: §4.1 proves every static
  order is wrong somewhere, and §4 shows the current default is right on the
  thick majority.
- It must **not hide or remove any of the fourteen rows**. At Bergen the
  player may legitimately prefer NA70 (+$238k) over KT72 (+$279k); at New
  York they may legitimately buy PA184 over MR180 for 16k a month less and
  four more seats of future headroom. Both are real choices.
- It must **not invent a suitability score**. The one that matters —
  `monthlyAfterAirframe` — is already computed by
  `GameState.airframeResult`.
