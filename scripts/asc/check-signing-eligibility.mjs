#!/usr/bin/env node
// scripts/asc/check-signing-eligibility.mjs
//
// Can this team still sign a build? Asked on the 1x runner, because last time
// the answer came back from a 10x one.
//
// ## Why this exists
//
// Release run 6 (2026-09-05, `ec4ef84`, v1.0.12 build 4) failed in `Archive`
// on the macOS runner:
//
//   Communication with Apple failed: The selected team does not have a
//   program membership that is eligible for this feature.
//   No profiles for 'com.airlineempire.game' were found: Xcode couldn't find
//   any iOS App Development provisioning profiles matching
//   'com.airlineempire.game'.
//
// The second line is the consequence of the first: automatic signing had
// nothing to fall back on once Apple refused to mint anything. The release
// plumbing was byte-identical to run 5, which archived and signed cleanly five
// days earlier, and the same API key answered the preflight in the same run —
// app record found, next build number 4. So App Store Connect access was fine
// and *Developer Program membership* was not. They are separate systems, and
// nothing on the cheap runner was asking the second one anything.
//
// This is the third entry in the same pattern: `check-app-icon.mjs` and
// `check-bundle-config.mjs` both exist because Apple refused something after
// the archive was paid for. The rule the workflow states in its own header is
// that anything not needing Xcode runs on ubuntu; a question answerable by
// three authenticated GETs was being answered by a compile.
//
// ## What it asks Apple
//
//   1. `GET /v1/bundleIds?filter[identifier]=…`  — is the bundle id registered
//      in the Developer portal at all?
//   2. `GET /v1/bundleIds/{id}/profiles`         — is there an unexpired App
//      Store profile for it?
//   3. `GET /v1/certificates`                    — is there an unexpired
//      distribution certificate, and how close is the account to Apple's limit
//      of two?
//
// (1) is the point. It is the cheapest authenticated call into the
// *provisioning* half of the API — the half `preflight.mjs` never touches —
// and it is where a team that cannot sign should say so. (2) and (3) are free
// once the token is minted and answer the two questions the workflow header
// already warns about in prose.
//
// ## The blocking rule, and why it is this narrow
//
// Exit 1 on ONE thing: Apple's own words saying the team's membership is not
// eligible. Everything else — a 403, an unexpected shape, no profile, no
// certificate, a network failure — warns and passes.
//
// That asymmetry is deliberate and it is `preflight.mjs`'s rule, not a new
// one: block only on positive evidence that the release cannot work. A missing
// profile is not evidence — automatic signing creates profiles, which is the
// entire point of `-allowProvisioningUpdates`. An API key without provisioning
// access would 403 here and still archive perfectly well, so a 403 must never
// stop a release.
//
// ## What is measured and what is inferred
//
// MEASURED: the message in `MEMBERSHIP_MARKERS[0]`, from run 6's `xcodebuild`
// output, quoted above.
//
// INFERRED: that the REST API refuses the same team with the same words.
// `xcodebuild` talks to the Developer portal's own service, not to
// api.appstoreconnect.apple.com, and Apple does not promise the two phrase
// their refusals alike. The other markers are the wordings Apple uses for a
// lapsed or unaccepted membership; none of them has been seen from this
// account. So this check may find nothing on a team that genuinely cannot
// sign — in which case it costs one second and the archive fails exactly as it
// does today, no worse. It cannot produce a false block: for that, Apple has
// to say the words.
//
// Do not upgrade that claim without a run to point at
// (docs/RELEASE_PIPELINE.md).
//
// Usage:  node scripts/asc/check-signing-eligibility.mjs

import { readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { AppStoreConnect } from './lib/asc.mjs'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')

/**
 * Apple's ways of saying "this team's membership will not do".
 *
 * The first is verbatim from run 6. The rest are the wordings a lapsed or
 * unaccepted membership produces; they are here so that the *next* variant is
 * recognised rather than passed over, and they are matched case-insensitively
 * against every part of the error Apple sends.
 *
 * Keep this list to phrases that can only mean the membership. "Forbidden",
 * "not permitted" and "no access" are all things an under-privileged API key
 * says too, and blocking on those would stop releases that would have worked.
 */
export const MEMBERSHIP_MARKERS = [
  'program membership',
  'not eligible for this feature',
  'membership has expired',
  'membership is not active',
  'renew your membership',
  'accept the latest',
  'agreements are missing',
]

/**
 * The marker Apple's error matched, or null.
 *
 * Reads title, detail and code from every error in a JSON:API response, plus
 * the message the client composed, because Apple puts the useful sentence in a
 * different one of those depending on the endpoint.
 */
export function membershipRefusal(error) {
  const haystack = [
    error?.message ?? '',
    ...(Array.isArray(error?.errors)
      ? error.errors.flatMap((item) => [item?.title ?? '', item?.detail ?? '', item?.code ?? ''])
      : []),
  ]
    .join('\n')
    .toLowerCase()

  return MEMBERSHIP_MARKERS.find((marker) => haystack.includes(marker)) ?? null
}

/** Apple issues at most two distribution certificates per account. */
export const DISTRIBUTION_CERTIFICATE_LIMIT = 2

const DISTRIBUTION_TYPES = new Set(['DISTRIBUTION', 'IOS_DISTRIBUTION'])
const APP_STORE_PROFILE_TYPES = new Set(['IOS_APP_STORE'])

function expired(attributes, now) {
  const raw = attributes?.expirationDate
  if (!raw) return false
  const at = Date.parse(raw)
  return Number.isFinite(at) && at <= now
}

/**
 * What the account's distribution certificates say about the next archive.
 *
 * Two notes worth having before a 10x runner starts: none at all (automatic
 * signing must create one, which needs the membership this file is about), and
 * both slots used (it cannot create one, and an ephemeral runner cannot reuse
 * the certificate it made last time — the hazard the workflow header spells
 * out in prose and nothing checked).
 */
export function auditCertificates(certificates, { now = Date.now() } = {}) {
  const warnings = []
  const distribution = certificates.filter((certificate) =>
    DISTRIBUTION_TYPES.has(certificate?.attributes?.certificateType),
  )
  const live = distribution.filter((certificate) => !expired(certificate.attributes, now))

  if (!distribution.length) {
    warnings.push(
      'No distribution certificate exists on this account. Automatic signing will try to create one, ' +
        'which needs an active Developer Program membership.',
    )
  } else if (!live.length) {
    warnings.push(
      `All ${distribution.length} distribution certificate(s) on this account have expired. ` +
        'Automatic signing will try to replace one.',
    )
  } else if (live.length >= DISTRIBUTION_CERTIFICATE_LIMIT) {
    warnings.push(
      `${live.length} distribution certificates exist and Apple allows ${DISTRIBUTION_CERTIFICATE_LIMIT}. ` +
        'Automatic signing cannot create another, and an ephemeral runner cannot reuse the one it made ' +
        'last time — see docs/APP_STORE_CONNECT.md §4 on moving to manual signing.',
    )
  }
  return { live: live.length, total: distribution.length, warnings }
}

/**
 * Whether an App Store profile exists for this bundle id.
 *
 * A note, never a problem: `-allowProvisioningUpdates` exists to create these,
 * and runs 2, 4 and 5 all archived without one being pre-made.
 */
export function auditProfiles(profiles, { now = Date.now() } = {}) {
  const appStore = profiles.filter((profile) => APP_STORE_PROFILE_TYPES.has(profile?.attributes?.profileType))
  const live = appStore.filter(
    (profile) => !expired(profile.attributes, now) && profile?.attributes?.profileState !== 'INVALID',
  )
  return { live: live.length, total: appStore.length }
}

// ---------------------------------------------------------------------------

async function main() {
  const config = JSON.parse(readFileSync(join(REPO_ROOT, 'store', 'config.json'), 'utf8'))
  const bundleId = process.env.BUNDLE_ID?.trim() || config.bundleId

  let client
  try {
    client = AppStoreConnect.fromEnv()
  } catch (error) {
    // Not this file's job to report: `preflight.mjs` runs first in the same
    // job and fails hard on a missing secret, with the instructions.
    return inconclusive(error.message)
  }

  let registered
  try {
    const page = await client.get(`/v1/bundleIds?filter[identifier]=${encodeURIComponent(bundleId)}&limit=10`)
    registered = (page?.data ?? []).find((entry) => entry.attributes?.identifier === bundleId) ?? null
  } catch (error) {
    return refusalOrInconclusive(error, 'the Developer portal bundle id lookup')
  }

  if (!registered) {
    // Not fatal. Automatic signing registers the bundle id on first use, which
    // is how it came to exist for runs 2, 4 and 5.
    console.warn(`⚠︎ Bundle id ${bundleId} is not registered in the Developer portal.`)
    console.warn('  Automatic signing will register it, which needs an active membership.')
  } else {
    console.log(`✓ Developer portal reachable, and ${bundleId} is registered (id ${registered.id}).`)
  }

  if (registered) {
    try {
      const page = await client.get(`/v1/bundleIds/${registered.id}/profiles?limit=200`)
      const { live, total } = auditProfiles(page?.data ?? [])
      console.log(
        total
          ? `  · ${live} of ${total} App Store profile(s) for this bundle id are usable.`
          : '  · No App Store profile yet; automatic signing will create one.',
      )
    } catch (error) {
      const marker = membershipRefusal(error)
      if (marker) return blocked(marker, error, 'the provisioning profile lookup')
      console.warn(`⚠︎ Could not read provisioning profiles — ${error.message}`)
    }
  }

  try {
    const page = await client.get(`/v1/certificates?limit=200`)
    const { live, total, warnings } = auditCertificates(page?.data ?? [])
    console.log(`  · ${live} of ${total} distribution certificate(s) are unexpired.`)
    for (const warning of warnings) console.warn(`⚠︎ ${warning}`)
  } catch (error) {
    const marker = membershipRefusal(error)
    if (marker) return blocked(marker, error, 'the certificate lookup')
    console.warn(`⚠︎ Could not read certificates — ${error.message}`)
  }

  console.log('\n✓ Nothing here says this team cannot sign a build.')
}

function refusalOrInconclusive(error, what) {
  const marker = membershipRefusal(error)
  if (marker) return blocked(marker, error, what)
  return inconclusive(`${what} failed — ${error.message}`)
}

function inconclusive(reason) {
  console.warn(`⚠︎ signing eligibility could not be established: ${reason}`)
  console.warn('  Passing anyway — the archive itself remains the source of truth.')
  process.exit(0)
}

/** The one exit-1: Apple said the membership is the problem. */
function blocked(marker, error, what) {
  console.error(`✗ Apple refused ${what}: the team's Developer Program membership is not eligible.`)
  console.error(`  Matched: "${marker}"`)
  console.error(`  ${error.message}`)
  console.error('')
  console.error('  This is an account state, not a code or pipeline problem. In order:')
  console.error('   1. developer.apple.com/account → Membership details. Active? Expired?')
  console.error('      Any banner asking the Account Holder to accept an updated Program')
  console.error('      License Agreement? A pending agreement refuses provisioning while')
  console.error('      App Store Connect keeps answering normally.')
  console.error('   2. App Store Connect → Business / Agreements — anything to review.')
  console.error('   3. APPLE_TEAM_ID must name the paid team, not a Personal Team.')
  console.error('   4. The API key needs App Manager or Admin to create signing assets.')
  console.error('')
  console.error('  Manual signing is not a way round this: the certificate and profile it')
  console.error('  wants have to be issued by the same membership. The full checklist is')
  console.error('  docs/APP_STORE_CONNECT.md §1; manual signing is §4.')
  process.exit(1)
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await main()
}
