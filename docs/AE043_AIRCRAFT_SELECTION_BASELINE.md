# AE-043 — The aircraft selection pipeline, as built

What the game does between "the player is told which market to fly" and "an
aircraft is on that route", traced through the source before anything was
changed.

Everything here is **READ** (from the repository at commit 71046d9) unless a
line says otherwise. The reproduction is in
docs/AE043_BUG056_ROOT_CAUSE.md; the decision in
docs/AE043_AIRCRAFT_SELECTION_DECISION.md.

## 1. The path, end to end

| Step | Where | What it does |
| --- | --- | --- |
| 1. Rank markets | `GameState.marketOpportunities` — `Session/MarketOpportunities.swift` | Since AE-042, each opportunity carries `bestAirframe`, `monthlyAfterAirframe` and `paysForItsAirframe`. |
| 2a. Before the first route | `OnboardingCard` — `App/Screens/DashboardView.swift:528` | `model.suggestions`, of type `FirstRouteSuggestion`. |
| 2b. After the checklist | `NextMovesCard` — same file | `marketOpportunities(limit: 4)`, and **the only surface that reads `bestAirframe`**. |
| 3. The tap | `FirstRouteSuggestion` → `RouteDraft` → `OpenRouteSheet` | Prefills origin, destination and the reference fare. |
| 4. Acquisition | `AircraftShopSheet` — `App/Screens/FleetView.swift:669` | Presented from `NetworkView.swift:55` as `AircraftShopSheet()` — **no arguments**. |
| 5. Assignment | `GameState.assignmentCandidates(forRoute:catalog:)` | The player's own fleet against one route, with blockers. |
| 6. Reality | `OpenRouteCommand`, `AssignAircraftToRouteCommand`, `FlightOpsSystem`, `EconomySystem` | The ledger. |

## 2. The market's sort key

```swift
@State private var sort: Sort = .seats            // FleetView.swift:675
enum Sort { case seats, range, efficiency, price }
```

```swift
case .seats:      specs.sorted { $0.seats > $1.seats }
case .range:      specs.sorted { $0.rangeKm > $1.rangeKm }
case .efficiency: specs.sorted { fuelBurnKgPerKm / seats ascending }
case .price:      specs.sorted { $0.listPrice.cents < $1.listPrice.cents }
```

Four READ facts:

1. **The default is seats, descending.** The largest aircraft is row one.
2. **Every sort key is a static property of the spec.** None consults the
   route, the player's cash, the era, or any economics. The market cannot
   express "good for this route" because it is never told what the route is.
3. **The sort is static across navigation.** `sort` is `@State` on the sheet,
   so it resets to `.seats` every time the sheet is presented.
4. **It is deterministic in practice.** Swift's `sorted(by:)` is not a stable
   sort, but all fourteen types have distinct seat counts (§4), distinct
   ranges and distinct list prices, so no tie can be broken arbitrarily. The
   input, `catalog.orderedAircraftTypeCodes`, is itself deterministic.

## 3. The market's filters

Exactly one, and it is **off by default**:

```swift
@State private var hidesLocked = false
.filter { !hidesLocked || allowed.contains($0.category) }
```

So the default market lists **all fourteen types**, era-locked ones included,
each with a "later era" badge and no commit button
(`if !locked(spec, …) { ShopCommitButton(…) }`).

Affordability does not filter. `facts(…)` passes the player's cash into
`ShopDealFacts`, and unaffordable deals are disabled in place with the reason
— the UI-006 fix. That behaviour is correct and is not in question here.

## 4. What that produces in the startup era

`Progression.swift:70` — the startup era allows `turboprop`, `regionalJet`
and `narrowbody`. Against the catalog (`Resources/aircraft.json`), in the
market's default order:

| # | Code | Model | Category | Seats | Range | Lease/mo | Startup era |
| ---: | --- | --- | --- | ---: | ---: | ---: | --- |
| 1 | AV420 | AV-420 Imperial | largeWidebody | 422 | 14,300 | $3.00M | **locked** |
| 2 | MR410 | MR-410 Stratos | largeWidebody | 408 | 13,900 | $2.85M | **locked** |
| 3 | AV310 | AV-310 Grandeur | widebody | 310 | 11,900 | $2.15M | **locked** |
| 4 | MR300 | MR-300 Horizon | widebody | 298 | 11,400 | $2.00M | **locked** |
| 5 | PA290 | PA-290 Meridian Sea | widebody | 288 | 10,800 | $1.90M | **locked** |
| 6 | PA228 | PA-228 Coastline | largeNarrowbody | 228 | 6,100 | $940k | **locked** |
| 7 | MR220 | MR-220 Longline | largeNarrowbody | 221 | 6,400 | $890k | **locked** |
| **8** | **PA184** | **PA-184 Current** | narrowbody | **184** | 5,700 | **$790k** | **first buyable** |
| 9 | MR180 | MR-180 | narrowbody | 180 | 5,400 | $740k | buyable |
| 10 | NA160 | NA-160 Bris | narrowbody | 162 | 5,100 | $690k | buyable |
| 11 | KT95 | KT-95 Skylark | regionalJet | 95 | 3,050 | $350k | buyable |
| 12 | AV90 | AV-90 Riviera | regionalJet | 88 | 2,750 | $315k | buyable |
| 13 | KT72 | KT-72 Prairie | turboprop | 74 | 1,600 | $195k | buyable |
| 14 | NA70 | NA-70 Fjord | turboprop | 68 | 1,450 | $175k | buyable |

**Seven unbuyable rows sit above the first aircraft a new player can
actually take**, and that first buyable row is the largest and most expensive
one they can have. This confirms the airframe AE-042's baseline assumed
(`--acquire biggest` → PA184, $790k/month) is the one the shipped UI leads to.

## 5. Where the recommendation's airframe goes

AE-042 computed `bestAirframe` for every ranked market. Every consumer, by
grep:

| Reader | File | Uses |
| --- | --- | --- |
| `NextMovesCard.airframeLine` | DashboardView.swift:676 | `bestAirframe`, `monthlyAfterAirframe`, `paysForItsAirframe` |
| `NextMovesCard.anyMarketPays` | DashboardView.swift:654 | `paysForItsAirframe` |
| — | — | nothing else |

Two consequences, both READ:

1. **The route sheet ignores it.** `marketCandidates` carries all three
   fields (`MarketOpportunities.swift:370`) and `RoutesView` reads none of
   them. The sheet warns whether *something* can fly the pair
   (`canServe.fleet` / `canServe.era`) but never names what.
2. **The onboarding suggestion drops it on the floor.**
   `MarketOpportunity.asFirstRouteSuggestion` maps into
   `FirstRouteSuggestion`, whose six stored properties are origin,
   destination, city, distance, passengers and reference fare. There is no
   airframe field to carry.

## 6. The order the game teaches

`OnboardingModel.Step.allCases` — `Session/OnboardingModel.swift:10`:

```
1. acquireAircraft   → "Get an aircraft"
                       "Airline tab → Fleet → Acquire. Leasing keeps cash free early on."
2. openRoute         → "Open your first route"
3. assignAircraft
4. watchFirstFlight
5. earnFirstRevenue
```

**The player is told to buy an aircraft before they have a route.** And the
card that is on screen while they do it is `OnboardingCard`, whose suggestion
rows read:

```
{ORIGIN} → {DEST} · {City}
≈{N} passengers/day for a typical service · {D} km · fares near {fare}
```

`NextMovesCard`'s airframe sentence — the one AE-042 shipped — is not there,
because `NextMovesCard` only replaces the checklist once the checklist is
complete (`DashboardView.swift:539`, `model.nextStep == .openRoute`).

So at the single moment that matters most for BUG-056 — the first aircraft
purchase, with $60.0M of starting cash — the game has computed which airframe
the market should be flown on, and shows the player none of it.

## 7. Answers to the seven questions Phase 1 asked

| Question | READ answer |
| --- | --- |
| Current sort key | `seats`, descending, by default; four static options |
| All current filters | one: `hidesLocked`, default off. Affordability disables in place, it does not filter |
| Is the sort static? | Yes, and it resets to `.seats` on every presentation |
| Does route context reach the market? | **No.** `AircraftShopSheet()` takes no arguments and has no route or draft in scope |
| Does the recommendation know which aircraft the player picked? | **No.** Nothing flows back; the two systems never meet |
| Can the market display economically inappropriate aircraft? | Yes — and it does: seven era-locked rows above the first buyable one, and no aircraft is ever described relative to a route |
| Is route context preserved into the market? | There is none to preserve |

## 8. What is not wrong

Recorded so the fix stays small:

- **Assignment is sound.** `assignmentCandidates(forRoute:catalog:)` mirrors
  the command validator, checks range and runway at both ends, and reports a
  typed blocker per aircraft. Eligible and blocked are shown separately
  (`RoutesView.swift:582`, `:608`).
- **Affordability is sound.** Cash is on screen; unaffordable deals are
  disabled with their reason rather than failing after the tap.
- **Era locking is sound and honest.** Locked types are shown with a badge
  and no commit button, which is a deliberate "this exists, later" rather
  than a silent omission.
- **The commands are the authority.** `FleetCommands.swift:93/143/205` all
  re-check the era, so no UI ordering change can let an illegal purchase
  through.

Nothing in §8 needs changing to fix BUG-056.
