# TestFlight 1.0.21 (10) — transparent menu and motion

13 September 2026: Apple processing completed with **VALID** at 12:57 UTC.
The build is assigned to the existing internal **Tester** group (one tester),
verified on the build's App Store Connect page. Build-specific testing notes were
saved successfully (the page shows Saved). No App Store review submission was made.

- [Successful release run](https://github.com/Wrexist/Airline-Empire/actions/runs/34753437678)
- [Merged PR #35](https://github.com/Wrexist/Airline-Empire/pull/35)
- [TestFlight build](https://appstoreconnect.apple.com/teams/47a0adf3-7006-447c-8543-48214a1a243d/apps/6806410538/testflight/ios/e2ae3d1c-8332-4e34-87dc-32ba2c980b4c)
- Candidate: `b88a758827fedaa026c6103479038be9024e0a17`.
- Main merge: `68c3b956211da4eae6b0cfb8eb7a4386e1ac051b`; identical source tree.
- The local project was fast-forwarded; all 14 pre-existing modified/untracked
  files retained their original hashes.

The solid navy founding footer is removed. The action floats above a continuous
dusk background with a soft fade at the bottom of the scrolling form. Welcome
and founding actions use clear interactive Liquid Glass on iOS 26, with a material
fallback on older systems. Press springs, menu transitions, animated airport
selection, field-focus feedback and a one-time atlas route reveal add motion.
Reduce Motion, Reduce Transparency and increased contrast have dedicated alternatives.

Validation on the uploaded candidate:

- 527 Core tests passed in Debug and 527 in Release; warnings-as-errors Release
  build passed.
- 29 native UI/performance executions passed across iPhone and iPad. Final native
  iPhone, iPad and large-text previews were reviewed.
- Launch safety passed save, StoreKit, free-tier and Release entitlement-isolation checks.
- All PR checks and automatic main CI, launch-safety and portability checks passed.
- The shell-and-map worker passed on attempt 3. Attempt 1 hit an Xcode app-launch
  timeout before the first accessibility test could open the app. Attempt 2 passed
  that test but failed an aircraft-selection assertion; its screenshot shows the
  picker still open after the synthetic tap. Source, assertions and gates stayed
  unchanged for both retries.
- One pre-existing direct moving-marker gesture test skipped after thirty synthetic
  taps selected no aircraft. The accessible Follow journey passed separately.
  Direct marker selection still needs physical-device acceptance.
- The downloaded IPA passed independent bundle inspection and matches the upload
  SHA-256: `64ace0eb76a8f93ae37911caa69f1411db300ace1dfbb8ae376cc0d5751bfb75`.

IPA, dSYMs, inspection reports, release receipts, test notes and native previews:
`C:/Users/IsacC/Airline-Empire-release-artifacts/candidate-b88a758/`.

Before submission, update the physical TestFlight installation and check the glass
press response, airport selection and draft retention, keyboard/large-text layout,
accessibility settings, Continue with an existing save, save/reopen and an offline flight.
