# App Store Connect — Claude in Chrome prompt

Claude in Chrome runs in **your** browser, where you are signed in to App
Store Connect. A cloud session cannot sign in to your Apple Account (2FA is
tied to your devices), so this is the handoff: open App Store Connect, open
Claude in Chrome, and paste the prompt in §3. It is written to verify first,
change only the few things listed, and stop before anything irreversible.

## 1. What the API audit already established (25 September)

Read-only runs of `app-store-metadata.yml` in plan mode (no `--apply`; the
write, screenshot and URL steps were skipped):

| Fact | Evidence |
|---|---|
| Version **1.1.0 is `READY_FOR_DISTRIBUTION`** | run 36191754996: the tool refused to edit it, as it should |
| **173 of 175 territories** `AVAILABLE_FOR_PREORDER`; China mainland and Vietnam excluded | crash-audit artifact `territories.json` |
| Release date **16 October**, pre-order published **24 September**, in all 173 | same |
| Weekly, Yearly, Lifetime each in the same 173 territories | same |
| One beta crash on record: build **1**, 28 August, negative day in the daily digest | `beta-crashes.json`; fixed since (`dailyDigest` guards `dayIndex >= 0`, covered by a Core test) |
| Listing on this branch validates with **0 warnings** | validate job |

**Tooling finding.** `push-metadata.mjs` looks versions up by exact
`versionString`. Asked for `1.0`, `1.0.0` or `1.0.22` it plans to **create**
that version, because none exists. An `apply` run with the wrong string would
therefore have created a stray version rather than failed. **Fixed:**
`refuseVersionCreation` in `scripts/asc/lib/asc.mjs` now refuses — in plan
mode too — to create any version that is not higher than every existing one,
with two selftests covering the 25 September strings. Still pass the real
version (`1.1.0` today, `1.2.0` next).

## 2. What can still change while 1.1.0 waits for release

| Item | Changeable now? |
|---|---|
| 1.1.0 description, keywords, screenshots, What's New | **No** — frozen until 1.2.0 exists |
| Promotional text | Yes, any time |
| Featuring nomination | Possibly — depends on Apple letting a submitted one be edited |
| App Privacy, age rating, pricing, availability | Yes, but **none needs changing** — leave them |
| Game Center achievements and leaderboards | Can be created now; attach to 1.2.0 later |
| In-App Event | Only once 1.2.0 is live |

## 3. The prompt — paste into Claude in Chrome

```text
You are helping me check and tidy my app "Airline Empire: Flight Tycoon"
(Apple ID 6806410538) in App Store Connect. I am signed in. Work in the
current tab.

HARD RULES — never break these:
- Never click Submit for Review, Add for Review, Release This Version,
  Remove from Sale, Delete, Cancel Pre-Order, or anything that changes
  price, availability, territories, release date or pre-order settings.
- Never edit version 1.1.0's description, keywords, screenshots or What's New.
- Never change App Privacy, age rating, agreements, tax or banking.
- Only type text that appears verbatim in this prompt.
- If a page looks different from what I describe, or anything asks for a
  password, a confirmation you are unsure of, or a payment: stop and ask me.
- Before every Save, tell me exactly what you are about to save and wait
  for me to say yes.

PART A — READ ONLY. Report each item as "matches" or "differs: <what you see>".
1. Apps → Airline Empire → Distribution. iOS version shown: expect 1.1.0,
   status "Ready for Distribution" (or pre-order equivalent), build 1.1.0 (13).
2. Pricing and Availability: price Free; pre-order ON; release date
   16 October 2026; 173 countries or regions; China mainland and Vietnam
   NOT selected.
3. Monetization → Subscriptions → group "Airline Empire Pro": Pro Weekly
   and Pro Yearly both Approved. Pro Weekly has an introductory offer:
   Pay As You Go, 1 week, $0.99 (US).
4. Monetization → In-App Purchases: Pro Lifetime, Non-Consumable, Approved.
5. App Privacy: shows "Purchase History", used for App Functionality and
   Analytics, not linked to identity, not used for tracking. Privacy Policy
   URL is https://wrexist.github.io/Airline-Empire/privacy.html
6. App Information: Primary category Games → Simulation, Strategy;
   age rating 4+.
7. Distribution → Nominations: the App Launch nomination
   "Airline Empire — Your first route to a global network", status Submitted.
   Tell me whether it can still be edited, and what supplemental-material
   URL it shows.

PART B — TWO SMALL FIXES (ask me before each Save).
8. Promotional text (on the 1.1.0 version page; it stays editable).
   If English (U.S.) differs from the text below, replace it:
   Start free with one aircraft and one route, then build a global airline. 94 real airports, rivals that fight back, no ads, no timers. Plays fully offline.
   If English (U.K.) differs from the text below, replace it:
   Start free with one aircraft and one route, then build a global airline. 94 real airports, rivals that fight back, no adverts, no timers. Plays fully offline.
9. Only if step 7 says the nomination is editable AND its supplemental URL
   is https://airline-empire-official.isacmolin.chatgpt.site/press.html :
   change that URL to https://wrexist.github.io/Airline-Empire/press.html
   and change nothing else in the nomination.

Finish with a short table of every item: matches / differs / changed / skipped.
```

## 4. Later — Game Center and the 1.2 In-App Event

Do these when you are ready to build 1.2.0, not before: the achievement and
leaderboard IDs are permanent once created. Everything to enter is in
[`GAME_CENTER.md`](GAME_CENTER.md) §3 (IDs, points, titles, descriptions,
images in `store/game-center/`), and the event in
[`APP_STORE_IN_APP_EVENT.md`](APP_STORE_IN_APP_EVENT.md). Claude in Chrome
can enter them from those files; give it the same hard rules as above, and
upload images from `store/game-center/achievements/` and
`store/game-center/leaderboards/`.
