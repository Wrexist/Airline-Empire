# Aircraft Asset Bible

How aircraft are drawn, everywhere they appear. Companion to
`docs/DESIGN_SYSTEM.md`; the artwork itself is code, in
`AirlineEmpireApp/Sources/Map/AircraftSilhouette.swift`.

**Status: BUILT, NOT VISUALLY VALIDATED.** Every mapping below resolves and
compiles. None of it has been seen rendered — there is no simulator and no
device in the environment this was written in (`tasks/TECH_DEBT.md` TD-003,
TD-006). Read the art-direction rules as intent, not as observation.

---

## 1. The system in one line

**Four planforms, drawn as vector paths, tinted by context, scaled by class.**

There are no image assets. Nothing is fetched, nothing is bundled, nothing can
404. An aircraft's artwork is a `Path` built from its category, which means it
is resolution-independent, themeable, and impossible to leave missing — the
failure mode this document exists to prevent cannot occur, because there is no
file to forget.

That is worth stating plainly because MASTER PROMPT 5 §8 asks that "no aircraft
should silently fall back to broken or missing artwork". In this architecture
none can: `AircraftSilhouette.path(for:)` is total over `AircraftCategory`, and
the compiler enforces it.

---

## 2. Six categories, four planforms

`AircraftCategory` has six cases. The map draws four.

| Category | Planform | Relative scale |
| --- | --- | --- |
| `turboprop` | turboprop | 0.82 |
| `regionalJet` | regionalJet | 0.90 |
| `narrowbody` | narrowbody | 1.00 |
| `largeNarrowbody` | narrowbody | 1.00 |
| `widebody` | widebody | 1.22 |
| `largeWidebody` | widebody | 1.22 |

**Two pairs share a shape, deliberately.** At map scale a narrowbody and a
large narrowbody are the same object: the difference is 40 seats and 1,000 km,
neither of which has a silhouette. Drawing them apart would be a distinction
the player cannot see and a second path to keep consistent.

**It is a real limitation elsewhere.** In the market and on a detail hero there
*is* room to tell them apart, and today there is not. A player comparing an
MR180 against an MR220 sees the same drawing at the same size beside two
different seat counts. Recorded as `TD-014`; the fix is a scale factor keyed on
category rather than planform, not a fifth and sixth path.

---

## 3. Art direction

The silhouettes are **plan view** — the aircraft seen from directly above, nose
up. Not the ¾ elevated perspective MASTER PROMPT 5 §7 offers as an option, and
the reason is that the map came first: a plan-view shape can be rotated to a
heading and read correctly at any angle, which a perspective render cannot.
Having one aircraft language rather than two is worth more than the extra
presence a hero render would give the detail screen.

Rules that hold everywhere:

- **One silhouette per category, one orientation, one weight.** A shape is
  never redrawn for a screen; it is scaled and tinted.
- **Fill, never stroke.** A stroked outline disappears below about 16 pt; a
  filled shape stays readable down to roughly 10 pt, which is the size the map
  uses at world zoom.
- **No internal detail.** No windows, no engine cowls, no registration. Detail
  that vanishes at small sizes is detail that costs contrast at every size.
- **Colour is state, not identity.** The shape says what class of aeroplane it
  is; the tint says whose it is and what it is doing. They are independent, and
  neither is ever the only carrier of its meaning.
- **No manufacturer or airline reference.** Every type in the catalog is
  fictional (`AV`, `KT`, `MR`, `NA`, `PA` prefixes) and the shapes are generic
  planforms, not any real aircraft's outline.

---

## 4. Where each asset is used

| Surface | Source | Size | Tint |
| --- | --- | --- | --- |
| Map, world zoom | `placed(..., simplified: true)` — **a wedge, not the planform** | 9 pt (rivals 7.0) | Airline livery |
| Map, regional zoom | `placed(..., simplified: false)` | 13 pt × planform scale (rivals 10.1) | Airline livery |
| Map, local zoom | `placed(..., simplified: false)` | 18 pt × planform scale (rivals 14.0) | Airline livery |
| Market card | `AircraftShape(category:)` | 34 × 34 | `AETheme.accent`, or `mutedText` when era-locked |
| Fleet row | `Vocab.categoryIcon` (SF Symbol) | caption | `AETheme.accent` |
| Aircraft detail header | `AircraftShape(category:)` | 44 × 44 | **the airline's livery colour** |

**At world zoom there is no silhouette.** `MapPresentation.simplifiedAircraft`
is true at that level, so every aircraft draws as the same wedge whatever its
category. That is the right call — at 9 pt a planform is a smudge, and the
wedge reads as a direction, which is the only thing the marker is being asked
for at that zoom. It does mean the category artwork exists for two of the three
zoom levels, and the level a player spends most time at is the one without it.

Rivals draw at **0.78×** the player's size at every level, and are dropped
entirely at 16× speed. That is where §42's "visually subordinate" is actually
enforced.

The detail header is the one surface tinted by **livery** rather than accent, so
a player's own fleet reads as theirs.

**The fleet row is the inconsistency.** It uses an SF Symbol rather than the
silhouette, so the one screen a player scans most often distinguishes a
turboprop from a widebody by a system glyph that is nearly the same for both.
Recorded as `TD-015`. It is a small change and it was left out of AE-029
deliberately: swapping it without being able to look at the result risks
unbalancing a row whose spacing is already tight, and this phase had no way to
check.

---

## 5. Per-type asset mapping

All fourteen types, with the artwork each resolves to. Nothing here is
per-type: the mapping is entirely by category, which is why there is no
possibility of a missing entry.

| Code | Model | Category | Planform | Scale | Role shown in market |
| --- | --- | --- | --- | --- | --- |
| `NA70` | 68 seats, 1,450 km | turboprop | turboprop | 0.82 | Short-field regional |
| `KT72` | 74 seats, 1,600 km | turboprop | turboprop | 0.82 | Short-field regional |
| `AV90` | 88 seats, 2,750 km | regionalJet | regionalJet | 0.90 | Regional connector |
| `KT95` | 95 seats, 3,050 km | regionalJet | regionalJet | 0.90 | Regional connector |
| `NA160` | 162 seats, 5,100 km | narrowbody | narrowbody | 1.00 | Short-haul workhorse |
| `MR180` | 180 seats, 5,400 km | narrowbody | narrowbody | 1.00 | Short-haul workhorse |
| `PA184` | 184 seats, 5,700 km | narrowbody | narrowbody | 1.00 | Short-haul workhorse |
| `MR220` | 221 seats, 6,400 km | largeNarrowbody | narrowbody | 1.00 | High-capacity narrowbody |
| `PA228` | 228 seats, 6,100 km | largeNarrowbody | narrowbody | 1.00 | High-capacity narrowbody |
| `PA290` | 288 seats, 10,800 km | widebody | widebody | 1.22 | Long-haul widebody |
| `MR300` | 298 seats, 11,400 km | widebody | widebody | 1.22 | Long-haul widebody |
| `AV310` | 310 seats, 11,900 km | widebody | widebody | 1.22 | Long-haul widebody |
| `MR410` | 408 seats, 13,900 km | largeWidebody | widebody | 1.22 | Flagship long-haul |
| `AV420` | 422 seats, 14,300 km | largeWidebody | widebody | 1.22 | Flagship long-haul |

Five types share the narrowbody shape at identical scale, and five share the
widebody shape at identical scale. Within those groups the artwork carries no
information at all — the numbers beside it do all the work. That is the honest
state of the visual system, and TD-014 is the entry that tracks narrowing it.

---

## 6. Livery

The player's airline has a livery colour, chosen at founding and persisted
(save v11, `LiveryMigrationTests`). It tints the player's map markers. Rival
airlines get muted, distinguishable tints from a fixed palette.

The rule that matters for readability: **rival aircraft are always visually
subordinate.** At world zoom rivals draw smaller and dimmer than the player's,
because a map where every airline is equally loud is a map that answers no
question. MASTER PROMPT 5 §42 asks for exactly this and it is already how
`MapPresentation` behaves.

There is no aircraft painting system and none is planned. A single airline
colour is enough to answer "is that mine", which is the only question the map
asks of livery.

---

## 7. Accessibility

- Every silhouette is `accessibilityHidden(true)`. It is decoration beside a
  label that already names the aircraft; a VoiceOver user hearing "airplane
  shape" before "MR180, narrowbody, 180 seats" is hearing noise.
- **Shape is never the only carrier.** Category is always available as text
  (`Vocab.category`) or as a role (`Vocab.role`) beside the artwork.
- **Tint is never the only carrier.** Status is a badge with an icon and a
  word; the colour agrees with it and adds nothing on its own.
- The shapes scale with their frames, not with Dynamic Type. That is
  deliberate — a silhouette growing to accessibility sizes would push the
  numbers it illustrates off the row.

---

## 8. Adding a type

Nothing is required. A new `AircraftTypeSpec` in `aircraft.json` resolves to
artwork through its category on the day it is added, and
`AircraftContentTests.rolesCoverTheCatalog` will fail if it introduces a
category with no role.

Adding a new **category** is the case that needs work: `AircraftCategory` is
exhaustively switched in `AircraftSilhouette.Planform.of` and
`AircraftTypeSpec.role`, so the compiler will name both sites. Decide there
whether it earns a fifth planform or shares an existing one — and if it shares
one, say so in §2 above, because that is the table this document exists for.
