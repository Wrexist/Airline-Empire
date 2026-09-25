# Passenger Experience & Reputation — implementation and evidence

## Result

The Reputation screen is now a passenger-experience management screen. It opens
with the overall score, what it means and what it is made of; five compact
driver cards that explain each component from the simulation's own state; an
explicit current-versus-proposed airline service tier; a Core-backed cost and
effect forecast; and direct links to the routes, aircraft and airport services
that drive the inputs. Choosing a tier sets a draft. Nothing is submitted until
a named **Apply Service Tier** action is confirmed.

The screen never implies an instant reputation purchase. The forecast
distinguishes *today* from *where the service component is heading*, and the
confirmation says the reputation response is gradual.

No simulation behavior was changed. The only Core edits are a new read model
plus two extractions that keep one definition of the service target and the
seat-weighted comfort the reputation system already used
(`ReputationSystem.serviceTarget`, `ReputationSystem.seatWeightedComfort`), and
one additive field (`AircraftConfigurationPreview.monthlyPassengers`).

## Audit before implementing

Audited at `79c1e93` on `codex/ae049-aircraft-configuration`, before any change.
No AGENTS.md exists. Existing unrelated edits were preserved.

| Area inspected | Existing authoritative behavior | Decision |
|---|---|---|
| `ReputationDetailView` (OperationsView.swift:753) | Overall score, five component bars with prose, three tier rows. A tier tap submitted `SetServiceTierCommand` immediately. Comfort copy claimed "newer and larger cabins score better". | Replace with draft/preview/confirm; correct the comfort explanation; keep the type reachable. |
| `Reputation` / `ReputationSystem` | Five components drift daily (`0.05`) toward measured operations, the tier's service target, seat-weighted fleet comfort, and a value target from fare position (`0.02`). Blended 25/25/20/15/15. | Do not change. Expose the weights (`ReputationComponent`) and pin them to `Reputation.score` by test. |
| `SetServiceTierCommand` | No cost, no validation beyond an active airline; sets `airline.serviceTier`. | Leave the command alone; move the *decision* to a draft + confirmation. |
| `FlightOpsSystem` | `passengerService` is posted per carried passenger at `serviceCostPerPax(tier) + aircraft cabin upgrades`. | Quote the same per-passenger rate; state that spend follows actual passengers. |
| Aircraft passenger experience | `ReputationSystem` comfort = seat-weighted `aircraft.passengerComfort` = `min(1, spec.comfortBaseline + cabin.comfortBonus)`. Age affects reliability, not comfort. | Correct the screen's comfort copy; add `FleetComfortSnapshot` for the premium-seat and upgrade breakdown. |
| `DemandSystem` | Reputation enters the offer only as `demandMultiplier(tuning:)` inside `offerQualityTerms.reputation`. Airport lounge comfort is a separate `comfortOverride` term, not part of `reputation.comfort`. | Show the multiplier as the engine's own number; say lounges are counted separately. |
| Airport services | Lounge raises the demand comfort term; ground services reduce departure technical-disruption risk; neither changes reputation instantly. | Link to the station Services screens; do not claim a reputation effect. |
| Economy / ledger / Finance | Recurring service cost is per passenger, not monthly; there is no reservation or proration. | Quote a 30-day reference volume, not a commitment; say it is an estimate. |
| Persistence / migrations | v13 current; reputation and `serviceTier` are already persisted. | No persisted shape changed; a mid-campaign tier change is tested across save/restore. |
| Tests | `ReputationTests` cover the blend, drift, tier cost, value positioning and save determinism. | Add preview purity/determinism, exact costs, target projection, gradual timing and mid-campaign save/load. |

### Which explanations were outdated

- **Comfort** ("newer and larger cabins score better") contradicted the model,
  which uses seat-weighted `comfortBaseline + comfortBonus` and no age or size
  term. Age enters *reliability*. Corrected on the card and in the forecast
  disclosure.
- **Service** was described as something the tier "sets"; the tier sets a
  *target* the component drifts toward. Corrected.
- **Value** is quality relative to fare position; the card now states the
  airline's actual fare position (`farePositionEWMA`).
- No complaints, historical trends, bonuses or dollar savings were invented,
  and no airport Food & Beverage / Wi-Fi controls were added.

### Proposed improvements that would need Core changes (not taken)

- A passenger-volume forecast for a proposed tier. The multiplier is estimable
  now; the passengers it yields would require re-running allocation against a
  future reputation state and the value component's second-order drift. Omitted
  rather than overclaimed.
- Any airport-experience effect beyond the existing lounge/ground model. Those
  remain a separate balanced extension (docs/AIRPORT_SERVICES_REVIEW.md §Next).

## Core read models

`AirlineEmpireCore/Sources/AirlineEmpireCore/Session/PassengerExperienceModel.swift`

- `ReputationComponent` — the five terms with their blend weights, plus
  `value(of:in:)`. A test pins the weights to `Reputation.score`.
- `FleetComfortSnapshot` — seat-weighted comfort (identical to the reputation
  target), premium-seat share and onboard upgrade levels per seat.
- `ServicePolicyPreview` — a pure quote for a proposed tier: exact
  per-passenger costs, a 30-day reference passenger volume (the demand engine's
  own seat-limited allocation on a value copy), the tier's service target, and
  the reputation score / demand multiplier *if service settles* at each target
  with the other four components held. It reports no immediate demand change.

`ServicePolicyPreview.make` does not mutate the world; a test hashes the state
before and after two identical calls.

## Screen

`AirlineEmpireApp/Sources/Screens/PassengerExperienceView.swift`

- Overall score with the blend weights, today's demand multiplier and the
  administration scar when it exists.
- Five compact driver cards (punctuality, reliability, service, comfort, value)
  with the cause, not just the number.
- Airline service tier: each tier shows its per-passenger cost and target, with
  explicit `current` / `proposed` badges and a current-versus-proposed summary.
- Forecast: cost per passenger, estimated monthly service cost, the service
  target, and the demand multiplier once settled, each with its change and a
  "How this is estimated" disclosure.
- Manage what drives this: links to Route fares, Aircraft cabins, and each
  station's airport services.
- Reset Changes and a named **Apply Service Tier**, confirmed before the
  recurring commitment. Tier taps are drafts; a Core quote debounces on a
  controller revision that moves on a new tick or any applied command.

Visual direction follows the aircraft and Airport Services screens: compact
icon cards, AETheme/AEType/Vocab, semantic accents, current/proposed states, no
decorative photography, and one-column reflow at accessibility text sizes.

## Validation

**Core.** `PassengerExperienceTests` runs beside the existing reputation tests:
component weights against the blend; exact per-passenger costs and volume;
determinism and non-mutation; target/multiplier projection; the ground-experience
target bump; that choosing a tier changes no reputation that day; that service
drifts gradually; that fleet comfort matches the reputation target; and that a
mid-campaign tier change is deterministic across save/restore.

**Native.** `PassengerExperienceUITests` drives the real app from a save: it
opens the screen from the briefing, proves a chosen tier is proposed and not
submitted, reads the forecast and gradual-response note, resets, applies through
the confirmation, and persists the choice through the player's save, quit and
restore flow. `testPassengerExperienceAtAccessibilitySize` proves Apply and
Reset stay reachable at an accessibility text size.

**Hosted captures.** `AccessibilitySurfaceReviewTests
.testPassengerExperienceAtAccessibleSizes` renders the review state (premium
proposed) at a phone width, at an accessibility text size and at regular width,
in light and dark.

**Runs.** The branch validation
[35035752536](https://github.com/Wrexist/Airline-Empire/actions/runs/35035752536)
(24 min 31 s) is green: the 133-test focused Core suite (which includes the ten
new `PassengerExperienceTests`) and the release build with warnings as errors,
then the iPhone journeys, the iPad journeys and both hosted capture suites.

The **full** Core suite was then run on the same revision through `ci.yml`
([35037752594](https://github.com/Wrexist/Airline-Empire/actions/runs/35037752594)):
**566 tests passed** (565 in the parallel run plus the isolated campaign test)
and the release build was clean with warnings as errors. This covers the
extractions in `ReputationSystem` and the additive
`AircraftConfigurationPreview.monthlyPassengers` against the whole simulation,
not only the screens' own filters.

### Frames inspected, and what looking found

Every frame below was decoded from the run's xcresult and read, not assumed.

- **iPhone, dark, the review state** (`KEY-PAX-01` … `KEY-PAX-07`): the overall
  score, the five driver cards, the current/proposed tiers, the forecast and the
  confirmation all read as intended. `KEY-PAX-05-confirmation` shows the dialog
  with "$9 per passenger — about $890k a month", the gradual-response sentence
  and the named Apply. `KEY-PAX-07-restored` shows Premium badged `current` and
  "Current: Premium / Proposed: Premium / No change selected" after save, quit
  and relaunch.
- **Full page, light and dark, 393 pt** (`PAX-03-full-*`): the whole screen in
  one frame, including the "How this is estimated" disclosure and the links.
- **iPad, regular width** (`PAX-08-iPad-*`, `KEY-PAX-07-restored` on the iPad
  shell): the four-column driver grid, the one-row forecast and the restored
  Premium tier over the split-view map.
- **Large Dynamic Type** (`PAX-07-AX5-*`, `KEY-PAX-AX-*`): one-column cards,
  bold legibility, and the Apply and Reset actions still reachable.

Three real layout defects were found by looking and fixed:

1. Driver titles broke mid-word — "Punc-tuality", "Relia-bility" — in the
   two-column phone grid and the four-column iPad grid. The percentage moved
   from beside the title to the end of the bar, giving the title its full width.
2. At accessibility sizes the overall card's "demand ×1.14" broke as
   "de-mand"; it now stacks below the score.
3. The tier buttons kept the selected accessibility trait after they stopped
   being proposed, so both the installed and the proposed tier announced as
   selected. The trait is now explicitly removed when it does not apply.

One harness finding is recorded for future journeys: the passenger screen is
reached inside the briefing sheet, which covers the tab bar — and a covered tab
bar still reports a frame, so an action-reachability bound that reserved space
for it left the last control permanently out of bounds. The helper now measures
against the app frame and proves reachability with `isHittable`.

### Screenshot evidence map

| Requested evidence | Evidence |
|---|---|
| Actual iPhone screenshot | `KEY-PAX-01-initial` … `KEY-PAX-07-restored` (iPhone simulator, dark) |
| Full-page native capture | Hosted `AX-COMPONENT-PAX-03-full-light` / `-dark`, 393 pt |
| Light and dark | Hosted `PAX-03-full-*`; device light frames `KEY-PAX-AX-*`; device dark frames `KEY-PAX-*` |
| Large Dynamic Type | Hosted `PAX-07-AX5-*` (375 pt); device `KEY-PAX-AX-proposed/apply/reset` |
| iPad | Device `KEY-PAX-07-restored` on the iPad shell; hosted `PAX-08-iPad-*` |
| Confirmation and gradual response | `KEY-PAX-05-confirmation`; the `ae-service-gradual-note` frame in `KEY-PAX-03-forecast` |

Local exports are under
`build/ae-run-35035752536` on the machine that ran the review; the GitHub run
retains the `airport-review` artifact with the source PNGs, manifests and logs.

## Next recommendation

From `docs/NEXT_SCREEN_REVAMPS_2026-09-15.md`, the next slice is **Fleet
Operations & Maintenance**: an actionable fleet health board (idle aircraft,
current maintenance, poor condition, assignments, upcoming returns) built on a
shared attention/read model, using actual maintenance quotes and status. Batch
economic commands and replacement forecasts are explicitly deferred to separate
authoritative work in that document.
