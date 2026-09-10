# Release audit — 10 September 2026

> **Historical before-state.** Follow the [11 September execution record](RELEASE_CONTINUATION_STATUS.md)
> for completed fixes and saved Apple state. PRs #22–#26 are now merged;
> build **1.0.0 (5)** is processed and attached to the five-item review draft.
> Physical-device acceptance, final submission and publication remain pending.

**Decision: not ready to publish.** The launch implementation and store artwork are substantially complete. The remaining work is release integration, reliable runtime evidence, live legal/support access, real Apple purchase configuration, and final device acceptance. Starting another major simulation feature now would expand the release risk without closing these gates.

This is a repository, PR, CI, release-tooling and artifact audit. It is **not** a physical-device certification or a fresh inspection of the signed-in Apple account. Apple account facts below are dated handoff evidence, explicitly distinguished from checks performed today.

The repository describes a **first App Store release, version 1.0**, with pre-order planned for **16 October 2026**. There is no evidence here of a publicly released version that needs a 1.1 update. Confirm the live Apple version before assigning the next build/version. Do not interpret the user's request for a new version as authorization to change the planned launch date.

## 1. Evidence and scope

| Item | Audited state |
|---|---|
| Main | `8b95b1928a14151782f2f37210725e1a06618ea4`, merge of PR #22; local main matches fetched origin/main |
| Open release candidate | PR #23, `c65c98d1e6ff573acf6c7081f93e38408cb0250a` |
| PR inventory | 23 PRs: #1–22 merged, #23 open; no open GitHub issues returned |
| Candidate full CI | [34310565863](https://github.com/Wrexist/Airline-Empire/actions/runs/34310565863), nine successful jobs after attempt 2 |
| Candidate Launch safety | [34309158812](https://github.com/Wrexist/Airline-Empire/actions/runs/34309158812), both jobs successful; 523 Core release tests and 11 hosted/UI tests |
| Native screenshot capture | [34309158836](https://github.com/Wrexist/Airline-Empire/actions/runs/34309158836), iPhone and iPad successful |
| Last successful TestFlight workflow | [34027843211](https://github.com/Wrexist/Airline-Empire/actions/runs/34027843211), 6 September, **older** `e3d15e69da14ae31a1e2f08afbad94fa9939d9ec` |
| Release evidence script | Executed against GitHub for the candidate SHA: **passed**. This certifies its workflow requirements, not physical-device acceptance or Apple approval. |
| Environment | Windows; Python and Node available; no local Swift or Xcode command available. Swift/iOS results are inspected CI evidence, not local reruns. |

The complete PR inventory, review thread, workflow jobs and steps, screenshot hashes and gate result are retained in [evidence.json](validation/release-2026-09-10/evidence.json). Local bundle validation and dated HTTP failures are in [local-checks.json](validation/release-2026-09-10/local-checks.json).

Historical PRs were triaged by scope and merge status. Detailed review concentrated on the open #23 diff, #22's current implementation and regression coverage, and release-critical paths. This audit does not claim a new line-by-line review of every historical diff, every screen, or every economic state.

## 2. PR audit and integration order

| PRs | Delivered area | Release consequence |
|---|---|---|
| #1 | Core hardening and original QA handoff | Merged foundation; old Apple blockers are historical. |
| #2–4 | Release pipeline, listing, icon and iPad orientation fix | Merged. Signing/upload subsequently succeeded; stop listing first-upload failures as current blockers. |
| #5–8 | Crash fix, design system, audio/map work, first simulator journeys | Merged. Native listening, haptics and broad device performance remain separate evidence. |
| #9–12 | Wider UI journeys, map performance, first month/era decisions | Merged. Use current full CI rather than historical screenshots as the automation baseline. |
| #13–16 | Rival visibility, economic recommendations and demand estimation | Merged. #22 later changes player forecast assumptions and rival spending; old balance reports alone do not describe today's game. |
| #17–18 | Upload pipeline recovery, map motion and follow experience | Merged. Old upload is not a binary containing later saves, purchases or legal-link changes. |
| #19–21 | Free/Pro monetization, CI routing, map-first home | Merged. Current shell has four tabs; old five-tab plans are stale. |
| [#22](https://github.com/Wrexist/Airline-Empire/pull/22) | Campaign isolation/recovery, verified Pro, free entry, export/import, rescue financing, contracts, first-flight and balance fixes | Merged 8 September. Retain these fixes; do not reimplement already delivered features from the old roadmap. |
| [#23](https://github.com/Wrexist/Airline-Empire/pull/23) | Listing, genuine screenshot gallery, website/legal links, artwork tooling and handoff | Open, mergeable, CLEAN at audit time. One unresolved P2 review thread; green CI includes two retried journeys. Integrate after the corrections/review below. |

**#23 recommendation:** finish its small documentation/tooling corrections and review the live-link risk, then integrate it as the release preparation PR. It is not evidence that publication is ready. Any corrected head, squash or merge commit is a new SHA: the upload gate requires CI and Launch safety for that SHA. The existing candidate passes cannot simply be transferred to the merge commit.

No merges, remote review comments, workflow dispatches, Apple edits, uploads or publication were performed by this audit.

## 3. Release blockers and required evidence

Priority here describes the release decision. A missing check is not automatically an observed app defect.

| ID | Priority / evidence | Finding and required closure |
|---|---|---|
| REL-01 | P0, verified missing current workflow evidence | **No fresh processed TestFlight build for the intended release.** The last successful upload predates #22 and #23. Freeze the final SHA, pass its gates, archive/upload with the matching Apple marketing version and a new build number, wait for processing, attach that build to the version and record the SHA → build mapping. |
| REL-02 | P0, reproduced verification failure | **Public destinations fail the actual live-check client.** All five new-host pages return HTTP 403 with Cloudflare `error code: 1010` from this environment. Static source checks pass. This is not proof that browsers or Apple cannot open them. Verify anonymously on a normal browser/device and execute the same `--live` check from the release runner. Resolve hosting or client compatibility based on evidence; preserve content validation and do not bypass the gate. |
| REL-03 | P0, account state unverified | **Separate App Privacy URL and nutrition-label answers are unfinished in the handoff.** Reopen the Apple record, save/verify the current privacy URL for the supported locales, reconcile declarations with the archived app and its dependencies, and retain proof that the fields persisted. Source manifest and description URLs do not complete this Apple section. |
| REL-04 | P0, account/device state unverified | **Real Pro products and prices are not certified.** Verify app price Free, weekly/yearly subscriptions, lifetime non-consumable, subscription grouping, regional availability and introductory offer. Obtain an actual paywall review screenshot, test each product from the current TestFlight build and include the first IAPs with the app submission. A `.storekit` fixture is not the live catalogue. |
| REL-05 | P0 release acceptance, unverified device behavior | **Campaign and entitlement trust need a physical-device rehearsal.** Test upgrade from the previous distributed build, existing/legacy saves, two Pro campaigns, failed save and retry, background/termination, export/import, offline relaunch, restore, expiry/refund/revocation and preservation of owned assets after lapse. Record device/OS/build and resulting campaign identities. |
| REL-06 | P1 before publication, observed intermittent failure | **Arrival and map-home are green after retry, without an established root cause.** Attempt 1 could not reach February and could not obtain a stable/hittable Pause control. Attempt 2 passed unchanged code. Diagnose input/animation/accessibility/OS timing; retain the exact-date and acknowledgement assertions. Close with a reproduced correction or documented external cause and relevant device evidence. Repeatedly rerunning until green does not close this finding. |
| REL-07 | P1 before publication, incomplete coverage | **Supported-device and accessibility acceptance is incomplete.** Deployment target is iOS 17.0, but the inspected main simulator evidence uses iOS 26-era lanes. Exercise the minimum supported OS, a small supported phone, current iPhone and iPad, landscape and compact iPad width, VoiceOver, large text, Reduce Motion and real system appearance switching. Fix crashes, blocked actions and clipped controls. |
| REL-08 | P1 before publication, unmeasured shipping performance | **No final physical-device thermal, memory, battery or audio sign-off.** Profile a real late-game campaign at pause/1×/16×, pan/pinch/follow, save/load and background. Listen to music/cues, check silent switch, mute, interruptions, podcast coexistence and haptics. Compare against repository budgets; investigate leaks, sustained stalls, crashes and muted/background work. Simulator timing is not device FPS. |
| REL-09 | P0 at submission, account state unverified | **Final Apple submission package needs an actual account pass.** Verify selected build, screenshots/order/inheritance, review notes/contact, current age-rating questionnaire, content rights, export compliance, applicable trader/regional requirements, active agreements/tax/banking, and purchase attachments. Categories/trader/contact previously saved are handoff facts, not fresh confirmation. |
| REL-10 | P0 at publication, account state unverified | **Release mode/date/territories must be checked before the final action.** Handoff says 16 October 2026 in 175 regions, pending pre-order publication. Verify it remains true and that no selected territory would download immediately. Apple approval and pre-order publication have not been established by this audit. |

Apple requires functional review destinations and a complete deliverable submission; the [review guidelines](https://developer.apple.com/app-store/review/guidelines/) support REL-02 and the device/completeness gate. Apple documents the [separate privacy fields](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy) and [first-IAP submission alongside an app version](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase). Current uploads require the iOS/iPadOS 26 SDK or later under the [28 April 2026 requirement](https://developer.apple.com/news/?id=ueeok6yw); that is distinct from the app's minimum supported device OS. [Pre-order publication](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/publish-for-pre-order/) follows approval and can behave differently by territory.

## 4. Concrete engineering and documentation findings

These are smaller than the release gates. They should have explicit dispositions rather than being lost in another historical audit.

| ID | Finding / evidence | Action and acceptance |
|---|---|---|
| AUD-01, P2 | #23 has one [unresolved reviewer thread](https://github.com/Wrexist/Airline-Empire/pull/23#discussion_r3975430565): the screenshot reproduction command runs `swift run` at a repository root with no Package.swift. | Use `swift run --package-path AirlineEmpireCore -c release ae-rival-probe 2039 1825 ARN LHR-CDG:0.88 --snapshot-hour 12 --save store/artwork/captures/store-campaign.json`, or document the package working directory and adjusted output. Verify actual working-directory behavior on Swift before resolving the thread. The capture workflow already sets the correct directory. |
| AUD-02, P2 | Fresh Windows checkout reports a stale generated fill-in sheet: 47 selftests pass, one fails. `core.autocrlf=true`, index LF, working tree CRLF. Regeneration yields no substantive Git diff and all 48 pass. | Normalize line endings in comparison/input or add scoped `.gitattributes` rules. A clean Windows checkout and Linux CI must both pass without modifying the generated document first. This is a portability defect, not stale Apple copy. |
| AUD-03, P2 | `scripts/asc/check-bundle-config.mjs` uses `import.meta.url === file://${process.argv[1]}`. On Windows the CLI exits silently without running validation because a drive path is not a file URL. | Use Node's file-URL conversion for the entry-point check. Prove valid input succeeds and deliberately invalid input fails. Explicitly importing and calling `checkBundleConfig` during this audit returned no problems; do not count the silent CLI exit as validation. |
| AUD-04, P2 | `Entitlements.swift:99–104` accepts `-AEUITestPro` without `#if DEBUG`; the fixture loader is also called outside a DEBUG guard. Artwork docs describe the Pro fixture as DEBUG-only. | Confine entitlement overrides and fixture-loading entry points to test/debug builds, or document and review their intentional release inclusion. Check a Release build ignores Pro/fixture arguments while Debug UI journeys retain their fixtures. No ordinary App Store-user exploit was reproduced. |
| AUD-05, P2 | `StoreScreenshotUITests` silently falls back from `store-campaign.json` to a rival fixture when the intended campaign is absent. Ten captures can still be produced from the wrong source. | Require the intended fixture for store capture; fail clearly when absent. Keep the production workflow's generated save, ledger and source hashes together. Current committed screenshots' hashes pass; this is a future provenance weakness. |
| AUD-06, P2 | Planning state contradicts shipped code: CURRENT_PHASE still leads with AE-048; MASTER_PLAN lists rescue/contracts as planned; BUG-061 remains open although user-visible day wording was corrected; old text claims no successful signing or no app tests. | Maintain a dated current release dashboard. Mark historical entries superseded with links to #22 and current evidence rather than deleting their forensic record. Rescue/contracts are delivered, with remaining runtime evidence; offline catch-up is not delivered. |
| AUD-07, P2 | CI UI artifacts use three-day retention; store capture artifacts use fourteen days. Both are shorter than the remaining interval to 16 October. | Retain final native captures, failures, test summaries, archive/build IDs and device sign-off in a durable release packet. Do not rely on workflow URLs alone to preserve images. |
| AUD-08, P2 | Several reproduction/handoff statements inside #23 remain historical: artwork README says contact placeholders remain and no uploads occurred; handoff is dated 9 September while the PR description records the 10 September retry. | Reconcile the current-status paragraphs with dates and scope. Keep source-capture provenance (`cd30221`) distinct from candidate validation (`c65c98d`). |

## 5. App audit by player journey

| Area | Evidence available today | Remaining acceptance / recommendation |
|---|---|---|
| First launch and free entry | Dedicated free UI journey passes; unrelated appearance flags do not grant Pro; Founder entry is free. | Cold launch offline on device. Reach a useful map and next action without waiting for product pricing. Check first purchase prompt timing with the first-flight celebration. |
| Acquire → route → assign → fly | Current map-home journey passes after retry; acquisition, assignment, midnight schedule creation and accessible follow path are exercised. | Have a new player complete it without verbal rescue; verify usable controls and understand why departures may wait until the next schedule boundary. |
| Navigation and presentation | Four-tab shell, iPad and detailed settings journeys pass. Prior sheet/dismissal failures were fixed in #22. | Check landscape, split-width iPad, large text, modal cancellation and system appearance changes on the final build. |
| Map and follow | Production accessible follow path passes; geometry/LOD/counters have tests. | Direct aircraft-marker follow test in shell/map was **skipped** after synthetic taps selected no flight. Test direct finger selection, pan interruption, landing, stale selections and antimeridian routes manually; do not call this skipped case a pass. |
| Economy and rival credibility | 523 Core release tests, current five-test economy shard, campaign and Munich arrival evidence; #22 documents nine seeds and 45 surviving rivals. | Current suite is a regression baseline, not universal balance proof. Spot-check multiple homes, thin/long routes, lease/buy choices, runway/frequency limits and solvency advice. Avoid a wholesale rebalance without a reproduced harmful decision. |
| Progression, rescue, contracts | Rescue loan and flight/passenger contracts exist; migrations and reward/repayment regressions are included. | Play the rescue accept/decline and contract accept/complete/expire paths on device; ensure the debt cost, deadline and no-penalty terms are understandable and rewards cannot duplicate after reload. |
| Save/load/recovery | Four hosted launch-safety tests cover separate campaigns, failed save-and-quit/retry, override isolation and export/import. Source uses unique slots and bounded import size. | Upgrade/termination/low-storage/file-provider/legacy-backup rehearsals remain. A checksum protects integrity, not confidentiality; do not advertise encrypted campaign backups. |
| Paid/free boundaries | Real StoreKitTest framework exercises lifetime purchase/restore, failed purchase, pending purchase and weekly expiry. Core checks command/progression access. | Actual Apple catalogue and payment UI; yearly purchase, eventual Ask to Buy approval, grace/revocation/refund, cancellation while still entitled, offline paid relaunch, lifetime alongside an existing subscription. Preserve existing saves/assets after lapse. |
| Performance | Current simulator cold-launch sample averages about 2.85 seconds; two performance tests pass. Historical Linux benchmarks and map counters exist. | Do not translate simulator launch time or Linux year simulation into shipping-device FPS/battery claims. Collect physical-device traces against repository budgets. |
| Audio and haptics | Asset checker validates 54 cue files plus four music beds; simulator audio coverage exists. | No new listening or physical haptic pass in this audit. One-hour experience, route changes, calls, silent switch, mix restoration and muted/background work need actual ears/device measurements. |
| Accessibility | Large-text shell coverage, labelled controls and accessible flight menu exist. | VoiceOver task completion, hit targets, contrast/color-independent state and Reduce Motion on the final build. Claim only supported accessibility features verified against Apple's criteria. |
| Privacy/security | App-private UserDefaults reason CA92.1 declared; campaign export is explicit; source/legal pages describe no developer telemetry. | Inspect final archive dependencies and privacy report; verify actual account declarations. Remove accidental test entitlement paths from release as AUD-04. |

## 6. Store and marketing audit

**Passes:** both strict locale validations pass. All 36 localized PNGs decode as RGB at the expected native export sizes; all export/native hashes match; UK exports match US. There are 18 unique exports, six stories at three sizes. Content files confirm 94 airports and 14 aircraft types. Both six-panel phone/iPad overviews were inspected: coherent ordering, readable main headlines and visible Pro disclosure; the iPad compositions use their own captures.

**Limits:** this was gallery-overview inspection plus full pixel decoding, not a manual magnified inspection of every one of the 36 images. Images demonstrate selected seeded gameplay, not every advertised path. The screenshot workflow and saved native sources are historical/candidate evidence, not a physical TestFlight session. Apple upload/order/inheritance is from the handoff, not rechecked today.

**Polish, not launch-critical redesign:** the native management text and Pro footnote are small at storefront thumbnail size. Review on the App Store preview at actual phone size, especially the dense fleet/rivals screens. Keep authentic pixels and benefit-led headlines; do not rebuild the gallery solely to change taste. The first frame's “connections” wording should not imply passenger-transfer/hub-connection simulation, which remains post-launch; “routes” would be less ambiguous.

The validator emits four advisories for description URLs and free-entry wording. The explicit EULA/privacy disclosure and explanation of free/Pro access serve real customer/review needs. Treat these as contextual copy review, not proof of an Apple rejection or a reason to delete necessary disclosures blindly.

The featuring nomination is prepared but unsubmitted in the handoff. **Featuring, a preview video, extra languages and an in-app rating prompt are optional launch work**, not prerequisites for a functional submission. Submit the nomination when the release date and assets are stable; editorial selection is not guaranteed.

## 7. What to build next

The next development slice should be **release stabilization**: AUD-01–05, current planning state, and a focused investigation of the two intermittent UI actions. Preserve feature scope while closing real device defects. Release gates are organized into executable stages in [RELEASE_CHECKLIST.md](../tasks/RELEASE_CHECKLIST.md).

After the launch candidate passes:

| Order | Product work | Why it follows launch / acceptance needed |
|---|---|---|
| 1 | First-hour comprehension and fleet identity polish from observed sessions | Improve successful first flights and decisions; measure where players stall before adding screens or systems. |
| 2 | Capped offline catch-up (AE-050) | Needs clock/rollback policy, bounded work, save migration if necessary, honest recap and economic tests. The current offline claim means playable without network, not automatic progress while closed. |
| 3 | Fleet identity/artwork and richer scenario/seed challenges | Existing aircraft classes share art; strengthen attachment and replay value without pretending aircraft-level profit is already measured. |
| 4 | Hub connections/banked schedules (AE-054), fleet commonality, bulk network operations | Real simulation/data changes; design costs, allocation and migrations and run economic regressions before adding claims to the listing. |
| 5 | Conflict-safe iCloud sync, cargo, alliances, terminals, subsidiaries and fare buckets | Separate expansions with explicit save/network/support implications. None should hold up this release unless a current advertised claim depends on it. |

Rescue financing, flight/passenger contracts, separate campaigns and export/import do **not** belong on a “not built” list: they are already in merged #22. New languages/paid models also need explicit scope decisions; they are not hidden release requirements.

## 8. Completion criteria and handoff

An honest release packet identifies: final SHA, exact marketing/build numbers, green required workflows and recorded retries/skips, decoded and reviewed native screenshots, live legal/support checks, final archive validation, Apple product/account/build state, device test results, unresolved issues and release/date/territory decision. Any subsequent source change requires appropriate retesting and a fresh matching binary.

Use [RELEASE_EXECUTION_PROMPT.md](RELEASE_EXECUTION_PROMPT.md) to continue the work. It requires evidence for closure and carries the existing launch scope forward. It does not turn a configured pre-order or green CI run into an approved, published release.
