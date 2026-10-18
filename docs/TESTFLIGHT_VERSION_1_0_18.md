# TestFlight 1.0.18

Requested by the owner on 11 September 2026. Upload authorization is explicit.

Candidate: `c66c6808ab452f918d0aca43f81c63a754c553f3`, containing the UI polish,
route-search dismissal fix and the paywall changes from main `1c61ec6`.

Required exact-candidate checks:

- Full CI with iPad: https://github.com/Wrexist/Airline-Empire/actions/runs/34626254623
- Launch safety: https://github.com/Wrexist/Airline-Empire/actions/runs/34626259020

Both checks passed. TestFlight workflow
[34630867296](https://github.com/Wrexist/Airline-Empire/actions/runs/34630867296)
was dispatched with version `1.0.18`, upload `true`, and the full candidate SHA
above. All four jobs passed. Apple accepted **1.0.18 (7)** and processing returned
**VALID** at 18:31:55 UTC on 11 September 2026. Do not dispatch a duplicate.
Public App Review submission is outside this TestFlight task.

The existing **Tester** internal group (one owner) is assigned to build 7.
Build-specific What to Test notes are saved and verified in App Store Connect.
[Open build 7](https://appstoreconnect.apple.com/teams/47a0adf3-7006-447c-8543-48214a1a243d/apps/6806410538/testflight/ios/19dd6dcf-c0ee-4b41-9da7-03dbab2c9b2e).
Install **1.0.18 (7)** from TestFlight and complete physical-device acceptance
before public release. The App Store submission draft was not changed.

The IPA and matching dSYM are retained in
`C:/Users/IsacC/Airline-Empire-release-artifacts/candidate-c66c680/build-1.0.18-7`.
Local bundle inspection matches the runner report, and executable/dSYM UUIDs match.
[Binary/account receipt](validation/release-2026-09-11/binary-1.0.18-7.json),
[bundle inspection](validation/release-2026-09-11/bundle-inspection-1.0.18-7.json),
and [workflow receipt](validation/release-2026-09-11/testflight-34630867296.json).

Validation history: both normal and accessibility-size paywall journeys passed
on candidate `c66c680` in Launch safety attempt 1, including all three selections,
full billing disclosure, persistent purchase button and reachable Restore Purchases.
The attempt failed on the first free-player simulator startup: XCTest reported
`Unable to monitor event loop`, then an absent target application before the
founding screen. The app job passed on attempt 2 on the same commit; no assertion
was skipped. The release build also passed the check that test flags cannot grant Pro.
The existing internal Tester group has one owner and automatic Xcode build
distribution enabled. Its available crash feedback is from 1.0.0 on 29 August,
not evidence of a crash in 1.0.16 or this candidate.
