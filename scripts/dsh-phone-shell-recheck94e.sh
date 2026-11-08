#!/bin/bash
# probe 94e —— 重启后复查壳服务：进程 oom_adj / tree-server 线程 wchan / 一次 ping。纯只读。
set -u
SH=$(ps -eo pid,args | grep '[c]om.zhl.dsh' | grep -v grep | awk '{print $1}' | head -1)
echo "shell_pid=${SH:-空}"
if [ -n "${SH:-}" ]; then
  echo "oom_adj=$(cat /proc/$SH/oom_score_adj 2>/dev/null)"
  echo "cgroup_freezer=$(grep -i freezer /proc/$SH/cgroup 2>/dev/null)"
  TID=$(grep -l dsh-tree-server /proc/$SH/task/*/comm 2>/dev/null | sed -E 's#.*/task/([0-9]+)/comm#\1#' | head -1)
  echo "tree_server_tid=${TID:-空} wchan=$(cat /proc/$SH/task/${TID:-0}/wchan 2>/dev/null)"
fi
echo "-- ping --"
/usr/local/bin/node -e 'const net=require("net");const s=net.connect({path:"\0dsh-mobile-tree"});const t=setTimeout(()=>{console.log("TIMEOUT");process.exit(0)},8000);s.on("connect",()=>s.write("ping\n"));s.on("data",d=>{clearTimeout(t);console.log("DATA "+JSON.stringify(d.toString()));process.exit(0)});s.on("error",e=>{clearTimeout(t);console.log("ERR "+e.code)})'
echo "== 完 =="