#!/bin/bash
# probe 148 —— 端到端测试：按坐标点一下（x y 由参数给），只打结果。
#   用法：bash tools/run-probe.sh scripts/dsh-e2e-xy-probe148.sh downloads/p148.txt 720 1505
set -u
X=${1:-720}; Y=${2:-1505}
X=$X Y=$Y /usr/local/bin/node - <<'JS'
const net=require('net');
const x=+process.env.X, y=+process.env.Y;
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},25000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const t0=Date.now();
  const r=await call({cmd:'tap_xy',x:x,y:y});
  console.log('tap_xy('+x+','+y+') ok='+r.ok+' ms='+(Date.now()-t0)+' result='+(r.result||r.error));
  console.log('head: '+((r.screen||'').split('\n')[0]||''));
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
