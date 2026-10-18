# TestFlight validation repair - 14 September 2026

Current repair candidate: `fb556404455a5271777b0c3a25856f2538ec3b31`, [PR #37](https://github.com/Wrexist/Airline-Empire/pull/37), based on merged PR #36 (`f48a181`). **Full native validation and the unchanged exact-source release-evidence checker passed.**

## Findings and changes

The [failed TestFlight workflow](https://github.com/Wrexist/Airline-Empire/actions/runs/34891887252) stopped during validation. Archive/upload and processing were skipped. Map Home had an Xcode app-launch timeout. Economy had an app-launch timeout and a briefing failure. Core, Campaign, Arrival, iPad, Shell/Map and Launch safety passed in that run.

The Economy log shows no synthesized briefing tap: the helper stopped while waiting for the live handle to remain stationary, then incorrectly described the result as a failed tap. Live flight advice/progress can change the card's height at 16x. The briefing handle now sits at the bottom of the card, anchored above the tab bar, with changing content above it. The real-flight Economy journey asserts a hittable 44-point target and stable vertical position during departures and after zoom, without pausing the simulation, then requires the briefing to open.

An intermediate Map Home run launched and opened the briefing, but its Close action did not produce a verified dismissal. The test ignored that failed wait and sent a coordinate tap to a non-hittable map action underneath; this activated Finance inside the foreground briefing. The current repair:

- Gives Briefing Close an explicit callback to the map's owning presentation state.
- Hides covered map content from accessibility whenever a map sheet is presented, with sheet content outside that hidden subtree.
- Requires successful dismissal and a usable briefing handle before continuing navigation.
- Removes the shared test helper's fallback that tapped non-hittable elements by coordinate.
- Adds native assertions that covered briefing/next-move controls cannot receive taps while the sheet is open. XCTest may retain covered elements in its snapshot; existence alone is not a visibility or VoiceOver-navigation assertion.

The test action uses XcodeGen's documented [debugEnabled](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) option set to false, selecting its non-debugger test launcher. Interactive Run retains debugging; test assertions, failures, crash reports and Release archive configuration remain unchanged. No test retries or skips were added. The intermediate run launched successfully, but a debugger-version-store warning still appeared; absence of that warning is not an acceptance criterion or evidence of a proven root cause. Actual native launches and completed journeys are the validation.

## Current gates

| Check | Run | Status |
| --- | --- | --- |
| Focused briefing/real-flight regression | [34902350689](https://github.com/Wrexist/Airline-Empire/actions/runs/34902350689) | Both journeys passed on 9c5fd8d; final change only corrects singular/plural warning copy |
| Full iPhone/iPad CI | [34904475257](https://github.com/Wrexist/Airline-Empire/actions/runs/34904475257) | Passed on final fb55640, suite=full and ipad=true |
| PR Launch safety | [34904478869](https://github.com/Wrexist/Airline-Empire/actions/runs/34904478869) | Passed: 527 Release Core, 23 hosted, five UI tests and Release entitlement isolation |
| Windows/Linux tooling and public pages | [34904478857](https://github.com/Wrexist/Airline-Empire/actions/runs/34904478857) | Passed on final fb55640 |
| Native map camera review | [34904478780](https://github.com/Wrexist/Airline-Empire/actions/runs/34904478780) | Passed on final fb55640; phone/tablet gestures, rotation and hosted geometry |
| Exact-source evidence checker | Unchanged repository script | Passed; identifies CI 34904475257 and Launch safety 34904478869 for final fb55640 |

Seven release-workflow regression tests and local live-page/source checks passed. The final PR merge tree was verified identical to its candidate and recorded in `build/ui-polish/release-validation/testflight-34891887252/pr-merge-equivalence.json`. All 16 original user files remain hash-identical. A duplicate standalone safety run was cancelled; it is not counted as a completed gate. Superseded runs retain their actual failed/cancelled status and do not substitute for final validation.

Full CI passed all 527 Debug Core tests and the warnings-as-errors Release build, three iPad tests, six Campaign tests, five Economy tests, one Arrival test and two MapHome tests. Shell/Map passed 13 tests with one existing legacy coordinate-search follow test skipped, plus two separate performance measurements. The skipped test is not counted as a pass; actual following was exercised successfully in MapHome and the dedicated camera review. The native map camera review passed two UI tests and nine hosted geometry tests on each device lane; the phone lane's iPad-only rotation method returns early, so the actual rotation evidence is the tablet lane.

The camera exports retain a UIKit `_UIReparentingView` runtime warning. No application `addSubview`/`UIHostingController` manipulation was found, and the camera interactions passed. This framework warning was not suppressed and is not being described as a resolved app defect. Device review remains important.

Original failure logs/screenshots and new run receipts are under `build/ui-polish/release-validation/testflight-34891887252/`. The final phone portrait/follow and iPad rotation/large-text Market/Finance captures have been inspected. Full native screenshots are indexed with source attribution and SHA-256 hashes in the local review gallery at build/ui-polish/release-validation/testflight-34891887252/review.html; final journey capture review continues. This report is local review evidence; the PR description carries the public validation summary.

## Remaining release acceptance

The repair passed full native validation and the unchanged exact-source evidence checker. Final Economy captures show the first-month statement reopened after a real save/restart and a real aircraft airborne at 16x with the briefing footer anchored. Final MapHome captures show return to Market after closing the briefing and an acquired/assigned aircraft being followed. No gate has been relaxed. The fix remains a separate PR, not merged into main by this repair task. The original failed request was version 1.1.0 with upload=true; any restart must pin the exact validated SHA above.

An approved signed candidate still needs physical VoiceOver, upgrade/save continuity, offline/purchase/restore, real iPad multitasking and sustained performance/thermal/battery checks before App Store readiness. The previous performance comparison had mixed Fleet/16x CPU results; this UI repair is not evidence that those device acceptance items are resolved.

## Restarted request

After every source gate passed, the original version 1.1.0 upload request was restarted as [run 34909225180](https://github.com/Wrexist/Airline-Empire/actions/runs/34909225180), with upload=true and candidate_sha=fb556404455a5271777b0c3a25856f2538ec3b31. It runs its own full validation and safety jobs before any archive/upload. The request is running; an uploaded build, assigned build number and Apple processing completion have not yet been confirmed. No App Store submission or listing change was made. PR #37 remains unmerged.
