# AE-051: Airport & hub management

The subsequent [Airport Services review](AIRPORT_SERVICES_REVIEW.md) records the
compact Services redesign, expanded validation and measured investment trade-offs.
The implementation below is the original airport-management baseline.

## Player experience

Airport detail now follows the aircraft and route screens: navy outlined panels,
adaptive metrics, readable text and five sections.

- Overview: airport identity, operating status, home/network presence, route and
  slot totals, business/leisure/tourism strength, available slots and real fees.
- Your Network: routes, aircraft counts, fares and links to Route Management;
  the existing action to open a route from home remains available.
- Facilities: airline-owned lounge and ground-service levels, cost and demand
  preview, confirmation, rejection reasons and state-confirmed saved feedback.
- Competition: each local rival's reserved movements, routes, frequency and fares.
- History: this airport's entries from the latest 100 airline facility decisions.

The airport browser's Mine scope includes the home airport and stations with
installed services, even after routes close. This keeps ongoing costs discoverable.
The feature develops an airport's role in the network; it does not relocate the
home airport or grant additional slots, connecting passengers or airport ownership.

## Authoritative economics and effects

`AirportFacilityTuning` is content-owned, validated on catalog load, with defaults
for older content bundles. Each service has levels 0, 1 and 2.

| Per level | Installation | Monthly cost | Effect |
|---|---:|---:|---|
| Lounge | $150,000 | $15,000 | +4 comfort points at this endpoint |
| Ground services | $100,000 | $10,000 | 10% relative reduction in technical disruption risk on departures here |

The demand engine averages lounge levels across a route's two airports and adds
the resulting comfort before the existing cap. The existing demand allocation,
competitive split, fares and seat limits still decide how many passengers book.
This is a product-quality improvement, not a promised passenger percentage.

Ground services multiply technical disruption probability before storm risk is
added. They do not remove weather risk or guarantee punctuality. Existing flight
operations, event reporting and reputation record the resulting outcomes.

Monthly airport expenses are itemized under overhead in the authoritative ledger.
Charges begin at the next monthly boundary, with no partial-month proration, and
continue at inactive stations until services are closed. Increasing a level pays
the incremental installation cost; downgrades produce no refund. Reopening pays
installation again. Level 0 can be selected even in debt or after leaving a station.

## Commands, persistence and forecasts

`ConfigureAirportFacilitiesCommand` checks active airline, known airport, valid
levels, airport presence/closure when expanding, and sufficient installation funds.
It changes both services together, posts installation once and records bounded
history. Reapplying an identical plan is a no-op. It does not change slots or refill
the day's remaining demand.

Facilities and history are optional Codable fields on Airline. Existing saves
decode with no airport services. Both player and AI airline entities support the
same command and effects; autonomous AI investment strategy is not added here.

`AirportInvestmentPreview` runs the authoritative demand system on value copies,
then uses the shared aircraft estimator for affected routes. It subtracts the
change in station monthly costs once. The preview is an estimate of the monthly
change, not total airline profit. It excludes installation, future operational
disruption savings and future market changes. Ground investments therefore show
their expense without pretending to know the future cash benefit of reliability.
Aircraft and route forecast labels explicitly exclude fixed airport-service costs.

## Validation

Eight focused Core tests cover atomic installation, ledger amounts, idempotency,
invalid/unserved changes, insufficient cash, closure in debt, monthly billing,
legacy decoding, round trips through saves, actual demand changes, preview purity
and an actual flight dispatch prevented by origin ground services. The dispatch
test also verifies that destination-only services do not change departure risk.

Native journeys load the committed simulation-generated campaign and exercise
airport navigation, both upgrades, the preview, confirmation, saved controls,
network, competition and history on iPhone and iPad. Hosted captures cover all
sections in light/dark and airport/service content at AX5.

## Verified result (2026-09-15)

Application revision `9fe01dc`; subsequent changes affect UI test viewport handling only.

- [Core and iPhone run 35002062634](https://github.com/Wrexist/Airline-Empire/actions/runs/35002062634):
  117 focused Core tests, release build with warnings as errors, native build,
  iPhone investment journey (139.917 seconds, zero failures), and hosted
  light/dark/AX5 captures passed. That run's iPad test stopped at a fully visible
  apply button because its helper incorrectly reserved space for a bottom tab bar.
- [Focused iPad run 35004023363](https://github.com/Wrexist/Airline-Empire/actions/runs/35004023363):
  native build and the full iPad investment journey passed (129.614 seconds,
  zero failures). Core and iPhone checks were intentionally not repeated: the
  application sources are identical, and the test now accounts for iPad's sidebar.
- Native visual review confirmed both upgrades, the expense warning, confirmed
  monthly cost, saved feedback, and retained selections. Hosted captures verify
  readable light/dark layouts and vertically stacked controls/metrics at AX5.
- Review also fixed airport browser navigation, paused-game list invalidation,
  and an unavailable service icon. Test gestures use controlled drags and visible
  control bounds to avoid overshooting or tapping behind navigation chrome.
- Local UTF-8 and diff checks passed. Existing unrelated user edits were preserved.

Both device journeys use the committed simulation-generated campaign; the hosted
review uses a separate small campaign and therefore shows different example values.
No physical-device test, TestFlight release, or full long-campaign regression run
is claimed.

### Screenshots

- `build/ae051-phone-verified/iphone-airport-facilities.png`: actual iPhone simulator.
- `build/ae051-phone-verified/iphone-width-full-investment.png`: full hosted facility
  page at iPhone width, including the investment preview and review controls.
- `build/ae051-ipad-verified/ipad-airport-investment-saved.png`: actual iPad simulator,
  showing both installed services and saved feedback.

## Next recommendation

Finance planning: connect aircraft, route and airport commitments in a clear
monthly cost breakdown and cash forecast, so players can judge how much expansion
they can sustain. Use the existing ledger and simulation estimates throughout.
