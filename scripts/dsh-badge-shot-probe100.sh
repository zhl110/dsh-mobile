#!/bin/bash
# probe 100 —— 同 99，但发完 key home 后多停 12 秒，够 PC 侧从容截图（badge 自己 8 秒收）。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},20000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const h=await call({cmd:'key',key:'home'});
  console.log('HOME ok='+h.ok+' result='+(h.result||h.error));
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
sleep 12
echo "== 完 =="
