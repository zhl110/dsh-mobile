#!/bin/bash
# probe 96 —— 量动作时延（纯读 vs 窗口切换 vs 无变化），看提速版 settle 的实际数字。只读+按键，安全。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},15000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const t=async(label,p)=>{const t0=Date.now();const r=await call(p);const ms=Date.now()-t0;const head=(r.screen||r.result||'').toString().split('\n')[0];console.log(label+'  ms='+ms+'  ok='+r.ok+'  '+head);};
  await t('screen(纯读,无settle)      ',{cmd:'screen'});
  await t('key notifications(窗口切换) ',{cmd:'key',key:'notifications'});
  await t('key back(窗口切换)          ',{cmd:'key',key:'back'});
  await t('key home(桌面,无变化)       ',{cmd:'key',key:'home'});
  await t('key home(再按,无变化)       ',{cmd:'key',key:'home'});
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="