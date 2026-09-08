# Launch implementation status

8 September 2026. Implementation branch: `codex/launch-readiness`, PR #22.
The original audit is preserved in [LAUNCH_AUDIT.md](LAUNCH_AUDIT.md). This file records what has actually changed; the full expansion backlog is not a completed feature list.

## Implemented

| Audit | Change | Remaining evidence or limitation |
|---|---|---|
| R01 | Each campaign owns a unique save slot. Loading legacy `auto` keeps that slot; new campaigns cannot overwrite it. | Hosted app regression covers founding two airlines, saving, quitting and loading. |
| R02 | Failed save-and-quit retains the live session and reports the failure. Retry remains available. | Hosted failure/retry regression uses an unwritable save destination. |
| R03 | Private UserDefaults use declared with CA92.1. | Confirm the final archive's privacy report before submission. |
| R04 | Correctly cased `.html` URLs, accurate privacy/support copy, Terms page linking Apple's standard EULA, public support request link. | Pages still needs deployment and a successful live URL check. |
| R05 | Pending, failure, restore and purchase feedback in the paywall/Settings; restore errors no longer become “nothing to restore.” | StoreKit integration tests must pass. |
| R06 | Unrelated UI test flags no longer grant Pro. Existing full-world fixtures opt in explicitly; a dedicated free journey and hosted purchase tests use StoreKit. | Complete device/sandbox validation remains required. |
| R07–08 | Runtime progression ceiling shared by every simulation time path. Free/lapsed airlines keep operating; paid aircraft, new capability programs and out-of-radius routes are checked at the command boundary. | Existing earned eras and assets are preserved. No persisted save schema change. |
| R09 | Dedicated Launch safety workflow; TestFlight upload requires successful same-commit Launch safety plus full CI with all five journeys and iPad. | Existing full-suite failures must be resolved and rerun. Compilation alone cannot authorize upload. |
| R10 | Store metadata links/review notes corrected and fill-in sheet regenerated. | Legal seller name, review contact, screenshots, App Store product/account configuration remain external inputs. |
| R11 | Aircraft shop initially hides locked classes and ranks a viable starter-route aircraft first, with a route and estimated result to explain the recommendation. | Multi-home economic calibration and physical-device comprehension checks remain. |
| R12 | Player forecasts use the route creator's two-round-trip default, capped by the airframe's daily capacity. Assumptions explain lease/payroll and excluded airline overhead. | Forecast is still an estimate; no claim of guaranteed profit or completed balance calibration. |
| R13 | Idle routes place aircraft assignment near the top. Young routes explain ticket revenue versus company profit. | Observe first-session comprehension on devices. |
| R14 | User-facing day advance labels now match the midnight behavior. | Internal function names stay compatible. |
| R15 | Refresh on foreground, product load, transaction updates and expiry. Only verified grace deadlines extend expired subscriptions. | Real Apple sandbox cancellation/refund/grace rehearsals remain. |
| R16 | Initial checkpoint, daily autosaves, captured session/slot on background, UIKit background allowance, checked synchronization/rotation errors, future-version protection. | Forced termination/low-storage rehearsal on physical devices remains. |
| R17 | First automatic offer follows the first completed flight; foreground nudges require that milestone. | Check presentation alongside the first-flight celebration. |
| R18 | Low-cost rivals prefer used ownership; expansion waits for placed aircraft and nonnegative closed-month net profit. Retrenchment distinguishes positive recurring cash from genuine cash drain. Nine-seed controlled runs improved all five strategies; the regression now requires every median to preserve starting capital. | See RIVAL_BALANCE_FIX.md. Integrated Core and curated player journeys still need to pass. |
| R19 | Time-control hit targets are at least 44 points. Flight-follow menu gives a production accessibility path without tapping tiny moving markers. Follow test now fails when the path is unavailable. | Fresh small-phone, iPad, Dynamic Type and VoiceOver review remains. |
| R20 | No unsupported performance claim added. | Physical-device memory, battery, thermal and frame-time evidence remains. |
| R21 | Manifest, legal/support pages, review notes, generated store checklist and this status document updated. | Older design/audit documents describe historical behavior and are not release certification. |

## Additional delivered feature

Campaign export/import is available through the system file picker. Export captures a coherent snapshot using the existing checksummed save format. Import checks file size, codec/version/integrity and the presence of a founded airline, then writes a new slot before opening it. It respects the free campaign limit and never overwrites an existing campaign. The hosted regression covers export, import, slot separation and rejection of corrupt data.

## Validation record

- Initial launch commit `e73c98f`: iOS `build-for-testing` passed on the existing macOS 26 CI runner.
- Initial targeted Core run: **45 tests passed**, covering save store/migrations, campaign isolation, failure preservation, time access and entitlement expiry/grace rules.
- Release tooling: **47 selftests passed** after regenerating the fill-in sheet.
- Local Swift 6 Core type-check and app/test syntax checks passed. SwiftPM's local runner crashes before assertions in this environment; it is not counted as a test pass.
- The first new app test job used macOS 15's older SDK and failed on the existing iOS 26 glass API. The workflow now uses the project's macOS 26 runner.
- Commit `3f5f207`: current-Xcode iOS build passed. All four hosted save/fixture tests and the free-player UI entry journey passed. The map journey failed at market dismissal after leasing. The sheet now owns the dismissal callback.
- StoreKit test setup on iOS 26.4 returned `SKInternalErrorDomain Code=3` before products could load. The dedicated test lane now selects the installed Xcode/iOS 26.2 combination, consistent with the reported simulator workaround. Current-Xcode compilation remains in normal CI. See [Apple Developer Forums](https://developer.apple.com/forums/thread/826364).
- A nested Swift Testing macro in the malformed-save test failed to compile; the unwraps are now separate statements.
- The full 513-test release run found five stale expectations in three test cases after the forecast correction: the shared-estimator comparison assumed maximum aircraft utilization, and Munich advice/arrival fixtures assumed Istanbul opened in February. Expectations now use the actual starter schedule. The observed rival still arrived on Munich–Istanbul on day 61, with 39% player share after a month and Regional progression on day 59; these substantive checks remain enforced.
- Commit `2059bb2`: all four hosted save tests, all four real StoreKit tests (purchase/restore, failure, pending, expiry), and free-player entry passed on iOS 26.2. The map journey exposed two nested accessibility nodes for the same confirmation button; its selector now resolves the first matching control. Opening Home, briefing and aircraft-market screenshots were inspected.
- Commit `5d47846`: **all 513 Core release tests passed**, followed by the release source checks. Current-Xcode iOS compilation and release tooling also passed. Normal CI's longer debug suite and the full map journey were still running when this entry was prepared.
- The same commit's UI run confirmed leasing, route creation and assignment. Its follow leg raced the clock: screenshots showed a flight at 06:45 and none when Pause finally landed at 11:30. The test now uses 4× and pauses before capturing its checkpoint. Hosted tests then aborted during test-process startup before any assertion; that run does not supersede the earlier eight-test pass or constitute fresh hosted evidence.
- Store descriptions now state 16× speed, separate campaign saves and the network requirement for Apple purchases. Planned hub/commonality mechanics are no longer advertised as shipped. TestFlight instructions follow the map-first controls and include save/purchase recovery checks.
- All later fixes still require current-commit CI evidence. Earlier passes do not certify later edits.

## Continuation: 8 September

Candidate `b2420a1` completed both workflows successfully. The full 513-test Core suite passed in debug and release. The app lane passed all four save tests, all four StoreKit tests, free entry and the full map-to-first-flight/follow journey. The follow and later-map screenshots were inspected. Normal CI still skipped the full journey matrix and iPad.

Additional implementations now awaiting candidate validation:

- Home's existing briefing strip shows next-era progress after the first flight. The full briefing names the next unmet requirement and opens the existing progression screen, using the same cached Core model.
- A successful save-and-quit produces a session recap with actual flights, passengers, days, cash movement, fleet/network changes and a next action. Failed saves produce no success recap. Each opened campaign starts a new baseline, and cash movement is explicitly distinguished from profit.
- The map top bar switches to two rows when the full date and controls do not fit. The previous successful journey still photographed the date as “20…”.
- A `full-validation` PR label requests all UI journey shards plus the iPad lane and forces a real build even after a prior green compile. PR #22 carries that label.
- README, the go-live guide and release pipeline now distinguish dated signing failures from the later successful upload.

## Rescue and contract implementation

- A distressed airline can accept or permanently decline a one-time rescue before its first administration. Financing restores at least $2M cash, borrows $5M–$20M, and uses the existing loan system at 15% annually over 24 months. The briefing discloses the repayment and continued bankruptcy risk before confirmation.
- Players who complete their first flight can choose a flight or passenger contract in Progression. One acceptance per calendar month, one active contract, 28 game days to complete, no deposit or expiry penalty. Only activity after acceptance counts. Rewards use the existing mission ledger and cannot be claimed again after reload.
- Save format v13 migrates old rescue decisions and protects older clients from unknown contract kinds. Regression coverage exercises financing repayment, decision persistence, migration, both reward types, duplicate claims, expiry and late completion.
- UI journeys use a unique debug-only save directory per test. Relaunches within a test retain it. The recap test exposed cross-test contamination from a prior free campaign; isolation does not grant Pro or delete player saves.

On `3063ab9`, Core release tests, iPad shell, map-home and release-tooling checks passed. The full date is visible in inspected map screenshots. All eight hosted save/StoreKit tests passed. The recap UI test failed before founding due to shared saves; the isolation fix above requires a fresh run. Other full journey shards were still running when this entry was written.

Candidate `9e6bd6b` passed all **521 Core release tests**, including rescue repayment, legacy migration and both contract reward paths. All **11 app/UI launch-safety tests** also passed: four save tests, four StoreKit tests, free entry, save recap and the first-flight/follow journey. The recap screenshot showed a redundant success alert covering the card; save-and-quit now uses the card as its success confirmation while preserving failure alerts. The full journey matrix and subsequent fixes still require final-candidate validation.

The long economy journey now waits for the requested one-day or seven-day calendar movement after each tap. UI idleness alone did not await the asynchronous simulation task, allowing overlapping advances to skip an exact target date. The strict destination-date assertion remains in place.

PR review identified a stale-ownership nudge on foreground. The foreground task now awaits ownership refresh and cancels when the scene changes; verified Pro ownership also clears any stale purchase prompt. The real StoreKit purchase regression checks that refresh behavior. Contract confirmations now quote an exact midnight deadline aligned with daily mission settlement, including when accepted at midday.

Candidate `a9037e4` passed all **522 Core release tests** and all **11 launch-safety app/UI tests**. Full CI passed map-home and release tooling, but exposed additional issues:

- Campaign and arrival stopped on a lost time-control tap during a milestone. The informational celebration overlay now passes taps through; a cancelled older banner task can no longer dismiss a newer banner.
- iPad failed during first launch. Its actual crash report shows `SIGABRT` in `AURemoteIO::Initialize`, reached through `AudioEngine.prepare` and `mainMixerNode`. Audio preparation now waits for an active scene, checks session activation and output availability before building the graph, and supports retry without attaching duplicate nodes. A fresh iPad pass is required; this is not dismissed as a flaky assertion.
- The recap checkpoint photographed Settings during dismissal despite finding the recap in the accessibility tree. The test now requires Settings to disappear and the recap to be usable before capture.
- Reviewer instructions now identify Founder as the well-funded free start and use the current map/briefing navigation. The generated store fill-in sheet was refreshed.

The rival investigation and reproducible nine-seed measurements are in [RIVAL_BALANCE_FIX.md](RIVAL_BALANCE_FIX.md). No cash, fare, service, maintenance, aircraft-price or debt-limit subsidy was used.

Candidate `4d918ab` passed iPad shell, map-home and release tooling. All eight hosted save/StoreKit tests passed. Its stricter recap test exposed an undismissed briefing/Settings sheet; the briefing now explicitly dismisses when the session ends. Core passed the strengthened archetype benchmark but found one quick aircraft sale in the existing seed-2039 credibility regression. The cash-flow retrenchment correction above removes it in the local reproduction; the final nine-seed benchmark retains 45/45 surviving rivals and improves every archetype median over starting capital. The campaign still lost a day-control tap after the banner change. The responsive map header now creates only one time-control group instead of measuring two interactive candidates, and the journey selects a hittable matching control. The exact target-date assertion remains. These subsequent fixes still require fresh integrated CI.

Candidate `be00c89` passed **523 Core release tests**, including the unchanged rival-credibility regression and four new cash-flow cases. All eight hosted save/StoreKit tests and first-flight/follow passed. The recap visibility test still failed because its decorative container was not hittable; the XCTest trace evaluated the second half of the predicate, confirming Settings was already absent. The check now uses the visible recap caption and captures the screen before asserting, so failure evidence is retained. Full CI and this corrected UI assertion still require completion.

The `be00c89` arrival failure screenshot identifies an external obstruction: SpringBoard's “Ready for Apple Intelligence” banner covers the date and time controls. The journey now dismisses only that named simulator notification. A DEBUG-only acknowledgement records each manual-advance request synchronously, so recovery can retry an OS-intercepted tap only when the app did not receive it; a slow accepted request is never duplicated. Unknown missed taps and incorrect target dates still fail, with acknowledgement counts in the log. Earlier banner/header changes alone did not resolve this interruption.

## Release sequence

1. Resolve every current-commit Launch safety and CI failure; review the screenshot artifacts.
2. Run CI with `suite=full` and `ipad=true` on the candidate commit. The upload gate requires all five journeys and iPad to have actually run successfully.
3. Publish the support site from the reviewed commit and run `python3 scripts/check-release-readiness.py --live`.
4. Fill real seller/contact fields, complete the screenshot package, confirm StoreKit products in App Store Connect, and rehearse purchases on a physical device.
5. Test termination, recovery, upgrades, offline use, subscription changes and accessibility. Upload only after the same-commit evidence gate passes.

No merge, Pages deployment, TestFlight upload or App Store submission was performed by this implementation work.

## Accepted follow-up backlog

The remaining audit recommendations need further implementation and validation: capped offline catch-up; stronger fleet identity; connecting hubs and banked schedules; fleet commonality; bulk network management; versioned seed challenges; richer scenarios/historical starts; iCloud conflict-safe synchronization; cargo, alliances, terminals and subsidiaries. Rescue financing, flight/passenger contracts and the measured rival ownership/spending correction are implemented above, pending final candidate validation.

These changes add persistent simulation or product behavior. Each needs a concrete design, migration where applicable, economic tests and device review. They have not been silently added to the launch feature claims.

## Primary references

- [Apple required-reason API categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [StoreKit renewal states](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/renewalstate)
- [Verified grace-period deadline](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/renewalinfo/graceperiodexpirationdate)
- [StoreKit testing](https://developer.apple.com/documentation/storekittest/sktestsession)
- [Apple standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)
