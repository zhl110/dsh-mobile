#!/bin/bash
# probe 153 —— 端到端收尾：先 scroll up 还原列表，再 key back 回到设置主屏；各打一行结果。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},25000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',x=>{b+=x;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const a=await call({cmd:'scroll',direction:'up'});
  console.log('scroll up ok='+a.ok+' result='+(a.result||a.error)+' | head: '+((a.screen||'').split('\n')[0]||''));
  const b=await call({cmd:'key',key:'back'});
  console.log('key back ok='+b.ok+' result='+(b.result||b.error)+' | head: '+((b.screen||'').split('\n')[0]||''));
  const lines=(b.screen||'').split('\n');
  for(let i=1;i<lines.length;i++) if(lines[i].includes('搜索编辑框')||lines[i].includes('搜索')) console.log('find: '+lines[i].trim());
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
