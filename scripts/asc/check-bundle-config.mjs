#!/usr/bin/env node
// scripts/asc/check-bundle-config.mjs
//
// The bundle rules Apple enforces at upload, checked against `project.yml`
// before anything is compiled.
//
// ## Why this exists
//
// Run 33216345773 archived, signed and exported an .ipa — about eleven
// minutes on a 10x-billed macOS runner — and then Apple refused it:
//
//   Invalid bundle. The "UIInterfaceOrientationPortrait,…LandscapeLeft,
//   …LandscapeRight" orientations were provided for the
//   UISupportedInterfaceOrientations Info.plist key … but you need to include
//   all of the "…Portrait,…PortraitUpsideDown,…LandscapeLeft,…LandscapeRight"
//   orientations to support iPad multitasking. (90474)
//
// Every fact in that rejection was knowable from a manifest that had been
// committed for hours. That is the definition of a check belonging on the
// cheap runner, and the pipeline already had the shape for it — the icon check
// is the same idea — so the failure is worth more as a permanent gate than as
// a fixed line in a YAML file.
//
// ## Scope, and what it deliberately is not
//
// This is not a reimplementation of Apple's validator: that lives inside
// `altool` and needs a built binary. It encodes the small set of rules that
// (a) Apple enforces at upload, (b) are decided entirely in `project.yml`, and
// (c) this project has actually been bitten by, or would obviously be bitten
// by. One rule per thing that can reject a release. Grow it when a rejection
// teaches something new, and record the run number that taught it.
//
// Reads the manifest with regular expressions rather than a YAML parser, for
// the same reason as the bundle-id check: a parser is a dependency, and this
// needs a handful of scalar values. A pattern that stops matching reports that
// it could not read the setting rather than silently passing.
//
// Usage:  node scripts/asc/check-bundle-config.mjs

import { readFileSync, existsSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
const MANIFEST = join(REPO_ROOT, 'AirlineEmpireApp', 'project.yml')

/** All four, in Apple's own spelling. An iPad app must support every one. */
export const IPAD_REQUIRED_ORIENTATIONS = [
  'UIInterfaceOrientationPortrait',
  'UIInterfaceOrientationPortraitUpsideDown',
  'UIInterfaceOrientationLandscapeLeft',
  'UIInterfaceOrientationLandscapeRight',
]

/** A build setting's value, or null when the manifest does not set it. */
function setting(manifest, key) {
  const match = manifest.match(new RegExp(`^\\s*${key}:\\s*(.+?)\\s*$`, 'm'))
  if (!match) return null
  return match[1].replace(/^["']|["']$/g, '').replace(/\s+#.*$/, '')
}

/**
 * Every problem with the bundle configuration, as sentences.
 *
 * Exported so the selftest can drive it over synthetic manifests rather than
 * only over the committed one — a check that can only be tested by breaking
 * the real project is a check nobody tests.
 */
export function checkBundleConfig(manifestText) {
  const problems = []

  const deviceFamily = setting(manifestText, 'TARGETED_DEVICE_FAMILY')
  if (!deviceFamily) {
    problems.push('TARGETED_DEVICE_FAMILY is not set; the device families cannot be determined.')
  }
  const shipsIpad = (deviceFamily ?? '').split(',').map((value) => value.trim()).includes('2')

  // Rule 1 — iPad multitasking orientations (Apple error 90474).
  //
  // Shipping an iPad build opts into Slide Over and Split View, and an app
  // that refuses an orientation cannot be tiled beside another one. Apple
  // therefore requires all four in the iPad list. The generic key counts when
  // no iPad-specific key is set, which is exactly how this project failed:
  // one generic list of three, applied to an iPad build.
  if (shipsIpad) {
    const ipad =
      setting(manifestText, 'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad') ??
      setting(manifestText, 'INFOPLIST_KEY_UISupportedInterfaceOrientations')
    const requiresFullScreen = (setting(manifestText, 'INFOPLIST_KEY_UIRequiresFullScreen') ?? '').toUpperCase()

    if (requiresFullScreen === 'YES') {
      // Legal, and a deliberate trade: it opts out of multitasking entirely.
      // Not an error, but it should never happen by accident.
      problems.push(
        'UIRequiresFullScreen is YES, which opts the iPad build out of Slide Over and Split View. ' +
          'That is a product decision — if it was intended, record it in tasks/DECISIONS.md and delete this check.',
      )
    } else if (!ipad) {
      problems.push(
        'The app targets iPad but declares no supported orientations. Apple rejects the upload (error 90474).',
      )
    } else {
      const missing = IPAD_REQUIRED_ORIENTATIONS.filter((orientation) => !ipad.includes(orientation))
      if (missing.length) {
        problems.push(
          `The iPad orientation list is missing ${missing.join(', ')}. Apple requires all four for an iPad ` +
            'build and rejects the upload with error 90474 — after the archive is paid for.',
        )
      }
    }
  }

  // Rule 2 — export compliance.
  //
  // Its absence does not fail an upload; it makes every single build stop in
  // App Store Connect behind a manual questionnaire, which is worse, because
  // it is a papercut that recurs rather than an error that teaches.
  const encryption = setting(manifestText, 'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption')
  if (encryption === null) {
    problems.push(
      'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption is not declared. Every upload will then wait on a manual ' +
        'export-compliance answer in App Store Connect. The app makes no network calls; the value is NO.',
    )
  }

  // Rule 3 — the icon build setting must name the set that exists.
  const iconName = setting(manifestText, 'ASSETCATALOG_COMPILER_APPICON_NAME')
  if (!iconName) {
    problems.push('ASSETCATALOG_COMPILER_APPICON_NAME is not set, so the build ships without an app icon.')
  } else if (!existsSync(join(REPO_ROOT, 'AirlineEmpireApp', 'Resources', 'Assets.xcassets', `${iconName}.appiconset`))) {
    problems.push(`ASSETCATALOG_COMPILER_APPICON_NAME is "${iconName}", but no ${iconName}.appiconset exists.`)
  }

  // Rule 4 — a shared scheme, or xcodebuild cannot find anything to build.
  if (!/^schemes:/m.test(manifestText)) {
    problems.push(
      'project.yml declares no schemes. XcodeGen only generates a shared scheme when one is declared, and ' +
        '`xcodebuild -scheme AirlineEmpire` fails with "scheme not found" on a runner.',
    )
  }

  return problems
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const problems = checkBundleConfig(readFileSync(MANIFEST, 'utf8'))
  if (problems.length) {
    console.error('✗ AirlineEmpireApp/project.yml would produce a bundle Apple rejects:\n')
    for (const problem of problems) console.error(`  · ${problem}`)
    console.error('')
    process.exit(1)
  }
  console.log('✓ Bundle configuration is sound: iPad orientations, export compliance, icon set, scheme.')
}
