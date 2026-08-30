# Aircraft & Fleet UX

How the app presents aircraft, and which layer decides what. Companion to
`docs/AIRCRAFT.md`, which describes the simulation this renders.

**Status: BUILT AND TESTED IN CORE, NOT VISUALLY VALIDATED.** The read models
below are covered by Core tests that run on Linux. The screens that consume
them compile on macOS CI and have never been seen rendered — no simulator, no
device (`tasks/TECH_DEBT.md` TD-003, TD-006).

---

## 1. The rule

**Core decides. The app words it.**

Not a style preference — it is the fix for the defect this phase was mostly
about. Every time a screen has re-derived a rule Core already owns, it has got
it wrong, and always quietly:

| What the UI re-derived | How it was wrong |
| --- | --- |
| Which routes an aircraft may fly | No range check, no runway check — offered moves Core refused |
| Which aircraft may fly a route | Same, plus hid aircraft in a check that Core would have accepted |
| Which routes accept another aircraft | Only offered empty routes, though Core appends |
| Fleet aggregates (AE-028) | Counted aircraft on order as zero-age, so ordering made the fleet look younger |

None of these produced a crash, a warning, or a failing test. They produced a
game that quietly disagreed with itself.

So: eligibility, aggregates, verdicts and classifications live in Core beside
the rules they mirror, and each is pinned by a test that fails when the two
drift apart. `Vocab` chooses the words. A screen formats; it never decides.

---

## 2. Assignment eligibility

`AssignmentCandidate` (Core) answers "may this aircraft fly this route, and
what would it mean?" for one pairing. Two entry points —
`assignmentCandidates(forAircraft:)` and `assignmentCandidates(forRoute:)` —
so the Fleet side and the Route side ask the same question and get the same
answer. `bothDirectionsAgree` pins that.

**Blockers** mirror `AssignAircraftToRouteCommand.validate` exactly, in the
same order, so that a pairing failing two rules reports the same one the
command would. `blockersAgreeWithTheValidator` drives every aircraft against
every route in a real world and asserts agreement on each — sabotage-checked
by disabling the range branch, which fails it on four pairings.

| Blocker | Means |
| --- | --- |
| `notDelivered(deliveryAt:)` | Still on order. Carries the date, because "not delivered" without a when is not something to plan around. |
| `alreadyAssigned(RouteID)` | Flying something else. |
| `beyondRange(rangeKm:distanceKm:)` | The route is longer than the aeroplane. Rendered as the shortfall, not the two figures. |
| `runwayTooSmall(airport:needs:has:)` | Names *which* end, because the two ends are rarely equally replaceable. |

**Ineligible pairings are shown, not hidden.** A picker that silently drops
what it cannot offer answers "why isn't my new route in this list?" with
nothing, which is how every range and runway problem stayed invisible until
the command refused.

**Maintenance is a note, not a blocker.** Core permits assigning an aircraft
that is in a check; the old UI's `isActive` filter hid those. The screen now
offers it and says it will fly when the check finishes.

### Notes (§24 fit signals)

Restrained on the same reasoning as `RouteVerdict`: a signal that fires on
every candidate ranks nothing, and one that guesses is worse than silence.

- **Range margin** is exact and always available.
- **Capacity** is only described for a route the demand engine has actually
  priced. A brand-new route reads as zero demand; calling that "far more seats
  than demand" would be an artefact of tick timing, not a fact about the
  market. `unpricedRouteSaysNothingAboutCapacity` pins it.
- Between the bands, nothing is said at all.

---

## 3. What an aircraft type is for

`AircraftCategory` is a taxonomy. "Regional jet" tells a player who already
knows the industry everything, and a new player nothing.

`AircraftRole` says what the aeroplane is bought to do, and
`Vocab.roleDetail` names the trade rather than selling it. **The derivation is
one-to-one with category, and the doc comment says so** — in this catalog
nothing else separates types within a class. `roleIsAFunctionOfCategory` fails
the day that changes, which is the moment to revisit both.

### Seat efficiency

The market used to print `fuelBurnKgPerKm / seats` to three decimals. That is
not a figure anyone can rank without the other thirteen beside it, and ranking
was the only thing it was for.

`SeatEfficiencyBand` bands it against the best type in the catalog, which
surfaces the fact the screen was hiding:

| Class | Fuel per seat-km | Band |
| --- | --- | --- |
| largeNarrowbody | 0.0176 | best |
| narrowbody | 0.0190 | best |
| largeWidebody | 0.0217 | strong |
| widebody | 0.0224 | strong |
| turboprop | 0.0303 | thirsty |
| regionalJet | 0.0325 | thirsty |

**A turboprop burns about 72% more fuel per seat-kilometre than a large
narrowbody, and regional jets are the thirstiest per seat of anything you can
buy.** Small aircraft are not cheap aircraft. They buy reach and short fields,
and the fuel bill per passenger is what you pay for it. A player reading raw
`fuelBurnKgPerKm` would conclude the exact opposite, because a widebody's
total burn is several times a turboprop's — which is why
`regionalAircraftAreThirstiestPerSeat` exists.

---

## 4. Fleet at scale

`FleetFilter` (Core) narrows by status, ownership and category. It lives beside
the cards it filters so the counts a screen shows and the rows it lists cannot
disagree.

The property that matters at 200 aircraft is that a filter **partitions** the
fleet — no row lost, no row double-counted. `statusFiltersPartitionTheFleet`
sums the four status buckets and asserts the total is the fleet. That class of
bug is invisible once a fleet is too big to count by eye, which is exactly when
it starts happening.

Two presentation rules:

- **The bar appears past eight aircraft.** Below that it costs a row and saves
  nothing.
- **An empty result says so and offers the way back.** An empty list under an
  active filter is otherwise indistinguishable from a fleet that has vanished.

`idle` means airworthy, unassigned and costing money — not "in a check", not
"on order". Neither of those is something the player can act on today, and
folding them in is what turns an idle count from a to-do list into a number.

---

## 5. Refusals

Core refuses with a stable `code`; `Rejections.present` switches on the code,
never the message, so Core can reword itself freely.

**The failure mode is silence.** A code that does not match compiles fine, is
simply never taken, and drops to the generic branch with its suggestion
missing. Three mappings were in that state before AE-029: the app had
`route.hasAirborneFlights` and `route.runway`/`route.runwayTooShort` against
Core's `route.flightsAirborne` and `route.runwayTooSmall`. The two most
confusing refusals in the fleet flow had careful copy no player could ever have
seen.

`RejectionCodeContractTests` provokes each from a real command and pins the
literal string. It cannot test the app's half — that target does not build on
Linux — so it guards the half it can, and names the three wrong strings
explicitly so anyone reintroducing one meets a test rather than a no-op.

---

## 6. What this phase did not do

Stated plainly, because a document claiming completeness it lacks is worse than
none.

- **Nothing has been seen.** Every claim about legibility or hierarchy is
  authored, not observed.
- **No "show on map" from Aircraft Detail** (§31). There is no map-focus API
  to call — the map owns its own camera and exposes no way to ask it to frame
  an aircraft. That is a real piece of work, not a wiring job.
- **No aircraft-level profitability** (§26). Core attributes economics to
  routes, not airframes, and splitting a route's P&L across the aeroplanes
  that flew it would be an invented allocation. Route economics are shown
  instead.
- **No acquisition moment** (§14). The purchase dismisses the sheet and the
  feed announces it; there is no confirmation using the artwork.
- **Five types share one silhouette at one scale** (`AIRCRAFT_ASSET_BIBLE.md`
  TD-014), so within a class the artwork carries no information.
- **The catalog has no economic personality** (§39). `docs/AIRCRAFT.md`
  claimed ±15% per-type variation; the largest within-category spread is 4.5%
  and most are under 2%. Not rebalanced — pinned by a characterization test so
  the drift is visible next time.
