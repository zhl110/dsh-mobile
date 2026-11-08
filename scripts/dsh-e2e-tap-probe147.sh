#!/bin/bash
# probe 147 —— 端到端测试第 2 步：点设置里的「显示与亮度」，回结果与新屏（紧接着由 PC 侧读 dumpsys input 判 deviceId）。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},25000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const t0=Date.now();
  const r=await call({cmd:'tap',id:28});
  console.log('tap#28 ok='+r.ok+' ms='+(Date.now()-t0)+' result='+(r.result||r.error));
  const s=(r.screen||'').split('\n');
  console.log('head: '+(s[0]||''));
  console.log('next: '+(s[1]||''));
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
