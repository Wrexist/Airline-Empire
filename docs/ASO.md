# App Store Optimisation

The listing is a product surface, and this document is its design rationale.
The copy itself lives in [`store/`](../store) — text files, versioned and
reviewed like everything else — and [`docs/APP_STORE_CONNECT.md`](APP_STORE_CONNECT.md)
covers the account plumbing that gets it there. This file explains *why* the
words are the words, and what to change first when they do not work.

**Status, honestly:** none of this has met a real user. There is no app record,
no impressions data and no baseline, so every claim below is either a rule of
the platform (which is stable and stated as such), a decision with its
reasoning recorded, or a hypothesis with a way to test it. Nothing here is
dressed up as a measured result. The numbers that would make it measured
arrive in App Store Connect's own analytics after the first release, and §10
says which ones matter.

---

## 1 · The funnel this listing is optimising

    impressions → product page views → downloads
        (search + browse)      (conversion rate)

ASO moves two of those three: **impressions** come from what the app is
*findable* for (name, subtitle, keyword field, category), and **conversion**
comes from what the page *shows* (icon, first two screenshots, first three
lines of the description, rating).

Airline Empire is a **paid app with no ads and no in-app purchases**
(`docs/GAME_DESIGN.md` §"Premium single-purchase posture"). That single fact
reorders the whole discipline:

- **Conversion matters more than reach.** A free game can afford a wide,
  loosely-matched keyword net; every install costs the user nothing and some
  fraction monetises later. Here, a mismatched visitor never converts and the
  listing has spent an impression to be rejected. Precision beats volume.
- **The page has to answer "why does this cost money?" above the fold.** The
  answer this listing gives, in three places, is: no ads, no in-app purchases,
  no timers, nothing to wait out — a complete game, bought once. That is a
  genuine differentiator in a category built almost entirely on the opposite,
  and it belongs in the promotional text, in the screenshots and in the
  description's first block.
- **Browse traffic is worth more than usual.** Category browsing brings people
  who are already looking for a simulation game rather than for a specific
  free one, which is why the category choice in §4 is a real decision and not
  a formality.

---

## 2 · What the app actually is

Every line of store copy in `store/` is checkable against the code, and it was
written that way on purpose: a store listing that promises something the build
does not do is both a refund and a one-star review, and Apple treats a serious
mismatch as a guideline 2.3 rejection.

| Claim in the listing | Where it comes from |
|---|---|
| Eighty airports, nine world regions | `Resources/airports.json` — 80 entries, 9 distinct `region` values |
| Fourteen aircraft, 68 to 422 seats, turboprop to widebody | `Resources/aircraft.json` — 14 types, 6 categories |
| Buy new, buy used, or lease | `listPrice`, `deliveryLeadDays`, `leaseMonthly` per type; `FleetCommands` |
| Slot capacity, runway limits, weather risk | per-airport `slotCapacityPerDay`, `runwayClass`, `weatherRisk` |
| Monthly statements and a full ledger | `Domain/Ledger.swift`, `FinanceState`, the Finance screen |
| Loans and their interest | `Domain/Loan.swift`, `TakeLoanCommand` / `RepayLoanCommand` |
| Reputation from punctuality, comfort, delays | `Systems/ReputationSystem.swift`, `ServiceTier` |
| Competitors that expand, price-fight and collapse | `Systems/CompetitorAISystem.swift`, `AIProfile` |
| Seasons, fuel, storms, world events | `Systems/WorldEventSystem.swift`, `seasonality.json` |
| A daily digest of what yesterday cost | `Session/DailyDigest.swift` |
| Three starting scenarios | `Resources/scenarios.json` — Founder, Entrepreneur, Magnate |
| Same seed, same world | `Foundation/SeededRandom.swift`; determinism is tested |
| Multiple save slots, autosave on background | `Persistence/SaveStore.swift`, `GameController` |
| Completely offline, nothing collected | audited twice: zero network references in Core or App |

Two things the copy deliberately does **not** say, because they are not true
yet: nothing about cabins (there is one fare per route, not per cabin), and
nothing about refinancing (loans can be taken and repaid, not restructured).

**The world is fictional, and the listing says so.** Stockholm Sjövik, the
Nordavia NA-70, the Kestrel KT-72: invented, deliberately. That is a legal
asset as much as a design one — no manufacturer marks, no airline marks, no
licensing exposure — and `scripts/asc/lib/metadata.mjs` hard-fails any listing
that names a real one, because "our Boeing 737 equivalent" is exactly the
sentence a well-meaning editor adds later.

---

## 3 · Name, subtitle, keywords: the indexed surface

Apple indexes, roughly in descending weight: the **app name** (30 characters),
the **subtitle** (30), the **keyword field** (100, hidden from users), the
**developer name**, and the **category**. It does not index the description on
the App Store (unlike Google Play, where it does) — which is why the
description below is written for humans and the keyword field is written for
the algorithm.

Three platform rules drive the shape of the current fields, and the validator
enforces all three:

1. **The keyword field is comma-separated with no spaces.** `a,b,c`, never
   `a, b, c` — a space after a comma is a character spent on nothing.
2. **Apple combines terms across fields into phrases automatically.** With
   "airline" in the name and "manager" in the keywords, the app is eligible
   for "airline manager" without either field containing that phrase. So
   repeating a word already present in the name or subtitle is waste, and the
   validator warns about it.
3. **The category and platform are already indexed.** "game", "games", "app",
   "iphone", "ipad" in the keyword field buy nothing.

### The current allocation

| Field | Value | What it is doing |
|---|---|---|
| Name | `Airline Empire: Flight Tycoon` (29/30) | Brand first, then the highest-volume category term in the genre. "Tycoon" is what players of this genre type; "Empire" is the brand and doubles as a scale signal. |
| Subtitle | `Route & fleet strategy sim` (26/30) | Four terms the name does not have — route, fleet, strategy, sim — and a sentence that still reads as a description rather than a keyword list. |
| Keywords (en-US) | `aviation,airport,aircraft,planes,manager,management,simulator,offline,business,network,economy` (94/100) | Terms not in the name or subtitle. `manager`+`management` are separate entries because Apple's stemming across the pair is not reliable enough to assume. `offline` is a differentiator, not a category term: it is what someone who has been burned by an always-online game searches for. |
| Keywords (en-GB) | `aviation,airport,aeroplane,airliner,aircraft,manager,management,simulator,offline,timetable,hub` (95/100) | Not "extra" keywords: the en-GB listing is the one served in the UK, Ireland, Australia and New Zealand storefronts, so it carries the same core terms with the spellings those markets type. |

### What to test first, once there is data

In order, one change at a time (§10 explains why):

1. **`tycoon` versus `simulator` in the name.** They attract different
   audiences: "tycoon" is broader and more casual, "simulator" is smaller and
   converts harder on a paid app. This is the single highest-leverage
   experiment available, and it is a Product Page Optimisation test, not a
   guess.
2. **`offline` promoted into the subtitle.** If the paid-and-complete
   positioning is what converts, the word should be higher up the page.
3. **Rotating the six unused characters** in the keyword field into a
   long-tail term (`turboprop`, `widebody`, `airline tycoon`) and watching
   whether the impressions for it are real.

---

## 4 · Category

Primary **Games → Simulation**, secondary subcategory **Strategy**, no second
top-level category (`store/config.json`).

Simulation is what the game *is*: a deterministic economic model with a map on
top. Strategy is where its players also browse, and the second subcategory
costs nothing. The reason there is no secondary top-level category is that the
only honest candidates are other game categories, and a second weak category
dilutes browse ranking in the first rather than adding a new source of
traffic.

---

## 5 · The screenshots

Six shots, portrait, in a fixed order. Two canvases are required — 6.9-inch
iPhone (1320×2868) and 13-inch iPad (2064×2752) — because the app ships for
both device families; Apple scales every other size down from those. The
validator checks the dimensions and rejects any image with an alpha channel,
which is the most common silent failure in a screenshot pipeline.

**The first two carry the listing.** They are what shows in search results
without a tap, and most people never scroll the gallery. Both must work as a
thumbnail.

| # | Screen | Caption (≤ 6 words) | What it has to prove |
|---|---|---|---|
| 1 | Map, mid-game network | "Build a network that is yours" | This is a *map* game. The single strongest differentiator against the spreadsheet-shaped competition, and the most beautiful screen. |
| 2 | Route detail with the profit breakdown open | "Every number, explained" | Depth *and* legibility — the explainability pillar is what separates this from a tap-to-earn game. |
| 3 | Fleet acquisition | "Fourteen aircraft. New, used or leased." | Progression and scale: there is a lot to buy. |
| 4 | Finance, month closed | "Read the business, not a menu" | It is a real economic model. |
| 5 | World feed with a rival's move | "A world that moves without you" | It is not solitaire against a spreadsheet. |
| 6 | Dashboard with the daily digest | "No ads. No timers. One purchase." | The monetisation promise, stated last and plainly. |

Rules for producing them (they need a Mac and a simulator, so they do not
exist yet):

- Capture a **real mid-game world**, never a fresh save. Three routes and
  £2,000 in the bank reads as a demo; forty routes across two continents reads
  as a game worth £5.
- Use the **same seed and the same airline name** across all six so it is one
  story, not six unrelated screens.
- Caption text at the **top**, in the app's own type, at a size legible in the
  gallery thumbnail — the failure mode is 12-point body copy inside a device
  frame nobody can read.
- No fake UI, no invented numbers, no screens the app does not have. A
  screenshot is a claim.
- PNG, no alpha, no rounded-corner mask of its own.

`store/screenshots/<locale>/<DISPLAY_TYPE>/01-map.png` is where they go; the
directory name is the App Store Connect display-type enum, passed to the API
unchanged.

---

## 6 · The icon

**Missing, and it blocks release** (`AirlineEmpireApp/Resources/README.md`).
The brief, so whoever draws it is not starting from nothing:

- **One idea, readable at 60 points.** The category is full of detailed
  three-quarter aircraft renders that turn to mush at thumbnail size. The
  strongest options here are geometric: a route arc between two points, a tail
  fin as a single flat shape, a stylised network node.
- **Not a photo, not a real livery, not a real manufacturer's silhouette.**
  The world is fictional and the icon should look it.
- **High contrast against both light and dark home screens**, tested at 60 pt
  next to the actual competition rather than at 1024 in isolation.
- **No text.** The name is already under the icon.
- 1024×1024 PNG, no alpha, no pre-applied corner radius.

The icon is also the single highest-leverage thing to A/B test once Product
Page Optimisation is available — it is the only asset that appears in search
results, in browse, and on the page.

### A prompt you can paste into an image model

Three concepts, because the right one is decided at thumbnail size and not
before. Generate four variations of each, shrink them all to 60×60, and judge
them there, beside the real icons in Games → Simulation. Detail that vanishes
at that size was never doing any work.

**Concept 1 — The Arc** (the flagship: a route is what this game is about)

```
A premium mobile game app icon for an airline management strategy game.

SUBJECT: A single bold golden flight-path arc sweeping from lower-left to
upper-right across the frame. The arc is a clean, thick, tapering ribbon —
thin where it starts, widest at its apex. At the leading tip of the arc sits
one small solid triangle, abstracted to a paper-plane silhouette, banking
slightly upward. Two small filled circles mark the arc's origin and its
destination. Below and behind the arc, the gentle curve of a planet's horizon
crosses the lower third of the frame, rendered as one simple curved band with
a soft glow along its edge — no continents, no countries, no map detail.

COMPOSITION: Centered, symmetrical weight, generous margins. Exactly three
elements: horizon curve, arc, aircraft mark. Nothing else. The arc occupies
roughly 60% of the frame width. Flat vector geometry with crisp edges — every
shape readable as a silhouette.

STYLE: Modern flat vector illustration with subtle depth. Geometric and
confident, in the spirit of premium simulation-game iconography — clean, not
cartoonish, not photorealistic, not skeuomorphic, not 3D-rendered.

COLOR: Deep midnight navy background (#0E2033) with a subtle vertical
gradient to indigo (#1B3358). The arc and aircraft mark in warm gold
(#F2A93B) with a soft amber glow. Horizon band edge in pale warm white
(#FFE9C4). High contrast: the gold must read instantly against the navy at
very small sizes.

LIGHT: A faint warm glow radiating from the arc's apex, as if the route
itself is lit. No lens flare, no heavy bloom.

FORMAT: Perfect square, 1024x1024, fully opaque background extending to all
four edges. No transparency, no drop shadow outside the canvas, no rounded
corners, no border, no frame, no device mockup.

CRITICAL: No text, no letters, no numbers, no logos, no wordmarks. No real
airline liveries or manufacturer shapes. No detailed airliner. No clouds, no
runways, no airport terminals, no clutter. The design must remain legible when
scaled down to 60x60 pixels.
```

Negative prompt, for models that take one:

```
text, letters, numbers, watermark, logo, signature, rounded corners,
transparency, alpha channel, drop shadow, border, frame, device mockup,
photorealistic airplane, 3D render, cluttered, busy, gradient mesh, lens
flare, clouds, map continents, realistic earth texture
```

**Concept 2 — The Tail.** *A single airline tail fin, flat geometric
silhouette, filling the frame at a slight angle; one gold route-arc stripe
sweeping across it as the livery mark; deep navy background.* Same COLOR,
FORMAT and CRITICAL blocks. Reads as "airline" fastest, and is the most
ownable as a brand mark.

**Concept 3 — The Hub.** *Three gold arcs radiating from one glowing node in
the lower-centre, spreading upward and outward like a route network; deep navy
field.* Same blocks. Says *empire* and *network growth* rather than *a flight*.

Why the prompt is shaped this way, in case it needs rewriting: the SUBJECT
block names exactly three elements because anything more disappears at 60 pt;
the FORMAT block spells out opacity and corners because Apple flattens alpha
to black and applies its own mask; the CRITICAL block forbids text because
image models garble letterforms, and a wordmark with a malformed letter is a
brand you cannot use and cannot fix.

Afterwards: flatten to no alpha, save as
`AirlineEmpireApp/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`,
add its `"filename"` to that folder's `Contents.json`, and run
`node scripts/asc/check-app-icon.mjs` — which checks the two things Apple
rejects uploads over.

---

## 7 · The description, and the one field you can change any time

The description is not indexed on the App Store, so it has exactly one job:
convert someone who is already looking at the page. Structure:

1. **First ~170 characters** — everything above "more". Currently: *"One
   aircraft. One route. Everything after that is yours to build."* plus the
   opening line of what the game is.
2. **Scannable blocks** with capitalised headers and bulleted lines, because
   nobody reads a wall of text on a phone.
3. **The no-strings block**, which is the paid-app argument, stated plainly.
4. **The fictional-world note**, last: it pre-empts the "why aren't these real
   airports?" review before it is written.

**Promotional text** (170 characters) sits above the description and — this is
the useful part — can be changed **without submitting a new version**. It is
the only listing field with that property, which makes it the right home for
anything time-bound: an update's headline, a press mention, a seasonal note.
Never put anything permanent there, and never put a price claim there (Apple
rejects those, and the validator warns).

---

## 8 · Localisation

Today: **en-US and en-GB only.**

The temptation is to translate the listing into a dozen languages for the
keyword coverage, and it is a trap while the app itself is English-only: a
German listing sends German-speaking users to an English game, which converts
badly and returns one-star reviews complaining about exactly that. The rule
here is **localise the app first, then its listing** — with en-GB as the one
exception, because it is the same language and it is the listing actually
served in the UK, Irish, Australian and New Zealand storefronts.

When the app is localised, the order to add listings in is the one that
follows the simulation-genre audience: German, then Japanese, then French,
Spanish and Brazilian Portuguese. `KNOWN_LOCALES` in
`scripts/asc/lib/metadata.mjs` already accepts all of them; adding a directory
is the whole change.

---

## 9 · Things this listing deliberately does not do

- **No keyword stuffing in the name.** "Airline Empire: Flight Tycoon Airplane
  Manager Sim 2026" ranks for more and reads like malware.
- **No competitor or manufacturer names anywhere.** Guideline 5.2, and the
  validator fails the build over it.
- **No emoji in the name or subtitle.** A routine metadata rejection.
- **No price or promotion claims in the copy.** Prices change per storefront
  and Apple rejects the claim.
- **No fake urgency, no "best", no "#1".** The product's own pitch is that it
  respects the player; the listing should not open by not respecting them.
- **No incentivised or purchased reviews.** Beyond being a ban, the rating on
  a paid game is the conversion lever, and a fake one is a lie that shows up
  in the refund rate.
- **No rating prompt yet.** When one is added it should fire after a genuine
  milestone (a first profitable month, an era transition) and never during a
  decision or after a loss. Apple caps the prompt at three per year per user
  and ignores the rest; spending one on a bad moment is worse than not asking.
  Not implemented — it is a task, not a claim (`tasks/TODO.md`).

---

## 10 · Measuring, once there is anything to measure

App Store Connect's own analytics, in the order they matter here:

| Metric | Reads as | Watch for |
|---|---|---|
| Impressions, split search vs browse | Findability | A keyword change should move search impressions within about a week. |
| Product page views | Interest from the thumbnail | The icon and the first screenshot are the levers. |
| Conversion rate (views → downloads) | Whether the page closes | Below the category norm means the page over-promises or under-explains. |
| Proceeds per download | Storefront pricing sanity | Paid apps only; not a keyword signal. |
| Crash-free rate, ratings | Whether the product is good | ASO cannot fix a 3.1-star game. |

Three rules for changing things:

1. **One variable at a time.** Changing the icon, the screenshots and the
   keywords in one release means learning nothing.
2. **Wait a full week.** Search ranking after a metadata change is not stable
   for a few days, and weekday/weekend traffic differs.
3. **Prefer Product Page Optimisation to guessing.** It is Apple's own A/B
   test, it splits traffic properly, and it reports significance instead of
   leaving you to eyeball two weeks of a line chart.

Custom product pages (up to 35, each with its own screenshots and promotional
text, each with its own URL) are worth exactly one thing at launch: a link for
whatever community the game is posted to, with the screenshots reordered to
lead with the map. Not before there is a link to hand out.

**In-app events** are a poor fit for this app and that is fine to say out
loud: they exist to surface time-limited live content, and this game has none
by design (no timers, no seasons-as-monetisation). If a content update ever
adds a new region, that is a legitimate event; nothing before then is.

---

## 11 · Competitive context

Deliberately thin, because it cannot be checked from here. The genre's shape
is well known — a large free-to-play tier built on timers and premium
currency, a smaller premium tier, and a browser-simulation tier with a
desktop-shaped UI — and Airline Empire is aimed squarely at the second: the
player who has bounced off the first and cannot carry the third onto a phone.

What that positioning needs, before launch, is real research rather than
recollection: the current top twenty in Games → Simulation for "airline",
their prices, their icons at thumbnail size, their first two screenshots, and
their one-star reviews (which is where the market tells you what it wants).
`TODO(verify)` — this environment has no store access, and inventing a
competitor's price or ranking would be exactly the kind of wrong fact the rest
of this repository refuses to write down.

---

## 12 · Before submitting

- [ ] App icon exists (§6) — **blocking**
- [ ] Six screenshots per required canvas, from a real mid-game world (§5) — **blocking**
- [ ] `REPLACE_ME` gone from `store/config.json` and `site/` — **blocking**
- [ ] `node scripts/asc/validate-metadata.mjs` passes *without* `--allow-placeholders`
- [ ] Support and privacy URLs resolve (the Pages workflow has been run)
- [ ] Age rating questionnaire answered (`docs/APP_STORE_CONNECT.md` §7)
- [ ] App privacy answers: no data collected (§6 there)
- [ ] Review notes read as written (`store/metadata/review/notes.txt`)
- [ ] A build has been uploaded, processed, and installed from TestFlight on a real device
- [ ] `docs/APPLE_VALIDATION.md` §4's walkthrough has been performed on that build
