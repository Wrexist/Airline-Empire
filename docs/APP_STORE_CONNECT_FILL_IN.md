# App Store Connect — the fill-in sheet

<!-- GENERATED FILE — DO NOT EDIT BY HAND.
     Written by `node scripts/asc/build-fill-in-sheet.mjs` from `store/`,
     which is the single source of truth for the listing (decision D-012).
     Edit the files under store/metadata/, then regenerate. CI fails if this
     file is stale. -->

Everything App Store Connect asks for, in the order its own screens ask for
it, with the exact value to paste. Work top to bottom; nothing here needs
you to open another file.
Read the [handoff status](APP_STORE_HANDOFF_STATUS.md) before submitting:
prepared copy does not confirm live URLs, account setup or a release build.

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

**Subtitle** — 29/30 characters

```text
Offline Fleet & Route Manager
```

**Privacy Policy URL** — 67/255 characters

```text
https://airline-empire-official.isacmolin.chatgpt.site/privacy.html
```

#### English (U.K.)

_Add this localization first: the language dropdown at the top right of the page → **Add Language** → English (U.K.)._

**Name** — 29/30 characters

```text
Airline Empire: Flight Tycoon
```

**Subtitle** — 29/30 characters

```text
Offline Fleet & Route Manager
```

**Privacy Policy URL** — 67/255 characters

```text
https://airline-empire-official.isacmolin.chatgpt.site/privacy.html
```

### General Information

- **Primary Category** — Games
- **Primary Subcategory 1** — Simulation
- **Primary Subcategory 2** — Strategy
- **Secondary Category** — None

> Simulation and Strategy describe the game accurately. No additional category is needed; see [ASO rationale](ASO.md).

**Content Rights** — **account-holder declaration; confirm before submission.**
Cities, airports and geography are real. Commercial airlines, aircraft and
manufacturers are fictional. The map uses public-domain Natural Earth data.
Review the bundled asset licences and select the declaration that accurately
covers the submitted build; fictional brands do not make every asset original.

**Age Rating** → Edit. **hand-entry only.** Suggested answers for the current
single-player build are below. Confirm against the actual submitted build.

| Question | Answer |
|---|---|
| Parental Controls / Age Assurance | No / No |
| User-Generated Content / Social Media / Messaging and Chat | No |
| Advertising | No |
| Health or Wellness Topics | No |
| Guns or Other Weapons | None |
| Graphic Sexual Content and Nudity | None |
| Loot Boxes | No |
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

Expected general rating: **4+**, subject to Apple’s calculation and regional
rules. Do not change truthful answers to force a target rating. Aircraft
losses are financial events, not depicted violence. Contracts and AI rivals
are single-player mechanics, not contests between users. External legal links
do not provide unrestricted browsing inside the app.
Reference: [Apple age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/), checked 2026-09-09.

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

**Localized purchase text — use for English (U.S.) and English (U.K.).**

**Display name**

```text
Airline Empire Pro Weekly
```

**Description**

```text
All airports, all eras and unlimited saves.
```

**Display name**

```text
Airline Empire Pro Yearly
```

**Description**

```text
All airports, all eras and unlimited saves.
```

**Display name**

```text
Airline Empire Pro Lifetime
```

**Description**

```text
Full Pro access with a one-time purchase.
```

**IAP review screenshot:** a separate, genuine capture of the paywall showing
the configured products and prices is still needed. The six marketing images
are not substitutes for this review evidence. Verify products in StoreKit sandbox.

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

The current app has no developer-operated analytics, advertising SDK, crash
reporter or game account. Gameplay is local; purchases and restores use Apple
services, and legal/support links open external web pages. Confirm the privacy
declaration against the submitted build, its privacy manifest and public policy.

**Privacy Policy URL (asked again here)** — 67/255 characters

```text
https://airline-empire-official.isacmolin.chatgpt.site/privacy.html
```

---

## 5 · The version page — "iOS App 1.0"

_Left sidebar → the version under **iOS App**. Everything in this section
except the screenshots and the release option is what the metadata workflow
pushes for you._

### English (U.S.)

**Promotional Text** — 151/170 characters

```text
Build a regional airline into a global network. Master routes, grow your fleet and outsmart rivals. 94 airports to discover. No ads. Play at your pace.
```

> The only field that can be changed **without submitting a new version**.
> Keep anything time-bound here and nothing permanent.

**Description** — 2921/4000 characters

```text
Your first aircraft. Your first profitable route. Your airline, growing into an empire.

Build the network you have always wanted to run. Airline Empire is an offline airline management simulator for iPhone and iPad, where smart decisions turn a regional startup into a global business.

FIND YOUR NEXT GREAT ROUTE
Connect real places across a world map. Plan around demand, distance, runway limits and airport capacity. Set fares and frequencies, assign the right aircraft, and see how each decision changes your results.

BUILD A FLEET TO BE PROUD OF
Choose from 14 fictional aircraft types, from regional turboprops to long-haul widebodies. Buy new, find a used aircraft or lease your next addition. Balance capacity, range and running costs as your ambitions grow.

MAKE THE NUMBERS WORK FOR YOU
Understand what your airline earns and where the money goes. Route breakdowns, monthly statements and a detailed ledger help you spot opportunities, manage loans and build a stronger business.

OUTSMART A CHANGING WORLD
Compete with AI airlines as they expand and adjust their fares. Seasonal demand, fuel prices, storms and world events keep your strategy moving. Build a reputation through the service your passengers experience.

EARN YOUR NEXT MILESTONE
Grow through five eras: Startup, Regional, National, International and Empire. The full game includes 94 real airports across nine world regions and three starting scenarios. Progress opens new opportunities to build the airline your way.

PLAY AT YOUR PACE
Pause to plan or speed up the simulation to 16×. Daily autosaves, rolling backups and campaign export/import help protect your progress. Replay a seed to explore a different strategy. Campaigns run offline, without a game account.

START FREE. EXPAND WITH PRO.
Start with the Founder scenario, one campaign, the 20 airports nearest your home and the first two eras. Explore the core economy, fleet management and AI competition before choosing to expand.

Optional Airline Empire Pro opens all 94 airports, all five eras, every starting scenario and unlimited campaign saves. Choose an auto-renewing weekly or yearly subscription, or a one-time Lifetime purchase. All three provide the same Pro access.

No ads, energy meters, premium currency or paid shortcuts. You control the simulation clock; aircraft deliveries and other operations use game time.

Purchases and restoring Pro require Apple’s App Store services. Subscriptions renew automatically unless cancelled; manage them in your Apple Account settings. Saves stay on your device unless you export them. There is no multiplayer or automatic cloud save sync.

Real geography. Fictional airlines, aircraft and manufacturers. An empire shaped by your decisions.

Terms of Use (Apple Standard EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://airline-empire-official.isacmolin.chatgpt.site/privacy.html
```

**Keywords** — 97/100 characters

```text
airport,aircraft,aviation,planes,business,economy,management,simulator,network,transport,airliner
```

> Comma-separated, **no spaces after the commas** — a space is a character
> spent on nothing. Hidden from users; this is pure search surface.

**Support URL** — 67/255 characters

```text
https://airline-empire-official.isacmolin.chatgpt.site/support.html
```

**Marketing URL** — 55/255 characters

```text
https://airline-empire-official.isacmolin.chatgpt.site/
```

### English (U.K.)

**Promotional Text** — 155/170 characters

```text
Build a regional airline into a global network. Master routes, grow your fleet and outsmart rivals. 94 airports to discover. No adverts. Play at your pace.
```

> The only field that can be changed **without submitting a new version**.
> Keep anything time-bound here and nothing permanent.

**Description** — 2925/4000 characters

```text
Your first aircraft. Your first profitable route. Your airline, growing into an empire.

Build the network you have always wanted to run. Airline Empire is an offline airline management simulator for iPhone and iPad, where smart decisions turn a regional startup into a global business.

FIND YOUR NEXT GREAT ROUTE
Connect real places across a world map. Plan around demand, distance, runway limits and airport capacity. Set fares and frequencies, assign the right aircraft, and see how each decision changes your results.

BUILD A FLEET TO BE PROUD OF
Choose from 14 fictional aircraft types, from regional turboprops to long-haul widebodies. Buy new, find a used aircraft or lease your next addition. Balance capacity, range and running costs as your ambitions grow.

MAKE THE NUMBERS WORK FOR YOU
Understand what your airline earns and where the money goes. Route breakdowns, monthly statements and a detailed ledger help you spot opportunities, manage loans and build a stronger business.

OUTSMART A CHANGING WORLD
Compete with AI airlines as they expand and adjust their fares. Seasonal demand, fuel prices, storms and world events keep your strategy moving. Build a reputation through the service your passengers experience.

EARN YOUR NEXT MILESTONE
Grow through five eras: Startup, Regional, National, International and Empire. The full game includes 94 real airports across nine world regions and three starting scenarios. Progress opens new opportunities to build the airline your way.

PLAY AT YOUR PACE
Pause to plan or speed up the simulation to 16×. Daily autosaves, rolling backups and campaign export/import help protect your progress. Replay a seed to explore a different strategy. Campaigns run offline, without a game account.

START FREE. EXPAND WITH PRO.
Start with the Founder scenario, one campaign, the 20 airports nearest your home and the first two eras. Explore the core economy, fleet management and AI competition before choosing to expand.

Optional Airline Empire Pro opens all 94 airports, all five eras, every starting scenario and unlimited campaign saves. Choose an auto-renewing weekly or yearly subscription, or a one-time Lifetime purchase. All three provide the same Pro access.

No adverts, energy meters, premium currency or paid shortcuts. You control the simulation clock; aircraft deliveries and other operations use game time.

Purchases and restoring Pro require Apple’s App Store services. Subscriptions renew automatically unless cancelled; manage them in your Apple Account settings. Saves stay on your device unless you export them. There is no multiplayer or automatic cloud save sync.

Real geography. Fictional airlines, aircraft and manufacturers. An empire shaped by your decisions.

Terms of Use (Apple Standard EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://airline-empire-official.isacmolin.chatgpt.site/privacy.html
```

**Keywords** — 95/100 characters

```text
airport,aircraft,aviation,aeroplane,business,economy,management,simulator,network,transport,hub
```

> Comma-separated, **no spaces after the commas** — a space is a character
> spent on nothing. Hidden from users; this is pure search surface.

**Support URL** — 67/255 characters

```text
https://airline-empire-official.isacmolin.chatgpt.site/support.html
```

**Marketing URL** — 55/255 characters

```text
https://airline-empire-official.isacmolin.chatgpt.site/
```

### Screenshots

| App Store Connect tab | Canvas (px) | Status |
|---|---|---|
| iPhone 6.9" | 1320 × 2868 | in `store/screenshots/` |
| iPad 13" | 2064 × 2752 | in `store/screenshots/` |
| iPhone 6.5" (additional export) | 1242 × 2688 | six images in `store/screenshots/` |

Portrait, PNG, **no alpha channel**, at most ten per size. The six-shot
storyboard and captions are in `store/artwork/README.md`; the upload can be done for you
by the metadata workflow with **screenshots** ticked.

### App Review Information

**hand-entry only** for the sign-in question; the rest is pushed.

- **Sign-in required** — **No**. The game has no accounts of any kind.

- **First Name** — `Isac`
- **Last Name** — `Molin`
- **Phone Number** — `+46723241663`
- **Email** — `isacmolin@gmail.com`

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

**Copyright**

```text
2026 Isac Molin
```

- **Routing App Coverage File** — none.
- **Version publication** — **Manually release this version** — after approval, publish the pre-order only once every target region is configured correctly. The app downloads on its pre-order release date.
- **Availability** — Pre-order, planned release **2026-10-16**, 173 countries or regions. Excludes China mainland and Vietnam. Automatic expansion to future regions is off. See [release setup](RELEASE_SETUP.md). Version publication and pre-order availability are separate Apple settings.

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

- **Feedback Email** — `isacmolin@gmail.com`
- **Marketing URL** — `https://airline-empire-official.isacmolin.chatgpt.site/`
- **Privacy Policy URL** — `https://airline-empire-official.isacmolin.chatgpt.site/privacy.html`
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
