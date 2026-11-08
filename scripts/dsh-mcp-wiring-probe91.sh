#!/bin/bash
# p91 — 只读普查：引擎 0.2.1-rc.2 的 MCP 客户端怎么读 server 定义（为手机操控接线定形状）
# 不重启、不改任何文件。判据落到「它从哪个键读 command/args/env」与「web profile 现在有没有 mcp 层」。
set -u
DSH=/usr/local/lib/node_modules/@deepseek-ai/dsh
MC=$DSH/node_modules/@deepseek-ai/dsh-mcp-client

echo "== ① 包在不在 / 版本 / 入口 =="
if [ -d "$MC" ]; then
  node -e "const p=require('$MC/package.json');console.log('name='+p.name,'version='+p.version,'main='+(p.main||'?'))"
  echo "-- lib 文件清单 --"
  ls -1 "$MC/lib" 2>/dev/null
else
  echo "MC_NOT_FOUND $MC"
fi

echo "== ② 配置 schema：server 从哪些键读（command/args/env/url/transport/servers） =="
IDX="$MC/lib/index.js"
if [ -f "$IDX" ]; then
  echo "index.js bytes=$(wc -c <"$IDX")"
  grep -nE "command|args|env|url|transport|stdio|servers|mcpServers|z\.object|z\.record|serverSchema|ServerConfig" "$IDX" | head -50
else
  echo "IDX_NOT_FOUND"
fi

echo "== ③ 它怎么被激活 / 从哪取 server 列表（ctx / config / profile） =="
if [ -f "$IDX" ]; then
  grep -nE "ctx\.|getConfig|config\.|profileContext|mcpServers|\.servers|readFile|existsSync|join\(" "$IDX" | head -40
fi

echo "== ④ web profile 目录里有没有 mcp 配置文件 =="
PROF=/root/.dsh/profiles/web
ls -1 "$PROF" 2>/dev/null
echo "-- cordis.patch.yml 全文 --"
cat "$PROF/cordis.patch.yml" 2>/dev/null
echo "-- 找 mcp 相关件 --"
find /root/.dsh -maxdepth 3 -iname '*mcp*' 2>/dev/null

echo "== ⑤ 组合配置里 mcp 命中（--dump-config 打印完就退，不起服务） =="
dsh --profile web --dump-config 2>/dev/null > /tmp/p91-dump.txt
echo "dump bytes=$(wc -c </tmp/p91-dump.txt)"
grep -niE "mcp" /tmp/p91-dump.txt | head -30
rm -f /tmp/p91-dump.txt
echo "== 完 =="