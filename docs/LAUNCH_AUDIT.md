# Airline Empire: launch audit and implementation roadmap

Prepared 7 September 2026 for Isac Molin. Priority: shortest credible path to a polished App Store release.

## Verdict

**Do not submit this candidate yet. The game has enough underlying systems for a substantial first release. Its immediate weaknesses are save safety, paid-feature correctness, submission assets, and incomplete runtime verification.**

Freeze major feature development while resolving the release findings below. Keep the map-first direction. Improve the journey from founding an airline to watching its first profitable operation. Defer the new investor, offline simulation, and hub-connection systems until the existing product can be sold and played reliably.

This audit makes no claim that every possible defect has been found. It combines source inspection, local release checks, live GitHub workflow evidence, and inspection of seven simulator screenshots. Runtime defects inferred from source are explicitly distinguished from reproduced failures. No application code, repository settings, purchases, or releases were changed.

## 1. What was audited

| Item | Baseline |
|---|---|
| Repository | [Wrexist/Airline-Empire](https://github.com/Wrexist/Airline-Empire) |
| Main branch at inspection | `fd078ea49ffa02bf6ce8e49e3b558a0804005a6b` |
| Candidate | [Open PR #21](https://github.com/Wrexist/Airline-Empire/pull/21), `27580a2edacf5e779962b4bb42338bcbb32d0a5f` |
| PR branch | `claude/ae-048-map-home-screen-uvtp09` |
| Inventory | 37 app Swift files, 79 Core/executable Swift files, 53 Core test files, 7 UI-test files |
| Content | 94 airports, 14 aircraft types, 3 starting scenarios, 5 eras |
| Inspected surfaces | App lifecycle, saves, monetization, navigation, map/home, onboarding, aircraft and route selection, simulation and economy seams, progression, content, tests, CI, release tooling, listing, privacy/support pages, existing bug/debt registers |
| Not directly exercised | Physical iPhone/iPad play, VoiceOver, StoreKit sandbox transactions, Instruments, private App Store Connect configuration |

Swift/Xcode were not available on this audit host. The Core test result below is verified from the remote CI log, not represented as a local rerun. Existing economic experiments are cited as repository evidence rather than claimed as experiments newly executed for this audit.

The owner's earlier direction document says “build the big version” without a launch clock. This report follows the newer instruction to prioritize launch. The larger direction remains a backlog, not a requirement to complete all planned phases before 1.0.

### Current evidence, corrected

| Evidence | Actual conclusion |
|---|---|
| [Latest CI, run 34155243731](https://github.com/Wrexist/Airline-Empire/actions/runs/34155243731) | Core: **506 tests passed**, release Core build passed, release-tooling checks passed, iOS simulator compilation passed. UI tests and iPad were skipped. |
| [Full UI run 34155113814](https://github.com/Wrexist/Airline-Empire/actions/runs/34155113814) | Arrival, map-home, campaign, and shell/map jobs passed. Economy and iPad jobs failed. The dedicated follow-camera test skipped. |
| Code difference between those runs | The later commit changes only `docs/AE048_FINAL_REPORT.md`. The failed full run therefore covers the same application code as the latest green candidate. |
| [TestFlight run 34027843211](https://github.com/Wrexist/Airline-Empire/actions/runs/34027843211) | September 6: archive, export, upload to App Store Connect, and processing all succeeded for `e3d15e69da14ae31a1e2f08afbad94fa9939d9ec`. |
| Old membership/signing blocker | Superseded by that successful upload. It should not be presented as the current blocker. This is evidence of successful signing then, not a live inspection of today's account page. |
| Current listing validator, run locally | **Exit 1: five errors**, all unresolved contact/copyright placeholders. Also warns that screenshots are absent. |
| Other local checks | 47 release-tooling selftests passed. Bundle configuration, app icon, and app-symbol checks passed. |

**A green compile-only workflow is not a green release rehearsal. A processed TestFlight build is not evidence of App Review approval.**

## 2. Existing feature inventory

“Implemented” below means code/content exists. It does not automatically imply physical-device or purchase verification.

| Area | What already exists | Launch assessment |
|---|---|---|
| Founding | Airline name, livery, curated or custom home, world seed | Good foundation. Test the ordinary free-player defaults. |
| Difficulty | Founder: $90M/4 rivals. Entrepreneur: $60M/5 rivals. Magnate: $35M/6 rivals | Founder is free. UI journeys generally use Pro/Entrepreneur, a different first experience. |
| World | 94 airports across nine regions, geography, distances, airport constraints and seasonality | Enough content for launch. More airports are low priority. |
| Home map | Four-tab shell, map as Home, briefing sheet, state strip and contextual next action | Keep. This is the strongest coherent product direction. |
| Map interaction | Pan, pinch, zoom buttons, airport/route/aircraft selection, overlays and route arcs | Substantial implementation. Follow-camera verification remains incomplete. |
| Atmosphere | Night/day presentation, city lights, airport activity, storms, aircraft motion | Existing work should be profiled on a phone before adding more effects. |
| Fleet | 14 fictional aircraft, acquisition gates, buy new/used, leasing, aircraft details | Market ordering is poor for a first purchase. |
| Fleet operations | Assignment, wear, reliability, maintenance, depreciation and disposal | Protect with lifecycle and long-session checks. |
| Routes | Open/close, fares, frequencies, aircraft assignment, runway/range/slot checks | Core commands validate actions. Improve how choices are introduced. |
| Flight simulation | Scheduling, boarding, travel, arrival, turnaround, delays/cancellations and repositioning | Real simulation exists behind the map. |
| Demand | Business/leisure demand, price sensitivity, competitive offer allocation, seasonality and world economy | Good foundation. Forecast configuration is still inconsistent with the operation opened. |
| Finance | Flight economics, ledger, monthly statements, route P&L, payroll, overhead, loans/interest | Strong differentiator if the summary labels stay honest. |
| Reputation/service | Service tiers and operating-performance effects on reputation/demand | Already supplies meaningful depth without a new subsystem. |
| Rivals | Five AI archetypes, route/fleet decisions, pricing, entries, exits and collapse | Known archetype imbalance needs explicit acceptance or correction. |
| World events | Fuel/economic changes, storms, tourism booms and strikes | Enough variety to support a first release. |
| Progression | Startup → Regional → National → International → Empire, shared era requirements | Good code/UI seam, but the free-tier stopping behavior needs correction or honest disclosure. |
| Goals | Milestones, achievements, capability programs, tourism-boom missions | Existing mission foundation is narrower than the planned contract system. |
| Guidance | Onboarding checklist, next moves, market opportunities, advisories, daily digest and rival signals | Retain and consolidate. Advice must match the player's actual setup. |
| Failure | Solvency warnings, administration/fire-sale behavior and terminal collapse | Investor rescue is still planned. Existing warnings are the launch baseline. |
| Time | Pause, 1×, 4×, 16×, manual day advance | Listing still says up to 4×. “Morning” currently means midnight. |
| Persistence | Versioned JSON envelope, checksum, backup rotation, recovery, migrations, autosave/manual save/load/delete | Storage machinery is substantial. Campaign-slot integration is unsafe for the advertised multiple-airline feature. |
| Audio/haptics | Audio engine, soundscape/feedback routing, settings and haptics | Check on-device interruption, mute and background behavior. |
| Accessibility | Labels, Reduce Motion handling, Dynamic Type adaptations and iPad shell | Partial evidence. VoiceOver and supported smaller/older device surfaces remain unproven here. |
| Monetization | StoreKit weekly/yearly/lifetime Pro products, paywall, restore, contextual gates and presentation history | Highest concentration of launch defects and missing end-to-end coverage. |
| Release | XcodeGen, CI, signing/upload/processing, metadata scripts, icon, website source and review notes | Proven upload plumbing. Public legal pages and submission package need completion. |

Core seams: [systems](https://github.com/Wrexist/Airline-Empire/tree/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireCore/Sources/AirlineEmpireCore/Systems), [session/read models](https://github.com/Wrexist/Airline-Empire/tree/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireCore/Sources/AirlineEmpireCore/Session), [content](https://github.com/Wrexist/Airline-Empire/tree/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireCore/Sources/AirlineEmpireCore/Resources).

## 3. Release findings, in implementation order

Priority labels: **Block** means resolve before submission or selling the affected claim. **High** means complete during the launch stabilization pass. **Later** means it can follow launch if honestly described and acceptable in testing.

### R01 · Block · Multiple paid campaigns share the same autosave slot

**Evidence: confirmed source path, not a device reproduction.** `ContentAccess` permits unlimited new campaigns for Pro. `NewGameView` promises keeping the existing airline while starting another. Yet founding, loading, background saving, “Save now,” and “Save and quit” ultimately use the same `auto` slot. No production UI call supplies a unique campaign slot.

Starting campaign B and saving it replaces campaign A's current autosave. Backup rotation may temporarily retain A, but subsequent saves displace it. Backups are not independently selectable campaigns. The advertised “Unlimited airlines” benefit is therefore not delivered by the current app wiring.

**Fix:** establish an active campaign ID/slot when founding and retain it when loading. Route all explicit and automatic saves to that slot. Migrate the legacy `auto` directory safely. Count campaigns, not backup generations, for the free limit.

**Acceptance:** create A, save, create B, save repeatedly, relaunch, independently resume both with correct state. Resume A and background it without altering B. A failed migration preserves original files.

[GameController](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireApp/Sources/App/GameController.swift), [save store](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireCore/Sources/AirlineEmpireCore/Persistence/SaveStore.swift), [paywall benefit](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireCore/Sources/AirlineEmpireCore/Monetization/PaywallContent.swift).

### R02 · Block · “Save and quit” discards the live session even when saving fails

**Evidence: confirmed source path.** `saveAndQuit` awaits `save`, captures the success/failure outcome, and calls `quitToMenu()` unconditionally. The notification is preserved, but the unsaved in-memory session is gone.

**Fix:** have saving return a result. Quit automatically only after success. On failure, preserve the game and offer Retry, Keep playing, and an explicit discard option.

**Acceptance:** inject a write failure. Save-and-quit must leave the airline playable and retryable. Successful retry must restore the exact expected state after relaunch.

[GameController, saveAndQuit](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireApp/Sources/App/GameController.swift#L493).

### R03 · Block · Privacy manifest contradicts API usage

**Evidence: confirmed source.** `PrivacyInfo.xcprivacy` has an empty required-reason API array and explicitly claims the app does not use UserDefaults. `Entitlements`, player preferences and audio settings do use it.

**Fix:** declare the UserDefaults category and the approved reason matching the actual app-private settings usage. `CA92.1` is the relevant documented reason for app-only reads/writes. Audit other required-reason APIs rather than adding speculative declarations. Inspect the final archive's manifest.

**Acceptance:** the bundled manifest declares the APIs actually used and the incorrect comments are removed. Add a small source/manifest consistency gate so a future preference setting cannot silently reintroduce this mismatch.

[Manifest](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireApp/Resources/PrivacyInfo.xcprivacy). Apple requires a declaration for each used required-reason category: [Apple documentation](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [approved API reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

### R04 · Block · Legal links are broken and privacy copy predates purchases

**Evidence: direct HTTP requests.** The paywall's exact `/airline-empire/terms` and `/airline-empire/privacy` links returned 404, as did the listing's `/airline-empire/support` URL. The uppercase repository-style privacy/support paths checked as alternatives also returned 404. `site/` contains no terms page.

The repository privacy page says there are “no purchases” and no required-reason API use. Both contradict the current source. The blanket promise of no network activity also needs to distinguish offline gameplay from StoreKit commerce and external legal links.

**Fix:** host a working privacy page, terms/EULA destination, and support page, then make app and listing URLs agree. Explain local saves/settings and Apple-handled purchases accurately. Check the actual collection behavior before updating App Store privacy answers. Using UserDefaults alone does not mean collecting user data.

**Acceptance:** tap every legal/support link from the installed release candidate and verify the page, not merely a successful HTTP code. Pages contain current contact details and accurate purchase/privacy language.

[Paywall URLs](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireCore/Sources/AirlineEmpireCore/Monetization/PaywallContent.swift#L178), [privacy source](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/site/privacy.html). Apple's completeness, privacy and subscription disclosures apply: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

### R05 · Block · Purchase failure and pending approval have no visible outcome

**Evidence: confirmed source.** `purchase()` sets `.failed(...)` or `.pending`. The paywall only binds an alert to `.nothingToRestore`. No other app consumer of these purchase outcomes was found. Restore also catches sync errors and proceeds to “nothing to restore,” potentially giving a network failure the wrong explanation.

**Fix:** display actionable purchase-error and pending-approval states. Distinguish restore failure from a successful check finding no entitlement. Keep pending approvals listening for transaction updates. Do not nag on ordinary cancellation.

**Acceptance:** cancelled, failed, pending, successful, already-owned, restored, and offline-restore cases each show the right state. Approved pending purchases unlock once and dismiss correctly.

[Entitlements](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireApp/Sources/Monetization/Entitlements.swift), [PaywallView](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireApp/Sources/Monetization/PaywallView.swift).

### R06 · Block · Normal UI journeys bypass the free game and real purchases

**Evidence: confirmed configuration and test inventory.** Any `-AEUITest...` launch argument makes the app Pro unless explicitly overridden with `-AEUITestFree`. No free-tier purchase journey was found in the seven UI-test files. The StoreKit fixture is attached to the scheme's run action, not explicitly to its test action.

This explains how hundreds of green Core tests coexist with R01 and R05. Core tests validate policy values, not the app's StoreKit/persistence integration. Most runtime evidence also starts with Entrepreneur's $60M, while a new free player starts Founder with $90M.

**Fix:** add a small dedicated free/commerce suite, using `SKTestSession` or an explicitly configured StoreKit test action. Separately verify actual App Store product availability and purchases in sandbox/TestFlight.

**Acceptance:** ordinary free launch → decline → first flight → free boundary → purchase → unlock → save → relaunch → restore. Include campaign B and a lapsed subscription. Confirm all offered product IDs exist in App Store Connect. That private configuration was not verified here.

[Override logic](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireApp/Sources/Monetization/Entitlements.swift#L112), [scheme](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireApp/project.yml).

### R07 · High · The era wall stops speed controls but not day advance

**Evidence: confirmed source path.** `setSpeed` refuses a non-paused speed beyond the entitlement ceiling. `advanceToNextMorning` has no matching check and directly advances the session. Both time-control surfaces expose it. The era bar is an inset, not an interaction-blocking screen.

**Fix:** put the shared entitlement decision at every app time-advance entry point, retaining Core's independence from StoreKit. Make blocked actions explain the boundary. Also test that queued advances cannot cross it repeatedly before UI refresh.

**Acceptance:** load a free account's National-era save. Speed controls and repeated morning advances must follow the same defined access policy. Buying Pro changes that policy without relaunch.

[Controller](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireApp/Sources/App/GameController.swift#L585), [time controls](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireApp/Sources/DesignSystem/Components.swift).

### R08 · High · “Keep flying for free” conflicts with freezing the campaign on progression

**Evidence: confirmed product/code mismatch.** The free-game copy promises an untimed regional airline. The implementation automatically earns the next era, then pauses the entire clock when that era exceeds Regional. A successful player can therefore lose the ability to continue the regional airline they already built.

**Fix choice for launch:** either keep the regional operation playable while explicitly gating expansion, or plainly describe this as a progression-limited demo before the boundary. The former is better aligned with the existing promise but has a larger implementation/testing scope. Fixing R07 alone makes this product mismatch more visible.

**Acceptance:** a tester understands what happens before reaching the boundary. Declining never deletes or corrupts the campaign. Paid and lapsed access behavior is described truthfully.

[ContentAccess](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireCore/Sources/AirlineEmpireCore/Monetization/ContentAccess.swift), [era ceiling](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireApp/Sources/App/GameController.swift#L842).

### R09 · Block · The full UI release gate is still red

**Evidence: observed CI failures on identical app code.** In run 34155113814:

- Economy: `testNewYorkAdviceIsWorthFollowing` failed because the sunrise control could not reach March 2031.
- iPad: `testFoundingAnAirlineReachesEveryTab` could not request a screenshot because the target app did not exist at that moment. This alone does not establish whether the cause is a crash, termination, or test infrastructure.
- Flight-following: the dedicated test skipped after synthetic taps failed to select an aircraft.

**Fix:** diagnose the two failures using result bundles/process evidence. Make follow selection deterministic or exercise the visible Home follow action, then verify camera lock and release. Do not convert a critical path to an optional assertion to get a green badge.

**Acceptance:** full UI and iPad evidence on the final candidate, no unexplained failures or critical skips. A release gate should state which suites actually ran.

[Full run](https://github.com/Wrexist/Airline-Empire/actions/runs/34155113814), [CI configuration](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/.github/workflows/ci.yml).

### R10 · Block · Repository submission package is incomplete

**Evidence: locally reproduced validator failure.** Review first name, last name, email, phone and copyright are still `REPLACE_ME`. `store/screenshots` contains a README but no submission screenshots. These are repository facts; the live App Store Connect listing may have separately entered values and was not inspected.

**Fix:** fill verified account/contact values, capture real candidate screenshots for the supported iPhone/iPad families, and run strict validation. Do not guess the legal publishing entity from the user's other businesses.

**Acceptance:** strict validator exits zero, screenshots match the submitted binary, the current App Store Connect record is reconciled with repository metadata, and review notes explain Pro.

[Store config](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/store/config.json), [screenshots directory](https://github.com/Wrexist/Airline-Empire/tree/27580a2edacf5e779962b4bb42338bcbb32d0a5f/store/screenshots).

## 4. First-session and technical weaknesses

### R11 · High · The first aircraft shop presents the wrong decision

**Observed in screenshot, confirmed in source.** The first shop frame leads with the locked 422-seat Avionne AV-420 Imperial. Default sorting is seats and locked aircraft remain visible. The player has just been told to obtain a starter aircraft, then arrives at aspirational content they cannot use.

**Launch fix:** default first-session entry to eligible aircraft, with a small starter comparison and a “Show full catalogue” option. If a route is known, carry it into the market and name why each candidate fits. Keep lease payment, upfront price and ownership differences visible. Do not attach a “best” recommendation until R12 is addressed.

**Acceptance:** a new free player can locate and acquire a usable starter without discovering sorting/filter controls. The first visible option is usable for the intended operation.

[FleetView](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireApp/Sources/Screens/FleetView.swift#L859).

### R12 · High · Forecasts describe a busier schedule than the default route

**Confirmed call mismatch; impact measured by earlier repository experiments.** `MarketOpportunities.airframeResult` uses an estimator whose rotation default is maximum aircraft utilization. `OpenRouteSheet` defaults to two round trips. TD-036 reports aircraft-ranking agreement of 4/12 markets under mismatched assumptions versus 11/12 when both sides use two rotations.

Those numbers were not remeasured in this audit, but the mismatching call/default remain present. TD-035 separately documents optimistic schedule-completion assumptions. Advice can therefore be confidently worded while describing an operation the player did not create.

**Launch fix:** pass intended frequency into player forecasts and show its assumptions: aircraft, fare, rotations, lease/payroll inclusion, and excluded company overhead. Avoid globally retuning every AI strategy in the same patch. Use conservative wording where disruption uncertainty remains.

**Acceptance:** for curated homes and risky markets, the suggested aircraft and opening frequency match what the UI actually creates. Compare forecast with a full month's ledger and label material remaining approximation.

[Estimator call](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireCore/Sources/AirlineEmpireCore/Session/MarketOpportunities.swift), [TD-035/036](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/tasks/TECH_DEBT.md#L891).

### R13 · High · First revenue and first company profit need different explanations

The route-detail screenshot correctly says no aircraft is assigned, but then presents several sections of zeroes. The briefing's first-revenue milestone is useful, yet a ticket sale, positive direct route contribution, and company net profit are different achievements.

**Launch fix:** make the next executable action prominent beside an idle-route warning. After first revenue, explain the next financial milestone in one line. Show “Awaiting first flight/day close” where a zero is not yet an informative result. Keep the full ledger available below.

**Acceptance:** a new tester can explain why cash changed, why a route can earn revenue while the airline loses money, and what to do next without opening documentation.

### R14 · High · “Advance to next morning” actually lands at 00:00

**Confirmed implementation; existing BUG-061.** `GameSession.advanceToNextMorning` targets next midnight. Operating-day start is 360 minutes, or 06:00. Repeated advances therefore present midnight as morning and can make the living map feel inactive.

**Smallest launch fix:** rename the action to “Advance one day” or “Next day” if midnight is intentional. If retaining the sunrise promise, advance to the next defined operating morning using the simulation's authoritative tuning and test boundary cases.

[GameSession](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireCore/Sources/AirlineEmpireCore/Session/GameSession.swift).

### R15 · High · Subscription lifecycle has unverified refresh edges

**Source risk, not a reproduced billing failure.** Startup refreshes entitlement before loading products. Billing/grace status lookup depends on those products being loaded, and product loading does not itself repeat entitlement refresh. The scene-active path also does not explicitly refresh entitlement. Time-based expiry is computed from `Date()` without a dedicated observable expiry transition.

**Fix:** refresh after product loading and on foreground return, with explicit handling for expiry/grace/retry and an appropriate observable transition. Handle verified transaction states consistently. Never assume a local fixture proves sandbox behavior.

**Acceptance:** purchase, relaunch offline, expire while foregrounded, background through expiry, cancel renewal, enter/leave grace, refund/revoke, and restore on another device. Each must match the stated access policy.

### R16 · High · Save durability needs a real interrupted-session rehearsal

Background saving starts an asynchronous task. No explicit background execution allowance was found in the inspected app lifecycle. Periodic autosave is every seven game days, which is 42 minutes at 1×, though scene transitions also request saves. Source alone cannot establish whether a particular device suspension will lose a save.

**Fix:** prove save completion under background/termination pressure. Add a founding checkpoint and suitable checkpoints around costly irreversible decisions if tests show a gap. Keep failed writes visible and recovery non-destructive. Do not treat ordinary app backgrounding and abrupt process termination as the same guarantee.

**Acceptance:** save/load during active flights, at month close, after a purchase and immediately after founding. Exercise backup recovery and v10/v11 save migration to current v12. Preserve files after an unsupported-version refusal.

### R17 · High · First-run paywall arrives before the game demonstrates value

The app offers Pro after founding, before the first aircraft/flight. This is a product judgment, not a measured conversion result. For the current calm builder direction, asking for a recurring payment before the player sees the airline operate is a weak opening.

**Recommendation:** let the first flight and first meaningful result happen before an unsolicited offer. Keep contextual upgrade access and a readily dismissible offer. Measure the complete free journey before optimizing paywall frequency.

### R18 · Later, with launch guard · Rival strategy balance is uneven

TD-038 reports low-cost rivals with zero median terminal value and expansionists below their starting capital. The current test explicitly permits only four of five archetypes to have positive medians. Therefore 506 passing tests should not be translated into “every business strategy is viable.”

**Launch decision:** ensure curated starts produce credible competition through the first hours. Do not market low-cost strategy parity until demonstrated. After launch, diagnose archetype ledgers and scheduling/pricing behavior rather than compensating with arbitrary extra cash.

[Debt register](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/tasks/TECH_DEBT.md#L1033), [balance tests](https://github.com/Wrexist/Airline-Empire/blob/27580a2edacf5e779962b4bb42338bcbb32d0a5f/AirlineEmpireCore/Tests/AirlineEmpireCoreTests/BalanceTests.swift).

### R19 · High · Device polish is only partially evidenced

Inspected frames show readable standard management screens and a stacked accessibility-size Home layout. They do not prove every viewport, touch target, VoiceOver path, or thermal condition. At accessibility size the briefing occupies much more of the map. The standard screenshot's date is abbreviated, but that frame also includes a test-only extra time button, so it is not proof of the identical production layout.

**Launch check:** smallest supported phone layout, a current iPhone, iPad portrait/landscape and narrow multitasking width, large text, Reduce Motion, light/dark, and VoiceOver through the first playable loop. Test the paywall at large text, including close, plan, commitment, restore and legal links. A layout surviving is not the same as comfortably reading it.

### R20 · Later, with launch guard · Performance metrics do not yet certify phone performance

The existing AE-048 report records roughly 9–11 ms average map draw cost during interactions and a 243.55 ms worst opening frame on one simulator run. Those are draw-probe metrics, not full frame presentation time or device energy measurements. The report itself notes the comparison is not a controlled A/B.

**Launch check:** a 20–40 minute physical-device session, then a mature network at 16× while panning, zooming, opening finance and saving. Profile actual hitches, memory growth and thermal/energy behavior. Only optimize a measured bottleneck. Avoid a renderer rewrite before release.

### R21 · High · Documentation and sales copy disagree with the product

Examples: README says the app has never compiled, the go-live guide still foregrounds the resolved membership blocker, status tables mix old pending outcomes with later evidence, listing says 4× while the app offers 16×, privacy says no purchases, and the store description implies hubs/fleet commonality already matter even though hub connections are explicitly deferred.

**Fix:** one short release-status document with candidate SHA, tested suites, build number, blockers and owner actions. Label historical audit results as historical. Reconcile every store claim with an implemented and verified behavior. Explain that offline gameplay currently pauses when the app is closed; capped offline catch-up is not implemented.

## 5. Monetization recommendation

For a launch-first release, **a substantial free slice plus a clearly priced one-time Pro unlock is the simplest fit** for the current offline content model. Lifetime entitlement code already exists. This is a product recommendation, not a demonstrated revenue optimum, and no live prices were verified.

Weekly/yearly subscriptions add expiry, grace, renewal, restoration, disclosure, and ongoing-value obligations. Apple's subscription guideline requires ongoing value, with examples including substantive updates and new game content. This does not establish that the current game would be rejected, but a subscription needs a credible recurring benefit and flawless lifecycle behavior. [Apple subscription guidelines](https://developer.apple.com/app-store/review/guidelines/#subscriptions).

If subscriptions remain, keep them within this launch scope only after R05/R06/R08/R15 pass. If simplifying the offer, continue honoring any previously purchased entitlements and first determine whether any real customers already hold them. Do not remove access from existing buyers.

Do not add ads, premium currency, a backend, accounts, or daily-streak pressure to solve launch monetization. Those create additional product and verification work while weakening the offline/cozy proposition.

## 6. Prioritized improvements and feature backlog

Effort is relative: S = contained change, M = several connected surfaces/tests, L = new simulation or persistence behavior. It is not a calendar estimate.

| Improvement | When | Value | Effort | Completion condition |
|---|---|---|---|---|
| Unique campaign saves and legacy migration | Before launch | Protects purchased value and progress | M | Two airlines survive repeated independent saves/relaunches |
| Retryable save failures | Before launch | Prevents avoidable progress loss | S–M | Failed save leaves live session intact |
| Working legal/support pages and accurate manifest | Before launch | Removes concrete submission defects | S | Exact installed-app URLs work; archive declaration matches source |
| Purchase/restore/pending feedback | Before launch | Makes buying trustworthy | M | Every transaction outcome is visible and correct |
| Free/paid end-to-end test lane | Before launch | Covers the real customer journey | M | Free → paid → restored → lapsed behavior demonstrated |
| Unified time-access policy | Before launch | Fixes bypass and boundary inconsistency | M | All time actions agree |
| Starter-focused aircraft shop | Launch polish | Reduces first-session confusion | S–M | First visible choice can serve the intended starter route |
| Forecasts tied to selected operation | Launch polish | Makes advice credible | M | Fare/frequency/airframe assumptions match created route |
| Idle-route action beside warning | Launch polish | Gets the first aircraft flying | S | Assign action visible where the problem is described |
| First revenue → company profit explanation | Launch polish | Turns raw figures into understandable progress | S | Tester explains revenue versus profit |
| Correct next-day wording/behavior | Launch polish | Aligns expectation with time simulation | S | Label and resulting clock agree |
| Deterministic follow-camera journey | Launch polish | Validates the core map delight | M | Camera follows, releases and handles landing correctly |
| Visible next-era progress on Home | First update or small launch polish | Supplies a longer-term reason to continue | S–M | One useful next requirement, no new competing overlay |
| A concise session-end summary | First update | Gives a satisfying stopping point | M | Shows actual gains/losses and one next opportunity |
| User-initiated save export/import | First update | Recovery and device migration | M | Version validation, collision handling and safe import |
| Investor rescue with clear terms | First major update | Matches the intended guided failure experience | L | Accept/decline, obligations and terminal bankruptcy remain coherent |
| Capped offline catch-up | First major update | Rewards returning | L | Cap, clock changes, expiry, no absence punishment, deterministic processing |
| Opt-in contract variety | First major update | Gives sessions varied goals | M–L | Goals/rewards/penalties persist and cannot be farmed by reload |
| Rival archetype rebalance | First major update | Makes competition diverse and credible | M–L | Per-archetype viability measured across seeds |
| Fleet identity and collection moments | First major update | Gives aircraft purchases emotional value | M | Distinct readable silhouettes, useful comparisons, milestone presentation |
| Hub connections and banked schedules | Later | Adds network strategy beyond independent routes | L | Demand conserved, transfer timing explained, AI can use it |
| Fleet commonality economics | Later | Adds meaningful fleet planning | M–L | Visible trade-off, not an invisible discount |
| Mature-network bulk management | Later | Reduces repetitive late-game work | M | Filters/bulk decisions remain reversible or clearly confirmed |
| Seeded challenge sharing | Later | Replayability and word of mouth | M | Seed plus content/scenario version reproduces the challenge |
| Richer scenarios and historical starts | Later | Efficient replay content | M | Each changes meaningful constraints and is balanced |
| iCloud synchronization | Later | Cross-device continuity | L | Explicit conflict/recovery model; no silent last-writer loss |
| Cargo, alliances, terminals, subsidiaries | Expansion | Substantial new depth | L each | Separate design, migration, economy and AI validation |

Existing missions, achievements and era requirements should be extended where suitable. Do not build a second parallel progression engine. Likewise, hub connections and offline catch-up are new simulation work, not small UI switches.

## 7. Shortest responsible release plan

### Batch A: protect the player's airline

Implement R01/R02 together as a cohesive persistence change. Add campaign identity and a legacy-slot transition. Include save failure and backup recovery tests. Rehearse background saving and preserve old TestFlight saves.

**Exit:** multiple paid airlines are real, and failed saving cannot silently discard the current session.

### Batch B: make the commercial promise true

Fix the manifest, host the actual legal/support destinations, reconcile privacy language, surface purchase states, and test free/paid boundaries. Resolve the regional-ceiling promise before hardening its bypass. Choose the smallest defensible launch offer, preserving existing buyers.

**Exit:** a new free user and a paying user can each complete the lifecycle appropriate to them, including restoration and offline relaunch.

### Batch C: polish the first playable loop

Change starter-market defaults, align recommendation assumptions, expose the next idle-route action, and correct the morning label. Validate follow-camera behavior. Add only lightweight era guidance if it fits without delaying stabilization.

**Exit:** an unfamiliar tester can found an airline, acquire an appropriate aircraft, open/assign a route, watch it fly, understand the first result, save, and continue without coaching.

### Batch D: close evidence gaps on one candidate

Resolve economy/iPad failures. Run the full relevant UI suite and iPad lane on the candidate, inspect the frames, then produce a TestFlight build from that SHA. Walk the free and paid paths on physical devices. Check large text, VoiceOver, memory/thermal behavior and long-session saving.

**Exit:** no unexplained critical failure or skip. Record the exact SHA, build number and test evidence together.

### Batch E: package and submit

Use real release-candidate screenshots. Fill verified contact/copyright information. Correct stale listing claims. Confirm product setup, current age-rating/privacy answers, review notes and working links in App Store Connect. Run strict metadata validation. Use manual release after approval so publication timing is controlled.

**Exit:** the submitted binary, screenshots, listing and paid features describe the same product.

No reliable number of calendar days can be inferred from this repository. The unresolved iPad failure, StoreKit sandbox setup and available physical-device testing are the critical uncertainties. Adding AE-049 through AE-054 now would make the release harder to predict.

## 8. Release acceptance checklist

- [ ] Distinct campaigns persist independently; legacy saves survive upgrade.
- [ ] Write failure leaves the active game recoverable; save-and-quit never discards without consent.
- [ ] Background, force-termination and backup-recovery cases have explicit results.
- [ ] Required-reason API manifest matches the final archive.
- [ ] Privacy, terms and support links work from the installed app.
- [ ] App, website and listing agree about purchases, offline play and free limits.
- [ ] Real free-player Founder journey passes, including decline and boundary behavior.
- [ ] Offered StoreKit products load and buy/restore correctly; failure and pending states are visible.
- [ ] Subscription expiry/grace/revocation tested if subscriptions ship.
- [ ] First aircraft purchase and first route are understandable without guidance outside the app.
- [ ] Forecasts identify the operation they estimate and exclude misleading certainty.
- [ ] Candidate Core and iOS build pass; full UI/iPad failures are resolved and critical skips closed.
- [ ] Follow camera is actually exercised, including release and landing.
- [ ] Physical iPhone/iPad, large text, VoiceOver and long-session checks recorded.
- [ ] Real screenshots and verified review metadata are ready; strict validator exits zero.
- [ ] Final candidate SHA, TestFlight build and submission record match.

## 9. What to preserve

Preserve the deterministic Core, shared read models, seeded world, ledger transparency, versioned save format, existing migration chain, offline gameplay, and map-first shell. Those are valuable foundations.

The highest-return launch work is making those foundations meet the player consistently: a sensible first aircraft, an explanation that matches the economy, a purchase that visibly works, and an airline that is still there tomorrow.
