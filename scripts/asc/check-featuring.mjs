#!/usr/bin/env node
// Checks featuring nominations and In-App Events against Apple's field
// limits, so copy that would be truncated or refused fails in CI instead of
// in App Store Connect's form.
//
// Limits from App Store Connect Help ("Nominate your app for featuring",
// "In-app event metadata"). A limit change on Apple's side means editing
// the table below, deliberately, in one place.

import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..')
const read = (p) => JSON.parse(readFileSync(join(root, p), 'utf8'))
const problems = []
const report = []

function limit(file, field, value, max) {
  const length = [...(value ?? '')].length
  report.push(`${file} ${field}: ${length}/${max}`)
  if (!value) problems.push(`${file}: ${field} is empty`)
  else if (length > max) problems.push(`${file}: ${field} is ${length} characters, limit ${max}`)
}

for (const file of ['store/featuring-nomination.json', 'store/featuring-nomination-1.1.json']) {
  const n = read(file)
  limit(file, 'name', n.name, 60)
  limit(file, 'description', n.description, 1000)
  limit(file, 'helpfulDetails', n.helpfulDetails, 500)
}

const eventFile = 'store/in-app-events/game-center/event.json'
const event = read(eventFile)
const badges = ['Challenge', 'Competition', 'Live Event', 'Major Update',
  'New Season', 'Premiere', 'Special Event']
if (!badges.includes(event.badge)) problems.push(`${eventFile}: badge "${event.badge}" is not one of Apple's`)
limit(eventFile, 'referenceName', event.referenceName, 64)
for (const [locale, copy] of Object.entries(event.localizations)) {
  limit(eventFile, `${locale}.name`, copy.name, 30)
  limit(eventFile, `${locale}.shortDescription`, copy.shortDescription, 50)
  limit(eventFile, `${locale}.longDescription`, copy.longDescription, 120)
}
if (event.schedule?.durationDays > 31) problems.push(`${eventFile}: events last at most 31 days`)

for (const line of report) console.log(`  ${line}`)
if (problems.length) {
  for (const p of problems) console.error(`✗ ${p}`)
  process.exit(1)
}
console.log('✓ Featuring nominations and In-App Event fit Apple\'s limits.')
