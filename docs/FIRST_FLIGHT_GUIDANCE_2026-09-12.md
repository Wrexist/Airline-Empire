# First-flight guidance and navigation

Review: https://github.com/Wrexist/Airline-Empire/pull/30
Branch: `codex/first-flight-guidance`, stacked on PR #29.
Final behavior validated: `6b812d62665eb4858a18ee7b19321ca8b013a8ab`. Subsequent changes are documentation and comments only.

## Player experience

- Shared first-flight progress appears on the home map, route discovery, route detail and aircraft market. Scheduled, boarding and cancelled flights do not complete the takeoff step.
- Home guidance distinguishes paused time from waiting for departure. It offers resuming at 1x or explicitly advancing game time to the next morning.
- Route details confirm assignment and explain readiness waits, flying aircraft or a real scheduled departure in game minutes. Resume flights and View on map provide direct next actions.
- View on map closes route setup, returns to Home, clears the map navigation stack and selects the route. New routes await their first completed flight before receiving performance advice.
- Setup prioritizes name, airport and difficulty. Livery sits under Personalize your airline; backup import and world seed sit under Advanced options & backups. The dusk appearance is anchored at the root and in setup so native glass remains dark behind white text.
- The map statistics visibly open the Airline overview. Compatible aircraft explain range/runway fit and the capacity/lease-cost ranking.

## Presentation and state

Uses the existing glass/material surfaces, typography, semantic colors, accessible controls and Reduce Motion-aware animation. No save format or simulation mechanics changed. Progress uses the existing read model without new persisted flags; requesting progress without suggestions avoids calculating market recommendations.

## Validation

- [Full regression](https://github.com/Wrexist/Airline-Empire/actions/runs/34658847252) passed on `12ba8f45954b1f20876f367f0100857064033530`: 527 Core tests, release build with warnings as errors, every iPhone journey shard, both iPad checks, performance and release tooling.
- [Final focused validation](https://github.com/Wrexist/Airline-Empire/actions/runs/34661632632) passed on the final behavior: five onboarding Core tests, release build, four iPhone setup/navigation/large-text journeys, both iPad checks and release tooling.
- The manual onboarding suite is a focused follow-up; ordinary PR, push, smoke and full Core coverage remains unchanged.

Reviewed actual simulator captures of setup contrast, normal and large-text home layouts, route readiness, aircraft shopping and returning to the selected route. Final retained captures: [home](validation/first-flight-2026-09-12/map-home.png), [setup options](validation/first-flight-2026-09-12/setup-options.png), [assigned route](validation/first-flight-2026-09-12/route-assigned.png), [route on map](validation/first-flight-2026-09-12/route-map.png).

Not uploaded to TestFlight.
