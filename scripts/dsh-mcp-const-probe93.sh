#!/bin/bash
# p93 — 只读取齐接线常量：node 绝对路径 / mcp-client Config schema 全文 / 引擎与入口 pid / 现 cordis.patch.yml 指纹
set -u
DSH=/usr/local/lib/node_modules/@deepseek-ai/dsh
MC=$DSH/node_modules/@deepseek-ai/dsh-mcp-client/lib/index.js
echo "== node 路径 =="
command -v node; readlink -f "$(command -v node)"
echo "== Config schema（760-835 行） =="
sed -n '760,835p' "$MC"
echo "== 引擎 / 入口 pid（cmdline 含 dsh web / dsh-entry.js） =="
for p in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)
  case "$c" in *"dsh web"*|*"dsh-entry.js"*) echo "pid=${p#/proc/} cmd=$c";; esac
done
echo "== 现 cordis.patch.yml 指纹 =="
md5sum /root/.dsh/profiles/web/cordis.patch.yml; wc -c </root/.dsh/profiles/web/cordis.patch.yml
echo "== 完 =="