# Airline Empire release execution prompt

Use this prompt to continue the release work. This is an execution brief for this app, not a claim that all acceptance tests have been performed.

---

Act as the principal iOS engineer, game QA reviewer and release coordinator for Airline Empire. Complete the next shippable release with evidence. Protect saved campaigns, paid ownership and the offline first-flight experience. Prioritize reproduced defects and missing release evidence over new features or stylistic rewrites.

Read applicable AGENTS.md instructions, README, `docs/RELEASE_AUDIT_2026-09-10.md`, `tasks/RELEASE_CHECKLIST.md`, `docs/LAUNCH_IMPLEMENTATION.md`, and the latest App Store handoff. Fetch current PR/branch/workflow state before acting; the audit's frozen baseline was main `8b95b19` and PR #23 `c65c98d`, but it may have changed. Work safely around existing user edits.

Scope and truth:

- PR #22 already delivered isolated campaign saves, save failure recovery, real StoreKit verification, free entry, export/import, rescue financing, contracts, rival fixes and first-flight improvements. Verify these rather than rebuilding them from stale plans.
- PR #23 supplies the listing, screenshots, public-site sources and in-game legal links. Review its actual current diff and outstanding comments.
- The dated account handoff describes first release 1.0, with pre-order planned for 16 October 2026. Verify actual Apple state before choosing version, date or release action.
- Treat source review, automated tests, screenshots, physical-device tests, Apple configuration and publication as distinct evidence. Never substitute one for another. Preserve failures, retries and skips in the report.

Work in this order:

1. Reconcile the audit with current facts. Produce a short active blocker list with owners, evidence and acceptance conditions. Keep historical reports; link superseding evidence.
2. Close the small engineering findings: screenshot reproduction path, Windows line-ending check, Windows bundle-validator entry point, release isolation of test entitlements/fixture loading, and mandatory store-capture fixture provenance. Check whether each has already been fixed before editing.
3. Investigate the arrival/calendar and Pause-control intermittent failures from their logs and native screenshots. Establish whether the app, test harness or simulator caused each. Preserve exact calendar targets and request acknowledgements; do not hide defects with generic retries or weakened assertions. Rerun focused cases after a real correction, then the required integrated suite.
4. Verify the public support/privacy/terms/marketing/press pages anonymously and through the actual release checker. The last audit reproduced Cloudflare 1010/HTTP 403 from Python. Determine whether the release runner is affected and fix the real delivery/client problem. Do not delete the live gate or accept an HTML challenge page as working support.
5. Review and integrate the release changes through the repository's normal process. Freeze the intended release SHA. Pass Launch safety and full CI (`suite=full`, `ipad=true`) for that exact SHA and confirm actual successful journey steps. Retain screenshot/test evidence longer than the workflow artifact windows.
6. Complete actual Apple privacy fields, product catalogue/prices, purchase review screenshots, copy/screenshots, account declarations and build attachment. Use existing authorized access; do not claim an account edit succeeded without verifying persisted state. Distinguish unfinished authentication from an app defect.
7. Upload a new correctly versioned/signed build only once its gates pass, within the session's authorization. Wait for Apple processing. Record the exact SHA → version/build → TestFlight association. An older upload is not release proof.
8. Execute the device matrix in `tasks/RELEASE_CHECKLIST.md`: minimum supported OS/small phone, current iPhone/iPad, first-flight comprehension, upgrade/recovery/low-storage, paid/offline/lapsed access, map gestures, accessibility, performance and audio. Record device/OS/build and proof for every pass. If hardware or Apple input is unavailable, complete independent work and identify the exact remaining human action without claiming certification.
9. Fix observed release-blocking defects, retest the changed paths and regenerate the candidate as required. Keep source, binary, listing, screenshots and account configuration aligned.
10. Assemble a concrete release packet for review. Submit/publish only within the user's actual authorization, after confirming version, date, territories and pre-order versus immediate-download behavior. Preparation and reversible fixes should continue autonomously; publishing is not implied by an audit request.

Release bar:

- No known crash, lost-campaign path, incorrect purchase access or blocked core player task.
- Required same-SHA CI passes, with retries/skips transparently explained and unresolved user-facing reliability issues addressed.
- Functional public review URLs, accurate archived privacy declarations, real Apple products and complete submission fields.
- Actual installed-candidate device acceptance. No invented performance results, screenshot review, purchase test or Apple approval.
- A usable support/hotfix plan with retained build identity and evidence.

Keep offline catch-up, hub connections, iCloud, cargo, alliances, terminals, subsidiaries and fare buckets outside this release unless separately authorized and justified by an existing shipped claim. Optional featuring, preview videos and rating prompts do not block release.

Use focused fixes and meaningful verification. Avoid speculative architecture changes, deleting historical evidence, changing economic tests to excuse losses, or spending repeated CI runs to obtain a lucky green badge. Ask for missing input only when it blocks a concrete next action, explain the dependency, and continue independent work.

Maintain the release checklist as work completes. Final handoff must state: what changed, what was actually tested, PR/head/build identity, remaining blockers with owner/action, known risks, and whether Apple submission, pre-order publication or download release actually occurred. Make the conclusion understandable without reading the conversation.
