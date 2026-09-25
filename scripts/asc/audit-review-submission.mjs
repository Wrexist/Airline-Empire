#!/usr/bin/env node
// Read-only: what is in the open App Review submission for this app?
//
// App Review rejected 1.0 under Guideline 2.1(b) because the three Pro products
// had not been submitted for review, even though all three are READY_TO_SUBMIT
// with their App Review screenshots complete. That finding lives in the
// submission, not in the products, so this reads the submission itself:
// every review submission for the app, its state, and the items attached to
// the open one.
//
// Writes apple-audit/review-submission.json and prints a summary. Never writes
// to App Store Connect.
import { mkdirSync, writeFileSync } from 'node:fs'
import { join, resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { AppStoreConnect, findApp, listVersions } from './lib/asc.mjs'
import { loadStore } from './lib/metadata.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const store = loadStore(join(root, 'store'))
const client = AppStoreConnect.fromEnv()
const app = await findApp(client, store.config.bundleId)
if (!app) throw new Error(`No app record for ${store.config.bundleId}`)

const submissions = await client.getAll(`/v1/apps/${app.id}/reviewSubmissions?limit=50`)
const report = {
  checkedAt: new Date().toISOString(),
  appId: app.id,
  bundleId: store.config.bundleId,
  submissions: [],
}

for (const submission of submissions) {
  const entry = {
    id: submission.id,
    state: submission.attributes?.state,
    platform: submission.attributes?.platform,
    submittedDate: submission.attributes?.submittedDate,
    items: [],
  }
  // No `include`, deliberately: the relationship names differ between the
  // classic products this app has (subscriptions v1, inAppPurchases v2) and
  // the version-based ones newer records use, and an unknown include is a 400.
  // Printing the relationship keys Apple returns is the honest read.
  try {
    const items = await client.getAll(`/v1/reviewSubmissions/${submission.id}/items?limit=50`)
    entry.items = items.map((item) => ({
      id: item.id,
      state: item.attributes?.state,
      relationships: Object.keys(item.relationships ?? {}),
      related: Object.fromEntries(Object.entries(item.relationships ?? {})
        .map(([name, value]) => [name, value?.data?.id ?? null])),
    }))
  } catch (error) {
    entry.itemsError = String(error.message ?? error)
  }
  // Apple's own id for the version on each item, when it will tell us: the
  // item id's trailing number is not always the appStoreVersion id, and a 409
  // named a different one.
  try {
    const withVersion = await client.getAll(
      `/v1/reviewSubmissions/${submission.id}/items?limit=50&include=appStoreVersion`)
    entry.itemVersions = withVersion.map((item) => ({
      id: item.id,
      state: item.attributes?.state,
      appStoreVersion: item.relationships?.appStoreVersion?.data?.id ?? null,
    }))
  } catch (error) {
    entry.itemVersionsError = String(error.message ?? error)
  }
  report.submissions.push(entry)
}

const versions = await listVersions(client, app.id)
report.versions = []
for (const v of versions) {
  // The version record and the attached build's marketing version are separate
  // strings, and App Review reports the pair ("1.0 (10)"). Read both.
  let build = null
  try {
    const attached = (await client.get(`/v1/appStoreVersions/${v.id}/build`)).data
    if (attached) {
      build = {
        id: attached.id,
        buildNumber: attached.attributes?.version,
        processingState: attached.attributes?.processingState,
        preReleaseVersion: null,
      }
      // The include is a separate, optional read: if Apple refuses it, the
      // build is still read and reported rather than reported as absent.
      try {
        const withPre = (await client.get(
          `/v1/appStoreVersions/${v.id}/build?include=preReleaseVersion`)).data
        build.preReleaseVersion = withPre?.relationships?.preReleaseVersion?.data?.id ?? null
      } catch { /* include unsupported; the build is still known */ }
    }
  } catch {
    build = null
  }
  report.versions.push({
    id: v.id,
    versionString: v.attributes?.versionString,
    state: v.attributes?.appStoreState ?? v.attributes?.state,
    build,
  })
}

const products = [
  { name: 'weekly', path: '/v1/subscriptions/6810782782', localizations: '/v1/subscriptions/6810782782/subscriptionLocalizations?limit=50' },
  { name: 'yearly', path: '/v1/subscriptions/6810785364', localizations: '/v1/subscriptions/6810785364/subscriptionLocalizations?limit=50' },
  { name: 'lifetime', path: '/v2/inAppPurchases/6810786506', localizations: '/v2/inAppPurchases/6810786506/inAppPurchaseLocalizations?limit=50' },
]
report.products = []
for (const product of products) {
  const data = (await client.get(product.path)).data
  // An IAP with no localised display name or description is a rejection that
  // costs a review cycle, and it is invisible in a product-state check.
  let localizations = []
  try {
    localizations = (await client.getAll(product.localizations)).map((l) => ({
      locale: l.attributes?.locale,
      name: l.attributes?.name ?? null,
      description: l.attributes?.description ? 'present' : 'MISSING',
    }))
  } catch (error) {
    localizations = [{ error: String(error.message ?? error) }]
  }
  report.products.push({
    name: product.name,
    productId: data.attributes?.productId,
    state: data.attributes?.state,
    localizations,
  })
}

// Every build Apple holds, newest first: the version attached to the App Store
// version under review is not necessarily the newest thing in TestFlight, and
// a build whose marketing version differs cannot be attached to that version.
report.builds = []
try {
  const builds = await client.getAll(
    `/v1/builds?filter[app]=${app.id}&limit=50&include=preReleaseVersion&sort=-uploadedDate`)
  for (const build of builds) {
    const prereleaseId = build.relationships?.preReleaseVersion?.data?.id ?? null
    report.builds.push({
      id: build.id,
      buildNumber: build.attributes?.version,
      processingState: build.attributes?.processingState,
      expired: build.attributes?.expired,
      uploadedDate: build.attributes?.uploadedDate,
      expirationDate: build.attributes?.expirationDate,
      preReleaseVersionId: prereleaseId,
    })
  }
  const versionsSeen = new Map((report.builds).map((b) => [b.preReleaseVersionId, null]))
  for (const id of versionsSeen.keys()) {
    if (!id) continue
    try {
      const pre = (await client.get(`/v1/preReleaseVersions/${id}`)).data
      versionsSeen.set(id, pre.attributes?.version ?? '?')
    } catch { versionsSeen.set(id, '?') }
  }
  for (const build of report.builds) build.marketingVersion = versionsSeen.get(build.preReleaseVersionId) ?? '?'
} catch (error) {
  report.buildsError = String(error.message ?? error)
}

mkdirSync(join(root, 'apple-audit'), { recursive: true })
writeFileSync(join(root, 'apple-audit/review-submission.json'), JSON.stringify(report, null, 2) + '\n')

for (const submission of report.submissions) {
  console.log(`Submission ${submission.id} · ${submission.state} · ${submission.platform} · items ${submission.items.length}`)
  for (const item of submission.items) {
    console.log(`  item ${item.id} · ${item.state} · ${item.relationships.join(',')} · ${JSON.stringify(item.related)}`)
  }
  for (const item of submission.itemVersions ?? []) {
    console.log(`  item ${item.id} · ${item.state} · appStoreVersion ${item.appStoreVersion}`)
  }
  if (submission.itemsError) console.log(`  items error: ${submission.itemsError}`)
  if (submission.itemVersionsError) console.log(`  item versions error: ${submission.itemVersionsError}`)
}
for (const version of report.versions) {
  const build = version.build
    ? `build ${version.build.buildNumber} ${version.build.processingState} prerelease ${version.build.preReleaseVersion ?? '?'}`
    : 'NO BUILD ATTACHED'
  console.log(`Version ${version.versionString} · ${version.id} · ${version.state} · ${build}`)
}
// The string the App Store page will show, read from Apple rather than assumed.
const prereleaseIds = new Set(report.versions.map((v) => v.build?.preReleaseVersion).filter(Boolean))
for (const id of prereleaseIds) {
  try {
    const prerelease = (await client.get(`/v1/preReleaseVersions/${id}`)).data
    console.log(`Pre-release version ${prerelease.attributes?.version} · ${prerelease.attributes?.platform} · ${prerelease.attributes?.appStoreState ?? prerelease.attributes?.state}`)
  } catch (error) {
    console.log(`Pre-release version ${id}: ${error.message ?? error}`)
  }
}
for (const build of report.builds ?? []) {
  console.log(`Build ${build.marketingVersion} (${build.buildNumber}) · ${build.processingState} · uploaded ${build.uploadedDate} · expires ${build.expirationDate} · expired ${build.expired}`)
}
if (report.buildsError) console.log(`builds error: ${report.buildsError}`)

for (const product of report.products) {
  const locales = product.localizations
    .map((l) => l.error ? `error ${l.error}` : `${l.locale} name=${l.name ? 'yes' : 'NO'} description=${l.description}`)
    .join('; ')
  console.log(`Product ${product.name} · ${product.state} · ${locales}`)
}
