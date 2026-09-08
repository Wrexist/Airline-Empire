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

**Privacy Policy URL** — 53/255 characters

```text
https://wrexist.github.io/Airline-Empire/privacy.html
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

**Privacy Policy URL** — 53/255 characters

```text
https://wrexist.github.io/Airline-Empire/privacy.html
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

- **Price** — **Free**. The app itself is not sold; the three Pro products
  are (`MONETIZATION.md`).
- **Availability** — all countries and regions, unless you have a reason.
- **Pre-Orders** — off, unless you are running a launch campaign.

### The three in-app purchases

Full walkthrough in `docs/MONETIZATION.md` §8. All three are submitted
**with** the version, each needs a display name, a description and a review
screenshot of the paywall, and every identifier below is immutable once
created.

| What | Identifier | Type | Price (US) |
|---|---|---|---|
| Pro Weekly | `com.airlineempire.game.pro.weekly` | Auto-renewable, 1 week | 8.99 |
| Pro Yearly | `com.airlineempire.game.pro.yearly` | Auto-renewable, 1 year | 39.99 |
| Pro Lifetime | `com.airlineempire.game.pro.lifetime` | Non-Consumable | 49.99 |

- Subscription group: **`Airline Empire Pro`**, holding the weekly and the
  yearly at the same group level.
- Introductory offer on the **weekly only**: **Pay As You Go, 1 week,
  0.99**. Not pay-up-front — Apple does not offer that duration on a weekly
  subscription, and it is the detail this setup is most often got wrong on.
- One introductory offer per group per Apple Account, ever. That is why the
  yearly carries none.

> Reminder: selling anything needs the **Paid Applications agreement** active
> under Business, plus tax and banking — a free app with in-app purchases
> included. It is the step most often discovered at the end, when the
> products cannot be created.

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

**Privacy Policy URL (asked again here)** — 53/255 characters

```text
https://wrexist.github.io/Airline-Empire/privacy.html
```

---

## 5 · The version page — "iOS App 1.0"

_Left sidebar → the version under **iOS App**. Everything in this section
except the screenshots and the release option is what the metadata workflow
pushes for you._

### English (U.S.)

**Promotional Text** — 143/170 characters

```text
Ninety-four real airports. Fourteen aircraft. One turboprop to start with. Free to play, with no ads and no timers — Pro opens the whole world.
```

> The only field that can be changed **without submitting a new version**.
> Keep anything time-bound here and nothing permanent.

**Description** — 2911/4000 characters

```text
One aircraft. One route. Everything after that is yours to build.

Airline Empire is a deep, offline airline management simulator. You decide where to fly, what to fly and what to charge — and a living world answers back. Demand shifts with the seasons, fuel prices move, rivals undercut you on your best route, and every number you see can be opened up and explained.

BUILD A NETWORK THAT IS YOURS
• Ninety-four real airports across nine world regions — Arlanda, Heathrow, Haneda, Landvetter — each with its own demand, slot capacity, runway limits and weather risk
• Open routes, set frequencies, set the fare, and watch the map fill in behind you
• Grow from a single regional hop to widebodies and long-haul as you earn new eras and expand your fleet

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
• Pause, or run at up to 16×. It works in five minutes and it works for an hour
• Daily autosaves, backup recovery and campaign export/import — with Pro, keep multiple airlines in separate saves

FREE TO FLY, AND WE MEAN IT
• The whole simulation is free: the full ledger, every explainer, rivals that fight back, the seeded world you can replay exactly
• No ads. No timers. No energy meter. No premium currency. Nothing to wait out and nothing to pay to skip
• A free airline flies the twenty airports nearest its home, through the Startup and Regional eras
• Airline Empire Pro opens the rest: National, International and Empire, all 94 airports across nine regions, widebodies and long-haul, every scenario, and as many airlines as you like
• Pro is more world, never a shortcut through it — no aircraft, route or advantage is ever sold

OFFLINE GAMEPLAY
• No game account, advertising or tracking
• Play your campaign in Airplane Mode; purchases and restoring Pro use Apple’s App Store services
• iPhone and iPad

A NOTE ON THE WORLD
The map is the real one: ninety-four real airports, from Arlanda to Haneda, with real geography, distances and time zones. The airlines, aircraft and manufacturers are invented for the simulation, which is what lets the economics be honest instead of approximate.
```

**Keywords** — 94/100 characters

```text
aviation,airport,aircraft,planes,manager,management,simulator,offline,business,network,economy
```

> Comma-separated, **no spaces after the commas** — a space is a character
> spent on nothing. Hidden from users; this is pure search surface.

**Support URL** — 53/255 characters

```text
https://wrexist.github.io/Airline-Empire/support.html
```

**Marketing URL** — 41/255 characters

```text
https://wrexist.github.io/Airline-Empire/
```

### English (U.K.)

**Promotional Text** — 147/170 characters

```text
Ninety-four real airports. Fourteen aircraft. One turboprop to start with. Free to play, with no adverts and no timers — Pro opens the whole world.
```

> The only field that can be changed **without submitting a new version**.
> Keep anything time-bound here and nothing permanent.

**Description** — 2917/4000 characters

```text
One aircraft. One route. Everything after that is yours to build.

Airline Empire is a deep, offline airline management simulator. You decide where to fly, what to fly and what to charge — and a living world answers back. Demand shifts with the seasons, fuel prices move, rivals undercut you on your best route, and every number you see can be opened up and explained.

BUILD A NETWORK THAT IS YOURS
• Ninety-four real airports across nine world regions — Arlanda, Heathrow, Haneda, Landvetter — each with its own demand, slot capacity, runway limits and weather risk
• Open routes, set frequencies, set the fare, and watch the map fill in behind you
• Grow from a single regional hop to widebodies and long-haul as you earn new eras and expand your fleet

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
• Pause, or run at up to 16×. It works in five minutes and it works for an hour
• Daily autosaves, backup recovery and campaign export/import — with Pro, keep multiple airlines in separate saves

FREE TO FLY, AND WE MEAN IT
• The whole simulation is free: the full ledger, every explainer, rivals that fight back, the seeded world you can replay exactly
• No adverts. No timers. No energy meter. No premium currency. Nothing to wait out and nothing to pay to skip
• A free airline flies the twenty airports nearest its home, through the Startup and Regional eras
• Airline Empire Pro opens the rest: National, International and Empire, all 94 airports across nine regions, widebodies and long-haul, every scenario, and as many airlines as you like
• Pro is more world, never a shortcut through it — no aircraft, route or advantage is ever sold

OFFLINE GAMEPLAY
• No game account, advertising or tracking
• Play your campaign in Aeroplane Mode; purchases and restoring Pro use Apple’s App Store services
• iPhone and iPad

A NOTE ON THE WORLD
The map is the real one: ninety-four real airports, from Arlanda to Haneda, with real geography, distances and time zones. The airlines, aircraft and manufacturers are invented for the simulation, which is what lets the economics be honest instead of approximate.
```

**Keywords** — 95/100 characters

```text
aviation,airport,aeroplane,airliner,aircraft,manager,management,simulator,offline,timetable,hub
```

> Comma-separated, **no spaces after the commas** — a space is a character
> spent on nothing. Hidden from users; this is pure search surface.

**Support URL** — 53/255 characters

```text
https://wrexist.github.io/Airline-Empire/support.html
```

**Marketing URL** — 41/255 characters

```text
https://wrexist.github.io/Airline-Empire/
```

### Screenshots

| App Store Connect tab | Canvas (px) | Status |
|---|---|---|
| iPhone 6.9" | 1320 × 2868 | in `store/screenshots/` |
| iPad 13" | 2064 × 2752 | in `store/screenshots/` |

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

**Notes** — 3956/4000 characters

```text
Airline Empire is a single-player airline management simulation. No sign-in is required.

WHAT THE APP DOES NOT DO
• No account, no sign-in, no user-generated content, no social features, no chat.
• Gameplay works offline. Prices, purchases and Restore purchases use Apple's StoreKit services and need a connection. Legal and support links open web pages. The simulation pauses while the app is closed; there is no offline catch-up.
• No advertising, third-party SDKs, analytics or tracking. Nothing is collected, so the privacy label declares no data collection and the bundled privacy manifest declares no tracking domains and private UserDefaults use (CA92.1) for preferences and Pro offer history.
• No gambling, no loot boxes, no randomised paid rewards. The only randomness is the simulation's own seeded world generation, which the player sets and can repeat.

IN-APP PURCHASES
The app is free to play. One entitlement, "Airline Empire Pro", sold three ways — a subscription group of two plans plus one non-consumable:

• com.airlineempire.game.pro.weekly — auto-renewable, 1 week. Introductory offer: pay as you go, 1 week at the reduced price.
• com.airlineempire.game.pro.yearly — auto-renewable, 1 year.
• com.airlineempire.game.pro.lifetime — non-consumable, one-time, never renews.

All three grant identical access.

WHAT THE FREE GAME INCLUDES
The entire simulation — the full ledger, every explainer, competitor airlines, world events, seeded replay, the map — through the Startup and Regional eras, on the Founder scenario, the twenty airports nearest the chosen home, one saved airline. No ads, energy meter or premium currency.

WHAT PRO ADDS
More world only: the National, International and Empire eras, all 94 airports across nine regions, the widebodies those eras allow, the Entrepreneur and Magnate scenarios, and unlimited saved airlines. No aircraft, route, cash or advantage is sold — which aircraft a player may buy is decided by the era their airline has earned, identically for free and paying players.

SEEING THE PAYWALL
Home → tap the airline-state strip to open the briefing → Settings → "Airline Empire Pro". It also appears once after completing the first flight, and whenever a locked control is tapped. Restore Purchases, Terms of Use and Privacy Policy are on the paywall and in Settings.

HOW TO SEE THE GAME QUICKLY
1. Launch, name an airline and choose a seed, then found it. Founder is the free, well-funded start ($90M). Entrepreneur ($60M) and Magnate ($35M, the harder start) require Pro; they are not needed to review the first playable loop.
2. Home opens on the map. Tap its next-action card to open the aircraft market, read the recommended aircraft and route, and lease an aircraft. The market closes after acquisition.
3. Tap the suggested route on Home, review the pre-filled route sheet, and open the route.
4. Open the route detail and assign the aircraft you leased.
5. Set the speed to 4×. Flights depart and arrive; use "Follow a flight" to follow one on the map. A month boundary closes a statement in Finance.
6. Open the briefing and Settings, then save and quit. A session recap appears. Continue the saved airline to verify persistence. Export/import backups are also in Settings and use Files.

AGE RATING
No violence, sexual content, profanity, substances, gambling or horror. The subject is running an airline: money, aircraft, schedules and reputation. Aircraft losses are modelled as financial and reputational events only; no crash, casualty or injury is depicted anywhere.

CONTENT AND LIKENESS
Cities and airports use factual names, codes and locations. Everything commercial is fictional: airlines, liveries, aircraft and manufacturers were invented for this simulation. No real airline or manufacturer trademark is depicted or referenced, no airport branding or imagery is used, and no real-world flight data is used.

CONTACT
Use the App Review contact supplied with the submission.
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
Airline Empire is a single-player airline management simulation. Found an airline, acquire aircraft, open routes, set fares, and run a network while competitors, seasons, fuel prices and world events change the market.

Gameplay works offline without a game account. Optional Pro purchases and Restore purchases use Apple’s App Store services and need a connection. Free players use Founder, the nearest twenty airports and the first two eras; existing operations remain playable at the expansion boundary.

WHAT TO TEST
1. Found a free airline. Home should open on the map with a next action and no immediate purchase offer.
2. Open the aircraft market from Home, read the suggested aircraft/route, and sign a lease. The market should close and the aircraft should appear in your fleet.
3. Open a suggested route from Home, then assign the aircraft from the route detail screen.
4. Run at 1x, 4x and 16x. Follow a live flight using the map menu, then drag to release the camera. Check departure, arrival and feed updates.
5. Advance to the next day and cross a month boundary; inspect route results and the Finance statement.
6. Save and quit, then continue. Check date, cash, fleet and network. Export a backup, quit, and import it into a fresh campaign slot where your plan permits another save.
7. Background mid-flight and return. Rehearse termination, low-storage failure and retry on a test device; existing campaigns must remain recoverable.
8. In the App Store sandbox, test Pro purchase, cancellation, pending approval, restore and expiry. After expiry, existing operations should continue while new paid expansion is blocked.

WHAT WE MOST WANT TO HEAR ABOUT
Report crashes, unreadable layouts, controls that do not respond, slow or hot devices, missing saves, incorrect purchase access, and numbers whose assumptions are unclear. Include device, iOS version, scenario, seed and steps. Do not include account passwords or payment details.
```

- **Feedback Email** — `REPLACE_ME@example.com`  ⚠️ **you must replace this**
- **Marketing URL** — `https://wrexist.github.io/Airline-Empire/`
- **Privacy Policy URL** — `https://wrexist.github.io/Airline-Empire/privacy.html`
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
