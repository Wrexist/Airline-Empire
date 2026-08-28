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
| `swift test` on Linux | **Proven** — 253 tests locally 2026-08-27 (`APPLE_VALIDATION.md` §7), and in CI 2026-08-28 (run 33213797384: 8m 02s) |
| Release release-build gate (`-warnings-as-errors`) | **Proven** — 2026-08-28, run 33213797384. The core builds in release with zero warnings, so "target: zero new warnings" is now enforced by a machine rather than remembered. |
| Release tooling selftest (30 tests) | **Proven** — locally and in CI, 2026-08-28 (run 33213797384) |
| Listing validation, bundle-id agreement, icon check | **Proven** — run against this checkout, 2026-08-28 (the icon check correctly reports the icon as missing) |
| `xcodebuild` compile of the app | **PROVEN — 2026-08-28**, [CI run 33213797384](https://github.com/Wrexist/Airline-Empire/actions/runs/33213797384). `** BUILD SUCCEEDED **` on `macos-26` / Xcode 26.6 / iPhoneSimulator 26.5 SDK, universal arm64 + x86_64, `com.airlineempire.game`, in 53 seconds. The first Xcode build in this project's history. |
| Archive, export, signing | **PROVEN — 2026-08-28**, [run 33216345773](https://github.com/Wrexist/Airline-Empire/actions/runs/33216345773). Archive in 71s, export in 16s, a real signed `.ipa` and its dSYMs kept as artefacts. Signing, the API key, the export options and the whole macOS job work. |
| Upload to App Store Connect | **Attempted, refused at validation** — same run. `xcrun altool --validate-app` reached Apple and came back with error 90474 (iPad multitasking orientations). That is the validation step doing its job: the bundle never left for the store. Fixed in `project.yml`, and the rule now runs on the 1x preflight (`check-bundle-config.mjs`). Still unproven: the upload itself and TestFlight processing. |
| App Store Connect API calls | **PROVEN — 2026-08-28**, same run: `preflight.mjs` and `next-build-number.mjs` both authenticated and answered. The JWT, the client and the resolver work against the live API. |
| Metadata push, screenshot upload | **Never run.** |
| Pages deploy | **Never run.** |

The scripts are written to fail honestly rather than optimistically: the
preflight passes when it cannot reach Apple, the build-number resolver falls
back to epoch seconds when there is no app record, and the metadata push
refuses to write anything until it is asked twice.

---

## Cost, and why the jobs are split the way they are

GitHub bills macOS runners at **ten times** the ubuntu rate. Everything below
is measured from real runs rather than estimated, because a cost argument made
from intuition is how the 53-minute idle wait in the sibling repository
happened in the first place.

### Measured, before optimisation

| Run | Job | Runner | Wall | Billed |
|---|---|---|---|---|
| CI 33215272439 | Core (test + release build) | ubuntu | 7m30s | 7.5 |
| | Release tooling | ubuntu | 9s | 0.1 |
| | iOS app (xcodebuild) | macOS | 1m07s | **11.2** |
| | | | | **18.8 min** |
| Release 33216345773 | Core tests | ubuntu | 9m16s | 9.3 |
| | Preflight | ubuntu | 7s | 0.1 |
| | Archive + export + validate | macOS | 2m50s | **28.3** |
| | | | | **37.7 min** |

Two things stood out, and both were addressed on 2026-08-28:

**`--validate-app` cost 62 seconds of macOS — 10.3 billed minutes, 27% of the
release — to ask a question the upload repeats.** `altool --upload-app`
validates server-side before delivering; that is precisely how error 90474
surfaced. So validation now runs only on runs that do NOT upload, where it is
the entire point (learning whether the bundle would be accepted, without
submitting it). An uploading run goes straight to the upload and gets the same
error codes if the bundle is bad.

**`swift test` is mostly compilation.** 253 tests of pure computation do not
take nine minutes to execute; the package and the test target take nine minutes
to build. Both the CI job and the release job now restore a SwiftPM build
cache keyed on the toolchain and the manifest, with `restore-keys` falling back
to the newest build for the same toolchain so a source edit recompiles one
module rather than the package. They share one key, so releasing a commit CI
has already built restores that build.

Two further cuts, same date:

- **The Linux core job is now diff-gated**, like the macOS one already was. A
  docs-only commit — most commits in this repository — no longer spends nine
  minutes proving a simulation nobody touched still works. The job still
  reports a status on every pull request; only its expensive steps are
  conditional, because a required check that silently does not run is a
  required check that never blocks anything.
- **`app-store-metadata.yml` no longer runs on pull requests.** `ci.yml`
  already ran the same selftest and listing validation on every PR — a
  superset — so the duplicate was a second job to pay for and a second place
  to keep in step. It remains on dispatch, where it does something CI cannot:
  strict validation with no placeholders allowed.

### Expected after, and how to know

These are **projections, not measurements** — the numbers above were taken from
runs, these have not happened yet. Update this table from real runs and delete
this sentence when you do.

| Scenario | Before | Projected after |
|---|---|---|
| PR touching only docs or the listing | 18.8 | ~0.3 |
| PR touching the app or core, warm cache | 18.8 | ~14 |
| Release, warm cache, upload on | 37.7 | ~20 |

The rule the split still follows: **only compilation and `xcrun` run on
macOS.** The sibling-repository measurement that produced it (Wrexist/
WorldQuest, run #50) is worth keeping in view — a release job that waited for
Apple's queue on the same macOS runner that had compiled spent **53 minutes
idle**, 73% of a 1h13m job, roughly 530 billed minutes for nothing.

| Job | Runner | Why there |
|---|---|---|
| preflight | ubuntu | Secrets, version, listing, bundle config, icon, Apple's answers — none of it needs Xcode |
| core-tests | ubuntu | The simulation builds and tests on Linux |
| archive | macOS | Compiling, signing and `altool` genuinely need Xcode |
| processing | ubuntu | Waiting for Apple is waiting; it needs a network connection and nothing else |

### What was considered and rejected

- **Dropping the release workflow's `swift test`** because CI already ran it on
  the same commit. It is the one check whose absence would be discovered by
  players rather than by a machine, and with the cache it is now cheap. Kept.
- **`swift test --parallel`.** Might help, might introduce flakiness in a suite
  no one here can run to find out. Not changed blind; try it on a branch and
  measure.
- **Shorter artefact retention.** The dSYMs are kept 90 days on purpose: a
  TestFlight build expires at 90 days, and a crash report from a build whose
  symbols have been deleted is unreadable.
- **Skipping the archive-only rehearsal run.** It is the cheapest way to prove
  signing without touching Apple, and it costs less than a failed upload.

## Releasing: the order

0. **`node scripts/asc/check-app-icon.mjs`** — if this fails, an upload will
   fail too, and everything below is wasted time. (Passing since 2026-08-28.)
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
| `build-fill-in-sheet.mjs` | Generates `docs/APP_STORE_CONNECT_FILL_IN.md` from `store/`; `--check` fails CI when it is stale | nothing |
| `check-bundle-config.mjs` | Apple's bundle rules read off `project.yml` — iPad orientations, export compliance, the icon set, the shared scheme — before anything compiles | nothing |
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
| Validation: error **90474**, orientations | An iPad build must support all four orientations for Slide Over and Split View | Fixed 2026-08-28; `check-bundle-config.mjs` now catches it on the 1x runner. If it returns, read that script's rule 1 |
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
