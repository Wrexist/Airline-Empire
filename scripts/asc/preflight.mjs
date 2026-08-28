#!/usr/bin/env node
// scripts/asc/preflight.mjs
//
// Everything about a release that can be checked in five seconds on a cheap
// runner, checked before the expensive one starts.
//
// ## Why it exists
//
// A macOS runner bills at ten times an ubuntu one. WorldQuest measured the
// shape of this exactly: an iOS release job that compiles for ~17 minutes and
// then fails at the submit step has spent the entire bill to discover a
// missing secret. Every question below is answerable without Xcode, without a
// checkout of the toolchain, and without compiling anything:
//
//   1. Are the three App Store Connect secrets present, and does the .p8
//      actually decode to a private key?
//   2. Does Apple accept the JWT they produce? (One authenticated GET.)
//   3. Does an app record exist for this bundle id?
//   4. Is there an App Store version in a state that accepts a new build?
//   5. Does the marketing version we are about to ship already exist there —
//      i.e. is this the "You've already submitted this version" rejection,
//      twenty minutes early?
//
// ## Fail-open, except where it can be sure
//
// The rule WorldQuest's `check-ios-credentials.mjs` established, and it holds
// here: exit non-zero only on positive evidence that the release cannot work.
// A network failure, an unexpected response shape, an endpoint Apple changed —
// warn and pass, because a preflight that blocks a release for a reason it
// cannot articulate is worse than no preflight. Missing secrets are the one
// unambiguous case, and they are a hard failure.
//
// Usage:
//   node scripts/asc/preflight.mjs                 # credentials + app record
//   node scripts/asc/preflight.mjs --version 1.0.0 # also check that version
//
// NEVER EXECUTED against Apple from this repository — see docs/RELEASE_PIPELINE.md.

import { readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { AppStoreConnect, findApp, listVersions, versionState, EDITABLE_VERSION_STATES } from './lib/asc.mjs'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
const args = process.argv.slice(2)
const versionIndex = args.indexOf('--version')
const wantedVersion = versionIndex === -1 ? null : args[versionIndex + 1]

const config = JSON.parse(readFileSync(join(REPO_ROOT, 'store', 'config.json'), 'utf8'))
const bundleId = process.env.BUNDLE_ID?.trim() || config.bundleId

const problems = []
const notes = []

function inconclusive(reason) {
  console.warn(`⚠︎ preflight could not finish: ${reason}`)
  console.warn('  Passing anyway — the build itself remains the source of truth.')
  process.exit(0)
}

let client
try {
  client = AppStoreConnect.fromEnv()
} catch (error) {
  // The one hard failure. A missing secret cannot become present later in the
  // run, and every downstream step needs it.
  console.error(`✗ ${error.message}`)
  console.error('  Add them under Settings → Secrets and variables → Actions.')
  console.error('  What each one is and where it comes from: docs/APP_STORE_CONNECT.md.')
  process.exit(1)
}
console.log('✓ All three App Store Connect secrets are present and the key decodes to a PEM.')

let app
try {
  // Also the authentication test: a bad key id, issuer or .p8 fails here with
  // a 401 rather than anywhere more expensive.
  app = await findApp(client, bundleId)
} catch (error) {
  if (error.status === 401 || error.status === 403) {
    console.error(`✗ Apple rejected the API key (HTTP ${error.status}).`)
    console.error('  Check that the key id, issuer id and .p8 all come from the SAME key,')
    console.error('  and that the key has at least the App Manager role.')
    console.error(`  ${error.message}`)
    process.exit(1)
  }
  inconclusive(error.message)
}

if (!app) {
  // Not a failure: this is exactly the state before the app record is created,
  // and a build can still be produced and archived. It cannot be uploaded.
  console.warn(`⚠︎ No App Store Connect app record for bundle id ${bundleId}.`)
  console.warn('  An upload will fail until one exists. Create it once:')
  console.warn('  App Store Connect → Apps → + → New App. docs/APP_STORE_CONNECT.md §2.')
  process.exit(0)
}
console.log(`✓ App record found: "${app.attributes?.name}" (id ${app.id}, SKU ${app.attributes?.sku ?? '—'}).`)

try {
  const ios = await listVersions(client, app.id, { fields: ['createdDate'], limit: 20 })

  if (!ios.length) {
    notes.push('No App Store version exists yet. `push-metadata.mjs --apply` will create one.')
  } else {
    for (const version of ios.slice(0, 5)) {
      console.log(`  · ${version.attributes?.versionString} — ${versionState(version)}`)
    }
  }

  if (wantedVersion) {
    const existing = ios.find((version) => version.attributes?.versionString === wantedVersion)
    if (!existing) {
      notes.push(`Version ${wantedVersion} does not exist yet; it will be created on the first metadata push.`)
    } else if (EDITABLE_VERSION_STATES.has(versionState(existing))) {
      console.log(`✓ Version ${wantedVersion} exists and is editable (${versionState(existing)}).`)
    } else {
      // The expensive mistake this catches: shipping a build for a version
      // Apple has already released. The archive would succeed and the upload
      // would be refused.
      problems.push(
        `Version ${wantedVersion} is in state ${versionState(existing)}, which does not accept a new build or metadata.\n` +
          '  Bump the marketing version for this release.',
      )
    }
  }
} catch (error) {
  inconclusive(`version lookup failed — ${error.message}`)
}

for (const note of notes) console.log(`  note: ${note}`)

if (problems.length) {
  console.error('')
  for (const problem of problems) console.error(`✗ ${problem}`)
  process.exit(1)
}
console.log('\n✓ Preflight clear.')
