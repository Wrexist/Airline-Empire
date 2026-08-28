# App Store Connect — the fill-in sheet

<!-- GENERATED FILE — DO NOT EDIT BY HAND.
     Written by `node scripts/asc/build-fill-in-sheet.mjs` from `store/`,
     which is the single source of truth for the listing (decision D-012).
     Edit the files under store/metadata/, then regenerate. CI fails if this
     file is stale. -->

Everything App Store Connect asks for, in the order its own screens ask for
it, with the exact value to paste. Work top to bottom; nothing here needs
you to open another file.

Three kinds of line appear below:

- **A code block** — paste it verbatim.
- **⚠️ you must replace this** — the value contains `REPLACE_ME`, because only
  the Apple account holder can supply it. Fix it in `store/config.json` and
  regenerate this sheet; the release workflow refuses to push a listing that
  still contains one.
- **A decision** — marked _your call_. Nothing in the repository decides it.

Prerequisites (the Apple Developer Program, the API key, the secrets) are in
[`APP_STORE_CONNECT.md`](APP_STORE_CONNECT.md). The whole release, of which
this is one stage, is [`GO_LIVE.md`](GO_LIVE.md).

> **Most of §2 and §5 can be pushed for you** by the *App Store metadata*
> workflow (`plan`, then `apply`), which writes exactly the values below.
> The sections marked **hand-entry only** cannot: App Store Connect does not
> accept them over the API, so they are always typed by a person.

---

## 1 · Apps → ⊕ → New App

_Once, when the app record is created._

**Platforms** — tick **iOS** only.

**Name** — 29/30 characters

```text
Airline Empire: Flight Tycoon
```

> App Store Connect calls this "Name". It must be globally unique across the
> App Store — if it is taken, choose another, change it in
> `store/metadata/*/name.txt`, and regenerate this sheet.

**Primary Language** — English (U.S.)

**Bundle ID**

```text
com.airlineempire.game
```

> Pick the identifier you registered in the Developer portal. It must equal
> this exactly, or the upload lands against no app record.

**SKU**

```text
airline-empire-ios
```

> Internal only. Never shown to anyone, never change it afterwards.

**User Access** — Full Access.

---

## 2 · App Information

_Left sidebar → General → App Information._

### Localizable Information

#### English (U.S.)

**Name** — 29/30 characters

```text
Airline Empire: Flight Tycoon
```

**Subtitle** — 26/30 characters

```text
Route & fleet strategy sim
```

**Privacy Policy URL** — 48/255 characters

```text
https://wrexist.github.io/airline-empire/privacy
```

#### English (U.K.)

_Add this localization first: the language dropdown at the top right of the page → **Add Language** → English (U.K.)._

**Name** — 29/30 characters

```text
Airline Empire: Flight Tycoon
```

**Subtitle** — 26/30 characters

```text
Route & fleet strategy sim
```

**Privacy Policy URL** — 48/255 characters

```text
https://wrexist.github.io/airline-empire/privacy
```

### General Information

- **Primary Category** — Games
- **Primary Subcategory 1** — Simulation
- **Primary Subcategory 2** — Strategy
- **Secondary Category** — None

> Why no secondary category: the only honest candidates are other game
> categories, and a second weak category dilutes browse ranking in the first
> rather than adding traffic (`ASO.md` §4).

**Content Rights** — "No, it does not contain, show, or access third-party
content." True: the world is entirely invented — every airport, city,
aircraft and manufacturer.

**Age Rating** → Edit. **hand-entry only.** Answer every question **None**:

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Profanity or Crude Humor | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Simulated Gambling | None |
| Sexual Content or Nudity | None |
| Contests | None |
| Unrestricted Web Access | No |
| Gambling and Contests | No |

Expected result: **4+**. Anything higher means a question was answered
wrong — the game has no violence (aircraft losses are financial and
reputational events, never depicted), no gambling (seeded world randomness
is not wagering), no web view and no user content.

---

## 3 · Pricing and Availability

**hand-entry only.**

- **Price** — _your call._ Nothing in the repository decides it; what is
  decided is the shape: one purchase, no in-app purchases, no ads, no
  subscription (`GAME_DESIGN.md`).
- **Availability** — all countries and regions, unless you have a reason.
- **Pre-Orders** — off, unless you are running a launch campaign.

> Reminder: a paid app also needs the **Paid Applications agreement** active
> under Business, plus tax and banking. It is the step most often discovered
> at the end, when the Release button is greyed out.

---

## 4 · App Privacy

**hand-entry only.** Left sidebar → App Privacy → Get Started.

**"Do you or your third-party partners collect data from this app?"** →
**No**

That is the entire questionnaire, and it is true rather than convenient:
there is no network code anywhere in the app or the core, no analytics, no
crash reporter, no advertising SDK and no account. The bundled
`PrivacyInfo.xcprivacy` says the same thing in the form Apple reads
mechanically, and `site/privacy.html` says it in prose. If that ever stops
being true, all three change in the same commit.

**Privacy Policy URL (asked again here)** — 48/255 characters

```text
https://wrexist.github.io/airline-empire/privacy
```

---

## 5 · The version page — "iOS App 1.0"

_Left sidebar → the version under **iOS App**. Everything in this section
except the screenshots and the release option is what the metadata workflow
pushes for you._

### English (U.S.)

**Promotional Text** — 151/170 characters

```text
Eighty airports. Fourteen aircraft. One turboprop to start with. Version 1.0 is the whole simulation — no timers, no ads, nothing to unlock with money.
```

> The only field that can be changed **without submitting a new version**.
> Keep anything time-bound here and nothing permanent.

**Description** — 2183/4000 characters

```text
One aircraft. One route. Everything after that is yours to build.

Airline Empire is a deep, offline airline management simulator. You decide where to fly, what to fly and what to charge — and a living world answers back. Demand shifts with the seasons, fuel prices move, rivals undercut you on your best route, and every number you see can be opened up and explained.

BUILD A NETWORK THAT IS YOURS
• Eighty airports across nine world regions, each with its own demand, slot capacity, runway limits and weather risk
• Open routes, set frequencies, set the fare, and watch the map fill in behind you
• Grow from a single regional hop to widebodies and long-haul, as hubs and fleet commonality start to matter

RUN A REAL BUSINESS
• Fourteen aircraft types, from a 68-seat turboprop to a 422-seat widebody — buy new, buy used, or lease
• Monthly statements and a full ledger: every cent traceable to the flight that earned or spent it
• Loans when you need them, and the interest that comes with them
• A service tier and a reputation built out of punctuality, comfort and delays — and lost the same way

A WORLD THAT MOVES WITHOUT YOU
• Competitor airlines expand, fight you on price, retreat, and sometimes collapse
• Seasons, fuel markets, storms and world events reshape demand while you are deciding
• A daily digest tells you what yesterday made or lost, and why

PLAY IT YOUR WAY
• Three starting scenarios, from a careful regional debut to a well-funded launch
• Pick your seed — the same seed always grows the same world, so a run can be replayed exactly
• Pause, or run at up to 4×. It works in five minutes and it works for an hour
• Multiple save slots, and a save that survives being backgrounded mid-flight

NO STRINGS ATTACHED
• One purchase. No ads, no in-app purchases, no energy meters, nothing to wait out
• Completely offline. No account, no sign-in, no servers, no tracking, nothing sent anywhere
• iPhone and iPad

A NOTE ON THE WORLD
Airline Empire is set in an invented one. Its cities, airports, aircraft and manufacturers were designed for the simulation rather than copied from a timetable, which is what lets the economics be honest instead of approximate.
```

**Keywords** — 94/100 characters

```text
aviation,airport,aircraft,planes,manager,management,simulator,offline,business,network,economy
```

> Comma-separated, **no spaces after the commas** — a space is a character
> spent on nothing. Hidden from users; this is pure search surface.

**Support URL** — 48/255 characters

```text
https://wrexist.github.io/airline-empire/support
```

**Marketing URL** — 41/255 characters

```text
https://wrexist.github.io/airline-empire/
```

### English (U.K.)

**Promotional Text** — 155/170 characters

```text
Eighty airports. Fourteen aircraft. One turboprop to start with. Version 1.0 is the whole simulation — no timers, no adverts, nothing to unlock with money.
```

> The only field that can be changed **without submitting a new version**.
> Keep anything time-bound here and nothing permanent.

**Description** — 2188/4000 characters

```text
One aircraft. One route. Everything after that is yours to build.

Airline Empire is a deep, offline airline management simulator. You decide where to fly, what to fly and what to charge — and a living world answers back. Demand shifts with the seasons, fuel prices move, rivals undercut you on your best route, and every number you see can be opened up and explained.

BUILD A NETWORK THAT IS YOURS
• Eighty airports across nine world regions, each with its own demand, slot capacity, runway limits and weather risk
• Open routes, set frequencies, set the fare, and watch the map fill in behind you
• Grow from a single regional hop to widebodies and long-haul, as hubs and fleet commonality start to matter

RUN A REAL BUSINESS
• Fourteen aircraft types, from a 68-seat turboprop to a 422-seat widebody — buy new, buy used, or lease
• Monthly statements and a full ledger: every penny traceable to the flight that earned or spent it
• Loans when you need them, and the interest that comes with them
• A service tier and a reputation built out of punctuality, comfort and delays — and lost the same way

A WORLD THAT MOVES WITHOUT YOU
• Competitor airlines expand, fight you on price, retreat, and sometimes collapse
• Seasons, fuel markets, storms and world events reshape demand while you are deciding
• A daily digest tells you what yesterday made or lost, and why

PLAY IT YOUR WAY
• Three starting scenarios, from a careful regional debut to a well-funded launch
• Pick your seed — the same seed always grows the same world, so a run can be replayed exactly
• Pause, or run at up to 4×. It works in five minutes and it works for an hour
• Multiple save slots, and a save that survives being backgrounded mid-flight

NO STRINGS ATTACHED
• One purchase. No adverts, no in-app purchases, no energy meters, nothing to wait out
• Completely offline. No account, no sign-in, no servers, no tracking, nothing sent anywhere
• iPhone and iPad

A NOTE ON THE WORLD
Airline Empire is set in an invented one. Its cities, airports, aircraft and manufacturers were designed for the simulation rather than copied from a timetable, which is what lets the economics be honest instead of approximate.
```

**Keywords** — 95/100 characters

```text
aviation,airport,aeroplane,airliner,aircraft,manager,management,simulator,offline,timetable,hub
```

> Comma-separated, **no spaces after the commas** — a space is a character
> spent on nothing. Hidden from users; this is pure search surface.

**Support URL** — 48/255 characters

```text
https://wrexist.github.io/airline-empire/support
```

**Marketing URL** — 41/255 characters

```text
https://wrexist.github.io/airline-empire/
```

### Screenshots

| App Store Connect tab | Canvas (px) | Status |
|---|---|---|
| iPhone 6.9" | 1320 × 2868 | **missing — blocks submission** |
| iPad 13" | 2064 × 2752 | **missing — blocks submission** |

Portrait, PNG, **no alpha channel**, at most ten per size. The six-shot
storyboard and the captions are `ASO.md` §5; the upload can be done for you
by the metadata workflow with **screenshots** ticked.

### App Review Information

**hand-entry only** for the sign-in question; the rest is pushed.

- **Sign-in required** — **No**. The game has no accounts of any kind.

- **First Name** — `REPLACE_ME`  ⚠️ **you must replace this**
- **Last Name** — `REPLACE_ME`  ⚠️ **you must replace this**
- **Phone Number** — `REPLACE_ME`  ⚠️ **you must replace this**
- **Email** — `REPLACE_ME@example.com`  ⚠️ **you must replace this**

**Notes** — 2220/4000 characters

```text
Airline Empire is a single-player airline management simulation. Everything a reviewer needs is in the app on first launch — there is nothing to sign in to.

WHAT THE APP DOES NOT DO
• No account, no sign-in, no user-generated content, no social features, no chat.
• No network access of any kind. The app makes no requests; it will behave identically in Airplane Mode, and we would encourage testing it that way.
• No advertising, no in-app purchases, no third-party SDKs, no analytics and no tracking. Nothing is collected, so the privacy nutrition label declares no data collection and the bundled privacy manifest declares no tracking domains and no required-reason API use.
• No gambling, no loot boxes, no randomised paid rewards. The only randomness is the simulation's own seeded world generation, which the player sets and can repeat.

HOW TO SEE THE GAME QUICKLY
1. Launch → "New Game" → name an airline, pick the "Magnate" scenario (the well-funded start) and any seed.
2. Fleet → Acquire → buy a used aircraft (it is available immediately; new aircraft are orders with a delivery lead time).
3. Dashboard → the onboarding card suggests two routes ranked by demand → tap one → the route sheet opens pre-filled → open the route.
4. Route detail → Aircraft → assign the aircraft you bought.
5. Set the speed to 4× → flights depart and arrive, the map animates, and the feed narrates the day. A month boundary closes a statement, which Finance then charts.

AGE RATING
The game contains no violence, no sexual content, no profanity, no substances, no gambling and no horror. Its subject matter is running an airline: money, aircraft, schedules and reputation. Aircraft losses are modelled as financial and reputational events only; there are no crashes, casualties or injury depicted anywhere in the game.

CONTENT AND LIKENESS
The world is entirely fictional. Airports, cities, airlines, aircraft models and manufacturers were invented for this simulation. No real airline, manufacturer, aircraft model, airport or trademark is depicted or referenced, and no real-world flight data is used.

CONTACT
The contact on this version is the developer, who can respond the same day for anything that blocks the review.
```

- **Attachment** — none needed.

### Version Information

**Copyright**  ⚠️ **you must replace this**

```text
2026 REPLACE_ME
```

- **Routing App Coverage File** — none.
- **Release** — **Manually release this version** — an approved build waits for you to press Release.

---

## 6 · TestFlight

**hand-entry only.** App Store Connect keeps beta metadata on a different
resource from the store listing, so none of this is pushed.

**Internal Testing** needs none of it: add your Apple account to the
internal group and the build is installable minutes after it processes, with
no Beta App Review. Everything below is for **external** testers, where
Apple reviews the first build of each version.

**Beta App Description / What to Test**

```text
Airline Empire is a single-player airline management simulation. You found an airline, buy aircraft, open routes, set fares, and run a living network while competitors, seasons, fuel prices and world events push back.

This build is the whole game. It is entirely offline — no account, no sign-in, no network calls of any kind — so it behaves identically in Airplane Mode.

WHAT TO TEST
1. New game: name an airline, pick a scenario and a seed, and found it.
2. Fleet → Acquire → buy a used aircraft (used ones are available immediately; new ones are orders with a delivery lead time).
3. Dashboard → open one of the two suggested routes → assign your aircraft to it from the route's detail screen.
4. Run at 1x and 4x: flights should depart and arrive, the map should animate, and the feed should narrate the day.
5. Cross a month boundary so a statement closes, then read Finance.
6. Save, quit to the menu, and continue — the game should resume at the same date, cash and network.
7. Background the app mid-flight and return: autosave should have fired and the simulation should resume.

WHAT WE MOST WANT TO HEAR ABOUT
Anything that renders wrong, any control that is hard to hit, anything that is slow on your device, and any number on screen you cannot explain from the screen it is on. Please include your device, your iOS version, and the seed and scenario you started with — the simulation is deterministic, so with those a run can be reproduced exactly.
```

- **Feedback Email** — `REPLACE_ME@example.com`  ⚠️ **you must replace this**
- **Marketing URL** — `https://wrexist.github.io/airline-empire/`
- **Privacy Policy URL** — `https://wrexist.github.io/airline-empire/privacy`
- **Beta App Review Information** — the same contact and notes as §5.

---

## 7 · Before you press Submit

- [ ] A build is attached to the version (upload it with the *iOS TestFlight* workflow).
- [ ] You have installed that build from TestFlight and played it on a real device.
- [ ] Screenshots are uploaded for both required sizes.
- [ ] No `REPLACE_ME` remains: `node scripts/asc/validate-metadata.mjs` passes without `--allow-placeholders`.
- [ ] `node scripts/asc/check-app-icon.mjs` passes.
- [ ] The support and privacy URLs open in a browser you are not signed into.
- [ ] Age rating shows 4+ and App Privacy shows no data collected.

Then **Add for Review** → **Submit**. With the release option above, an
approved version waits for you to press **Release**.
