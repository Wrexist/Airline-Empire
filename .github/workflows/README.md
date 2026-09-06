# Workflows

Four workflows. One rule: **a new job runs on `ubuntu-latest` unless it needs
Xcode.** macOS runners bill at **10×**, so every macOS minute costs what ten
Linux minutes cost, and the arrangement below exists to spend as few of them
as possible without losing signal.

## What runs when

| Workflow | Runs on | Jobs | Runner |
| --- | --- | --- | --- |
| **`ci.yml`** | PRs targeting `main`; pushes to `main` (except docs); manual dispatch | `core`, `release-tooling`, `plan` | ubuntu |
| | | `app` (matrix), `app-ipad` (opt-in) | **macOS** |
| **`ios-testflight.yml`** | Manual dispatch only | `preflight`, `core-tests`, `processing` | ubuntu |
| | | `archive` | **macOS** |
| **`app-store-metadata.yml`** | Manual dispatch only | `validate`, `push` | ubuntu |
| **`pages.yml`** | Manual dispatch only | `deploy` | ubuntu |

During ordinary development — a pull request, or a merge to `main` — **exactly
one macOS job runs**, and only when the code it compiles has actually changed.

## How `ci.yml` decides

`plan` is a Linux job that answers two questions before any macOS runner is
booked.

**Should the app be built at all?** It diffs against **the last commit CI was
green on for this branch**, not against the pull request's base. Diffing the
base means that once a branch touches `AirlineEmpireApp/`, every later push
re-runs the whole macOS suite forever, markdown included — which is exactly
what happened on 2026-09-06, when a commit changing one file under `tasks/`
spent about 90 macOS minutes. Diffing the last *green* head is also safer than
diffing the last push: a change whose run was cancelled by `concurrency` is
still in the diff, because that run never went green. When the answer is no,
the macOS job does not start, so it costs nothing at all.

**Which journeys?** A pull request gets a **smoke subset** — eight tests, about
six minutes, chosen by value per second from measured per-test costs: the
founding journey that reaches every tab, the home guidance to a first
aircraft, the audio-cue decode, the currency-glyph contract, acquiring an
aircraft and opening a route, a frame assertion, an airport tap, and the clock
actually running.

Everything else runs on demand: dispatch `CI` with **suite: full** for all four
journey classes and the performance baselines, on four runners. Do that before
a release, and after touching the map, the shell or the campaign. The iPad
shell journey is a separate opt-in input on the same dispatch.

**No simulator cloning anywhere.** Four separate runs proved these runners
cannot take simultaneous app launches; run 162 was the last of them, where the
second clone's test runner failed to launch and two journeys died of
starvation on a commit that changed one markdown file. One test class to a
runner, serially.

## Standing rules

- **`concurrency` on every workflow.** `cancel-in-progress: true` for `ci.yml`,
  because a superseded run is wasted money. `false` for the release, metadata
  and pages workflows, where killing a mid-flight upload does harm.
- **`timeout-minutes` on every job.** A hung job must never bill an hour. The
  macOS caps come from the matrix — 25 minutes for the smoke shard, 45–60 for
  a full class shard — and are sized against a *measured* 1.75× spread between
  runners, not a guess. A cap under that loses green suites to whichever
  machine they landed on.
- **Artifacts on failure only, three days.** The xcresult bundles are ~30 MB
  each; keeping them for every green run is what grew Actions storage to 1,990
  GB-hrs in a week. The success case loses nothing, because the job log
  already carries every frame as base64 — which is where they are read from.
  `ios-testflight.yml` is the exception: its `.ipa` and dSYMs are release
  artifacts that cannot be regenerated, and it is dispatch-only.
- **No code signing in CI.** `CODE_SIGNING_ALLOWED=NO`. Signing needs
  credentials and belongs to `ios-testflight.yml`.
- **No archive in CI.** `build-for-testing` plus `test-without-building`.
  Archives are release work.
- **Runner images are pinned**, never `-latest`. `macos-26` is declared in
  `.github/actionlint.yaml` because actionlint's label table predates it.

## Validating a change

```sh
actionlint .github/workflows/*.yml
```

Must exit 0 with no output.
