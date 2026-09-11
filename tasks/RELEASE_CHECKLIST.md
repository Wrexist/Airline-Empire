# Release checklist — 11 September 2026

**Build 1.0.16 (6) is ready; physical acceptance and publication are pending.**
PRs #22 through #26 are merged; no PRs remain open. Candidate `18253b3` passed full
CI, Launch safety and portability, then Apple processing. The app and four
purchase/group items are staged in one unsubmitted draft. See the
[current evidence](../docs/RELEASE_CONTINUATION_STATUS.md),
[release plan](../docs/RELEASE_PLAN.md) and
[owner steps](../docs/RELEASE_OWNER_STEPS.md). The
[dated audit](../docs/RELEASE_AUDIT_2026-09-10.md) preserves the before-state.

Check a box only when its acceptance evidence is linked. Apple account tasks require actual saved state, and physical-device tasks require device/OS/build results. A source change or a previous build's pass does not satisfy them.

## A. Historical baseline evidence (superseded by candidate evidence in C)

- [x] PR #22 merged: campaign isolation/recovery, Pro verification, free entry, export/import, rescue financing, contracts and launch-journey improvements.
- [x] #23's 523 Core release tests and 11 launch-safety hosted/UI tests passed.
- [x] All nine full CI jobs passed for `c65c98d`, including five iPhone journey shards and iPad. Arrival/map-home required retries; one separate direct-marker follow case skipped.
- [x] Exact-candidate GitHub release evidence script passed on 10 September.
- [x] Strict US/UK listing validation passed; four advisories remain for contextual review.
- [x] 36 localized RGB exports decoded, correct sizes/hashes verified; phone/iPad gallery overviews inspected.
- [x] Source privacy/link checks, explicit bundle validator, icon, symbols and audio assets passed.
- [x] All 48 release-tooling selftests passed after isolated Windows line-ending regeneration; clean-checkout portability remains below.

## B. Release engineering completed

- [x] **AUD-01 implementation:** Corrected probe package selection and save path in `store/artwork/README.md`; old review thread resolved after integration.
- [x] **AUD-02:** Clean Windows/LF checks pass without regeneration, including hosted Windows/Linux portability runs.
- [x] **AUD-03:** Windows bundle entry point fixed; positive and negative actual CLI tests pass, including paths with spaces.
- [x] **AUD-04:** Pro overrides/fixture loading guarded from Release; actual Release entitlement-isolation test passed in run `34518221910` on `11ae4d2`, with Debug fixture coverage retained.
- [x] **AUD-05:** Store capture now fails if its intended fixture is missing.
- [x] **REL-06:** Investigated calendar/Pause/navigation/lease observation and simulator termination failures. Original assertions and evidence retained; corrected candidate passed all five economy cases. See the current execution record and `phone-failures/economy-lifecycle.json`.
- [x] **AUD-06/08:** Current release pointers and #23 handoff wording reconciled; dated history preserved. Historical feature lists are labeled as historical.
- [x] PR #23 reviewed and merged at `e11cea4`; #24, #25 and #26 are merged with release corrections, account receipts and future archive source pinning.

## C. Establish the final candidate — engineering/release owner

- [x] Final source `18253b31333f4e7c0e9a8b9b4410cda2ea45b80d`; App Store listing 1.0, binary **1.0.16 (6)**. This is the first release.
- [x] **REL-02 browser/HTTP:** All five official destinations return actual page content anonymously; browser privacy page inspected. Installed-device links remain in device acceptance.
- [x] **REL-02:** Live checker passes locally and on hosted Windows/Linux. An identified client resolves the default User-Agent rejection; HTTP/content validation remains enforced.
- [x] Full CI `34532237542`, Launch safety `34532239981` and portability `34532242458` passed for the exact source. All job/step receipts: `docs/validation/release-2026-09-10/candidate-18253b3-ci.json`. One existing direct-marker camera case remained NOT VERIFIED; separate Follow path passed. Physical follow remains in E.
- [x] Final candidate strict metadata/generated sheet, 50 tooling selftests, six IPA-inspection selftests, bundle/icon/symbol/audio/artwork gates passed in CI and archive preflight; actual IPA inspected and dSYM UUID matched. See `../docs/validation/release-2026-09-11/binary-1.0.16-6.json` and `../docs/validation/release-2026-09-11/bundle-inspection-1.0.16-6.json`.
- [x] Exact-SHA release evidence gate passed for `18253b3` in TestFlight preflight `34579597613`. Later docs/workflow merges do not change the uploaded binary source.
- [x] **AUD-07 retention:** Native CI/capture artifact retention increased to 45 days, past the planned launch. Final IPA/dSYMs and CI/account reports copied to `C:/Users/IsacC/Airline-Empire-release-artifacts/candidate-18253b3`; installed-device acceptance packet remains in E/F.

## D. Complete the Apple account — account holder/release owner

- [x] **REL-03 account fields:** Separate US/UK official privacy URLs saved; existing published label is Data Not Collected. Actual build 6 archive privacy validation passed.
- [x] **REL-04 account fields:** App price Free; weekly/yearly auto-renewable and lifetime non-consumable IDs created with documented prices. Weekly/yearly share group level 1. US/UK localizations and Family Sharing match the plan.
- [x] Apple prices, product states, weekly introductory offer configuration and 173-region availability verified; future territory expansion off for app and all products. See `apple-territories.json` and `apple-iap-review-images.json`.
- [ ] Verify localized Apple purchase sheets and introductory eligibility on a physical device (E).
- [x] Supply genuine review images for Weekly, Yearly and Lifetime; Apple API run `34533267128` verified COMPLETE, checksums and product attachments. Add all three purchases and the subscription group to one unsubmitted iOS draft.
- [x] App version 1.0 / **1.0.16 (6)** joined the same draft; Apple shows **Items Ready to Submit (5)** and enables Submit for Review. Final submission remains pending device acceptance.
- [x] **REL-09:** Screenshot slots/order/UK inheritance, copy, review contact, 4+ age rating, content rights, export compliance and agreements/trader/regional/payment statuses verified. Saved account evidence is in the current execution record. All 20 native source captures visually inspected; see `store-capture-review.json`.
- [x] **REL-01:** TestFlight `34579597613` attempt 1 successfully archived/uploaded **1.0.16 (6)**; Apple returned VALID at 11 September 08:54:00 UTC. See `docs/TESTFLIGHT_VERSION_1_0_16.md`; older build 5 signing evidence remains historical.
- [x] Build 6 attached to App Store version 1.0 and verified after reload; Tester group assignment and build-specific test notes verified.
- [ ] Install build **1.0.16 (6)** from TestFlight and record physical acceptance below.

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
- [x] Monitoring and save-compatible hotfix procedure documented in `docs/RELEASE_OPERATIONS.md`; binary/dSYMs preserved and UUIDs matched.
- [ ] Execute release-day crash/purchase/support monitoring after publication; record actual storefront/download/product results.

## Optional work and post-release queue

- [ ] Fleet wording: summary excludes maintenance aircraft while the "Flying" filter includes assigned maintenance aircraft. Non-blocking; align wording/predicate in a later tested change.
- [ ] Featuring nomination after launch plan/assets stabilize; it is not a publication blocker.
- [ ] Storefront-size crop/readability review and unambiguous route wording; preview video/localizations/rating prompt only if prioritized.
- [ ] First-hour/fleet polish from observed friction, then capped offline catch-up, fleet identity/challenges, hub connections and bulk operations.
- [ ] Defer iCloud sync, cargo, alliances, terminals, subsidiaries and fare buckets to separately designed/tested updates.

The original audit made local documentation/evidence changes only. This checklist
also records the later authorized implementation and saved Apple account changes.
Unchecked actions remain incomplete; no physical-device acceptance is implied.
