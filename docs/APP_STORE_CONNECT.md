# App Store Connect — the one-time setup

Everything in this repository that talks to Apple depends on account state that
no agent session, no CI job and no script can create: an Apple Developer
membership, an app record, a signing certificate. This is that list, in the
order it has to happen, with the exact values each step produces and where they
go.

**Nothing on this page has been done.** As of 2026-08-28 the project has no
Apple Developer account. Every step is written from Apple's documentation and
from the same setup performed in a sibling repository, and each one should be
ticked here *by the person who did it*, with the date — the same rule
[`APPLE_VALIDATION.md`](APPLE_VALIDATION.md) §9 sets for itself.

**Looking for the values to type in?** They are not here. This page is the
account plumbing — enrolment, keys, certificates, secrets. Every field of the
listing itself, with the exact text to paste and in the order App Store
Connect asks for it, is
[`APP_STORE_CONNECT_FILL_IN.md`](APP_STORE_CONNECT_FILL_IN.md), generated
from `store/` so it cannot drift from what the pipeline pushes.

Related: [`GO_LIVE.md`](GO_LIVE.md) (all of this as an ordered checklist, with
everything else that has to happen around it) ·
[`RELEASE_PIPELINE.md`](RELEASE_PIPELINE.md) (what the workflows do once this
exists) · [`ASO.md`](ASO.md) (what goes in the listing and why).

---

## 1 · Apple Developer Program

- [ ] Enrol at <https://developer.apple.com/programs/> — 99 USD/year,
      individual or organisation. An organisation needs a D-U-N-S number and
      takes days to weeks; an individual is usually same-day. **The app is
      published under this name** and changing entity type later is a
      migration, not a setting.
- [ ] Accept the **Paid Applications agreement** in App Store Connect →
      Business. A paid app cannot be sold without it, and it is the step most
      often discovered at the end: the app is approved, the listing is
      finished, and the release button is greyed out.
- [ ] Complete **tax forms and banking** in the same place.

**Produces:** the 10-character **Team ID** (Developer portal → Membership).
→ repository secret `APPLE_TEAM_ID`.

---

## 2 · Bundle identifier and app record

- [ ] Developer portal → Certificates, Identifiers & Profiles → Identifiers →
      + → App IDs → App. Description "Airline Empire", Bundle ID **explicit**:
      `com.airlineempire.game`. Capabilities: **none** — the app uses no push,
      no iCloud, no Sign in with Apple, no App Groups, nothing. An unnecessary
      entitlement is a rejection risk and an extra thing that can expire.
- [ ] App Store Connect → Apps → + → New App:
      - Platform **iOS**
      - Name — must be globally unique; if "Airline Empire" is taken, the name
        in `store/metadata/*/name.txt` changes and so does §3 of `ASO.md`
      - Primary language **English (U.S.)**
      - Bundle ID: the one above
      - SKU: `airline-empire-ios` (internal only, never shown, never changed)
      - User access: Full

`com.airlineempire.game` appears in exactly three places and they must agree:
`store/config.json`, `AirlineEmpireApp/project.yml`
(`PRODUCT_BUNDLE_IDENTIFIER`) and `.github/workflows/ios-testflight.yml`
(`BUNDLE_ID`). Change one, change all three.

---

## 3 · App Store Connect API key

This is what lets CI upload builds and push metadata without anyone's Apple ID
password.

- [ ] App Store Connect → Users and Access → Integrations → App Store Connect
      API → **Team Keys** → + . Name "CI — Airline Empire", access **App
      Manager** (Admin also works; Developer does not, it cannot upload).
- [ ] Download the `AuthKey_XXXXXXXXXX.p8`. **Apple allows exactly one
      download.** Lose it and the key is revoked and remade.

**Produces three values**, all repository secrets:

| Secret | Where it comes from |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | the key's ID column, e.g. `ABC123XYZ9` |
| `APP_STORE_CONNECT_ISSUER_ID` | the Issuer ID above the key list — a UUID, shared by every key on the team |
| `APP_STORE_CONNECT_API_KEY_BASE64` | the `.p8` file, base64-encoded (or its text pasted directly — both are accepted) |

```sh
# macOS / Linux
base64 -i AuthKey_ABC123XYZ9.p8 | tr -d '\n' | pbcopy
# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('AuthKey_ABC123XYZ9.p8')) | Set-Clipboard
```

Verify before relying on it — this needs nothing but the three values:

```sh
export APP_STORE_CONNECT_KEY_ID=... APP_STORE_CONNECT_ISSUER_ID=... APP_STORE_CONNECT_API_KEY_BASE64=...
node scripts/asc/preflight.mjs
```

A wrong key id or a `.p8` from a different key produces a bare HTTP 401, which
is exactly what that script exists to translate into a sentence.

---

## 4 · Signing: two ways, and which to pick

A store build needs an **Apple Distribution certificate** and an **App Store
provisioning profile**. Unlike some hosted build services, `xcodebuild` *can*
create both from CI — `-allowProvisioningUpdates` with the API key does it —
so neither path is blocked on owning a Mac.

**Automatic** (set none of the three signing secrets). Simplest, and the right
choice for the first build. The cost: an Apple Developer account holds at most
two Apple Distribution certificates, an ephemeral runner cannot reuse the one
it made last time, and a third request fails until an old one is revoked. Fine
occasionally; a trap as a habit.

**Manual** (preferred once releases are routine). One human export, then every
build is deterministic and nothing is created on Apple's side:

- [ ] Create or reuse an Apple Distribution certificate. From a Mac: Xcode →
      Settings → Accounts → Manage Certificates → + → Apple Distribution.
      Then Keychain Access → export the certificate **with its private key**
      as a `.p12` with a password.
- [ ] Developer portal → Profiles → + → **App Store Connect** distribution →
      App ID `com.airlineempire.game` → the certificate above. Download the
      `.mobileprovision`.

| Secret | Value |
|---|---|
| `IOS_DISTRIBUTION_CERT_P12_BASE64` | `base64 -i dist.p12` |
| `IOS_DISTRIBUTION_CERT_PASSWORD` | the password set during export |
| `IOS_PROVISIONING_PROFILE_BASE64` | `base64 -i profile.mobileprovision` |

The workflow reads the profile's *name* out of the file itself, so there is no
fourth secret to keep in sync. It is all-or-nothing: one or two of the three
set is a misconfiguration, and the preflight job fails on it deliberately
rather than letting `xcodebuild` fail forty minutes later with something
unrelated-looking.

Certificates expire after a year. When one does, every release fails at once —
the fix is this section again, not a debugging session.

---

## 5 · The repository secrets, in full

Settings → Secrets and variables → Actions → New repository secret.

| Secret | Required | Used by |
|---|---|---|
| `APP_STORE_CONNECT_KEY_ID` | yes | preflight, build number, upload, metadata |
| `APP_STORE_CONNECT_ISSUER_ID` | yes | same |
| `APP_STORE_CONNECT_API_KEY_BASE64` | yes | same |
| `APPLE_TEAM_ID` | yes | archive and export |
| `IOS_DISTRIBUTION_CERT_P12_BASE64` | manual signing only | archive |
| `IOS_DISTRIBUTION_CERT_PASSWORD` | manual signing only | archive |
| `IOS_PROVISIONING_PROFILE_BASE64` | manual signing only | archive |

Nothing else is secret. The team id and the key id are identifiers rather than
credentials — Apple's own documentation treats them that way — but they live
with the others so there is one place to look.

**Never commit any of these**, including the `.p8`. `.gitignore` covers
`AuthKey_*.p8`, `*.p12` and `*.mobileprovision` for the accident case; the
workflows write the key outside the workspace and delete it in an `always()`
step.

---

## 6 · App privacy ("nutrition labels")

App Store Connect → App Privacy → Get Started.

- [ ] **"Do you or your third-party partners collect data from this app?"** →
      **No.**

That is the entire questionnaire for this app, and it is true rather than
convenient: there is no network code anywhere in `AirlineEmpireCore` or
`AirlineEmpireApp`, no analytics, no crash reporter, no advertising SDK and no
account. The bundled privacy manifest
(`AirlineEmpireApp/Resources/PrivacyInfo.xcprivacy`) says the same thing in the
form Apple reads mechanically, and `site/privacy.html` says it in prose.

All three must change together, in the same commit as the code, if that ever
stops being true.

---

## 7 · Age rating

App Store Connect → Age Rating → Edit. Every question is **None**:

| Question | Answer | Why |
|---|---|---|
| Cartoon or fantasy violence | None | There is none. Aircraft losses are modelled as financial and reputational events; nothing is depicted. |
| Realistic violence, sexual content, nudity, profanity, horror | None | Not present. |
| Alcohol, tobacco, drug use | None | Not present. |
| Simulated gambling | None | Important, and easy to get wrong: the game has randomness (seeded world events) but no wagering, no loot boxes and no paid randomised rewards. Simulated gambling means a casino, not a probability model. |
| Contests, unrestricted web access, user-generated content | None | No web view, no links out of gameplay, no user content. |

Expected result: **4+**. If the questionnaire returns anything higher,
something was answered wrong — check it rather than accepting it, because the
rating restricts who can be shown the app.

---

## 8 · Export compliance

Already handled in the build:
`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` in
`AirlineEmpireApp/project.yml`. The app makes no network calls and uses no
encryption beyond what Apple exempts, so every upload skips the compliance
questionnaire instead of stopping for a human on each one.

If that key ever disappears from the manifest, the symptom is every TestFlight
build sitting in "Missing Compliance" until someone clicks through a form. The
`processing` job warns when Apple reports the answer as unset.

---

## 9 · TestFlight

- [ ] **Internal testing**: TestFlight → Internal Group → add the App Store
      Connect users who should get builds. Installable within minutes of
      processing, **no Beta App Review**, no metadata required. This is what
      closes the "has anyone ever run this on a phone" question in
      `APPLE_VALIDATION.md`.
- [ ] **External testing** (anyone else): needs **Beta App Review** on the
      first build of each version, plus a description, an email and — if the
      app had accounts, which it does not — a demo login. A reviewer opens the
      app. `store/metadata/review/notes.txt` is written to answer their
      questions before they ask.

A TestFlight build expires **90 days** after upload.

---

## 10 · Pricing and availability

- [ ] App Store Connect → Pricing and Availability → set the price tier and
      the storefronts.

No price is recorded in this repository, deliberately: it is a business
decision with no technical dependency, and writing a number here that nobody
decided would be exactly the invented fact the project's rules forbid. What is
decided, and is a product constraint rather than a pricing one: **one
purchase, no in-app purchases, no ads, no subscription** (`GAME_DESIGN.md`).

---

## 11 · What is still blocking a submission

Independent of everything above, and none of it fixable from a Linux agent
session:

1. **The app has never compiled.** `AirlineEmpireApp` is authored and parsed,
   never built by Xcode (`APPLE_VALIDATION.md`). `.github/workflows/ci.yml`
   answers this on a macOS runner without anyone owning a Mac — it is the
   first thing to run.
2. **No app icon.** `AirlineEmpireApp/Resources/README.md` has the slot and
   the brief; the 1024×1024 does not exist. Validation rejects the upload
   without it.
3. **No screenshots.** They need a simulator and a real mid-game world —
   `ASO.md` §5 is the storyboard.
4. **`REPLACE_ME` in `store/config.json` and `site/support.html`** — the App
   Review contact and the support email. The validator blocks a metadata push
   while they are there, and the Pages workflow refuses to publish the site.
