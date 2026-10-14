#!/usr/bin/env node
// The App Store set, portrait (9:16 on iPhone, 3:4 on iPad), from native
// captures only. Two layouts, both app-dominant (Guideline 2.3.3):
//
//   phone  one screen in a device frame, with one or two magnified callouts
//          cut from the same campaign's other screens.
//   hub    the 3D hub, which runs landscape on iPhone, in a device turned on
//          its side, over two large panels cut from other hub frames.
//
// Every pixel inside a frame, callout or panel is a capture pixel, cropped and
// uniformly scaled; nothing is redrawn. The only drawn content is the headline
// band, the frames, the labels and the background.
//
//   node scripts/store-art/showcase.cjs [captureRoot] [outputRoot] [iphone|ipad]
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),sharp=require('sharp');
const positional=process.argv.slice(2).filter(a=>!a.startsWith('--'));
const captureRoot=path.resolve(positional[0]||'store/artwork/captures');
const outputRoot=path.resolve(positional[1]||'store/screenshots/en-US');
const deviceArg=positional[2];
const board=JSON.parse(fs.readFileSync(path.join(__dirname,'showcase.json')));
const sizes=[{key:'APP_IPHONE_67',device:'iphone',width:1320,height:2868},{key:'APP_IPHONE_65',device:'iphone',width:1242,height:2688},{key:'APP_IPAD_PRO_3GEN_129',device:'ipad',width:2064,height:2752}];
const esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const GOLD='#F3C47A',FONT='Arial,Helvetica,sans-serif';

const cache=new Map();
async function load(device,file){
  const key=`${device}/${file}`;
  if(!cache.has(key)){
    const buffer=fs.readFileSync(path.join(captureRoot,device,file));
    const meta=await sharp(buffer).metadata();
    if(meta.format!=='png'||Math.min(meta.width,meta.height)<1200)throw Error(`Native PNG required: ${key}`);
    cache.set(key,{key,buffer,meta,uri:`data:image/png;base64,${buffer.toString('base64')}`,sha256:sha(buffer)});
  }
  return cache.get(key);
}

// One rectangle of a capture, scaled uniformly into a box of the given width.
let clipId=0;
function cut(src,crop,x,y,w,radius){
  const [cx,cy,cw,ch]=crop;
  if(cx<0||cy<0||cx+cw>src.meta.width||cy+ch>src.meta.height)throw Error(`Out-of-bounds crop ${crop} in ${src.key}`);
  const s=w/cw,h=ch*s,id=`c${clipId++}`;
  return {h,svg:`<clipPath id="${id}"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${radius}"/></clipPath>
    <g clip-path="url(#${id})"><image x="${x-cx*s}" y="${y-cy*s}" width="${src.meta.width*s}" height="${src.meta.height*s}" preserveAspectRatio="none" xlink:href="${src.uri}"/></g>`};
}

function chip(x,y,text,size,{dark=false}={}){
  const w=text.length*size*0.68+size*1.6,h=size*1.9;
  return `<g transform="translate(${x},${y})" filter="url(#lift)">
    <rect width="${w}" height="${h}" rx="${h/2}" fill="${dark?'#071322':'url(#gold)'}" fill-opacity="${dark?.86:1}" ${dark?'stroke="#F3C47A" stroke-opacity=".55" stroke-width="2"':''}/>
    <text x="${w/2}" y="${h*0.66}" text-anchor="middle" font-family="${FONT}" font-size="${size}" font-weight="700" letter-spacing="${size*0.12}" fill="${dark?'#F7E3BE':'#1A1206'}">${esc(text)}</text>
  </g>`;
}

function backdrop(W,H,ipad){
  // Three faint great-circle arcs and a few airports: the game's own map
  // vocabulary, at a whisper, so the canvas reads as one family.
  const arcs=[[-.1,.34,.6,.1,1.1,.28],[-.05,.78,.5,.52,1.05,.7],[.2,1.02,.62,.8,1.1,.95]]
    .map(([x1,y1,cx,cy,x2,y2])=>`<path d="M${x1*W} ${y1*H} Q${cx*W} ${cy*H} ${x2*W} ${y2*H}" fill="none" stroke="#6FA2E8" stroke-opacity=".16" stroke-width="${ipad?4:3}" stroke-dasharray="${ipad?'2 16':'2 14'}" stroke-linecap="round"/>`).join('');
  return `<rect width="${W}" height="${H}" fill="url(#base)"/>
    <ellipse cx="${W*.92}" cy="${H*.06}" rx="${W*.75}" ry="${H*.22}" fill="url(#glowBlue)"/>
    <ellipse cx="${W*.05}" cy="${H*.62}" rx="${W*.7}" ry="${H*.25}" fill="url(#glowGold)"/>
    ${arcs}`;
}

function header(shot,index,W,ipad){
  const m=ipad?120:72,brandY=ipad?132:112,t=ipad?132:112,sub=ipad?46:40;
  const first=brandY+(ipad?70:62)+t*0.74;
  const lines=shot.headline.map((s,i)=>`<text x="${m-5}" y="${first+i*t*1.04}" font-size="${t}" font-weight="700" letter-spacing="${-t*0.035}" fill="${i?'url(#gold)':'#FFFFFF'}">${esc(s)}</text>`).join('');
  const subY=first+(shot.headline.length-1)*t*1.04+sub*1.75;
  return {bottom:subY+sub*0.6,svg:`<g font-family="${FONT}">
    <path d="M${m} ${brandY} L${m+26} ${brandY-18} L${m+16} ${brandY+2} L${m+13} ${brandY-8} Z" fill="${GOLD}"/>
    <text x="${m+38}" y="${brandY+1}" font-size="${ipad?30:27}" font-weight="700" letter-spacing="6" fill="#DCE5EF">AIRLINE EMPIRE</text>
    ${lines}
    <text x="${m}" y="${subY}" font-size="${sub}" fill="#C4D2E3">${esc(shot.sub)}</text>
  </g>${shot.tag?chip(W-m-(shot.tag.length*(ipad?26:23)*0.68+(ipad?26:23)*1.6),brandY-(ipad?36:32),shot.tag,ipad?26:23):''}`};
}

// A device frame around a capture shown whole. `land` turns it on its side.
function device(src,x,y,sw,ipad){
  const s=sw/src.meta.width,sh=src.meta.height*s,b=ipad?24:20;
  const r=(ipad?64:170)*s+b,inner=(ipad?64:170)*s,id=`d${clipId++}`;
  const land=src.meta.width>src.meta.height;
  // The Dynamic Island belongs to the iPhone, not the capture.
  const island=ipad?'':land
    ?`<rect x="${x+b+26*s*3}" y="${y+b+sh/2-62*s*3/2}" width="${12*s*3}" height="${62*s*3}" rx="${6*s*3}" fill="#000"/>`
    :`<rect x="${x+b+sw/2-62*s*3/2}" y="${y+b+11*s*3}" width="${62*s*3}" height="${18*s*3}" rx="${9*s*3}" fill="#000"/>`;
  return {w:sw+2*b,h:sh+2*b,svg:`<g filter="url(#drop)">
      <rect x="${x}" y="${y}" width="${sw+2*b}" height="${sh+2*b}" rx="${r}" fill="#0A0E15"/>
    </g>
    <rect x="${x+1.5}" y="${y+1.5}" width="${sw+2*b-3}" height="${sh+2*b-3}" rx="${r-1.5}" fill="none" stroke="url(#metal)" stroke-width="3"/>
    <clipPath id="${id}"><rect x="${x+b}" y="${y+b}" width="${sw}" height="${sh}" rx="${inner}"/></clipPath>
    <g clip-path="url(#${id})"><image x="${x+b}" y="${y+b}" width="${sw}" height="${sh}" preserveAspectRatio="none" xlink:href="${src.uri}"/></g>
    ${island}`};
}

function callout(src,c,device,x,y,w,ipad){
  const r=ipad?30:28,pad=ipad?10:8;
  const body=cut(src,c.crop[device],x+pad,y+pad,w-2*pad,r-pad);
  const h=body.h+2*pad,size=ipad?24:22;
  return {h,svg:`<g filter="url(#drop)"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="#FFFFFF"/></g>
    ${body.svg}
    <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="none" stroke="#F3C47A" stroke-opacity=".9" stroke-width="3"/>
    ${chip(x+(ipad?28:24),y-size*0.95,c.label,size)}`};
}

async function composePhone(shot,index,f,used){
  const ipad=f.device==='ipad',W=ipad?2064:1320,H=ipad?2752:2868;
  const head=header(shot,index,W,ipad);
  const main=await load(f.device,shot.screen);used.push(main);
  const sw=ipad?1540:1000,top=Math.round(head.bottom+(ipad?60:52));
  const frame=device(main,0,0,sw,ipad);
  const fx=(W-frame.w)/2;
  const placed=device(main,fx,top,sw,ipad);
  let calls='';
  for(const c of shot.callouts||[]){
    const src=await load(f.device,c.source);used.push(src);
    const cw=W*(c.width??(ipad?.66:.8));
    const cx=c.side==='left'?(ipad?70:34):W-cw-(ipad?70:34);
    calls+=callout(src,c,f.device,cx,top+placed.h*c.at,cw,ipad).svg;
  }
  return {svg:`${backdrop(W,H,ipad)}${head.svg}${placed.svg}${calls}`,W,H};
}

async function composeHub(shot,index,f,used){
  const ipad=f.device==='ipad',W=ipad?2064:1320,H=ipad?2752:2868;
  const head=header(shot,index,W,ipad);
  const main=await load(f.device,shot.screen);used.push(main);
  const sw=ipad?1640:1196,top=Math.round(head.bottom+(ipad?60:52));
  const probe=device(main,0,0,sw,ipad);
  const placed=device(main,(W-probe.w)/2,top,sw,ipad);
  const gap=ipad?44:40,m=ipad?86:44;
  let panels='';
  {
    // Rows: a full-width panel, or two half-width panels side by side; on
    // iPad, all of them side by side. The spare height is shared out evenly.
    const pw=W-2*m,rows=ipad?[shot.panels]:[];
    for(const p of ipad?[]:shot.panels){
      const last=rows[rows.length-1];
      if(p.half&&last&&last.length===1&&last[0].half)last.push(p);else rows.push([p]);
    }
    const sized=rows.map(r=>{
      const w=(pw-gap*(r.length-1))/r.length;
      return {w,items:r,h:Math.max(...r.map(p=>w*p.crop[f.device][3]/p.crop[f.device][2]))};
    });
    const spare=H-56-(top+placed.h)-sized.reduce((a,r)=>a+r.h,0);
    if(spare<gap*(rows.length+1))throw Error(`${shot.id}: panels overflow by ${Math.round(gap*(rows.length+1)-spare)} px`);
    const step=spare/(rows.length+1);
    let y=top+placed.h+step;
    for(const r of sized){
      for(const [i,p] of r.items.entries()){
        const src=await load(f.device,p.source);used.push(src);
        const x=m+i*(r.w+gap),body=cut(src,p.crop[f.device],x,y,r.w,36);
        panels+=`<g filter="url(#drop)"><rect x="${x}" y="${y}" width="${r.w}" height="${body.h}" rx="36" fill="#0A0E15"/></g>${body.svg}
          <rect x="${x}" y="${y}" width="${r.w}" height="${body.h}" rx="36" fill="none" stroke="#F3C47A" stroke-opacity=".55" stroke-width="3"/>
          ${chip(x+26,y-(ipad?23:21),p.label,ipad?24:22,{dark:true})}`;
      }
      y+=r.h+step;
    }
  }
  return {svg:`${backdrop(W,H,ipad)}${head.svg}${placed.svg}${panels}`,W,H};
}

function document(f,{svg,W,H}){
  return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${f.width}" height="${f.height}" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMin slice">
    <defs>
      <linearGradient id="base" x2="0" y2="1"><stop stop-color="#0B1D36"/><stop offset=".45" stop-color="#081427"/><stop offset="1" stop-color="#040A14"/></linearGradient>
      <radialGradient id="glowBlue"><stop stop-color="#3D7BF0" stop-opacity=".38"/><stop offset="1" stop-color="#3D7BF0" stop-opacity="0"/></radialGradient>
      <radialGradient id="glowGold"><stop stop-color="#E0A04E" stop-opacity=".16"/><stop offset="1" stop-color="#E0A04E" stop-opacity="0"/></radialGradient>
      <linearGradient id="gold"><stop stop-color="#FBE2B4"/><stop offset="1" stop-color="#DE9F4C"/></linearGradient>
      <linearGradient id="metal" x2="1" y2="1"><stop stop-color="#C9D3DF"/><stop offset=".3" stop-color="#4B5A6C"/><stop offset=".7" stop-color="#2A3442"/><stop offset="1" stop-color="#B9C4D1"/></linearGradient>
      <filter id="drop" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="26" stdDeviation="30" flood-color="#000" flood-opacity=".55"/></filter>
      <filter id="lift" x="-20%" y="-40%" width="140%" height="200%"><feDropShadow dx="0" dy="6" stdDeviation="8" flood-color="#000" flood-opacity=".35"/></filter>
    </defs>
    ${svg}
  </svg>`;
}

(async()=>{
  const records=[];
  for(const f of sizes.filter(s=>!deviceArg||s.device===deviceArg)){
    fs.mkdirSync(path.join(outputRoot,f.key),{recursive:true});
    for(const [i,shot] of board.shots.entries()){
      clipId=0;
      const used=[];
      const body=shot.layout==='hub'?await composeHub(shot,i,f,used):await composePhone(shot,i,f,used);
      const encoded=await sharp(Buffer.from(document(f,body))).flatten({background:'#081427'}).removeAlpha().png({compressionLevel:9}).toBuffer();
      const meta=await sharp(encoded).metadata();
      if(meta.width!==f.width||meta.height!==f.height||meta.hasAlpha)throw Error(`Invalid export ${shot.id}`);
      const file=`${f.key}/${shot.id}.png`;
      fs.writeFileSync(path.join(outputRoot,file),encoded);
      const sources=[...new Map(used.map(s=>[s.key,{file:s.key,sha256:s.sha256,width:s.meta.width,height:s.meta.height}])).values()];
      records.push({file,layout:shot.layout,headline:shot.headline.join(' '),sources,composition:'native-showcase',width:meta.width,height:meta.height,bytes:encoded.length,sha256:sha(encoded)});
      console.log(`${file} ${meta.width}x${meta.height}`);
    }
  }
  fs.writeFileSync(path.join(outputRoot,'export-manifest.json'),JSON.stringify({direction:board.creativeDirection,composition:'native-showcase',exports:records},null,2)+'\n');
})().catch(e=>{console.error(e);process.exit(1)});
