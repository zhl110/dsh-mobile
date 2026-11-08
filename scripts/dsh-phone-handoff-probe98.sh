#!/bin/bash
# probe 98 —— 验 handoff（切回 DSH 前台）与 open（拉起一个 App）。安全：只开设置/回 DSH，不做任何破坏。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},20000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
const head=x=>(x||'').toString().split('\n')[0];
(async()=>{
  const o=await call({cmd:'open',app:'com.android.settings'});
  console.log('OPEN ok='+o.ok+' '+(o.error||head(o.screen)));
  await new Promise(r=>setTimeout(r,1000));
  const h=await call({cmd:'handoff',reason:'测试交还：请选择A或B'});
  console.log('HANDOFF ok='+h.ok+' result='+(h.result||h.error));
  await new Promise(r=>setTimeout(r,1200));
  const s=await call({cmd:'screen'});
  console.log('AFTER_HANDOFF_FOREGROUND '+head(s.screen));
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="