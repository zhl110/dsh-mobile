#!/bin/bash
# probe 94 —— 壳 0.12 手机控制环端到端（chroot 内跑，uid 0；纯本机链路，不碰他的应用数据）。
# 三段：① 壳 socket 的新 JSON 协议（ping/screen/key home/screen）② 桥独立 MCP 握手 + tools/list
#       ③ 桥 tools/call（screen + key home）真连壳 ⇒ 证 MCP→桥→壳→动作→新屏幕 整条通。
# key home 只是回桌面（安全动作，证 globalAction 与 settle 真跑）；不点任何应用按钮、不输入。
set -u
NODE=/usr/local/bin/node
BRIDGE=/usr/local/bin/dsh-phone-bridge.js
echo "== ① 壳 socket JSON 协议（现连现发，abstract dsh-mobile-tree） =="
"$NODE" - <<'JS' || echo "[① 失败：壳服务没应答——无障碍开关或服务没起]"
const net=require('net');
function call(p){return new Promise((res,rej)=>{const s=net.connect({path:'\0dsh-mobile-tree'});let b='';const t=setTimeout(()=>{s.destroy();rej(new Error('timeout'))},15000);s.on('connect',()=>s.write(JSON.stringify(p)+'\n'));s.on('data',d=>{b+=d;const i=b.indexOf('\n');if(i>=0){clearTimeout(t);s.destroy();try{res(JSON.parse(b.slice(0,i)))}catch(e){rej(e)}}});s.on('error',e=>{clearTimeout(t);rej(e)});});}
(async()=>{
  const ping=await call({cmd:'ping'}); console.log('ping ok='+ping.ok+' result='+ping.result);
  const scr=await call({cmd:'screen'}); console.log('screen ok='+scr.ok+' bytes='+(scr.screen||'').length+' head='+(scr.screen||'').split('\n')[0]);
  const home=await call({cmd:'key',key:'home'}); console.log('key_home ok='+home.ok+' result='+home.result+' new_bytes='+(home.screen||'').length+' new_head='+(home.screen||'').split('\n')[0]);
  const scr2=await call({cmd:'screen'}); console.log('screen2 head='+(scr2.screen||'').split('\n')[0]);
  const bad=await call({cmd:'tap',id:99999}); console.log('tap_bad_id ok='+bad.ok+' error='+bad.error);
})().catch(e=>{console.log('ERR '+e.message);process.exit(1)});
JS

echo "== ② 桥独立 MCP 握手 + tools/list（不连壳） =="
"$NODE" - <<'JS' || echo "[② 失败]"
const {spawn}=require('child_process');
const c=spawn('/usr/local/bin/node',['/usr/local/bin/dsh-phone-bridge.js'],{stdio:['pipe','pipe','pipe']});
let out='',err='';c.stdout.on('data',d=>out+=d);c.stderr.on('data',d=>err+=d);
const send=o=>c.stdin.write(JSON.stringify(o)+'\n');
function wait(id,ms){return new Promise((res,rej)=>{const t=setTimeout(()=>rej(new Error('reply timeout '+id)),ms);const iv=setInterval(()=>{for(const l of out.split('\n')){if(!l.trim())continue;try{const o=JSON.parse(l);if(o.id===id){clearTimeout(t);clearInterval(iv);res(o);return}}catch(e){}}},50);});}
(async()=>{
  send({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2025-06-18',capabilities:{},clientInfo:{name:'probe94',version:'1'}}});
  const ini=await wait(1,5000);console.log('initialize ver='+ini.result.protocolVersion+' server='+ini.result.serverInfo.name+' tools_cap='+!!ini.result.capabilities.tools);
  send({jsonrpc:'2.0',method:'notifications/initialized'});
  send({jsonrpc:'2.0',id:2,method:'tools/list'});
  const tl=await wait(2,5000);console.log('tools/list count='+tl.result.tools.length+' names='+tl.result.tools.map(t=>t.name).join(','));
  c.kill();
})().catch(e=>{console.log('ERR '+e.message+' stderr='+err.slice(0,200));c.kill();process.exit(1)});
JS

echo "== ③ 桥 tools/call 真连壳（screen + key home）⇒ MCP→桥→壳→动作→新屏幕 =="
"$NODE" - <<'JS' || echo "[③ 失败：桥连壳这一段不通]"
const {spawn}=require('child_process');
const c=spawn('/usr/local/bin/node',['/usr/local/bin/dsh-phone-bridge.js'],{stdio:['pipe','pipe','pipe']});
let out='',err='';c.stdout.on('data',d=>out+=d);c.stderr.on('data',d=>err+=d);
const send=o=>c.stdin.write(JSON.stringify(o)+'\n');
function wait(id,ms){return new Promise((res,rej)=>{const t=setTimeout(()=>rej(new Error('reply timeout '+id)),ms);const iv=setInterval(()=>{for(const l of out.split('\n')){if(!l.trim())continue;try{const o=JSON.parse(l);if(o.id===id){clearTimeout(t);clearInterval(iv);res(o);return}}catch(e){}}},50);});}
(async()=>{
  send({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2025-06-18',capabilities:{},clientInfo:{name:'probe94',version:'1'}}});
  await wait(1,5000);send({jsonrpc:'2.0',method:'notifications/initialized'});
  send({jsonrpc:'2.0',id:3,method:'tools/call',params:{name:'screen',arguments:{}}});
  const tc=await wait(3,15000);const txt=tc.result.content[0].text;console.log('call_screen isError='+(tc.result.isError||false)+' bytes='+txt.length+' head='+txt.split('\n')[0]);
  send({jsonrpc:'2.0',id:4,method:'tools/call',params:{name:'key',arguments:{key:'home'}}});
  const tk=await wait(4,15000);const kt=tk.result.content[0].text;console.log('call_key_home isError='+(tk.result.isError||false)+' bytes='+kt.length+' head='+kt.split('\n')[0]);
  c.kill();
})().catch(e=>{console.log('ERR '+e.message+' stderr='+err.slice(0,200));c.kill();process.exit(1)});
JS
echo "== 完 =="