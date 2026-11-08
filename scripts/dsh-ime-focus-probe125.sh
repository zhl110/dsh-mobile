#!/bin/bash
# probe 125 —— 打开 DSH，找到输入框编号并用 uinput 点它（验"真触摸能唤出原生键盘"）。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},25000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const a=await call({cmd:'open',app:'com.zhl.dsh'});
  console.log('OPEN '+(a.result||a.error));
  const s=await call({cmd:'screen',detail:true});
  const lines=(s.screen||'').split('\n');
  let id=null;
  for (const l of lines) {
    if (/描述你想构建|输入|文本框/.test(l)) { console.log('CAND '+l); const m=l.match(/\[(\d+)\]/); if (m && id===null) id=+m[1]; }
  }
  if (id===null) { console.log('NO_CANDIDATE'); return; }
  const t=await call({cmd:'tap',id:id});
  console.log('TAP id='+id+' ok='+t.ok+' result='+(t.result||t.error));
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
