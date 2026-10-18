# TestFlight 1.0.20 (9) — menu redesign

13 September 2026: Apple processing completed with **VALID** at 10:35 UTC.
The new build is available in the existing internal **Tester** group (one tester),
verified in App Store Connect. Build-specific testing notes are saved.
No App Store review submission was made.

- [Successful release run](https://github.com/Wrexist/Airline-Empire/actions/runs/34749418574)
- [Merged PR #34](https://github.com/Wrexist/Airline-Empire/pull/34)
- [TestFlight build](https://appstoreconnect.apple.com/teams/47a0adf3-7006-447c-8543-48214a1a243d/apps/6806410538/testflight/ios/76c653ec-4ff3-4d2a-b961-825189169555)
- Candidate: `09ee8d0cf824e85099d9c3ecd6c0b5c3dbe3aceb`.
- Main merge: `8139270d852381d42f5fe9fbc7de430cd1657e35`; its tree is identical to the validated candidate.
- The local project was fast-forwarded; all 13 pre-existing modified/untracked user files retained their original hashes.

The menu now separates returning to a saved airline from founding a new one.
A native route atlas introduces the welcome screen, with dedicated Continue
cards for existing saves. The setup screen uses compact airport choices,
selected-airport details, readable fields, and a solid bottom action bar.
The scroll viewport is clipped above that bar, removing the overlap shown
in the original screenshot. A founding draft survives returning to Menu.
The layout adapts to iPad and accessibility text sizes.

Validation on the uploaded candidate:

- 527 Core tests in Debug and 527 in Release; warnings-as-errors Release build passed.
- 29 native UI/performance executions passed across iPhone and iPad, including the new menu, seed/home selection, campaign, economy, map and rival-arrival journeys.
- Launch safety passed save, StoreKit, free-tier and Release entitlement-isolation checks.
- One pre-existing direct moving-marker gesture test skipped; the accessible Follow journey passed. Check direct marker selection on the physical device.
- The economy worker passed all five cases on attempt 2 after one simulator input was not delivered on attempt 1. The candidate and validation gates were unchanged.
- All PR checks passed before merge. Automatic main CI and Launch safety were still running when this record was written; they repeat checks on the identical tree.
- The downloaded IPA passed independent bundle inspection and matches the upload SHA-256: `358bd51f4481c364934f5a8d44a95fcd8a9ec83a5f45ab0acb40b790d9a1986b`.

IPA, dSYMs, inspection reports, release receipts and native screenshots:
`C:/Users/IsacC/Airline-Empire-release-artifacts/candidate-09ee8d0/`.

Apple API processing and the browser's build-specific Tester group assignment
are verified. The What to Test field was saved successfully; a local copy is
retained in the artifact folder as `testflight-notes.txt`.

Before submission, update the physical TestFlight installation and check
Continue with an existing save, new-airline draft retention, the airport
picker, keyboard/large-text layout, save/reopen, and an offline flight.
