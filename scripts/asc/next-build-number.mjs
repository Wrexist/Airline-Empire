#!/usr/bin/env node
// scripts/asc/next-build-number.mjs
//
// The next CFBundleVersion: strictly higher than anything App Store Connect
// has already seen for this bundle id.
//
// ## Why this is not just `github.run_number`
//
// Apple rejects an upload whose build number it already holds for the same
// marketing version ("The bundle version must be higher than the previously
// uploaded version"). A run number restarts at 1 when a workflow is renamed or
// recreated, and it knows nothing about builds uploaded by hand from someone's
// Mac — both of which produce a collision that is only discovered after the
// archive has been paid for on a 10x-billed macOS runner.
//
// Asking Apple is the only answer that is right by construction.
//
// Resolution order:
//   1. App Store Connect — the highest `version` across every build on record
//      for the app, plus one. Requires the three APP_STORE_CONNECT_* secrets
//      and an app record that already exists.
//   2. Epoch seconds — monotonic, always larger than any small historical
//      build number, and available with no credentials at all. Used when the
//      lookup cannot be made or the app record does not exist yet (which is
//      the state this repository is in as of 2026-08-28).
//
// The fallback is deliberate rather than lazy: a build must not be blocked
// because Apple is unreachable, and both branches satisfy the only property
// that matters — the number goes up.
//
// Output contract: the chosen integer on stdout and nothing else, so it is
// safe to capture with `BUILD=$(node scripts/asc/next-build-number.mjs)`.
// Diagnostics go to stderr.
//
// Ported from Wrexist/WorldQuest's script of the same name, which has run
// against the live API; the difference here is that Airline Empire has no
// eas.json to read an app id from, so the app is resolved from the bundle id
// in store/config.json.

import { readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { AppStoreConnect, findApp } from './lib/asc.mjs'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
const log = (...args) => console.error('[next-build-number]', ...args)

/** Monotonic and always unique; the number of seconds since the epoch. */
function fallback(reason) {
  const value = Math.floor(Date.now() / 1000)
  log(`falling back to epoch seconds (${reason}) → ${value}`)
  console.log(value)
  process.exit(0)
}

const bundleId =
  process.env.BUNDLE_ID?.trim() ||
  JSON.parse(readFileSync(join(REPO_ROOT, 'store', 'config.json'), 'utf8')).bundleId

let client
try {
  client = AppStoreConnect.fromEnv()
} catch (error) {
  fallback(error.message)
}

try {
  const app = await findApp(client, bundleId)
  if (!app) fallback(`no App Store Connect app record for ${bundleId}`)

  // Every build Apple holds, newest first. `filter[app]` plus a sort on
  // version would be neater, but `version` sorts lexically on Apple's side
  // ("9" > "10"), so the numbers are compared here instead.
  const builds = await client.getAll(`/v1/builds?filter[app]=${app.id}&limit=200&fields[builds]=version`)
  const highest = builds
    .map((build) => Number.parseInt(build.attributes?.version ?? '', 10))
    .filter((value) => Number.isFinite(value))
    .reduce((max, value) => Math.max(max, value), 0)

  if (highest === 0 && builds.length > 0) {
    // Non-numeric build numbers (someone used "1.0.3" as CFBundleVersion at
    // some point). Comparing against them is meaningless, so don't pretend.
    fallback(`App Store Connect has ${builds.length} build(s) but no numeric version among them`)
  }

  log(`App Store Connect holds ${builds.length} build(s); highest numeric version ${highest}`)
  console.log(highest + 1)
} catch (error) {
  fallback(`lookup failed — ${error.message}`)
}
