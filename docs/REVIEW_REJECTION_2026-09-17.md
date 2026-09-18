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

## If this happens again

`app-store-metadata.yml` now carries the whole path: `submit_for_review=plan`
reads the submission, `attach` adds the version, `submit` sends it. Every step
is idempotent — `attach` on a submission that already holds the version says so
and changes nothing.
