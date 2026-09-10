# Airline Empire — execution plan for the first release

Updated 10 September 2026. PR #23 is merged at `e11cea4`. Version 1.0 is still
Prepare for Submission in the live Apple account; no build is attached.
The pre-order date is 16 October 2026. The owner chose to launch in 173 regions,
excluding China mainland and Vietnam because game licenses are not held.
Release finalization is being
implemented on `codex/release-finalization`.

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

Stages 4 and applicable parts of 5 run while hosted tests execute. A merge or
code edit changes the release SHA, so the exact-SHA gate must be rerun where
required. Compilation, generated assets and an old uploaded build do not
replace installed-device acceptance. No estimated date overrides a failed gate.

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
report will distinguish tests completed, Apple changes saved, and remaining
owner-only steps. Do not mark a step complete from this plan alone.

The concrete owner handoff is [RELEASE_OWNER_STEPS.md](RELEASE_OWNER_STEPS.md).
It includes only the remaining upload-setting/device work and a manual fallback
for final submission. The app version currently passes Apple's draft validation
apart from the missing build; purchase draft validation requires the prepared
review screenshots to be uploaded.

## Owner-only handoff template

Use only steps left unfinished in the final continuation report:

1. On your iPhone/iPad, install TestFlight from Apple, open the Airline Empire
   tester invitation/internal build and install the exact recorded build.
2. Launch with network off. Found a free Founder airline, acquire an aircraft,
   open and assign a route, advance through midnight, watch a departure and
   arrival, save/quit, close/reopen and confirm the same campaign.
3. Reconnect. Open Home's briefing → Settings → Airline Empire Pro. Test the
   sandbox products/restore with the appropriate sandbox/TestFlight account;
   confirm the Apple sheet indicates a test transaction before accepting.
   Never make an unintended real purchase for this test.
4. Check existing campaign upgrades, two Pro saves, export/import, expiry/lapse
   and the device/accessibility/audio matrix in the checklist. Report exact
   failing steps and the build number; do not reinstall before exporting saves.
5. In App Store Connect → Airline Empire → Distribution → 1.0, select the
   recorded processed build, finish any specifically named missing fields,
   include the required purchases and submit only after acceptance passes.
6. After approval, review Pricing and Availability. Confirm the intended date
   and every region's pre-order state before Release This Version. That action
   can make the game downloadable immediately in non-pre-order regions.

Steps that the agent successfully completes will be removed from the final
owner handoff. Do not create or change products, prices, agreements, dates or
territories merely to make this generic template shorter.
