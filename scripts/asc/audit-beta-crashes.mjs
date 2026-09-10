// Read-only diagnostic export. Raw Apple logs and tester identities are never written.
import { mkdirSync, writeFileSync } from 'node:fs'
import { AppStoreConnect } from './lib/asc.mjs'

const client = AppStoreConnect.fromEnv()
const appId = '6806410538'
const page = await client.get(`/v1/apps/${appId}/betaFeedbackCrashSubmissions?limit=50&fields[betaFeedbackCrashSubmissions]=createdDate,deviceModel,osVersion,build&include=build&fields[builds]=version`)
const results = []
for (const submission of page.data ?? []) {
  const record = { id: submission.id, ...submission.attributes }
  const buildId = submission.relationships?.build?.data?.id
  record.buildNumber = page.included?.find(b => b.id === buildId)?.attributes?.version
  try {
    const response = await client.get(`/v1/betaFeedbackCrashSubmissions/${encodeURIComponent(submission.id)}/crashLog?fields[betaCrashLogs]=logText`)
    const raw = response.data?.attributes?.logText ?? ''
    let report
    try { report = JSON.parse(raw) } catch {
      try { report = JSON.parse(raw.slice(raw.indexOf('\n') + 1)) } catch { /* older text crash format */ }
    }
    if (report?.threads) {
      record.exception = report.exception
      record.termination = report.termination
      record.triggeredThreads = report.threads.filter(t => t.triggered).map(t => ({
        frames: t.frames.map(f => ({
          image: report.usedImages?.[f.imageIndex]?.name,
          symbol: f.symbol,
          symbolLocation: f.symbolLocation,
          imageOffset: f.imageOffset,
        })),
      }))
    } else {
      record.diagnosticLines = raw.split('\n').filter(l =>
        /^(Exception Type:|Exception Codes:|Termination Reason:|Triggered by Thread:|Thread \d+ Crashed:|\d+\s+(AirlineEmpire|libswiftCore|SwiftUI|SwiftUICore)\s)/.test(l)
      ).map(l => l.replace(/\/Users\/[^/\s]+/g, '/Users/<user>')).slice(0,100)
      record.logFormat = record.diagnosticLines.length ? 'filtered-text' : 'unrecognized-or-empty'
    }
  } catch (error) {
    record.crashLogStatus = error.status ?? 'unavailable'
  }
  results.push(record)
}
mkdirSync('apple-audit', { recursive: true })
writeFileSync('apple-audit/beta-crashes.json', JSON.stringify({ appId, checkedAt: new Date().toISOString(), morePages: Boolean(page.links?.next), results }, null, 2) + '\n')
console.log(`Read ${results.length} beta crash submission(s). Technical evidence saved without raw logs or tester identities.`)
