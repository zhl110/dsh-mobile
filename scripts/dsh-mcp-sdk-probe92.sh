#!/bin/bash
# p92 — 只读：chroot 里有哪些 @modelcontextprotocol 包（决定桥复用 SDK server 还是零依赖手写），
#       以及客户端默认协议版本 / 工具命名形状。不改任何文件。
set -u
DSH=/usr/local/lib/node_modules/@deepseek-ai/dsh
NM=$DSH/node_modules

echo "== ① @modelcontextprotocol _scope 在引擎 node_modules 里有哪些包 =="
for base in "$NM" "$NM/@modelcontextprotocol" "/root/.dsh/profiles/web/node_modules"; do
  echo "-- base=$base --"
  ls -1 "$base/@modelcontextprotocol" 2>/dev/null || ls -1d "$base"/@modelcontextprotocol* 2>/dev/null || echo "(无)"
done

echo "== ② 逐包 name/version/main + 有没有 server stdio =="
for p in "$NM"/@modelcontextprotocol/*; do
  [ -d "$p" ] || continue
  node -e "const j=require('$p/package.json');console.log(j.name+'@'+j.version,'main='+(j.main||'?'),'exports='+Object.keys(j.exports||{}).join(','))" 2>/dev/null
done

echo "== ③ 客户端默认协议版本 / 工具公共名怎么拼 =="
MC=$NM/@deepseek-ai/dsh-mcp-client/lib/index.js
grep -nE "protocolVersion|LATEST_PROTOCOL|mcp__|publicName|serverName.*tool|__.*name|qualif" "$MC" | head -25
echo "-- client SDK 里的协议版本常量 --"
grep -rnE "LATEST_PROTOCOL_VERSION|protocolVersion *= *\"|SUPPORTED_PROTOCOL" "$NM/@modelcontextprotocol" 2>/dev/null | head -10

echo "== ④ node 版本（桥要用） =="
node --version
echo "== 完 =="