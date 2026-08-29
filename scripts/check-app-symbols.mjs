#!/usr/bin/env node
// scripts/check-app-symbols.mjs
//
// Does every design-system symbol the app uses actually exist?
//
// ## Why this exists
//
// `swiftc -parse` is the only compiler check the Linux sessions have, and it
// answers exactly one question: is this syntactically valid Swift. It does not
// resolve a single name. So on 2026-08-29 an edit that rewrote `SpeedControl`
// truncated `Components.swift` at that marker and silently deleted everything
// after it — the `aeGlass` extension, `AEDuskBackdrop`, `AEChip`,
// `AEChoiceCard` — and the parse sweep passed on every file. The macOS runner
// found it, 29 errors later, after a 10x-billed build.
//
// Every one of those errors was "cannot find X in scope" or "has no member
// aeGlass": a question answerable by reading the sources, in milliseconds, on
// the cheap runner. That is what this does.
//
// ## What it is not
//
// Not a type-checker, and it will never be one. It knows nothing about
// arguments, generics, availability or SwiftUI. It answers one question — is
// this name declared anywhere in the app target — which is precisely the class
// of mistake that a truncating edit produces and a parse cannot see. The macOS
// compile stays the authority on everything else.
//
// Scope is deliberately narrow: the project's own `AE`-prefixed types and
// `ae`-prefixed view modifiers. Apple's API is the compiler's business.
//
// Usage: node scripts/check-app-symbols.mjs

import { readdirSync, readFileSync, statSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const APP_SOURCES = join(REPO_ROOT, 'AirlineEmpireApp', 'Sources')

/** Every .swift file under the app target. */
function swiftFiles(dir) {
  const found = []
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry)
    if (statSync(path).isDirectory()) found.push(...swiftFiles(path))
    else if (entry.endsWith('.swift')) found.push(path)
  }
  return found.sort()
}

/** Strip comments and string literals so neither can declare or use a name. */
function code(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ')
    .replace(/"(?:[^"\\\n]|\\.)*"/g, '""')
}

const files = swiftFiles(APP_SOURCES)
const declaredTypes = new Set()
const declaredModifiers = new Set()

for (const file of files) {
  const source = code(readFileSync(file, 'utf8'))
  for (const [, name] of source.matchAll(/\b(?:struct|class|enum|actor|protocol|typealias)\s+(AE[A-Za-z0-9_]*)/g)) {
    declaredTypes.add(name)
  }
  // View modifiers live as `func aeSomething(` inside an extension.
  for (const [, name] of source.matchAll(/\bfunc\s+(ae[A-Z][A-Za-z0-9_]*)\s*[(<]/g)) {
    declaredModifiers.add(name)
  }
}

const problems = []

for (const file of files) {
  const source = code(readFileSync(file, 'utf8'))
  const lines = source.split('\n')

  lines.forEach((line, index) => {
    // A type used as `AEThing(` or `AEThing.member` or a bare `AEThing()`.
    for (const [, name] of line.matchAll(/\b(AE[A-Z][A-Za-z0-9_]*)\b/g)) {
      if (!declaredTypes.has(name)) {
        problems.push({
          file: relative(REPO_ROOT, file),
          line: index + 1,
          message: `uses '${name}', which no file in the app target declares`,
        })
      }
    }
    // A modifier used as `.aeThing(`.
    for (const [, name] of line.matchAll(/\.\s*(ae[A-Z][A-Za-z0-9_]*)\s*\(/g)) {
      if (!declaredModifiers.has(name)) {
        problems.push({
          file: relative(REPO_ROOT, file),
          line: index + 1,
          message: `uses '.${name}()', which no extension in the app target declares`,
        })
      }
    }
  })
}

// De-duplicate: one report per name per file is enough to act on.
const unique = new Map()
for (const problem of problems) {
  const key = `${problem.file}:${problem.message}`
  if (!unique.has(key)) unique.set(key, problem)
}

if (unique.size) {
  console.error('✗ The app target uses symbols it does not declare:\n')
  for (const problem of unique.values()) {
    console.error(`  ${problem.file}:${problem.line} — ${problem.message}`)
  }
  console.error('\n  Every one of these is a "cannot find X in scope" on the macOS runner.')
  process.exit(1)
}

console.log(
  `✓ ${declaredTypes.size} AE types and ${declaredModifiers.size} ae modifiers declared; ` +
    `every use across ${files.length} files resolves.`,
)
