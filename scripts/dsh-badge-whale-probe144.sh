#!/bin/bash
# probe 144 —— 壳 0.28 校验：只发一条 screen（不改前台、不点任何东西）。
#   看两件事：① 提示条换成「🐳 小鲸鱼正在看屏幕」并留 60s（PC 侧趁这窗口截图）；
#            ② actions.log 里落下一行 screen（路径在宿主：/data/data/com.zhl.dsh/files/actions.log）。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},20000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const t0=Date.now();
  const r=await call({cmd:'screen'});
  console.log('screen ok='+r.ok+' ms='+(Date.now()-t0)+' bytes='+((r.screen||'').length));
  console.log('head: '+((r.screen||'').split('\n')[0]||r.error));
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="
