# Go live — the step-by-step

Everything between where the project is today and Airline Empire being on the
App Store, in the order it has to happen, with the commands to run and what
"done" looks like for each step.

**Legend:** 🧑 you, by hand · 🤖 a workflow or a script · ⏳ waiting on Apple

Where a step needs detail, it points at the page that has it:
[`APP_STORE_CONNECT.md`](APP_STORE_CONNECT.md) (accounts, keys, secrets) ·
[`RELEASE_PIPELINE.md`](RELEASE_PIPELINE.md) (what the workflows do) ·
[`ASO.md`](ASO.md) (the listing) · [`APPLE_VALIDATION.md`](APPLE_VALIDATION.md)
(the device walkthrough).

---

## Stage 0 — Merge this work (10 minutes)

**0.1** 🧑 Open a pull request from `claude/airline-empire-workflows-aso-fbvml7`
to `main`, or merge it directly if you would rather not review it in a PR.

**0.2** 🤖 CI runs on the PR. Expect **core** and **release-tooling** green.
The **iOS app (xcodebuild)** job will run for the first time in this
repository's history — see stage 1.

**0.3** 🧑 Merge.

> Nothing after this point depends on my session. Everything below is yours,
> and the order is chosen so that the free, fast and reversible steps happen
> before the ones that cost money or take days.

---

## Stage 1 — Find out whether the app compiles ✅ done, 2026-08-28

**Already answered: it compiles.** CI run 33213797384 built the app with
`xcodebuild` on a macOS runner — `** BUILD SUCCEEDED **`, Xcode 26.6, iOS 26.5
simulator SDK, no source changes needed. Nothing to do here unless CI goes red
later, in which case:

**1.1** 🤖 Actions → **CI** → Run workflow → on `main`. A manual dispatch
always runs the macOS job regardless of what changed.

**1.2** 🧑 Read the **iOS app (xcodebuild)** job.

- **Green:** the SwiftUI shell compiles. Update
  `tasks/CURRENT_PHASE.md` — the app moves from AUTHORED to **COMPILED** — and
  note the run number. This closes half of blocker B-002.
- **Red:** read the errors. Expect Apple-SDK-specific ones rather than logic
  errors: SwiftUI API availability, `#if os(iOS)` gaps, Swift 6 actor
  isolation. `APPLE_VALIDATION.md` §2 says where to fix them (in the App
  layer, almost never in Core). Fix, push, repeat until green.

**Do not go further while this is red.** Everything below archives, signs and
ships whatever this compiles.

---

## Stage 2 — The Apple account (1 day to 2 weeks, 99 USD/year)

Start this early: enrolment can take days, and the Paid Applications agreement
plus banking details take longer than anyone expects. Details:
[`APP_STORE_CONNECT.md`](APP_STORE_CONNECT.md) §1.

**2.1** 🧑 Enrol in the Apple Developer Program at
<https://developer.apple.com/programs/>. Individual is same-day-ish;
organisation needs a D-U-N-S number and takes longer. **The app is published
under this name** — changing entity type later is a migration.

**2.2** ⏳ Wait for approval.

**2.3** 🧑 App Store Connect → Business → accept the **Paid Applications
agreement**, and complete **tax and banking**. A paid app cannot be sold
without it, and the usual way to discover that is on release day.

**2.4** 🧑 Note your **Team ID** (Developer portal → Membership). Ten
characters.

✅ Done when: you can sign in to App Store Connect and the Paid Applications
agreement shows as active.

---

## Stage 3 — Register the app (20 minutes)

Details: [`APP_STORE_CONNECT.md`](APP_STORE_CONNECT.md) §2.

**3.1** 🧑 Developer portal → Identifiers → + → App IDs → App. Explicit bundle
ID **`com.airlineempire.game`**. **No capabilities** — the app uses none.

**3.2** 🧑 App Store Connect → Apps → + → New App. Every value for this form
— and for every other screen App Store Connect will ask you about — is in
[`APP_STORE_CONNECT_FILL_IN.md`](APP_STORE_CONNECT_FILL_IN.md) §1, ready to
paste.

> If the name is taken, pick the alternative now and change it in
> `store/metadata/en-US/name.txt`, `store/metadata/en-GB/name.txt` and
> `docs/ASO.md` §3 in the same commit. The name in the listing must equal the
> name on the record.

**3.3** 🧑 If you ever change the bundle id, change it in all three files —
`store/config.json`, `AirlineEmpireApp/project.yml`,
`.github/workflows/ios-testflight.yml`. CI fails if they disagree, so you
cannot get this half-done silently.

✅ Done when: the app appears in App Store Connect with the right bundle id.

---

## Stage 4 — Keys and secrets (30 minutes)

Details: [`APP_STORE_CONNECT.md`](APP_STORE_CONNECT.md) §3–5.

**4.1** 🧑 App Store Connect → Users and Access → Integrations → App Store
Connect API → **Team Keys** → +. Name it "CI — Airline Empire", role **App
Manager**. Download the `AuthKey_XXXXXXXXXX.p8` — **Apple allows exactly one
download.**

**4.2** 🧑 Encode it:

```sh
base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | pbcopy    # macOS/Linux
```

**4.3** 🧑 GitHub → Settings → Secrets and variables → Actions. Add four:

| Secret | Value |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | the key ID, e.g. `ABC123XYZ9` |
| `APP_STORE_CONNECT_ISSUER_ID` | the Issuer ID (a UUID) above the key list |
| `APP_STORE_CONNECT_API_KEY_BASE64` | what you just copied |
| `APPLE_TEAM_ID` | the ten-character Team ID from 2.4 |

**4.4** 🤖 Prove they work, locally, in two seconds:

```sh
export APP_STORE_CONNECT_KEY_ID=... APP_STORE_CONNECT_ISSUER_ID=... APP_STORE_CONNECT_API_KEY_BASE64=...
node scripts/asc/preflight.mjs
```

Expect: three ticks and the app record's name. A bare HTTP 401 means the key
id, issuer id and `.p8` are not all from the same key.

**4.5** 🧑 *(Optional now, recommended later.)* Manual signing: export the
distribution certificate as a `.p12` and download the App Store provisioning
profile, then add `IOS_DISTRIBUTION_CERT_P12_BASE64`,
`IOS_DISTRIBUTION_CERT_PASSWORD` and `IOS_PROVISIONING_PROFILE_BASE64` — all
three or none ([`APP_STORE_CONNECT.md`](APP_STORE_CONNECT.md) §4). Skip it for
the first build: without them, Xcode signs automatically using the API key.

✅ Done when: `preflight.mjs` prints "Preflight clear."

---

## Stage 5 — The app icon (blocking, needs a designer or you)

**Nothing can be uploaded without it.** The workflow now fails on the cheap
runner rather than after the archive, but it still fails.

**5.1** 🧑 Draw or commission a 1024×1024 PNG, **no alpha channel**, no
rounded corners of its own, no text, legible at 60 points. The brief — what to
draw, what the category already looks like, what to avoid — is
[`ASO.md`](ASO.md) §6.

**5.2** 🧑 Save it as
`AirlineEmpireApp/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
and add `"filename": "icon-1024.png"` to that folder's `Contents.json`.

**5.3** 🤖 Check it:

```sh
node scripts/asc/check-app-icon.mjs
```

Expect: "✓ App icon present, 1024×1024, no alpha."

✅ Done when: that command exits 0 and CI is green.

---

## Stage 6 — First build to TestFlight (1 hour, mostly waiting)

Details: [`RELEASE_PIPELINE.md`](RELEASE_PIPELINE.md).

**6.1** 🤖 Actions → **iOS TestFlight** → Run workflow. Version `1.0.0`,
**upload OFF**. This proves signing and export without touching Apple.

**6.2** 🧑 Download the `.ipa` artefact from the run. It should exist and be
tens of megabytes. If the job failed at signing, the fix is
[`APP_STORE_CONNECT.md`](APP_STORE_CONNECT.md) §4.

**6.3** 🤖 Run it again with **upload ON**. The macOS job validates and
uploads; the ubuntu `processing` job polls until Apple reports the build VALID.

**6.4** 🧑 App Store Connect → TestFlight → add yourself to the **Internal
Testing** group. Install TestFlight on your phone, install the build.

✅ Done when: Airline Empire launches on a physical iPhone.

---

## Stage 7 — Actually play it (a day, and the real gate)

This is the step the entire project has been waiting on, and no amount of
green CI substitutes for it.

**7.1** 🧑 Walk [`APPLE_VALIDATION.md`](APPLE_VALIDATION.md) §4 — all fifteen
steps, on an iPhone, then on an iPad. New game → buy a used aircraft → open a
suggested route → assign the aircraft → run at 4× → close a month → check the
feed shows only your airline → force a rejected command → read the daily
digest → save, quit, reload → background the app → reach game over and start
again.

**7.2** 🧑 File what you find as bugs in `tasks/BUGS.md`, P0/P1 first.
Rendering, gestures, `@Observable` update behaviour, scene-phase autosave and
accessibility have **never** been exercised; expect findings.

**7.3** 🧑 Fix, push, and repeat stage 6 with `1.0.1`, `1.0.2`, … until a
build survives the walkthrough.

✅ Done when: you can play a full session on a device without hitting a P0 or
P1.

---

## Stage 8 — Screenshots (half a day, needs a Mac or a simulator build)

**8.1** 🧑 Play a real game until the map is full — forty-ish routes, two
continents, an aged fleet. Three routes and no money reads as a demo.

**8.2** 🧑 Capture the six screens in [`ASO.md`](ASO.md) §5, in that order, on
a 6.9-inch iPhone simulator (1320×2868) and a 13-inch iPad simulator
(2064×2752). Same seed and same airline name across all six — it is one story.

**8.3** 🧑 Add the captions from that table, in the app's own type, at the top,
legible at thumbnail size.

**8.4** 🧑 Save them as
`store/screenshots/en-US/APP_IPHONE_67/01-map.png` … `06-digest.png`, and the
same six under `APP_IPAD_PRO_3GEN_129`. Copy the set to `en-GB` (same
language, same shots).

**8.5** 🤖 `node scripts/asc/validate-metadata.mjs` — it checks the canvas
sizes and rejects any image with an alpha channel.

✅ Done when: the validator lists six shots per display type with no errors.

---

## Stage 9 — Finish the listing (1 hour)

**9.1** 🧑 Replace every `REPLACE_ME`:

| Where | What |
|---|---|
| `store/config.json` → `review.*` | your name, email and phone for App Review |
| `store/config.json` → `copyright` | e.g. `2026 Isac Molin` — the legal entity on the account |
| `site/support.html` | the support email address |

**9.2** 🧑 Read the copy once as a stranger would:
`store/metadata/en-US/description.txt`, `subtitle.txt`, `promotional_text.txt`.
It is your product's pitch, and it is the part of this work most worth your
own judgement.

**9.3** 🤖 The strict validation — the one a release requires:

```sh
node scripts/asc/validate-metadata.mjs
```

Expect: "✓ Listing is valid." with no `REPLACE_ME` errors.

**9.4** 🧑 Commit and merge.

✅ Done when: the strict validator passes on `main`.

---

## Stage 10 — Publish the support and privacy pages (20 minutes)

Apple requires both URLs to resolve, and the listing already points at them.

**10.1** 🧑 GitHub → Settings → Pages → Source: **GitHub Actions**. (The
repository must be public, or on a plan that allows private Pages.)

**10.2** 🤖 Actions → **Publish the support site** → Run workflow.

**10.3** 🧑 Open `https://wrexist.github.io/airline-empire/privacy` and
`/support`. If the published URL differs from that, change the three URL files
in `store/metadata/*/` to match — those are what Apple will open.

✅ Done when: both pages load in a browser you are not signed into.

---

## Stage 11 — Push the listing (15 minutes)

**11.1** 🤖 Actions → **App Store metadata** → Run workflow. Version `1.0.0`,
mode **plan**. Read the before/after it prints.

**11.2** 🤖 Run it again: mode **apply**, type `APPLY` in the confirm box, and
tick **screenshots**.

**11.3** 🧑 Open the app in App Store Connect and look at the page. Everything
should be there except the answers only the web UI takes — those, and every
other field with its exact value, are in
[`APP_STORE_CONNECT_FILL_IN.md`](APP_STORE_CONNECT_FILL_IN.md), which is
generated from `store/` and can be worked top to bottom:

- **App Privacy** → "Do you collect data?" → **No**
  ([`APP_STORE_CONNECT.md`](APP_STORE_CONNECT.md) §6)
- **Age Rating** → every question **None**, expect 4+ (§7 there)
- **Pricing and Availability** → your price tier and storefronts (§10 there)

✅ Done when: the App Store Connect page has no yellow "required" markers left.

---

## Stage 12 — Submit (10 minutes, then 1–3 days of review)

**12.1** 🧑 In App Store Connect, attach the build from stage 6 to version
1.0.0.

**12.2** 🧑 Read `store/metadata/review/notes.txt` once — it tells the reviewer
the game is offline, has no account, and how to reach a mid-game state in five
taps. It is already accurate; make sure it still is.

**12.3** 🧑 **Submit for Review.** Deliberately not automated: this is the one
irreversible outward-facing action in the sequence, and a person should look
at the page before a reviewer does.

**12.4** ⏳ Wait. Typically a day or two.

**12.5** 🧑 On approval: the release type is **MANUAL**, so nothing goes live
until you press **Release**. Press it when you are ready to answer support
email.

---

## Afterwards

- **Watch, then change one thing at a time.** [`ASO.md`](ASO.md) §10 has the
  metrics that mean something and the three rules for changing metadata.
- **The first experiment** is `tycoon` versus `simulator` in the app name,
  through Apple's Product Page Optimisation rather than a guess (§3 there).
- **Promotional text** can be changed any time without a new version. Nothing
  else in the listing can.
- **Update `docs/RELEASE_PIPELINE.md`'s "what has actually run" table** as each
  path runs for the first time. It is the only honest record of what this
  pipeline has done, and it is worth keeping honest.

---

## The critical path, in one line

Compile (stage 1) → Apple account (2) → app record (3) → secrets (4) → **icon
(5)** → TestFlight (6) → **play it (7)** → screenshots (8) → listing (9–11) →
submit (12).

Stages 2 and 5 are the long poles: one is bureaucratic waiting, the other is
creative work nobody has started. Both can begin today, in parallel with
everything else.
