#!/bin/bash
# scripts/dsh-voice-picker-probe18.sh —— 把 speech/catalog 那一发完整读回来（17 里截在 1500 字节，
# 正好断在"这个 provider 就绪了没有"那几个字段之前）。只读、不调 prepare、不改配置。
# 判据：目录里若给出 cached/ready/available 这类状态位，那才是"插件自己认这三份文件"的读数；
# 没有的话就照实说"没这条读数"，别拿"文件在盘上"当成"插件判过了"。口令不进 argv、不打印。
set -u
B=http://127.0.0.1:3081
K=$(tr -d '\r\n' < /root/.dsh/entry.key)
OUT=/tmp/p18-catalog.json
printf 'cookie = dsh-entry=%s\n' "$K" | curl -s -m 25 -K - -X POST \
  -H 'content-type: application/json' -H "origin: $B" -H "referer: $B/" \
  -d '{"type":"client-request","rpcId":"p18","method":"speech/catalog","payload":{"args":{}}}' \
  "$B/api/speech/catalog" > "$OUT" 2>&1
echo "  返回 $(wc -c <"$OUT") B"
echo "=== provider 那几条里所有字段名（去重）==="
node -e '
const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
const ps=(j.result&&j.result.value&&j.result.value.providers)||[];
console.log("  provider 条数："+ps.length);
const keys=new Set(); ps.forEach(p=>Object.keys(p).forEach(k=>keys.add(k)));
console.log("  字段："+[...keys].sort().join(", "));
ps.forEach(p=>console.log("  --- "+p.id+" | name="+p.name+" | location="+p.location+
  " | 状态类字段："+Object.keys(p).filter(k=>/ready|cached|avail|download|installed|state|status|precision|bytes|version/i.test(k))
    .map(k=>k+"="+JSON.stringify(p[k])).join("  ")+" | languages="+JSON.stringify(p.languages)));
' "$OUT" 2>&1 | head -30
echo "=== 原样头 900 字节（防 node 解析盖住形状）==="
head -c 900 "$OUT"; printf '\n'
rm -f "$OUT"
