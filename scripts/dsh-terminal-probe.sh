#!/bin/bash
# 只读探针 v2：包体在 dsh 的嵌套 node_modules 里，上一版路径写错了，重扫
N=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai
echo "=== 嵌套目录里跟「形态」有关的包 ==="
ls -1 $N | grep -iE 'headless|tui|cli|terminal|pty|term|acp|desktop|web' | sed 's/^/  /'

echo
echo "=== 账号包（找 auth-api 的 origin） ==="
A=$(ls -d $N/*account* 2>/dev/null)
echo "  $A"
for d in $A; do
  grep -rhoE 'https://[a-z0-9.-]*deepseek[a-z0-9.-]*' "$d/lib" 2>/dev/null | sort | uniq -c | sed "s/^/  $(basename $d) /"
  grep -rn 'auth-api' "$d/lib" 2>/dev/null | head -4 | sed 's/^/    /'
done

echo
echo "=== 有没有 xterm/pty：说明 web 里能开真终端 ==="
ls -d $N/../*xterm* /usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@xterm/* 2>/dev/null | sed 's/^/  /'
for d in $(ls -d $N/*pty* $N/*terminal* 2>/dev/null); do echo "  $(basename $d)"; done
grep -rloE 'node-pty|@xterm' $N/*/package.json 2>/dev/null | head -8 | sed 's/^/  引用者: /'

echo
echo "=== headless profile 的补丁内容（它是不是一个能对话的入口） ==="
head -40 $N/dsh-headless/cordis.patch.yml 2>/dev/null | sed 's/^/  /'
