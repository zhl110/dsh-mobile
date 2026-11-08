#!/bin/bash
# probe 150 —— 回退路径验证：先在 chroot 里杀掉注入器，紧接着发 tap_xy（不等桥的 3 秒重起）。
#   期望：这一发走无障碍手势（dumpsys 里 deviceId=-1）；再等 4 秒重发一发，回到 deviceId=4。
set -u
pkill -f "dsh-uinput.py --serve" 2>/dev/null
sleep 0.2
X=720 Y=1505 /usr/local/bin/node - <<'JS'
const net=require('net');
const x=+process.env.X, y=+process.env.Y;
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},20000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const t0=Date.now();
  const r=await call({cmd:'tap_xy',x:x,y:y});
  console.log('tap_xy('+x+','+y+') ok='+r.ok+' ms='+(Date.now()-t0)+' result='+(r.result||r.error));
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
