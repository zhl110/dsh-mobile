#!/bin/bash
# probe 154 —— 端到端：往设置搜索框（id 31）里输入一段无害文字，回读 + 新屏。
#   顺带验证 type 路径的"先真触摸聚焦、再 SET_TEXT"。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},25000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',x=>{b+=x;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const t0=Date.now();
  const r=await call({cmd:'type',id:26,text:'dsh e2e 测试'});
  console.log('type#26 ok='+r.ok+' ms='+(Date.now()-t0)+' result='+(r.result||r.error));
  console.log('head: '+((r.screen||'').split('\n')[0]||''));
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
