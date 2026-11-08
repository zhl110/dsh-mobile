#!/bin/bash
# probe 156 —— 只读：把当前屏幕的整棵控件树打出来（端到端测试里挑 id 用）。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},20000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',x=>{b+=x;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const r=await call({cmd:'screen'});
  console.log(r.ok? r.screen : ('ERR '+(r.error||'')));
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
