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
import { mkdtempSync, writeFileSync, mkdirSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { Buffer } from 'node:buffer'

import { decodePrivateKey, credentialsFromEnv, mintToken, AppStoreConnect, AscError } from './lib/asc.mjs'
import { loadStore, validateStore, inspectPng, LIMITS } from './lib/metadata.mjs'

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

rmSync(scratch, { recursive: true, force: true })

// ---------------------------------------------------------------------------

if (failures.length) {
  console.error(`\n✗ ${failures.length} failing, ${passed} passing\n`)
  for (const failure of failures) console.error(`  ✗ ${failure}`)
  process.exit(1)
}
console.log(`✓ ${passed} tests passing.`)
