#!/usr/bin/env node
// scripts/asc/wait-for-processing.mjs
//
// Poll App Store Connect until an uploaded build finishes processing, then say
// what happened to it.
//
// ## Why this is a separate job on a cheap runner
//
// `xcrun altool --upload-app` returns when the bytes are transferred, not when
// the build is usable: Apple then processes it for anywhere between two
// minutes and half an hour, and the interesting failures happen in that
// window — an invalid binary, a missing icon, an entitlement the account is
// not allowed to use. None of those show up in the archive job's log.
//
// Waiting for it there would mean holding a macOS runner idle at ten times the
// billing rate. WorldQuest measured that exact mistake: 53 minutes of pure
// waiting on a 10x runner, 73% of the job, for a state change that needed
// nothing from the machine. So the wait lives here, on ubuntu, and the only
// thing it needs is an HTTPS connection.
//
// Usage:
//   node scripts/asc/wait-for-processing.mjs --version 1.0.0 --build 42
//   node scripts/asc/wait-for-processing.mjs --version 1.0.0 --build 42 --timeout 45
//
// Exit 0 when the build reaches VALID, 1 when Apple reports INVALID or the
// wait times out.
//
// NEVER EXECUTED against Apple from this repository — see docs/RELEASE_PIPELINE.md.

import { readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { AppStoreConnect, findApp, sleep } from './lib/asc.mjs'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
const args = process.argv.slice(2)
const valueOf = (flag, fallback = null) => {
  const index = args.indexOf(flag)
  return index === -1 ? fallback : args[index + 1]
}

const versionString = valueOf('--version')
const buildNumber = valueOf('--build')
const timeoutMinutes = Number.parseInt(valueOf('--timeout', '40'), 10)
const POLL_SECONDS = 60

if (!versionString || !buildNumber) {
  console.error('Usage: node scripts/asc/wait-for-processing.mjs --version <x.y.z> --build <n> [--timeout <minutes>]')
  process.exit(2)
}

const config = JSON.parse(readFileSync(join(REPO_ROOT, 'store', 'config.json'), 'utf8'))
const client = AppStoreConnect.fromEnv()
const app = await findApp(client, process.env.BUNDLE_ID?.trim() || config.bundleId)
if (!app) {
  console.error(`✗ No app record for ${config.bundleId}; nothing to wait for.`)
  process.exit(1)
}

const deadline = Date.now() + timeoutMinutes * 60_000
let lastState = null

while (Date.now() < deadline) {
  const builds = await client.getAll(
    `/v1/builds?filter[app]=${app.id}&filter[preReleaseVersion.version]=${encodeURIComponent(versionString)}` +
      `&filter[version]=${encodeURIComponent(buildNumber)}&limit=10` +
      '&fields[builds]=version,processingState,expired,uploadedDate,usesNonExemptEncryption',
  )
  const build = builds[0]

  if (!build) {
    // Apple takes a minute or two to make a just-uploaded build visible on
    // the API. Absence early in the wait is normal; absence at the end is not.
    console.log('… build not visible in App Store Connect yet')
  } else {
    const state = build.attributes?.processingState
    if (state !== lastState) {
      console.log(`… ${versionString} (${buildNumber}): ${state}`)
      lastState = state
    }

    if (state === 'VALID') {
      console.log(`\n✓ Build ${buildNumber} processed and is available in TestFlight.`)
      // Worth surfacing: a build that reaches VALID but reports missing
      // export-compliance data still cannot be distributed to testers without
      // someone answering a questionnaire in the web UI. project.yml sets
      // ITSAppUsesNonExemptEncryption so this should read false, not null.
      const encryption = build.attributes?.usesNonExemptEncryption
      if (encryption === null || encryption === undefined) {
        console.warn('⚠︎ Export compliance is unanswered on this build — TestFlight will ask before distributing it.')
        console.warn('  INFOPLIST_KEY_ITSAppUsesNonExemptEncryption in AirlineEmpireApp/project.yml is what avoids that.')
      }
      process.exit(0)
    }

    if (state === 'INVALID' || state === 'FAILED') {
      console.error(`\n✗ Apple rejected build ${buildNumber} during processing (${state}).`)
      console.error('  The reason arrives by email to the account holder and appears in App Store Connect')
      console.error('  under TestFlight → Builds. Common causes: a missing app icon, an unsupported')
      console.error('  entitlement, or an SDK version Apple no longer accepts.')
      process.exit(1)
    }
  }

  await sleep(POLL_SECONDS * 1000)
}

console.error(`\n✗ Build ${buildNumber} was still not VALID after ${timeoutMinutes} minutes.`)
console.error('  That is unusual but not necessarily fatal — check App Store Connect directly.')
process.exit(1)
