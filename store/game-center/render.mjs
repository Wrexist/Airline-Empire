#!/usr/bin/env node
// Renders the Game Center achievement and leaderboard images, and checks
// that store/game-center/catalog.json agrees with Core's GameCenterCatalog.
//
//   node store/game-center/render.mjs          render every image
//   node store/game-center/render.mjs --check  only check catalog ↔ Swift
//
// Apple wants one image per achievement (1024×1024 accepted) and masks it to
// a circle, so everything that matters sits inside the inscribed circle.
// Images carry no text: an achievement image is shown beside its localised
// title, and words baked into a picture are words nobody can translate.
//
// Icons are Google Material Symbols (Apache-2.0), vendored in ./icons so the
// render is reproducible offline.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'
import { execSync } from 'node:child_process'

const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..', '..')
const catalog = JSON.parse(readFileSync(join(here, 'catalog.json'), 'utf8'))

// --- 1 · Catalog ↔ Swift --------------------------------------------------

function check() {
  const swift = readFileSync(join(root,
    'AirlineEmpireCore/Sources/AirlineEmpireCore/Session/GameCenterCatalog.swift'), 'utf8')
  const rows = [...swift.matchAll(/a\("(\w+)", \.[a-z]+\([^)]*\), (\d+), "([^"]+)"\)/g)]
    .map(([, suffix, points, title]) => ({ suffix, points: Number(points), title }))
  const problems = []
  if (rows.length !== catalog.achievements.length) {
    problems.push(`Swift has ${rows.length} achievements, catalog.json has ${catalog.achievements.length}`)
  }
  for (const row of rows) {
    const entry = catalog.achievements.find((a) => a.suffix === row.suffix)
    if (!entry) { problems.push(`${row.suffix} missing from catalog.json`); continue }
    if (entry.points !== row.points) problems.push(`${row.suffix}: points ${entry.points} ≠ Swift ${row.points}`)
    if (entry.title !== row.title) problems.push(`${row.suffix}: title "${entry.title}" ≠ Swift "${row.title}"`)
  }
  for (const entry of catalog.achievements) {
    for (const field of ['preEarned', 'earned']) {
      if (entry[field].length > 255) problems.push(`${entry.suffix}.${field} exceeds 255 characters`)
    }
    try { readFileSync(join(here, 'icons', `${entry.icon}.svg`)) }
    catch { problems.push(`${entry.suffix}: icon ${entry.icon}.svg not vendored`) }
  }
  const boards = [...swift.matchAll(/leaderboardPrefix \+ "(\w+)", title: "([^"]+)"/g)]
    .map(([, suffix, title]) => ({ suffix, title }))
  for (const board of boards) {
    const entry = catalog.leaderboards.find((b) => b.suffix === board.suffix)
    if (!entry) problems.push(`leaderboard ${board.suffix} missing from catalog.json`)
    else if (entry.title !== board.title) problems.push(`leaderboard ${board.suffix}: title mismatch`)
  }
  const total = catalog.achievements.reduce((sum, a) => sum + a.points, 0)
  if (total !== 1000) problems.push(`points total ${total}, expected 1000`)
  if (problems.length) {
    for (const p of problems) console.error(`✗ ${p}`)
    process.exit(1)
  }
  console.log(`✓ Game Center catalog matches Swift: ${rows.length} achievements (${total} points), ${boards.length} leaderboards.`)
}

check()
if (process.argv.includes('--check')) process.exit(0)

// --- 2 · Render -----------------------------------------------------------

// Tier by points: effort reads as metal, consistently across the set.
function tier(points) {
  if (points <= 30) return { ring: '#C98B5A', glow: 'rgba(201,139,90,0.35)' }   // bronze
  if (points <= 60) return { ring: '#D5DEEA', glow: 'rgba(213,222,234,0.30)' }  // silver
  return { ring: '#F2A93B', glow: 'rgba(242,169,59,0.40)' }                      // ember gold
}

function page(iconSVG, colors) {
  // Recolour the Material glyph and let it scale to its box.
  const glyph = iconSVG
    .replace(/width="\d+"/, 'width="100%"').replace(/height="\d+"/, 'height="100%"')
    .replace('<path', `<path fill="${colors.ring}"`)
  return `<!doctype html><html><head><style>
    html,body{margin:0;width:1024px;height:1024px;background:#0A1224;overflow:hidden}
    .sky{position:absolute;inset:0;background:
      radial-gradient(circle at 50% 108%, rgba(242,169,59,0.30), transparent 55%),
      linear-gradient(180deg,#0A1224 0%,#1A2138 100%)}
    .arc{position:absolute;inset:0}
    .ring{position:absolute;left:112px;top:112px;width:800px;height:800px;border-radius:50%;
      box-shadow:0 0 90px ${colors.glow}, inset 0 0 60px rgba(0,0,0,0.35);
      border:18px solid ${colors.ring}; box-sizing:border-box;
      background:radial-gradient(circle at 50% 40%, #22304F 0%, #111A30 70%)}
    .inner{position:absolute;left:176px;top:176px;width:672px;height:672px;border-radius:50%;
      border:3px solid rgba(255,255,255,0.10); box-sizing:border-box}
    .glyph{position:absolute;left:292px;top:282px;width:440px;height:440px;
      filter:drop-shadow(0 10px 28px rgba(0,0,0,0.45))}
  </style></head><body>
    <div class="sky"></div>
    <svg class="arc" viewBox="0 0 1024 1024"><path d="M-40 860 Q 512 520 1064 700"
      stroke="${colors.ring}" stroke-opacity="0.18" stroke-width="6" fill="none"/></svg>
    <div class="ring"></div><div class="inner"></div>
    <div class="glyph">${glyph}</div>
  </body></html>`
}

const require = createRequire(join(execSync('npm root -g').toString().trim(), 'noop.js'))
const { chromium } = require('playwright')
const browser = await chromium.launch()
const tab = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 })

async function render(icon, colors, out) {
  const svg = readFileSync(join(here, 'icons', `${icon}.svg`), 'utf8')
  await tab.setContent(page(svg, colors))
  mkdirSync(dirname(out), { recursive: true })
  // JPEG-free, opaque PNG: Game Center rejects nothing here, and an opaque
  // image cannot show a checkerboard where the mask meets transparency.
  await tab.screenshot({ path: out, omitBackground: false })
}

const manifest = []
for (const a of catalog.achievements) {
  const out = join(here, 'achievements', `${a.suffix}.png`)
  await render(a.icon, tier(a.points), out)
  manifest.push({ id: `com.airlineempire.game.achievement.${a.suffix}`, file: `achievements/${a.suffix}.png` })
}
for (const b of catalog.leaderboards) {
  const out = join(here, 'leaderboards', `${b.suffix}.png`)
  await render(b.icon, { ring: '#5EA0FF', glow: 'rgba(94,160,255,0.35)' }, out)
  manifest.push({ id: `com.airlineempire.game.leaderboard.${b.suffix}`, file: `leaderboards/${b.suffix}.png` })
}
await browser.close()
writeFileSync(join(here, 'images.json'), JSON.stringify(manifest, null, 2) + '\n')
console.log(`✓ Rendered ${manifest.length} images into store/game-center/.`)
