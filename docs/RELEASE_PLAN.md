# Airline Empire — execution plan for the first release

Updated 11 September 2026. PRs #22 through #26 are merged; no PRs remain open.
Candidate `18253b31333f4e7c0e9a8b9b4410cda2ea45b80d` passed full CI,
Launch safety and portability. TestFlight **1.0.0 (5)** is processed and
assigned to Tester, with test notes saved. App Store version **1.0** has
this build attached and is **Ready for Review** in a five-item draft with
Weekly, Yearly, Lifetime and their subscription group. Nothing is submitted
or published. The remaining critical path is physical-device acceptance,
App Review, then authorized publication.

The pre-order release date is **16 October 2026**, in **173 regions**,
excluding China mainland and Vietnam as instructed. Future expansion is off
for the app and all three products. Detailed current evidence is in
[the execution record](RELEASE_CONTINUATION_STATUS.md).

## Sequence and completion evidence

| Stage | Work | Completion evidence | Dependency |
|---|---|---|---|
| 1 — engineering | Fix Windows metadata/CLI validation, exclude Pro test overrides from Release, require correct store fixture, fix capture instructions, retain evidence 45 days | 50 local tooling tests; actual positive and negative CLI cases; fresh hosted Release test and native captures | Merged #23 |
| 2 — public destinations | Use an identified release-check client and retain HTTP/content assertions; verify all five pages without authentication | Five HTTP 200 responses with real page content locally and on hosted Windows/Linux | Current official site |
| 3 — candidate QA | Full CI with all five journeys and iPad; Launch safety including Release entitlement isolation; portability/live checks; screenshots | Successful required jobs/steps for the exact candidate; inspect screenshots and explain failures/skips | Stages 1–2 |
| 4 — Apple record | Correct separate privacy URLs; verify Data Not Collected, categories/age/content rights, all screenshots, review contact and pricing/availability | Saved fields and current account state, recorded in the continuation report | Signed-in App Store Connect |
| 5 — purchases | Verify weekly/yearly/lifetime IDs, types, prices/offers, localization and availability; supply genuine paywall review screenshots | Products ready for review; device sandbox purchase/restore/expiry results | Apple record and current binary |
| 6 — TestFlight | Archive with the intended marketing version and next available build number; upload, await processing, attach to version 1.0 | SHA → marketing version → build number → processed Apple build | Exact-candidate gates; existing signing credentials |
| 7 — device acceptance | First-flight comprehension, upgrade/legacy campaigns, failed-save retry, offline paid/free/lapsed access, VoiceOver, small phone/iPad, audio and performance | Device model, OS/build, steps, expected/actual result, screenshot/trace, disposition | Installed candidate |
| 8 — review | Include first IAPs/subscriptions, attach accepted build, complete review package, submit and address review feedback | Apple review state and approval | All preceding mandatory gates |
| 9 — publication | Recheck date/territories and pre-order versus immediate-download behavior; publish approved version when ready | Actual public listing state and eventual download/purchase verification | Approval and accepted release decision |
| 10 — support | Retain dSYMs/build identity, monitor crashes/purchases/support and prepare a save-compatible hotfix | Named owner and reproducible triage instructions | Publication |

Stages 1 through 4 and 6 are complete. Stage 5 account configuration is complete;
its device transactions remain in stage 7. Stage 8's complete draft is ready,
but submission awaits acceptance. Stage 10's retention and hotfix procedures
are documented; actual launch monitoring begins at publication.

The binary source is frozen at `18253b3`. Later documentation and workflow
merges do not alter that uploaded source. Future uploads can use PR #26's
full `candidate_sha` input to check out and verify an already-tested source;
this build used the original workflow at `18253b3`. Any replacement binary
requires evidence for its own source and affected acceptance checks.
Compilation and screenshots do not replace installed-device acceptance.

## Current corrections

- The new official host returns all five actual pages to the non-authenticated
  `AirlineEmpire-ReleaseCheck/1.0` client. Python's default User-Agent was
  rejected with Cloudflare 1010. The checker now identifies itself and still
  rejects non-200, missing-title and missing-heading responses.
- The fill-in comparison normalizes CRLF; clean Windows validation passes.
- The bundle CLI uses a proper file URL; regression cases prove it executes
  and rejects an invalid manifest, including paths with spaces.
- Release entitlement initialization ignores UI-test overrides. The fixture
  loader is guarded by DEBUG, and a Release-configured hosted test verifies
  the Pro override cannot grant ownership.
- Marketing capture fails if its generated campaign is absent. Capture
  instructions explicitly select the Swift package and correct save path.
- Paywall UI tests explicitly start a StoreKit test session. The first capture
  run failed because the scheme's Run configuration did not activate StoreKit
  products during the Test action; the product-loading assertion was preserved.
- CI and screenshot evidence is retained for 45 days, past the planned launch.
- The bounded two-year Debug economy regression runs alone before the rest
  of the suite; its original ten-minute limit and all assertions remain.
- iPad CI uses an explicitly booted iOS 26.2 simulator after a diagnosed
  26.5 Core Audio RPC abort. Phone CI remains on current Xcode. Physical
  current-OS iPad audio testing remains mandatory.

## Gate details

Use [RELEASE_CHECKLIST.md](../tasks/RELEASE_CHECKLIST.md) for individual device,
purchase and submission checks. The [dated audit](RELEASE_AUDIT_2026-09-10.md)
preserves the before-state and known reliability gaps. The current execution
report distinguishes tests completed, Apple changes saved, and remaining
owner-only steps. Do not mark a step complete from this plan alone.

The concrete owner handoff is [RELEASE_OWNER_STEPS.md](RELEASE_OWNER_STEPS.md).
It includes the remaining device work and a manual fallback for final
submission. All three purchase review images are uploaded and verified. The
app, three purchases and subscription group are in one five-item unsubmitted
iOS draft with **1.0.0 (5)** attached. Apple enables Submit for Review; device
acceptance is the remaining prerequisite.

## Remaining owner-only sequence

1. Export existing saved airlines to Files before updating. Install exact
   **1.0.0 (5)** from TestFlight; if the older 1.0.14 train is shown, use
   Previous Builds > 1.0.0 > build 5. Preserve the existing installation.
2. With network off, found a free Founder airline, acquire an aircraft, open
   and assign a route, watch departure/arrival and a month statement, then
   save/quit/reopen and verify the same airline. Test export/import.
3. Reconnect and test the three sandbox products, intro eligibility, cancel,
   restore, lapse/recovery and paid offline relaunch using the
   [detailed sandbox guide](RELEASE_OWNER_STEPS.md#3-verify-pro-and-purchase-trust).
4. Complete the small-phone/iOS 17/current-iPhone/iPad device matrix, save
   upgrades/failures, VoiceOver, appearance, audio and measured performance.
   Record device, OS, build, exact steps and pass/fail evidence. See the
   [checklist, section E](../tasks/RELEASE_CHECKLIST.md).
5. After all mandatory acceptance passes, App Store Connect > Airline Empire
   → App Review → existing draft started 10 September at 23:40 Stockholm.
   Verify all five items and **1.0.0 (5)**, then Submit for Review.
6. Address Apple feedback. After approval, recheck 173 regions, both exclusions
   and 16 October 2026 before manual publication of the pre-order. Monitor the
   public listing, scheduled download availability, purchases and crash feedback
   using [release operations](RELEASE_OPERATIONS.md).

The agent cannot operate physical iPhone/iPad hardware or supply human
listening/comprehension results from this Windows workspace. No Apple license,
Chrome extension setting, product creation or image upload remains for the owner.
