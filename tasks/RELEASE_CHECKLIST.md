# Release checklist — 10 September 2026

**Publication: blocked pending the gates below.** Baseline: main `8b95b19`; open PR #23 `c65c98d`. Evidence and priorities: [release audit](../docs/RELEASE_AUDIT_2026-09-10.md). This is the current release work list; older phase records retain historical context.

Check a box only when its acceptance evidence is linked. Apple account tasks require actual saved state, and physical-device tasks require device/OS/build results. A source change or a previous build's pass does not satisfy them.

## A. Already delivered and verified at the recorded candidate

- [x] PR #22 merged: campaign isolation/recovery, Pro verification, free entry, export/import, rescue financing, contracts and launch-journey improvements.
- [x] #23's 523 Core release tests and 11 launch-safety hosted/UI tests passed.
- [x] All nine full CI jobs passed for `c65c98d`, including five iPhone journey shards and iPad. Arrival/map-home required retries; one separate direct-marker follow case skipped.
- [x] Exact-candidate GitHub release evidence script passed on 10 September.
- [x] Strict US/UK listing validation passed; four advisories remain for contextual review.
- [x] 36 localized RGB exports decoded, correct sizes/hashes verified; phone/iPad gallery overviews inspected.
- [x] Source privacy/link checks, explicit bundle validator, icon, symbols and audio assets passed.
- [x] All 48 release-tooling selftests passed after isolated Windows line-ending regeneration; clean-checkout portability remains below.

## B. Finish the release preparation PR — engineering

- [ ] **AUD-01:** Correct screenshot probe working-directory instructions; verify output path and resolve the one open #23 review thread after the fix.
- [ ] **AUD-02:** Make generated metadata checks pass on clean Windows/LF checkouts without regeneration.
- [ ] **AUD-03:** Fix the Windows bundle-check entry point; demonstrate both real success and real failure.
- [ ] **AUD-04:** Keep Pro overrides/fixture loading out of Release, or record an explicit reviewed disposition; retain Debug fixture coverage.
- [ ] **AUD-05:** Require the intended campaign fixture for store captures.
- [ ] **REL-06:** Investigate missed calendar/Pause actions. Preserve failed evidence and substantive assertions; distinguish app defect from harness/OS cause.
- [ ] **AUD-06/08:** Reconcile current phase, bug/debt status and #23 handoff wording; preserve dated history.
- [ ] Review the final #23 diff and integrate it through the normal repository process.

## C. Establish the final candidate — engineering/release owner

- [ ] Record final release SHA and intended Apple marketing version. Account handoff says version 1.0; do not assume this is an already-live app update.
- [ ] **REL-02:** Confirm all five website destinations load correct content anonymously on device/browser.
- [ ] **REL-02:** Run `python3 scripts/check-release-readiness.py --live` from the release environment; resolve the observed 403/Cloudflare 1010 without removing validation.
- [ ] Run full CI with `suite=full` and `ipad=true` for that exact SHA, plus Launch safety; inspect jobs and steps, not only the workflow badge.
- [ ] Run strict metadata/selftests, generated-sheet, bundle/icon, symbol/audio and artwork checks on the final tree.
- [ ] Run the exact-SHA release evidence gate. Earlier #23 passes do not satisfy a new merge SHA.
- [ ] **AUD-07:** Preserve test reports/native screenshots/failure diagnoses in a durable packet beyond the 3-/14-day artifact windows.

## D. Complete the Apple account — account holder/release owner

- [ ] **REL-03:** Save/verify separate App Privacy policy URLs and nutrition labels against the final archive.
- [ ] **REL-04:** Confirm app price Free and all three exact product IDs: `com.airlineempire.game.pro.weekly`, `.yearly`, `.lifetime`; subscriptions and non-consumable must be configured correctly.
- [ ] Verify localized prices, regional availability, weekly introductory offer and eligibility behavior; record Apple product states.
- [ ] Supply a genuine paywall screenshot for purchase review and attach required first IAP/subscription submissions with the app version.
- [ ] **REL-09:** Recheck uploaded screenshot slots/order/UK inheritance, copy, contact, age rating, content rights, export compliance and applicable agreements/trader/regional/payment requirements.
- [ ] **REL-01:** Archive/upload the final SHA with a fresh build number; wait for successful processing; record SHA/version/build/processing evidence.
- [ ] Attach the processed build to the intended App Store version and install it from TestFlight.

## E. Accept the installed build — QA/product owner

Record each result with device model, OS, build, date, steps, pass/fail and artifact. Simulator results remain separate.

- [ ] **REL-07:** Small supported iPhone and minimum iOS 17 baseline; current iPhone; iPad portrait/landscape/compact width. Test actual system light/dark changes.
- [ ] New free player: offline launch → aircraft → route → assignment → midnight schedule → first departure/arrival → statement → save/continue; no explanatory intervention required.
- [ ] **REL-05:** Upgrade previous distributed build with existing saves; load legacy/backup saves; alternate two Pro campaigns; repeated save/quit/relaunch keeps their identity.
- [ ] Failed save/low storage retains live play and supports retry; background/force termination loses no more than the documented checkpoint; export/import/corrupt/future-version files behave safely.
- [ ] Weekly/yearly/lifetime purchases, cancellation/pending/approval, restore/reinstall, expiry/grace/refund/revocation and offline paid relaunch; free/lapsed campaigns preserve earned assets.
- [ ] Direct map selection, accessible follow, pan/pinch interruption, landing, stale-selection recovery and antimeridian route behavior.
- [ ] VoiceOver completes core tasks; large text retains controls; Reduce Motion and color-independent status work.
- [ ] Rescue accept/decline and contract complete/expire/reload; player understands debt/deadline and no duplicate rewards.
- [ ] Representative late-game 1×/16×/pause session with Instruments: memory, frames, CPU, heat/battery, save/load and background behavior assessed against repository budgets.
- [ ] Audio/haptics listening: mute/silent switch, interrupts, background, external audio and restored mix; no crash or unwanted ongoing sound/work.
- [ ] Triage all findings. No unresolved crash, data-loss, purchase-access or core-task blocker; document any accepted lesser issue.

## F. Submit and publish — release owner

- [ ] Assemble final acceptance packet, known issues and exact build identity; confirm every mandatory gate above is closed.
- [ ] **REL-10:** Verify current date/mode/territories. Dated handoff is pre-order on 16 October 2026 in 175 regions, pending publication; recheck in Apple.
- [ ] Submit the complete app and required purchases for App Review; record submission state.
- [ ] Resolve review feedback on the actual candidate; if the binary changes, repeat relevant gates.
- [ ] After approval, confirm the final publication action matches the intended pre-order/download behavior in every territory.
- [ ] Publish using the authorized release decision; verify public listing and store product access, then scheduled download availability.
- [ ] Establish release-day crash/purchase/support monitoring and a saved-campaign-safe hotfix procedure; preserve dSYMs/build artifacts.

## Optional work and post-release queue

- [ ] Featuring nomination after launch plan/assets stabilize; it is not a publication blocker.
- [ ] Storefront-size crop/readability review and unambiguous route wording; preview video/localizations/rating prompt only if prioritized.
- [ ] First-hour/fleet polish from observed friction, then capped offline catch-up, fleet identity/challenges, hub connections and bulk operations.
- [ ] Defer iCloud sync, cargo, alliances, terminals, subsidiaries and fare buckets to separately designed/tested updates.

The audit itself made local documentation/evidence changes only. It did not execute the unchecked external actions.
