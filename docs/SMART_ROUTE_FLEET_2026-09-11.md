# Smart route and fleet planning

Implementation branch: `codex/smart-route-fleet`, stacked on PR #28.
Draft review: https://github.com/Wrexist/Airline-Empire/pull/29

## Player flow

- Expand a selected airport on the home map to see its routes and a create-route action.
- Served airports seed the origin; unserved airports seed the destination from home. Closed airports cannot start creation, and expansion access remains enforced by the existing command precheck.
- Filter route discovery by all destinations, aircraft ready and idle, fleet compatibility, or no incumbent airlines. Existing player routes are omitted. Search and filter redraws reuse the market model.
- Route creation waits for the new route to exist, then opens its detail screen with aircraft assignment and a contextual market action.
- The market can focus on routes with no aircraft or capacity shortages. Compatible types must meet range and runway requirements and the era filter. Best fit ranks capacity against demand, then monthly lease cost; new routes use estimated demand.
- The general aircraft market starts without a selected route; automatic assignment requires an explicit route choice.
- Leasing or buying used for a selected route waits for acquisition, then assigns the aircraft. New orders explicitly wait for delivery. Errors preserve the acquired aircraft in the fleet, and pending actions block duplicate taps.

## Presentation

Filters share a single glass surface using the existing native iOS 26 glass helper and material fallback. Filter transitions and airport expansion use the existing Reduce Motion-aware animation helper. Controls have at least 44-point targets and horizontal scrolling accommodates longer text.

## Validation

Final source candidate: `907115c89c58741b9b7863c808e47f87d08b515f`.
Full Core, iPhone journey, and iPad checks: https://github.com/Wrexist/Airline-Empire/actions/runs/34643725897 (passed on `23cf92e660097890994122d84fafc772dedd0dcf`: 526 Core tests, all iPhone journey shards, both iPad checks, and release tooling).

Added Core coverage for readiness, assignment, range, era, missing aircraft, frequency shortages, seat shortages, and new-route demand estimates. Added an airport-popup-to-route-to-lease-and-assignment simulator journey. Updated existing journeys to finish the new route setup screen explicitly.

These changes are not included in TestFlight 1.0.18 (7). No new upload was requested for this feature pass.

The initial full run passed Core, all five economy journeys, both home-map journeys, and both performance checks. It exposed keyboard occlusion of searched destinations, inherited accessibility identifiers on the airport panel, and an iPad app-launch failure before any feature interaction. Search now uses a compact header, the map selection has a dedicated accessibility container, and general market purchases require an explicit route choice before auto-assignment. The completed full run verified these fixes, the new lease-and-assignment journey, and both iPad checks.

Final visual review found excess empty space in an airport card with no routes. Short action lists now use their natural height; larger lists remain scrollable. The existing airport-panel smoke journey now expands the card and checks the bottom spacing. Focused validation: https://github.com/Wrexist/Airline-Empire/actions/runs/34648062848 (all nine iPhone smoke checks passed; repeated Core checks still running).

Reviewed actual simulator screenshots for the expanded airport, empty idle-aircraft filter, route-matched market, leased-and-assigned route, and keyboard-visible destination search. The final `86b-airport-expanded-fits-content` checkpoint confirms the compact airport card without excess bottom space.
