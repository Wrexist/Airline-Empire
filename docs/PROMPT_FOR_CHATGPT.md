# Meta-prompt: ask ChatGPT to write the next master prompt

Copy everything between the lines below into ChatGPT.

---

You are going to write a **master prompt** — a long, structured brief that will
be handed to an autonomous coding agent (Claude Code) working on an iOS game
repository. I will give you the project's real state. Your job is to turn it
into the next phase's brief.

Do not write code. Do not solve the problems. **Write the prompt.**

## The project

**Airline Empire** — an offline, single-player airline tycoon game for iOS.
Swift 6, SwiftUI, SwiftPM. Two halves:

- **`AirlineEmpireCore`** — a pure, deterministic simulation. 15-minute ticks,
  seeded RNG, a typed command pipeline (`Command` → validate → apply), versioned
  saves (v11), ~412 tests, builds and tests on Linux. This is the healthy half.
- **`AirlineEmpireApp`** — the SwiftUI app. Compiles only on macOS/Xcode, via
  an XcodeGen manifest (`project.yml`). This is the half where the defects are.

The architectural seam is deliberate and load-bearing: **policy lives in Core
(so it is testable on Linux), platform lives in the app.** The UI must never
recompute anything the simulation owns.

## How this project has actually gone wrong, historically

This matters more than any feature list, and the master prompt you write must
be built around it.

**Four consecutive phases of interface work shipped as "authored, not
observed."** The build environment is Linux, so the app could be parsed but
never compiled and never run. Every UI claim was a claim about source code.

Then a UI test target and a CI job that boots a real iPhone simulator were
added, and screenshots started arriving. Within minutes they found defects
that four phases of code review had missed. The pattern in all of them is the
same: **they are agreements that the Swift compiler does not check.**

| Defect class | Real example | What actually catches it |
| --- | --- | --- |
| A link that resolves to nothing | a `NavigationLink(value:)` with no matching `navigationDestination` — silently inert | tapping it |
| A string that matches nothing | three refusal-code mappings that could never fire | a contract test |
| A control in the wrong place | a third of a tab was dead space; the section picker floated 40% down the screen, in the state every new game starts in | a frame assertion, or looking |
| Two correct decisions that disagree | a permanently-dark map canvas under chrome whose glass follows the *system* appearance: white text on a near-white panel in light mode | looking |
| A symbol that is right in intent and wrong on screen | `¤` (generic currency sign) was chosen because the world is fictional; it renders as a hollow box, so every cash figure read as a font error | a human looking at a screenshot |

Three further traps this project has fallen into and that your prompt should
explicitly guard against:

1. **`swiftc -parse` proves nothing.** It is syntax only — it resolves no
   names, checks no conformances, and does not catch an argument-order error.
   Only a real Xcode build does.
2. **A test can manufacture evidence.** A dark-mode test set the simulator to
   dark, captured five screens, named them "dark", and passed — and every
   screenshot was light. A guard was added; the guard was put on a screen that
   is pinned dark by design, so it *also* passed for the wrong reason. Passing
   is not the same as validating.
3. **A test can drive the wrong control and blame the app.** A query matching
   `label BEGINSWITH "Lease"` hit a *"Lease term: 60 months"* stepper, leased
   nothing, and reported a silent app failure. The screenshot is what revealed
   it.

## Current state

**Green:** Core builds and its full test suite passes. Release tooling and
store-listing validation pass.

**The app compiles**, and a UI test target drives a booted simulator in CI,
attaching a screenshot at every step. Because artifacts need a credential the
agent lacks, screenshots are also base64'd into the job log, downscaled.

**Recently landed, all UNVERIFIED VISUALLY** (pushed, but no render has been
looked at yet):
- Real geography: Natural Earth coastlines at three levels of detail chosen by
  zoom, plus lakes and political borders, replacing a 631-point hand trace.
- 175 country labels with Unicode flag emoji, placed around airport labels.
- Pinch-to-zoom that anchors on the fingers, resists past the zoom limits,
  coasts on a flick, and zooms about a double-tapped point.
- Flight trails: the flown portion of a route brightened behind each aircraft.
- A bounding-box cull so off-screen coastline is not projected.
- A map screenshot in light appearance to confirm the chrome fix.
- A UI test that leases an aircraft, opens a route, assigns it, runs the clock
  at 16×, and waits for a real flight — polling the map's own accessibility
  value ("N aircraft in the air") rather than guessing a duration.

**Known open, honestly stated:**
- **Dark appearance has never been validated.** The guard is now correct;
  nothing has passed through it.
- Route detail, aircraft detail, sheets, game over and settings have never
  been rendered.
- iPad regular-width shell: never run.
- Dynamic Type at accessibility sizes, VoiceOver order, contrast ratios: never
  measured.
- No performance profiling of any kind. `ae-map-bench` measures the map model,
  not the renderer.
- Audio: 58 `.wav` files ship and **not one has ever been heard.**
- Tech debt with open items includes: most call sites still use raw `.font()`
  instead of the type scale; summary read models not wired into every screen;
  nothing checks that a value-based navigation link can resolve; five aircraft
  types share one silhouette; the screenshot bridge is a log scrape.
- App Store: the listing has never been pushed. Blocked on screenshots from a
  real mid-game world, and on three `REPLACE_ME` placeholders (App Review
  contact, copyright entity, support email) that only the owner can fill.

## Hard constraints the master prompt MUST carry forward

State these as non-negotiable:

- **Do not rebuild `AirlineEmpireCore`.** It works and it is tested.
- **No backend. No Supabase. No network calls of any kind.** The app declares
  `ITSAppUsesNonExemptEncryption: NO` on the grounds that it makes none, and
  the privacy manifest is built on that. Offline is a feature.
- **No multiplayer, no Three.js, no web stack.**
- **The UI must not recompute simulation values** — no depreciation, no
  reliability, no range, no eligibility. Read them from Core or from a tested
  read model. Never build a shadow simulation in SwiftUI.
- **No third-party imagery.** No airline logos, no real liveries, no
  manufacturer artwork. Everything visual is drawn procedurally at runtime;
  the shipping app contains exactly one image file (the icon). Preserve that.
- **Never claim visual quality without observing it.** If something cannot be
  rendered and looked at, the honest report is "authored, not observed" — say
  so plainly rather than implying validation.
- **Do not mass-generate before validating a pipeline.**

## What I want you to produce

A single master prompt, ready to paste to a coding agent. It must:

1. **Name the phase** and state its one central goal in a sentence.
2. **Be organised as numbered sections** (roughly 15–40), each a specific,
   checkable piece of work — not vague aspirations.
3. **Prioritise explicitly as P0 / P1 / P2**, and justify the ordering.
   Weight the ordering toward *closing the gap between what is claimed and
   what has been observed*, because that gap is this project's dominant
   failure mode. A feature nobody has looked at is worth less than proof that
   an existing one works.
4. **Include an explicit "Do NOT" section** carrying the hard constraints
   above verbatim in substance.
5. **Demand evidence.** Every claim of completion must say whether it was
   *observed* (a screenshot from a real render, looked at), *asserted* (a test
   on a booted simulator), or *read* (source only). Require the agent to state
   plainly what it could not verify.
6. **Specify the final report format** the agent must produce: what was done,
   what was found, what was NOT done and why, and what remains unverified.
7. **Include a section on the traps above** — parse-is-not-compile, tests that
   manufacture evidence, tests that drive the wrong control — instructing the
   agent to treat a passing test as a claim requiring evidence, not as proof.

Decide the priorities yourself from the state I have given you. If you think
the most valuable next phase is verification rather than features, say so and
write that prompt — do not pad it with new features to look ambitious.

Write the master prompt in full. Do not summarise it or describe what it would
contain.
