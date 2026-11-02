#!/bin/bash
# 探针 80（只读）：79 号扫出"前端全量里没有 getUserMedia"，但壳的 shell.log 里有 14 条 `mic ::`
# （最近一条 10-22 14:15:56）⇒ 两条读数互相打脸。这一发就问一件事：**手机上真在跑的那份页面代码在哪，
# 里面到底有没有 mediaDevices**。
#
# 为什么要较这个真：他要的是"所有功能都接上"的账，我如果拿"扫了 64 个文件没命中"当"页面不用"，
# 而语音这条明明真发过权限请求，那整张对照表就都是可疑的。可能的解释有三种，逐个问：
# ① 我扫的那个 dist 不是 :3081 真发出去的那份（有两份前端）；
# ② 语音不在前端 dist 里，而在入口注入的兼容层 / 引擎侧 / 插件里；
# ③ 字符串被拼出来的（`e['get'+'UserMedia']`）⇒ 字面量扫不到。
set -u
ROOT=/usr/local/lib/node_modules/@deepseek-ai
say() { printf '\n=== %s\n' "$1"; }

say '① 盘上有几份 dsh-web-frontend/dist（有没有第二份）'
timeout 90 find / -xdev -type d -name dist -path '*dsh-web-frontend*' 2>/dev/null | sed 's/^/  /' | head -10

say '② 真在跑的那份：入口/引擎静态目录里 index-*.js 的指纹'
for d in $(timeout 90 find / -xdev -type d -name dist -path '*dsh-web-frontend*' 2>/dev/null | head -4); do
  printf '  %s\n' "$d"
  timeout 30 ls -l "$d"/assets/index-*.js 2>/dev/null | sed 's/^/      /'
  timeout 60 md5sum "$d"/assets/index-*.js 2>/dev/null | sed 's/^/      md5 /'
done

say '③ 谁在说 mediaDevices（把整个 @deepseek-ai 包树扫一遍，只列文件名）'
timeout 240 find "$ROOT" -type f -name '*.js' 2>/dev/null > /tmp/p80.js
echo "  包树内 js=$(wc -l </tmp/p80.js) 个"
timeout 240 xargs -a /tmp/p80.js grep -l -F 'mediaDevices' 2>/dev/null | head -8 | sed 's/^/    mediaDevices 命中 /'
timeout 240 xargs -a /tmp/p80.js grep -l -F 'getUserMedia' 2>/dev/null | head -8 | sed 's/^/    getUserMedia 命中 /'

say '④ 入口注入的兼容层里有没有（那是服务端 JS，不在 dist 里）'
ls -l /usr/local/bin/dsh-entry.js 2>/dev/null | sed 's/^/  /'
for p in getUserMedia mediaDevices 'dsh:dlname'; do
  n=$(timeout 30 grep -F -c -- "$p" /usr/local/bin/dsh-entry.js 2>/dev/null); rc=$?
  printf '  %-14s dsh-entry.js 命中行数=%s (rc%s)\n' "$p" "${n:-读不出}" "$rc"
done

say '⑤ 字符串被拼出来的可能：包树里 "UserMedia" / "ediaDevices" 这种半截字面量'
for p in UserMedia ediaDevices; do
  timeout 240 xargs -a /tmp/p80.js grep -l -F -- "$p" 2>/dev/null | wc -l | sed "s/^/  $p 命中文件=/"
done

say '收尾'
rm -f /tmp/p80.js
echo '本探针只读：没写、没改、没装；临时件已删。'
