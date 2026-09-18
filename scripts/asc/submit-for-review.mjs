#!/usr/bin/env node
// Attach the app version to the open review submission, and optionally submit.
//
// App Review rejected 1.0 under Guideline 2.1(b). The audit showed why: the
// rejected submission held only the app version, and a second submission in
// READY_FOR_REVIEW holds the three Pro products (and their group) but not the
// version. A resubmission needs both in one submission.
//
// Usage:
//   node scripts/asc/submit-for-review.mjs --version 1.0            # plan only
//   node scripts/asc/submit-for-review.mjs --version 1.0 --apply    # attach the version
//   node scripts/asc/submit-for-review.mjs --version 1.0 --apply --submit
//
// --apply without --submit leaves a prepared submission, which is reversible
// and visible in App Store Connect. --submit is the act that sends it to Apple.
import { mkdirSync, writeFileSync } from 'node:fs'
import { join, resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { AppStoreConnect, findApp, listVersions } from './lib/asc.mjs'
import { loadStore } from './lib/metadata.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const args = process.argv.slice(2)
const apply = args.includes('--apply')
const submit = args.includes('--submit')
const versionIndex = args.indexOf('--version')
const versionString = versionIndex === -1 ? null : args[versionIndex + 1]
if (!versionString) {
  console.error('Usage: node scripts/asc/submit-for-review.mjs --version <version> [--apply] [--submit]')
  process.exit(2)
}

const store = loadStore(join(root, 'store'))
const client = AppStoreConnect.fromEnv()
const app = await findApp(client, store.config.bundleId)
if (!app) throw new Error(`No app record for ${store.config.bundleId}`)

const version = (await listVersions(client, app.id))
  .find((v) => v.attributes?.versionString === versionString)
if (!version) throw new Error(`Version ${versionString} not found`)
const versionState = version.attributes?.appStoreState ?? version.attributes?.state

const submissions = await client.getAll(`/v1/apps/${app.id}/reviewSubmissions?limit=50`)
// The one that is still being prepared. An app has at most one at a time.
const open = submissions.find((s) => ['READY_FOR_REVIEW', 'WAITING_FOR_REVIEW'].includes(s.attributes?.state))
if (!open) throw new Error('No review submission in READY_FOR_REVIEW; nothing to attach to')

const items = await client.getAll(`/v1/reviewSubmissions/${open.id}/items?limit=50`)
const report = {
  checkedAt: new Date().toISOString(),
  appId: app.id,
  version: { id: version.id, versionString, state: versionState },
  submission: { id: open.id, state: open.attributes?.state, itemCount: items.length },
  mode: submit ? 'apply+submit' : apply ? 'apply' : 'plan',
  actions: [],
}

const decode = (id) => {
  try { return Buffer.from(id, 'base64').toString('utf8') } catch { return id }
}
for (const item of items) console.log(`item ${item.id} · ${item.attributes?.state} · ${decode(item.id)}`)

let versionAttached = false
for (const item of items) {
  const parts = decode(item.id).split('|')
  if (parts[2] === version.id) versionAttached = true
}
// The version can also be attached without its id being legible in the item id,
// so ask Apple directly before deciding.
try {
  const withVersion = await client.getAll(
    `/v1/reviewSubmissions/${open.id}/items?limit=50&include=appStoreVersion`)
  for (const entry of withVersion) {
    if (entry.relationships?.appStoreVersion?.data?.id === version.id) versionAttached = true
  }
} catch (error) {
  console.log(`include=appStoreVersion unavailable (${error.status ?? '?'}); relying on the item ids`)
}

if (versionAttached) {
  report.actions.push('version already attached')
  console.log('The app version is already in the open submission.')
} else if (!apply) {
  report.actions.push(`would attach version ${version.id} (${versionString}, ${versionState})`)
  console.log(`Would attach version ${version.id} (${versionString}, ${versionState}) to submission ${open.id}.`)
} else {
  try {
    const created = await client.post('/v1/reviewSubmissionItems', {
      data: {
        type: 'reviewSubmissionItems',
        relationships: {
          reviewSubmission: { data: { type: 'reviewSubmissions', id: open.id } },
          appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } },
        },
      },
    })
    report.actions.push(`attached version item ${created?.data?.id}`)
    console.log(`Attached version item ${created?.data?.id} to submission ${open.id}.`)
  } catch (error) {
    // Apple's associated errors say *why* a resource cannot be reviewed; the
    // summary line alone does not, and guessing wastes a review cycle.
    report.error = { status: error.status, errors: error.errors ?? String(error.message ?? error) }
    console.error(JSON.stringify(report.error, null, 2))
    throw error
  }
}

if (submit) {
  if (!apply) throw new Error('--submit needs --apply')
  // Re-read: Apple needs the item list to be settled before it will submit.
  const settled = await client.getAll(`/v1/reviewSubmissions/${open.id}/items?limit=50`)
  report.submission.itemCountAfter = settled.length
  const patched = await client.patch(`/v1/reviewSubmissions/${open.id}`, {
    data: { type: 'reviewSubmissions', id: open.id, attributes: { submitted: true } },
  })
  report.submission.stateAfter = patched?.data?.attributes?.state
  report.actions.push(`submitted (state ${report.submission.stateAfter})`)
  console.log(`Submitted submission ${open.id}; state is now ${report.submission.stateAfter}.`)
}

mkdirSync(join(root, 'apple-audit'), { recursive: true })
writeFileSync(join(root, 'apple-audit/submit-for-review.json'), JSON.stringify(report, null, 2) + '\n')
console.log(JSON.stringify(report, null, 2))
