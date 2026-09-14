# Pre-TestFlight audit - 14 September 2026

Current app source: `cc18dd0ccebaea742577637cc8556975cad95830` on `codex/clay-glass-game-2026-09-14`.

**Release hold: the user explicitly requires approval before creating or uploading another TestFlight build.** Positive feedback on a design is not upload approval. Current distributed build remains 1.0.22 (11), source `a381091`. PR #36 is a draft. Do not replace the existing App Review submission or store gallery as part of this audit.

## Evidence and scope

Six focused audits: visual hierarchy, first-session usability, accessibility/motion, saves/purchases, performance, and release operations. This is a source/evidence audit, not a newly executed hands-on device session.

- Current native iOS compile passed: [job 103844850050](https://github.com/Wrexist/Airline-Empire/actions/runs/34801461086/job/103844850050).
- Current Launch safety passed, including Core, app save/StoreKit checks and Release isolation: [34801461131](https://github.com/Wrexist/Airline-Empire/actions/runs/34801461131).
- 40 native frames captured successfully: ten screens each on iPhone/iPad in [light](https://github.com/Wrexist/Airline-Empire/actions/runs/34801461083) and [dark](https://github.com/Wrexist/Airline-Empire/actions/runs/34801468270). Local capture hashes were verified. All ten dark iPhone screens were visually reviewed across the revision and this audit; Home/route/Finance also reviewed on dark iPad and light iPhone.
- Captures use an earned 2035 campaign. They do not cover a fresh first session, every sheet, every accessibility setting or iOS 17-25. Dark captures explicitly pin appearance; they do not prove system appearance switching.
- Current CI was requested in **compile** mode. Its successful iOS compile is not the full five-journey/iPad release gate. Previous full CI and camera-follow passes belong to `a381091`, not automatically to this UI revision.
- No newly reproduced crash, data-loss or purchase-access defect was found. That is not proof that none exist. Physical-device performance, real storefront behavior and upgrade acceptance remain unverified for this revision.

Evidence labels: **Observed** = visible native frame; **Source** = directly supported by current code; **Gap** = missing runtime evidence; **Proposal** = an improvement, not a proven malfunction. P1 = recommended before the next TestFlight; P2 = next polish pass or targeted validation; P3 = later scope.

## Audit 1 - Visual hierarchy and consistency

### AUD-01 - Map framing leaves too much empty space (P2, Observed + Source)

Both current portrait Home captures leave a large dark field above the geographic band, despite the newly smaller toolbar. This is a pre-existing map-composition issue, not a new missing-data failure. `MapCamera.frameNetwork` in `AirlineEmpireApp/Sources/Map/MapView.swift:936` fits normalized airport spans without taking the available viewport/chrome into account.

**Improve:** frame the airline inside the usable map region using actual viewport dimensions and overlay occlusion. Keep zoom-out/pan available; do not simply force a zoom that hides distant routes. Test regional, global, one-airport and widely separated networks on phone portrait and iPad portrait/landscape. Acceptance: useful geography occupies the visual center; fit includes intended airports and controls remain tappable. Camera changes require gesture/follow regression checks.

### AUD-02 - Fleet and Routes still spend too much space before the list (P1, Observed)

`02-fleet.png` and `03b-routes.png` show stacked summaries, nested card outlines, section controls and filters taking roughly the upper half of the phone before useful list rows. The hierarchy still feels like a report before it feels like an airline to manage. Relevant sources: `FleetView.swift` summary/filter sections and `RoutesView.swift` network summary.

**Improve:** one compact operational summary, one filter row and optional expanded statistics. Prioritize idle/unassigned/losing items; keep all current metrics accessible. Acceptance: at default phone text size, at least two useful fleet rows are visible without scrolling in the review fixture; the first route appears substantially earlier. Large text must reflow, not shrink.

### AUD-03 - Aircraft market has mismatched card sections (P2, Observed + Source)

`02b-market.png` shows gray native grouped-list sections around a darker model body and purchase footer, plus substantial filter/context chrome before the first aircraft. In `FleetView.swift:1003`, only `shopRow` sets `listRowBackground`; `ShopCommitButton` is a separate default-background row. This explains the visible seam.

**Improve:** apply one deliberate card treatment across model facts and commit row, preserving separate safe tap targets and the acquisition lock. Consolidate network filters/context into one compact area. Acceptance: coherent surface boundaries in both appearances; price, lease term and total commitment remain visible before tapping; purchasing cannot be triggered by tapping unrelated facts.

### AUD-04 - Briefing and competitor cards repeat too much prose (P2, Observed)

`06b-briefing.png` repeats the full forecasting assumptions on each opportunity; `05-rivals.png` repeats similar presence explanations. These are useful disclosures, but overwhelm scanning.

**Improve:** concise result plus one action per item; show shared forecast assumptions once or in a clearly labeled disclosure. Keep 'estimate', the basis, and 'before airline overhead' beside every financial projection. No inflated or guaranteed-income copy. Acceptance: two opportunities can be compared at a glance; assumptions remain one action away.

## Audit 2 - First-session clarity and everyday tasks

### AUD-05 - Route departure timing became too hidden (P1, Source)

`DesignSystem/FirstFlightGuide.swift:48` puts all schedule detail behind a collapsed disclosure. This includes the next departure or the midnight scheduling explanation. A player seeing 'Waiting for departure' can again mistake normal waiting for a broken clock.

**Improve:** retain one always-visible line: actual next departure/ETA when known, otherwise the accurate midnight/readiness explanation. Keep longer revenue/delay context expandable. Do not promise departure when aircraft are unavailable. Acceptance: a new player can tell what to do next without expanding help; test paused, scheduled, airborne and unready aircraft.

### AUD-06 - Frequent route actions are buried (P2, Source + Proposal)

`RoutesView.swift:249` places fare controls after performance, demand, competition, expense breakdown and aircraft sections. The data is useful, but the action can require several screens of scrolling.

**Improve:** provide a compact 'Manage route' entry or accessible jump links to fares/aircraft while retaining the detailed report. Avoid extra floating bars over the tab bar. Acceptance: fares and assignment are reachable in one obvious action from the route header, including with VoiceOver.

### AUD-07 - Fresh-game and secondary-sheet review is missing on this revision (P1, Gap)

The 2035 capture journey does not validate onboarding, the empty fleet/route experience, loans, save/import failures, settings, game over, world-event details, reputation or the free-to-Pro transition. Some have previous runtime tests; that is useful historical coverage, not current visual approval.

**Validate:** clean free start -> aircraft -> route -> assignment -> midnight -> departure/arrival -> first statement -> save/reopen. Also capture borrowing, Settings, paywall, import failure and game-over/recovery states. Use ordinary game commands and real test failure injection; do not fabricate gameplay outcomes for screenshots. Record unclear steps and click depth.

## Audit 3 - Accessibility and motion

### AUD-08 - Badge colors do not reliably meet the small-text contrast target (P1, Observed + Source calculation)

`Theme.swift` defines fixed fare/owned/leased colors, while `Components.swift:162` uses the same hue for text over a 16% tinted background. These colors are not appearance-adaptive like the main semantic palette.

Calculated sRGB contrast ranges against both current clay gradient endpoints:

| Badge | Light | Dark |
|---|---:|---:|
| Fare | 3.30-3.67:1 | 2.94-3.18:1 |
| Owned | 4.24-4.72:1 | 2.32-2.50:1 |
| Leased | 2.86-3.18:1 | 3.34-3.63:1 |

These are source-color estimates, not calibrated device pixel measurements. They agree with the faint purple/teal labels in current dark captures. Use **4.5:1 for small informative text** as the engineering acceptance target, following [W3C contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html); inactive controls are a different case. This is not a claim of App Review certification.

**Improve:** separate adaptive badge foreground and fill tokens. Verify every informative badge on actual rendered backgrounds, including Increased Contrast. Preserve words/icons so hue is never the only meaning. Calculation receipt: `build/ui-polish/audit-2026-09-14/badge-contrast.json`.

### AUD-09 - Motion and accessibility settings need explicit review (P2, Source + Gap)

Most shared motion uses Reduce Motion checks, but `CelebrationOverlay` (`Advisories.swift:241`) and `GameOverView` (`RootView.swift:311`) invoke symbol effects without the explicit guard used elsewhere. This flags inconsistent implementation; system adaptation may occur, so a runtime violation is not established.

**Validate/improve:** verify these effects with Reduce Motion and provide a static/fade alternative where needed. Audit VoiceOver focus after sheets/disclosures, custom map alternatives, large text, Bold Text, Increased Contrast and Reduce Transparency. New compact Finance metrics reflow at accessibility sizes, but the current capture runs do not exercise that branch. Test iPhone SE-sized width and iPad split view; keep minimum touch targets and all primary actions reachable.

## Audit 4 - Save, purchase and support trust

**Evidence in favor:** current Launch safety passed. Source waits for successful save before quitting, retains the live session after failure, guards campaign identity, provides export/import and surfaces automatic-save failures. Current StoreKit tests cover lifetime purchase/restore, failure, pending approval and subscription expiry. The paywall keeps the actual charge adjacent to its button and disables buying while the price is unavailable. No new defect in these mechanisms was established.

### AUD-10 - Settings reports the wrong build identity (P1, Source)

`OperationsView.swift:1078` hard-codes `LabeledContent("Airline Empire", value: "1.0")`. Testers cannot identify 1.0.22 (11) or the next build from inside the app.

**Improve:** read `CFBundleShortVersionString` and `CFBundleVersion`; show both and provide a copyable support summary with device/iOS/version. Do not include save contents, account identifiers or other private data by default. Acceptance: Settings matches the inspected installed binary exactly.

### AUD-11 - Physical upgrade and purchase acceptance remains open (P1 release gate, Gap)

Before App Store submission of the eventual new binary, test an in-place upgrade with multiple saved airlines, offline continue, save/quit/reopen, export/import, purchase cancellation and restore, and entitlement access after relaunch. Retain backups; do not delete the user's installed app as a shortcut.

This is **after the approved TestFlight upload** for the exact new candidate. It cannot honestly be marked done on this Windows machine before a signed candidate exists. Existing build 1.0.22 can supply baseline observations now. Real storefront purchases are not inferred from StoreKit simulator passes.

## Audit 5 - Performance and responsiveness

### AUD-12 - Performance measurements are not regression gates (P2, Source + Gap)

`PerformanceBaselineUITests.swift:202` asserts that frames were drawn; the launch measurement at line 220 is explicitly a baseline, not an agreed time budget. A pass does not certify smooth scrolling, fast launch, thermal behavior or battery use.

**Next:** compare old/new source on the same simulator/device with the same save. Record cold launch, map pan/pinch/follow, Fleet/Market scrolling, 16x simulation, foreground/background and memory after a sustained session. Track median/p95 frame/hitch measurements and regressions, rather than comparing noisy CI wall-clock numbers across machines. Agree thresholds from measured device baselines before making them release gates. Physical heat/audio/haptics checks follow the approved upload. Keep the existing inexpensive content surfaces and cached read models; do not add live blur/looping animation to every row without measurements.

## Audit 6 - Release evidence and project hygiene

### AUD-13 - Active release documents point at obsolete builds (P1, Source; navigation corrected by this audit)

`tasks/TODO.md`, `tasks/RELEASE_CHECKLIST.md`, `RELEASE_CONTINUATION_STATUS.md` and `RELEASE_OWNER_STEPS.md` mix historical work with active instructions. Several still identify 1.0.16 (6), say no PR is open or say the app is an unsubmitted draft. The old Fleet 'Flying' filter item is already addressed by the current 'Assigned' label. The old camera-follow skip is superseded by the successful previous release run, not an unresolved current crash.

**Action taken:** add a current audit/todo entry point and mark earlier release instructions historical. Preserve evidence rather than erasing it. Last observed App Review state was Waiting for Review; this audit does not re-query Apple or change that submission. Any later release decision must check actual saved account state again.

### AUD-14 - Exact-source full journey coverage is still required (P1 before upload, Gap)

After the chosen fixes, freeze app source, run full iPhone journeys and iPad plus current launch-safety/portability checks, and inspect relevant frames at both normal and accessibility text sizes. Reuse evidence only when production source identity is established. A screenshot success, compile-only CI or older build's pass is not equivalent to full release validation. Do not weaken the upload workflow's checks to avoid waiting.

## Recommended todo and order

1. **Small reliability/readability pass:** AUD-08 badge contrast, AUD-05 visible departure summary, AUD-10 accurate version/build.
2. **Focused visual pass:** AUD-02 compact Fleet/Routes; AUD-03 coherent Market surface. Address AUD-01 map framing separately because it touches camera behavior. AUD-04/AUD-06 are valuable follow-ons, not reasons to redesign everything again.
3. **Validation pass:** AUD-07 new-player/secondary states, AUD-09 accessibility and supported-OS fallbacks, AUD-14 full current-source UI journeys. Include a same-environment performance comparison for the affected screens (AUD-12).
4. **User review:** show actual final screenshots and list remaining limitations. Request explicit approval to create/upload TestFlight. No version bump/archive/upload before that approval.
5. **After approval:** immutable candidate -> configured CI/signing/upload -> processing -> existing Tester group and build-specific notes.
6. **On TestFlight, before App Store changes:** AUD-11 physical upgrades/purchases and AUD-12 device performance/audio checks; triage feedback, then make a separate App Review decision.

P3 later: richer aircraft identity, contextual event/rival actions, polished milestone moments and fewer repetitive explanations. Defer new 3D engines, terminals, cargo, alliances or save-system rewrites from this polish build; they need separate design and regression scope.

The audit created documentation and the current todo only. It did not implement the findings, create a new app binary, upload TestFlight or change App Store Connect.
