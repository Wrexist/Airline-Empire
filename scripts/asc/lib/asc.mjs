// scripts/asc/lib/asc.mjs
//
// A dependency-free App Store Connect API client: ES256 JWT minting plus the
// small amount of JSON:API plumbing every script in this directory needs.
//
// ## Why Node in a Swift repository
//
// Master plan rule 6 says no unnecessary third-party dependencies, and this
// obeys it: there are no packages here, no package.json, no lockfile, and
// nothing from this directory ships in the app. Node itself is preinstalled on
// every GitHub-hosted runner (ubuntu and macOS alike), and `node:crypto` signs
// ES256 out of the box — which is the whole job. The alternatives were worse:
// fastlane drags in a Ruby toolchain and a Gemfile for the same REST calls,
// and signing an ES256 JWT in bash means hand-converting OpenSSL's DER
// signature to the raw r||s pair the spec demands. Swift would be the natural
// choice, and it cannot be: the release tooling has to run before and after
// the compile, on runners where building a helper binary costs more than the
// helper saves.
//
// The JWT construction below is ported from Wrexist/WorldQuest's
// `scripts/next-build-number.mjs`, which has authenticated against the live
// API (that repo's run #2, 2026-08-09) — so the header/claims/encoding shape
// here is proven, not inferred.
//
// ## What is proven and what is not
//
// Nothing in this file has been run against Apple from THIS repository: as of
// 2026-08-28 Airline Empire has no Apple Developer account, no app record and
// no API key (docs/APP_STORE_CONNECT.md is the list). The JWT path is
// exercised offline by `node scripts/asc/selftest.mjs`, which mints a key,
// signs a token and verifies the signature — that proves the crypto, not
// Apple's acceptance of it. Every request path is marked in
// docs/RELEASE_PIPELINE.md as "never executed" until a run says otherwise.
// Do not upgrade those claims without a run to point at.

import crypto from 'node:crypto'
import { Buffer } from 'node:buffer'

export const ASC_HOST = 'https://api.appstoreconnect.apple.com'

/** Apple rejects a token older than 20 minutes; 19 leaves room for clock skew. */
const TOKEN_TTL_SECONDS = 19 * 60

function b64url(input) {
  return Buffer.from(input).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

/**
 * The .p8 private key, however it was handed to us.
 *
 * The same tolerant decode WorldQuest's workflows use for this secret, and for
 * the same reason: the value is pasted by a human from one of three operating
 * systems, and a release must not fail on a stray carriage return. Accepts raw
 * PEM text, base64-encoded PEM, and either with CRLF line endings.
 */
export function decodePrivateKey(raw) {
  if (!raw || !raw.trim()) return null
  let text = raw.replace(/\r/g, '').trim()
  if (!text.includes('BEGIN')) {
    try {
      text = Buffer.from(text.replace(/\s+/g, ''), 'base64').toString('utf8')
    } catch {
      return null
    }
  }
  return text.includes('BEGIN') && text.includes('PRIVATE KEY') ? text : null
}

/**
 * Credentials from the environment, or a list of what is missing.
 *
 * One reader for every script so the three secret names are spelled in exactly
 * one place. They match the names WorldQuest already uses
 * (APP_STORE_CONNECT_KEY_ID / _ISSUER_ID / _API_KEY_BASE64), because the same
 * person will be pasting the same values into a second repository and a second
 * naming scheme buys nothing.
 */
export function credentialsFromEnv(env = process.env) {
  const keyId = env.APP_STORE_CONNECT_KEY_ID?.trim()
  const issuerId = env.APP_STORE_CONNECT_ISSUER_ID?.trim()
  const privateKey = decodePrivateKey(env.APP_STORE_CONNECT_API_KEY_BASE64 ?? '')

  const missing = []
  if (!keyId) missing.push('APP_STORE_CONNECT_KEY_ID')
  if (!issuerId) missing.push('APP_STORE_CONNECT_ISSUER_ID')
  if (!privateKey) {
    missing.push(
      env.APP_STORE_CONNECT_API_KEY_BASE64
        ? 'APP_STORE_CONNECT_API_KEY_BASE64 (set, but did not decode to a PEM private key)'
        : 'APP_STORE_CONNECT_API_KEY_BASE64',
    )
  }
  return { keyId, issuerId, privateKey, missing }
}

/**
 * An App Store Connect bearer token.
 *
 * ES256 is ECDSA on P-256 with SHA-256, and JWS wants the raw r||s pair rather
 * than Node's default DER wrapper — hence `dsaEncoding: 'ieee-p1363'`. Getting
 * this wrong produces a token that looks perfectly well-formed and is rejected
 * with a bare 401, which is why it is worth a comment.
 */
export function mintToken({ keyId, issuerId, privateKey }, { now = Date.now() } = {}) {
  const issuedAt = Math.floor(now / 1000)
  const header = { alg: 'ES256', kid: keyId, typ: 'JWT' }
  const payload = {
    iss: issuerId,
    iat: issuedAt,
    exp: issuedAt + TOKEN_TTL_SECONDS,
    aud: 'appstoreconnect-v1',
  }
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`
  const signature = crypto.sign('sha256', Buffer.from(signingInput), {
    key: crypto.createPrivateKey({ key: privateKey, format: 'pem' }),
    dsaEncoding: 'ieee-p1363',
  })
  return `${signingInput}.${b64url(signature)}`
}

/** Apple's JSON:API errors carry the useful part in `errors[].detail`. */
export class AscError extends Error {
  constructor(status, method, path, body) {
    const errors = Array.isArray(body?.errors) ? body.errors : []
    const detail = errors
      .map((e) => [e.title, e.detail, e.source?.pointer ?? e.source?.parameter].filter(Boolean).join(' — '))
      .join('\n  ')
    super(`${method} ${path} → HTTP ${status}${detail ? `\n  ${detail}` : ''}`)
    this.name = 'AscError'
    this.status = status
    this.errors = errors
  }
}

/**
 * A thin client. Deliberately not a wrapper around every endpoint — each script
 * spells out the resources it touches, so a reader can match the code against
 * Apple's reference page without going through an abstraction first.
 */
export class AppStoreConnect {
  #credentials
  #token = null
  #tokenExpiresAt = 0

  constructor(credentials) {
    this.#credentials = credentials
  }

  static fromEnv(env = process.env) {
    const credentials = credentialsFromEnv(env)
    if (credentials.missing.length) {
      const error = new Error(`Missing App Store Connect credentials: ${credentials.missing.join(', ')}`)
      error.missing = credentials.missing
      throw error
    }
    return new AppStoreConnect(credentials)
  }

  /** Cached until shortly before expiry — a long metadata push outlives one token. */
  token() {
    const now = Date.now()
    if (!this.#token || now > this.#tokenExpiresAt - 60_000) {
      this.#token = mintToken(this.#credentials, { now })
      this.#tokenExpiresAt = now + TOKEN_TTL_SECONDS * 1000
    }
    return this.#token
  }

  /**
   * One request, with retries on the failures that are worth retrying.
   *
   * 429 is Apple's rate limit and 5xx is Apple having a moment; both are
   * transient and both would otherwise fail a release for no reason. A 4xx
   * that is not 429 is our mistake and is raised immediately — retrying a
   * malformed PATCH just makes the log longer.
   */
  async request(method, path, { body, headers = {}, attempts = 4 } = {}) {
    const url = path.startsWith('http') ? path : `${ASC_HOST}${path}`
    let lastError = null

    for (let attempt = 1; attempt <= attempts; attempt++) {
      const response = await fetch(url, {
        method,
        headers: {
          Authorization: `Bearer ${this.token()}`,
          Accept: 'application/json',
          ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
          ...headers,
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      })

      if (response.status === 204) return null

      const text = await response.text()
      const json = text ? safeJson(text) : null

      if (response.ok) return json

      const retryable = response.status === 429 || response.status >= 500
      lastError = new AscError(response.status, method, path, json ?? { errors: [{ detail: text.slice(0, 500) }] })
      if (!retryable || attempt === attempts) throw lastError

      // Exponential backoff: 2s, 4s, 8s — the same shape the repo's git
      // retries use, and long enough for a rate-limit window to reopen.
      const waitMs = 1000 * 2 ** attempt
      console.error(`[asc] ${method} ${path} → ${response.status}; retrying in ${waitMs / 1000}s`)
      await sleep(waitMs)
    }
    throw lastError
  }

  get(path, options) {
    return this.request('GET', path, options)
  }

  post(path, body) {
    return this.request('POST', path, { body })
  }

  patch(path, body) {
    return this.request('PATCH', path, { body })
  }

  delete(path) {
    return this.request('DELETE', path)
  }

  /**
   * Follows `links.next` until the collection is exhausted.
   *
   * Apple pages at 50 by default and silently truncates otherwise — a listing
   * with 40 locales would read as complete and be wrong.
   */
  async getAll(path, options) {
    const items = []
    let next = path
    while (next) {
      const page = await this.get(next, options)
      items.push(...(page?.data ?? []))
      next = page?.links?.next ?? null
    }
    return items
  }
}

function safeJson(text) {
  try {
    return JSON.parse(text)
  } catch {
    return null
  }
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

// ---------------------------------------------------------------------------
// Resource helpers shared by more than one script.
// ---------------------------------------------------------------------------

/** The app record for a bundle id, or null if App Store Connect has none. */
export async function findApp(client, bundleId) {
  const page = await client.get(`/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}&limit=10`)
  const apps = page?.data ?? []
  // filter[bundleId] is a prefix-ish match on Apple's side in some cases, so
  // confirm the exact string rather than trusting the first row.
  return apps.find((app) => app.attributes?.bundleId === bundleId) ?? null
}

/**
 * States in which App Store Connect will accept metadata edits.
 *
 * Anything else (IN_REVIEW, PENDING_APPLE_RELEASE, READY_FOR_DISTRIBUTION, …)
 * is locked, and a PATCH against it fails with a 409 that reads like a bug in
 * this tooling. Checking first turns that into a sentence a human can act on.
 */
export const EDITABLE_VERSION_STATES = new Set([
  'PREPARE_FOR_SUBMISSION',
  'DEVELOPER_REJECTED',
  'REJECTED',
  'METADATA_REJECTED',
  'INVALID_BINARY',
  'WAITING_FOR_REVIEW', // editable for metadata-only fields; Apple decides per field
])

/** `appVersionState` is the current attribute; `appStoreState` is its deprecated twin. */
export function versionState(version) {
  return version?.attributes?.appVersionState ?? version?.attributes?.appStoreState ?? null
}

/**
 * Every iOS App Store version for an app, newest first.
 *
 * Through the app's own relationship endpoint — `GET /v1/apps/{id}/appStoreVersions`
 * — which is the one Apple documents. The top-level `/v1/appStoreVersions`
 * collection accepts POST and GET-by-id but has no documented list form, so a
 * `?filter[app]=` against it is a request Apple never promised to answer. The
 * first draft of this tooling used exactly that, in three places; one helper
 * means the endpoint is spelled once and can be corrected once.
 */
export async function listVersions(client, appId, { fields = [], limit = 50 } = {}) {
  const attributes = ['versionString', 'appVersionState', 'appStoreState', 'platform', ...fields]
  const versions = await client.getAll(
    `/v1/apps/${appId}/appStoreVersions?limit=${limit}&fields[appStoreVersions]=${attributes.join(',')}`,
  )
  // filter[platform] exists, but an app that is iOS-only returns nothing else
  // anyway and a filter Apple rejects would fail the whole call. Filter here.
  return versions.filter((version) => (version.attributes?.platform ?? 'IOS') === 'IOS')
}

