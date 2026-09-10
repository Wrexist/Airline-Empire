# The remaining owner steps

Updated 10 September 2026. The agent has configured the Apple record and
all three purchases for **173 regions**, excluding China mainland and Vietnam.
The app remains a first release, version 1.0, with a **16 October 2026**
pre-order date. It has not been submitted or published.

Use [the current execution record](RELEASE_CONTINUATION_STATUS.md) for the
candidate's actual build/upload state. Do not treat the old TestFlight
1.0.14 (4) installation as the new release candidate.

## 1. Allow the three prepared purchase screenshots to upload

Chrome's extension currently refuses local-file uploads. The images are
already captured from the real app and visually checked.

1. In Chrome, open `chrome://extensions`.
2. Find the ChatGPT browser extension and click **Details**.
3. Turn on **Allow access to file URLs**, then tell the agent it is enabled.
   The agent can finish the three uploads and their saved-state verification.

Alternatively, upload them yourself in App Store Connect:

| Product page | File in this repository |
|---|---|
| [Pro Weekly](https://appstoreconnect.apple.com/apps/6806410538/distribution/subscriptions/6810782782) | `docs/validation/release-2026-09-10/iap-review/weekly.png` |
| [Pro Yearly](https://appstoreconnect.apple.com/apps/6806410538/distribution/subscriptions/6810785364) | `docs/validation/release-2026-09-10/iap-review/yearly.png` |
| [Pro Lifetime](https://appstoreconnect.apple.com/apps/6806410538/distribution/iaps/6810786506) | `docs/validation/release-2026-09-10/iap-review/lifetime.png` |

On each page, scroll to **Review Information → Screenshot → Choose File**,
select the matching image, wait for its thumbnail and click **Save**.
Use the Review Information slot; the separate optional promotional image
expects a different asset. Apple explicitly reported the missing review
screenshot when the agent validated Weekly's **Add for Review** action.

## 2. Upgrade your existing TestFlight installation

After a new candidate is uploaded, processed and assigned to your existing
**Tester** group:

1. Open the current game and export each important saved airline to Files.
2. Open TestFlight → Airline Empire. Check its version/build against the
   execution record, then tap **Update**. Keep the existing app installation.
3. Open every existing saved airline. Compare airline name, date, cash, fleet
   and routes. Save, quit, reopen and confirm those same values.
4. Keep the exported backups until the release is accepted. Reinstall testing
   belongs on a separate test device or after backups are safely verified.

The agent can build, upload, assign and attach the candidate. Installing and
operating your physical phone cannot be done from this Windows workspace.

## 3. Play one complete free session

On your iPhone 15, record the iOS version and candidate build, then:

1. Turn network access off. Start a new **Founder** airline.
2. Follow Home's next-action card to lease an aircraft.
3. Open the suggested route, then assign that aircraft in route detail.
4. Advance through midnight. Watch a departure and an arrival; try Follow,
   then pan/pinch the map to interrupt following.
5. Advance to a month boundary and open the statement in Finance.
6. Save and quit, close the app, reopen and continue the same airline.
7. Export that airline, import it and verify its identity and progress.
8. Report any point where you could not tell what to do without coaching.

Pass means no crash, lost progress, wrong campaign, blocked control or
unexplained first-flight step. The original TestFlight founding crash was
diagnosed as BUG-008 and fixed; this hardware journey confirms the candidate.

## 4. Verify Pro and purchase trust

Reconnect and open **Home briefing → Settings → Airline Empire Pro**.
Use TestFlight/sandbox transactions and confirm the Apple sheet identifies
the test environment. Check the localized price before confirming.

| Case | Expected result |
|---|---|
| Weekly, eligible new subscriber | Localized one-week intro and later weekly renewal are clear; Pro unlocks after verified purchase |
| Yearly | One annual charge upfront, annual renewal; same Pro access |
| Lifetime | One payment, no renewal; same Pro access |
| Cancel the purchase sheet | No charge or Pro grant; the game remains usable |
| Restore Purchases | Existing ownership restores without a duplicate purchase |
| Paid offline relaunch | Existing verified access behaves as documented; saves remain available |
| Subscription expires or is revoked | No unearned new Pro access; earned assets and existing campaigns remain safe |
| Two saved airlines | Switching, saving and restarting never overwrites the other airline |

The repository's StoreKit tests already exercise transaction states. Real
Apple storefront eligibility, purchase/restore and device relaunch still
require a device. For controlled expiry, refund and pending-approval cases,
use a sandbox tester or the repository's Xcode StoreKit test configuration;
the agent can prepare the exact scenario after the first device results.

## 5. Complete the device and accessibility checks

The detailed matrix is [section E of the release checklist](../tasks/RELEASE_CHECKLIST.md).
At minimum, record results on the current iPhone, a small supported iPhone
with the iOS 17 baseline, and an iPad in portrait/landscape/compact width.
Use a tester with the missing hardware if you do not own it.

1. Switch system light/dark appearance while playing; increase text size.
2. Turn on VoiceOver and complete founding, route assignment, save/continue
   and opening the paywall. Check control names and navigation order.
3. Turn on Reduce Motion. Verify essential status is understandable without
   animation or color alone.
4. Listen with effects/music on and off, silent mode, headphones/external
   audio, and after background/foreground interruptions.
5. Relaunch repeatedly with audio enabled. CI exposed a Core Audio RPC timeout
   in an iPad simulator during `AudioEngine.prepare`; a simulator retry does
   not prove hardware safety.
6. Play a representative large saved airline at 1×, 16× and paused. On a Mac,
   connect the device and use Xcode **Product → Profile** with Time Profiler
   and Allocations. Record stalls, sustained memory growth, heat, save/load
   times and background activity against the
   [map acceptance targets](MAP_PERFORMANCE_TARGETS.md) and
   [performance measurement guidance](PERFORMANCE.md). Record measured values;
   simulator timings are not a hardware frame-rate certification.

## 6. Return an easy-to-use result

Copy this for each device; attach a screenshot or TestFlight feedback for failures:

```text
Device / iOS:
TestFlight version (build):
Existing saves after Update: PASS / FAIL
Offline first flight and statement: PASS / FAIL
Save, quit, reopen, export/import: PASS / FAIL
Purchases / restore / expiry cases tested:
VoiceOver / large text / light-dark / Reduce Motion:
Audio / relaunch / background:
Large-game performance:
Failure: exact taps → expected result → actual result
```

The agent can triage these results, fix code, rebuild, complete Apple draft
submission fields and track review. No new game license, product creation,
banking change or tester invitation is needed for your existing account.

## 7. Final submission and launch

After the recorded candidate passes the mandatory gates, submit the accepted
app and the three first purchases together. Address any Apple feedback on
that exact build. Once approved, recheck **173 regions**, the two exclusions
and **16 October 2026** before the manual publication action. Apple currently
states that manual release publishes the pre-order listing; approval alone
does not mean the game is downloadable everywhere.

If continuing manually: App Store Connect → Airline Empire → Distribution →
version 1.0 → select the accepted build → **Add for Review**. Add each prepared
purchase to the same draft submission, inspect all four items, then submit.
After approval, follow the release controls for the verified pre-order plan.
Never substitute a different build simply because it is already selectable.
