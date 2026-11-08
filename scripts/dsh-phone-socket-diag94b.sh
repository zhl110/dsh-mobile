#!/bin/bash
# probe 94b —— 诊断壳 socket 为何不应答（事件级日志 + 0.11 裸 ping 对照）。只读，不做任何屏幕操作。
set -u
NODE=/usr/local/bin/node
echo "== 连接进程 uid/pid =="
"$NODE" -e 'console.log("uid="+process.getuid()+" pid="+process.pid)'
echo "== ① 事件级：JSON ping（连接/数据/关闭/错误/超时 全打） =="
"$NODE" - <<'JS'
const net=require('net');
const t0=Date.now();
const log=(...a)=>console.log('['+((Date.now()-t0)/1000).toFixed(2)+'s]',...a);
const s=net.connect({path:'\0dsh-mobile-tree'});
let sent=false;
function send(tag){ if(sent)return; sent=true; log('send via '+tag); s.write(JSON.stringify({cmd:'ping'})+'\n'); }
s.on('connect',()=>{log('connect fired'); send('connect');});
s.on('ready',()=>log('ready fired'));
s.on('data',d=>log('data '+d.length+'B: '+JSON.stringify(d.toString().slice(0,100))));
s.on('end',()=>log('end'));
s.on('close',()=>log('close'));
s.on('error',e=>log('error '+(e.code||'')+' '+e.message));
setTimeout(()=>{ if(!sent){log('connect never fired -> send anyway'); send('fallback');} },400);
setTimeout(()=>{log('done'); process.exit(0);},5000);
JS
echo "== ② 0.11 裸 ping 对照（若回 pong 就说明在跑旧代码） =="
"$NODE" - <<'JS'
const net=require('net');
const s=net.connect({path:'\0dsh-mobile-tree'});
let connected=false;
s.on('connect',()=>{connected=true;console.log('bare: connect, sending ping');s.write('ping\n');});
s.on('data',d=>{console.log('bare: data '+JSON.stringify(d.toString().slice(0,100)));process.exit(0);});
s.on('close',()=>console.log('bare: close'));
s.on('error',e=>console.log('bare: error '+(e.code||'')+' '+e.message));
setTimeout(()=>{console.log('bare: done connected='+connected);process.exit(0);},5000);
JS
echo "== 完 =="