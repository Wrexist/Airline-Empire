# AI asset prompts

Every asset in this game that is worth generating with an image model, as a
prompt you can copy whole and paste without editing.

Written for **conversational image models** — ChatGPT / DALL·E, Gemini / Nano
Banana, and anything else that takes a paragraph rather than flag syntax. There
are no `--ar` switches or weighted tokens anywhere; framing, aspect and
exclusions are written as sentences, because that is what these models read.

**Read §0 before generating anything.** It is four rules, and three of them are
the difference between an asset that drops into the app and one that has to be
thrown away.

Companion documents, which this one does not repeat:
docs/ASSET_INVENTORY.md (what exists today),
docs/AIRCRAFT_ASSET_BIBLE.md (why the aircraft look the way they do),
docs/DESIGN_SYSTEM.md (the tokens), docs/ASO.md (the store listing),
docs/ASSET_PROVENANCE.md (the originality claim these prompts must not break).

---

## 0 · The four rules

### Rule 1 — Two registers, never mixed

This project has **two** visual languages, and using the wrong one is the most
expensive mistake available.

| Register | Where it lives | What it looks like |
| --- | --- | --- |
| **Instrument** | Everything inside the app | Flat. Solid fill, no stroke, no gradient, no shadow, no internal detail. A shape that still reads at 10 pt. |
| **Theatre** | The app icon, the store, the website | Painterly, warm, three-dimensional. Dusk, cloud, light on metal. The existing 1024 icon is the reference. |

The app is an instrument you fly an airline with. The store page is an
advertisement for the feeling of doing that. Each section below says which
register it is in. **Never bring theatre inside the app**, and never put a flat
silhouette on a store page.

### Rule 2 — Nothing real, ever

Every prompt in this file carries an explicit exclusion line, and you should
not delete it to save space. The project's provenance claim
(docs/ASSET_PROVENANCE.md) is that no manufacturer, airline, logo, livery or
registration anywhere in the product references a real one. Aircraft codes are
fictional (`AV`, `KT`, `MR`, `NA`, `PA`), and so are the carriers.

If a generated image comes back with a recognisable tail logo, a Boeing or
Airbus wing, or a real registration on the fuselage, **discard it**. Do not
retouch it out; regenerate. A retouched real aircraft is still a real aircraft.

### Rule 3 — Screenshots are captured, not generated

docs/ASO.md §5 is explicit: *"No fake UI, no invented numbers, no screens the
app does not have. A screenshot is a claim."* The six store screenshots come
from a real mid-game world on a real simulator, same seed and same airline
across all six.

So §3 of this file generates **the canvas around them** — backgrounds, feature
art, the website cover — and never the interface itself. If a model offers you
a plausible-looking app screen, you cannot use it.

### Rule 4 — Generate big, transparent, and square unless told otherwise

Every in-app asset: **2048 × 2048, transparent background, single centred
subject.** Downscaling is free and upscaling is not, and the app tints these
shapes at runtime, which needs alpha. The store assets have their own sizes,
given per prompt.

---

## 1 · The palette, for pasting into prompts

Give the model hex values, not colour names. "Deep blue" gets you six different
blues across six generations; `#3D82EB` gets you one.

### In-app tokens (`AETheme`)

| Token | Hex | Means |
| --- | --- | --- |
| `accent` | `#3D82EB` | Interactive, selected |
| `positive` | system green | Profit, health |
| `negative` | system red | Loss, danger |
| `caution` | system orange | Attention, not alarm |
| `mutedText` | system secondary | Supporting |
| `fare` | `#8C5CDB` | Fare badges |
| `owned` | `#4F59C2` | Owned aircraft |
| `leased` | `#2B8F99` | Leased aircraft |

### Map surface

| Token | Hex |
| --- | --- |
| `mapBackground` | `#0B101B` |
| `mapDeep` | `#060A13` |
| `mapLand` | `#212B3C` |
| `mapCoast` | `#41536B` |
| `mapBorder` | `#4A5B73` |

### Brand / theatre palette

Taken from the shipped icon and the dusk tokens. This is the store's palette.

| Name | Hex | Where |
| --- | --- | --- |
| Dusk top | `#0A1224` | Sky at the top of frame |
| Dusk bottom | `#1A2138` | Sky at the horizon |
| Ember | `#F2A83B` | Terminal light, sun, the tail mark |
| Azure | `#3D82EB` | The airline's own blue |
| Fuselage white | `#F4F6FA` | Aircraft body |

### The eight liveries

Rivals and the player are told apart by these. Use them when a prompt needs
more than one carrier in shot.

`azure #3D82EB` · `ember #F28C33` · `jade #29B37A` · `crimson #DE3D52` ·
`violet #8F5CDE` · `slate #7D8FA6` · `gold #DBB333` · `teal #299EAD`

---

## 2 · Aircraft — the instrument register

**This is the one genuine visual gap in the product** (ASSET_INVENTORY.md §5).
Everything else in the app is already solved procedurally.

### 2.1 What you are making, and what you are not

The app draws aircraft as **plan-view silhouettes** — seen from directly above,
nose up — because a plan view can be rotated to any heading and still read
correctly on the map. That constraint is why there is no perspective render
anywhere in the app, and it is not up for negotiation here.

You are generating **four planforms**, not fourteen. Six categories map onto
four shapes:

| Category | Planform to use | Draw scale |
| --- | --- | --- |
| `turboprop` | Turboprop | 0.82 |
| `regionalJet` | Regional jet | 0.90 |
| `narrowbody` | Narrowbody | 1.00 |
| `largeNarrowbody` | Narrowbody | 1.00 |
| `widebody` | Widebody | 1.22 |
| `largeWidebody` | Widebody | 1.22 |

Two pairs share a shape deliberately: at map scale a narrowbody and a large
narrowbody are the same object. Do not generate a fifth or sixth planform to
fix that — it is tracked as TD-014 and the fix is a scale factor, not new art.

### 2.2 The shared style block

Every aircraft prompt below ends with this. Paste it verbatim each time; it is
what keeps the four shapes in one family.

```
STYLE, applies to the whole image:
Pure top-down orthographic plan view, camera directly overhead, no perspective,
no tilt, no vanishing point. The aircraft is a single solid silhouette in one
flat colour (#3D82EB) on a fully transparent background. Absolutely flat: no
gradient, no shading, no highlight, no drop shadow, no ambient occlusion, no
reflection, no outline or stroke of any kind. No internal detail whatsoever —
no windows, no doors, no cockpit glazing, no engine cowl lines, no panel lines,
no registration, no text, no numbers. The shape reads correctly when scaled
down to 10 pixels tall, so every feature must be chunky and unambiguous; thin
spars, antennae and pitot tubes must be omitted rather than thinned. Nose
points to the top of the frame, aircraft perfectly vertical and bilaterally
symmetrical about the vertical centre line, centred with even margins.
Square canvas, 2048 x 2048.

MUST NOT CONTAIN: any real aircraft's outline, any manufacturer's design
language, any airline livery, logo, roundel, flag, registration or text of any
kind. This is a generic fictional planform, not a depiction of an existing
aeroplane.
```

### 2.3 Planform 1 of 4 — Turboprop

Used by NA70 (68 seats) and KT72 (74 seats).

```
A flat top-down plan-view silhouette of a generic twin-engine regional
turboprop airliner, seen from directly above.

Proportions: a slender, straight fuselage roughly 7 times longer than it is
wide. A high, straight, unswept wing of constant chord spanning slightly wider
than the fuselage is long, mounted about 40% of the way back from the nose.
One engine nacelle on each wing, set about a third of the way out from the
fuselage, each showing a blunt rounded propeller spinner projecting forward of
the wing leading edge — represent each propeller as a simple solid circular
disc centred on the spinner, as a spinning prop reads from above. A
conventional tail at the very back: a single horizontal tailplane about 40% of
the main wing's span, and a tall vertical fin which from directly above reads
only as a narrow solid spine along the centre line. Nose is rounded and blunt.

STYLE, applies to the whole image:
[paste the §2.2 style block here — it carries the no-real-aircraft
 exclusion, so the prompt is not safe to send without it]
```

### 2.4 Planform 2 of 4 — Regional jet

Used by AV90 (88 seats) and KT95 (95 seats).

```
A flat top-down plan-view silhouette of a generic regional jet airliner, seen
from directly above.

Proportions: a slim fuselage roughly 9 times longer than it is wide, noticeably
more slender than a mainline airliner. A low wing with a modest sweep of about
20 degrees, spanning a little less than the fuselage length, mounted just
behind the midpoint. The engines are mounted on the REAR FUSELAGE, not on the
wings: two short rounded nacelles sitting either side of the fuselage close to
the tail, so the wing itself is completely clean with nothing hanging from it.
A T-tail: the horizontal tailplane sits at the very top of the fin, so from
directly above it reads as a clean horizontal bar crossing the extreme rear of
the fuselage, about 35% of the main wing's span. Nose is pointed and tapered.

STYLE, applies to the whole image:
[paste the §2.2 style block here — it carries the no-real-aircraft
 exclusion, so the prompt is not safe to send without it]
```

### 2.5 Planform 3 of 4 — Narrowbody

Used by NA160 (162), MR180 (180), PA184 (184), MR220 (221), PA228 (228).
**The most important of the four** — it is the startup era's whole fleet and
the shape a new player sees first.

```
A flat top-down plan-view silhouette of a generic single-aisle narrowbody
airliner, seen from directly above.

Proportions: a clean tubular fuselage roughly 10 times longer than it is wide.
A low wing swept back about 25 degrees, spanning slightly less than the
fuselage length, mounted just aft of the midpoint, tapering from a broad root
to a narrower tip with a small squared-off wingtip. One engine under each wing,
mounted about 35% of the way out from the fuselage and set forward of the wing
leading edge so each nacelle clearly projects ahead of the wing — each is a
plain rounded capsule. A conventional tail: one horizontal tailplane at the
extreme rear, swept to match the wing, about 35% of the main wing's span, with
the vertical fin reading from above as a narrow solid spine on the centre line
between the tailplanes. Nose is a smooth rounded cone.

STYLE, applies to the whole image:
[paste the §2.2 style block here — it carries the no-real-aircraft
 exclusion, so the prompt is not safe to send without it]
```

### 2.6 Planform 4 of 4 — Widebody

Used by PA290 (288), MR300 (298), AV310 (310), MR410 (408), AV420 (422).

```
A flat top-down plan-view silhouette of a generic twin-aisle widebody
airliner, seen from directly above.

Proportions: a long, visibly THICK fuselage roughly 9 times longer than it is
wide — the extra width against a narrowbody is the whole point of this shape
and must be obvious at a glance. A low wing swept back about 32 degrees,
spanning a little more than the fuselage length, with a long tapering planform
and a raked wingtip. One engine under each wing, mounted about 30% of the way
out from the fuselage, each a large rounded capsule projecting well forward of
the wing leading edge and clearly bigger relative to the wing than a
narrowbody's. A conventional tail with a broad swept horizontal tailplane at
the extreme rear, about 38% of the main wing's span. Nose is a wide, blunt,
rounded dome.

STYLE, applies to the whole image:
[paste the §2.2 style block here — it carries the no-real-aircraft
 exclusion, so the prompt is not safe to send without it]
```

### 2.7 Acceptance checklist

Before you keep a planform, check all seven. Any failure means regenerate, not
retouch.

- [ ] Nose points to the top of the frame and the shape is bilaterally symmetrical.
- [ ] One flat colour. Hold it at 15% zoom — no gradient or shadow appears.
- [ ] Background is genuinely transparent, not white.
- [ ] No windows, text, registration or panel lines anywhere.
- [ ] Scaled to 10 px tall it still reads as this category and not another.
- [ ] Placed beside the other three, the four are obviously one family and obviously four different aeroplanes.
- [ ] It does not resemble any specific real aircraft.

### 2.8 Getting them into the app

The app draws these as SwiftUI `Shape` paths in
`AirlineEmpireApp/Sources/Map/AircraftSilhouette.swift`, not as images.

So a generated PNG is a **reference**, not a shippable asset: trace it to a
vector, export the outline as a path, and hand that to a developer to replace
the existing planform. Dropping the PNG in as an image asset would break
runtime tinting, cost memory at every zoom level, and lose the crispness the
current shapes have — the map redraws these at three sizes on every frame.

---

## 3 · Store and marketing — the theatre register

### 3.1 What AI makes here, and what it does not

| Asset | Source |
| --- | --- |
| The six screenshots' **UI** | **Captured from a real mid-game simulator.** Never generated — Rule 3. |
| The **canvas behind** those screenshots | Generated. §3.3 |
| App Store **feature / promo art** | Generated. §3.4 |
| **Website cover** | Generated. §3.5 |

### 3.2 The shared theatre style block

Paste this at the end of every prompt in §3.

```
STYLE, applies to the whole image:
Cinematic dusk aviation illustration, painterly and warm, in the style of a
premium mobile strategy game's marketing art. Deep navy night sky (#0A1224 at
the top, #1A2138 near the horizon) with warm amber light (#F2A83B) from
terminal windows, apron floodlights and the last of the sun. Volumetric
cumulus cloud catching the amber. Wet apron surfaces reflecting light. Rich
contrast, clean edges, no grain, no lens dirt, no chromatic aberration, no
text of any kind anywhere in the image.

MUST NOT CONTAIN: any real airline's name, logo, livery or colours; any real
aircraft manufacturer's design language; any real airport's identifiable
architecture; any registration, flag, roundel, brand mark, watermark, caption
or lettering. Every aircraft and carrier in this image is fictional.
```

### 3.3 Screenshot canvas (behind the captured device frames)

Six shots on two canvases — 6.9-inch iPhone at **1320 × 2868** and 13-inch iPad
at **2064 × 2752**. The captured screenshot sits on top of this, so the middle
of the frame must stay quiet.

```
A vertical portrait marketing background for a mobile game store listing, in
9:19.5 aspect, 1320 pixels wide by 2868 tall.

The composition is deliberately EMPTY THROUGH THE CENTRE: a large calm region
runs from 15% to 90% of the image height where a phone screenshot will be laid
on top, so nothing important, bright or busy may sit there. Keep that band to
a smooth, dark, gently graded navy.

Interest lives only at the extreme top and the extreme bottom. Across the top
20%, a dusk sky with layered amber-lit cloud and one small fictional airliner
in silhouette climbing away, tiny, upper right. Across the bottom 12%, the
soft out-of-focus glow of an airport apron at night — runway edge lights and
terminal windows reduced almost to bokeh, no readable structure.

The overall impression is depth and calm, not activity. This is a stage, not a
scene.

STYLE, applies to the whole image:
[paste the §3.2 style block here — it carries the no-real-airline
 exclusion, so the prompt is not safe to send without it]
```

For the iPad canvas, change the first paragraph to `2064 pixels wide by 2752
tall, in a 3:4 portrait aspect` and widen the quiet centre band to run from 12%
to 92% of the height. Everything else is unchanged.

### 3.4 Feature / promotional art

One hero image, reusable for a custom product page header, a press kit and
social posts. **1920 × 1080**, and it must survive being cropped square.

```
A wide 16:9 cinematic key art image, 1920 by 1080 pixels, for a mobile airline
management strategy game.

A fictional twin-engine narrowbody airliner in a deep azure and white livery
(#3D82EB and #F4F6FA) climbs away from the viewer at a shallow angle, seen from
below and slightly behind, filling the right third of the frame. Its tail
carries a simple abstract amber mark: a stylised aeroplane glyph in #F2A83B,
geometric and flat, not a logo of any real carrier.

Behind and below, a modern airport at dusk: a glass terminal with warm amber
interior light, a control tower to the left, wet apron reflecting the lights,
a second fictional airliner in a different livery parked at a gate. Beyond the
airfield the land falls away into a dark landscape scattered with the pinpoint
lights of distant cities, hinting at a network reaching to the horizon.

The left third of the frame is deliberately uncluttered sky so a title can be
placed over it later. Do not draw any title, logo or text yourself.

Compose so that a centre square crop still contains the aircraft and the
terminal, because this image will also be used at 1:1.

STYLE, applies to the whole image:
[paste the §3.2 style block here — it carries the no-real-airline
 exclusion, so the prompt is not safe to send without it]
```

### 3.5 Website cover

Replaces `site/assets/cover.png`. Wider and quieter than the key art — this one
sits behind a headline.

```
A very wide banner image, 2400 by 1260 pixels, for the top of a game's website.

A high, wide dusk panorama looking down on a fictional airport from perhaps a
thousand feet: two runways, a terminal with warm amber light, aircraft at
gates, service vehicles reduced to points of light. The horizon sits low, about
70% of the way down the frame, so the upper half is a broad expanse of dusk sky
with layered cloud.

Three faint azure arcs (#3D82EB) sweep across the sky from the airport toward
the edges of the frame, drawn as thin luminous great-circle route lines with a
small glowing dot travelling along each, the way a route map animates. They are
subtle — a suggestion of a network, not a diagram.

The whole left half is calm enough to carry a headline and a paragraph of body
text over it. Do not draw any text.

STYLE, applies to the whole image:
[paste the §3.2 style block here — it carries the no-real-airline
 exclusion, so the prompt is not safe to send without it]
```

---

## 4 · UI art

### 4.1 App icon

**An icon already ships**, at 1024 × 1024, and its source is retained in
`docs/design/icon-source-1254.png`. It works: dusk, a narrowbody climbing over a
lit terminal, an amber tail mark. Only regenerate it if you are deliberately
testing an alternative — docs/ASO.md §7 warns to change one listing variable at
a time, and the icon is the highest-leverage one on the page.

If you do test one, the constraint that matters is **thumbnail legibility**: on
a search result the icon is about 60 px, and the current one's terminal, tower
and clouds are all lost at that size. The brief below is deliberately simpler
than the shipped icon for exactly that reason.

```
A square app icon, 1024 by 1024 pixels, for a premium airline management
strategy game. No text anywhere.

A single bold subject, centred, readable at 60 pixels: the tail fin of a
fictional airliner seen from a low three-quarter angle, filling roughly the
central 60% of the frame, in deep azure (#3D82EB) with a crisp amber (#F2A83B)
abstract aeroplane glyph on it — a simple geometric swept shape, flat, no
detail, not a real carrier's logo.

Behind it, a simple dusk gradient from #0A1224 at the top to #1A2138 at the
bottom, with one soft amber glow low and left suggesting terminal light. A
single thin azure arc curves behind the fin from lower left to upper right,
suggesting a flight path.

Keep the background almost empty. Depth comes from the gradient and the glow,
not from detail. No clouds with structure, no buildings, no runway markings, no
other aircraft — everything must survive being shrunk to a thumbnail.

Square, full bleed to all four edges, no rounded corners of its own, no border,
no drop shadow outside the artwork, no alpha channel.

MUST NOT CONTAIN: any real airline's name, logo, livery or colours; any real
manufacturer's design language; any lettering, registration, flag or watermark.
```

**Then check it honestly:** shrink it to 60 px and put it beside the shipped
icon and four competitors' icons at the same size. If you cannot tell at a
glance which is yours, it has failed regardless of how it looks at full size.

### 4.2 Empty-state illustrations — read this before generating

ASSET_INVENTORY.md rates these **P2** and warns, from MASTER PROMPT §14,
against introducing illustrations that are stylistically unrelated to the rest
of the product. Today an empty state is an SF Symbol, a title, a message and an
action, and the copy is doing the work.

The honest position: **these are optional, and a bad set is worse than none.**
If you generate them, all six must be one family, in the instrument register —
flat, single-colour, no scene — or they will read as clip art dropped into an
instrument.

The six states, from the source:

| Screen | Icon today | Title |
| --- | --- | --- |
| Fleet | `airplane` | No aircraft |
| Routes | `…curvepath` | No routes yet |
| Route search | `magnifyingglass` | No matches |
| Route closed | `xmark.circle` | Route closed |
| World, calm | `sun.max` | Calm skies |
| World, no rivals | `person.2.slash` | No rivals |

Shared style block for all six:

```
STYLE, applies to the whole image:
A single flat vector spot illustration in one colour (#3D82EB) plus its own
lighter tint, on a fully transparent background. Geometric and minimal, built
from simple shapes with generous stroke weights of even thickness. No gradient,
no shadow, no texture, no perspective, no scene, no background, no character,
no text. It must read at 64 pixels. Square canvas, 2048 x 2048, subject
centred with generous margins.

MUST NOT CONTAIN: any real airline or manufacturer reference, any logo, any
lettering.
```

And the six subjects, each pasted above that block:

```
1. FLEET — An empty aircraft hangar reduced to its simplest geometry: a wide
   arched opening, an empty floor line, nothing inside.

2. ROUTES — Two small circular airport dots on a plain field with a single
   dashed arc between them left incomplete, stopping short of the second dot.

3. SEARCH — A magnifying glass over a small grid of four dots, one of which is
   hollow, suggesting a gap rather than a result.

4. ROUTE CLOSED — A single route arc between two dots with a clean break in the
   middle of the arc, the two ends drawn slightly apart.

5. CALM SKIES — A simple sun disc low behind two flat horizontal cloud bars,
   nothing else in the frame.

6. NO RIVALS — Three airport dots connected by arcs, all in the same single
   colour, with the space around them conspicuously empty.
```

### 4.3 What deliberately has no art, and should stay that way

ASSET_INVENTORY.md §5 already swept this. Recorded here so nobody generates it
by accident:

- **Airports** — map markers sized by tier. Modelling 80 airports was
  considered and rejected.
- **Events** — an SF Symbol plus a semantic tint and severity band.
- **Backgrounds** — beyond `aeScreenBackground`, wallpaper was explicitly
  warned against.
- **Finance and economy** — every chart is drawn from real data.
- **Missions, onboarding, effects** — no gap.

---

## 5 · Generation order

If you are doing this in one sitting, this order gets the most value soonest
and lets each stage inform the next.

| # | Asset | Why here | Blocking? |
| --- | --- | --- | --- |
| 1 | **Narrowbody planform** (§2.5) | The startup fleet. Get this one right and the other three follow its proportions. | The real gap |
| 2 | Widebody, regional jet, turboprop (§2.6, 2.4, 2.3) | Generate as a set, against the narrowbody, so the family holds. | The real gap |
| 3 | Feature art (§3.4) | Needed for a press kit and any custom product page. | No |
| 4 | Screenshot canvas (§3.3) | Needed only once the six captures exist. | Store submission |
| 5 | Website cover (§3.5) | Replaces an existing file that already works. | No |
| 6 | Icon alternative (§4.1) | Only as a deliberate A/B against a shipped icon that already works. | No |
| 7 | Empty states (§4.2) | Optional, and easy to make worse. Do last, or not at all. | No |

---

## 6 · The rule under all of it

Every asset here is **original and fictional**. No real aircraft, no real
airline, no real airport, no borrowed artwork — that is the claim
docs/ASSET_PROVENANCE.md makes on this project's behalf, and an image model
will happily break it for you if the prompt lets it.

So the check is not "does this look good". It is **"could anyone point at this
and name the real thing it came from"**. If the answer is yes, it does not
ship, however good it looks.
