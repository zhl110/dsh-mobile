#!/bin/bash
# probe 123 —— 打开 Settings 读带坐标的树，找搜索/输入类节点。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},25000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const a=await call({cmd:'open',app:'com.android.settings'});
  console.log('OPEN '+(a.result||a.error));
  const s=await call({cmd:'screen',detail:true});
  const lines=(s.screen||'').split('\n');
  console.log('ITEMS='+lines.length);
  for (const l of lines) if (/搜索|输入|编辑|文本框/.test(l)) console.log(l);
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
