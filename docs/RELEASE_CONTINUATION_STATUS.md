# Release continuation — 11 September 2026

**Current build: 1.0.16 (6), superseding 1.0.0 (5).** The owner requested
an increase above 1.0.15. [Version correction and receipts](TESTFLIGHT_VERSION_1_0_16.md)
record successful run `34579597613`: exact source `18253b3`, all 523
simulation tests passed, archive/upload/inspection passed, and Apple returned
VALID at 11 September 08:54 UTC. Tester assignment and test notes are saved.
App Store version 1.0 has build 6 attached in the same five-item ready draft.
Physical acceptance is pending; nothing has been submitted or published.

Run `34578192830` failed because it selected the documentation commit without
passing Launch safety evidence. The corrected dispatch explicitly sets
`candidate_sha=18253b31333f4e7c0e9a8b9b4410cda2ea45b80d`; no gate was bypassed.
The older build 5 evidence below is preserved as history and is superseded
for installation/draft selection by the linked build 6 receipt.

## Previous build 5 evidence

- PR #23 merged to main at `e11cea4b2bfe3407aefbf19bcbc2a7d1a682364d`.
- Release fixes: [PR #24](https://github.com/Wrexist/Airline-Empire/pull/24) merged
  at `1cdb46fb944d47464d0ddcb1035a43d3cebe4e5d` on 10 September 22:10 UTC.
  Its full tree is identical to the tested candidate. The
  current candidate `18253b31333f4e7c0e9a8b9b4410cda2ea45b80d`, frozen on
  `codex/release-candidate-2026-09-10`. Full CI `34532237542` passed;
  Launch safety `34532239981` passed. Portability `34532242458`, iPad shell, the full
  Debug Core job and all 523 Release Core tests passed. Shipping app/Core source is unchanged from
  `11ae4d2336073e7c9188e0c46e45ac6242c2a999`; test observation and release
  tooling include the corrections below. Duplicate PR native runs were
  canceled; the manual frozen-candidate runs remain authoritative.
- All five phone jobs passed. Economy passed all five cases: acquisition,
  aircraft flight, New York, currency and first-month statement. The complete
  New York journey passed in 562.356 seconds; the suite had zero failures.
  Exact run/job/step receipts are in `candidate-18253b3-ci.json` in the dated
  validation directory. Redundant main-merge native runs were canceled after
  verifying tree identity; no failed run was counted as a pass.
- Shell/map passed eight tests with one existing NOT VERIFIED skip because
  thirty synthetic taps did not select a tiny aircraft marker. Its camera
  assertion was not reached. The separate map-home Follow path passed;
  physical marker selection and Follow remain required.
- Simulator performance tests completed, but cold-launch samples include
  35.283 seconds and 128.879% relative variation. No stored regression baseline
  exists. `performance-18253b3.json` records all samples and map timings;
  these numbers do not establish acceptable physical-device performance.
- PR #25 merged at `075ba5eacf3bff0e6d78a90a36f9e7712fff5acc`; PR #26 merged
  at `c48cba29f4aaf0ac50b6761142d61524349578c9`. No PRs remain open. These
  changes add account evidence and improve future archive orchestration;
  app/Core/UI-test source remains identical to the frozen candidate.
- App Store app `6806410538`, listing version **1.0 / Ready for Review**, now has processed
  **1.0.0 (5)** attached. TestFlight workflow [34535969370](https://github.com/Wrexist/Airline-Empire/actions/runs/34535969370)
  passed on attempt 2 for exact source `18253b3`. Apple build
  `ac776d10-7bb0-4dc6-aadd-07d9cab19e05` became **VALID** at
  10 September 22:42:23 UTC. It is assigned to the existing one-owner
  **Tester** internal group; build-specific What to Test notes are saved.
- The first archive attempt failed while gathering provisioning inputs,
  before compilation. One bounded retry succeeded with unchanged Xcode
  26.6 (17F113), credentials and signing settings. The original failure is
  preserved in `archive-signing-attempt1.json`; exact server cause is unknown.
  The archive workflow's original Core batch passed all 523 tests. PR #26's
  isolated-test/source-pin improvement is for subsequent workflows and was
  not used by this binary.
- The downloaded IPA passes local inspection, exactly matching the runner's
  report. Its SHA-256 is
  `03ed4c7e2edc97f7e44c319d26448b6388996c483f54d3d80dd32ac1712bf515`.
  Executable and dSYM UUIDs match: `8C6045C1-59F4-399A-965A-617D42294367`.
  Binary, symbols, reports and CI/account receipts are retained outside the
  repository at `C:/Users/IsacC/Airline-Empire-release-artifacts/candidate-18253b3`.
  See `binary-1.0.0-5.json` and `bundle-inspection-1.0.0-5.json` in the dated
  validation directory. Local retention covers the GitHub IPA's 14-day expiry.
- Previous candidate `2a7a8e1` failed full CI `34530096281`: economy and the
  performance startup phase of shell/map failed. Core, iPad, arrival, campaign
  and map-home passed, as did Launch safety, portability and store captures.
  Its upload watcher stopped; this candidate is not eligible for upload.
- Full execution sequence: [release plan](RELEASE_PLAN.md).

## Completed engineering work

- Windows CRLF metadata checks and the bundle CLI entry point are fixed;
  50 release-tooling selftests pass, including real positive/negative CLI calls.
- Release ignores Pro UI-test overrides and DEBUG campaign fixture loading.
  A Release-configured hosted test was added to verify entitlement isolation.
- Store captures require the correct fixture; reproduction instructions are fixed.
- Anonymous live checks pass for all five official pages with an identified
  HTTP client. Status and actual-content assertions remain enforced.
- Hosted Windows and Linux portability/public-page checks passed for `11ae4d2`.
- Native CI artifacts are retained for 45 days.
- The actual exported IPA passed bundle identity/version, iPhone/iPad support,
  privacy manifest and test-resource exclusion checks. The six inspector
  selftests and candidate Windows/Linux CI passed. No test resources ship;
  minimum iOS is 17.0, tracking/data collection are absent, and the private
  UserDefaults reason is CA92.1. See [release operations](RELEASE_OPERATIONS.md)
  for binary retention and launch monitoring.
- Added actual paywall UI capture coverage and unaltered review-image export.
  The first run `34515993864` failed to load StoreKit products in the new UI
  capture test. Existing StoreKit purchase tests passed. Commit `11ae4d2`
  explicitly starts `SKTestSession` and includes its configuration in the UI
  test bundle. Run `34518221910` now passes: 523 Core Release tests, hosted
  launch/save/StoreKit tests, paywall UI capture, and the separate Release
  entitlement-isolation test. All three unaltered paywall images were downloaded
  and visually inspected; see `validation/release-2026-09-10/iap-review/manifest.json`.
- Phone and iPad store capture run `34518221887` passed for `11ae4d2`.

## Saved App Store Connect changes

- Separate US and UK App Privacy policy URLs now point to
  `https://airline-empire-official.isacmolin.chatgpt.site/privacy.html`.
- Existing published privacy label is **Data Not Collected**.
- Created **Airline Empire Pro**, group `22374948`, with US/UK display names.
- Created Weekly `6810782782`, product `com.airlineempire.game.pro.weekly`,
  one week, US $8.99. US/UK descriptions saved; Family Sharing on.
- Weekly intro saved: Pay as you go, one week, US $0.99; 175 regions;
  starts 10 September 2026, no end date. Eligibility still needs device verification.
- Created Yearly `6810785364`, product `com.airlineempire.game.pro.yearly`,
  one year upfront, US $39.99, 175 existing regions; US/UK descriptions saved;
  Family Sharing on. Monthly installment billing was not configured.
- Weekly and Yearly are both service level **1**, matching equal Pro access.
- Created Lifetime `6810786506`, product `com.airlineempire.game.pro.lifetime`,
  **Non-Consumable**, US $49.99; US/UK names/descriptions, review instructions
  and Family Sharing saved. Apple manages regional equivalent prices.
- App and all three purchases now select **173 regions**, excluding China
  mainland and Vietnam. The owner confirmed no game licenses for those regions.
  Automatic expansion to future regions is off. Existing weekly intro prices
  remain listed for 175 regions, but the product itself cannot be sold in the
  two excluded regions.
- Read-only API run `34526736960` confirms 173 available app territories,
  all with pre-order enabled and release date 2026-10-16; the app and each
  purchase have automatic future expansion disabled. An earlier API readback
  caught that the app and Weekly still had expansion enabled despite the
  intended scope. Both were corrected in Apple and verified again. The
  final raw technical record is `validation/release-2026-09-10/apple-territories.json`.
  A fresh browser load also confirmed Mac and Vision Pro distribution off.
- App price is **Free**, pre-order date **16 October 2026**, pending developer
  publication. Both excluded regions show Not Available. See Apple's
  [game licensing requirements](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/).
- Initial platform scope is iPhone/iPad. Existing optional Apple silicon Mac
  and Vision Pro distribution opt-ins were turned off pending platform QA.
- Paid/Free Apps agreements, bank/tax setup, DSA and DAC7 statuses are Active.
  No agreement was accepted or banking/tax data changed.
- Content rights declaration saved: necessary rights to third-party content,
  reflecting the [public-domain Natural Earth map](https://www.naturalearthdata.com/about/terms-of-use/).
- Categories are Games / Simulation / Strategy; current age rating is 4+.
- App review instructions were updated from the checked-in source through
  metadata apply run `34520457476`; a subsequent read-only plan found no
  review-detail drift, including configured contact details.
- US/UK phone 6.5-inch and iPad 13-inch sets contain the six intended images
  in network/fleet/routes/finance/rivals/progression order. Media Manager
  confirms UK 6.9-inch inherits the complete US 6.9-inch set.
- All three genuine purchase review images were uploaded through Apple's
  supported API in run `34533267128`, after read-only plan `34533194273`.
  Apple returned COMPLETE for each, no delivery errors/warnings, matching
  source checksums, and the correct product attachment. All three products
  became READY_TO_SUBMIT. See `validation/release-2026-09-10/apple-iap-review-images.json`.
  The browser also loaded Weekly's 1206 × 2622 review thumbnail successfully.
- App version **1.0 / build 1.0.0 (5)**, Weekly, Yearly, Lifetime and
  subscription group Airline Empire Pro are together in one **unsubmitted iOS
  draft**, started 10 September at 23:40 Stockholm time and updated
  11 September at 00:50. Apple shows **Items Ready to Submit (5)** with
  **Submit for Review enabled** and no remaining draft validation message.
  The build attachment was saved and verified after reload. Final submission
  is pending physical acceptance; the final Submit button was not clicked.
- The earlier Chrome file-chooser restriction was resolved by using the
  authenticated Apple API. No extension setting or manual upload is needed.

## Existing beta evidence and limits

- Internal group `Tester` contains the owner and the new build 1.0.0 (5),
  in addition to four historical builds.
  The owner has installed 1.0.14 (4) on iPhone 15 / iOS 26.5.2. Preserve that
  installation and its saves for the candidate upgrade test.
- Apple exposes one submitted crash-feedback entry from build 1, dated
  28 August 23:04 UTC / 29 August locally. The official read-only API returned
  the stack: `GameCalendar.date` → `GameState.dailyDigest` → `DashboardView`.
  This confirms BUG-008 rather than merely matching its date. The negative-day
  guard and safe previous-day accessor are present; their regression suite
  passes in the current 523-test Release run. Sanitized evidence is in
  `validation/release-2026-09-10/apple-beta-crashes/beta-crashes.json`.
- A fresh TestFlight group check attributes both historical crash counts to
  1.0.0 (1), with three sessions. Builds 1.0.1 (2) and 1.0.11 (3) show one
  and four sessions respectively and dashes for crashes; 1.0.14 (4) shows
  dashes for both. Dashes are not a device-acceptance result. The existing
  one-owner Tester group uses automatic distribution for Xcode builds;
  assignment of build 1.0.0 (5) is now verified. No installed-device
  sessions or acceptance results were present for build 5 at handoff.
  Hardware confirmation remains required on this candidate.
- Earlier full CI `34518221954` has an iPad launch failure. The retained result
  bundle was exported using diagnostic run `34520664211`: the crash is
  `SIGABRT` in Core Audio `_ReportRPCTimeout` / `AURemoteIO::Cleanup`, reached
  from `AudioEngine.prepare()` line 120 while accessing `mainMixerNode` on
  the iOS 26.5 iPad Air simulator. This is distinct from BUG-008. The next
  shell/detail test passed. Preserve this failure; it is not a full CI pass
  and does not establish hardware audio reliability.
- The same full run's Debug Core test hit its 600-second wall limit in
  `regionalRivalKeepsMoneyInTheStandardCast`. It printed three profitable
  routes, $631k direct profit and 57% fees, with no failed economy assertion.
  Tiny unrelated tests also reported roughly 18 minutes from cooperative-pool
  contention. CI now runs this one test alone with its original timeout,
  verifies exactly one test passed, then runs all remaining tests normally.
  No economic assertion, simulation duration or timeout was relaxed.
- The iPad lane now explicitly selects and boots the installed iOS 26.2
  runtime used by the passing store captures, with simulator cloning off.
  Phone CI retains the current Xcode/runtime. This is an environment
  correction, not a claim that the 26.5 audio crash is fixed on hardware.
- Main merge `e11cea4` smoke CI `34515089793` failed when XCTest could not
  terminate/relaunch the app, before a campaign assertion. The new full
  candidate tests are the required evidence; the main badge is not a pass.

## Preserved investigation evidence

### Previous native findings (candidate `2a7a8e1`)

- Economy job `103048517562` passed aircraft acquisition/route creation,
  currency checks and the first-month statement. It failed flight-on-map
  during lease observation, then New York during simulator app termination.
- The lease confirmation was tapped at t=58.06. The eight-second disappearance
  wait ran from t=59.01 to t=97.31 across slow accessibility queries. The
  original screenshot at t=99.34 shows a populated Fleet with one leased
  Meridian MR-180 at $740k/month. The helper short-circuited its aircraft
  check when the waiter timed out, then looked for the empty-fleet market
  entry. The prepared correction reconciles the current disappearance state
  and still requires `leaseLanded` proof; it does not repeat the lease.
- New York failed at `app.launch()` before founding or any journey assertion:
  XCTest could not terminate previous app PID 17432, then reported PID 0.
  This does not validate or invalidate the navigation correction. Native
  diagnostic export `34531523765` completed. The runner requested termination
  at 21:13:01.677, Xcode received it at 21:13:54.048, and the simulator reported
  the requested SIGTERM at 21:13:54.343. XCTest still reported Running
  Foreground at its 21:14:01.721 timeout, then received not-running state.
  This is a host/runner state timeout, not evidence of a spontaneous app crash.
  The sanitized timeline is `phone-failures/economy-lifecycle.json` in the
  dated validation directory. No lifecycle workaround or automatic test
  retry was added; the next candidate must execute the full journey.
- Launch safety `34530096278` passed: Core Release, hosted save/StoreKit,
  paywall captures, map-home, and Release entitlement isolation.
- The shell/map job's performance phase failed before measurements:
  `testColdLaunchBaseline` timed out launching via Xcode, followed by PID 0
  background-assertion failure for map measurement. The original log is
  retained in job `103048518023`; this is not a valid performance baseline.
- Fresh store captures contain all ten source views on both iPhone and iPad.
  All twenty source images have now been inspected and their checksums
  verified. The dated validation directory contains `store-capture-review.json`
  and `visual-review.md`, including a non-blocking Fleet filter wording
  inconsistency and the limits of screenshot inspection. These captures do
  not replace the full native journeys or physical acceptance.

### Earlier native findings (candidate `dff78b4`)

- Full CI `34525956478` passed Core, iPad, arrival, campaign, map-home and
  shell/map. Economy passed four of five cases, including the first-month
  statement; `testNewYorkAdviceIsWorthFollowing` failed at navigation to Routes.
- Its original `KEY-NO-AIRLINE-SECTION-Routes` screenshot shows Home still
  selected, one opened route and one aircraft. The log records an Airline tap,
  but `openTab` returned without checking that selection changed. This is
  evidence of a missed navigation transition, not an economy balance failure.
- The next candidate waits for the route sheet to disappear, then requires
  actual selected-tab state. It permits two total idempotent navigation taps
  and captures each unsuccessful attempt. Route creation and time advancement
  are not repeated. The original journey assertions remain in place.
- Launch safety passed all 523 Release Core tests, hosted save/StoreKit tests,
  genuine paywall captures, map-home on iOS 26.2, and Release override isolation.
  These passes do not override the failed full CI gate or prove device acceptance.

### Earlier native findings (candidate `51b295b`)

- Full CI `34522453247` passed iPad and shell/map, but failed map-home,
  arrival and two campaign cases. Core Debug now passes, including the
  isolated economy test in 80.9 seconds and 522 remaining tests. The economy
  UI journey also passed all five tests. Launch safety `34522453285` passed.
  The three failed UI jobs still make this a failed full CI result.
- Arrival's captured screen remained on Routes after the Fleet tap. The
  helper returned success without checking selection. The next candidate
  requires selected state, allows at most two idempotent selection attempts,
  and retains failed-attempt screenshots.
- The World-tab failure screenshot already showed World selected. The
  next candidate avoids tapping an already selected tab.
- The four-second frame-stability helper could expire before its required
  two comparisons because individual accessibility queries took longer than
  four seconds. The next candidate always performs those two comparisons;
  the requirement that frames agree is unchanged.
- The calendar failure acknowledged request 24 -> 25; its failure screenshot
  showed 26 January. Accessibility snapshot retries consumed the original
  20-second observation window. The next candidate waits up to 60 seconds
  for the same calendar assertion and reconciles one final read, without
  resending an acknowledged advance.
- Diagnostic run `34525098373` exported the original failed native results.
  Its separate read-only Apple metadata plan returned HTTP 401 once and
  passed on retry using the same credentials. No credential was changed.

## Remaining execution order

1. Export existing saves, then install **1.0.16 (6)** through TestFlight and
   execute the device/save/purchase/accessibility/audio/performance matrix.
2. Triage actual device findings; fix any blocking issue and repeat affected
   gates on a replacement build if necessary. Simulator marker selection,
   variable launch timings and current-OS iPad audio remain explicit limits.
3. Once acceptance passes, submit the existing five-item draft, handle Apple
   feedback, then publish the approved pre-order in the verified 173 regions
   for 16 October 2026. Submission, approval and publication remain incomplete.

Engineering, full candidate CI, archive/upload/processing, build attachment
and purchase draft preparation are complete. Later documentation commits do
not change the source identity of the already-uploaded candidate.

Physical iPhone/iPad use and human comprehension/listening cannot be completed
from this Windows workspace. Follow the [remaining owner steps](RELEASE_OWNER_STEPS.md).
