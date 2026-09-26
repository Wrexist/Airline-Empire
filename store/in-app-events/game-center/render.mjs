#!/usr/bin/env node
// Renders the media for the "Game Center arrives" In-App Event
// (docs/APP_STORE_IN_APP_EVENT.md).
//
//   event card   1920×1080 (16:9)   — shown in search, Today, the product page
//   details page 1080×1920 (9:16)   — shown when the card is opened
//
// No words in either image: Apple places the event name and descriptions
// over and beside the media, and asks that the media itself carry none.
// The composition is the release's actual content — the achievement
// medallions from store/game-center — over the listing's existing,
// text-free key art (store/artwork/cinematic, decorative and labelled as
// such in its prompts.json).

import { readFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'
import { execSync } from 'node:child_process'

const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..', '..', '..')
const dataURL = (p) => 'data:image/png;base64,' + readFileSync(p).toString('base64')

const art = dataURL(join(root, 'store/artwork/cinematic/06-progression.png'))
const medal = (s) => dataURL(join(root, 'store/game-center/achievements', `${s}.png`))
// Bronze → silver → gold, left to right: the arc from a first flight to an empire.
const row = ['firstFlight', 'fleet10', 'firstIntercontinental', 'eraEmpire', 'weatherProof']

function page(w, h, portrait) {
  const size = portrait ? 250 : 210
  const medals = row.map((s, i) => {
    const lift = portrait ? 0 : -Math.round(Math.sin((i / (row.length - 1)) * Math.PI) * 30)
    return `<img src="${medal(s)}" style="width:${size}px;height:${size}px;border-radius:50%;
      transform:translateY(${-lift}px);box-shadow:0 18px 50px rgba(0,0,0,.55)">`
  }).join('')
  // In the open sky at the top, clear of the aircraft and of the lower band
  // where App Store surfaces lay the event name over the media.
  const layout = portrait
    ? `display:grid;grid-template-columns:repeat(2,${size}px);gap:44px 60px;justify-content:center;
       position:absolute;left:0;right:0;top:230px`
    : `display:flex;gap:44px;justify-content:center;align-items:flex-end;
       position:absolute;left:0;right:0;top:150px`
  // Portrait shows four in a 2×2 — five in a column would each be too small.
  const shown = portrait ? row.slice(0, 4) : row
  const html = portrait ? shown.map((s) => `<img src="${medal(s)}" style="width:${size}px;height:${size}px;border-radius:50%;box-shadow:0 18px 50px rgba(0,0,0,.55)">`).join('') : medals
  return `<!doctype html><html><head><style>
    html,body{margin:0;width:${w}px;height:${h}px;overflow:hidden;background:#0A1224}
    .art{position:absolute;inset:0;background:url(${art}) center ${portrait ? '62%' : '58%'}/cover no-repeat}
    .shade{position:absolute;inset:0;background:
      linear-gradient(180deg, rgba(10,18,36,.55) 0%, rgba(10,18,36,0) 45%, rgba(10,18,36,0) 70%, rgba(10,18,36,.65) 100%)}
  </style></head><body>
    <div class="art"></div><div class="shade"></div>
    <div style="${layout}">${html}</div>
  </body></html>`
}

const require = createRequire(join(execSync('npm root -g').toString().trim(), 'noop.js'))
const { chromium } = require('playwright')
const browser = await chromium.launch()
for (const [name, w, h, portrait] of [['event-card', 1920, 1080, false], ['details-page', 1080, 1920, true]]) {
  const tab = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 })
  await tab.setContent(page(w, h, portrait))
  await tab.waitForTimeout(150)
  mkdirSync(here, { recursive: true })
  await tab.screenshot({ path: join(here, `${name}.png`) })
  await tab.close()
}
await browser.close()
console.log('✓ Rendered event-card.png (1920×1080) and details-page.png (1080×1920).')
