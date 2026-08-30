# UI Audit — AE-031

**The first audit of this project written against screens rather than source.**

Every previous UI audit here — `UIUX_FORENSIC_AUDIT.md`, and the review passes
in AE-028 and AE-029 — was written by reading code, because nothing could run
the app. This one is partly written by looking at it.

That distinction is the point of the document, so it is marked per finding:

| Mark | Means |
| --- | --- |
| 👁 | **Observed.** Seen in a screenshot from a booted simulator. |
| 🧪 | **Runtime validated.** Asserted by a UI test on a booted simulator. |
| 📖 | **Read.** From source only — the standard of every prior audit. |

---

## 1. How the evidence is produced

`AirlineEmpireUITests` boots an iPhone simulator in CI, drives the first
minute of the game, and attaches a screenshot at every step. The result bundle
is kept as an artifact for 14 days; the same screenshots are also base64'd into
the job log, downscaled, because an artifact needs a GitHub credential and the
agent doing the interface work reads logs (TD-020).

**Coverage so far is small and should not be overstated.** Three tests, one
device, portrait, light appearance:

| Screen | Evidence |
| --- | --- |
| New game | 🧪 reachable, 👁 not yet inspected |
| Home | 🧪 reachable, renders content |
| Map | 🧪 reachable, renders content |
| Network — Routes empty | 👁 observed |
| Network — Fleet empty | 👁 observed, before and after a fix |
| Aircraft market | 👁 observed |
| Finance | 🧪 reachable, renders content |
| World | 🧪 reachable, renders content |
| Route detail, aircraft detail, sheets, game over, settings | 📖 only |

---

## 2. Findings

### P1 — BUG-035, a third of the Network tab was dead space 👁 FIXED

The first screenshot this project ever produced showed the Routes/Fleet picker
floating about 40% down the screen with nothing above it, in the state every
new game starts in.

One SwiftUI default caused both the gap above the picker and the gap below the
card: `EmptyStateView` is smaller than its parent, so it centred; then
`safeAreaInset(edge: .top)` placed the picker against the *content's* top edge.
Fixed by top-aligning the empty state, and re-confirmed by screenshot — both
gaps closed with the one change, which is what a single-cause diagnosis
predicts.

**The interesting part is why it survived four UI phases.** It appears *only*
in the empty state. A list fills its parent and has nowhere to float to, so
every screen anybody would think to check looked right, and the one a new
player meets first did not.

### P2 — The app renders as light, near-default iOS chrome 👁

`docs/DESIGN_SYSTEM.md` describes glass, dusk and a premium operations-centre
feel. What a simulator in its default appearance actually shows is a light,
largely stock iOS layout: system segmented control, system tab bar, white
ground, blue accents.

**Not filed as a bug, because I do not yet know the intent.** The app may be
correctly adaptive and simply photographed in light mode — in which case the
dark appearance is the one nobody has seen, and it is the one the design
documents describe. Establishing that is one line in the UI test
(`UITraitCollection` override, or launching with the simulator in dark) and it
is the single highest-value next observation.

Until then the honest statement is: **the app has been seen in one appearance,
and it is not the one the design system is written about.**

### P2 — `¤` reads as a missing glyph 👁

Cash renders as `¤60.0M`. This is **deliberate and documented**: the world is
fictional, and `Format`'s own comment says picking a real currency "would be a
lie, and localizing an invented currency into euros would be a bigger one."
The reasoning is sound.

The observation is only available from a screenshot: `¤` (U+00A4) is drawn as a
hollow rounded box in many system faces, and at a glance on the market screen it
reads as a font-fallback error rather than as money. A player cannot tell "we
chose a neutral symbol" from "this build is broken."

Worth a decision, not a fix: keep it, or use a bare grouped number with a
`credits`-style suffix. Recorded here rather than changed, because the current
behaviour is intentional and the alternative is a design call.

*(Noted for the record: I nearly filed this as a formatting bug and stopped
after reading the code. A screenshot shows what something looks like, never
what it is for.)*

### P3 — "Fuel per s…" truncates in the market's sort picker 👁

A segmented control with four options at Dynamic Type default already clips its
longest label. It will be worse at larger sizes. Cheap fix: shorten to "Fuel".

### Confirmed working 👁

Worth recording, since these were shipped as "authored, not observed" and are
now observed:

- **Aircraft roles** — "Flagship long-haul" renders under the model name.
- **Seat-efficiency bands** — "Good fuel per seat" renders as a chip.
- **The trade sentence** — "The most seats and the most range you can field.
  Only pays on dense long routes."
- **Era-lock explanation** — "Unlocks in the International era. The whole
  catalogue; the world is the market." with a `later era` badge and a muted
  silhouette.
- **Empty states** — icon, title, message and a working call to action, on both
  Routes and Fleet.

That is AE-029's market work moving from AUTHORED to VISUALLY VALIDATED.

---

## 3. What this audit deliberately does not claim

- **No opinion on Home, Map, Finance or World.** They are proven to load and
  render content 🧪; they have not been looked at. Any statement about their
  hierarchy or density would be the same authored-not-observed claim the last
  three audits made.
- **No accessibility findings.** Dynamic Type at accessibility sizes, VoiceOver
  order and contrast ratios are all measurable on a simulator and none has been
  measured.
- **No iPad findings.** The regular-width sidebar shell has never been run.
- **No performance findings.** `docs/UI_PERFORMANCE.md` does not exist because
  nothing has been profiled; writing one now would be fabrication.

---

## 4. The pattern across three phases

Three distinct defect classes have now been found here, and no compiler can see
any of them:

| Class | Example | What catches it |
| --- | --- | --- |
| A link that resolves to nothing | BUG-029, BUG-030 | tapping it |
| A string that matches nothing | BUG-033 | a contract test |
| A control in the wrong place | BUG-035 | looking, or a frame assertion |

All three are *agreements* — between a link and a destination, a code and its
copy, a view and its container — and Swift checks none of them. The project's
412 Core tests are excellent and would not have caught one.

The correction is not more Core tests. It is that **the app must be run**, and
as of AE-031 it is.

---

## 5. AE-032 — the screen-by-screen record, updated against real frames

Every row below names its evidence. Frames come from CI runs 59 (main,
c387dde) and 60 (branch, e135c3a), decoded from the job logs with
`scripts/decode-ci-screenshots.py` and looked at; "next run" marks coverage
authored in AE-032 whose frames land with the branch's fixed run.

| Screen | Reached | Observed | Interactions | Known issues / uncertainty |
| --- | --- | --- | --- | --- |
| New game | 🧪 | 👁 (pinned dark) | Found button 🧪 | — |
| Home | 🧪 | 👁 light + darkforced + AccessibilityL | onboarding card 🧪 | date reads "2030-01-01 00:00 · Winter" — terse, deliberate |
| Map | 🧪 | 👁 world, regional, local, post-pinch — six distinct frames (run 61) | zoom buttons, double-tap and pinch all 🧪 against the published camera | pinch on hardware still needs a person |
| Network — Routes empty | 🧪 layout | 👁 light + dark | Open a route 🧪 | — |
| Network — Fleet empty | 🧪 layout | 👁 light + dark | Browse the market 🧪 | — |
| Fleet with aircraft | 🧪 | 👁 | row → detail 🧪 next run | — |
| Aircraft market | 🧪 | 👁 light + AccessibilityL | lease 🧪 (dialog-verified) | sort segment truncates "Fuel per s…"; chips fixed for accessibility sizes (AEChipRow) |
| Route sheet | 🧪 | 👁 | destination select + commit 🧪 (run 61) | commit rides a bottom bar (BUG-038) |
| Route detail | 🧪 | 👁 (run 61) | reached via the new commit bar 🧪 | assignment interaction asserted only in the flight journey |
| Aircraft detail | 🧪 | 👁 (run 61) | Ownership section asserted | run 60's first frame was the board under this name — predicate now screen-unique |
| Finance | 🧪 | 👁 light + darkforced | — | — |
| World | 🧪 | 👁 darkforced | — | — |
| Settings | 🧪 | 👁 (run 61) | mute toggle asserted | — |
| Game over | 📖 only | — | — | needs a bankruptcy path or a debug hook — NOT VERIFIED |
| iPad shell | 🧪 (sidebar found) | 👁 one frame | failed on tab-bar assumption; harness fixed | sidebar layout looks sane in the one frame; full pass next run |

Dark appearance remains the **forced** route (`darkforced`): the CI simulator
will not switch system appearance, so "the app follows the system setting"
stays 📖. Audio: the engine running and all cues decoding is 🧪 (run 60);
audibility is NOT VERIFIED and cannot be from CI.
