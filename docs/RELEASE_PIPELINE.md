# The release pipeline

Four workflows and eight scripts, from a commit to a build on a phone and a
listing on the store. This page is what they do, what it costs, what has
actually been run, and what to do when a step fails.

Setup that has to happen once, by a human with the Apple account, is in
[`APP_STORE_CONNECT.md`](APP_STORE_CONNECT.md). The listing copy and its
reasoning are in [`ASO.md`](ASO.md). If you are asking "what do I do next",
read [`GO_LIVE.md`](GO_LIVE.md) instead — it is the same material as an
ordered checklist.

---

## The map

| Workflow | Trigger | Runners | What it answers |
|---|---|---|---|
| `ci.yml` | push to main, every PR | ubuntu ×2, macOS ×1 | Does the core pass? Is the tooling sound and the listing legal? **Does the app compile?** |
| `ios-testflight.yml` | manual | ubuntu ×2, macOS ×1 | Can we produce a signed, uploadable build — and upload it? |
| `app-store-metadata.yml` | PRs touching `store/`, manual | ubuntu | Is the listing valid, and can it be deployed to App Store Connect? |
| `pages.yml` | manual only | ubuntu | Publish the support and privacy pages Apple requires a link to. |

```
                    ┌──────────────── ci.yml ────────────────┐
   commit  ───────► │ core (swift test) · tooling · app build │
                    └────────────────────────────────────────┘

                    ┌──────── ios-testflight.yml ────────┐
   dispatch ──────► │ preflight → archive → processing   │ ──► TestFlight
                    └────────────────────────────────────┘

                    ┌────── app-store-metadata.yml ──────┐
   dispatch ──────► │ validate → plan / apply            │ ──► product page
                    └────────────────────────────────────┘
```

---

## What has actually run

This table is the point of this document. Do not upgrade a row without a run
to point at, and put the date and the run number in when you do.

| Path | Status |
|---|---|
| `swift test` on Linux | **Proven** — 253 tests, 2026-08-27 (`APPLE_VALIDATION.md` §7) |
| Release tooling selftest (30 tests) | **Proven** — run locally, 2026-08-28 |
| Listing validation, bundle-id agreement, icon check | **Proven** — run against this checkout, 2026-08-28 (the icon check correctly reports the icon as missing) |
| `xcodebuild` compile of the app | **Never run.** The app has never been built by Xcode. |
| Archive, export, signing | **Never run.** No certificate, no team. |
| Upload to App Store Connect | **Never run.** No app record. |
| Any App Store Connect API call | **Never run** from this repository. The JWT construction is ported from a repository where it authenticated successfully; that is evidence, not proof. |
| Metadata push, screenshot upload | **Never run.** |
| Pages deploy | **Never run.** |

The scripts are written to fail honestly rather than optimistically: the
preflight passes when it cannot reach Apple, the build-number resolver falls
back to epoch seconds when there is no app record, and the metadata push
refuses to write anything until it is asked twice.

---

## Cost, and why the jobs are split the way they are

GitHub bills macOS runners at **ten times** the ubuntu rate. The split in
`ios-testflight.yml` comes from a measurement in a sibling repository
(Wrexist/WorldQuest, run #50): a release job that waited for Apple's queue on
the same macOS runner that had compiled spent **53 minutes idle** — 73% of a
1h13m job, roughly 530 billed minutes for nothing.

So the rule here is: **only compilation and `xcrun` run on macOS.**

| Job | Runner | Roughly | Why there |
|---|---|---|---|
| preflight | ubuntu | 2 min | Secrets, version, listing, Apple's answers — none of it needs Xcode |
| core-tests | ubuntu | 5 min | The simulation builds and tests on Linux |
| archive | macOS | 15–30 min | Compiling, signing, and `altool` genuinely need Xcode |
| processing | ubuntu | 5–30 min | Waiting for Apple is waiting; it needs a network connection and nothing else |

`ci.yml`'s macOS job is skipped when a commit touches neither the app, the
core, nor the workflow — checked with `git diff` rather than a job-level
`paths:` filter, so the check still reports a status on every pull request.

---

## Releasing: the order

0. **`node scripts/asc/check-app-icon.mjs`** — if this fails, an upload will
   fail too, and everything below is wasted time.
1. **Merge to main with CI green.** In particular the macOS `app` job — if the
   app does not compile, nothing downstream matters.
2. **Run `ios-testflight.yml`** with the marketing version, `upload` off the
   first time. This proves signing and export without touching Apple. Download
   the `.ipa` artefact and check it exists and is the size you expect.
3. **Run it again with `upload` on.** The `processing` job reports when the
   build is VALID; internal TestFlight testers can install it minutes later.
4. **Walk `APPLE_VALIDATION.md` §4 on a real device.** This is the step the
   whole project has been waiting on; do not skip it because the build
   installed.
5. **Run `app-store-metadata.yml` in `plan` mode.** Read the diff.
6. **Run it in `apply` mode**, with `APPLY` typed into the confirmation and
   `screenshots` ticked once the screenshots exist.
7. **Submit for review by hand, in App Store Connect.** Deliberately not
   automated: submission is the one irreversible, outward-facing action in the
   sequence, and a person should look at the page before a reviewer does.

---

## The scripts

All of them are dependency-free Node (see the header of `scripts/asc/lib/asc.mjs`
for why Node in a Swift repository), and none of them ship in the app.

| Script | Does | Needs |
|---|---|---|
| `selftest.mjs` | 30 tests over the JWT, the HTTP client, PNG inspection, the app icon and the listing validator | nothing |
| `validate-metadata.mjs` | Character limits, keyword hygiene, trademarks, URLs, screenshot canvases, bundle-id agreement across three files | nothing |
| `check-app-icon.mjs` | Whether the icon exists, is 1024×1024 and has no alpha — the most common first-upload rejection, caught before the archive | nothing |
| `preflight.mjs` | Secrets, authentication, app record, version state | the three ASC secrets |
| `next-build-number.mjs` | The next CFBundleVersion, from Apple or from the clock | optional |
| `push-metadata.mjs` | Deploys `store/` to a version; dry run by default | the three ASC secrets |
| `upload-screenshots.mjs` | Reserve → PUT → commit → order, per locale and display type | the three ASC secrets |
| `wait-for-processing.mjs` | Polls until the build is VALID or INVALID | the three ASC secrets |

Two conventions run through all of them:

- **Fail-open where the answer is unknown, hard-fail where it is known.** A
  preflight that blocks a release because Apple was unreachable is worse than
  no preflight. A missing secret is a different thing and stops the run.
- **Nothing destructive without being asked twice.** `push-metadata` never
  deletes a locale, `upload-screenshots` needs `--replace` to touch an
  existing set, and applying either needs both a dropdown and a typed word.

---

## When it fails

| Symptom | Cause | Fix |
|---|---|---|
| `Missing secret(s): …` in preflight | Secret absent or misspelled | `APP_STORE_CONNECT.md` §5 |
| HTTP 401 from any script | Key id, issuer id and `.p8` are not from the same key | Re-download the key; §3 there |
| `No App Store Connect app record for …` | The app record does not exist, or the bundle id disagrees | §2 there. The three places the bundle id lives must match |
| Archive fails on code signing | Certificate missing, expired, or not all three signing secrets set | §4 there |
| Export fails with "no profile matching" | The profile is for a different bundle id or a different certificate | Re-download the profile after fixing the certificate |
| Upload rejected: SDK version | The runner's Xcode is older than Apple's current minimum | `runs-on: macos-26` in the workflow; Apple refuses the upload *after* the compile, which is why the runner is pinned |
| Upload rejected: build number already used | Two runs produced the same CFBundleVersion | `next-build-number.mjs` prevents it when the app record exists; the `ios-release` concurrency group prevents the race |
| Processing → INVALID | Usually a missing icon | `AirlineEmpireApp/Resources/README.md` |
| Metadata push: "version is … and does not accept edits" | The version is in review or released | Create the next version, or push to the editable one |
| `still contains REPLACE_ME` | The review contact or support email is unset | `store/config.json`, `site/support.html` |

---

## Rollback

There is no rollback for a released version — Apple has no "unpublish this
build" button that leaves the previous one installed. What exists:

- **Before release:** reject the binary in App Store Connect and upload
  another. The `.ipa` and dSYMs of every archive are kept as workflow
  artefacts for 14 and 90 days.
- **After release:** ship a new version. Phased release (updates only) can be
  paused, which slows the spread of a bad build but does not recall it.
- **The listing:** `store/` is version-controlled, so reverting the commit and
  re-running `app-store-metadata.yml` restores the previous copy exactly. That
  is the main argument for keeping the listing in the repository at all.
- **Save data:** the app's own migration path (`Persistence/Migrations.swift`)
  is what protects players across an update, and it is tested. A store
  rollback would not help there anyway.
