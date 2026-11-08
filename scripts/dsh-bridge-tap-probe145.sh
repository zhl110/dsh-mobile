#!/bin/bash
# probe 145 —— 壳 0.28 + 真触摸注入器端到端一发：只在 DSH 聊天页空白处点一下（横屏 2693,782），
#   看三件事：① 请求回 ok；② actions.log 落一行 tap_xy；③ dumpsys input 里这一发是 deviceId=4（真设备）还是 -1（退回无障碍）。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},20000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const t0=Date.now();
  const r=await call({cmd:'tap_xy',x:2693,y:782});
  console.log('tap_xy ok='+r.ok+' ms='+(Date.now()-t0)+' result='+(r.result||r.error));
  console.log('head: '+((r.screen||'').split('\n')[0]||''));
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
