#!/usr/bin/env node
/* Render native screenshots into editable vector-led App Store compositions.
 * Usage: NODE_PATH=/path/to/node_modules node scripts/store-art/build.cjs CAPTURE_ROOT OUTPUT_ROOT
 * Dependencies: sharp. Native captures are placed in CAPTURE_ROOT/{iphone,ipad}.
 * The SVG embeds the original PNG; it does not redraw or regenerate game UI.
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('sharp');

const project = path.resolve(__dirname, '../..');
const captureRoot = path.resolve(process.argv[2] || 'store/artwork/captures');
const outputRoot = path.resolve(process.argv[3] || 'store/screenshots/en-US');
const board = JSON.parse(fs.readFileSync(path.join(__dirname, 'storyboard.json')));
const sizes = [
  { key: 'APP_IPHONE_67', device: 'iphone', width: 1320, height: 2868 },
  { key: 'APP_IPHONE_65', device: 'iphone', width: 1242, height: 2688 },
  { key: 'APP_IPAD_PRO_3GEN_129', device: 'ipad', width: 2064, height: 2752 },
];
const escape = s => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const cached = new Map();

// The same public-domain Natural Earth geometry used by the game.
const geoSource = fs.readFileSync(path.join(project, 'AirlineEmpireApp/Sources/Map/WorldGeometryData.swift'), 'utf8');
const polygons = geoSource.match(/static let coarseLand = """([\s\S]*?)"""/)[1].trim().split('\n');
const worldPaths = polygons.map(line => {
  const pairs = line.trim().split(/\s+/).map(p => p.split(',').map(Number));
  return pairs.map(([lat, lon], i) => `${i ? 'L' : 'M'}${((lon + 180) * 4).toFixed(1)},${((90 - lat) * 4).toFixed(1)}`).join(' ') + 'Z';
});

async function imageSource(device, file) {
  const key = `${device}/${file}`;
  if (!cached.has(key)) {
    const buffer = fs.readFileSync(path.join(captureRoot, key));
    const metadata = await sharp(buffer).metadata();
    if (metadata.format !== 'png' || metadata.width < 1200) throw new Error(`Not a native capture: ${key}`);
    cached.set(key, { buffer, metadata, uri: `data:image/png;base64,${buffer.toString('base64')}`, sha256: sha(buffer) });
  }
  return cached.get(key);
}

function svgFor(shot, index, format, source) {
  const ipad = format.device === 'ipad';
  const W = ipad ? 2064 : 1320;
  const H = ipad ? 2752 : 2868;
  const light = shot.theme === 'light';
  const bg = light ? '#F4F6FA' : '#08111F';
  const ink = light ? '#101B2E' : '#F7FAFF';
  const muted = light ? '#526174' : '#A6B5C9';
  const blue = light ? '#2268CD' : '#73B0FF';
  const accent = shot.accent === 'amber' ? '#F0B44E' : blue;
  const margin = ipad ? 126 : 86;
  const titleSize = ipad ? 168 : (index === 3 || index === 5 ? 140 : 148);
  const labelY = ipad ? 160 : 172;
  const titleY = ipad ? 350 : 348;
  const bodyY = ipad ? 607 : 575;
  const x = ipad ? 126 : 86;
  const y = ipad ? 770 : 745;
  const frameW = W - x * 2;
  const frameH = ipad ? 1430 : 1440;
  const crop = shot.crop[format.device];
  const [cx, cy, cw, ch] = crop;
  if (cx < 0 || cy < 0 || cx + cw > source.metadata.width || cy + ch > source.metadata.height) throw new Error(`Crop outside source: ${shot.id}/${format.device}`);
  // Contain a real gameplay excerpt, with equal padding. No UI element moves
  // relative to another and none of the game's text or figures are altered.
  const imageScale = Math.min((frameW - 24) / cw, (frameH - 24) / ch);
  const imageW = cw * imageScale, imageH = ch * imageScale;
  const insetX = x + (frameW - imageW) / 2, insetY = index===0 && !ipad ? y+45 : y+(frameH-imageH)/2;
  const detail = shot.detailCrop?.[format.device];
  let detailSVG = '';
  if (detail) {
    const [dx,dy,dw,dh] = detail;
    if (dx<0 || dy<0 || dx+dw>source.metadata.width || dy+dh>source.metadata.height) throw new Error('Detail crop outside capture');
    const ds = (frameW-24)/dw, tx=x+12, ty=1920, th=dh*ds;
    detailSVG = `<defs><clipPath id="detail"><rect x="${tx}" y="${ty}" width="${dw*ds}" height="${th}" rx="22"/></clipPath></defs>
      <rect x="${tx-12}" y="${ty-12}" width="${dw*ds+24}" height="${th+24}" rx="32" fill="#111925" stroke="#294563" stroke-width="2"/>
      <g clip-path="url(#detail)"><image x="${tx-dx*ds}" y="${ty-dy*ds}" width="${source.metadata.width*ds}" height="${source.metadata.height*ds}" xlink:href="${source.uri}"/></g>
      <text x="${margin}" y="${ty+th+75}" font-family="Nimbus Sans,Arial,sans-serif" font-size="30" fill="${muted}">One real airline. Five years in the making.</text>`;
  }
  const r = ipad ? 38 : 38;
  const routeY = ipad ? 1600 : 1660;
  const geometry = worldPaths.map(d => `<path d="${d}"/>`).join('');
  const line = `<path d="M-140 ${routeY + 550} C${W * 0.6} ${routeY + 510}, ${W * 0.6} ${routeY - 300}, ${W + 180} ${routeY - 500}" fill="none" stroke="${accent}" stroke-width="2.6" opacity="${light ? '.22' : '.28'}"/>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${format.width}" height="${format.height}" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMin meet">
    <defs>
      <linearGradient id="sky" x1="0" y1="0" x2="1" y2="1"><stop stop-color="${bg}"/><stop offset="1" stop-color="${light ? '#E9EFF7' : '#0D1B2E'}"/></linearGradient>
      <linearGradient id="edge" x1="0" y1="0" x2="1" y2="1"><stop stop-color="${light ? '#C3CFDF' : '#51749B'}"/><stop offset="1" stop-color="${light ? '#D5DFEC' : '#1A304A'}"/></linearGradient>
      <filter id="shadow" x="-25%" y="-15%" width="150%" height="140%"><feDropShadow dx="0" dy="28" stdDeviation="34" flood-color="#020916" flood-opacity="${light ? '.18' : '.45'}"/></filter>
      <clipPath id="screen"><rect x="${insetX}" y="${insetY}" width="${imageW}" height="${imageH}" rx="${r-10}"/></clipPath>
    </defs>
    <rect width="${W}" height="${H}" fill="url(#sky)"/>
    <g transform="translate(${ipad ? 1100 : 620},-60) scale(${ipad ? 1.12 : .85})" fill="none" stroke="${light ? '#A7BEDB' : '#29496B'}" stroke-width="1.3" opacity="${light ? '.28' : '.36'}">${geometry}</g>
    ${line}
    <path d="M${W-164} 70 V180" stroke="${accent}" stroke-width="2" opacity=".65"/>
    <circle cx="${W-164}" cy="190" r="7" fill="${accent}"/>
    <circle cx="${W-164}" cy="190" r="18" fill="none" stroke="${accent}" opacity=".4"/>
    <g font-family="Nimbus Sans,Arial,sans-serif">
      <text x="${margin}" y="92" fill="${ink}" font-size="37" font-weight="700" letter-spacing="6">AIRLINE EMPIRE</text>
      <text x="${margin}" y="${labelY}" fill="${muted}" font-size="25" font-weight="500" letter-spacing="4">${escape(shot.label)}</text>
      ${shot.headline.map((t,i) => `<text x="${margin-5}" y="${titleY + i*(titleSize*1.03)}" font-size="${titleSize}" font-weight="700" letter-spacing="-4.5" fill="${i === 1 ? accent : ink}">${escape(t)}</text>`).join('')}
      ${shot.body.map((t,i) => `<text x="${margin}" y="${bodyY+i*54}" font-size="${ipad ? 48 : 41}" fill="${muted}">${escape(t)}</text>`).join('')}
    </g>
    <text x="${margin}" y="${y-35}" font-family="Nimbus Sans,Arial,sans-serif" font-size="24" letter-spacing="3.5" fill="${muted}">ACTUAL GAMEPLAY</text>
    <rect x="${insetX-12}" y="${insetY-12}" width="${imageW+24}" height="${imageH+24}" rx="${r+2}" fill="#080F1B" stroke="url(#edge)" stroke-width="2" filter="url(#shadow)"/>
    <g clip-path="url(#screen)"><image x="${insetX-cx*imageScale}" y="${insetY-cy*imageScale}" width="${source.metadata.width*imageScale}" height="${source.metadata.height*imageScale}" xlink:href="${source.uri}"/></g>
    ${detailSVG}
    <g font-family="Nimbus Sans,Arial,sans-serif">
      <path d="M${margin} ${H-505} H${W-margin}" stroke="${muted}" opacity=".25"/>
      <text x="${margin-5}" y="${H-287}" font-size="${shot.proof.length > 3 ? (ipad ? 150 : 130) : 232}" font-weight="700" letter-spacing="-6" fill="${accent}">${escape(shot.proof)}</text>
      <text x="${margin}" y="${H-215}" font-size="${ipad ? 55 : 48}" font-weight="700" fill="${ink}">${escape(shot.proofLabel)}</text>
      ${shot.proofBody.map((t,i) => `<text x="${ipad ? 1120 : 705}" y="${H-325+i*55}" font-size="${ipad ? 43 : 34}" fill="${muted}">${escape(t)}</text>`).join('')}
    </g>
    <g font-family="Nimbus Sans,Arial,sans-serif" fill="${muted}" font-size="27">
      <text x="${margin}" y="${H-37}">${index === 5 ? 'Free to start. Full game with Pro.' : 'Gameplay shown with Pro.'}</text>
      <text x="${W-margin}" y="${H-37}" text-anchor="end" letter-spacing="3">0${index+1} / 06</text>
    </g>
  </svg>`;
}

(async () => {
  const records = [];
  for (const format of sizes.filter(s => !process.argv[4] || s.device === process.argv[4])) {
    const dir = path.join(outputRoot, format.key);
    fs.mkdirSync(dir, { recursive: true });
    for (let i=0; i<board.shots.length; i++) {
      const shot = board.shots[i];
      const source = await imageSource(format.device, shot.source);
      const svg = svgFor(shot, i, format, source);
      const filename = path.join(dir, `${shot.id}.png`);
      const encoded = await sharp(Buffer.from(svg)).flatten({ background: '#08111F' }).removeAlpha().png({ compressionLevel: 9 }).toBuffer();
      await sharp(encoded).raw().toBuffer(); // Reject incomplete encodes before writing.
      fs.writeFileSync(filename, encoded);
      const m = await sharp(filename).metadata();
      if (m.width !== format.width || m.height !== format.height || m.hasAlpha) throw new Error(`Invalid export: ${filename}`);
      const buffer = fs.readFileSync(filename);
      records.push({ file: path.relative(outputRoot,filename), width: m.width, height: m.height, bytes: buffer.length,
        sha256: sha(buffer), nativeSource: `${format.device}/${shot.source}`, nativeSha256: source.sha256,
        nativeWidth: source.metadata.width, nativeHeight: source.metadata.height, sourceCrop: shot.crop[format.device], detailCrop: shot.detailCrop?.[format.device], headline: shot.headline.join(' ') });
      console.log(`${format.key}/${shot.id}.png ${m.width}x${m.height}`);
    }
  }
  fs.writeFileSync(path.join(outputRoot, 'export-manifest.json'), JSON.stringify({ direction: board.creativeDirection, exports: records }, null, 2)+'\n');
})().catch(e => { console.error(e); process.exit(1); });
