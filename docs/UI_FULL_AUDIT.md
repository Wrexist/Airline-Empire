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
| Map | 🧪 | 👁 six distinct zoom/pinch frames (run 61); airport labels in the "Sjövik (Stockholm)" form with graceful city/code fallback (run 63, iPhone + iPad) | zoom buttons, double-tap and pinch all 🧪 against the published camera | pinch on hardware still needs a person |
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
| iPad shell | 🧪 full five-tab pass (run 63) | 👁 all five tabs at regular width | sidebar navigation driven by the tab ladder | detail screens on iPad still blocked by the market-sheet lease step |

Dark appearance remains the **forced** route (`darkforced`): the CI simulator
will not switch system appearance, so "the app follows the system setting"
stays 📖. Audio: the engine running and all cues decoding is 🧪 (run 60);
audibility is NOT VERIFIED and cannot be from CI.

---

## 6. AE-033 — the post-immersion audit, from run 74's frames

Every finding below was read off a decoded CI screenshot of run 74
(commit e0958d7) or traced to the line that produces it. Nothing here is
inferred from source alone; where a claim is READ rather than OBSERVED it
says so. Ordered by how much each one costs a player.

### 6.1 P1 — the map's help line is drawn underneath the tab bar

**OBSERVED**, `KEY-81-flight-in-progress`. The idle hint — "Tap an airport,
a route or an aircraft." — renders as a glass capsule at the bottom of the
map chrome and the floating iOS 26 tab bar sits directly on top of it. It
is not merely crowded; the sentence is unreadable.

**Root cause, READ:** `MapView.swift:82` applies
`.ignoresSafeArea(edges: .bottom)` to the ZStack that holds *both* the
canvas and the chrome. The canvas should bleed to the screen edge; the
chrome must not. The taller "Your airline begins here" card survives only
because it is tall enough to poke out above the bar — which is why this
was invisible for the whole of AE-032: every early-game frame shows the
card, and the hint only appears once the player has routes.

**Fix:** let the canvas ignore the safe area and leave the chrome inside it.

### 6.2 P2 — a route that has never flown reports a perfect record

**OBSERVED**, `KEY-91-route-detail`: a brand-new ARN–LHR with no aircraft
assigned shows **Punctuality 100%, Completion 100%** while, three rows up,
Load factor correctly reads 0% and the banner says the route is not flying.

The screen is claiming operational performance for operations that have
never happened — the same class of error as a screenshot named `dark`
that rendered light. Load factor already knows how to say nothing; these
two should use `—` until the route has flown at least once.
(`RoutesView.swift:409-410`.)

### 6.3 P2 — the aircraft market collides with itself at accessibility type

**OBSERVED**, `KEY-97-dynamictype-market`. At AccessibilityL the aircraft
name wraps to three lines while the silhouette stays vertically centred
beside it, so the glyph lands in the middle of the word "Longline", and
the "later era" chip overlaps the title's last line. The AE-032 pass fixed
the *metric strip* at this size (whole figures, no "$110. / 0M"), but the
row header above it was never re-checked.

### 6.4 P3 — the Home pulse strip orphans its fourth metric

**OBSERVED**, `KEY-20-shell-home`: "in the air / load factor / aircraft
used" sit in one row, and "month to date" drops alone onto a second,
reading as a stray rather than a fourth member of a set.

**Root cause, READ:** `AEMetricStrip` lays out an adaptive grid with an
88 pt column floor (`Components.swift:745`); four metrics at 88 pt on a
390 pt-wide phone fit three across. Either a fixed four-column layout at
compact width or a 2×2 grid would read as one picture, which is what the
call-site comment says it is for.

### 6.5 P3 — the route sheet says "From" twice, and the search box sits below the commit

**OBSERVED**, `KEY-06-route-sheet-destination-picked`. The section header
is `Text("From")` and the picker inside it is `Picker("From", …)`, so the
word stacks on itself (`RoutesView.swift:801` and `:847`). Separately,
iOS 26 anchors `.searchable` to the bottom of the sheet, which puts the
search field *below* the "Open this route" bar added for BUG-038 — so the
reading order is browse, commit, then search.

### 6.6 P3 — dead space on World (and a correction about the empty boards)

**OBSERVED**, `KEY-24-shell-world`. World is four navigation rows over
roughly half a screen of nothing. It is a hub with room for the world's
own conditions, which a player otherwise had to read off their own
dashboard.

**Correction to this finding's first draft**, which also named the empty
Fleet and Routes boards (`KEY-41-layout-fleet-empty`). On a second look
that half is *not* a defect: each empty state already carries its next
action ("Browse the market", "Open a route") directly under the picker,
which is exactly the BUG-035 shape working. Space under a call to action
is ordinary iOS, and filling it would be decoration — the thing this
project's own standards are against. Recorded rather than quietly
dropped, because an audit that only ever adds findings is not an audit.

### 6.7 Not a defect, but the evidence is weaker than its name

`testLightAppearanceMapForComparison` produces a frame
(`KEY-61-light-map`) that is indistinguishable from the dark one. That is
**correct behaviour** — the map ZStack pins `colorScheme = .dark`
deliberately (BUG-036, `MapView.swift:60`), so there is no such thing as a
light map. The test name promises a comparison it cannot make. Rename it,
or point it at chrome that does vary.

### 6.8 The AE-033 work itself, re-checked against the frames

| Claim | Status |
| --- | --- |
| World zoom labels only hubs + home | 👁 OBSERVED (`KEY-71`) |
| Regional/local ladder reveals majors then secondaries | 👁 OBSERVED (`KEY-72`, `KEY-73`) |
| Day/night terminator, correct hemisphere and phase | 👁 OBSERVED + measured (brightness profile, run 73) |
| Player route glow | 👁 OBSERVED (`KEY-81`, `KEY-82`) |
| Moving aircraft along the great circle | 👁 OBSERVED (`KEY-81`, `KEY-82`) |
| "Airline" tab, light and dark | 👁 OBSERVED (`KEY-22`, `KEY-52`) |
| Global-hub second ring | ⚠️ drawn, but too small to resolve in a downscaled log frame — NOT VERIFIED |
| Selection pulse | ❌ NOT VERIFIED — no automated frame selects an airport |

The last two are the honest gap in this phase: both are real code on every
render, and neither has been *seen*. A journey leg that taps an airport
and captures the panel would close both at once, and is the single
highest-value addition to the harness.

### 6.9 Fixed — commit 6f6b0ef

All six findings above were fixed in one pass, and the harness gained the
leg §6.8 said was missing:

| Finding | Fix |
| --- | --- |
| 6.1 map hint under the tab bar | the canvas bleeds past the safe area; the chrome no longer does |
| 6.2 perfect record with no history | `RouteCardModel.hasFlown`; the screen shows `—` until a flight operates |
| 6.3 market row collision | silhouette and badge take their own row above the accessibility threshold |
| 6.4 orphaned fourth metric | four metrics lay out 2×2; other counts keep adaptive columns |
| 6.5 doubled "From", search below commit | header dropped; search pinned above the list it filters |
| 6.6 World dead space | the hub ends with fuel per ton and the economic index |
| 6.8 pulse and hub ring unseen | `testSelectingAnAirportOpensItsPanel` — taps until the map reports a selection, then photographs it |

The new test is deliberately a skip rather than a failure when its taps
find no marker: a synthetic tap landing between two markers is not the
app being wrong, and claiming the pulse on a frame that does not show it
is the exact failure mode §4 of this document exists to prevent.

Core 414/414 on Linux after the read-model change.

### 6.10 Verified against run 75's frames, and one regression caught

`testSelectingAnAirportOpensItsPanel` **passed on its first run** — 14 of
15 UI tests green, the sole failure being the same lease-tap flake as runs
73 and 74. Each fix, checked against the frame rather than assumed:

| Fix | Frame | Verdict |
| --- | --- | --- |
| 6.1 map hint | `KEY-81` | 👁 **fixed** — "Tap an airport, a route or an aircraft." now sits fully legible above the tab bar |
| 6.3 market row | `KEY-97` | 👁 **fixed** — silhouette on its own row, name at full width, no collision |
| 6.4 pulse strip | `KEY-20` | 👁 **fixed** — a clean 2×2, no orphan |
| 6.5 route sheet | `KEY-06` | 👁 **fixed** — one "From", search above the list, commit at the foot |
| 6.6 World hub | `KEY-24` | 👁 **partly** — fuel and economy are there, but they read as a footnote and most of the dead space remains. Honest verdict: a small improvement, not a solved screen |
| 6.2 punctuality `—` | — | ❌ **NOT VERIFIED** — needs a route that exists and has never flown; no journey reaches that state, and the change is a two-line conditional on a field Core now supplies |
| 6.8 selection pulse | `KEY-86`, `KEY-87` | 👁 **OBSERVED at last** — the ring around Arlanda, in the first frame in this project's history to open an airport panel |

**The regression, caught by measurement rather than by eye.** Comparing
the top strip of run 74's and run 75's map frames: median RGB sum 54 →
765. The status bar had gone from the map's near-black to system white.
Cause: a bare `Color` background bleeds into the safe areas on its own,
and 6.1's fix wrapped it in `.ignoresSafeArea(edges: .bottom)` — the
moment a `Color` is wrapped in a modifier it stops bleeding anywhere it
is not told to. Fixed by ignoring every edge on the background while the
chrome stays inside the safe area, which is what 6.1 actually needed.

Worth stating plainly: the fix for a defect found by looking introduced a
second defect that looking nearly missed. A three-line pixel comparison
against the previous run caught it in seconds.

### 6.11 P1 — the airport tier ranked cities, not airports

**OBSERVED**, `KEY-86` — and only observable because §6.8's new test
opened the first airport panel ever photographed. Arlanda's card read
**"6"** above the words **"small field"**.

Two defects in one strip of four facts, one cosmetic and one structural.

The cosmetic half: `MapFact(label: tierLabel, value: prominence * 100)`
put the tier in the *label* slot and a bare unitless number in the value —
"6" of nothing. It now reads `size / regional`.

The structural half is the real finding. `MapModel.tier` ranked airports
on `prominence` alone — metro population over the largest metro — so it
was measuring **cities, not airports**:

| | metro | slots/day | old tier | new tier |
| --- | --- | --- | --- | --- |
| Frankfurt | 2.7 M | 1,140 | small field | global |
| Amsterdam | 2.9 M | 1,178 | small field | global |
| Dubai | 3.6 M | 1,500 | small field | global |
| Singapore | 5.9 M | 1,292 | regional | global |
| Gothenburg | 1.05 M | 150 | small field | small |

Tokyo's catchment genuinely is fifteen times Frankfurt's, so on
population Frankfurt *is* small; as an airport it is among the busiest on
earth. Forty-seven of ninety-four airports were "small field".

**This was not cosmetic, because the tier drives the map's label ladder.**
The reveal thresholds added earlier in AE-033 — global always, major from
2.8×, regional from 5.0×, small from 8.0× — were being applied to a
ranking of city size. Three of Europe's largest hubs stayed hidden until
the deepest zoom. The density work was correct and was reading the wrong
input.

**Fix:** the score is now the larger of the two claims to importance — the
city's catchment, or the airport's own capacity share — with capacity
discounted slightly so a city of real size still outranks a big empty
field on equal slots. The runway gates are untouched: a huge catchment
with a short runway is still not a global hub. The distribution moves
from 10/12/25/47 (global/major/regional/small) to 23/20/37/14, which is
recognisably the real world.

`MapPresentationTests.tiersAreDistributed` asserted "a bigger catchment is
never a lower tier", which is now false *by design* — it encoded the bug.
Replaced with the invariant that actually holds and is worth holding: with
the same runway class, an airport at least as large in **both** catchment
and capacity can never sit in a lower tier. Verified: zero violations
across all 94, and the smallest global's score (0.72) clears the largest
small's (0.17) with room.

Core 414/414 after the change.

### 6.12 Run 76: the regression closed, and the cost of §6.11 seen

The status-bar regression is **fixed, confirmed by the same measurement
that found it** — median RGB sum over the top strip: run 74 (baseline) 54,
run 75 (regressed) 765, run 76 **54**. Exactly back to the ground truth.

`KEY-86` shows Arlanda's card reading **`regional / size`** in place of
`6 / small field`. The tier fix landed and the panel now says something
true and something useful. `KEY-71` confirms world zoom is still sparse —
five labels (ARN, JFK, IST, DEL, HND) — so the wider `.global` tier did
*not* flood the world view; the budget held.

**But §6.11 had a cost, and the frames show it.** Comparing the same crop
of western Europe at regional zoom across runs 75 and 76: the tier fix
correctly surfaced Madrid, which had been hidden as a "small field" — and
it also put two dozen airports at their true, larger marker size, so
**labels now run straight through marker discs**. `KEY-72` shows "Charles
de Gaulle (Paris)" with two discs sitting in the middle of the words, and
"Barajas (Madrid)" overlapping both its own marker and the SPAIN country
label.

The placer had only ever avoided *other labels*. That was survivable while
most markers were small dots and stopped being so the moment the airports
were sized honestly — a latent flaw in the layout that the data fix
exposed rather than caused.

Two changes, both in this commit:
- `MapLabelLayout.place` now takes the renderer's own `markerRadius` and
  seeds its occupied set with every marker disc, so text dodges dots as
  well as text. An airport's own disc is exempt: its label sits above it
  by design. Passing the radius rather than duplicating it means the
  placer and the renderer cannot disagree about how big a dot is.
- The marker ladder steps down (global 5.0 → 4.4, major 4.0 → 3.5,
  regional 3.0 → 2.6, small 2.2 → 2.0). The *ratios* are what carry the
  hierarchy; the absolute sizes were tuned when ten airports were global
  and twenty-three now is a crowd at the old scale.

**Run 77 — the first fully green run since 69**, 15 of 15 including the
lease journey that had flaked for five runs straight. The status bar held
at 54 on every map frame, world zoom stayed sparse at four labels, and
**no text crosses a marker disc anywhere in the regional frame**. The
collision fix works.

**And it starved the map, exactly as feared.** Run 76 labelled "Heathrow
(London)", "Charles de Gaulle (Paris)", "Barajas (Madrid)"; run 77 shows
"AMS", "Madrid", "FCO" — and **London and Paris carry no label at all**,
the two largest airports in the view reduced to anonymous rings. The
degradation ladder (full name → city → code) was doing its job, but the
placement rule underneath it had only one position to offer: directly
above the marker. In a dense corner that space belongs to a neighbour's
disc, so the label was *refused* rather than moved.

Fixed by giving the placer the other three sides — above, then below,
then right, then left — which is the ordinary cartographic answer and
costs three rectangle tests per candidate. Also NOT YET VERIFIED; the run
that confirms it is the fourth in a row where a fix for something found by
looking had to be checked for what it broke.

Run 76: 13 of 15 UI tests green. Both failures are the lease-tap flake
(one surfacing as a screenshot timeout inside the retry loop); every test
touching this work — selection, zoom and labels, dark tabs, accessibility,
the flight journey — passed.

### 6.13 Runs 77–78: converging, one frame at a time

Three rounds on the same crop of western Europe, each fixing what the last
one revealed:

| Run | Labels in the crop | Problem |
| --- | --- | --- |
| 76 | Heathrow (London), Charles de Gaulle (Paris), Barajas (Madrid), Rome, Istanbul | text drawn straight through marker discs |
| 77 | AMS, Madrid, FCO, Istanbul | no collisions — but London and Paris lost their labels entirely |
| 78 | …s de Gaulle (Paris), AMS, Madrid, Rome, Istanbul | Paris recovered by placing left — and pushed off the screen edge |

Run 78 proved the four-sided placement works: Paris came back, Rome
recovered its name, and **no text crosses a disc anywhere in the frame**.
It also showed the last gap — the placer had no idea where the screen
ends, so "left of the marker" for a westerly airport means half the label
outside the viewport. `place` now takes the viewport and refuses any box
not fully inside it, which costs one `contains` per candidate position.

The status bar held at 54 on every map frame across runs 76, 77 and 78.

**The lease flake, root-caused at last.** Run 78's `LEASE-ATTEMPT-1` frame
shows a **"Buy used (8y)?"** dialog — the row immediately *above* "Lease" —
over a perfectly healthy market, while the identical helper leased
successfully inside the flight journey in the same run. The cause is not
the app and not really the runner: a coordinate tap resolves the element's
frame and then fires at that point, and the helper taps immediately after
dragging the row into view, so the frame it aims at is the row's position
*before* the scroll momentum finishes. `waitUntilStill` polls the frame
until two consecutive reads agree before the tap. Not a skip, not a
retry-until-green: the tap now aims at where the row actually is.

### 6.14 What remains untestable here, unchanged from AE-032

System-appearance following, audio audibility, VoiceOver order, contrast
as rendered, hardware performance, and the game-over screen. The iPad
detail journey still fails on the same market-sheet tap flakiness as the
phone (runs 73 and 74 both lost `testAcquireAircraftThenOpenARoute` to it
while the identical helper leased successfully inside the flight journey
minutes later — automation, not app).
