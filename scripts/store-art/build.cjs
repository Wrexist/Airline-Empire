#!/usr/bin/env node
// Editable compositions: decorative key art plus untouched native gameplay pixels.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),sharp=require('sharp');
const project=path.resolve(__dirname,'../..');
const captureRoot=path.resolve(process.argv[2]||'store/artwork/captures');
const outputRoot=path.resolve(process.argv[3]||'store/screenshots/en-US');
const board=JSON.parse(fs.readFileSync(path.join(__dirname,'storyboard.json')));
const sizes=[{key:'APP_IPHONE_67',device:'iphone',width:1320,height:2868},{key:'APP_IPHONE_65',device:'iphone',width:1242,height:2688},{key:'APP_IPAD_PRO_3GEN_129',device:'ipad',width:2064,height:2752}];
const esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const uri=b=>`data:image/png;base64,${b.toString('base64')}`;

function excerpt(source,crop,box,id){
  const [cx,cy,cw,ch]=crop;
  if(cx<0||cy<0||cx+cw>source.meta.width||cy+ch>source.meta.height)throw Error(`Out-of-bounds crop: ${id}`);
  const scale=Math.min(box.w/cw,box.h/ch),w=cw*scale,h=ch*scale,x=box.x+(box.w-w)/2,y=box.y;
  return {x,y,w,h,svg:`<defs><clipPath id="${id}"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="32"/></clipPath></defs>
    <rect x="${x-11}" y="${y-11}" width="${w+22}" height="${h+22}" rx="43" fill="#050B13" stroke="url(#edge)" stroke-width="2" filter="url(#shadow)"/>
    <g clip-path="url(#${id})"><image x="${x-cx*scale}" y="${y-cy*scale}" width="${source.meta.width*scale}" height="${source.meta.height*scale}" xlink:href="${source.uri}"/></g>`};
}

function compose(shot,index,f,source,art){
  const ipad=f.device==='ipad',W=ipad?2064:1320,H=ipad?2752:2868,m=ipad?118:82,t=ipad?176:143,gold='#F3C47A';
  const artY=ipad?85:180,artH=ipad?1180:990,py=ipad?1080:1065;
  const panel=excerpt(source,shot.crop[f.device],{x:m,y:py,w:W-2*m,h:ipad?(shot.detailCrop?.ipad?1050:1330):1470},'game');
  let detail='';
  if(shot.detailCrop?.[f.device])detail=excerpt(source,shot.detailCrop[f.device],{x:m,y:panel.y+panel.h+65,w:W-2*m,h:210},'detail').svg;
  const proofY=H-202;
  return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${f.width}" height="${f.height}" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMin meet">
    <defs>
      <linearGradient id="base" x2=".7" y2="1"><stop stop-color="#071322"/><stop offset=".58" stop-color="#0B1727"/><stop offset="1" stop-color="#050B14"/></linearGradient>
      <linearGradient id="fade" x2="0" y2="1"><stop stop-color="white" stop-opacity="0"/><stop offset=".12" stop-color="white"/><stop offset=".78" stop-color="white"/><stop offset="1" stop-color="white" stop-opacity="0"/></linearGradient>
      <mask id="artMask"><rect y="${artY}" width="${W}" height="${artH}" fill="url(#fade)"/></mask>
      <linearGradient id="shade" x2="0" y2="1"><stop stop-color="#040B17" stop-opacity=".5"/><stop offset="1" stop-color="#040B17" stop-opacity="0"/></linearGradient>
      <linearGradient id="edge" x2="1" y2="1"><stop stop-color="#BFCBDA" stop-opacity=".8"/><stop offset=".35" stop-color="#526E89" stop-opacity=".4"/><stop offset=".75" stop-color="#253549"/><stop offset="1" stop-color="#D6A564" stop-opacity=".6"/></linearGradient>
      <filter id="shadow" x="-20%" y="-12%" width="140%" height="135%"><feDropShadow dx="0" dy="22" stdDeviation="24" flood-color="#000" flood-opacity=".55"/></filter>
      <linearGradient id="gold"><stop stop-color="#F9DCAA"/><stop offset="1" stop-color="#D99A47"/></linearGradient>
      <linearGradient id="caption" x2="0" y2="1"><stop stop-color="#071322" stop-opacity="0"/><stop offset=".5" stop-color="#071322" stop-opacity=".65"/><stop offset="1" stop-color="#071322" stop-opacity="0"/></linearGradient>
    </defs>
    <rect width="${W}" height="${H}" fill="url(#base)"/>
    <image y="${artY}" width="${W}" height="${artH}" preserveAspectRatio="xMidYMid slice" xlink:href="${art.uri}" mask="url(#artMask)"/>
    <rect width="${W}" height="580" fill="url(#shade)"/>
    <rect y="${py-100}" width="${W}" height="90" fill="url(#caption)"/>
    <g font-family="Arial,Helvetica,sans-serif">
      <path d="M${m} 88 L${m+30} 67 L${m+18} 91 L${m+15} 79 Z" fill="${gold}"/>
      <text x="${m+43}" y="89" font-size="32" font-weight="700" letter-spacing="5" fill="#DCE5EF">AIRLINE EMPIRE</text>
      <text x="${W-m}" y="89" text-anchor="end" font-size="26" letter-spacing="4" fill="#B7C7D9">0${index+1}</text>
      ${shot.headline.map((s,i)=>`<text x="${m-5}" y="${230+i*t*1.05}" font-size="${t}" font-weight="700" letter-spacing="-5" fill="${i?'url(#gold)':'white'}">${esc(s)}</text>`).join('')}
      ${shot.body.map((s,i)=>`<text x="${m}" y="${(ipad?495:455)+i*48}" font-size="${ipad?45:37}" fill="#D7E0EB">${esc(s)}</text>`).join('')}
      <text x="${m}" y="${py-47}" font-size="${ipad?27:24}" letter-spacing="4" fill="#CDD8E7">${esc(shot.label)}</text>
      <text x="${W-m}" y="${py-47}" text-anchor="end" font-size="${ipad?23:21}" letter-spacing="2" fill="#92A6BD">ACTUAL GAMEPLAY</text>
    </g>
    ${panel.svg}${detail}
    <g font-family="Arial,Helvetica,sans-serif">
      <path d="M${m} ${proofY-63} H${W-m}" stroke="#7390AF" opacity=".25"/>
      <text x="${m}" y="${proofY}" font-size="${ipad?62:50}" font-weight="700" letter-spacing="-1.5" fill="${gold}">${esc(shot.proof)} <tspan fill="#E7EDF5" font-size="${ipad?46:36}" font-weight="400" letter-spacing="0">${esc(shot.proofLabel)}</tspan></text>
      <text x="${m}" y="${proofY+56}" font-size="${ipad?36:30}" fill="#A5B6C9">${esc(shot.proofBody.join(' '))}</text>
      <text x="${m}" y="${H-45}" font-size="${ipad?27:24}" fill="#93A5BA">Gameplay shown with Pro. Aviation artwork is illustrative.</text>
      <g transform="translate(${W-m-138},${H-53})">${board.shots.map((_,i)=>`<rect x="${i*26}" width="${i===index?22:7}" height="7" rx="3.5" fill="${i===index?gold:'#44536A'}"/>`).join('')}</g>
    </g>
  </svg>`;
}

(async()=>{
  const records=[];
  for(const f of sizes.filter(s=>!process.argv[4]||s.device===process.argv[4])){
    fs.mkdirSync(path.join(outputRoot,f.key),{recursive:true});
    for(const [i,shot]of board.shots.entries()){
      const native=fs.readFileSync(path.join(captureRoot,f.device,shot.source));
      const source={uri:uri(native),meta:await sharp(native).metadata()};
      if(source.meta.format!=='png'||source.meta.width<1200)throw Error('Native PNG required');
      const artPath=`store/artwork/cinematic/${shot.id}.png`,artwork=fs.readFileSync(path.join(project,artPath));
      const file=`${f.key}/${shot.id}.png`,svg=compose(shot,i,f,source,{uri:uri(artwork)});
      const encoded=await sharp(Buffer.from(svg)).flatten({background:'#071322'}).removeAlpha().png({compressionLevel:9}).toBuffer();
      await sharp(encoded).raw().toBuffer();fs.writeFileSync(path.join(outputRoot,file),encoded);
      const meta=await sharp(encoded).metadata();
      if(meta.width!==f.width||meta.height!==f.height||meta.hasAlpha)throw Error('Invalid export');
      records.push({file,width:meta.width,height:meta.height,bytes:encoded.length,sha256:sha(encoded),nativeSource:`${f.device}/${shot.source}`,nativeSha256:sha(native),nativeWidth:source.meta.width,nativeHeight:source.meta.height,sourceCrop:shot.crop[f.device],detailCrop:shot.detailCrop?.[f.device],headline:shot.headline.join(' '),artwork:artPath,artworkSha256:sha(artwork),artworkRole:'Decorative illustration, outside gameplay panel'});
      console.log(`${file} ${meta.width}x${meta.height}`);
    }
  }
  fs.writeFileSync(path.join(outputRoot,'export-manifest.json'),JSON.stringify({direction:board.creativeDirection,exports:records},null,2)+'\n');
})().catch(e=>{console.error(e);process.exit(1)});
