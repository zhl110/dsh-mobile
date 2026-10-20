#!/bin/bash
# scripts/dsh-voice-picker-probe19.sh —— 只一件事：把 speech/catalog 那一发**整条**读回来（18 里我 head -c 900
# 正好把它截在 preparation 与 setupEstimate 两个字段之前，那两个才是要看的）。
# 为什么这两个字段重要：盘上三份文件撞上校验是"我算的"，插件自己认不认（preparation 是什么状态）才算闭环。
# 只读：不调 prepare（那是让它去下载）、不调 configure/cancel（那是写）。口令不进 argv、不打印。
set -u
B=http://127.0.0.1:3081
K=$(tr -d '\r\n' < /root/.dsh/entry.key)
R=$(printf 'cookie = dsh-entry=%s\n' "$K" | curl -s -m 25 -K - -X POST \
  -H 'content-type: application/json' -H "origin: $B" -H "referer: $B/" \
  -d '{"type":"client-request","rpcId":"p19","method":"speech/catalog","payload":{"args":{}}}' \
  "$B/api/speech/catalog" 2>&1)
echo "=== 整条原文（$(printf '%s' "$R" | wc -c) B）==="
printf '%s\n' "$R"
echo
echo "=== 那两个字段单独挑出来（node 解析，防我看花）==="
printf '%s' "$R" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  const p=JSON.parse(s).result.value.providers[0];
  console.log("  preparation   = "+JSON.stringify(p.preparation,null,1));
  console.log("  setupEstimate = "+JSON.stringify(p.setupEstimate,null,1));
  console.log("  downloadSources = "+JSON.stringify(p.downloadSources));
});' 2>&1
