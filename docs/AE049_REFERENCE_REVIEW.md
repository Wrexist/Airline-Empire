# Aircraft screen reference review

## Comparison and refinements

| Reference area | Implementation and refinement |
| --- | --- |
| Dark aircraft hero | Original Pacifica artwork, navy gradient panels and real status/route. Reduced header size and kept identity left aligned so more of the cabin fits on iPhone. |
| Five aircraft facts | Installed seats, range, speed, runway and calculated fuel per seat. Compact five-column facts at normal text size; accessible sizes reflow. Fuel uses an actual numeric measure rather than an invented Excellent rating. |
| Section navigation | Cabin, Upgrades, Operations, Condition and History retain the existing app navigation. Reduced tab padding and type size, while retaining 44-point targets and horizontal scrolling when needed. |
| Cabin map | Exact seat counts with class colors and initials, premium floor-space weighting, aisle, galley and lavatory. Added seat-back shading and replaced the emoji galley with a native symbol. The map is a vector illustration, not a photographic cutaway. |
| Class controls | Sliders, percentages, counts and plus/minus controls. Aligned card tops and heights; replaced oversized system button padding with 44-point circular controls. Uses two columns on iPhone, four on iPad, one at accessibility sizes. |
| Reset and saving | Compact outlined reset button beside the heading when it fits. Reviewable refit price, confirmation, discard, state-confirmed saved notice and persistent history. |
| Route performance | Real shared simulation preview: revenue, costs, profit and load factor. Expandable calculation notes keep the figures prominent. The reference's dollar amounts and growth percentages are examples, not fixed game values. |
| Passenger experience | Expected happiness from actual comfort, service, reliability and punctuality. Equipment levels now have visible progress bars. Food is amber; equipment bars are green. |
| Reputation | Explains the aircraft's seat-weighted contribution and shows actual dispatch reliability. Does not invent the reference's +4% result or an unsupported cleanliness score. |
| Upgrades | Wi-Fi, food, seat comfort and entertainment have three levels, real installation/service costs and demand/comfort effects. |
| Operations | Existing route assignment, route navigation, sale and lease-return flows. |
| Condition and history | Real condition, reliability, age, flight hours and maintenance information, plus persisted refits and recent maintenance/delivery events. |
| Light mode and accessibility | Adaptive theme, meaningful labels, class initials in addition to color, Dynamic Type reflow, touch targets and native light/dark captures. |
| Persistence and economics | Legacy saves retain all-economy defaults. Configuration modifies existing demand, revenue, service cost, boarding and reputation systems. No UI-only economy. |

## Intentional differences

The reference packs nearly every section onto one phone image. The implemented
page scrolls so its controls and labels remain readable at actual iPhone sizes.
Premium seating consumes more floor space; economy automatically fills the
remainder. A fully premium layout therefore has fewer passengers than the
reference's example 184-seat total, as required by its written strategy brief.

## Evidence

The previous implementation passed 94 focused Core tests, a release build,
iPhone cabin/save/upgrades and light-mode journeys, an iPad journey, and hosted
accessibility captures. Refinement commit `ccc1b9a` passed
[run 34960987182](https://github.com/Wrexist/Airline-Empire/actions/runs/34960987182).
All 94 focused Core tests, the release build, native build, iPhone journeys,
hosted accessibility captures and iPad journey passed. Full-height native component captures use 393-point iPhone width;
they show the scrollable content and are labelled separately from device screenshots.

Visual review confirmed the tighter hero, readable specification row, aligned
class controls, native galley icon, forecast figures and equipment bars. The
History tab remains reachable by horizontal scrolling at the tested phone size.
Full-content captures include a configured ARN-CDG route and all four cabin
classes; normal device screenshots use the newly leased all-economy aircraft.
