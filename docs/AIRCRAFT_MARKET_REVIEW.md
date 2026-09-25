# Aircraft Market comparison — implementation and evidence

## Result

The market now answers one question instead of listing fourteen catalogues.

When a route is selected — which is how the route sheet enters the market, and
the only route-aware entry there is — the screen leads with a **shortlist
comparison for that route**:

- **the held facts**: distance, the route's own fare, its daily frequency,
  written out as held still so the reader knows what was not allowed to move;
- **the demand**: the passengers a day the pair wants and the passengers a day
  the route carries today;
- **up to four candidates**, best result first, each with the cabin, the
  rotations one aircraft of that type flies, the fleet the schedule needs, one
  line in seats explaining the rank, and **a month of the route's operating
  result on that type after its lease, its crew and the route payroll**;
- **the count**: "4 of 6 types this era can buy, best result first."

Every candidate is a way in: tapping one scrolls the market to that aircraft's
own deal cards and commit, so the shortlist is a route into the purchase flow
rather than a second catalogue beside it. The purchase-and-assignment flow is
untouched.

## Audit before implementing

Audited on `codex/ae049-aircraft-configuration` before any change. Existing
unrelated working-tree edits were preserved and never staged.

| Area inspected | Existing authoritative behavior | Decision |
|---|---|---|
| `AircraftShopSheet` (`FleetView.swift`) | Wallet, filters, route picker, `RouteFocus`, sort, per-type card, `ShopDealPicker`, `ShopCommitButton`, confirmation and receipt. | Keep all of it; add the comparison above the list and keep every identifier. |
| `GameState.aircraftFits(route:catalog:era:)` | Range/runway filter, then capacity mismatch, then lease cost. Explicitly **not** a profit forecast. | Leave as the "Best fit" sort. Do not relabel it, and do not reuse it for the money. |
| `GameState.airframeResult(...)` / `MarketOpportunity` | Already prices a market's best airframe with `CompetitorAISystem.airframeDayEstimate` on the demand engine's allocation, after lease, crew and route payroll, before airline overhead. | Reuse the same engine and the same subtraction; never re-derive economics in the view. |
| `CompetitorAISystem.airframeDayEstimate(…)` | Pure, deterministic; carries `fareRatio`, `serviceTier`, `reputationMultiplier`, real `incumbents`, `rotationsPerDay`, `.profit` basis. | Call it per candidate with the route held. |
| `FlightSchedulingSystem.roundTripsPerAircraftPerDay` | The only definition of what one airframe can fly in a day. | Use it for the fleet the frequency needs. |
| `PlayerRouteDefaults.dailyRoundTrips` (= 2) | The frequency new routes are created with. | Not the comparison's frequency: an existing route's own `dailyRoundTrips` is what is held. |
| Commands `BuyNewAircraftCommand`, `BuyUsedAircraftCommand`, `LeaseAircraftCommand` | Unchanged. | Untouched. |
| Persistence | Nothing new. | No save change. |

### What the audit found

- The market had **route filtering but no route economics**: the route picker
  could hide types that did not fit, and the fit rank ordered by capacity
  mismatch and lease cost, but the screen never said what the route would keep
  on any of them. `MarketOpportunity` was already answering that for markets
  the player had not opened; the same answer for a route they *had* opened was
  nowhere.
- Building the estimate in the view would have put economics in a screen and
  out of the test suite's reach — the seam this project is built on. It lives
  in Core.
- The screen's own numbers were compared across mismatched schedules: a smaller
  aircraft could look better simply because it was priced at its own frequency.

## Core read model

`AirlineEmpireCore/Sources/AirlineEmpireCore/Session/AircraftMarket.swift`

`GameState.aircraftMarketComparison(routeID:catalog:era:shortlistLimit:)`

- Holds **the route** (distance, both airports, their runways), **the fare**
  (the route's own ticket price against the demand engine's reference, with a
  1.0 fallback rather than a divide by zero) and **the frequency** (the route's
  own daily round trips — never each airframe's best).
- For every type the era allows and the pair accepts, calls
  `CompetitorAISystem.airframeDayEstimate` with the route's fare ratio, the
  player's service tier and reputation, and the incumbents actually on the pair
  **excluding the player's own route** — the player's route is the subject of
  the comparison, not a competitor in it.
- Reports `rotationsPerAircraft`, `aircraftNeeded` (integer ceiling of
  frequency ÷ rotations), `capacityPerAircraftPerDay`,
  `frequencySeatsPerDay` and `monthlyAfterAirframe`
  (`estimate.value × 30 − lease × aircraftNeeded − payrollPerAircraft ×
  aircraftNeeded − payrollPerRoute`), the same subtraction `MarketOpportunity`
  makes.
- Ranked on the money, then the smaller fleet, then the smaller cabin, then the
  code — deterministic, and `shortlist` is the ranked prefix, so a shorter
  shortlist never reorders.
- Pure: reads the snapshot, mutates nothing, consumes no RNG.

`GameController.aircraftMarketComparison(for:)` caches it per route, cleared
with every other derived cache on each published snapshot — the sheet switches
routes without a new snapshot, and each comparison prices every airframe.

## Screen

`AirlineEmpireApp/Sources/Screens/FleetView.swift`

- `comparisonPanel(_:proxy:)` — the held facts, the demand line, the shortlist
  rows and the count.
- `comparisonRow`, `comparisonIdentity`, `comparisonMoney` — at accessibility
  sizes the money stacks under the identity rather than splitting the width,
  which had left the model name two characters wide.
- `comparisonLabel` and `comparisonFit` — the VoiceOver sentence and the one
  in-seat line that explains the rank. No profit is claimed in either; the
  money is the figure on the right.
- `ScrollViewReader` around the market list and `.id(spec.code)` on each
  aircraft's row, so a candidate scrolls to its own terms.

New identifiers: `ae-aircraft-comparison`, `ae-aircraft-comparison-row`. Every
existing market identifier is unchanged (`ae-market-list`, `ae-market-options`,
`ae-market-route`, `ae-market-network-details`, `ae-deal-*`, `ae-market-*`,
`ae-confirm-*`).

The panel carries `.accessibilityElement(children: .contain)` before its
identifier — the phase-6 finding that a container identifier otherwise
overwrites every child's.

## Validation

**Core.** `AircraftMarketTests`: candidates are era- and range-eligible and
carry the route's own fare and frequency; the fleet the schedule needs is the
integer ceiling of frequency over rotations, and `coversFrequencyAlone` agrees;
the shortlist is the ranked prefix of every candidate and a shorter shortlist
never reorders; a foreign or unknown route has no comparison; comparing is pure
and deterministic (clock, routes, aircraft, ledger and the event log are all
unchanged across two calls); the fare is anchored where the demand engine
anchors it; the era ceiling filters what may be priced; the market demand is
the pair's, not the candidate's.

**Screen tests.** `AccessibilitySurfaceReviewTests.testAircraftMarketAtAccessibleSizes`
renders the market opened on a route at 393 pt and 834 pt in light and dark plus
an AX5 frame. `AircraftMarketUITests` is the device journey: the comparison
appears for the route the market was opened from, names the route it is for,
lists more than one candidate, and a candidate reaches that aircraft's own
lease terms — plus the same comparison at the largest text, where the market is
scrolled until a candidate is genuinely reachable.

**Runs.** Branch validation
[35183970159](https://github.com/Wrexist/Airline-Empire/actions/runs/35183970159):
the focused Core suite — **256 tests passed** — and the release build with
warnings as errors, then the iPhone journeys (airport, passenger, fleet,
finance, campaign, briefing, world/competition and the aircraft market), the
iPad journeys and both hosted capture suites. All green.

The **full** Core suite then ran on the same revision through `ci.yml`
([35186763440](https://github.com/Wrexist/Airline-Empire/actions/runs/35186763440)):
**603 tests passed**, and the release build was clean with warnings as errors.

## Frames inspected, and what looking found

- **Market on a route, 393 pt, light and dark** (`MARKET-01-compare-*`): the
  held facts (`1,462 km · $160 fare · 2×/day held still`), the demand line
  (`2,614 passengers a day want this pair; 1,209 fly with you today.`), then
  Meridian MR-180 (`best`, $947k a month), Pacifica PA-184 Current ($932k),
  Nordavia NA-160 Bris ($802k), Kestrel KT-95 Skylark ($308k), each with its
  rotations, its cabin line and `4 of 6 types this era can buy, best result
  first.`
- **iPad, regular width** (`MARKET-01-compare-834-*`).
- **Large Dynamic Type** (`MARKET-05-AX5-*`): the panel wraps; the candidate
  rows stack rather than squeezing the name.
- **Device, dark** (`KEY-MARKET-01-comparison`, `KEY-MARKET-02-terms`): the
  comparison on a real phone, and a candidate opening its own deal cards.

Three defects were found by looking and by the journeys, all fixed: the
candidate's capacity field was dropped during editing (caught by the Core
build), the AX journey asserted reachability without scrolling the market, and
the candidate row split its width 50/50 at accessibility sizes and left the
model name unreadable.

### Screenshot evidence map

| Requested evidence | Evidence |
|---|---|
| Actual iPhone screenshot | `KEY-MARKET-01-comparison`, `KEY-MARKET-02-terms` |
| Full-page native capture | Hosted `MARKET-01-compare-393-light` / `-dark` |
| Light and dark | Hosted `MARKET-01-compare-*` at 393 pt and 834 pt |
| Large Dynamic Type | Hosted `MARKET-05-AX5-dark` / `-light`; device `KEY-MARKET-AX` |
| iPad | Hosted `MARKET-01-compare-834-*`; device on the iPad shell |
| A candidate reaches its purchase terms | `KEY-MARKET-02-terms` |

The GitHub runs retain the `airport-review` artifact with the source PNGs,
manifests and logs; local exports are under `build/ae-run-35183970159`.

## Store artwork refreshed (same change)

The store storyboard's own capture still photographed the pre-revamp market,
and the seven revamps had changed every screen the composed App Store images
use. Both were stale, so the whole artwork path was re-run:

- `StoreScreenshotUITests` now enters the market from the route rather than
  from the Fleet tab, asserts the comparison panel names the route and ranks
  more than one airframe, and only then photographs `02b-market`. The route
  sheet and the market's controls are scrolled into genuine reachability first
  — three CI runs (35189635088, 35190707150 and 35191948365) each found a
  control that existed below the fold and never received its tap.
- Store captures re-run green for both devices
  ([35191948365](https://github.com/Wrexist/Airline-Empire/actions/runs/35191948365)),
  the composed artwork rebuilt for en-US and copied to en-GB, and
  `verify.cjs` re-passed (`18 valid RGB exports; all original source hashes
  match`, 20 native captures). The overview JPEGs were regenerated and
  `capture-review.json` records the new run, commit and campaign hash
  (`619dd310…`, byte-identical across both device jobs).
- The market frame is review material, not a storyboard source, so the
  composed images are unchanged in structure; the refreshed frames show the
  revamped home, fleet, route, finance, rivals and progression screens.

`validate-metadata.mjs` now passes with **no warnings**: the description checks
were narrowed to what Apple actually rejects — a URL that is not one of the
app's declared links, an explicit price, a discount or a trial — rather than
flagging the subscription Terms link the guidelines require and the accurate
word "free". `asc/selftest.mjs` (53 tests) and
`validate-metadata.mjs` both pass, and `upload-iap-review.mjs --check` confirms
the three prepared purchase review images. Nothing was uploaded to Apple: the
listing's screenshots are refreshed on disk and wait for the next release run.

## Next recommendation

All seven slices in `docs/NEXT_SCREEN_REVAMPS_2026-09-15.md` are done, and the
store artwork now matches them.

1. **Ship the refreshed listing on the next release run.** The screenshots are
   regenerated and verified locally; the release workflow
   (`ios-testflight.yml`) is what uploads them.
2. **Food & Beverage / airport Wi-Fi**, which the plan defers until "effect
   ownership is clear" — the passenger-experience phase deliberately left it
   out because the effect is not the airline's to own yet.
