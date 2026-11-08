#!/bin/bash
# probe 95 —— 最小重启引擎 + 验证手机工具接线（chroot 内跑，root）。
# 只 SIGTERM `dsh web` 那一个（入口自己拉新一代，他的入场链接/cookie 不作废）。
# 杀前数身份（铁律 13）：cmdline 含 "dsh web" 的进程恰好 1 个、入口非空且不同 pid；用 starttime 判换代（防 pid 复用）。
# 重启后验：新引擎是否 spawn 了 dsh-phone-bridge.js（父进程=新引擎 ⇒ mcp-client(phone) 实例已加载）。
set -u
find_engine() { ps -eo pid,args | grep '[d]sh web' | awk '{print $1}' | sort -n; }
echo "== ① 杀前身份 =="
OLD=$(find_engine)
EC=$(printf '%s\n' "$OLD" | grep -c .)
echo "engine_pids=[$(echo $OLD | tr '\n' ' ')] count=$EC"
[ "$EC" = "1" ] || { echo "!! 引擎不唯一（count=$EC），停手不杀"; exit 1; }
ENT=$(ps -eo pid,args | grep '[d]sh-entry.js' | awk '{print $1}' | head -1)
echo "entry_pid=${ENT:-空}"
{ [ -n "${ENT:-}" ] && [ "$ENT" != "$OLD" ]; } || { echo "!! 入口空或与引擎同 pid，停手"; exit 1; }
OLD_ST=$(awk '{print $22}' "/proc/$OLD/stat" 2>/dev/null)
echo "old_engine=$OLD starttime=$OLD_ST"

echo "== ② SIGTERM 引擎 $OLD =="
kill -TERM "$OLD" && echo "sent TERM to $OLD"
NEW=""; NEW_ST=""
for i in $(seq 1 40); do
  sleep 1
  C=$(find_engine | head -1)
  [ -n "$C" ] || continue
  C_ST=$(awk '{print $22}' "/proc/$C/stat" 2>/dev/null)
  if [ "$C" = "$OLD" ] && [ "$C_ST" = "$OLD_ST" ]; then continue; fi
  NEW=$C; NEW_ST=$C_ST; break
done
[ -n "$NEW" ] || { echo "!! 40s 内没等到新一代引擎（入口 backoff？）；看入口是否在"; ps -eo pid,args | grep '[d]sh-entry' ; exit 1; }
echo "new_engine=$NEW starttime=$NEW_ST（old=$OLD）"
sleep 3

echo "== ③ 新引擎是否 spawn 了手机桥（mcp-client(phone) 实例已加载的硬证） =="
ps -eo pid,ppid,args | grep '[d]sh-phone-bridge.js' | sed 's/^/  /'
BR=$(ps -eo pid,ppid,args | grep '[d]sh-phone-bridge.js' | awk -v e="$NEW" '$2==e{print $1}')
if [ -n "$BR" ]; then echo "[ok] 桥 pid=$BR 的父进程正是新引擎 $NEW ⇒ 工具 mcp__phone__* 应已注册"; else echo "[warn] 没看到父进程=$NEW 的桥（查下面日志）"; fi

echo "== ④ 组合配置命中复点 =="
dsh --profile web --dump-config > /tmp/pd95.yml 2>&1
echo "dump_bytes=$(wc -c < /tmp/pd95.yml) phone_mcp=$(grep -c phone-mcp /tmp/pd95.yml) bridge_hits=$(grep -c dsh-phone-bridge /tmp/pd95.yml)"

echo "== ⑤ 引擎日志里 mcp-client / phone 相关行 =="
for L in /root/.dsh/profiles/web/log.ndjson /root/.dsh/log.ndjson; do
  if [ -f "$L" ]; then echo "-- $L --"; grep -iE 'mcp-client|mcp__phone|phone-bridge|dsh-phone' "$L" | tail -8; fi
done

echo "== ⑥ 新一代下，桥 tools/call screen 再走一遍（证壳仍通） =="
/usr/local/bin/node - <<'JS'
const {spawn}=require('child_process');
const c=spawn('/usr/local/bin/node',['/usr/local/bin/dsh-phone-bridge.js'],{stdio:['pipe','pipe','pipe']});
let out='';c.stdout.on('data',d=>out+=d);
const send=o=>c.stdin.write(JSON.stringify(o)+'\n');
function wait(id,ms){return new Promise((res,rej)=>{const t=setTimeout(()=>rej(new Error('timeout '+id)),ms);const iv=setInterval(()=>{for(const l of out.split('\n')){if(!l.trim())continue;try{const o=JSON.parse(l);if(o.id===id){clearTimeout(t);clearInterval(iv);res(o);return}}catch(e){}}},50);});}
(async()=>{
  send({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2025-06-18',capabilities:{},clientInfo:{name:'p95',version:'1'}}});
  await wait(1,5000);send({jsonrpc:'2.0',method:'notifications/initialized'});
  send({jsonrpc:'2.0',id:2,method:'tools/call',params:{name:'screen',arguments:{}}});
  const r=await wait(2,15000);const txt=r.result.content[0].text;console.log('screen isError='+(r.result.isError||false)+' bytes='+txt.length+' head='+txt.split('\n')[0]);
  c.kill();
})().catch(e=>{console.log('ERR '+e.message);c.kill();process.exit(1)});
JS
echo "== 完 =="