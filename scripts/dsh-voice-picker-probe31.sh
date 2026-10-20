#!/bin/bash
# scripts/dsh-voice-picker-probe31.sh —— 把"手机上能不能自己 clone GitHub 项目"量成一个数，别停在状态码上。
#
# p30 第①段那三条全报 404，是我 URL 写错了（仓库叫 k2-fsa/sherpa-onnx，不是 sherpa-onnx/sherpa-onnx），
# 但它顺带漏出一个更硬的读数：github.com 那张 404 页面在 10.87 秒里传回了 264,605 B ⇒ **连得上、传得动，只是慢（约 24 KB/s）**。
# 这条如果成立，"以后下 GitHub 项目"就不是"必须靠电脑"，而是"能自己下，看要不要提速"。所以要正面量：
#   ① 用正确 URL 各跑 30 秒封顶，算 KB/s（页面 + codeload 上的 tar.gz，后者就是 git clone 走的那条通道）；
#   ② 同一份资产走国内代理镜像（ghproxy.net 首页 p29 报 200）再算一次 KB/s —— 提速值不值；
#   ③ ModelScope 上有没有那份 SenseVoice 导出的同名字节（HEAD 看 Content-Length 等不等于 239,233,841）。
#      这条只是探路：仓库名我是猜的，猜不中就照实报"没验到"，不许把猜写成结论。
# 出网计量在结果末尾汇总（每一发都报 size_download）。
# 只读：不 clone、不落盘（全丢 /dev/null）、不装包、不写 hosts。口令不参与。
set -u
tot=0
pull() { # $1=URL $2=host:ip（可空）$3=上限秒
  local extra=() r
  [ -n "${2:-}" ] && extra=(--resolve "$2")
  r=$(curl -sL -m "${3:-30}" --connect-timeout 6 "${extra[@]}" -o /dev/null \
        -w 'http=%{http_code} size=%{size_download} time=%{time_total}s' "$1" 2>&1)
  local sz=$(printf '%s' "$r" | sed -n 's/.*size=\([0-9]*\).*/\1/p')
  tot=$(( tot + ${sz:-0} ))
  printf '%s' "$r"
}
gh=$(grep -E "[[:space:]]github\.com\$" /etc/hosts | head -1 | awk '{print $1}')
cl=$(grep -E "[[:space:]]codeload\.github\.com\$" /etc/hosts | head -1 | awk '{print $1}')

echo "== ① GitHub 直连（拿 DoH/hosts 里的 IP，30 秒封顶）"
printf '  仓库首页(k2-fsa/sherpa-onnx)  %s\n' "$(pull "https://github.com/k2-fsa/sherpa-onnx" "github.com:443:$gh" 30)"
printf '  codeload 上的 master.tar.gz   %s\n' "$(pull "https://codeload.github.com/k2-fsa/sherpa-onnx/tar.gz/refs/heads/master" "codeload.github.com:443:$cl" 30)"

echo
echo "== ② 走国内代理镜像同一份（DoH 拿 IP ⇒ 直连，别用没解析的 000 判死）"
doh() {
  curl -sk -m 8 "https://223.5.5.5/resolve?name=$1&type=A" 2>/dev/null |
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);
      console.log((j.Answer||[]).filter(x=>x.type===1).map(x=>x.data)[0]||"无");}catch(e){console.log("无");}});'
}
for G in ghproxy.net gh-proxy.com ghfast.top; do
  IP=$(doh "$G")
  case "$IP" in *[0-9]*) ;; *) printf '  %-14s DoH 无答案\n' "$G"; continue ;; esac
  printf '  %-14s 连 %s ⇒ %s\n' "$G" "$IP" "$(pull "https://$G/https://github.com/k2-fsa/sherpa-onnx/archive/refs/heads/master.tar.gz" "$G:443:$IP" 30)"
done

echo
echo "== ③ ModelScope 上探那份模型（HEAD 看 Content-Length；仓库名是猜的，猜不中就报没验到）"
MST=$(doh www.modelscope.cn); MS=${MST%%,*}
for U in \
  "https://www.modelscope.cn/models/pengzhendong/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/master/model.int8.onnx" \
  "https://www.modelscope.cn/models/AI-ModelScope/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/master/model.int8.onnx" \
  "https://www.modelscope.cn/models/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/master/model.int8.onnx" ; do
  printf '  %s\n    ⇒ %s\n' "$(printf '%s' "$U" | sed 's#.*/models/##; s#/resolve.*##')" \
    "$(curl -sI -m 15 --resolve "www.modelscope.cn:443:$MS" -o /dev/null -w 'http=%{http_code} content-length=%{size_download} 头长=%{size_header}B' "$U" 2>&1)"
done

echo
echo "== 出网合计（探针内可计的部分）：$tot B（GET 部分；HEAD 那几发不计入，每条几字节到几百字节）"
