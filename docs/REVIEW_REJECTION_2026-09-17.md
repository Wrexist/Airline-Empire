# App Review rejection of 1.0 — findings and fixes

Submission `a27498d9-9240-43ed-b27a-ffa6600e8e68`, reviewed 17 September 2026 on
an iPad Air 11-inch (M3), version 1.0 (10). Two guidelines were cited, both
fixed and both verified against App Store Connect rather than assumed.

## Guideline 2.1(b) — Performance: App Completeness

> The app includes references to Pro but the associated In-App Purchase
> products have not been submitted for review.

**What was actually wrong.** Not the review image. All three products are
`READY_TO_SUBMIT` with their App Review screenshots `COMPLETE`
(`upload-iap-review.mjs --check` had said so since 10 September). The audit of
the submission shows the real shape:

| Submission | State | Items |
|---|---|---|
| `a27498d9…` (the rejected one) | `UNRESOLVED_ISSUES` | 1 — the app version |
| `96ad6900…` | `READY_FOR_REVIEW` | 4 — the three products and their group |

The version and the products were in **different** submissions, so App Review
never had them together.

**The fix, executed through the API.** `scripts/asc/submit-for-review.mjs`
attaches the version to the submission that holds the products, and submits.
Four Apple state errors had to be solved in order, each now handled in the
script and recorded here because none of them is obvious:

1. `STATE_ERROR.ENTITY_STATE_INVALID` — the summary line, with the reason in
   `associatedErrors`; the script prints the full error rather than guessing.
2. `STATE_ERROR.ITEM_PART_OF_ANOTHER_SUBMISSION` — a version can be in only one
   submission, and it was still in the rejected one.
3. `DELETE` refused with "Item was already submitted" — a submitted item cannot
   be removed, so the resolved submission is closed instead
   (`canceled: true`).
4. The cancel is asynchronous — the script polls until the submission is
   `COMPLETE`, then attaches.

**Result, read back from Apple:** submission `96ad6900…` is
`WAITING_FOR_REVIEW` with **5 items**; version 1.0 and all three products are
`WAITING_FOR_REVIEW`. Submission `a27498d9…` is `COMPLETE`.

## Guideline 2.3.3 — Performance: Accurate Metadata

> The 6.7-inch iPhone, 6.5-inch iPhone, and 13-inch iPad screenshots do not show
> the actual app in use in the majority of the screenshots.

**What was actually wrong.** Every listing image was a decorative 3D aviation
illustration with a gameplay panel inset — genuine pixels, but a minority of
the canvas, and the guidelines say outright that "marketing or promotional
materials that do not reflect the UI of the app are not appropriate for
screenshots".

**The fix.** `scripts/store-art/build.cjs --native` composes the listing from
the native capture full-bleed at its native aspect, with a compact caption band
over the top and nothing else drawn over it: no illustration, no promotional
proof line, no crop that hides the screen. The app is now ~87% of every canvas.
`verify.cjs` was taught that an export with no artwork is the required shape
rather than a gap.

All 36 files were replaced in App Store Connect and verified by Apple's own
read-back: *"Verified 36 screenshots across 6 sets: exact checksums, filename
order and COMPLETE processing."* The cinematic collection is retained as source
in `store/artwork/cinematic/` and is no longer part of the listing.

## Also found, and fixed

- **A crash in the beta.** `audit-beta-crashes.mjs` returns exactly one result:
  build 1, 28 August 2026, a `precondition` failure in `GameCalendar.date`
  reached from `GameState.dailyDigest` on Home. The guard that fixed it is in
  the source with a comment naming the build, but nothing locked it;
  `DailyDigestTests` now does.
- **Listing metadata.** `push-metadata` applied 2 changes (version copyright and
  the review details), so the reviewer's copy matches `store/`.
- **Stale claims in the tooling.** The fill-in sheet said an IAP review
  screenshot was "still needed"; the screenshots README, `docs/ASO.md` and the
  artwork README all described the cinematic set as the listing.
- **Territories.** 173 of 175 available, CHN and VNM excluded as intended, all
  pre-order enabled for 2026-10-16.

## Verification

| Check | Result |
|---|---|
| Submission state (Apple) | `96ad6900…` `WAITING_FOR_REVIEW`, 5 items |
| Version / products (Apple) | all four `WAITING_FOR_REVIEW` |
| Screenshots (Apple read-back) | 36 across 6 sets, exact checksums, COMPLETE |
| `validate-metadata.mjs` | 0 warnings |
| `asc/selftest.mjs` | 53 passing |
| `store-art/verify.cjs` | 18 app-dominant RGB exports per locale |
| Full Core suite | 604 tests passed, release build clean |

## Resubmitted as 1.1.0 with a new binary (20 September 2026)

App Review's message also asked for a new binary, and the binary they had
reviewed (1.0.21 / build 10, uploaded 13 September) predated every one of the
seven screen revamps — as did the newest build then in TestFlight, 1.1.0 (12),
uploaded on the 14th. Nothing Apple held contained the work in this repository.

So the release was re-run from this branch
([35499150636](https://github.com/Wrexist/Airline-Empire/actions/runs/35499150636),
candidate `a1f92a2`) after the full validation caught four UI regressions the
branch had never been tested for — see "The validation's own findings" below.
The archive uploaded **1.1.0 (13)**, Apple processed it VALID, and the version
was moved across:

| Step | Result |
|---|---|
| New build | 1.1.0 (13), VALID, uploaded 2026-09-20 |
| Version | 1.0 renamed to **1.1.0** (Apple allows one editable version at a time, so a second could not be created; renaming kept the localisations and screenshots) |
| Listing | metadata re-applied; the 36 screenshots already matched |
| Products | the three Pro products and their group re-attached to the new submission |
| Submission | `1b421a5f…` — **WAITING_FOR_REVIEW**, 5 items |
| Withdrawn | `96ad6900…` (1.0) and the original rejection `a27498d9…`, both COMPLETE |

### The validation's own findings

The full UI suite had never run on this branch, and four shards failed the first
time it did. Three were journeys asserting against screens that had moved on —
the aircraft detail became tabbed, the route screen became the tabbed
`RouteManagementView`, and the Home briefing grew sections above Next Moves, so
a suggestion tap that needed hittability landed on nothing. One was a real
accessibility defect: an unhidden SF Symbol in `AESectionHeader` exposed its own
name as a label, which the audit rejects as not human-readable. All four are
fixed in `7ef5d45` and `a1f92a2`.

### Apple's API errors, for the next time

Each cost a run, and none is self-explanatory:

1. `ITEM_PART_OF_ANOTHER_SUBMISSION` — a version can be in one submission only.
2. `DELETE` refused: "Item was already submitted" — a submitted item cannot be
   removed; the submission is closed instead, and the cancel is asynchronous.
3. `ENTITY_ERROR.RELATIONSHIP.INVALID`, "You cannot create a new version of the
   App in the current state" — a version in review blocks a new one, and one
   editable version is the limit, so the rejected version is renamed.
4. `ENTITY_ERROR.RELATIONSHIP.INVALID`, "The given related type 'appStoreVersion'
   is not valid for the relationship 'appStoreVersion'" — relationship keys are
   singular, resource types plural.
5. HTTP 401 on every call, twice, minutes apart, with no change to the secrets:
   Apple returned a proper token error transitorily. Retrying is the right move.

## If this happens again

`app-store-metadata.yml` now carries the whole path: `submit_for_review=plan`
reads the submission, `retarget-plan` / `retarget` moves to a new version with
its purchases attached, `retarget-submit` sends it, and `attach` / `submit` do
the same for the version already in a submission. Every step is idempotent — an
item already added, a build already attached or a submission already prepared is
recognised and left alone.
