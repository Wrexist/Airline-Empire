# Accessibility, fresh-game and release review - 14 September 2026

Historical validation record for the candidate later merged as PR #36. For the subsequent TestFlight failure repair, final fb55640 validation and restarted 1.1.0 request, see [the current repair review](TESTFLIGHT_FAILURE_REVIEW_2026-09-14.md). The older candidate and approval statements below describe that earlier pass.

Candidate: `d44cf650d434f40ba5df366cfd6bf36bb65a6918`, draft PR #36. **Full automated release validation and the unchanged exact-source evidence checker passed.** Physical-device acceptance remains open. No TestFlight build/upload, signing/archive, version change, App Store Connect change or merge was made. Distributed build remains **1.0.22 (11)**.

## Changes

- Cash labels expose full amounts and dollars to assistive technology. Fresh Finance says "No outstanding loans"; empty statements and forecasts explain when results become available.
- Market specifications and collapse-summary dates/amounts reflow vertically at accessibility text sizes. Planning filters and acquisition actions have at least 44-point touch targets.
- Game-over headings receive accessibility focus. Reduce Motion removes celebration bounce and game-over pulse; VoiceOver users have ten seconds to read celebrations. Map hints name the available controls.
- Acquisition terms, Cancel, Confirm, errors and receipts now stay inside Market. The list remains mounted to preserve scroll position, with its covered controls excluded from interaction and accessibility. One confirmed command acquires the aircraft and verifies assignment to the intended route. Route-to-market navigation reuses its existing stack. This addresses the nested-presentation reset described in [Apple DTS guidance](https://developer.apple.com/forums/thread/844462).
- Paywall entry requests missing StoreKit prices and prevents overlapping requests. Tests require actual loaded prices and enabled purchase controls. The StoreKit fixture verifies its configured storefront instead of redundantly resetting it.
- Market calculates its available list once, skips fleet-demand analysis for All routes, and builds route-demand explanations only when expanded.
- Fresh-player tests close a real first month, save, terminate, continue and verify the reopened statement. Route helpers verify section selection before finding route actions; real route-creation assertions remain required.

## Final gates

| Check | Source / run | Result |
| --- | --- | --- |
| Full CI, suite=full and ipad=true | d44cf65 / [34874721043](https://github.com/Wrexist/Airline-Empire/actions/runs/34874721043) | Passed all required jobs |
| Launch safety | d44cf65 / [34874720842](https://github.com/Wrexist/Airline-Empire/actions/runs/34874720842) | Passed |
| Portability and public pages | d44cf65 / [34874720890](https://github.com/Wrexist/Airline-Empire/actions/runs/34874720890) | Passed after an unchanged retry of a terms-page HTTP 503; local checks returned 200 for all five pages |
| iOS 26.4 acquisition/cancellation, iPad and Core | 6b351bb / [34870000004](https://github.com/Wrexist/Airline-Empire/actions/runs/34870000004) | Passed; original captures reviewed |
| Performance comparison | 6b351bb / [34871598899](https://github.com/Wrexist/Airline-Empire/actions/runs/34871598899) | All measured journeys completed; qualified findings below |
| Unchanged release-evidence checker | d44cf65 | Passed, identifying the final CI and safety runs above |

Full CI passed 527 Debug Core tests (one isolated plus 526), Release compilation with warnings treated as errors, three iPad tests, six Campaign tests, five Economy tests, one Arrival test and two MapHome tests. Shell/Map had 13 passes and one skipped legacy coordinate-search follow test; two separate measurements passed. The dedicated MapHome journey actually reached flight and exercised follow successfully. The legacy skip is retained explicitly and is not counted as a pass.

Launch safety passed 527 Release Core tests, 23 hosted tests, five UI journeys and one Release entitlement-isolation test. Automated accessibility checks cover descriptions and traits on fresh-game tabs, with no ignored issues; they do not certify every audit category or physical VoiceOver navigation.

**Production equivalence:** d44cf65 changes only two calls in UITestSupport.swift relative to 6b351bb, using the existing stable route-section selector. App/Core sources and resources are identical, and the performance harness does not call these two helpers. `production-equivalence.json` retains the checked diff. Compatibility captures and measurements retain their actual 6b351bb attribution.

Earlier failed or superseded runs are not counted as final validation. The completed d44cf65 gates validate the corrected source without disabling required assertions or changing the release checker.

## Native visual and journey evidence

The [local review gallery](../build/ui-polish/release-validation/accessibility-review.html) contains **31 original native captures**, with source/run attribution and SHA-256 hashes in `final-gallery-manifest.json`.

- Final Economy captures show a real saved campaign after 31 days, 120 flights and 21,600 passengers. Reopening displays February 1 with January's statement intact.
- Final MapHome evidence shows an acquired, assigned aircraft airborne on ARN-LHR, visible above its follow panel, with Stop following available.
- Final iPad tests passed rotation, acquisition and largest-text review. The production-equivalent focused iPad capture also shows complete Seats, Range and fuel-efficiency values in full-width rows.
- The iOS 26.4 regression proves Cancel leaves Market open, reopening preserves usable confirmation controls, covered purchase controls are not hittable, both actions meet 44 points, and a single real lease is assigned to its intended route.
- The final safety artifact contains 22 accessibility component captures covering Finance, Borrow, Settings, Reputation, World events and genuine engine-earned collapse/menu states. They use 375/507-point viewports, Accessibility 3 text, Bold Text and Increased Contrast in light/dark appearances. These are component viewports, not physical devices or actual Split View sessions. All 45 entries in the exported artifact manifest were hash-verified.

Original images, logs, receipts and comparisons are retained under `build/ui-polish/release-validation/`. All 16 original local user files passed their recorded hash check and remain untouched.

## Performance


Production-equivalent comparison: `6b351bb`, [34871598899](https://github.com/Wrexist/Airline-Empire/actions/runs/34871598899). Measured PR merge commit `38e3ff0d8fb0717b485333d5c678344c2097e588` has a tree verified identical to this source. Baseline: `9b4625ba6e2b0dc5a690a4fae82c8ed228e97e05`.

Both revisions used the same earned late-game save and identical harness, sequentially on one iPhone 17 Pro Max/iOS 26.2 **Debug simulator**. All five measured journeys passed on both revisions (baseline 489.852 seconds, candidate 413.381 seconds). Five samples per measure, except three 20-second 16x windows. No saved regression budget exists: passing means the measured interaction completed.

| Median measurement | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Process launch | 3.980 s | 3.203 s | -19.5% |
| Market CPU | 4.567 s | 3.162 s | -30.8% |
| Market scroll duration | 2.664 s | 2.500 s | -6.2% |
| Market peak physical memory | 121,790 kB | 119,234 kB | -2.1% |
| Fleet scroll CPU | 2.665 s | 2.849 s | +6.9% |
| Fleet scroll duration | 2.550 s | 2.494 s | -2.2% |
| Fleet peak physical memory | 106,094 kB | 104,325 kB | -1.7% |
| Map pan/zoom CPU | 4.069 s | 3.826 s | -6.0% |
| Map peak physical memory | 88,498 kB | 88,694 kB | +0.2% |
| 16x CPU per 20-second window | 9.452 s | 10.229 s | +8.2% |

Scrolling uses Apple's [scrolling/deceleration metric](https://developer.apple.com/documentation/xctest/xctossignpostmetric/scrollinganddecelerationmetric), alongside CPU/memory. Clock measures include automation overhead. Hardware counters were unsupported/zero; no hitch distribution was exported. A sample maximum is not a reliable frame-time percentile. Baseline-first order, changed initial map framing and run-to-run variation limit causal conclusions.

Earlier source 53aa416 measured Market CPU -29.1%, Fleet CPU +18.2%, map CPU +35.1% and 16x CPU +10.8%; 6522e5f measured -6.3%, -5.5%, +13.7% and +4.4% respectively. **Map results vary substantially, and the latest lower number does not erase that uncertainty. Fleet/16x CPU are higher in the final sample.** Device frame pacing, sustained play, thermals and battery use remain open acceptance items.

Market avoids repeated demand/list work and separate per-row confirmation presenters. The benchmark opens Market directly from Fleet and does not submit an acquisition. It does not measure accessibility-size layout or confirmation performance. This is evidence of measured improvements and remaining profiling needs, not a universal speed-up claim.

Raw arrays, medians and source/simulator identity checks: `build/ui-polish/release-validation/performance-6b351bb/comparison-summary.json`. Prior comparisons are retained in `performance-53aa416/` and `performance-6522e5f/`.

## Remaining acceptance and next step

1. Review the final previews and changes. Explicit user approval is required before creating or uploading any new TestFlight build; PR #36 remains draft.
2. On an approved candidate, verify physical VoiceOver focus order, announcements, Cancel/focus restoration and rotor navigation; actual OS Reduce Motion/Reduce Transparency; older supported iOS; and real iPad multitasking.
3. Verify physical upgrade/save continuity, offline/interrupted purchase and restore, sustained play, thermal/battery/frame pacing and audio interruptions. Controlled StoreKit coverage includes purchase, restore, failure, pending approval and expiry, but does not replace App Store/device acceptance.
4. After an approved upload, check processing, the existing Tester group and build notes. App Store submission remains a separate decision after device acceptance.

No claim of universal performance improvement, complete accessibility certification or final App Store readiness is made from simulator gates alone.
