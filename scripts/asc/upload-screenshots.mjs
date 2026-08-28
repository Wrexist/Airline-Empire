#!/usr/bin/env node
// scripts/asc/upload-screenshots.mjs
//
// Upload `store/screenshots/<locale>/<DISPLAY_TYPE>/*.png` to an App Store
// version, in filename order.
//
// ## Why screenshots are their own script and their own protocol
//
// Every other piece of metadata is a field you PATCH. A screenshot is a
// four-step conversation: reserve an asset and receive a list of signed upload
// operations, PUT the bytes (Apple hands back one operation per chunk, and a
// large iPad screenshot really does come back as several), commit with an MD5
// of the source file so Apple can verify what landed, then order the set. Any
// step can fail on its own, and a half-uploaded asset sits in App Store
// Connect as a broken thumbnail until someone deletes it by hand.
//
// The signed upload URLs are NOT App Store Connect endpoints — they point at
// Apple's blob storage and carry their own authorisation in the headers the
// reservation returns. Sending our bearer token there would be both wrong and
// a credential leak to a third host, which is why the PUTs below use a bare
// `fetch` rather than the client used everywhere else in this directory.
//
// ## Replacing is opt-in
//
// Uploading into a set that already has screenshots appends. Getting from "the
// old six" to "the new six" therefore means deleting, and deleting a live
// product page's screenshots is exactly the kind of thing a script should not
// decide to do on its own. `--replace` is the opt-in; without it, a set that
// already matches is skipped and a set that differs is reported and left.
//
// Usage:
//   node scripts/asc/upload-screenshots.mjs --version 1.0.0            # plan only
//   node scripts/asc/upload-screenshots.mjs --version 1.0.0 --apply
//   node scripts/asc/upload-screenshots.mjs --version 1.0.0 --apply --replace
//
// NEVER EXECUTED against Apple from this repository: there are no screenshots
// to upload yet, because producing them needs a simulator and therefore a Mac
// (docs/APPLE_VALIDATION.md). Treat the upload path as unproven code.

import crypto from 'node:crypto'
import { readFileSync, statSync } from 'node:fs'
import { basename, dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { AppStoreConnect, findApp, listVersions, versionState, EDITABLE_VERSION_STATES } from './lib/asc.mjs'
import { loadStore, inspectPng, SCREENSHOT_SIZES, MAX_SCREENSHOTS_PER_SET } from './lib/metadata.mjs'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
const args = process.argv.slice(2)
const apply = args.includes('--apply')
const replace = args.includes('--replace')
const versionIndex = args.indexOf('--version')
const versionString = versionIndex === -1 ? null : args[versionIndex + 1]

if (!versionString) {
  console.error('Usage: node scripts/asc/upload-screenshots.mjs --version <MAJOR.MINOR.PATCH> [--apply] [--replace]')
  process.exit(2)
}

const store = loadStore(join(REPO_ROOT, 'store'))
const locales = Object.keys(store.screenshots)
if (!locales.length) {
  console.log('store/screenshots is empty — nothing to upload.')
  process.exit(0)
}

const client = AppStoreConnect.fromEnv()
const app = await findApp(client, store.config.bundleId)
if (!app) {
  console.error(`✗ No App Store Connect app record for ${store.config.bundleId}.`)
  process.exit(1)
}

const versions = await listVersions(client, app.id)
const version = versions.find((candidate) => candidate.attributes?.versionString === versionString)
if (!version) {
  console.error(`✗ No iOS version ${versionString}. Run push-metadata.mjs --apply first; it creates the version.`)
  process.exit(1)
}
if (!EDITABLE_VERSION_STATES.has(versionState(version))) {
  console.error(`✗ Version ${versionString} is ${versionState(version)} and does not accept screenshot changes.`)
  process.exit(1)
}

const localizations = await client.getAll(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=50`)
const localizationByLocale = new Map(localizations.map((item) => [item.attributes?.locale, item]))

let uploaded = 0
let skipped = 0

for (const locale of locales) {
  const localization = localizationByLocale.get(locale)
  if (!localization) {
    console.error(`✗ ${locale}: no localization on version ${versionString}. Push the metadata first.`)
    process.exitCode = 1
    continue
  }

  const existingSets = await client.getAll(`/v1/appStoreVersionLocalizations/${localization.id}/appScreenshotSets?limit=50`)

  for (const [displayType, files] of Object.entries(store.screenshots[locale])) {
    if (files.length > MAX_SCREENSHOTS_PER_SET) {
      console.error(`✗ ${locale}/${displayType}: ${files.length} files, Apple accepts ${MAX_SCREENSHOTS_PER_SET}.`)
      process.exitCode = 1
      continue
    }
    // Local checks first: an alpha channel or a wrong canvas size fails at the
    // commit step, after the bytes have been transferred, which is a slow way
    // to learn something readable from the file header. Tracked per set rather
    // than globally, so one bad image does not silently skip every later set.
    let rejected = false
    for (const file of files) {
      const png = inspectPng(file)
      if (!png) continue
      if (png.hasAlpha) {
        console.error(`✗ ${basename(file)}: has an alpha channel; App Store Connect will reject it.`)
        rejected = true
      }
      const sizes = SCREENSHOT_SIZES[displayType]
      if (sizes && !sizes.some((size) => size.width === png.width && size.height === png.height)) {
        console.error(`✗ ${basename(file)}: ${png.width}×${png.height} is not a ${displayType} canvas size.`)
        rejected = true
      }
    }
    if (rejected) {
      process.exitCode = 1
      continue
    }

    let set = existingSets.find((candidate) => candidate.attributes?.screenshotDisplayType === displayType)
    const existing = set ? await client.getAll(`/v1/appScreenshotSets/${set.id}/appScreenshots?limit=50`) : []

    // Apple stores the MD5 we sent at commit time, so "is this already the
    // set on the store?" is answerable without re-uploading anything.
    const wantedChecksums = files.map((file) => md5(readFileSync(file)))
    const currentChecksums = existing.map((item) => item.attributes?.sourceFileChecksum)
    if (
      currentChecksums.length === wantedChecksums.length &&
      currentChecksums.every((checksum, index) => checksum === wantedChecksums[index])
    ) {
      console.log(`= ${locale}/${displayType}: already ${files.length} matching screenshot(s).`)
      skipped += files.length
      continue
    }

    if (existing.length && !replace) {
      console.warn(
        `⚠︎ ${locale}/${displayType}: ${existing.length} screenshot(s) already uploaded and they differ. ` +
          'Pass --replace to delete and re-upload.',
      )
      continue
    }

    console.log(`${apply ? '→' : '·'} ${locale}/${displayType}: ${files.length} screenshot(s)` + (existing.length ? ` (replacing ${existing.length})` : ''))
    if (!apply) continue

    if (!set) {
      const created = await client.post('/v1/appScreenshotSets', {
        data: {
          type: 'appScreenshotSets',
          attributes: { screenshotDisplayType: displayType },
          relationships: {
            appStoreVersionLocalization: {
              data: { type: 'appStoreVersionLocalizations', id: localization.id },
            },
          },
        },
      })
      set = created.data
    }

    for (const item of existing) await client.delete(`/v1/appScreenshots/${item.id}`)

    const ids = []
    for (const file of files) {
      ids.push(await uploadOne(client, set.id, file))
      uploaded += 1
    }

    // Order is the story the six shots tell, and it is a separate call: the
    // upload order is not the display order.
    await client.patch(`/v1/appScreenshotSets/${set.id}/relationships/appScreenshots`, {
      data: ids.map((id) => ({ type: 'appScreenshots', id })),
    })
  }
}

console.log(`\n${apply ? 'Uploaded' : 'Would upload'} ${uploaded} screenshot(s); ${skipped} already matched.`)
if (!apply) console.log('Re-run with --apply (and --replace, if a set already exists) to perform it.')

// ---------------------------------------------------------------------------

function md5(buffer) {
  // Apple's `sourceFileChecksum` is an MD5 of the source file. MD5 as a
  // content fingerprint chosen by the API, not as a security primitive.
  return crypto.createHash('md5').update(buffer).digest('hex')
}

/** Reserve → PUT every chunk → commit. Returns the new asset's id. */
async function uploadOne(client, setId, file) {
  const bytes = readFileSync(file)
  const reservation = await client.post('/v1/appScreenshots', {
    data: {
      type: 'appScreenshots',
      attributes: { fileName: basename(file), fileSize: statSync(file).size },
      relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: setId } } },
    },
  })

  const asset = reservation.data
  const operations = asset.attributes?.uploadOperations ?? []
  if (!operations.length) throw new Error(`${basename(file)}: Apple returned no upload operations.`)

  for (const operation of operations) {
    const headers = Object.fromEntries((operation.requestHeaders ?? []).map((header) => [header.name, header.value]))
    // Deliberately a bare fetch: these URLs are Apple's blob storage and carry
    // their own authorisation in `headers`. Our bearer token must not travel
    // to a host that is not api.appstoreconnect.apple.com.
    const response = await fetch(operation.url, {
      method: operation.method ?? 'PUT',
      headers,
      body: bytes.subarray(operation.offset, operation.offset + operation.length),
    })
    if (!response.ok) {
      throw new Error(`${basename(file)}: chunk upload failed (HTTP ${response.status} ${await response.text()})`)
    }
  }

  await client.patch(`/v1/appScreenshots/${asset.id}`, {
    data: {
      type: 'appScreenshots',
      id: asset.id,
      attributes: { uploaded: true, sourceFileChecksum: md5(bytes) },
    },
  })
  return asset.id
}
