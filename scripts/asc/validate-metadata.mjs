#!/usr/bin/env node
// scripts/asc/validate-metadata.mjs
//
// Check the store listing against Apple's limits and this repo's own rules,
// offline. No secrets, no network, no Apple account — which is the point: it
// runs on every pull request, and it is the only part of the release pipeline
// that can run today, from Linux, before anyone owns an App Store Connect
// account at all.
//
// Exit codes: 0 clean (warnings do not fail), 1 at least one error.
//
// Usage:
//   node scripts/asc/validate-metadata.mjs            # store/ at the repo root
//   node scripts/asc/validate-metadata.mjs --root x   # somewhere else
//   node scripts/asc/validate-metadata.mjs --strict   # warnings fail too
//   node scripts/asc/validate-metadata.mjs --allow-placeholders
//                                                     # REPLACE_ME is a warning,
//                                                     # not an error (what CI runs
//                                                     # on a pull request)

import { fileURLToPath } from 'node:url'
import { dirname, join, resolve } from 'node:path'
import { loadStore, validateStore, LIMITS } from './lib/metadata.mjs'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')

const args = process.argv.slice(2)
const strict = args.includes('--strict')
const allowPlaceholders = args.includes('--allow-placeholders')
const rootIndex = args.indexOf('--root')
const storeRoot = rootIndex === -1 ? join(REPO_ROOT, 'store') : resolve(args[rootIndex + 1])

let store
try {
  store = loadStore(storeRoot)
} catch (cause) {
  console.error(`✗ Could not read the store listing at ${storeRoot}\n  ${cause.message}`)
  process.exit(1)
}

const { errors, warnings } = validateStore(store, { allowPlaceholders })

// A budget line per locale, printed on success as well as failure. Character
// counts are the whole game in ASO copy — the keyword field in particular is
// fixed ranking surface, and "94 of 100 used" is the number a person editing
// this copy actually wants to see.
for (const locale of Object.keys(store.locales).sort()) {
  const fields = store.locales[locale]
  const budget = ['name', 'subtitle', 'keywords', 'promotional_text', 'description']
    .filter((key) => fields[key] !== undefined)
    .map((key) => `${key} ${fields[key].length}/${LIMITS[key]}`)
    .join('  ·  ')
  const shots = store.screenshots[locale]
  const shotSummary = shots
    ? Object.entries(shots)
        .map(([type, files]) => `${type} ×${files.length}`)
        .join(', ')
    : 'no screenshots'
  console.log(`${locale}\n  ${budget}\n  ${shotSummary}`)
}

for (const warning of warnings) console.log(`⚠︎ ${warning}`)
for (const error of errors) console.error(`✗ ${error}`)

if (errors.length) {
  console.error(`\n${errors.length} error(s), ${warnings.length} warning(s). The listing would be rejected or truncated.`)
  process.exit(1)
}
if (strict && warnings.length) {
  console.error(`\n${warnings.length} warning(s) and --strict was passed.`)
  process.exit(1)
}
console.log(`\n✓ Listing is valid. ${warnings.length} warning(s).`)
