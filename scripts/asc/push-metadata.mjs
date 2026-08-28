#!/usr/bin/env node
// scripts/asc/push-metadata.mjs
//
// Deploy `store/` to App Store Connect. Dry run by default.
//
// ## The shape of it
//
//   store/metadata/<locale>/name.txt            → appInfoLocalizations.name
//                           subtitle.txt        → appInfoLocalizations.subtitle
//                           privacy_url.txt     → appInfoLocalizations.privacyPolicyUrl
//                           description.txt     → appStoreVersionLocalizations.description
//                           keywords.txt        → appStoreVersionLocalizations.keywords
//                           promotional_text.txt→ appStoreVersionLocalizations.promotionalText
//                           release_notes.txt   → appStoreVersionLocalizations.whatsNew
//                           support_url.txt     → appStoreVersionLocalizations.supportUrl
//                           marketing_url.txt   → appStoreVersionLocalizations.marketingUrl
//   store/metadata/review/notes.txt             → appStoreReviewDetail.notes
//   store/config.json  categories               → appInfos relationships
//                      copyright, releaseType   → appStoreVersions attributes
//
// Screenshots are a separate script (`upload-screenshots.mjs`): they are a
// multi-step reservation-and-commit protocol rather than a field, and mixing
// them in here would mean a text change could not be deployed without an
// image upload.
//
// ## Why dry run is the default
//
// This writes to a public-facing product page. `--apply` is the opt-in, the
// dry run prints the exact before/after for every field it would change, and
// the workflow that calls it requires a typed confirmation. Nothing here
// deletes: a locale present in App Store Connect but absent from `store/` is
// reported and left alone, because "the tree is the source of truth" is a good
// rule right up until a half-finished checkout wipes a listing.
//
// Usage:
//   node scripts/asc/push-metadata.mjs --version 1.0.0
//   node scripts/asc/push-metadata.mjs --version 1.0.0 --apply
//
// NEVER EXECUTED against Apple from this repository — see docs/RELEASE_PIPELINE.md.

import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { AppStoreConnect, findApp, versionState, EDITABLE_VERSION_STATES } from './lib/asc.mjs'
import { loadStore, validateStore } from './lib/metadata.mjs'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
const args = process.argv.slice(2)
const apply = args.includes('--apply')
const versionIndex = args.indexOf('--version')
const versionString = versionIndex === -1 ? null : args[versionIndex + 1]

if (!versionString || !/^\d+\.\d+(\.\d+)?$/.test(versionString)) {
  console.error('Usage: node scripts/asc/push-metadata.mjs --version <MAJOR.MINOR.PATCH> [--apply]')
  process.exit(2)
}

const store = loadStore(join(REPO_ROOT, 'store'))
const { errors, warnings } = validateStore(store)
for (const warning of warnings) console.warn(`⚠︎ ${warning}`)
if (errors.length) {
  for (const error of errors) console.error(`✗ ${error}`)
  console.error('\nRefusing to push an invalid listing. Fix the errors above first.')
  process.exit(1)
}

const client = AppStoreConnect.fromEnv()
const changes = []
const label = apply ? 'apply' : 'dry-run'

/** One line in the plan, and — when applying — the request that performs it. */
async function change(what, detail, perform) {
  changes.push({ what, detail })
  console.log(`  ${apply ? '→' : '·'} ${what}: ${detail}`)
  if (apply) await perform()
}

/** Before/after for a set of fields, ignoring the ones that already match. */
function diffAttributes(current, desired) {
  const delta = {}
  for (const [key, value] of Object.entries(desired)) {
    if (value === undefined) continue
    if ((current?.[key] ?? null) !== (value ?? null)) delta[key] = value
  }
  return delta
}

function summarize(value) {
  if (value === null || value === undefined) return '—'
  const text = String(value).replace(/\n/g, '⏎')
  return text.length > 72 ? `${text.slice(0, 69)}…` : text
}

const app = await findApp(client, store.config.bundleId)
if (!app) {
  console.error(`✗ No App Store Connect app record for ${store.config.bundleId}.`)
  console.error('  Create it first: App Store Connect → Apps → + → New App (docs/APP_STORE_CONNECT.md §2).')
  process.exit(1)
}
console.log(`App: ${app.attributes?.name} (${app.id}) — ${label}\n`)

// ---------------------------------------------------------------------------
// 1 · App information: name, subtitle, privacy policy URL, categories
// ---------------------------------------------------------------------------
//
// `appInfos` is the app-level record, and there are usually two: the live one
// and the editable one. Only the editable one accepts writes — patching the
// live one fails with a 409 that reads like a bug here.

console.log('App information')
const appInfos = await client.getAll(`/v1/apps/${app.id}/appInfos?limit=10`)
const editableAppInfo =
  appInfos.find((info) => (info.attributes?.state ?? info.attributes?.appStoreState) !== 'READY_FOR_DISTRIBUTION') ??
  appInfos[0]
if (!editableAppInfo) {
  console.error('✗ The app has no appInfo record. That should be impossible; check the API response by hand.')
  process.exit(1)
}

const categories = store.config.categories ?? {}
const categoryRelationships = {}
const relate = (key, id) => {
  if (id === undefined) return
  categoryRelationships[key] = { data: id === null ? null : { type: 'appCategories', id } }
}
relate('primaryCategory', categories.primary)
relate('primarySubcategoryOne', categories.primarySubcategoryOne)
relate('primarySubcategoryTwo', categories.primarySubcategoryTwo)
relate('secondaryCategory', categories.secondary)

if (Object.keys(categoryRelationships).length) {
  // Categories are relationships, not attributes, so there is nothing cheap to
  // diff against without a second round trip per category; this is idempotent,
  // so it is simply set every time.
  await change('categories', Object.values(categories).filter(Boolean).join(' / '), () =>
    client.patch(`/v1/appInfos/${editableAppInfo.id}`, {
      data: { type: 'appInfos', id: editableAppInfo.id, relationships: categoryRelationships },
    }),
  )
}

const appInfoLocalizations = await client.getAll(`/v1/appInfos/${editableAppInfo.id}/appInfoLocalizations?limit=50`)
const appInfoByLocale = new Map(appInfoLocalizations.map((item) => [item.attributes?.locale, item]))

for (const [locale, fields] of Object.entries(store.locales)) {
  const desired = {
    name: fields.name,
    subtitle: fields.subtitle,
    privacyPolicyUrl: fields.privacy_url,
  }
  const existing = appInfoByLocale.get(locale)

  if (!existing) {
    await change(`${locale} app info`, `create (${summarize(desired.name)})`, () =>
      client.post('/v1/appInfoLocalizations', {
        data: {
          type: 'appInfoLocalizations',
          attributes: { locale, ...desired },
          relationships: { appInfo: { data: { type: 'appInfos', id: editableAppInfo.id } } },
        },
      }),
    )
    continue
  }

  const delta = diffAttributes(existing.attributes, desired)
  for (const [key, value] of Object.entries(delta)) {
    console.log(`      ${key}: ${summarize(existing.attributes?.[key])} → ${summarize(value)}`)
  }
  if (Object.keys(delta).length) {
    await change(`${locale} app info`, Object.keys(delta).join(', '), () =>
      client.patch(`/v1/appInfoLocalizations/${existing.id}`, {
        data: { type: 'appInfoLocalizations', id: existing.id, attributes: delta },
      }),
    )
  }
}

for (const locale of appInfoByLocale.keys()) {
  if (locale && !store.locales[locale]) {
    console.warn(`  ⚠︎ ${locale} exists in App Store Connect but not in store/. Left alone — nothing here deletes.`)
  }
}

// ---------------------------------------------------------------------------
// 2 · The version: copyright, release type, and the localized listing
// ---------------------------------------------------------------------------

console.log('\nVersion')
const versions = await client.getAll(
  `/v1/appStoreVersions?filter[app]=${app.id}&limit=50&fields[appStoreVersions]=versionString,appVersionState,appStoreState,platform,copyright,releaseType`,
)
const iosVersions = versions.filter((version) => (version.attributes?.platform ?? 'IOS') === 'IOS')
let version = iosVersions.find((candidate) => candidate.attributes?.versionString === versionString)

// Apple rejects `whatsNew` on an app's very first version — there is nothing
// to be new against. Detected from whether any other version exists rather
// than from the version string, because 1.0.0 is not always the first thing
// uploaded (a 0.9 TestFlight-only version is common).
const isFirstVersion = iosVersions.length === 0 || (iosVersions.length === 1 && version)

if (!version) {
  const attributes = {
    platform: store.config.platform ?? 'IOS',
    versionString,
    ...(store.config.copyright ? { copyright: store.config.copyright } : {}),
    ...(store.config.releaseType ? { releaseType: store.config.releaseType } : {}),
  }
  await change('version', `create ${versionString}`, async () => {
    const created = await client.post('/v1/appStoreVersions', {
      data: {
        type: 'appStoreVersions',
        attributes,
        relationships: { app: { data: { type: 'apps', id: app.id } } },
      },
    })
    version = created.data
  })
  if (!apply) {
    // Nothing downstream can be diffed against a version that does not exist
    // yet, so say what would happen and stop rather than inventing a plan.
    console.log('\nDry run stops here: the rest of the plan depends on the version record that would be created.')
    console.log(`Re-run with --apply to create ${versionString} and push the listing into it.`)
    process.exit(0)
  }
} else {
  const state = versionState(version)
  if (!EDITABLE_VERSION_STATES.has(state)) {
    console.error(`✗ Version ${versionString} is ${state} and does not accept metadata edits.`)
    console.error('  Create the next version in App Store Connect, or push to the version that is editable.')
    process.exit(1)
  }
  console.log(`  version ${versionString} exists (${state})`)
  const delta = diffAttributes(version.attributes, {
    copyright: store.config.copyright,
    releaseType: store.config.releaseType,
  })
  if (Object.keys(delta).length) {
    await change('version attributes', Object.entries(delta).map(([k, v]) => `${k}=${summarize(v)}`).join(', '), () =>
      client.patch(`/v1/appStoreVersions/${version.id}`, {
        data: { type: 'appStoreVersions', id: version.id, attributes: delta },
      }),
    )
  }
}

const versionLocalizations = await client.getAll(
  `/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=50`,
)
const versionByLocale = new Map(versionLocalizations.map((item) => [item.attributes?.locale, item]))

for (const [locale, fields] of Object.entries(store.locales)) {
  const desired = {
    description: fields.description,
    keywords: fields.keywords,
    promotionalText: fields.promotional_text,
    supportUrl: fields.support_url,
    marketingUrl: fields.marketing_url,
    ...(isFirstVersion ? {} : { whatsNew: fields.release_notes }),
  }
  const existing = versionByLocale.get(locale)

  if (!existing) {
    await change(`${locale} listing`, 'create', () =>
      client.post('/v1/appStoreVersionLocalizations', {
        data: {
          type: 'appStoreVersionLocalizations',
          attributes: { locale, ...desired },
          relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } },
        },
      }),
    )
    continue
  }

  const delta = diffAttributes(existing.attributes, desired)
  for (const [key, value] of Object.entries(delta)) {
    console.log(`      ${key}: ${summarize(existing.attributes?.[key])} → ${summarize(value)}`)
  }
  if (Object.keys(delta).length) {
    await change(`${locale} listing`, Object.keys(delta).join(', '), () =>
      client.patch(`/v1/appStoreVersionLocalizations/${existing.id}`, {
        data: { type: 'appStoreVersionLocalizations', id: existing.id, attributes: delta },
      }),
    )
  }
}

if (isFirstVersion) {
  console.log('  note: release notes are not sent for a first version — Apple has nothing to show them against.')
}

// ---------------------------------------------------------------------------
// 3 · Review details
// ---------------------------------------------------------------------------

console.log('\nReview details')
const review = store.review ?? {}
const desiredReview = {
  contactFirstName: review.contactFirstName,
  contactLastName: review.contactLastName,
  contactPhone: review.contactPhone,
  contactEmail: review.contactEmail,
  demoAccountRequired: review.demoAccountRequired ?? false,
  notes: review.notes ?? undefined,
}

const existingReview = await client
  .get(`/v1/appStoreVersions/${version.id}/appStoreReviewDetail`)
  .catch((error) => (error.status === 404 ? null : Promise.reject(error)))

if (!existingReview?.data) {
  await change('review detail', 'create', () =>
    client.post('/v1/appStoreReviewDetails', {
      data: {
        type: 'appStoreReviewDetails',
        attributes: desiredReview,
        relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } },
      },
    }),
  )
} else {
  const delta = diffAttributes(existingReview.data.attributes, desiredReview)
  if (Object.keys(delta).length) {
    await change('review detail', Object.keys(delta).join(', '), () =>
      client.patch(`/v1/appStoreReviewDetails/${existingReview.data.id}`, {
        data: { type: 'appStoreReviewDetails', id: existingReview.data.id, attributes: delta },
      }),
    )
  }
}

// ---------------------------------------------------------------------------

console.log('')
if (!changes.length) {
  console.log('✓ App Store Connect already matches store/. Nothing to do.')
} else if (apply) {
  console.log(`✓ Applied ${changes.length} change(s).`)
  console.log('  Screenshots are separate: node scripts/asc/upload-screenshots.mjs --version ' + versionString)
} else {
  console.log(`${changes.length} change(s) would be applied. Re-run with --apply.`)
}
