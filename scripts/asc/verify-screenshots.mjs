#!/usr/bin/env node
// Read back Apple's ordered screenshots and wait for processing to complete.
import crypto from 'node:crypto'
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs'
import { basename, dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { AppStoreConnect, findApp, listVersions, sleep } from './lib/asc.mjs'
import { loadStore } from './lib/metadata.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const args = process.argv.slice(2)
const versionIndex = args.indexOf('--version')
const versionString = versionIndex < 0 ? null : args[versionIndex + 1]
if (!versionString) throw new Error('Usage: verify-screenshots.mjs --version <version>')
const store = loadStore(join(root, 'store'))
const client = AppStoreConnect.fromEnv()
const app = await findApp(client, store.config.bundleId)
if (!app) throw new Error('App not found')
const version = (await listVersions(client, app.id)).find(v => v.attributes.versionString === versionString)
if (!version) throw new Error('Version not found')
const localizations = await client.getAll(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=50`)
const report = { appId: app.id, version: versionString, versionId: version.id, checkedAt: null, passed: false, sets: [] }
const output = join(root, 'apple-audit/screenshots.json')
mkdirSync(dirname(output), { recursive: true })
for (let attempt = 0; attempt < 24; attempt++) {
  report.sets = []
  for (const [locale, wantedSets] of Object.entries(store.screenshots)) {
    const localization = localizations.find(l => l.attributes.locale === locale)
    if (!localization) throw new Error(`Missing localization ${locale}`)
    const sets = await client.getAll(`/v1/appStoreVersionLocalizations/${localization.id}/appScreenshotSets?limit=50`)
    for (const [displayType, files] of Object.entries(wantedSets)) {
      const set = sets.find(s => s.attributes.screenshotDisplayType === displayType)
      const screenshots = set ? await client.getAll(`/v1/appScreenshotSets/${set.id}/appScreenshots?limit=50`) : []
      const wanted = files.map(file => ({ name: basename(file), checksum: crypto.createHash('md5').update(readFileSync(file)).digest('hex') }))
      const actual = screenshots.map(s => ({ id: s.id, name: s.attributes.fileName, checksum: s.attributes.sourceFileChecksum, state: s.attributes.assetDeliveryState?.state, errors: s.attributes.assetDeliveryState?.errors ?? [] }))
      const matches = actual.length === wanted.length && actual.every((s, i) => s.checksum === wanted[i].checksum && s.name === wanted[i].name && s.state === 'COMPLETE')
      report.sets.push({ locale, displayType, setId: set?.id, matches, wanted, actual })
    }
  }
  report.checkedAt = new Date().toISOString()
  report.passed = report.sets.length > 0 && report.sets.every(s => s.matches)
  writeFileSync(output, JSON.stringify(report, null, 2) + '\n')
  if (report.passed) {
    console.log(`Verified ${report.sets.reduce((n, s) => n + s.actual.length, 0)} screenshots across ${report.sets.length} sets: exact checksums, filename order and COMPLETE processing.`)
    break
  }
  if (report.sets.some(s => s.actual.some(a => a.state === 'FAILED'))) throw new Error('Apple failed screenshot processing; see report')
  console.log(`Verification ${attempt + 1}: ${report.sets.filter(s => s.matches).length}/${report.sets.length} sets complete.`)
  if (attempt < 23) await sleep(10000)
}
if (!report.passed) throw new Error('Screenshot verification did not complete; see report')
