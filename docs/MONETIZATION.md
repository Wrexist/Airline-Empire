# Monetization

> How Airline Empire is sold, what a free player gets, what Pro adds, and
> every rule Apple enforces on the screen that sells it. Companions:
> `GAME_DESIGN.md` (the pillars this must not break), `ASO.md` (the listing),
> `GO_LIVE.md` (the App Store Connect steps), `APPLE_VALIDATION.md` (what of
> this is proven and what is assumed).
>
> Implemented by `AirlineEmpireCore/Sources/AirlineEmpireCore/Monetization/`
> (the rules, Linux-tested) and `AirlineEmpireApp/Sources/Monetization/`
> (StoreKit and the paywall).

## 1. The decision, and what it replaced

Version 1.0 was designed as a **paid app with no in-app purchases**
(`GAME_DESIGN.md` §7, `ASO.md` §2). It is now **free to start with one Pro
entitlement**, sold three ways.

The reason is conversion arithmetic, not taste. A paid game converts once, at
the store page, from a screenshot — and a deep management simulation is the
hardest possible thing to sell from six screenshots. Free-to-start moves the
sale to the moment the player already has an airline they built, which is
where this particular game is most persuasive.

What the pivot is **not** allowed to change is the game. `GAME_DESIGN.md` §1
names "waiting for timers, or paying to skip waiting" as explicitly not the
fantasy, and §2's pillars survive intact:

- No energy meter, no premium currency, no timer anywhere.
- No aircraft, airport, capability or advantage is sold. Pro is **more world,
  never a shortcut through it.**
- A free player gets the *whole simulation*: the full ledger, every demand
  and cost explainer, rivals that fight back, the map, the events, the
  seeded-replay determinism. What they run out of is world, not patience.
- No ads, in either tier.

That constraint is what makes the free tier a real game rather than a demo,
and it is the reason the gates are all *content* gates.

## 2. The entitlement

There is exactly one entitlement: **Pro**. Three products grant it, and
nothing in the game asks which one — a weekly subscriber and a lifetime owner
see an identical game. Anything else creates a pay-to-win axis.

`ProEntitlement` (Core) answers "is this player Pro, as of this instant" and
owns the three rules that decide it:

| Situation | Access | Why |
|---|---|---|
| Subscription within its period | Yes | Obvious. |
| Subscription cancelled, period not over | **Yes**, to the end date | They paid for the period. Ending it early is theft with extra steps. |
| Billing retry / grace period | **Yes** | Apple is still trying to collect. Locking a player out mid-campaign over a card decline turns a recoverable payment into a one-star review. |
| Subscription expired | No | |
| Lifetime | Yes, permanently | Never expires, outranks a stale subscription. |

The clock is a parameter, not `Date()`, so a test can move it a week.

## 3. The products

| Tier | Product ID | Price (US) | Offer |
|---|---|---|---|
| Pro Weekly | `com.airlineempire.game.pro.weekly` | $8.99 / week | **$0.99 first week** |
| Pro Yearly | `com.airlineempire.game.pro.yearly` | $39.99 / year | — |
| Pro Lifetime | `com.airlineempire.game.pro.lifetime` | $49.99 once | — |

Weekly is the default selection and sits first. In games, weekly is **82% of
every subscription plan sold** against 13% annual (RevenueCat, *State of
Subscription Apps 2026*) — this is the shape the market converts on.

Lifetime exists because of the other number in that report: games' median
revenue per payer over a full year is **$11.22**. Weekly churn is brutal, and
a player who would have cancelled in three weeks is worth more, and complains
far less, as a one-time buyer. Games already sell lifetime at ~9.6% of plans,
four times the cross-category average.

Yearly is the anchor. Its job on the paywall is to make the weekly price
legible as a yearly number, which is also what keeps the disclosure honest.

### 3.1 The introductory offer — the configuration that is easy to get wrong

"$0.99 for the first week, then $8.99/week" **cannot** be set up as a
*pay-up-front* introductory offer. Apple's allowed pay-up-front durations for
a one-week subscription are 1, 2, 3 or 6 months, or 1 year — not one week.

Configure it as:

- Type: **Pay As You Go**
- Duration: **1 week** (one billing period at the discounted price)
- Price: **$0.99**

Other rules that shape the design:

- **One introductory offer per subscription group, per Apple Account, ever.**
  All three plans live in the group `Airline Empire Pro`, so a player who
  takes the $0.99 weekly is not eligible for any offer on the yearly. This is
  why only the weekly carries an offer: spreading offers across the group
  would promise something most accounts cannot take.
- The paywall asks StoreKit for eligibility
  (`Product.SubscriptionInfo.isEligibleForIntroOffer`) and simply does not
  render the introductory line to an account that has spent it. It never
  advertises a price the player cannot get.
- Prices are **never written in this repository**. Every figure on the
  paywall comes from the loaded `Product`; a hard-coded "$8.99" is wrong in
  every storefront that is not the United States, and Apple rejects displayed
  prices that disagree with the product.

## 4. The gates — what is free and what is Pro

All of it lives in `ContentAccess`, one file, with a Linux test per rule.

| Dimension | Free | Pro |
|---|---|---|
| Eras | Startup + **Regional** | + National, International, Empire |
| Scenario | Founder | + Entrepreneur, Magnate |
| Saved airlines | 1 | Unlimited |
| Airports | The **20 nearest** to home, plus home | All 94, nine regions |
| Aircraft | Whatever the era allows | Whatever the era allows |
| Everything else | All of it | All of it |

Four decisions inside that table are worth their reasons.

**The ceiling is Regional, not Startup.** `PROGRESSION.md` §5 budgets 2–4
hours to the end of Regional — long enough for the map to fill in, for a
first profitable season, and for the network to start feeling owned, which is
the emotional payload the game exists to deliver. The wall then lands on the
player's own ambition. A one-era free tier walls the player during the
tutorial, before the game has made its case; games' 4.4% median
download-to-trial rate is set by whether the free slice was convincing, not
by how often the wall appeared.

**Twenty nearest airports, not the home region.** The regions are wildly
uneven — Europe ships 36 airports, the Middle East 4. A region rule would
have made the size of the free game depend on a choice the player makes in
the first thirty seconds, before they could know it mattered. Nearest-N is
the same free game from every home airport on the map, and it is also what a
regional airline *is*. A test asserts this for all 94 possible homes.

**No aircraft is sold.** The paywall locks no aircraft class of its own; the
*era* does, for paying and free players alike. Free players reach Regional
and fly everything up to a large narrowbody. Widebodies sit behind the era, as
they do for a player who bought Pro on day one and has not earned them yet.
One rule, one explanation, and no aircraft that is visible-but-purchasable.

**The free scenario is the easiest one.** Founder is the gentle start, so the
free tier is the *friendliest* configuration rather than a hobbled one.
Selling Entrepreneur and Magnate is selling replay and difficulty, not
selling advantage.

### 4.1 How the era ceiling is enforced

The airline still advances. `ProgressionSystem` decides eras from what the
airline has earned, and a paywall must not be able to change what the world
does — so the era transition happens, the celebration fires, and the player
sees that they earned it. What stops is **the clock**.

`GameController.eraCeiling` holds time at the ceiling and refuses to resume;
`EraCeilingBar` says so at the bottom of the screen. Every screen still
reads, every command still works, the save is intact. Buying Pro lifts the
bar immediately, mid-campaign, with no reload.

The alternative — refusing the era inside Core — would have meant a new field
in the save, a save-version bump, and a paying player's rules living in a
file that 253 deterministic tests depend on. This is the smaller blast radius
and the better sales moment.

The check runs on every snapshot rather than only on the `eraAdvanced` event,
because loading a save made before a subscription lapsed puts an airline
three eras past the ceiling with no transition to observe.

## 5. The paywall

Structure, in the order it argues: what the game is → how big it is → what
Pro adds → what it costs → **exactly what will be charged** → the button.

- `PaywallSky` — three great-circle arcs drawing across a night sky, the
  longest carrying an aircraft. A crown on a gradient is the genre default
  and says nothing about this game; *the network is the hero*
  (`GAME_DESIGN.md` §2, pillar 4) is what it is about.
- `PaywallStatBar` — 5 eras · 94 airports · 14 aircraft · 9 regions, read off
  `ContentCatalog`, never typed. A paywall promising 94 airports on a build
  carrying 80 is a refund with a screenshot attached.
- `PaywallBenefits` — eight lines, each naming a system that exists in this
  repository. Nothing on the paywall is a roadmap item in the present tense.
- `PaywallPlanCard` — three plans, weekly pre-selected. The recurring price
  is the largest number on the card; the discounted first period sits under
  the plan name, never over the price.
- The commitment sentence, then the button, then the assurances.

Copy lives in Core (`PaywallContent`) rather than in the view, because a
paywall's copy is a compliance surface and strings in a value type can be
asserted by a Linux test in a second.

### 5.1 Compliance — the specific rejections this design invites

The reference paywalls this was designed against render "Start 7 days free"
at roughly three times the size of the price. That is a rejection, verbatim:

> *Your auto-renewable subscription promotes the free trial or introductory
> period more clearly and conspicuously than the billed amount.*

What closes it here, with the test that holds each one:

| Requirement | Where | Test |
|---|---|---|
| Subscription title | Plan card | — |
| Length of the period | `renewalDescription` on every card | — |
| Price, and price per unit | Plan card, `AEType.metric` | `theCallToActionAlwaysNamesAPrice` |
| Billed amount at least as prominent as the intro | Commitment line directly above the button, body size | `theCommitmentLineAlwaysNamesTheBilledAmount` |
| Renewal terms, cancellation window, where to manage | `subscriptionTerms` | `subscriptionTermsCarryEveryRequiredClause` |
| Functional Terms of Use link | Paywall footer **and** Settings | — |
| Functional Privacy Policy link | Paywall footer **and** Settings | — |
| Restore Purchases | Paywall footer **and** Settings | — |

The call to action names an amount in every state it can be in — never a bare
"Continue". The refund and the rejection are the same defect.

### 5.2 The 3.1.2 "ongoing value" risk, stated plainly

Guideline 3.1.2 requires a subscription to provide ongoing value, and Apple's
own examples are new levels, episodic content, continually updated content,
SaaS and cloud. **Airline Empire is an offline, single-player game with no
server**, and a permanent content unlock sold as a subscription is the
textbook shape of a 3.1.2 rejection. Many games ship this anyway and pass.

This is a known, accepted risk, not an oversight. What reduces it:

- Pro Lifetime is a **non-consumable**, so the permanent-unlock path exists
  as a one-time purchase and the subscription is an alternative, not the only
  way to own the game.
- The disclosure above is complete and honest, which is what most 3.1.2
  rejections are actually about.
- The review notes (`store/metadata/review/notes.txt`) describe the tiers and
  the free game explicitly.

If App Review pushes back on the subscription tiers specifically, the fallback
that keeps the product shippable is to lead with Lifetime and drop the weekly
— a one-line change to `ProProduct.default` plus the removal of two products.

## 6. When the paywall appears

`PaywallPolicy` (Core), one function per rule. **Ask once early, answer every
time the player asks, and nag on a long fuse.**

| Trigger | Frequency |
|---|---|
| First run, after the first airline is founded | Exactly once, ever |
| A gate the player walked into (era, scenario, save, airport) | Every time, unthrottled |
| Opened from Settings or a Pro badge | Every time |
| Unprompted nudge | No sooner than 7 days, and **never after 4 refusals** |

Games start 81.5% of their trials on the day of install, so an offer that
never appears on day zero mostly never converts. The same report's 1.0%
median install-to-paid rate is why 99 of every 100 players must not be
followed around: after four refusals the app stops offering by itself and Pro
lives in Settings, permanently, one tap away.

The first-run offer comes **after** founding, not before. By then the player
has named an airline, chosen a livery and picked a home — the offer lands on
something they have begun, and declining leads into a real game instead of an
empty menu.

The nudge fires when the app returns to the foreground **with a game open**,
not on a timer inside a session: a sheet that interrupts someone mid-decision
is worse than one that greets them on the way in, and a paywall over the
new-game menu is an ad rather than an offer.

A gate is never answered with silence. A locked control that does nothing
when tapped is the defect this codebase has three bug numbers for (BUG-029,
BUG-030, BUG-032).

**A Pro player is never shown a paywall.** Not throttled — never.

## 7. The StoreKit layer

`Entitlements` is the only file in the project that imports StoreKit. Core
builds and tests on Linux, and the rules about what a purchase is worth
already live there.

- The transaction listener starts **before** the first entitlement refresh. A
  transaction completing during launch — an Ask to Buy approval, a purchase
  made on another device, an interrupted purchase Apple is retrying — arrives
  on `Transaction.updates` and would fall into the gap otherwise. A lost
  transaction is a player who paid and did not get the game.
- An **unverified** transaction grants nothing and is not finished, so
  StoreKit offers it again rather than the player silently losing it.
- `Transaction.currentEntitlements` is the source of truth; it already
  excludes expired, refunded and revoked purchases.
- A failed product load is a normal state for a game that advertises itself
  as fully offline. The paywall says "prices unavailable" and offers Retry —
  it never renders a guessed price.

### 7.1 Testing

- `AirlineEmpireApp/Resources/AirlineEmpire.storekit` serves the three
  products locally. Wired into the Debug **run** action only
  (`project.yml`), so the release archive talks to the real App Store.
- A UI-test process is **Pro by default**. Every journey in `UITests/` founds
  an airline and then drives the game; the first-run paywall would open a
  sheet over the first tap of all of them. `-AEUITestFree` opts into the free
  tier for journeys that are about the gates.
- The free tier is therefore only exercised by tests that ask for it. That
  gap is recorded in `APPLE_VALIDATION.md` rather than papered over.

## 8. App Store Connect setup

Everything below needs a human with the Apple Developer account.

1. **Agreements** → the Paid Applications agreement must be active, with tax
   and banking complete. In-app purchases cannot be sold without it.
2. **App price** → Free.
3. **Subscriptions** → create the group **`Airline Empire Pro`**, then:
   - `com.airlineempire.game.pro.weekly` — 1 week, $8.99, group level 1
   - `com.airlineempire.game.pro.yearly` — 1 year, $39.99, group level 1
4. **Introductory offer** on the weekly only — Pay As You Go, 1 week, $0.99
   (see §3.1; pay-up-front is not available at this duration).
5. **In-App Purchases** → `com.airlineempire.game.pro.lifetime`, a
   **Non-Consumable**, $49.99.
6. Each product needs a display name, a description, and a review screenshot
   of the paywall. All three are submitted **with** the app version.
7. Family Sharing is enabled on all three in the `.storekit` fixture; match
   that in App Store Connect or change the fixture, so the two agree.

Product identifiers are **immutable once created**. `productIdentifiersAreStable`
is a test that exists to make a rename fail loudly rather than silently
orphaning every existing purchase.

## 9. What is proven, and what is not

Proven on Linux, in CI, on every push: the entitlement clock, all four gates,
the airport radius for all 94 homes, the presentation policy, and the
paywall's required clauses — 30 tests.

Not proven anywhere yet, and needing a device or a simulator:

- That the paywall renders as designed at every Dynamic Type size.
- That a purchase completes, and that the era bar lifts mid-campaign when it
  does.
- That restore works against a real Apple Account.
- That the introductory offer displays as Pay As You Go on a real product.
- That App Review accepts §5.2.

Nothing above should be described as working until it has been observed.
