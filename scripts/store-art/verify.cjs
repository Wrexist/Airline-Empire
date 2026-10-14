#!/usr/bin/env node
// Read-only verification of the App Store set (showcase.cjs). Run after
// rendering and copying the English locales.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const sharp = require('sharp');
const root = path.resolve(__dirname, '../..');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const json = p => JSON.parse(fs.readFileSync(path.join(root,p)));
const board = json('scripts/store-art/showcase.json');
const dimensions = { APP_IPHONE_67: [1320,2868], APP_IPHONE_65: [1242,2688], APP_IPAD_PRO_3GEN_129: [2064,2752] };

(async () => {
  // Apple shows at most ten per display type.
  assert(board.shots.length >= 1 && board.shots.length <= 10);
  // The numbers the headlines claim are the numbers the game ships.
  const shot = name => board.shots.find(s => s.id.endsWith('-'+name));
  const content = 'AirlineEmpireCore/Sources/AirlineEmpireCore/';
  assert.equal(json(content+'Resources/airports.json').airports.length, Number(shot('network').proof));
  assert.equal(json(content+'Resources/aircraft.json').types.length, Number(shot('fleet').proof));
  for (const [file, enumName, name] of [['Domain/AIProfile.swift','AIArchetype','rivals'], ['Domain/Progression.swift','Era','progression']]) {
    const code = fs.readFileSync(path.join(root,content,file),'utf8').split(`public enum ${enumName}:`)[1].split('public ')[0];
    assert.equal((code.match(/^    case /gm)||[]).length, Number(shot(name).proof));
  }
  for (const s of board.shots) assert(s.sub.includes(s.proof ?? ''), `${s.id}: the claim is in the copy`);
  // Every crop inside its capture, on both devices.
  for (const device of ['iphone','ipad']) {
    for (const s of board.shots) {
      const parts = [{source: s.screen}, ...(s.panels||[]), ...(s.callouts||[])];
      for (const p of parts) {
        const file = path.join(root,'store/artwork/captures',device,p.source);
        assert(fs.existsSync(file), `${device}/${p.source}`);
        if (!p.crop) continue;
        const m = await sharp(file).metadata(), [x,y,w,h] = p.crop[device];
        assert(x>=0 && y>=0 && x+w<=m.width && y+h<=m.height, `${s.id}: ${device} crop in ${p.source}`);
      }
    }
  }
  const canvases = board.shots.length * Object.keys(dimensions).length;
  for (const locale of ['en-US','en-GB']) {
    const dir = path.join(root,'store/screenshots',locale);
    const manifest = json(`store/screenshots/${locale}/export-manifest.json`);
    assert.equal(manifest.exports.length,canvases);
    for (const [type, size] of Object.entries(dimensions)) {
      assert.equal(fs.readdirSync(path.join(dir,type)).filter(f=>f.endsWith('.png')).length,board.shots.length);
      for (const s of board.shots) {
        const file = `${type}/${s.id}.png`;
        const record = manifest.exports.find(r=>r.file===file);
        assert(record, `Missing manifest record: ${file}`);
        const buffer = fs.readFileSync(path.join(dir,file));
        const m = await sharp(buffer).metadata();
        assert.deepEqual([m.width,m.height],size);
        assert.equal(m.hasAlpha,false);
        assert.equal(m.channels,3);
        assert.equal(m.format,'png');
        // Decode every pixel, not just the PNG header.
        await sharp(buffer).raw().toBuffer();
        assert.equal(sha(buffer),record.sha256);
        // Guideline 2.3.3: built from native captures only, and those are
        // the captures in the repository today.
        assert.equal(record.composition,'native-showcase');
        assert(record.sources.length>=1);
        for (const src of record.sources) {
          assert.equal(sha(fs.readFileSync(path.join(root,'store/artwork/captures',src.file))),src.sha256, src.file);
        }
        if (locale==='en-GB') assert.equal(sha(buffer),sha(fs.readFileSync(path.join(root,'store/screenshots/en-US',file))));
      }
    }
    console.log(`${locale}: ${canvases} valid RGB exports; all capture hashes match.`);
  }
  console.log(`Showcase verified: ${board.shots.length} shots, 3 canvases, 2 locales, 4 content claims.`);
})().catch(e=>{console.error(e);process.exit(1);});
