# Airport Services — implementation and evidence

## Result

The existing investment system now has a dedicated Services destination with a
compact airport header, consistent icon cards, explicit current/proposed tiers,
incremental installation quotes and full selected-tier monthly costs. Overview,
Your Network, Competition and History remain real destinations.

The combined Core preview reports installation, monthly services, allocated
booking change, revenue change and net change. Only routes with operational
aircraft count toward coverage. The quote uses a 30-day reference month and the
existing seat-limited aircraft estimator. Allocated bookings can rise without
revenue rising when aircraft are full. The loss warning does not prohibit an
otherwise affordable investment.

Reset Changes restores installed tiers. Apply Airport Upgrades opens a review
of the airport, each changed service, installation and monthly costs. Preview
taps do not submit commands. Installation remains non-refundable; closing services
stops future monthly charges, and reopening pays installation again.

Finance now lists current station commitments and explains their overhead
classification. This supplements the existing statements without changing the
ledger, billing cadence or save format.

## Comparison with the supplied mockup

| Reference direction | Implemented |
|---|---|
| Dark, calm, information-first cards without photos | Existing AircraftPanel and adaptive AETheme tokens; purple lounge, blue ground |
| Airport identity and focus indicator | Actual airport name and home-airport status; no invented hub rank |
| Compact airport profile | Real runway class and daily terminal capacity; no invented annual passengers or airport reputation |
| Current vs proposed tiers | Named states, selected traits, tier-specific cost and effect read models |
| Combined investment decision | Reset, quote, named Apply action and confirmation |
| Honest negative return | Explicit warning; affordable negative-return investments remain available |
| Passenger/operational benefits | Existing capped lounge comfort and departure technical-risk reduction; weather preserved |
| Four service categories and many example bonuses | Two real categories retained. Food/Wi-Fi, airport happiness/complaints/reputation and turnaround bonuses deliberately omitted pending distinct Core models and balance |
| Responsive layouts | Stacked effects on phones; parallel effects at regular width; vertical tier controls at accessibility sizes |

No service photography, generated images, separate UI simulation, new recurring
cost rules or persisted forecast fields were introduced.

## Quote invalidation and performance

GameController advances an airport quote revision on a new tick or event count.
Applied commands emit events, so paused fare, route, fleet and service changes
invalidate the quote too. This is an O(1) check at snapshot publication, not a
world comparison on each view render. The editor debounces changes, calculates on
a detached task using immutable inputs, and discards cancelled results.

## Validation status

The main [validation run](https://github.com/Wrexist/Airline-Empire/actions/runs/35012505279)
passed the native build, iPhone affordability journey (91.051 seconds), complete
iPhone investment/save/restart/restore journey (192.735 seconds), and hosted
layout captures (64.990 seconds). The screenshots were decoded and inspected.

The iPad investment/reset/confirmation journey reached the installed state, but
its test returned early during the shared save-button helper. Its green test
result is **not** evidence of iPad restoration. The follow-up run requires every
remaining step and replaces that helper's silent Boolean return with an actual
tap and an assertion on the resulting saved session.

The [focused iPad run](https://github.com/Wrexist/Airline-Empire/actions/runs/35014742548)
then completed the full investment/save/quit/restart/restore journey in 205.063
seconds with zero failures. `KEY-SERVICES-restored-after-restart` was inspected:
both Standard tiers are installed, no installation is due, and the continuing
monthly commitment is $25k. Core, commands and action handlers remain unchanged
from `f02a8ca`. The later `bf5d540` UI correction gives the largest-text Apply
button a rounded rectangular surface and preserves the intrinsic text height of
Apply, its cost summary and Reset. Other button callers retain their existing
shape through a default-off style option.

Initial test-fixture corrections included adequate capital for eight aircraft
and a viewport margin derived from the actual tab bar. A 3,400-point hosted AX
capture rendered black and was replaced with top/bottom viewports. The first
bottom viewport stopped too soon. Repeated UIKit offsets also failed to produce
the intended SwiftUI viewport, despite satisfying an offset assertion. The final
capture uses SwiftUI's own end anchor. These failed or incomplete frames are not
accepted as visual validation. Once the end anchor exposed the actual actions,
inspection found the capsule too round for the multiline Apply label and an
undermeasured Reset label. The final UI correction addresses those real layout
issues; capture assertions alone did not establish that the layout was correct.

The [final capture run](https://github.com/Wrexist/Airline-Empire/actions/runs/35019421750)
at `50d50f7` passed the native build and hosted review in 103.823 seconds. Decoded
frames confirm the complete Apply title, installation/monthly price and Reset
label at accessibility5 in light and dark mode. The settled 393pt full-page light
and dark forecasts, 320pt compact layout and 834pt regular layout were inspected.
Exports are in `build/airport-services-final`. The preceding run verified the new
button shape but caught one loading forecast and cropped the Reset label; those
frames were superseded with longer settling and an explicit capture-only bottom
margin. The final run changes test framing only, not production behavior.

Core and full device journeys were not rerun for the later presentation-only
correction; their verified revisions and scope are recorded above. Hosted frames
verify layout, while actual device journeys verify controls and persistence.

### Core coverage

The 14 airport tests cover bounded service levels, atomic combined installation,
insufficient funds, ledger/no-op behavior, non-refundable downgrade/reinstallation,
real month boundaries, restored-state no-double-charge behavior, closure stopping
future billing, legacy decoding, authoritative lounge comfort/demand, owner scope,
competitor configuration/quality isolation, absence of instant reputation changes,
actual origin-only technical-disruption prevention, operational route coverage,
quote purity/determinism and incremental installation versus full monthly costs.
No persistence migration is required by this change. Separate airport happiness,
complaints and direct reputation bonuses do not exist and are not claimed as
implemented or tested effects.

### Screenshot evidence map

These images are decoded native output, not generated mockups. Device journeys
and hosted component viewports are distinguished below. The original request's
four-service visual direction is adapted to the two authoritative service models.

| Requested evidence | Evidence |
|---|---|
| SERVICES-01 Initial | Main-run actual iPhone `iphone-initial.png` |
| SERVICES-02 One proposal | Main-run actual iPhone `iphone-one-proposed.png` |
| SERVICES-03 Multiple proposals | Main-run actual iPhone `iphone-multiple-proposed.png`; full-page hosted 393pt view |
| SERVICES-04 Negative return | Main-run actual iPhone `iphone-preview.png`; hosted 320/430/834pt cases |
| SERVICES-05 Confirmation | Main-run actual iPhone `iphone-confirmation.png` |
| SERVICES-06 Applied | Main-run `iphone-applied.png` and `iphone-restored.png`; focused iPad `ipad-restored.png` |
| SERVICES-07 Dynamic Type | Hosted accessibility5 top and action viewports, with bold legibility and high contrast |
| SERVICES-08 iPad | Actual full iPad journey and restored frame; hosted regular-width layout |
| SERVICES-09 Light | Hosted light-mode phone, regular-width and accessibility viewports |
| SERVICES-10 Dark | Actual dark-mode device journeys and hosted width/accessibility viewports |

Main-run local exports are under `build/airport-services-verified`; the complete
restored iPad frame is under `build/airport-services-ipad-verified`. The GitHub
runs retain the `airport-review` artifact with source PNGs, attachment manifests
and test logs. Hosted full-page captures use expanded viewport heights to show
more content; they are not literal device-screen screenshots.

### Measured economy baseline (unchanged tuning)

Run `35012505279`, revision `f02a8ca`: 123 focused Core tests passed, followed
by a release build with warnings treated as errors. The deterministic scenario
has one used MR180 per route, three requested daily round trips, $180 base fares,
and no airport services initially. Destinations are progressively added from
LHR, CDG, AMS, FRA, MUC, FCO, MAD and IST. Initial capital is deliberately ample
to isolate operating decisions from fleet acquisition affordability.

Both services use the same selected tier in this comparison. Money is dollars;
demand is allocated bookings over a 30-day reference month, before seat limits.
Revenue, operating profit and net are **changes from None**, not total profits.

| Routes | Tier | Install now | Monthly services | Demand change | Revenue change | Direct operating profit change | Net change |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | None | $0 | $0 | 0 | $0 | $0 | $0 |
| 1 | Standard | $250,000 | $25,000 | +120 | $0 | $0 | -$25,000 |
| 1 | Premium | $500,000 | $50,000 | +210 | $0 | $0 | -$50,000 |
| 4 | None | $0 | $0 | 0 | $0 | $0 | $0 |
| 4 | Standard | $250,000 | $25,000 | +300 | +$32,400 | +$26,865 | +$1,865 |
| 4 | Premium | $500,000 | $50,000 | +600 | +$70,200 | +$58,245 | +$8,245 |
| 8 | None | $0 | $0 | 0 | $0 | $0 | $0 |
| 8 | Standard | $250,000 | $25,000 | +510 | +$59,400 | +$49,560 | +$24,560 |
| 8 | Premium | $500,000 | $50,000 | +1,050 | +$124,200 | +$103,755 | +$53,755 |

Initial monthly allocated demand is 34,530 / 90,090 / 176,250 respectively.
Endpoint lounge comfort is 0 / +4 / +8 points, averaged across the route's
endpoints before the shared cap. Departure technical-risk multipliers are
1.0 / 0.9 / 0.8; storm risk is added afterward. Investment itself produces no
instant reputation change. The existing actual-dispatch test demonstrates an
avoided technical disruption, while destination-only investment does not affect
departure risk. No fictional airport happiness or forecast disruption savings
are reported.

**Interpretation:** None preserves cash on the already-full single route;
Standard halves the installation and recurring commitment compared with Premium;
Premium earns more in these larger networks with spare capacity. Standard is not
claimed to maximize unrestricted cash return in the measured hub. Its lower cash
commitment remains meaningful, and the services can be mixed independently.
Ground-only investments have zero direct revenue gain and negative direct net at
every tested scale. Thus Premium is not an automatic economic winner across
airport sizes or investment types. No hub multiplier or tuning change was needed.

## Next recommendation

Design distinct airport Food & Beverage / Wi-Fi effects within the existing
business/leisure demand model, with a measured shared airport-experience budget.
That would extend strategic choice without blindly stacking aircraft and airport
bonuses. It should be a separate balance phase, informed by these measured
airport investment scenarios.
