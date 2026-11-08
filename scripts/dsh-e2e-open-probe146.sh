#!/bin/bash
# probe 146 —— 端到端测试第 1 步：用 open 工具拉起系统设置，把整棵控件树打出来（挑一个安全的点目标）。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},25000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const r=await call({cmd:'open',app:'com.android.settings'});
  console.log('open ok='+r.ok+' result='+(r.result||r.error));
  console.log(r.screen||'');
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
