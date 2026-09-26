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

// Only a submission still in play can hold an item. A COMPLETE or CANCELED one
// has been closed and no longer blocks a new submission - which is what
// canceling the rejected submission was for.
const BLOCKING_STATES = new Set([
  'READY_FOR_REVIEW', 'WAITING_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES',
])

let versionAttached = false
let elsewhere = null
for (const submission of submissions) {
  // The item id's trailing field is an internal number, not the appStoreVersion
  // uuid, so ask Apple for the relationship. `include` is what makes the
  // version id legible at all.
  let submissionItems
  try {
    submissionItems = await client.getAll(
      `/v1/reviewSubmissions/${submission.id}/items?limit=50&include=appStoreVersion`)
  } catch {
    submissionItems = submission.id === open.id
      ? items
      : await client.getAll(`/v1/reviewSubmissions/${submission.id}/items?limit=50`)
  }
  for (const item of submissionItems) {
    const related = item.relationships?.appStoreVersion?.data?.id
    const decoded = decode(item.id).split('|')[2]
    if (related !== version.id && decoded !== version.id) continue
    if (submission.id === open.id) versionAttached = true
    else if (BLOCKING_STATES.has(submission.attributes?.state)) {
      elsewhere = { submissionId: submission.id, state: submission.attributes?.state, itemId: item.id }
    }
  }
}
console.log(`Version attached here: ${versionAttached}; held elsewhere: ${JSON.stringify(elsewhere)}`)

if (versionAttached) {
  report.actions.push('version already attached')
  console.log('The app version is already in the open submission.')
} else if (elsewhere && !apply) {
  report.actions.push(`would release the version from submission ${elsewhere.submissionId} (${elsewhere.state}) item ${elsewhere.itemId}`)
  report.actions.push(`would attach version ${version.id} (${versionString}, ${versionState})`)
  console.log(`The version is held by submission ${elsewhere.submissionId} (${elsewhere.state}).`)
  console.log(`Would remove item ${elsewhere.itemId} there, then attach it here.`)
} else if (elsewhere) {
  // Apple: STATE_ERROR.ITEM_PART_OF_ANOTHER_SUBMISSION, and a DELETE is refused
  // with "Item was already submitted" - a submitted item cannot be removed. The
  // resolved submission is closed instead, which releases what it holds. That
  // is asynchronous, so wait for the state before attaching.
  const canceled = await client.patch(`/v1/reviewSubmissions/${elsewhere.submissionId}`, {
    data: { type: 'reviewSubmissions', id: elsewhere.submissionId, attributes: { canceled: true } },
  })
  let state = canceled?.data?.attributes?.state
  report.actions.push(`canceled submission ${elsewhere.submissionId} (state ${state})`)
  console.log(`Canceled submission ${elsewhere.submissionId}; state ${state}.`)
  for (let attempt = 0; attempt < 12 && !['CANCELED', 'COMPLETE'].includes(state); attempt++) {
    await new Promise((resolve) => setTimeout(resolve, 5000))
    const fresh = (await client.get(`/v1/reviewSubmissions/${elsewhere.submissionId}`)).data
    state = fresh?.attributes?.state
    console.log(`  submission state: ${state}`)
  }
  report.submission.releasedState = state
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
