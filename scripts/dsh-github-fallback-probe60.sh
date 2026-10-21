#!/bin/bash
# dsh-github-fallback-probe60.sh —— GitHub 那跳今晚死了（p59），这一发判"有没有活的替代路"，供 git 用。
#
# p59 的硬事实：github.com 钉 .166、DoH 也还给 .166，但 TLS 8 秒窗没动静、curl 三次都是 (28) 超时、0 字节；
# codeload 20 秒超时；objects.githubusercontent.com 反倒活着（404 / 424 B / TLS 400 ms）。
# 另外 p59 第 5 节冒出一条新的：**gh-proxy.com 解析不到**（curl (6)，9.78 s）—— 这台机 UDP 53 废，
# 而 gh-proxy.com 从来没进 doh-hosts.sh 的清单 ⇒ 文档里"GitHub 被拦就改走 gh-proxy"那条退路**在手机上现在也不成立**。
# 这一发就把两件事分开判：① gh-proxy 能不能钉上、钉上之后能不能真把 GitHub 的字节带回来；② gitee 这跳能不能当 git 的远端。
# 只读：不写 hosts、不改 git 配置、不 clone 任何东西（ls-remote 只问 refs，不落文件）。
set -u
DOH=https://223.5.5.5/resolve
W="code=%{http_code} bytes=%{size_download} connect=%{time_connect}s total=%{time_total}s"

echo "== 1 gh-proxy.com 能不能解析（DoH），答案是什么"
curl -sk -m 10 "$DOH?name=gh-proxy.com&type=A" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);const A=(j.Answer||[]).filter(x=>x.type===1).map(x=>x.data);console.log("  DoH A:",A.length?A.join(","):"（无答案）"," Status:",j.Status);});'

echo "== 2 hosts 里有没有它；没有就先用 --resolve 打一发（这一步只测连通，不改 hosts）"
IP=$(awk '$2=="gh-proxy.com"{print $1; exit}' /etc/hosts)
A=$(curl -sk -m 10 "$DOH?name=gh-proxy.com&type=A" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);console.log((j.Answer||[]).filter(x=>x.type===1).map(x=>x.data)[0]||"");}catch(e){console.log("");}});')
echo "  hosts 里 : ${IP:-没钉}   DoH 首选 : ${A:-没给}"
if [ -n "$A" ]; then
  printf '  --resolve 打 robots : %s\n' "$(curl -sS -o /dev/null -m 20 -w "$W" --resolve "gh-proxy.com:443:$A" https://gh-proxy.com/robots.txt 2>&1 | tr '\n' ' ')"
  printf '  经它取 GitHub 的 README : %s\n' "$(curl -sS -o /dev/null -m 30 -w "$W" --resolve "gh-proxy.com:443:$A" "https://gh-proxy.com/https://raw.githubusercontent.com/git/git/master/README.md" 2>&1 | tr '\n' ' ')"
  printf '  经它取一个真 tarball 前 1 KB : %s\n' "$(curl -sSL -o /dev/null -m 40 -w "$W" --resolve "gh-proxy.com:443:$A" -r 0-1023 "https://gh-proxy.com/https://github.com/git/git/archive/refs/tags/v2.43.0.tar.gz" 2>&1 | tr '\n' ' ')"
fi

echo "== 3 不经镜像，直接再试 GitHub 一次（8 秒窗，看是不是整晚都这样）"
printf '  github.com robots（--resolve .166, 8s）: %s\n' "$(curl -sS -o /dev/null -m 8 -w "$W" --resolve github.com:443:20.205.243.166 https://github.com/robots.txt 2>&1 | tr '\n' ' ')"

echo "== 4 gitee 这一跳能不能当 git 远端（ls-remote 只问 refs；仓库在不在另说，回 HTTP 层错误就算路通）"
printf '  curl gitee.com/git/git : %s\n' "$(curl -sS -o /dev/null -m 15 -w "$W" https://gitee.com/git/git 2>&1 | tr '\n' ' ')"
for U in https://gitee.com/git/git.git https://github.com/git/git.git; do
  # 退出码必须单独取：写成 $(… | head -2) 再 $?，数的是 head 的退出码（永远是 0），路死了也报"通"。
  RAW=$(GIT_TERMINAL_PROMPT=0 timeout 30 git ls-remote --heads "$U" 2>&1); RC=$?
  printf '  git ls-remote %-40s rc=%s\n' "$U" "$RC"
  printf '%s\n' "$RAW" | head -2 | sed 's/^/      /' | cut -c1-160
done

echo "== 5 npmmirror 上取一个真包（这台机现在唯一实测能落字节的源码路）"
printf '  npm view zod version : %s\n' "$(timeout 30 npm view zod version 2>&1 | tail -1)"
printf '  pip download 一个小的 : %s\n' "$(timeout 60 python3 -m pip download -q --no-deps -d /tmp/p60-pip six 2>&1 | tail -1) 落地 $(ls /tmp/p60-pip 2>/dev/null | wc -l) 个文件"
rm -rf /tmp/p60-pip
