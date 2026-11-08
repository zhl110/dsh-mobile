#!/bin/bash
# probe 117 —— 让壳在主内容区向下滚一次（走 uinput 滑动），打回结果与新屏前几行。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},20000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const h=await call({cmd:'scroll',direction:'down'});
  console.log('SCROLL ok='+h.ok+' result='+(h.result||h.error));
  if(h.screen) console.log(h.screen.split('\n').slice(0,5).join('\n'));
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
