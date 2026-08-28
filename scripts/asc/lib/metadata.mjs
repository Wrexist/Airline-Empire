// scripts/asc/lib/metadata.mjs
//
// The store listing, read off disk and checked before Apple ever sees it.
//
// ## Why the listing is a directory of files
//
// Same argument the simulation makes for `Resources/*.json`: content is data.
// A store listing is content — it is reviewed, versioned, diffed and rolled
// back exactly like a balance table, and the one place it must NOT live is a
// textarea in a web form that nothing can review and no history can explain.
// So `store/` is the source of truth and App Store Connect is a deployment
// target, which is what makes `push-metadata.mjs --apply` a deploy rather than
// an edit.
//
// The directory shape deliberately matches fastlane `deliver`'s
// (`metadata/<locale>/<field>.txt`), even though nothing here uses fastlane.
// It is the layout every iOS engineer already recognises, and it keeps the
// door open to swapping this tooling for `deliver` later without moving a
// single word of copy.
//
// ## What the checks are for
//
// Every field below has a hard limit that App Store Connect enforces at save
// time, and hitting one at submission is the expensive way to find out: the
// copy is already written, the release is already scheduled, and the person
// fixing it is counting characters by hand. `validate-metadata.mjs` runs this
// on every pull request, needs no secrets and no network, and fails in
// seconds.
//
// Limits verified 2026-08-28 against Apple's own reference:
//   https://developer.apple.com/help/app-store-connect/reference/app-information/
//   https://developer.apple.com/help/app-store-connect/reference/app-store-localized-version-information/
// They change. Re-verify before a release rather than trusting this comment —
// the same rule the repo applies to any other sourced number.

import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs'
import { join, basename, extname } from 'node:path'

/** Field name → maximum characters App Store Connect accepts. */
export const LIMITS = {
  name: 30,
  subtitle: 30,
  keywords: 100,
  promotional_text: 170,
  description: 4000,
  release_notes: 4000,
  support_url: 255,
  marketing_url: 255,
  privacy_url: 255,
  review_notes: 4000,
}

/** Files read per locale. `required` ones fail the build when absent. */
export const LOCALIZED_FIELDS = [
  { file: 'name.txt', key: 'name', required: true, target: 'appInfo' },
  { file: 'subtitle.txt', key: 'subtitle', required: true, target: 'appInfo' },
  { file: 'privacy_url.txt', key: 'privacy_url', required: true, target: 'appInfo' },
  { file: 'description.txt', key: 'description', required: true, target: 'version' },
  { file: 'keywords.txt', key: 'keywords', required: true, target: 'version' },
  { file: 'promotional_text.txt', key: 'promotional_text', required: false, target: 'version' },
  { file: 'release_notes.txt', key: 'release_notes', required: false, target: 'version' },
  { file: 'support_url.txt', key: 'support_url', required: true, target: 'version' },
  { file: 'marketing_url.txt', key: 'marketing_url', required: false, target: 'version' },
]

/**
 * App Store locale codes this repository is willing to publish.
 *
 * Not Apple's full list — deliberately. A typo like `en_US` or `en` creates a
 * directory that silently publishes nowhere, and an unrecognised code here is
 * far more likely to be that than a locale someone meant to add. Adding one is
 * a one-line change made on purpose; see docs/ASO.md §"Localisation" for why
 * the list is short today.
 */
export const KNOWN_LOCALES = new Set([
  'en-US',
  'en-GB',
  'en-AU',
  'en-CA',
  'de-DE',
  'fr-FR',
  'es-ES',
  'es-MX',
  'it',
  'nl-NL',
  'pt-BR',
  'sv',
  'da',
  'fi',
  'no',
  'ja',
  'ko',
  'zh-Hans',
  'zh-Hant',
])

/**
 * Screenshot canvas sizes, in device pixels, per App Store Connect display type.
 *
 * The directory name IS the App Store Connect `screenshotDisplayType` enum
 * value, passed to the API verbatim. That is not laziness: the enum is Apple's
 * and it changes when Apple ships a new screen size, so any mapping table
 * maintained here would be a second, staler copy of it. A wrong display type
 * is an upload that fails loudly; a wrong *mapping* is an upload that succeeds
 * into the wrong slot.
 *
 * Sizes verified 2026-08-07 against
 * https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/
 * (carried over from Wrexist/WorldQuest's `scripts/build-store-shots.cjs`,
 * which read them off that page on that date). Apple revises the required
 * sizes most years and a guessed pixel dimension is a rejected submission, so
 * treat this table like a sourced fact with a `verifiedAt`: re-read the page
 * before the first submission.
 *
 * TODO(verify): the enum spelling for the 6.9" iPhone and 13" iPad slots has
 * NOT been confirmed against a live API response from this repository. Both
 * sizes below are accepted in the slots Apple currently labels "iPhone 6.9-inch
 * display" and "iPad 13-inch display"; the enum values those map to are what
 * `store/config.json` names, and `upload-screenshots.mjs` prints Apple's own
 * accepted values when a POST is rejected. Confirm from a real run before
 * relying on the names.
 */
export const SCREENSHOT_SIZES = {
  APP_IPHONE_67: [
    { width: 1320, height: 2868 }, // 6.9" portrait
    { width: 2868, height: 1320 }, // 6.9" landscape
    { width: 1290, height: 2796 }, // 6.7" portrait
    { width: 2796, height: 1290 },
  ],
  APP_IPAD_PRO_3GEN_129: [
    { width: 2064, height: 2752 }, // 13" portrait
    { width: 2752, height: 2064 }, // 13" landscape
    { width: 2048, height: 2732 }, // 12.9" portrait
    { width: 2732, height: 2048 },
  ],
}

/** Marks a value only a human with the Apple Developer account can fill in. */
export const PLACEHOLDER = 'REPLACE_ME'

/** Apple allows at most ten screenshots per display type per locale. */
export const MAX_SCREENSHOTS_PER_SET = 10

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

function readText(path) {
  // Trailing newline is an artefact of the file, never of the copy: a text
  // editor adds one and Apple would count it against the character limit.
  return readFileSync(path, 'utf8').replace(/\r\n/g, '\n').replace(/\n+$/, '')
}

/**
 * Read `store/` into one object.
 *
 * Pure: no network, no environment, no side effects. Everything that talks to
 * Apple takes this as input, which is what lets the validator and the pusher
 * agree by construction rather than by convention.
 */
export function loadStore(root) {
  const configPath = join(root, 'config.json')
  if (!existsSync(configPath)) throw new Error(`No config.json in ${root}`)
  const config = JSON.parse(readFileSync(configPath, 'utf8'))

  const metadataRoot = join(root, 'metadata')
  const locales = {}
  if (existsSync(metadataRoot)) {
    for (const entry of readdirSync(metadataRoot).sort()) {
      const localeDir = join(metadataRoot, entry)
      if (!statSync(localeDir).isDirectory()) continue
      if (entry === 'review') continue // not a locale — handled below
      const fields = {}
      for (const field of LOCALIZED_FIELDS) {
        const path = join(localeDir, field.file)
        if (existsSync(path)) fields[field.key] = readText(path)
      }
      locales[entry] = fields
    }
  }

  const reviewNotesPath = join(metadataRoot, 'review', 'notes.txt')
  const review = {
    ...(config.review ?? {}),
    notes: existsSync(reviewNotesPath) ? readText(reviewNotesPath) : null,
  }

  return { root, config, locales, review, screenshots: loadScreenshots(join(root, 'screenshots')) }
}

/** `screenshots/<locale>/<DISPLAY_TYPE>/NN-name.png`, ordered by filename. */
export function loadScreenshots(screenshotRoot) {
  const byLocale = {}
  if (!existsSync(screenshotRoot)) return byLocale
  for (const locale of readdirSync(screenshotRoot).sort()) {
    const localeDir = join(screenshotRoot, locale)
    if (!statSync(localeDir).isDirectory()) continue
    const sets = {}
    for (const displayType of readdirSync(localeDir).sort()) {
      const setDir = join(localeDir, displayType)
      if (!statSync(setDir).isDirectory()) continue
      const files = readdirSync(setDir)
        .filter((f) => ['.png', '.jpg', '.jpeg'].includes(extname(f).toLowerCase()))
        .sort()
        .map((f) => join(setDir, f))
      if (files.length) sets[displayType] = files
    }
    if (Object.keys(sets).length) byLocale[locale] = sets
  }
  return byLocale
}

// ---------------------------------------------------------------------------
// PNG inspection — enough of the format to answer the two questions Apple asks
// ---------------------------------------------------------------------------

/**
 * Width, height and whether the image carries an alpha channel.
 *
 * Reads the IHDR chunk directly rather than pulling in an image library: the
 * first 33 bytes of a PNG are a fixed layout, and this is one of the few
 * places where hand-parsing a format is less risk than a dependency.
 *
 * Alpha matters because App Store Connect rejects screenshots and icons that
 * have it — the failure arrives at upload time with a message about
 * transparency, long after the screenshot pipeline that produced it has been
 * forgotten.
 */
export function inspectPng(path) {
  const buffer = readFileSync(path)
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
  if (buffer.length < 33 || !buffer.subarray(0, 8).equals(signature)) return null
  if (buffer.subarray(12, 16).toString('ascii') !== 'IHDR') return null
  const colorType = buffer.readUInt8(25)
  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20),
    // Colour types 4 (greyscale+alpha) and 6 (truecolour+alpha) carry alpha.
    hasAlpha: colorType === 4 || colorType === 6,
    bytes: buffer.length,
  }
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/**
 * Words that cost keyword characters and buy nothing.
 *
 * Apple already indexes the app name, the subtitle, the developer name and the
 * category, so repeating any of them in the 100-character keyword field spends
 * characters on terms that were already covered. These are warnings, not
 * errors: the rule is well established but it is a ranking heuristic, not a
 * documented API constraint, and this file does not fail a release over
 * something it cannot prove.
 */
const WASTED_KEYWORD_TERMS = new Set(['app', 'apps', 'ios', 'iphone', 'ipad', 'free', 'best', 'top', 'new', 'game', 'games'])

/**
 * Third-party marks that must not appear anywhere in the listing.
 *
 * Guideline 5.2 territory: naming another company's product in metadata is a
 * routine metadata rejection, and this game's world is entirely fictional —
 * its aircraft are Nordavia and Kestrel, its airports invented — so there is
 * never a legitimate reason for a real manufacturer or airline to appear in
 * the copy. An error, not a warning: this one is cheap to be strict about, and
 * "our Boeing 737 equivalent" is exactly the sentence a well-meaning editor
 * adds to a description.
 */
const FORBIDDEN_TRADEMARKS = [
  'boeing',
  'airbus',
  'embraer',
  'bombardier',
  'lufthansa',
  'ryanair',
  'emirates',
  'delta air',
  'united airlines',
  'american airlines',
]

/**
 * Apple's own marks: fine in the description, wrong in the indexed fields.
 *
 * "iPhone and iPad" in a description is normal, permitted and useful — it is
 * how you say which devices you support. In the name, subtitle or keywords it
 * is a different thing: Apple rejects platform names in app names, and in the
 * 100-character keyword field the platform is already implied, so the
 * characters buy nothing. Hence the split — the first version of this check
 * flagged the description's "iPhone and iPad" line, which was the check being
 * wrong rather than the copy.
 */
const APPLE_MARKS = ['apple', 'app store', 'ios', 'iphone', 'ipad', 'ipados', 'appstore']
const INDEXED_FIELDS = new Set(['name', 'subtitle', 'keywords', 'promotional_text'])

/** Whole-word match, so "ios" does not fire inside "scenarios". */
function mentions(haystackLower, mark) {
  const escaped = mark.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  return new RegExp(`(^|[^a-z0-9])${escaped}([^a-z0-9]|$)`).test(haystackLower)
}

const URL_FIELDS = ['support_url', 'marketing_url', 'privacy_url']

/**
 * Everything wrong with the listing, split into what blocks a release and what
 * only deserves an argument.
 *
 * Returns `{ errors, warnings }` — arrays of strings, each naming the locale
 * and field so a CI log line is actionable without opening the tree.
 */
export function validateStore(store, { allowPlaceholders = false } = {}) {
  const errors = []
  const warnings = []
  const error = (message) => errors.push(message)
  const warn = (message) => warnings.push(message)
  // A value only the Apple Developer account holder can supply — the review
  // contact, the copyright entity. The tree is complete and reviewable with
  // these still in it, and a submission with one in it would be a rejection,
  // so CI passes `allowPlaceholders` on a pull request and the release
  // workflow does not. That asymmetry is the whole design: green CI today,
  // a hard gate at the only moment it matters.
  const placeholder = (message) => (allowPlaceholders ? warn(`${message} (placeholder allowed here)`) : error(message))

  const config = store.config ?? {}
  if (!config.bundleId) error('config.json: bundleId is required (it is how the app record is found).')
  if (!config.platform) error('config.json: platform is required (e.g. "IOS").')
  if (!config.primaryLocale) error('config.json: primaryLocale is required.')
  else if (!store.locales[config.primaryLocale]) {
    error(`config.json: primaryLocale "${config.primaryLocale}" has no directory under store/metadata/.`)
  }

  const locales = Object.keys(store.locales)
  if (!locales.length) error('store/metadata contains no locale directories.')

  for (const locale of locales) {
    if (!KNOWN_LOCALES.has(locale)) {
      error(`store/metadata/${locale}: not an App Store locale code this repo knows. Typo, or add it to KNOWN_LOCALES.`)
    }
    const fields = store.locales[locale]

    for (const field of LOCALIZED_FIELDS) {
      const value = fields[field.key]
      if (value === undefined || value === '') {
        if (field.required) error(`${locale}/${field.file}: required and ${value === '' ? 'empty' : 'missing'}.`)
        continue
      }

      const limit = LIMITS[field.key]
      if (limit && value.length > limit) {
        error(`${locale}/${field.file}: ${value.length} characters, limit ${limit}.`)
      }
      if (value !== value.trim()) {
        error(`${locale}/${field.file}: leading or trailing whitespace — it counts against the limit and renders.`)
      }
      if (hasControlCharacters(value)) {
        error(`${locale}/${field.file}: contains control characters — they survive a copy-paste and break the API payload.`)
      }
      if (value.includes(PLACEHOLDER)) {
        placeholder(`${locale}/${field.file}: still contains ${PLACEHOLDER}.`)
      }
      if (value.includes('TODO')) {
        error(`${locale}/${field.file}: still contains a TODO. Placeholder copy must never reach the store.`)
      }

      const lower = value.toLowerCase()
      for (const mark of FORBIDDEN_TRADEMARKS) {
        if (mentions(lower, mark)) {
          error(`${locale}/${field.file}: names "${mark}". Third-party marks in metadata are a guideline 5.2 rejection.`)
        }
      }
      if (INDEXED_FIELDS.has(field.key)) {
        for (const mark of APPLE_MARKS) {
          if (mentions(lower, mark)) {
            error(`${locale}/${field.file}: names "${mark}". Apple's own marks do not belong in an indexed field.`)
          }
        }
      }
    }

    // Name and subtitle are the two highest-weighted indexed fields; emoji in
    // either is a common metadata rejection and neither can contain a newline.
    for (const key of ['name', 'subtitle']) {
      const value = fields[key]
      if (!value) continue
      if (value.includes('\n')) error(`${locale}/${key}.txt: contains a line break.`)
      if (/\p{Extended_Pictographic}/u.test(value)) {
        warn(`${locale}/${key}.txt: contains an emoji. App Review routinely rejects emoji in the name and subtitle.`)
      }
    }

    validateKeywords(locale, fields, { error, warn })
    validateDescription(locale, fields, { warn })

    for (const key of URL_FIELDS) {
      const value = fields[key]
      if (!value) continue
      let url
      try {
        url = new URL(value)
      } catch {
        error(`${locale}/${key}.txt: "${value}" is not a URL.`)
        continue
      }
      if (url.protocol !== 'https:') error(`${locale}/${key}.txt: must be https.`)
      if (value.includes(' ')) error(`${locale}/${key}.txt: contains a space.`)
    }
  }

  validateReview(store, { error, warn, placeholder })
  validateScreenshots(store, { error, warn })

  return { errors, warnings }
}

/** Any C0/C1 control character other than the newline a description may contain. */
function hasControlCharacters(value) {
  for (const char of value) {
    const code = char.codePointAt(0)
    if (char === '\n') continue
    if (code < 0x20 || (code >= 0x7f && code <= 0x9f)) return true
  }
  return false
}

function validateKeywords(locale, fields, { error, warn }) {
  const raw = fields.keywords
  if (!raw) return

  if (/,\s/.test(raw)) {
    error(`${locale}/keywords.txt: a space after a comma is a wasted character. Use "a,b,c".`)
  }
  const terms = raw
    .split(',')
    .map((term) => term.trim())
    .filter(Boolean)

  const seen = new Set()
  for (const term of terms) {
    const key = term.toLowerCase()
    if (seen.has(key)) error(`${locale}/keywords.txt: "${term}" appears twice.`)
    seen.add(key)
    if (WASTED_KEYWORD_TERMS.has(key)) {
      warn(`${locale}/keywords.txt: "${term}" is already indexed from the category or platform — spend the characters elsewhere.`)
    }
  }

  // Apple indexes the name and subtitle, so a word present in either is
  // already covered and repeating it costs characters for nothing.
  const indexedElsewhere = `${fields.name ?? ''} ${fields.subtitle ?? ''}`
    .toLowerCase()
    .split(/[^a-z0-9']+/)
    .filter((word) => word.length > 2)
  for (const term of terms) {
    if (indexedElsewhere.includes(term.toLowerCase())) {
      warn(`${locale}/keywords.txt: "${term}" already appears in the name or subtitle, which Apple indexes.`)
    }
  }

  const used = raw.length
  const remaining = LIMITS.keywords - used
  if (remaining > 10) {
    warn(`${locale}/keywords.txt: ${remaining} of ${LIMITS.keywords} characters unused. The field is free ranking surface — fill it.`)
  }
}

function validateDescription(locale, fields, { warn }) {
  const description = fields.description
  if (!description) return

  // The store shows roughly the first three lines before "more"; a description
  // whose first paragraph is one long block gets truncated mid-sentence.
  const firstParagraph = description.split('\n\n')[0]
  if (firstParagraph.length > 300) {
    warn(`${locale}/description.txt: the first paragraph is ${firstParagraph.length} characters. Only ~170 show before "more".`)
  }
  if (/https?:\/\//.test(description)) {
    warn(`${locale}/description.txt: contains a URL. Links are not clickable in the description; use the marketing URL field.`)
  }
  if (/\b(free|sale|discount|limited time)\b/i.test(description)) {
    warn(`${locale}/description.txt: mentions price or promotion. Prices change and Apple rejects price claims in metadata.`)
  }
}

function validateReview(store, { error, warn, placeholder }) {
  const review = store.review ?? {}
  if (!review.notes) {
    warn('store/metadata/review/notes.txt is missing. Review notes are how a reviewer learns the game is offline and needs no account.')
  } else if (review.notes.length > LIMITS.review_notes) {
    error(`store/metadata/review/notes.txt: ${review.notes.length} characters, limit ${LIMITS.review_notes}.`)
  }
  for (const key of ['contactFirstName', 'contactLastName', 'contactEmail', 'contactPhone']) {
    if (!review[key]) error(`config.json review.${key} is required — App Review will not accept a version without a contact.`)
    else if (String(review[key]).includes(PLACEHOLDER)) placeholder(`config.json review.${key} is still ${PLACEHOLDER}.`)
  }
  if (String(store.config?.copyright ?? '').includes(PLACEHOLDER)) {
    placeholder(`config.json copyright is still ${PLACEHOLDER} — it must name the legal entity on the App Store Connect account.`)
  }
  if (review.demoAccountRequired) {
    warn('config.json says a demo account is required. This game has no accounts; that is almost certainly wrong.')
  }
}

function validateScreenshots(store, { error, warn }) {
  const required = store.config?.requiredScreenshotDisplayTypes ?? []
  const locales = Object.keys(store.screenshots)

  if (!locales.length) {
    warn('store/screenshots is empty. Apple requires at least one screenshot per required display type before submission.')
    return
  }

  for (const locale of locales) {
    if (!store.locales[locale]) {
      error(`store/screenshots/${locale}: no matching metadata locale.`)
    }
    const sets = store.screenshots[locale]
    for (const displayType of Object.keys(sets)) {
      const files = sets[displayType]
      const sizes = SCREENSHOT_SIZES[displayType]
      if (!sizes) {
        warn(`${locale}/${displayType}: unknown display type — sizes cannot be checked here, only by Apple at upload.`)
      }
      if (files.length > MAX_SCREENSHOTS_PER_SET) {
        error(`${locale}/${displayType}: ${files.length} screenshots, Apple accepts at most ${MAX_SCREENSHOTS_PER_SET}.`)
      }
      // Three is where a gallery stops looking like a placeholder. Apple
      // requires one; a listing with one is a listing nobody finished.
      if (files.length < 3) {
        warn(`${locale}/${displayType}: only ${files.length} screenshot(s). The storyboard in docs/ASO.md §5 is six.`)
      }
      for (const file of files) {
        if (extname(file).toLowerCase() !== '.png') continue // JPEG is legal; only PNG is inspectable here.
        const png = inspectPng(file)
        if (!png) {
          error(`${basename(file)}: not a readable PNG.`)
          continue
        }
        if (png.hasAlpha) {
          error(`${basename(file)}: has an alpha channel. App Store Connect rejects transparency in screenshots.`)
        }
        if (sizes && !sizes.some((size) => size.width === png.width && size.height === png.height)) {
          const allowed = sizes.map((s) => `${s.width}×${s.height}`).join(', ')
          error(`${basename(file)}: ${png.width}×${png.height} is not a ${displayType} size (${allowed}).`)
        }
      }
    }
    for (const displayType of required) {
      if (!sets[displayType]) error(`${locale}: no screenshots for required display type ${displayType}.`)
    }
  }

  const primary = store.config?.primaryLocale
  if (primary && !store.screenshots[primary]) {
    warn(`No screenshots for the primary locale ${primary}. Other locales fall back to it, so this is the set that matters most.`)
  }
}

// ---------------------------------------------------------------------------
// Cross-file consistency
// ---------------------------------------------------------------------------

/**
 * The bundle identifier is written down in three places. Do they agree?
 *
 * `store/config.json` is what finds the app record, `project.yml` is what the
 * binary is stamped with, and the release workflow's `BUNDLE_ID` is what the
 * export options hand to the signing profile. A disagreement between any two
 * of them fails late and confusingly: the archive succeeds, the export picks
 * the wrong profile, or the upload lands against no app record at all.
 *
 * Read with regular expressions rather than a YAML parser on purpose — a YAML
 * parser is a dependency, and this needs one line out of each file. If the
 * pattern stops matching, the check reports that it could not read the value
 * rather than silently passing.
 */
export function checkBundleIdConsistency(repoRoot, expected) {
  const sources = [
    {
      path: join(repoRoot, 'AirlineEmpireApp', 'project.yml'),
      label: 'AirlineEmpireApp/project.yml PRODUCT_BUNDLE_IDENTIFIER',
      pattern: /^\s*PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)\s*$/m,
    },
    {
      path: join(repoRoot, '.github', 'workflows', 'ios-testflight.yml'),
      label: '.github/workflows/ios-testflight.yml BUNDLE_ID',
      pattern: /^\s*BUNDLE_ID:\s*(\S+)\s*$/m,
    },
  ]

  const errors = []
  for (const source of sources) {
    if (!existsSync(source.path)) {
      errors.push(`${source.label}: file not found at ${source.path}.`)
      continue
    }
    const match = readFileSync(source.path, 'utf8').match(source.pattern)
    if (!match) {
      errors.push(`${source.label}: could not find the value. The check cannot confirm the bundle id.`)
      continue
    }
    const found = match[1].replace(/^["']|["']$/g, '')
    if (found !== expected) {
      errors.push(`${source.label} is "${found}" but store/config.json says "${expected}". They must match exactly.`)
    }
  }
  return errors
}

/**
 * Is there an app icon, and is it one Apple will accept?
 *
 * This is the single most likely reason a first upload is rejected, and the
 * rejection arrives at the *end*: after the 10x-billed archive, after the
 * export, after the transfer, as an email about a missing marketing icon. Two
 * seconds here on the cheap runner buys that whole cycle back.
 *
 * Checks, in order of how often each one bites:
 *   · the asset catalogue names a file at all
 *   · the file exists on disk
 *   · it is 1024×1024
 *   · it has no alpha channel — Apple rejects transparency in the app icon,
 *     and the usual symptom is a black square where the rounded corners were
 *
 * Returns an array of problems; empty means the icon is submittable. Missing
 * entirely is reported as a problem rather than thrown, because the caller
 * decides whether that blocks (an upload) or merely warns (a pull request).
 */
export function checkAppIcon(repoRoot) {
  const setDir = join(repoRoot, 'AirlineEmpireApp', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset')
  const contentsPath = join(setDir, 'Contents.json')
  if (!existsSync(contentsPath)) {
    return [`No app icon set at ${contentsPath}.`]
  }

  let contents
  try {
    contents = JSON.parse(readFileSync(contentsPath, 'utf8'))
  } catch (cause) {
    return [`${contentsPath} is not valid JSON: ${cause.message}`]
  }

  const named = (contents.images ?? []).filter((image) => image.filename)
  if (!named.length) {
    return [
      'The app icon slot is empty — no image in AppIcon.appiconset names a file.',
      'Apple rejects an upload without one. The brief is in AirlineEmpireApp/Resources/README.md.',
    ]
  }

  const problems = []
  for (const image of named) {
    const file = join(setDir, image.filename)
    if (!existsSync(file)) {
      problems.push(`AppIcon references ${image.filename}, which is not in the asset catalogue.`)
      continue
    }
    const png = inspectPng(file)
    if (!png) {
      problems.push(`${image.filename} is not a readable PNG.`)
      continue
    }
    if (png.hasAlpha) {
      problems.push(`${image.filename} has an alpha channel. Apple rejects transparency in the app icon.`)
    }
    if (png.width !== 1024 || png.height !== 1024) {
      problems.push(`${image.filename} is ${png.width}×${png.height}; the app icon must be 1024×1024.`)
    }
  }
  return problems
}

