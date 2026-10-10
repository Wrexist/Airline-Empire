# Airline Empire — notes for Claude Code

Native iOS airline management sim (SwiftUI app + SwiftPM simulation core).
Owner: Isac (Wrexist). Start with the navigation table in `README.md`;
`tasks/TODO.md` is the active task list.

## Layout

- `AirlineEmpireCore/` — the simulation, Swift 6 SwiftPM package. Builds and
  tests on Linux (`scripts/setup-linux-toolchain.sh`).
- `AirlineEmpireApp/` — the iOS app. `project.yml` is the source of truth;
  generate the project with XcodeGen and never commit `*.xcodeproj`.
- `docs/` — design and audit records; `tasks/` — plan, decisions, bugs.

## Before pushing

- `cd AirlineEmpireCore && swift build -c release -Xswiftc -warnings-as-errors && swift test`
- App code compiles only on macOS: rely on the `CI` workflow's
  `iOS app (xcodebuild) · compile` job when working from Linux.

## 3D Hub View (target 1.1)

Read `docs/HUB_HANDOFF.md` first. It holds the current state, the shot-by-shot
gap list against the owner's reference clip, the ordered work plan, and the
render-and-compare loop in `scripts/hub-review/`. 3D models are made with Meshy +
Blender MCP following `docs/HUB_MODEL_PIPELINE.md`; validate every model with
`scripts/hub-models/check_usdz.py`. The reference clip is
third-party work: never commit it or frames cut from it (`.hub-review/` is
git-ignored).
