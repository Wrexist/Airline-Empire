#!/usr/bin/env node
// Game Center in App Store Connect, from store/game-center/ (docs/GAME_CENTER.md §3).
//
// The 1.2 build declares com.apple.developer.game-center, and Apple refuses to
// review a version whose build does that unless the version has a Game Center
// configuration (STATE_ERROR.BUILD_INDICATES_GAME_CENTER_ENABLED). This script
// enables Game Center for the app, creates the 17 achievements and three
// leaderboards with their en-US and en-GB text and images, and links the
// version. It only ever creates what is missing: IDs are permanent (renaming
// one orphans every player's progress), so nothing here edits or deletes.
//
// Usage:
//   node scripts/asc/setup-game-center.mjs --version 1.2.0            # plan
//   node scripts/asc/setup-game-center.mjs --version 1.2.0 --apply
import { readFileSync, statSync } from 'node:fs'
import { join, resolve, dirname, basename } from 'node:path'
import { fileURLToPath } from 'node:url'
import { AppStoreConnect, findApp, listVersions } from './lib/asc.mjs'
import { loadStore } from './lib/metadata.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const args = process.argv.slice(2)
const apply = args.includes('--apply')
const versionIndex = args.indexOf('--version')
const versionString = versionIndex === -1 ? null : args[versionIndex + 1]
if (!versionString) {
  console.error('Usage: node scripts/asc/setup-game-center.mjs --version <version> [--apply]')
  process.exit(2)
}

const gcRoot = join(root, 'store', 'game-center')
const catalog = JSON.parse(readFileSync(join(gcRoot, 'catalog.json'), 'utf8'))
const images = new Map(JSON.parse(readFileSync(join(gcRoot, 'images.json'), 'utf8')).map((i) => [i.id, i.file]))
const ACHIEVEMENT = 'com.airlineempire.game.achievement.'
const LEADERBOARD = 'com.airlineempire.game.leaderboard.'
const LOCALES = ['en-US', 'en-GB']

const store = loadStore(join(root, 'store'))
const client = AppStoreConnect.fromEnv()
const app = await findApp(client, store.config.bundleId)
if (!app) throw new Error(`No app record for ${store.config.bundleId}`)
console.log(`App ${app.id} — ${apply ? 'apply' : 'plan'}`)

let changes = 0
async function change(label, action) {
  changes += 1
  if (!apply) {
    console.log(`  would ${label}`)
    return null
  }
  const result = await action()
  console.log(`  ✓ ${label}`)
  return result
}

async function getOrNull(path) {
  try {
    return (await client.get(path))?.data ?? null
  } catch (error) {
    if (error?.status === 404) return null
    throw error
  }
}

// ---- Game Center for the app --------------------------------------------
let detail = await getOrNull(`/v1/apps/${app.id}/gameCenterDetail`)
console.log(`Game Center: ${detail ? `enabled (${detail.id})` : 'not enabled'}`)
if (!detail) {
  const created = await change('enable Game Center for the app', () =>
    client.post('/v1/gameCenterDetails', {
      data: {
        type: 'gameCenterDetails',
        relationships: { app: { data: { type: 'apps', id: app.id } } },
      },
    }))
  detail = created?.data ?? null
}

// ---- Images ---------------------------------------------------------------
/**
 * An image already there, unless it is a reservation an interrupted run never
 * committed: that one is ours, holds nothing, and is cleared for a fresh upload.
 */
async function existingImage(path, type) {
  const image = await getOrNull(path)
  if (!image) return null
  const state = image.attributes?.assetDeliveryState?.state
  if (state === 'AWAITING_UPLOAD' || state === 'FAILED') {
    await change(`clear an unfinished ${type} upload (${state})`, () => client.delete(`/v1/${type}/${image.id}`))
    return null
  }
  return image
}

/** Reserve, PUT the parts to Apple's storage, commit. */
async function upload(type, relationship, parentType, parentId, file) {
  const bytes = readFileSync(file)
  const reservation = await client.post(`/v1/${type}`, {
    data: {
      type,
      attributes: { fileName: basename(file), fileSize: statSync(file).size },
      relationships: { [relationship]: { data: { type: parentType, id: parentId } } },
    },
  })
  const asset = reservation.data
  for (const operation of asset.attributes?.uploadOperations ?? []) {
    const headers = Object.fromEntries((operation.requestHeaders ?? []).map((h) => [h.name, h.value]))
    // A bare fetch: Apple's blob storage carries its own authorisation.
    const response = await fetch(operation.url, {
      method: operation.method ?? 'PUT',
      headers,
      body: bytes.subarray(operation.offset, operation.offset + operation.length),
    })
    if (!response.ok) throw new Error(`${basename(file)}: upload failed (HTTP ${response.status})`)
  }
  await client.patch(`/v1/${type}/${asset.id}`, {
    data: { type, id: asset.id, attributes: { uploaded: true } },
  })
}

// ---- Achievements -----------------------------------------------------------
const existingAchievements = detail?.id
  ? await client.getAll(`/v1/gameCenterDetails/${detail.id}/gameCenterAchievements?limit=200`)
  : []
const achievementsById = new Map(existingAchievements.map((a) => [a.attributes?.vendorIdentifier, a]))
console.log(`Achievements: ${existingAchievements.length} in App Store Connect, ${catalog.achievements.length} in the catalogue`)

for (const a of catalog.achievements) {
  const id = ACHIEVEMENT + a.suffix
  let record = achievementsById.get(id)
  if (!record) {
    const made = await change(`create achievement ${id} (${a.points} points)`, () =>
      client.post('/v1/gameCenterAchievements', {
        data: {
          type: 'gameCenterAchievements',
          attributes: {
            referenceName: a.title, vendorIdentifier: id, points: a.points,
            showBeforeEarned: !a.hidden, repeatable: false,
          },
          relationships: { gameCenterDetail: { data: { type: 'gameCenterDetails', id: detail.id } } },
        },
      }))
    record = made?.data ?? null
  }
  const localizations = record?.id
    ? await client.getAll(`/v1/gameCenterAchievements/${record.id}/localizations?limit=50`)
    : []
  for (const locale of LOCALES) {
    let loc = localizations.find((l) => l.attributes?.locale === locale)
    if (!loc) {
      const made = await change(`add ${locale} text to ${a.suffix}`, () =>
        client.post('/v1/gameCenterAchievementLocalizations', {
          data: {
            type: 'gameCenterAchievementLocalizations',
            attributes: { locale, name: a.title, beforeEarnedDescription: a.preEarned, afterEarnedDescription: a.earned },
            relationships: { gameCenterAchievement: { data: { type: 'gameCenterAchievements', id: record.id } } },
          },
        }))
      loc = made?.data ?? null
    }
    const image = loc?.id
      ? await existingImage(`/v1/gameCenterAchievementLocalizations/${loc.id}/gameCenterAchievementImage`, 'gameCenterAchievementImages')
      : null
    if (!image) {
      const file = join(gcRoot, images.get(id) ?? `achievements/${a.suffix}.png`)
      await change(`upload ${locale} image for ${a.suffix}`, () =>
        upload('gameCenterAchievementImages', 'gameCenterAchievementLocalization',
          'gameCenterAchievementLocalizations', loc.id, file))
    }
  }
}

// ---- Leaderboards -----------------------------------------------------------
const existingBoards = detail?.id
  ? await client.getAll(`/v1/gameCenterDetails/${detail.id}/gameCenterLeaderboards?limit=200`)
  : []
const boardsById = new Map(existingBoards.map((b) => [b.attributes?.vendorIdentifier, b]))
console.log(`Leaderboards: ${existingBoards.length} in App Store Connect, ${catalog.leaderboards.length} in the catalogue`)

const singular = { passengers: 'passenger', destinations: 'destination', aircraft: 'aircraft' }
for (const b of catalog.leaderboards) {
  const id = LEADERBOARD + b.suffix
  let record = boardsById.get(id)
  if (!record) {
    const made = await change(`create leaderboard ${id}`, () =>
      client.post('/v1/gameCenterLeaderboards', {
        data: {
          type: 'gameCenterLeaderboards',
          attributes: {
            referenceName: b.title, vendorIdentifier: id, defaultFormatter: 'INTEGER',
            submissionType: 'BEST_SCORE', scoreSortType: 'DESC',
            scoreRangeStart: '0', scoreRangeEnd: '2000000000',
          },
          relationships: { gameCenterDetail: { data: { type: 'gameCenterDetails', id: detail.id } } },
        },
      }))
    record = made?.data ?? null
  }
  const localizations = record?.id
    ? await client.getAll(`/v1/gameCenterLeaderboards/${record.id}/localizations?limit=50`)
    : []
  for (const locale of LOCALES) {
    let loc = localizations.find((l) => l.attributes?.locale === locale)
    if (!loc) {
      const made = await change(`add ${locale} text to leaderboard ${b.suffix}`, () =>
        client.post('/v1/gameCenterLeaderboardLocalizations', {
          data: {
            type: 'gameCenterLeaderboardLocalizations',
            attributes: {
              locale, name: b.title,
              formatterSuffix: ` ${b.unit}`, formatterSuffixSingular: ` ${singular[b.unit] ?? b.unit}`,
            },
            relationships: { gameCenterLeaderboard: { data: { type: 'gameCenterLeaderboards', id: record.id } } },
          },
        }))
      loc = made?.data ?? null
    }
    const image = loc?.id
      ? await existingImage(`/v1/gameCenterLeaderboardLocalizations/${loc.id}/gameCenterLeaderboardImage`, 'gameCenterLeaderboardImages')
      : null
    if (!image) {
      const file = join(gcRoot, images.get(id) ?? `leaderboards/${b.suffix}.png`)
      await change(`upload ${locale} image for leaderboard ${b.suffix}`, () =>
        upload('gameCenterLeaderboardImages', 'gameCenterLeaderboardLocalization',
          'gameCenterLeaderboardLocalizations', loc.id, file))
    }
  }
}

// ---- The version ------------------------------------------------------------
const version = (await listVersions(client, app.id)).find((v) => v.attributes?.versionString === versionString)
if (!version) throw new Error(`Version ${versionString} not found`)
const linked = await getOrNull(`/v1/appStoreVersions/${version.id}/gameCenterAppVersion`)
console.log(`Version ${versionString}: ${linked ? 'Game Center linked' : 'no Game Center configuration'}`)
if (!linked) {
  await change(`link version ${versionString} to Game Center`, () =>
    client.post('/v1/gameCenterAppVersions', {
      data: {
        type: 'gameCenterAppVersions',
        relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } },
      },
    }))
}

console.log(`\n${apply ? 'Applied' : 'Would apply'} ${changes} change(s).`)
