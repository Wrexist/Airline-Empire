#!/usr/bin/env node
// Move the app to a new version and submit it with its purchases.
//
// Why this exists: App Review rejected 1.0 with "upload a new binary". Shipping
// the new binary means a new App Store version, and the three Pro products have
// to travel with it. Apple binds an item to one submission at a time
// (ITEM_PART_OF_ANOTHER_SUBMISSION), so the products must be released from the
// submission that holds them and re-added to the new one.
//
// Nothing is guessed: the product/group identifiers are read from the items
// Apple already holds, using each relationship include in turn, before anything
// is released.
//
// Usage:
//   node scripts/asc/resubmit-version.mjs --version 1.1.0            # plan
//   node scripts/asc/resubmit-version.mjs --version 1.1.0 --apply    # prepare
//   node scripts/asc/resubmit-version.mjs --version 1.1.0 --apply --submit
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
  console.error('Usage: node scripts/asc/resubmit-version.mjs --version <MAJOR.MINOR.PATCH> [--apply] [--submit]')
  process.exit(2)
}

const store = loadStore(join(root, 'store'))
const client = AppStoreConnect.fromEnv()
const app = await findApp(client, store.config.bundleId)
if (!app) throw new Error(`No app record for ${store.config.bundleId}`)

const BLOCKING = new Set(['READY_FOR_REVIEW', 'WAITING_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES'])
// The version this run is about, as Apple holds it now — needed before anything
// is created, so a prepared submission can be recognised rather than withdrawn.
const versionsBefore = await listVersions(client, app.id)
const existingTargetId = versionsBefore
  .find((v) => v.attributes?.versionString === versionString)?.id ?? null
// Every relationship a submission item can carry that this app uses. Apple
// rejects an unknown include for the whole request, so each is asked for alone.
const ITEM_INCLUDES = [
  'appStoreVersion', 'inAppPurchaseVersion', 'subscriptionVersion', 'subscriptionGroupVersion',
]

const report = { checkedAt: new Date().toISOString(), appId: app.id, version: versionString, mode: submit ? 'apply+submit' : apply ? 'apply' : 'plan', actions: [] }

// ---- what Apple holds now -------------------------------------------------
const submissions = await client.getAll(`/v1/apps/${app.id}/reviewSubmissions?limit=50`)
const blocking = submissions.filter((s) => BLOCKING.has(s.attributes?.state))
report.blockingSubmissions = blocking.map((s) => ({ id: s.id, state: s.attributes?.state }))

// The products' identifiers, read before anything is released.
const carried = []
for (const submission of blocking) {
  const items = await client.getAll(`/v1/reviewSubmissions/${submission.id}/items?limit=50`)
  for (const item of items) {
    for (const include of ITEM_INCLUDES) {
      try {
        const withInclude = await client.getAll(
          `/v1/reviewSubmissions/${submission.id}/items?limit=50&include=${include}`)
        const match = withInclude.find((entry) => entry.id === item.id)
        const related = match?.relationships?.[include]?.data?.id
        if (related) carried.push({ include, id: related, from: submission.id })
      } catch { /* include not supported for this item */ }
    }
  }
}
// One entry per resource: the same id can be found through more than one item.
const unique = new Map()
for (const entry of carried) unique.set(`${entry.include}:${entry.id}`, entry)
report.carried = [...unique.values()]
console.log(`Carried by the current submission: ${report.carried.map((c) => `${c.include}=${c.id}`).join(', ') || 'nothing'}`)

const productEntries = report.carried.filter((c) => c.include !== 'appStoreVersion')
if (!productEntries.length) {
  console.warn('No purchase items found in a blocking submission; the new submission would hold only the version.')
}

// ---- withdraw first -------------------------------------------------------
// Apple refuses to create a new version while another is in review
// (ENTITY_ERROR.RELATIONSHIP.INVALID, "You cannot create a new version of the
// App in the current state"), and an item can only be in one submission, so the
// version in review is withdrawn before anything is created. Closing it also
// releases the purchases, whose identifiers were read above.
//
// A submission that already carries *this* version is the one being prepared,
// not one to cancel: prepare and submit run as separate dispatches, and
// cancelling the prepared submission would rebuild it for no reason.
let reusable = null
for (const submission of blocking) {
  const isTarget = report.carried.some(
    (c) => c.from === submission.id && c.include === 'appStoreVersion' && c.id === existingTargetId)
  if (isTarget) reusable = submission
}
const toCancel = blocking.filter((s) => s.id !== reusable?.id)
if (reusable) console.log(`Reusing submission ${reusable.id} (${reusable.attributes?.state}).`)

if (!apply) {
  for (const submission of toCancel) console.log(`Would withdraw submission ${submission.id} (${submission.attributes?.state}).`)
} else {
  for (const submission of toCancel) {
    const canceled = await client.patch(`/v1/reviewSubmissions/${submission.id}`, {
      data: { type: 'reviewSubmissions', id: submission.id, attributes: { canceled: true } },
    })
    let state = canceled?.data?.attributes?.state
    for (let attempt = 0; attempt < 12 && !['CANCELED', 'COMPLETE'].includes(state); attempt++) {
      await new Promise((r) => setTimeout(r, 5000))
      state = (await client.get(`/v1/reviewSubmissions/${submission.id}`)).data?.attributes?.state
    }
    report.actions.push(`withdrew ${submission.id} (${state})`)
    console.log(`Withdrew submission ${submission.id}; state ${state}.`)
  }
}

// ---- the target version ---------------------------------------------------
let versions = await listVersions(client, app.id)
let target = versions.find((v) => v.attributes?.versionString === versionString)
if (target) {
  console.log(`Version ${versionString} exists (${target.attributes?.appStoreState ?? target.attributes?.state}).`)
} else if (!apply) {
  console.log(`Would create App Store version ${versionString} (IOS).`)
} else {
  const created = await client.post('/v1/appStoreVersions', {
    data: {
      type: 'appStoreVersions',
      attributes: { platform: 'IOS', versionString },
      relationships: { app: { data: { type: 'apps', id: app.id } } },
    },
  })
  target = created.data
  report.actions.push(`created version ${versionString} (${target.id})`)
  console.log(`Created App Store version ${versionString} (${target.id}).`)
}

// ---- the build to attach --------------------------------------------------
let buildToAttach = null
if (target) {
  const builds = await client.getAll(
    `/v1/builds?filter[app]=${app.id}&limit=50&include=preReleaseVersion&sort=-uploadedDate`)
  const preReleaseIds = new Map()
  for (const build of builds) {
    const id = build.relationships?.preReleaseVersion?.data?.id
    if (!id) continue
    if (!preReleaseIds.has(id)) {
      try {
        const pre = (await client.get(`/v1/preReleaseVersions/${id}`)).data
        preReleaseIds.set(id, pre.attributes?.version ?? null)
      } catch { preReleaseIds.set(id, null) }
    }
  }
  const candidates = builds.filter((b) => {
    const id = b.relationships?.preReleaseVersion?.data?.id
    return preReleaseIds.get(id) === versionString
      && b.attributes?.processingState === 'VALID' && b.attributes?.expired === false
  })
  buildToAttach = candidates[0] ?? null
  report.build = buildToAttach
    ? { id: buildToAttach.id, number: buildToAttach.attributes?.version, uploaded: buildToAttach.attributes?.uploadedDate }
    : null
  console.log(buildToAttach
    ? `Build to attach: ${versionString} (${buildToAttach.attributes?.version})`
    : `No VALID, unexpired ${versionString} build yet.`)

  const attached = (await client.get(`/v1/appStoreVersions/${target.id}/build`)).data
  if (attached?.id === buildToAttach?.id) {
    console.log('That build is already attached.')
  } else if (!apply) {
    console.log(`Would attach build ${buildToAttach?.attributes?.version ?? '(none)'} to version ${versionString}.`)
  } else if (buildToAttach) {
    await client.patch(`/v1/appStoreVersions/${target.id}/relationships/build`, {
      data: { type: 'builds', id: buildToAttach.id },
    })
    report.actions.push(`attached build ${buildToAttach.attributes?.version}`)
    console.log(`Attached build ${buildToAttach.attributes?.version} to version ${versionString}.`)
  }
}

// ---- the new submission ---------------------------------------------------
if (target && report.build) {
  if (reusable && !submit) {
    console.log(`Submission ${reusable.id} is prepared; nothing left to add here.`)
  } else if (!apply) {
    console.log(`Would create a submission with version ${versionString} and the ${productEntries.length} purchase item(s).`)
  } else {
    const submissionId = reusable?.id ?? (await client.post('/v1/reviewSubmissions', {
      data: {
        type: 'reviewSubmissions',
        attributes: { platform: 'IOS' },
        relationships: { app: { data: { type: 'apps', id: app.id } } },
      },
    })).data.id
    report.submission = { id: submissionId, reused: Boolean(reusable) }
    console.log(`${reusable ? 'Using' : 'Created'} submission ${submissionId}.`)

    const alreadyThere = new Set(
      report.carried.filter((c) => c.from === submissionId).map((c) => `${c.include}:${c.id}`))
    const addItem = async (relationship, id) => {
      if (alreadyThere.has(`${relationship}:${id}`)) {
        console.log(`  ${relationship} ${id} already in the submission`)
        return
      }
      await client.post('/v1/reviewSubmissionItems', {
        data: {
          type: 'reviewSubmissionItems',
          relationships: {
            reviewSubmission: { data: { type: 'reviewSubmissions', id: submissionId } },
            [relationship]: { data: { type: relationship, id } },
          },
        },
      })
      report.actions.push(`added ${relationship} ${id}`)
      console.log(`  added ${relationship} ${id}`)
    }

    await addItem('appStoreVersion', target.id)
    for (const entry of productEntries) await addItem(entry.include, entry.id)

    if (submit) {
      const submitted = await client.patch(`/v1/reviewSubmissions/${submissionId}`, {
        data: { type: 'reviewSubmissions', id: submissionId, attributes: { submitted: true } },
      })
      report.submission.state = submitted?.data?.attributes?.state
      report.actions.push(`submitted (${report.submission.state})`)
      console.log(`Submitted ${submissionId}; state ${report.submission.state}.`)
    }
  }
} else if (apply) {
  console.log('Skipped the submission: the version and a processed build are both required first.')
}

mkdirSync(join(root, 'apple-audit'), { recursive: true })
writeFileSync(join(root, 'apple-audit/resubmit-version.json'), JSON.stringify(report, null, 2) + '\n')
console.log(JSON.stringify({ mode: report.mode, actions: report.actions }, null, 2))
