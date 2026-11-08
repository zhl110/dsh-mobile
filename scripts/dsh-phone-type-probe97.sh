#!/bin/bash
# probe 97 —— 验 type 会先聚焦、唤出原生键盘：读当前屏的可输入控件，往第一个里填字，报回读。
set -u
/usr/local/bin/node - <<'JS'
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const tm=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},15000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(tm);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(tm);rej(e)});});}
(async()=>{
  const scr=await call({cmd:'screen',detail:true});
  const lines=(scr.screen||'').split('\n');
  console.log('HEAD '+lines[0]);
  const edits=lines.filter(l=>/可输入|输入框/.test(l));
  console.log('EDITABLE_COUNT='+edits.length);
  edits.slice(0,8).forEach(l=>console.log('  '+l.trim()));
  if(edits.length){
    const m=edits[0].match(/\[(\d+)\]/);
    if(m){ const id=parseInt(m[1],10);
      const r=await call({cmd:'type',id,text:'dsh测试'});
      console.log('TYPE id='+id+' ok='+r.ok+' result='+(r.result||r.error||''));
      const s2=await call({cmd:'screen'});
      const ed2=(s2.screen||'').split('\n').filter(l=>/dsh测试/.test(l));
      console.log('READBACK_MATCH='+ed2.length);
    }
  }
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS
echo "== 完 =="