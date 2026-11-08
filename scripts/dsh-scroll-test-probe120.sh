#!/bin/bash
# probe 120 —— 打开 Settings，读前 3 行；再向下滚一次，读前 3 行（看内容真的动了）。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},25000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
function head(r){return (r.screen||'').split('\n').slice(0,4).join('\n');}
(async()=>{
  const a=await call({cmd:'open',app:'com.android.settings'});
  console.log('OPEN '+(a.result||a.error)); console.log(head(a));
  const b=await call({cmd:'scroll',direction:'down'});
  console.log('SCROLL '+(b.result||b.error)); console.log(head(b));
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
