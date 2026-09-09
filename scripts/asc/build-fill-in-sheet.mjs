#!/usr/bin/env node
// scripts/asc/build-fill-in-sheet.mjs
//
// Generate `docs/APP_STORE_CONNECT_FILL_IN.md`: every field App Store Connect
// asks for, in the order its web UI asks for it, with the exact value to
// paste.
//
// ## Why this is generated rather than written
//
// The listing lives in `store/` (decision D-012) and
// `push-metadata.mjs` deploys it. A hand-written walkthrough repeating the
// same copy would be a second source of truth, and the two would disagree the
// first time a description changed — with the doc being the version a human
// actually pastes. So the sheet is derived from the same files the pusher
// reads, and `--check` fails CI when the committed sheet is stale.
//
// It is not redundant with the API push, either: several things App Store
// Connect will not accept over the API at all — the age-rating questionnaire,
// the privacy answers, pricing, TestFlight beta metadata — and someone has to
// type those. This is that list, with nothing left to look up.
//
// Usage:
//   node scripts/asc/build-fill-in-sheet.mjs            # write the doc
//   node scripts/asc/build-fill-in-sheet.mjs --check    # fail if it is stale

import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { loadStore, LIMITS, PLACEHOLDER } from './lib/metadata.mjs'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
const OUT = join(REPO_ROOT, 'docs', 'APP_STORE_CONNECT_FILL_IN.md')
const check = process.argv.includes('--check')

const store = loadStore(join(REPO_ROOT, 'store'))

/** App Store Connect's own label for each locale directory. */
const LOCALE_LABELS = {
  'en-US': 'English (U.S.)',
  'en-GB': 'English (U.K.)',
  'en-AU': 'English (Australia)',
  'en-CA': 'English (Canada)',
  'de-DE': 'German',
  'fr-FR': 'French',
  'es-ES': 'Spanish (Spain)',
  'es-MX': 'Spanish (Mexico)',
  ja: 'Japanese',
  ko: 'Korean',
  'pt-BR': 'Portuguese (Brazil)',
  'zh-Hans': 'Chinese (Simplified)',
  'zh-Hant': 'Chinese (Traditional)',
  it: 'Italian',
  'nl-NL': 'Dutch',
  sv: 'Swedish',
  da: 'Danish',
  fi: 'Finnish',
  no: 'Norwegian',
}

const out = []
const w = (line = '') => out.push(line)

/** A value with its character budget, in a block that is safe to paste. */
function field(label, value, limitKey) {
  const limit = limitKey ? LIMITS[limitKey] : null
  const count = value == null ? 0 : value.length
  const budget = limit ? ` — ${count}/${limit} characters` : ''
  const needsYou = value != null && value.includes(PLACEHOLDER)

  w(`**${label}**${budget}${needsYou ? '  ⚠️ **you must replace this**' : ''}`)
  w()
  if (value == null || value === '') {
    w('> _(not set — leave the field empty)_')
  } else if (value.includes('\n')) {
    w('```text')
    w(value)
    w('```')
  } else {
    w('```text')
    w(value)
    w('```')
  }
  w()
}

const locales = Object.keys(store.locales).sort((a, b) =>
  a === store.config.primaryLocale ? -1 : b === store.config.primaryLocale ? 1 : a.localeCompare(b),
)
const label = (locale) => LOCALE_LABELS[locale] ?? locale

// ---------------------------------------------------------------------------

w('# App Store Connect — the fill-in sheet')
w()
w('<!-- GENERATED FILE — DO NOT EDIT BY HAND.')
w('     Written by `node scripts/asc/build-fill-in-sheet.mjs` from `store/`,')
w('     which is the single source of truth for the listing (decision D-012).')
w('     Edit the files under store/metadata/, then regenerate. CI fails if this')
w('     file is stale. -->')
w()
w('Everything App Store Connect asks for, in the order its own screens ask for')
w('it, with the exact value to paste. Work top to bottom; nothing here needs')
w('you to open another file.')
w('Read the [handoff status](APP_STORE_HANDOFF_STATUS.md) before submitting:')
w('prepared copy does not confirm live URLs, account setup or a release build.')
w()
w('Three kinds of line appear below:')
w()
w('- **A code block** — paste it verbatim.')
w('- **⚠️ you must replace this** — the value contains `' + PLACEHOLDER + '`, because only')
w('  the Apple account holder can supply it. Fix it in `store/config.json` and')
w('  regenerate this sheet; the release workflow refuses to push a listing that')
w('  still contains one.')
w('- **A decision** — marked _your call_. Nothing in the repository decides it.')
w()
w('Prerequisites (the Apple Developer Program, the API key, the secrets) are in')
w('[`APP_STORE_CONNECT.md`](APP_STORE_CONNECT.md). The whole release, of which')
w('this is one stage, is [`GO_LIVE.md`](GO_LIVE.md).')
w()
w('> **Most of §2 and §5 can be pushed for you** by the *App Store metadata*')
w('> workflow (`plan`, then `apply`), which writes exactly the values below.')
w('> The sections marked **hand-entry only** cannot: App Store Connect does not')
w('> accept them over the API, so they are always typed by a person.')
w()
w('---')
w()

// § 1 ------------------------------------------------------------------------
w('## 1 · Apps → ⊕ → New App')
w()
w('_Once, when the app record is created._')
w()
w('**Platforms** — tick **iOS** only.')
w()
field('Name', store.locales[store.config.primaryLocale]?.name, 'name')
w('> App Store Connect calls this "Name". It must be globally unique across the')
w('> App Store — if it is taken, choose another, change it in')
w('> `store/metadata/*/name.txt`, and regenerate this sheet.')
w()
w(`**Primary Language** — ${label(store.config.primaryLocale)}`)
w()
field('Bundle ID', store.config.bundleId)
w('> Pick the identifier you registered in the Developer portal. It must equal')
w('> this exactly, or the upload lands against no app record.')
w()
field('SKU', store.config.sku ?? 'airline-empire-ios')
w('> Internal only. Never shown to anyone, never change it afterwards.')
w()
w('**User Access** — Full Access.')
w()
w('---')
w()

// § 2 ------------------------------------------------------------------------
w('## 2 · App Information')
w()
w('_Left sidebar → General → App Information._')
w()
w('### Localizable Information')
w()
for (const locale of locales) {
  const fields = store.locales[locale]
  w(`#### ${label(locale)}`)
  w()
  if (locale !== store.config.primaryLocale) {
    w(`_Add this localization first: the language dropdown at the top right of the page → **Add Language** → ${label(locale)}._`)
    w()
  }
  field('Name', fields.name, 'name')
  field('Subtitle', fields.subtitle, 'subtitle')
  field('Privacy Policy URL', fields.privacy_url, 'privacy_url')
}

w('### General Information')
w()
const categories = store.config.categories ?? {}
w(`- **Primary Category** — ${humanCategory(categories.primary)}`)
w(`- **Primary Subcategory 1** — ${humanCategory(categories.primarySubcategoryOne)}`)
w(`- **Primary Subcategory 2** — ${humanCategory(categories.primarySubcategoryTwo)}`)
w(`- **Secondary Category** — ${categories.secondary ? humanCategory(categories.secondary) : 'None'}`)
w()
w('> Why no secondary category: the only honest candidates are other game')
w('> categories, and a second weak category dilutes browse ranking in the first')
w('> rather than adding traffic (`ASO.md` §4).')
w()
w('**Content Rights** — **account-holder declaration; confirm before submission.**')
w('Cities, airports and geography are real. Commercial airlines, aircraft and')
w('manufacturers are fictional. The map uses public-domain Natural Earth data.')
w('Review the bundled asset licences and select the declaration that accurately')
w('covers the submitted build; fictional brands do not make every asset original.')
w()
w('**Age Rating** → Edit. **hand-entry only.** Suggested answers for the current')
w('single-player build are below. Confirm against the actual submitted build.')
w()
w('| Question | Answer |')
w('|---|---|')
w('| Parental Controls / Age Assurance | No / No |')
w('| User-Generated Content / Social Media / Messaging and Chat | No |')
w('| Advertising | No |')
w('| Health or Wellness Topics | No |')
w('| Guns or Other Weapons | None |')
w('| Graphic Sexual Content and Nudity | None |')
w('| Loot Boxes | No |')
w('| Cartoon or Fantasy Violence | None |')
w('| Realistic Violence | None |')
w('| Prolonged Graphic or Sadistic Realistic Violence | None |')
w('| Profanity or Crude Humor | None |')
w('| Mature/Suggestive Themes | None |')
w('| Horror/Fear Themes | None |')
w('| Medical/Treatment Information | None |')
w('| Alcohol, Tobacco, or Drug Use or References | None |')
w('| Simulated Gambling | None |')
w('| Sexual Content or Nudity | None |')
w('| Contests | None |')
w('| Unrestricted Web Access | No |')
w('| Gambling and Contests | No |')
w()
w('Expected general rating: **4+**, subject to Apple’s calculation and regional')
w('rules. Do not change truthful answers to force a target rating. Aircraft')
w('losses are financial events, not depicted violence. Contracts and AI rivals')
w('are single-player mechanics, not contests between users. External legal links')
w('do not provide unrestricted browsing inside the app.')
w('Reference: [Apple age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/), checked 2026-09-09.')
w()
w('---')
w()

// § 3 ------------------------------------------------------------------------
w('## 3 · Pricing and Availability')
w()
w('**hand-entry only.**')
w()
w('- **Price** — **Free**. The app itself is not sold; the three Pro products')
w('  are (`MONETIZATION.md`).')
w('- **Availability** — all countries and regions, unless you have a reason.')
w('- **Pre-Orders** — off, unless you are running a launch campaign.')
w()
w('### The three in-app purchases')
w()
w('Full walkthrough in `docs/MONETIZATION.md` §8. All three are submitted')
w('**with** the version, each needs a display name, a description and a review')
w('screenshot of the paywall, and every identifier below is immutable once')
w('created.')
w()
w('| What | Identifier | Type | Price (US) |')
w('|---|---|---|---|')
w('| Pro Weekly | `com.airlineempire.game.pro.weekly` | Auto-renewable, 1 week | 8.99 |')
w('| Pro Yearly | `com.airlineempire.game.pro.yearly` | Auto-renewable, 1 year | 39.99 |')
w('| Pro Lifetime | `com.airlineempire.game.pro.lifetime` | Non-Consumable | 49.99 |')
w()
w('**Localized purchase text — use for English (U.S.) and English (U.K.).**')
w()
for (const [name, description] of [
  ['Airline Empire Pro Weekly', 'All airports, all eras and unlimited saves.'],
  ['Airline Empire Pro Yearly', 'All airports, all eras and unlimited saves.'],
  ['Airline Empire Pro Lifetime', 'Full Pro access with a one-time purchase.'],
]) {
  if (name.length > 30 || description.length > 45) throw new Error('Purchase copy exceeds Apple limits')
  field('Display name', name)
  field('Description', description)
}
w('**IAP review screenshot:** a separate, genuine capture of the paywall showing')
w('the configured products and prices is still needed. The six marketing images')
w('are not substitutes for this review evidence. Verify products in StoreKit sandbox.')
w()
w('- Subscription group: **`Airline Empire Pro`**, holding the weekly and the')
w('  yearly at the same group level.')
w('- Introductory offer on the **weekly only**: **Pay As You Go, 1 week,')
w('  0.99**. Not pay-up-front — Apple does not offer that duration on a weekly')
w('  subscription, and it is the detail this setup is most often got wrong on.')
w('- One introductory offer per group per Apple Account, ever. That is why the')
w('  yearly carries none.')
w()
w('> Reminder: selling anything needs the **Paid Applications agreement** active')
w('> under Business, plus tax and banking — a free app with in-app purchases')
w('> included. It is the step most often discovered at the end, when the')
w('> products cannot be created.')
w()
w('---')
w()

// § 4 ------------------------------------------------------------------------
w('## 4 · App Privacy')
w()
w('**hand-entry only.** Left sidebar → App Privacy → Get Started.')
w()
w('**"Do you or your third-party partners collect data from this app?"** →')
w('**No**')
w()
w('The current app has no developer-operated analytics, advertising SDK, crash')
w('reporter or game account. Gameplay is local; purchases and restores use Apple')
w('services, and legal/support links open external web pages. Confirm the privacy')
w('declaration against the submitted build, its privacy manifest and public policy.')
w()
field('Privacy Policy URL (asked again here)', store.locales[store.config.primaryLocale]?.privacy_url, 'privacy_url')
w('---')
w()

// § 5 ------------------------------------------------------------------------
w('## 5 · The version page — "iOS App 1.0"')
w()
w('_Left sidebar → the version under **iOS App**. Everything in this section')
w('except the screenshots and the release option is what the metadata workflow')
w('pushes for you._')
w()
for (const locale of locales) {
  const fields = store.locales[locale]
  w(`### ${label(locale)}`)
  w()
  field('Promotional Text', fields.promotional_text, 'promotional_text')
  w('> The only field that can be changed **without submitting a new version**.')
  w('> Keep anything time-bound here and nothing permanent.')
  w()
  field('Description', fields.description, 'description')
  field('Keywords', fields.keywords, 'keywords')
  w('> Comma-separated, **no spaces after the commas** — a space is a character')
  w('> spent on nothing. Hidden from users; this is pure search surface.')
  w()
  field('Support URL', fields.support_url, 'support_url')
  field('Marketing URL', fields.marketing_url, 'marketing_url')
}

w('### Screenshots')
w()
const required = store.config.requiredScreenshotDisplayTypes ?? []
w('| App Store Connect tab | Canvas (px) | Status |')
w('|---|---|---|')
for (const displayType of required) {
  const present = Object.values(store.screenshots).some((sets) => sets[displayType]?.length)
  const canvas = displayType.includes('IPAD') ? '2064 × 2752' : '1320 × 2868'
  const device = displayType.includes('IPAD') ? 'iPad 13"' : 'iPhone 6.9"'
  w(`| ${device} | ${canvas} | ${present ? 'in `store/screenshots/`' : '**missing — blocks submission**'} |`)
}
w('| iPhone 6.5" (additional export) | 1242 × 2688 | six images in `store/screenshots/` |')
w()
w('Portrait, PNG, **no alpha channel**, at most ten per size. The six-shot')
w('storyboard and the captions are `ASO.md` §5; the upload can be done for you')
w('by the metadata workflow with **screenshots** ticked.')
w()
w('### App Review Information')
w()
w('**hand-entry only** for the sign-in question; the rest is pushed.')
w()
w('- **Sign-in required** — **No**. The game has no accounts of any kind.')
w()
const review = store.review ?? {}
w(`- **First Name** — \`${review.contactFirstName ?? ''}\`${flag(review.contactFirstName)}`)
w(`- **Last Name** — \`${review.contactLastName ?? ''}\`${flag(review.contactLastName)}`)
w(`- **Phone Number** — \`${review.contactPhone ?? ''}\`${flag(review.contactPhone)}`)
w(`- **Email** — \`${review.contactEmail ?? ''}\`${flag(review.contactEmail)}`)
w()
field('Notes', review.notes, 'review_notes')
w('- **Attachment** — none needed.')
w()
w('### Version Information')
w()
field('Copyright', store.config.copyright)
w(`- **Routing App Coverage File** — none.`)
w(`- **Version publication** — ${releaseWording(store.config.releaseType)}`)
w('- **Availability** — Pre-order, planned release **16 October 2026**, all 175 currently configured regions. See [release setup](RELEASE_SETUP.md). Version publication and pre-order availability are separate Apple settings.')
w()
w('---')
w()

// § 6 ------------------------------------------------------------------------
w('## 6 · TestFlight')
w()
w('**hand-entry only.** App Store Connect keeps beta metadata on a different')
w('resource from the store listing, so none of this is pushed.')
w()
w('**Internal Testing** needs none of it: add your Apple account to the')
w('internal group and the build is installable minutes after it processes, with')
w('no Beta App Review. Everything below is for **external** testers, where')
w('Apple reviews the first build of each version.')
w()
field('Beta App Description / What to Test', store.review?.testflight)
w(`- **Feedback Email** — \`${review.contactEmail ?? ''}\`${flag(review.contactEmail)}`)
w(`- **Marketing URL** — \`${store.locales[store.config.primaryLocale]?.marketing_url ?? ''}\``)
w(`- **Privacy Policy URL** — \`${store.locales[store.config.primaryLocale]?.privacy_url ?? ''}\``)
w('- **Beta App Review Information** — the same contact and notes as §5.')
w()
w('---')
w()

// § 7 ------------------------------------------------------------------------
w('## 7 · Before you press Submit')
w()
w('- [ ] A build is attached to the version (upload it with the *iOS TestFlight* workflow).')
w('- [ ] You have installed that build from TestFlight and played it on a real device.')
w('- [ ] Screenshots are uploaded for both required sizes.')
w('- [ ] No `' + PLACEHOLDER + '` remains: `node scripts/asc/validate-metadata.mjs` passes without `--allow-placeholders`.')
w('- [ ] `node scripts/asc/check-app-icon.mjs` passes.')
w('- [ ] The support and privacy URLs open in a browser you are not signed into.')
w('- [ ] Age rating shows 4+ and App Privacy shows no data collected.')
w()
w('Then **Add for Review** → **Submit**. With the release option above, an')
w('approved version waits for you to press **Release**.')
w()

const rendered = out.join('\n').replace(/\n{3,}/g, '\n\n')

function humanCategory(id) {
  if (!id) return 'None'
  const names = {
    GAMES: 'Games',
    GAMES_SIMULATION: 'Simulation',
    GAMES_STRATEGY: 'Strategy',
    ENTERTAINMENT: 'Entertainment',
  }
  return names[id] ?? id
}

function releaseWording(releaseType) {
  if (releaseType === 'MANUAL') return '**Manually release this version** — after approval, publish the pre-order only once every target region is configured correctly. The app downloads on its pre-order release date.'
  if (releaseType === 'AFTER_APPROVAL') return 'Automatically release this version as soon as it is approved.'
  if (releaseType === 'SCHEDULED') return 'Automatically release after a date you set.'
  return String(releaseType)
}

function flag(value) {
  return value && String(value).includes(PLACEHOLDER) ? '  ⚠️ **you must replace this**' : ''
}

if (check) {
  const current = existsSync(OUT) ? readFileSync(OUT, 'utf8') : null
  if (current !== rendered) {
    console.error('✗ docs/APP_STORE_CONNECT_FILL_IN.md is stale.')
    console.error('  The listing in store/ has changed since it was generated.')
    console.error('  Run: node scripts/asc/build-fill-in-sheet.mjs')
    process.exit(1)
  }
  console.log('✓ The fill-in sheet matches store/.')
} else {
  writeFileSync(OUT, rendered)
  console.log(`✓ Wrote ${OUT}`)
}
