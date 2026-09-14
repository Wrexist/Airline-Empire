#!/usr/bin/env node
// Change only public website links. Preserve current remote copy and metadata.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { AppStoreConnect, findApp, listVersions } from './lib/asc.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const args = process.argv.slice(2)
const index = args.indexOf('--version')
const versionString = index < 0 ? null : args[index + 1]
const apply = args.includes('--apply')
if (!versionString) throw new Error('Usage: update-website-urls.mjs --version <version> [--apply]')
const config = JSON.parse(readFileSync(join(root, 'store/config.json'), 'utf8'))
const base = config.websiteUrl.replace(/\/$/, '')
const previous = 'https://airline-empire-official.isacmolin.chatgpt.site'
const report = { checkedAt: new Date().toISOString(), version: versionString, mode: apply ? 'apply' : 'plan', pages: [], changes: [], verified: false }
for (const path of ['/', '/support.html', '/privacy.html', '/terms.html', '/press.html']) {
  const url = base + path
  const response = await fetch(url, { signal: AbortSignal.timeout(30000) })
  const html = await response.text()
  if (!response.ok || !html.includes('Airline Empire') || !response.headers.get('content-type')?.includes('text/html')) throw new Error(`Website is not ready: ${url}, HTTP ${response.status}`)
  report.pages.push({ url, status: response.status })
}
const client = AppStoreConnect.fromEnv()
const app = await findApp(client, config.bundleId)
if (!app) throw new Error('App not found')
const version = (await listVersions(client, app.id)).find(v => v.attributes.versionString === versionString)
if (!version) throw new Error('Version not found')
const localizations = await client.getAll(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=50`)
const infos = await client.getAll(`/v1/apps/${app.id}/appInfos?limit=10`)
const info = infos.find(i => (i.attributes?.state ?? i.attributes?.appStoreState) !== 'READY_FOR_DISTRIBUTION')
if (!info) throw new Error('No editable app information record')
const infoLocalizations = await client.getAll(`/v1/appInfos/${info.id}/appInfoLocalizations?limit=50`)

async function update(type, resource, attributes) {
  const delta = Object.fromEntries(Object.entries(attributes).filter(([key, value]) => resource.attributes[key] !== value))
  report.changes.push({ type, id: resource.id, locale: resource.attributes.locale, attributes: delta })
  if (apply && Object.keys(delta).length) await client.patch(`/v1/${type}/${resource.id}`, { data: { type, id: resource.id, attributes: delta } })
  if (apply) {
    const saved = (await client.get(`/v1/${type}/${resource.id}`)).data
    for (const [key, value] of Object.entries(attributes)) if (saved.attributes[key] !== value) throw new Error(`Readback mismatch: ${type}/${resource.id}/${key}`)
  }
  console.log(`${apply ? 'Verified' : 'Planned'} ${resource.attributes.locale} ${type}: ${Object.keys(delta).join(', ') || 'already correct'}`)
}
for (const locale of ['en-US', 'en-GB']) {
  const local = localizations.find(l => l.attributes.locale === locale)
  const appLocal = infoLocalizations.find(l => l.attributes.locale === locale)
  if (!local || !appLocal) throw new Error(`Missing locale ${locale}`)
  const description = (local.attributes.description ?? '').split(previous).join(base)
  await update('appStoreVersionLocalizations', local, { supportUrl: base + '/support.html', marketingUrl: base + '/', description })
  await update('appInfoLocalizations', appLocal, { privacyPolicyUrl: base + '/privacy.html' })
}
report.verified = apply
report.checkedAt = new Date().toISOString()
mkdirSync(join(root, 'apple-audit'), { recursive: true })
writeFileSync(join(root, 'apple-audit/website-urls.json'), JSON.stringify(report, null, 2) + '\n')
