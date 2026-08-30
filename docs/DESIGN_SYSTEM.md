# Design System

The visual contract for `AirlineEmpireApp`. Everything here is code in
`Sources/DesignSystem/`; this document explains the reasoning, not the values —
where the two disagree, the code is right and this file is stale.

**Status: BUILT, NOT VISUALLY VALIDATED.** Every rule below compiles and every
component resolves, but nothing in this document has been seen rendered. There
is no simulator and no device in the environment this was written in
(`tasks/TECH_DEBT.md` TD-003, TD-006). Read "should" as intent, not as an
observation.

---

## 1. What the system is for

A management game shows the player a great many numbers, and almost all of the
work is deciding which ones matter. The visual system exists to answer that
question consistently, so that two screens built months apart still agree on
what *important* looks like.

Three principles, in priority order when they conflict:

1. **Hierarchy over decoration.** If a change does not make something easier to
   find, rank, or compare, it is not an improvement.
2. **Density with air.** The enemy is not whitespace; it is *undifferentiated*
   whitespace. Sixteen points between unrelated groups and sixteen between a
   number and its own label is what makes a screen read as noise.
3. **Say it once.** Any value repeated at two call sites will eventually
   disagree at one of them. This applies to spacing, to colour, and most of all
   to derived numbers — see §5.

---

## 2. Typography — `AEType`

The app had 291 `.font(...)` call sites and no type tokens. Every one named a
*system size* (`.caption`, `.subheadline`), which records how big text is and
nothing about what it is for. `.caption` was simultaneously the metric label,
the supporting sentence, the badge and the timestamp — so "restyle every metric
label" was not a change anyone could make, and there was no way to even find
them.

That is the actual cause of weak hierarchy: not wrong sizes, but no record of
which size meant what.

`AEType` names roles. Pick by what the text **is**; the size follows.

| Role | Use |
| --- | --- |
| `hero` | The one number a screen exists to show. Rare by design. |
| `screenTitle` | A screen's title where the nav bar is not carrying it. |
| `sectionTitle` | The heading over a group of rows. |
| `metric` | A figure read as a number: cash, load factor, a count. |
| `metricCompact` | A figure in a dense row, where `metric` would dominate. |
| `metricLabel` | The label naming a metric. Deliberately quiet. |
| `body` | Ordinary prose and list rows. |
| `secondary` | A row's supporting detail. |
| `caption` | Timestamps, units, footnotes. The smallest thing to read. |
| `badge` | Text inside a pill. |
| `code` | An airport or aircraft code, where fixed width is the meaning. |

**Weight carries hierarchy more cheaply than size.** The sizes stay close
together and the weights do the work, which is also what stops Dynamic Type
from tearing layouts apart at the accessibility sizes.

Every metric role is `monospacedDigit()`. A number that ticks while the
simulation runs must not reflow the text beside it.

---

## 3. Containers — card, panel, strip

The app reached for `AECard` 40 times. A screen made entirely of cards has no
hierarchy: when every group is a raised rounded rectangle, being one stops
meaning anything, and the eye receives a list of equal boxes instead of a shape.

Three weights, in descending order:

- **`AECard`** — glass, elevated. Marks something that deserves separating from
  its neighbours. Use sparingly; if a screen has more than three, at least two
  of them are wrong.
- **`AEPanel`** — a flat tinted ground, no glass, no shadow. For things that
  merely belong together.
- **Nothing** — a `VStack` with a `AESectionHeader`. The default. Most groups
  need a heading and spacing, not a container.

**`AEMetricStrip`** is the dense case: several metrics sharing one panel.
`StatTile` gives each metric its own glass card, which is right for six
tappable headline figures and wrong for the eight supporting numbers in a
summary header — as eight cards those cost most of a screen and read as eight
separate claims rather than one picture.

It takes an **array of `AEMetric`**, not a `@ViewBuilder`, and that is the
whole design. The first version took a builder, which hands over one opaque
child; the only fallback available was `ViewThatFits` between an `HStack` and a
`Grid` holding a single `GridRow`. Those two lay out identically, so the
"fallback" was exactly as wide as the thing it was meant to rescue and nothing
ever wrapped — a nine-metric fleet strip would have run off the edge of a
phone. With an array it uses a real adaptive `LazyVGrid`: about three columns
on the narrowest iPhone, more as width allows, and the same strip serves three
metrics or nine with no decision at the call site.

---

## 4. Buttons — `AEButtonRole`

Before this the app had `.aePress` (no chrome at all), `.bordered` and
`.borderedProminent`: three levels, none named for meaning, and destructive
actions distinguished only by whoever remembered a red tint.

| Role | Weight | Rule |
| --- | --- | --- |
| `.aePrimary` | Filled accent | The action a screen is for. **At most one per screen.** |
| `.aeSecondary` | Outlined accent | A supporting action. |
| `.aeTertiary` | Text only | Available, deliberately quiet. |
| `.aeDestructive` | Outlined red | Irreversible or expensive. |

A destructive action is **never** the loudest thing on screen. It should be
findable, not inviting — filled red is an invitation.

`.aePress` remains correct for a *surface* that happens to be tappable: a card,
a row, a map marker. It is not a button weight; it is the absence of one.

---

## 5. Derived numbers live in Core

The rule that matters most, and the one with teeth.

Home, the Routes board and the Fleet board each wanted the same aggregates —
how many routes are earning, how full the aeroplanes are, how much of the fleet
is working. Each derived them in a view body. The risk is not performance; it
is **disagreement**: two screens answering the same question with different
numbers, and no test able to catch it because neither number is wrong on its
own.

`NetworkSummary` and `FleetSummary` (Core, `ReadModels.swift`) compute them
once, and `SummaryModelTests` holds each summary against the per-row model it
summarises. Views format; they never calculate.

Two conventions inside those types:

- **`nil` is not zero.** No aeroplanes is a different claim from empty
  aeroplanes, and `0%` load factor for an airline that has never flown is a
  lie. Optionals render as `—`.
- **Weighted, not averaged.** Network load factor is seats sold over seats
  flown, not the mean of the per-route rates — one daily widebody and one
  weekly turboprop are not two equal opinions about how full the airline is.

---

## 6. Colour

Semantic only. The palette was already disciplined — an audit of the whole app
found three raw colour literals — so this records the existing rules rather
than changing them.

| Token | Means |
| --- | --- |
| `positive` | Profit, health, a good trend. |
| `negative` | Loss, danger, a failed action. |
| `caution` | Attention, not alarm. Idle aircraft, wear, a warning. |
| `accent` | Interactive and selected. |
| `mutedText` | Secondary and supporting. |
| `fare`, `owned`, `leased` | Category hues, for badges only. |

**Colour is never the only carrier.** A losing route shows a minus sign and a
figure; the red is confirmation, not information. This is an accessibility
requirement and it is also just correct — the player reading in sunlight is not
a special case.

---

## 7. Motion — `AEMotion`

Three curves, named for what happened: `selection` (a tap changed something),
`content` (data arrived), `screen` (a view swapped). Screens name a feeling, not
a duration, so the whole app retimes in one place.

Numbers that change while the simulation runs use `.contentTransition(.numericText())`.
At 16× speed rolling digits are the difference between a dashboard that is
alive and one that flickers.

`.aeAnimation` asks the system about Reduce Motion rather than relying on
SwiftUI's defaults, which soften some animations and leave others alone.

---

## 8. Refusals — `Rejections`

Core refuses commands with a typed `CommandRejection`: a stable `code` and a
message written for whoever is reading the simulation. That is not the same
audience as the player. Shown verbatim, an over-long route reported:

    MR180 range 2750 km < route 4100 km

which is an inequality, not an explanation.

`Rejections.present` maps the **code** — the contract — rather than the message,
so Core may reword itself freely. Each mapping answers three questions: what
happened, why, and what to do next. The third is the one that was missing.

Codes describing broken invariants (`unknown…`, `noSuch…`, `notYours`) are
collapsed into one honest apology. A player can neither cause nor fix "Unknown
airline"; repeating it at them is noise.

---

## 9. Empty states

Every empty screen states what is absent, why, and offers the action that fills
it. An empty list is a moment where the player has decided to do something and
found nothing — the most useful place in the app to put a button.

`EmptyStateView` takes an optional action for exactly this. Where a screen has
no sheet of its own to raise, the action is `nil` and the message still has to
carry its own weight.

---

## 10. What this system does not yet cover

Stated plainly, because a design system that claims completeness it lacks is
worse than none:

- **Nothing here has been seen.** No simulator, no device. Layout, contrast in
  both appearances, Dynamic Type at accessibility sizes, and whether the metric
  strip actually wraps as intended are all unverified.
- **iPad** has a sidebar shell but its screens are phone layouts in a wider
  column. §31 of the brief asks for more; this is not that.
- **The type scale is not yet applied everywhere.** `AEType` exists and new and
  reworked code uses it; several hundred original `.font(...)` call sites
  remain. Migrating them mechanically without seeing the result would be
  changing the app blind, so they are being converted screen by screen as each
  is reworked.
