#!/usr/bin/env node
// scripts/asc/selftest.mjs
//
// Tests for the release tooling, runnable anywhere Node runs: no Apple
// account, no network, no macOS.
//
// ## Why this exists
//
// Master plan rule 5: nothing is done because it compiles. This directory is
// the part of the release path that CAN be tested from Linux today, and the
// parts that cannot — every request to Apple — are at least tested for the
// things that are provably wrong before they leave: a JWT whose signature does
// not verify, a listing over a character limit, a screenshot with an alpha
// channel, a paginated response read only to its first page.
//
// What this does NOT prove is that Apple accepts any of it. That claim needs a
// run, and docs/RELEASE_PIPELINE.md records which paths have had one.
//
// Run: node scripts/asc/selftest.mjs

import crypto from 'node:crypto'
import { mkdtempSync, writeFileSync, mkdirSync, rmSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { Buffer } from 'node:buffer'

import { decodePrivateKey, credentialsFromEnv, mintToken, AppStoreConnect, AscError } from './lib/asc.mjs'
import { loadStore, validateStore, checkBundleIdConsistency, checkAppIcon, inspectPng, LIMITS } from './lib/metadata.mjs'
import { checkBundleConfig } from './check-bundle-config.mjs'
import {
  membershipRefusal,
  auditCertificates,
  auditProfiles,
  DISTRIBUTION_CERTIFICATE_LIMIT,
} from './check-signing-eligibility.mjs'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')

let passed = 0
const failures = []

function test(name, body) {
  try {
    const result = body()
    if (result instanceof Promise) throw new Error('use `asyncTest` for async bodies')
    passed += 1
  } catch (error) {
    failures.push(`${name}\n    ${error.message}`)
  }
}

async function asyncTest(name, body) {
  try {
    await body()
    passed += 1
  } catch (error) {
    failures.push(`${name}\n    ${error.message}`)
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

function assertIncludes(list, needle, message) {
  assert(
    list.some((item) => item.includes(needle)),
    `${message}\n    got: ${list.length ? list.join('\n         ') : '(nothing)'}`,
  )
}

// ---------------------------------------------------------------------------
// Credentials and JWT
// ---------------------------------------------------------------------------

const { privateKey: testKeyObject, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' })
const testPem = testKeyObject.export({ type: 'pkcs8', format: 'pem' })

test('decodePrivateKey accepts raw PEM', () => {
  assert(decodePrivateKey(testPem)?.includes('BEGIN PRIVATE KEY'), 'raw PEM was not accepted')
})

test('decodePrivateKey accepts base64-wrapped PEM', () => {
  const base64 = Buffer.from(testPem).toString('base64')
  assert(decodePrivateKey(base64)?.includes('BEGIN PRIVATE KEY'), 'base64 PEM was not accepted')
})

test('decodePrivateKey survives a Windows CRLF paste', () => {
  const crlf = testPem.replace(/\n/g, '\r\n')
  assert(decodePrivateKey(crlf)?.includes('BEGIN PRIVATE KEY'), 'CRLF PEM was not accepted')
})

test('decodePrivateKey rejects a value that is not a key', () => {
  assert(decodePrivateKey('hello') === null, 'garbage was accepted as a private key')
  assert(decodePrivateKey('') === null, 'empty string was accepted as a private key')
})

test('credentialsFromEnv names every missing secret', () => {
  const { missing } = credentialsFromEnv({})
  assert(missing.length === 3, `expected 3 missing secrets, got ${missing.length}`)
  assertIncludes(missing, 'APP_STORE_CONNECT_KEY_ID', 'key id not reported missing')
  assertIncludes(missing, 'APP_STORE_CONNECT_ISSUER_ID', 'issuer id not reported missing')
})

test('credentialsFromEnv distinguishes "set but undecodable" from "absent"', () => {
  const { missing } = credentialsFromEnv({
    APP_STORE_CONNECT_KEY_ID: 'K',
    APP_STORE_CONNECT_ISSUER_ID: 'I',
    APP_STORE_CONNECT_API_KEY_BASE64: 'not-a-key',
  })
  assertIncludes(missing, 'did not decode', 'an undecodable key was reported as simply missing')
})

test('mintToken produces a token Apple could verify', () => {
  const token = mintToken({ keyId: 'ABC123XYZ9', issuerId: 'issuer-uuid', privateKey: testPem })
  const [headerPart, payloadPart, signaturePart] = token.split('.')
  assert(headerPart && payloadPart && signaturePart, 'token is not three dot-separated parts')

  const decode = (part) => JSON.parse(Buffer.from(part.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8'))
  const header = decode(headerPart)
  const payload = decode(payloadPart)

  assert(header.alg === 'ES256', `alg was ${header.alg}`)
  assert(header.kid === 'ABC123XYZ9', 'kid is not the key id')
  assert(payload.aud === 'appstoreconnect-v1', `aud was ${payload.aud}`)
  assert(payload.iss === 'issuer-uuid', 'iss is not the issuer id')
  assert(payload.exp - payload.iat <= 20 * 60, 'token lifetime exceeds the 20 minutes Apple allows')

  // The bug this catches is the expensive one: a DER-encoded signature is a
  // perfectly well-formed token that Apple answers with a bare 401.
  const signature = Buffer.from(signaturePart.replace(/-/g, '+').replace(/_/g, '/'), 'base64')
  assert(signature.length === 64, `ES256 signature must be 64 raw bytes, got ${signature.length}`)
  const verified = crypto.verify('sha256', Buffer.from(`${headerPart}.${payloadPart}`), {
    key: publicKey,
    dsaEncoding: 'ieee-p1363',
  }, signature)
  assert(verified, 'signature does not verify against the public key')
})

// ---------------------------------------------------------------------------
// HTTP client behaviour, against a stubbed fetch
// ---------------------------------------------------------------------------

const realFetch = globalThis.fetch

function stubFetch(handler) {
  globalThis.fetch = async (url, options) => handler(String(url), options)
}

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

const stubClient = () => new AppStoreConnect({ keyId: 'K', issuerId: 'I', privateKey: testPem })

await asyncTest('getAll follows links.next to the end', async () => {
  stubFetch((url) =>
    url.includes('cursor=2')
      ? jsonResponse(200, { data: [{ id: '3' }] })
      : jsonResponse(200, { data: [{ id: '1' }, { id: '2' }], links: { next: 'https://api.appstoreconnect.apple.com/v1/x?cursor=2' } }),
  )
  const items = await stubClient().getAll('/v1/x')
  assert(items.length === 3, `expected 3 items across two pages, got ${items.length}`)
})

await asyncTest('a 400 is raised immediately, with Apple\'s own detail', async () => {
  let calls = 0
  stubFetch(() => {
    calls += 1
    return jsonResponse(400, { errors: [{ title: 'A field is invalid', detail: 'keywords is too long' }] })
  })
  let thrown = null
  try {
    await stubClient().get('/v1/x')
  } catch (error) {
    thrown = error
  }
  assert(thrown instanceof AscError, 'a 400 did not raise an AscError')
  assert(calls === 1, `a 400 was retried ${calls} times; it should not be retried at all`)
  assert(thrown.message.includes('keywords is too long'), 'Apple\'s error detail was not surfaced')
})

await asyncTest('the bearer token never leaves App Store Connect', async () => {
  const hosts = new Map()
  stubFetch((url, options) => {
    hosts.set(new URL(url).host, options?.headers?.Authorization ?? null)
    return jsonResponse(200, { data: [] })
  })
  await stubClient().get('/v1/x')
  assert(hosts.get('api.appstoreconnect.apple.com')?.startsWith('Bearer '), 'no bearer token was sent to Apple')
})

globalThis.fetch = realFetch

// ---------------------------------------------------------------------------
// Signing eligibility
// ---------------------------------------------------------------------------

/** Run 6's message, verbatim, as `xcodebuild` printed it. */
const RUN_6_REFUSAL =
  'Communication with Apple failed: The selected team does not have a program ' +
  'membership that is eligible for this feature.'

test('the message that failed release run 6 is recognised', () => {
  assert(
    membershipRefusal(new Error(RUN_6_REFUSAL)) === 'program membership',
    'the one message this check exists for was not matched',
  )
})

test('a refusal is found in Apple JSON:API errors, not just the message', () => {
  const error = new AscError(403, 'GET', '/v1/bundleIds', {
    errors: [{ status: '403', code: 'FORBIDDEN_ERROR', title: 'Access denied', detail: 'Your membership has expired.' }],
  })
  assert(membershipRefusal(error) === 'membership has expired', 'the detail field was not read')
})

test('an ordinary permission failure is NOT read as a membership refusal', () => {
  // The false block this check must never produce: an API key without
  // provisioning access 403s here and archives perfectly well.
  const error = new AscError(403, 'GET', '/v1/certificates', {
    errors: [{ status: '403', code: 'FORBIDDEN_ERROR', title: 'Forbidden', detail: 'The request is not permitted.' }],
  })
  assert(membershipRefusal(error) === null, `a plain 403 would have blocked a release: ${membershipRefusal(error)}`)
})

test('neither a 401 nor a network failure reads as a membership refusal', () => {
  assert(membershipRefusal(new AscError(401, 'GET', '/v1/bundleIds', {})) === null, '401 blocked')
  assert(membershipRefusal(new Error('fetch failed')) === null, 'a network error blocked')
})

test('both distribution certificate slots in use is warned about before the 10x runner', () => {
  const certificate = (attributes) => ({ attributes: { certificateType: 'DISTRIBUTION', ...attributes } })
  const { live, warnings } = auditCertificates([certificate({}), certificate({})])
  assert(live === DISTRIBUTION_CERTIFICATE_LIMIT, `expected 2 live certificates, got ${live}`)
  assertIncludes(warnings, 'cannot create another', 'the certificate limit drew no warning')
})

test('an expired certificate does not count against the limit', () => {
  const certificates = [
    { attributes: { certificateType: 'DISTRIBUTION', expirationDate: '2020-01-01T00:00:00Z' } },
    { attributes: { certificateType: 'DISTRIBUTION' } },
  ]
  const { live, total, warnings } = auditCertificates(certificates)
  assert(live === 1 && total === 2, `expected 1 live of 2, got ${live} of ${total}`)
  assert(warnings.length === 0, `a healthy account was warned about: ${warnings.join(' ')}`)
})

test('development certificates are not counted as distribution ones', () => {
  const { total, warnings } = auditCertificates([{ attributes: { certificateType: 'DEVELOPMENT' } }])
  assert(total === 0, `a development certificate was counted: ${total}`)
  assertIncludes(warnings, 'No distribution certificate', 'an account with no distribution certificate said nothing')
})

test('only usable App Store profiles are counted', () => {
  const profiles = [
    { attributes: { profileType: 'IOS_APP_STORE', profileState: 'ACTIVE' } },
    { attributes: { profileType: 'IOS_APP_STORE', profileState: 'INVALID' } },
    { attributes: { profileType: 'IOS_APP_STORE', expirationDate: '2020-01-01T00:00:00Z' } },
    { attributes: { profileType: 'IOS_APP_DEVELOPMENT', profileState: 'ACTIVE' } },
  ]
  const { live, total } = auditProfiles(profiles)
  assert(total === 3 && live === 1, `expected 1 usable of 3 App Store profiles, got ${live} of ${total}`)
})

// ---------------------------------------------------------------------------
// PNG inspection
// ---------------------------------------------------------------------------

const scratch = mkdtempSync(join(tmpdir(), 'ae-selftest-'))

/** A PNG header only — `inspectPng` reads nothing past IHDR by design. */
function writePngHeader(path, { width, height, colorType }) {
  const buffer = Buffer.alloc(33)
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(buffer, 0)
  buffer.writeUInt32BE(13, 8)
  buffer.write('IHDR', 12, 'ascii')
  buffer.writeUInt32BE(width, 16)
  buffer.writeUInt32BE(height, 20)
  buffer.writeUInt8(8, 24) // bit depth
  buffer.writeUInt8(colorType, 25)
  writeFileSync(path, buffer)
  return path
}

test('inspectPng reads dimensions and spots an alpha channel', () => {
  const opaque = writePngHeader(join(scratch, 'opaque.png'), { width: 1320, height: 2868, colorType: 2 })
  const transparent = writePngHeader(join(scratch, 'alpha.png'), { width: 1320, height: 2868, colorType: 6 })
  assert(inspectPng(opaque).width === 1320 && inspectPng(opaque).height === 2868, 'dimensions were misread')
  assert(inspectPng(opaque).hasAlpha === false, 'an opaque PNG was reported as having alpha')
  assert(inspectPng(transparent).hasAlpha === true, 'a PNG with alpha was reported as opaque')
  writeFileSync(join(scratch, 'not.png'), 'hello')
  assert(inspectPng(join(scratch, 'not.png')) === null, 'a non-PNG was parsed as a PNG')
})

// ---------------------------------------------------------------------------
// The listing validator, against the real tree and against deliberate mistakes
// ---------------------------------------------------------------------------

test('the committed listing passes (placeholders allowed)', () => {
  const store = loadStore(join(REPO_ROOT, 'store'))
  const { errors } = validateStore(store, { allowPlaceholders: true })
  assert(errors.length === 0, `store/ has validation errors:\n    ${errors.join('\n    ')}`)
})

test('the committed listing blocks a real submission while placeholders remain', () => {
  const store = loadStore(join(REPO_ROOT, 'store'))
  const { errors } = validateStore(store)
  assertIncludes(errors, 'REPLACE_ME', 'placeholders did not block a strict validation')
})

test('the bundle id agrees across all three files that carry it', () => {
  const store = loadStore(join(REPO_ROOT, 'store'))
  const errors = checkBundleIdConsistency(REPO_ROOT, store.config.bundleId)
  assert(errors.length === 0, `bundle id disagreement:\n    ${errors.join('\n    ')}`)
})

test('a bundle id disagreement is caught rather than assumed away', () => {
  const errors = checkBundleIdConsistency(REPO_ROOT, 'com.example.wrong')
  assert(errors.length === 2, `expected both files to disagree, got ${errors.length}`)
  assertIncludes(errors, 'project.yml', 'the project manifest was not checked')
  assertIncludes(errors, 'ios-testflight.yml', 'the release workflow was not checked')
})

/** A manifest with everything right, so each mutation below is the only fault. */
function manifest(overrides = {}) {
  const settings = {
    TARGETED_DEVICE_FAMILY: '"1,2"',
    INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone:
      'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad:
      'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: 'NO',
    ASSETCATALOG_COMPILER_APPICON_NAME: 'AppIcon',
    ...overrides,
  }
  const lines = Object.entries(settings)
    .filter(([, value]) => value !== undefined)
    .map(([key, value]) => `        ${key}: ${value}`)
  return `targets:\n  AirlineEmpire:\n    settings:\n      base:\n${lines.join('\n')}\nschemes:\n  AirlineEmpire:\n    build:\n      targets:\n        AirlineEmpire: all\n`
}

test('the committed manifest produces a bundle Apple accepts', () => {
  const problems = checkBundleConfig(readFileSync(join(REPO_ROOT, 'AirlineEmpireApp', 'project.yml'), 'utf8'))
  assert(problems.length === 0, `project.yml would be rejected:\n    ${problems.join('\n    ')}`)
})

test('the fixture is clean, so the mutations below prove something', () => {
  assert(checkBundleConfig(manifest()).length === 0, `fixture is not clean: ${checkBundleConfig(manifest()).join(', ')}`)
})

test('an iPad build missing upside-down portrait is caught (Apple error 90474)', () => {
  // The exact shape of run 33216345773's rejection: one generic orientation
  // list of three, on a build that ships for iPad.
  const problems = checkBundleConfig(
    manifest({
      INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad: undefined,
      INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone: undefined,
      INFOPLIST_KEY_UISupportedInterfaceOrientations:
        'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    }),
  )
  assertIncludes(problems, 'PortraitUpsideDown', 'the missing iPad orientation was not caught')
  assertIncludes(problems, '90474', 'the error code that names this rejection was not cited')
})

test('an iPhone-only build is not held to the iPad orientation rule', () => {
  const problems = checkBundleConfig(
    manifest({
      TARGETED_DEVICE_FAMILY: '"1"',
      INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad: undefined,
    }),
  )
  assert(problems.length === 0, `an iPhone-only build was flagged: ${problems.join(', ')}`)
})

test('opting out of iPad multitasking is surfaced rather than silently allowed', () => {
  const problems = checkBundleConfig(manifest({ INFOPLIST_KEY_UIRequiresFullScreen: 'YES' }))
  assertIncludes(problems, 'Slide Over', 'UIRequiresFullScreen passed without comment')
})

test('a missing export-compliance declaration is caught', () => {
  const problems = checkBundleConfig(manifest({ INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: undefined }))
  assertIncludes(problems, 'export-compliance', 'the missing encryption declaration passed')
})

test('an icon setting that names a set which does not exist is caught', () => {
  const problems = checkBundleConfig(manifest({ ASSETCATALOG_COMPILER_APPICON_NAME: 'NotAnIconSet' }))
  assertIncludes(problems, 'NotAnIconSet', 'a dangling app-icon reference passed')
})

test('a manifest with no scheme is caught before xcodebuild fails on a runner', () => {
  const problems = checkBundleConfig(manifest().replace(/schemes:[\s\S]*$/, ''))
  assertIncludes(problems, 'no schemes', 'a manifest without a shared scheme passed')
})

test('the committed app icon is submittable', () => {
  // This asserted the opposite until 2026-08-28 — that the slot was empty and
  // the check said so — with a note that the day an icon arrived was the day
  // to flip it. It arrived; this is the flip. What it guards now is a real
  // regression: an icon replaced with the wrong size, or one re-exported from
  // an editor that helpfully added an alpha channel.
  const problems = checkAppIcon(REPO_ROOT)
  assert(problems.length === 0, `the committed app icon would be rejected:\n    ${problems.join('\n    ')}`)
})

test('an app icon with alpha or the wrong size is rejected', () => {
  const root = mkdtempSync(join(tmpdir(), 'ae-icon-'))
  const set = join(root, 'AirlineEmpireApp', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset')
  mkdirSync(set, { recursive: true })
  const write = (images) => writeFileSync(join(set, 'Contents.json'), JSON.stringify({ images, info: {} }))

  write([{ idiom: 'universal', size: '1024x1024', filename: 'icon.png' }])
  assertIncludes(checkAppIcon(root), 'not in the asset catalogue', 'a referenced but absent icon passed')

  writePngHeader(join(set, 'icon.png'), { width: 1024, height: 1024, colorType: 6 })
  assertIncludes(checkAppIcon(root), 'alpha channel', 'an icon with transparency passed')

  writePngHeader(join(set, 'icon.png'), { width: 512, height: 512, colorType: 2 })
  assertIncludes(checkAppIcon(root), '1024×1024', 'an undersized icon passed')

  writePngHeader(join(set, 'icon.png'), { width: 1024, height: 1024, colorType: 2 })
  assert(checkAppIcon(root).length === 0, 'a correct icon was rejected')
  rmSync(root, { recursive: true, force: true })
})

/** A minimal valid tree, so each mistake below is the only thing wrong with it. */
function fixture(mutate = () => {}) {
  const root = mkdtempSync(join(tmpdir(), 'ae-store-'))
  const locale = join(root, 'metadata', 'en-US')
  mkdirSync(locale, { recursive: true })
  mkdirSync(join(root, 'metadata', 'review'), { recursive: true })
  const files = {
    'name.txt': 'Airline Empire',
    'subtitle.txt': 'Route and fleet sim',
    'keywords.txt': 'aviation,airport,aircraft,manager,management,simulator,offline,business,network,economy',
    'description.txt': 'One aircraft. One route.\n\nA long enough description to be plausible.',
    'promotional_text.txt': 'Eighty airports.',
    'release_notes.txt': 'First release.',
    'support_url.txt': 'https://example.com/support',
    'marketing_url.txt': 'https://example.com/',
    'privacy_url.txt': 'https://example.com/privacy',
  }
  const config = {
    bundleId: 'com.airlineempire.game',
    platform: 'IOS',
    primaryLocale: 'en-US',
    copyright: '2026 Someone',
    review: {
      contactFirstName: 'A',
      contactLastName: 'B',
      contactEmail: 'a@example.com',
      contactPhone: '+100000000',
      demoAccountRequired: false,
    },
  }
  mutate({ files, config, root, locale })
  for (const [file, value] of Object.entries(files)) writeFileSync(join(locale, file), value)
  writeFileSync(join(root, 'metadata', 'review', 'notes.txt'), 'Offline single-player game; no account.')
  writeFileSync(join(root, 'config.json'), JSON.stringify(config, null, 2))
  return loadStore(root)
}

test('the fixture itself is clean (otherwise the tests below prove nothing)', () => {
  const { errors } = validateStore(fixture())
  assert(errors.length === 0, `fixture is not clean:\n    ${errors.join('\n    ')}`)
})

test('an over-long name is an error', () => {
  const store = fixture(({ files }) => {
    files['name.txt'] = 'x'.repeat(LIMITS.name + 1)
  })
  assertIncludes(validateStore(store).errors, 'name.txt', 'an over-long name passed')
})

test('a space after a comma in keywords is an error', () => {
  const store = fixture(({ files }) => {
    files['keywords.txt'] = 'aviation, airport'
  })
  assertIncludes(validateStore(store).errors, 'wasted character', 'a wasted keyword character passed')
})

test('a duplicated keyword is an error', () => {
  const store = fixture(({ files }) => {
    files['keywords.txt'] = 'aviation,airport,aviation'
  })
  assertIncludes(validateStore(store).errors, 'appears twice', 'a duplicate keyword passed')
})

test('a third-party trademark is an error wherever it appears', () => {
  const store = fixture(({ files }) => {
    files['description.txt'] = 'Fly the Boeing 737 of your dreams.'
  })
  assertIncludes(validateStore(store).errors, 'boeing', 'a manufacturer trademark passed')
})

test("Apple's own marks are fine in a description and wrong in a subtitle", () => {
  const fine = fixture(({ files }) => {
    files['description.txt'] = 'One aircraft.\n\nPlays on iPhone and iPad.'
  })
  assert(validateStore(fine).errors.length === 0, '"iPhone and iPad" in a description was rejected')

  const wrong = fixture(({ files }) => {
    files['subtitle.txt'] = 'The best iPhone airline sim'
  })
  assertIncludes(validateStore(wrong).errors, 'indexed field', 'a platform name in the subtitle passed')
})

test('a placeholder or a TODO never reaches the store', () => {
  const store = fixture(({ files }) => {
    files['promotional_text.txt'] = 'TODO write this'
  })
  assertIncludes(validateStore(store).errors, 'TODO', 'placeholder copy passed')
})

test('a non-https or malformed URL is an error', () => {
  const store = fixture(({ files }) => {
    files['support_url.txt'] = 'http://example.com/support'
  })
  assertIncludes(validateStore(store).errors, 'https', 'a plain-http support URL passed')

  const broken = fixture(({ files }) => {
    files['privacy_url.txt'] = 'example.com/privacy'
  })
  assertIncludes(validateStore(broken).errors, 'not a URL', 'a malformed URL passed')
})

test('an unknown locale directory is an error, not a silent no-op', () => {
  const store = fixture(({ root, files }) => {
    const bad = join(root, 'metadata', 'en_US')
    mkdirSync(bad, { recursive: true })
    for (const [file, value] of Object.entries(files)) writeFileSync(join(bad, file), value)
  })
  assertIncludes(validateStore(store).errors, 'en_US', 'a typo\'d locale directory passed')
})

test('control characters are caught but ordinary newlines are not', () => {
  const store = fixture(({ files }) => {
    // A literal BEL, spelled out rather than pasted: a raw control character
    // in a source file is invisible in a diff, which is the whole problem.
    files['description.txt'] = `One aircraft.${String.fromCharCode(7)}\n\nStill a description.`
  })
  assertIncludes(validateStore(store).errors, 'control characters', 'a control character passed')
  assert(validateStore(fixture()).errors.length === 0, 'a normal multi-line description was flagged')
})

test('a missing required field is an error and a missing optional one is not', () => {
  const store = fixture(({ files }) => {
    delete files['description.txt']
  })
  assertIncludes(validateStore(store).errors, 'description.txt', 'a missing description passed')

  const optional = fixture(({ files }) => {
    delete files['marketing_url.txt']
  })
  assert(validateStore(optional).errors.length === 0, 'a missing optional field was treated as an error')
})

test('review contact details are required', () => {
  const store = fixture(({ config }) => {
    config.review.contactEmail = ''
  })
  assertIncludes(validateStore(store).errors, 'contactEmail', 'a missing review contact passed')
})

test('an unused keyword budget is a warning', () => {
  const store = fixture(({ files }) => {
    files['keywords.txt'] = 'aviation'
  })
  assertIncludes(validateStore(store).warnings, 'unused', 'a mostly empty keyword field drew no comment')
})

await asyncTest('the committed fill-in sheet matches store/', async () => {
  // Runs the generator in --check mode in-process. The sheet is what a human
  // pastes into App Store Connect; if it disagrees with store/, the wrong copy
  // is the one that reaches the store.
  const { execFileSync } = await import('node:child_process')
  execFileSync(process.execPath, [join(REPO_ROOT, 'scripts', 'asc', 'build-fill-in-sheet.mjs'), '--check'], {
    stdio: 'pipe',
  })
})

rmSync(scratch, { recursive: true, force: true })

// ---------------------------------------------------------------------------

if (failures.length) {
  console.error(`\n✗ ${failures.length} failing, ${passed} passing\n`)
  for (const failure of failures) console.error(`  ✗ ${failure}`)
  process.exit(1)
}
console.log(`✓ ${passed} tests passing.`)
