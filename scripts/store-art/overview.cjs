#!/usr/bin/env node
const sharp = require('sharp');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
(async () => {
  for (const [device, type, w, h] of [['iphone','APP_IPHONE_67',440,956], ['ipad','APP_IPAD_PRO_3GEN_129',540,720]]) {
    const dir = path.join(root,'store/screenshots/en-US',type);
    const files = fs.readdirSync(dir).filter(f=>f.endsWith('.png')).sort();
    const tiles = await Promise.all(files.map(async (f,i)=>({
      input: await sharp(path.join(dir,f)).resize(w,h).toBuffer(),
      left: i%3*(w+20)+10, top: Math.floor(i/3)*(h+20)+10,
    })));
    await sharp({create:{width:(w+20)*3,height:(h+20)*2+20,channels:3,background:'#D9E1EC'}})
      .composite(tiles).jpeg({quality:94}).toFile(path.join(root,'store/artwork',`overview-${device}.jpg`));
  }
})().catch(e=>{console.error(e);process.exit(1);});
