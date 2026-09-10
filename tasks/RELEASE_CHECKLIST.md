# Release checklist — 10 September 2026

**Publication: blocked pending the gates below.** PRs #22 and #23 are merged. Release finalization is in PR #24; [release plan](../docs/RELEASE_PLAN.md). The [dated audit](../docs/RELEASE_AUDIT_2026-09-10.md) preserves the before-state. This is the current release work list; older phase records retain historical context.

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

- [x] **AUD-01 implementation:** Corrected probe package selection and save path in `store/artwork/README.md`; resolve the old review thread once integrated.
- [x] **AUD-02:** Clean Windows/LF checks pass without regeneration, including hosted Windows/Linux portability runs.
- [x] **AUD-03:** Windows bundle entry point fixed; positive and negative actual CLI tests pass, including paths with spaces.
- [x] **AUD-04:** Pro overrides/fixture loading guarded from Release; actual Release entitlement-isolation test passed in run `34518221910` on `11ae4d2`, with Debug fixture coverage retained.
- [x] **AUD-05:** Store capture now fails if its intended fixture is missing.
- [ ] **REL-06:** Investigate missed calendar/Pause actions. Preserve failed evidence and substantive assertions; distinguish app defect from harness/OS cause.
- [x] **AUD-06/08:** Current release pointers and #23 handoff wording reconciled; dated history preserved. Historical feature lists are labeled as historical.
- [x] PR #23 reviewed and merged at `e11cea4`; PR #24 carries follow-up release corrections.

## C. Establish the final candidate — engineering/release owner

- [ ] Record final release SHA and intended Apple marketing version. Account handoff says version 1.0; do not assume this is an already-live app update.
- [x] **REL-02 browser/HTTP:** All five official destinations return actual page content anonymously; browser privacy page inspected. Installed-device links remain in device acceptance.
- [x] **REL-02:** Live checker passes locally and on hosted Windows/Linux. An identified client resolves the default User-Agent rejection; HTTP/content validation remains enforced.
- [ ] Run full CI with `suite=full` and `ipad=true` for that exact SHA, plus Launch safety; inspect jobs and steps, not only the workflow badge.
- [ ] Run strict metadata/selftests, generated-sheet, bundle/icon, symbol/audio and artwork checks on the final tree.
- [ ] Run the exact-SHA release evidence gate. Earlier #23 passes do not satisfy a new merge SHA.
- [x] **AUD-07 retention:** Native CI/capture artifact retention increased to 45 days, past the planned launch. Retain the final archive/dSYMs and acceptance packet too.

## D. Complete the Apple account — account holder/release owner

- [x] **REL-03 account fields:** Separate US/UK official privacy URLs saved; existing published label is Data Not Collected. Final archive privacy validation remains required.
- [x] **REL-04 account fields:** App price Free; weekly/yearly auto-renewable and lifetime non-consumable IDs created with documented prices. Weekly/yearly share group level 1. US/UK localizations and Family Sharing match the plan.
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
- [x] **REL-10 account plan:** Pre-order date 16 October 2026 verified. Owner selected 173 regions, excluding China mainland/Vietnam without licenses; saved and both exclusions read back. Recheck immediately before final publication.
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

The original audit made local documentation/evidence changes only. This checklist
also records the later authorized implementation and saved Apple account changes.
Unchecked actions remain incomplete; no physical-device acceptance is implied.
