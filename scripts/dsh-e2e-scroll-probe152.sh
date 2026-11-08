#!/bin/bash
# probe 152 —— 端到端：在设置页滚一下（down），回结果与新屏；由 PC 侧看 MOVE 序列的 deviceId。
set -u
D=${1:-down}
D=$D /usr/local/bin/node - <<'JS'
const net=require('net');
const d=process.env.D;
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},25000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',x=>{b+=x;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const t0=Date.now();
  const r=await call({cmd:'scroll',direction:d});
  console.log('scroll '+d+' ok='+r.ok+' ms='+(Date.now()-t0)+' result='+(r.result||r.error));
  console.log('head: '+((r.screen||'').split('\n')[0]||''));
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
