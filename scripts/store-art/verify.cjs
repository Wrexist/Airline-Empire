#!/usr/bin/env node
// Read-only artwork verification. Run after rendering and copying English locales.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const sharp = require('sharp');
const root = path.resolve(__dirname, '../..');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const json = p => JSON.parse(fs.readFileSync(path.join(root,p)));
const board = json('scripts/store-art/storyboard.json');
const dimensions = { APP_IPHONE_67: [1320,2868], APP_IPHONE_65: [1242,2688], APP_IPAD_PRO_3GEN_129: [2064,2752] };

(async () => {
  assert.equal(board.shots.length, 6);
  const content = 'AirlineEmpireCore/Sources/AirlineEmpireCore/';
  assert.equal(json(content+'Resources/airports.json').airports.length, Number(board.shots[0].proof));
  assert.equal(json(content+'Resources/aircraft.json').types.length, Number(board.shots[1].proof));
  for (const [file, enumName, shot] of [['Domain/AIProfile.swift','AIArchetype',4], ['Domain/Progression.swift','Era',5]]) {
    const code = fs.readFileSync(path.join(root,content,file),'utf8').split(`public enum ${enumName}:`)[1].split('public ')[0];
    assert.equal((code.match(/^    case /gm)||[]).length, Number(board.shots[shot].proof));
  }
  for (const device of ['iphone','ipad']) {
    const dir = path.join(root,'store/artwork/captures',device);
    assert.equal(fs.readdirSync(dir).filter(f=>f.endsWith('.png')).length,10);
  }
  for (const locale of ['en-US','en-GB']) {
    const dir = path.join(root,'store/screenshots',locale);
    const manifest = json(`store/screenshots/${locale}/export-manifest.json`);
    assert.equal(manifest.exports.length,18);
    for (const [type, size] of Object.entries(dimensions)) {
      assert.equal(fs.readdirSync(path.join(dir,type)).filter(f=>f.endsWith('.png')).length,6);
      for (const shot of board.shots) {
        const file = `${type}/${shot.id}.png`;
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
        const native = fs.readFileSync(path.join(root,'store/artwork/captures',record.nativeSource));
        assert.equal(sha(native),record.nativeSha256);
        for (const [x,y,w,h] of [record.sourceCrop,record.detailCrop].filter(Boolean)) {
          assert(x>=0 && y>=0 && x+w<=record.nativeWidth && y+h<=record.nativeHeight);
        }
        if (locale==='en-GB') assert.equal(sha(buffer),sha(fs.readFileSync(path.join(root,'store/screenshots/en-US',file))));
      }
    }
    console.log(`${locale}: 18 valid RGB exports; all original source hashes match.`);
  }
  console.log('Artwork verified: 6 stories, 3 canvases, 2 locales, 20 native captures, 4 content claims.');
})().catch(e=>{console.error(e);process.exit(1);});
