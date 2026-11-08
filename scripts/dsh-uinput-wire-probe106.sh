#!/bin/bash
# probe 106 —— ① ping 注入器（@dsh-uinput）；② 让壳点一下 (1000,1250)，看是不是走 uinput。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(path,p,timeout){return new Promise((res,rej)=>{const s=net.connect({path});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},timeout||8000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  try { const p=await call('\0dsh-uinput',{op:'ping'}); console.log('UINPUT ping ok='+p.ok+' pid='+(p.pid||'')); }
  catch(e){ console.log('UINPUT ping ERR '+e.message); }
  try { const h=await call('\0dsh-mobile-tree',{cmd:'tap_xy',x:1000,y:1250},20000); console.log('TAP ok='+h.ok+' result='+(h.result||h.error)); }
  catch(e){ console.log('TAP ERR '+e.message); }
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
