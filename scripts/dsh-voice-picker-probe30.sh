#!/bin/bash
# scripts/dsh-voice-picker-probe30.sh —— 把他那句"以后在手机上要下 GitHub 项目怎么办"落到一个真读数上。
#
# 前两发把形状量出来了，但留下一条我读反了的风险：
#   p26 记的是 github.com ⇒ http=000（-m 6、--connect-timeout 4，size=0）；
#   p29 ④ 同一条主机换成 -m 8 ⇒ **http=200 time=8.0008s**。
#   ⇒ 它不是"连不上"，是"连得上但 8 秒传不完首页"。000 到底是"连不上"还是"我没给它足够时间"，
#     决定的是完全不同的两个结论，所以这一发**实测吞吐**而不是实测状态码。
# 测法：每发 12 秒封顶，报回落到磁盘的字节数与 KB/s，并把"是不是走解析"标清楚。
# ③ 那条最关键：直接在 chroot 里跑一发真 git ls-remote —— 他以后要的就是这个动作能不能成。
# ④ 顺带把 apt 那条讲清楚：chroot 里现在配的源主机是哪台、它在不在我钉过的可达名单里（不发 apt-get update，那是写）。
# 出网计量：12 秒 × 4 发 + 一发 ls-remote，读数里逐条报字节；不落盘（全丢 /dev/null）。
# 只读：不写 hosts、不改 sources.list、不装包、不 clone 任何东西。口令不参与。
set -u
B12=12
pull() { # $1=URL $2=要 --resolve 的主机:IP（可空）
  local extra=()
  [ -n "${2:-}" ] && extra=(--resolve "$2")
  curl -sL -m $B12 --connect-timeout 6 "${extra[@]}" -o /dev/null \
    -w 'http=%{http_code} size=%{size_download} time=%{time_total}s' "$1" 2>&1
}
ghip=$(grep -E "[[:space:]]github\.com\$" /etc/hosts | head -1 | awk '{print $1}')
clip=$(grep -E "[[:space:]]codeload\.github\.com\$" /etc/hosts | head -1 | awk '{print $1}')
objip=$(grep -E "[[:space:]]objects\.githubusercontent\.com\$" /etc/hosts | head -1 | awk '{print $1}')
echo "== ⓪ hosts 里这几条（p28 复述：凡钉过的都能连，本轮只测速度）"
printf '  github.com=%s  codeload=%s  objects=%s\n' "$ghip" "$clip" "$objip"

echo
echo "== ① 吞吐实测（每发 12 秒封顶，字节全丢 /dev/null）"
printf '  github.com 仓库首页      %s\n'        "$(pull "https://github.com/sherpa-onnx/sherpa-onnx" "github.com:443:$ghip")"
printf '  codeload tar.gz（clone 场景）%s\n'    "$(pull "https://codeload.github.com/sherpa-onnx/sherpa-onnx/tar.gz/refs/heads/master" "codeload.github.com:443:$clip")"
printf '  objects.githubusercontent  %s\n'      "$(pull "https://objects.githubusercontent.com/" "objects.githubusercontent.com:443:$objip")"

echo
echo "== ② raw.githubusercontent.com：DoH 答案直连（p29 报 0.14 秒 0 字节，那条到底是不是死）"
RIP=$(curl -sk -m 8 "https://223.5.5.5/resolve?name=raw.githubusercontent.com&type=A" 2>/dev/null |
  node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);
    console.log((j.Answer||[]).filter(x=>x.type===1).map(x=>x.data)[0]||"无");}catch(e){console.log("无");}});')
printf '  DoH=%s ⇒ %s\n' "${RIP:-无}" "$(pull "https://raw.githubusercontent.com/sherpa-onnx/sherpa-onnx/master/README.md" "raw.githubusercontent.com:443:$RIP")"

echo
echo "== ③ 最关键的一条：chroot 里真跑一发 git ls-remote（他以后就是这个动作）"
command -v git >/dev/null || { echo "  chroot 里没有 git 这个命令（那要先装，装就得走 apt 源）"; }
if command -v git >/dev/null; then
  T0=$(date +%s)
  OUT=$(GIT_TERMINAL_PROMPT=0 timeout 40 git -c http.connectTimeout=8 ls-remote https://github.com/sherpa-onnx/sherpa-onnx.git HEAD 2>&1 | head -3)
  printf '  耗时 %ss  回：%s\n' "$(( $(date +%s) - T0 ))" "${OUT:-空输出}"
fi

echo
echo "== ④ apt 那条：现在配的源主机是谁（只 cat，不发 update）"
grep -hvE '^\s*#|^\s*$' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null | head -8 | sed 's/^/  /'
for H in $(grep -rhoE 'https?://[^ /]+' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null | sed 's#https\?://##' | sort -u | head -6); do
  printf '  源主机 %-30s hosts命中=%s DoH=%s\n' "$H" "$(grep -cE "[[:space:]]$H\$" /etc/hosts)" \
    "$(curl -sk -m 8 "https://223.5.5.5/resolve?name=$H&type=A" 2>/dev/null | head -c 60)"
done
