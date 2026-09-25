# Game Center

> Achievements and leaderboards for the **first update (1.2)**. Version
> 1.1.0 (13) is approved and on pre-order for 16 October, so Game Center does
> not ship in it; this is
> built, tested and staged so the update — and its App Enhancements featuring
> nomination (`docs/APP_STORE_FEATURING_NOMINATION.md`) — can go as soon as
> 1.0 is out.

## 1. What it is, and what it is not

Game Center adds **no rules**. Every achievement is a milestone,
achievement or era `ProgressionSystem` already awards and the celebration
overlay already shows. Every leaderboard is a count the simulation already
keeps. Nothing in the game waits on it, and a player who never signs in
loses nothing.

- **Never interrupts.** GameKit offers a sign-in screen at launch. It is
  held and shown only from Settings → Game Center — never over a new
  player's first minute, which is also where the first-run Pro offer lands.
- **No duplicate celebration.** Achievements report with
  `showsCompletionBanner = false`; the game's own overlay already marks
  each one at the moment it happens.
- **Converges without bookkeeping.** The full earned set is reported
  whenever it changes and again at every sign-in. Game Center ignores a
  report for something already complete, so offline play, a reinstall or a
  second device all catch up with no record of what was sent.
- **Leaderboards rank the world, not money.** Passengers, network size and
  delivered fleet. Cash would rank the starting scenario — Magnate begins
  with several times Founder's — rather than play.
- **Off in UI tests,** like the Pro override, so no GameKit sheet can land
  over a journey.

Code: `AirlineEmpireCore/.../Session/GameCenterCatalog.swift` (the mapping,
Linux-tested), `AirlineEmpireApp/Sources/App/GameCenter.swift` (the only
file that imports GameKit), `GameCenterSection.swift` (Settings).

## 2. The catalogue

Titles, points and IDs below are generated from
`store/game-center/catalog.json`, which CI checks against the Swift file on
every pull request (`render.mjs --check`). **IDs are permanent** once
created in App Store Connect; renaming one orphans every player's progress.

### Achievements — 17, totalling exactly 1,000 points

Apple caps one achievement at 100 points and a game at 1,000. Spending the
full budget now means nothing can be added later without deciding what it
is worth against these.

| # | Achievement ID | Title | Points | Image |
|---|---|---|---|---|
| 1 | `com.airlineempire.game.achievement.firstFlight` | First flight | 20 | `achievements/firstFlight.png` |
| 2 | `com.airlineempire.game.achievement.firstOwnedAircraft` | First aircraft of your own | 15 | `achievements/firstOwnedAircraft.png` |
| 3 | `com.airlineempire.game.achievement.firstProfitableMonth` | First profitable month | 25 | `achievements/firstProfitableMonth.png` |
| 4 | `com.airlineempire.game.achievement.eraRegional` | Regional carrier | 30 | `achievements/eraRegional.png` |
| 5 | `com.airlineempire.game.achievement.fleet10` | A fleet of ten | 40 | `achievements/fleet10.png` |
| 6 | `com.airlineempire.game.achievement.destinations10` | Ten destinations | 40 | `achievements/destinations10.png` |
| 7 | `com.airlineempire.game.achievement.passengers100k` | 100,000 passengers | 50 | `achievements/passengers100k.png` |
| 8 | `com.airlineempire.game.achievement.firstMillionMonth` | First million-dollar month | 60 | `achievements/firstMillionMonth.png` |
| 9 | `com.airlineempire.game.achievement.eraNational` | National airline | 60 | `achievements/eraNational.png` |
| 10 | `com.airlineempire.game.achievement.firstIntercontinental` | First intercontinental route | 70 | `achievements/firstIntercontinental.png` |
| 11 | `com.airlineempire.game.achievement.eraInternational` | International airline | 80 | `achievements/eraInternational.png` |
| 12 | `com.airlineempire.game.achievement.passengers1m` | One million passengers | 90 | `achievements/passengers1m.png` |
| 13 | `com.airlineempire.game.achievement.eraEmpire` | Airline empire | 100 | `achievements/eraEmpire.png` |
| 14 | `com.airlineempire.game.achievement.debtFree` | Debt free | 80 | `achievements/debtFree.png` |
| 15 | `com.airlineempire.game.achievement.weatherProof` | Weatherproof | 80 | `achievements/weatherProof.png` |
| 16 | `com.airlineempire.game.achievement.valueLegend` | Value legend | 80 | `achievements/valueLegend.png` |
| 17 | `com.airlineempire.game.achievement.purist` | Single-family purist | 80 | `achievements/purist.png` |

Pre-earned and earned descriptions for each are in `catalog.json`
(`preEarned`, `earned`; all under Apple's 255-character limit). None are
hidden. Image tiers follow points: bronze up to 30, silver up to 60, ember
gold above.

### Leaderboards — 3

| Leaderboard ID | Title | Type | Score | Image |
|---|---|---|---|---|
| `com.airlineempire.game.leaderboard.passengers` | Passengers flown | Classic, all time | Integer, High to low | `leaderboards/passengers.png` |
| `com.airlineempire.game.leaderboard.destinations` | Largest network | Classic, all time | Integer, High to low | `leaderboards/destinations.png` |
| `com.airlineempire.game.leaderboard.fleet` | Largest fleet | Classic, all time | Integer, High to low | `leaderboards/fleet.png` |

Score format suffixes (English): "passengers", "destinations", "aircraft".

### Images

Rendered by `node store/game-center/render.mjs` at 1024×1024, opaque PNG,
with all content inside the inscribed circle because Game Center masks to
one. No text in any image — titles are localised beside them. Icons are
Google Material Symbols (Apache-2.0), vendored in `store/game-center/icons/`
so the render is reproducible offline.

## 3. App Store Connect setup (owner, Claude in Chrome can do this)

1. **App → Distribution → Features → Game Center.** Enable Game Center for
   the app, and set up achievements and leaderboards as **single-game**
   (not a Game Center group) unless you plan a second title that should
   share them.
2. **Achievements → +** for each row above: Reference name = title, ID
   exactly as listed, points as listed, Hidden = No, Achievable more than
   once = No. Add an English (U.S.) localisation: title, pre-earned
   description, earned description, image. Repeat English (U.K.).
3. **Leaderboards → + → Classic** for each row: ID, reference name, score
   format Integer, submission type *Best score*, sort High to low, score
   range 0 to 2,000,000,000. Localisation: title, format suffix, image.
4. **The 1.2 version page → Game Center → add** all 17 achievements and 3
   leaderboards, so they go to review with the build that reports them.
5. **Privacy.** Game Center data is processed by Apple under the player's
   Game Center settings. Re-read Apple's current App Privacy guidance for
   GameKit before submitting 1.2, and update the label only if it now
   requires a declaration; the in-app privacy line in Settings already
   says where the data goes.

## 4. Signing — check before the first 1.2 archive

The app now declares `com.apple.developer.game-center`
(`Resources/AirlineEmpire.entitlements`, wired by `project.yml`).

- **Automatic signing** (`-allowProvisioningUpdates`): regenerates the
  profile with the capability. Nothing to do.
- **Manual signing** (the `IOS_PROVISIONING_PROFILE_BASE64` secret): the
  stored profile must include Game Center. It normally does — the
  capability is on by default for an explicit App ID — but a profile
  generated before the App ID had it will fail the archive with an
  entitlement mismatch. Check in Certificates, Identifiers & Profiles →
  Profiles → the App Store profile → Enabled Capabilities. Regenerate and
  update the secret if Game Center is missing.

## 5. What is proven, and what is not

Proven on Linux in CI: the mapping from every awarded code to an
achievement (the test reads `ProgressionSystem.swift` and fails naming any
code left out — verified by deleting one), ID stability and uniqueness,
Apple's point limits, era coverage, earned-set and fingerprint behaviour,
and leaderboard scores from a real session. Also: catalog ↔ Swift parity.

Not proven: that GameKit authenticates, that reports and submissions reach
Game Center, and that the Settings section renders — those need a device
signed in to a sandbox Game Center account, on the first 1.2 TestFlight.
