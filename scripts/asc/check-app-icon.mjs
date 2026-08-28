#!/usr/bin/env node
// scripts/asc/check-app-icon.mjs
//
// Exit non-zero if the app icon would be rejected by App Store Connect.
//
// Run on the cheap runner before an upload. A missing or transparent icon is
// the most common reason a first submission fails, and it fails at the very
// end — after the archive, the export and the transfer, as an email. The
// check itself takes milliseconds and reads the PNG header.
//
// `validate-metadata.mjs` reports the same problems as warnings, because a
// pull request should not go red over an asset nobody has drawn yet. This is
// the version with teeth, for the moment a build is about to be uploaded.

import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { checkAppIcon } from './lib/metadata.mjs'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
const problems = checkAppIcon(REPO_ROOT)

if (problems.length) {
  console.error('✗ The app icon is not submittable:\n')
  for (const problem of problems) console.error(`  · ${problem}`)
  console.error('\n  Brief and slot: AirlineEmpireApp/Resources/README.md · docs/ASO.md §6')
  process.exit(1)
}
console.log('✓ App icon present, 1024×1024, no alpha.')
