# Release continuation — 10 September 2026

Work in progress. This record supersedes account-access assumptions in the
9 September handoff and the before-merge audit. Do not interpret an unchecked
gate or a running workflow as a release pass.

## Candidate

- PR #23 merged to main at `e11cea4b2bfe3407aefbf19bcbc2a7d1a682364d`.
- Release fixes: [PR #24](https://github.com/Wrexist/Airline-Empire/pull/24),
  branch `codex/release-finalization`. Native app/Core source is unchanged
  from `11ae4d2336073e7c9188e0c46e45ac6242c2a999`; the next candidate also
  includes the CI corrections described below. Use the PR's current head
  for the exact-SHA upload gate, not the earlier source baseline.
- App Store app `6806410538`; marketing version **1.0**, Prepare for Submission.
  No new candidate build has been attached or uploaded yet.
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
- Apple's app-version **Add for Review** validation reports only
  **You must choose a build**. No review submission was created.
- Products are still Prepare for Submission. None has been submitted for review.
- Weekly's **Add for Review** validation reports the missing Review Information
  screenshot. Chrome's extension refuses file chooser uploads until the owner
  enables **Allow access to file URLs**. All three genuine files are ready;
  [the owner guide](RELEASE_OWNER_STEPS.md) gives the exact setting and an
  alternative manual upload path. No product screenshot upload is claimed.

## Existing beta evidence and limits

- Internal group `Tester` already contains the owner and four historical builds.
  The owner has installed 1.0.14 (4) on iPhone 15 / iOS 26.5.2. Preserve that
  installation and its saves for the candidate upgrade test.
- Apple exposes one submitted crash-feedback entry from build 1, dated
  28 August 23:04 UTC / 29 August locally. The official read-only API returned
  the stack: `GameCalendar.date` → `GameState.dailyDigest` → `DashboardView`.
  This confirms BUG-008 rather than merely matching its date. The negative-day
  guard and safe previous-day accessor are present; their regression suite
  passes in the current 523-test Release run. Sanitized evidence is in
  `validation/release-2026-09-10/apple-beta-crashes/beta-crashes.json`.
  Hardware confirmation remains required on the new candidate.
- Current full CI `34518221954` has an iPad launch failure. The retained result
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

## Remaining release gates

1. Finish and verify all purchase fields, genuine review screenshots and app metadata.
2. Finish exact-candidate full CI/Launch safety; investigate every failure.
3. Freeze integration SHA, rerun required checks for it, archive/upload and await processing.
4. Install the recorded build and execute device/save/purchase/accessibility acceptance.
5. Submit the accepted app and first purchases together, handle Apple feedback,
   then publish using the verified pre-order/date/territory plan.

Physical iPhone/iPad use and human comprehension/listening cannot be completed
from this Windows workspace. Follow the [remaining owner steps](RELEASE_OWNER_STEPS.md).
