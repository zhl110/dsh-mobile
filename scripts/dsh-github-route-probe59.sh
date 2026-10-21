#!/bin/bash
# dsh-github-route-probe59.sh —— github 这一跳今晚到底通不通，把错误文本取出来，不许停在 code=000。
#
# 触发这一发的读数（downloads/p58.txt 第 1、2 节）：
#   github.com 三种打法（不带 --resolve / 钉 .166 / 首页 Range）全是 code=000 bytes=0 connect=0.000s，
#   codeload.github.com 同样 000；而同一发里 objects.githubusercontent.com 回 404 + 425 B、
#   npmmirror / aliyun / plugins.json 都落字节 ⇒ **不是整机出网通了再断，是 github 那两跳单独坏**。
#   探针 57 里 github.com 那次 connect=1.098s（连上了又中止），这一发 connect=0.000s（连都没连上）——
#   **两发读数不一样本身就是证据**：这条路由今晚在漂，不能拿"昨天量到 676 KB"当今天的结论。
# 只读：不改 hosts、不 --sync、不装包。
set -u
DOH=https://223.5.5.5/resolve
E() { printf '  %-30s %s\n' "$1" "$(curl -sS -o /dev/null -m "$2" \
        -w 'code=%{http_code} bytes=%{size_download} connect=%{time_connect}s ttfb=%{time_starttransfer}s total=%{time_total}s' \
        ${@:3} "https://github.com/robots.txt" 2>&1 | tr '\n' ' | ')"; }

echo "== 1 现在这一刻 DoH 给 github 的 A 记录是什么"
curl -sk -m 10 "$DOH?name=github.com&type=A" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log("  Answer:",(j.Answer||[]).map(x=>x.type+":"+x.data).join("  "));});'
echo "  hosts 里 github / codeload 的行："
grep -nE '[[:space:]](github\.com|codeload\.github\.com|objects\.githubusercontent\.com)$' /etc/hosts | sed 's/^/    /'

echo "== 2 三种打法，带错误文本（-S 不吞 stderr），40 秒窗"
E '不带 --resolve（走 hosts）' 40
E '钉 hosts 里那条 .166'       40 --resolve github.com:443:20.205.243.166
E '钉 .165（codeload 那条）'   40 --resolve github.com:443:20.205.243.165

echo "== 3 TCP 层单测：443 握不握得上（5 秒窗，避开 curl 的 TLS 变量）"
for IP in 20.205.243.166 20.205.243.165 185.199.109.133; do
  if timeout 5 bash -c "exec 3<>/dev/tcp/$IP/443" 2>/dev/null; then T="TCP 连上"; else T="TCP 连不上"; fi
  exec 3<&- 2>/dev/null; exec 3>&- 2>/dev/null
  printf '  %-18s %s\n' "$IP:443" "$T"
done

echo "== 4 TLS 层单测：拿 node 直接握手，把错误名打出来（185.199.109.133 = objects 那台，作对照）"
node -e '
const tls=require("tls");
const hosts=[["20.205.243.166","github.com"],["20.205.243.165","github.com"],["185.199.109.133","objects.githubusercontent.com"]];
let i=0;
function go(){ if(i>=hosts.length) return; const [ip,sni]=hosts[i++];
  const s=tls.connect({host:ip,port:443,servername:sni,timeout:8000},()=>{
    console.log("  "+sni+" @ "+ip+" ⇒ 握手成，证书 "+(s.getPeerCertificate().subject.CN||"?")+"，用时 "+(Date.now()-t0)+"ms");
    s.end(); go(); });
  const t0=Date.now();
  s.on("tlsClientError",e=>{console.log("  "+sni+" @ "+ip+" ⇒ TLS 失败："+e.code+" ("+e.message+")"); go();});
  s.on("error",e=>{console.log("  "+sni+" @ "+ip+" ⇒ error："+e.code+" ("+e.message+")，用时 "+(Date.now()-t0)+"ms"); s.destroy(); go();});
  s.on("timeout",()=>{console.log("  "+sni+" @ "+ip+" ⇒ 8 秒窗内没动静"); s.destroy(); go();});
} go();'

echo "== 5 同一时刻，另一条 GitHub 路（objects 与 gh-proxy）落不落字节 —— 用来分「GitHub 整体」与「这跳 IP」"
printf '  %-24s %s\n' "objects.githubusercontent" \
  "$(curl -sS -o /dev/null -m 20 -w 'code=%{http_code} bytes=%{size_download} t=%{time_total}s' https://objects.githubusercontent.com/nope 2>&1 | tr '\n' ' ')"
printf '  %-24s %s\n' "codeload（tarball 路）" \
  "$(curl -sS -o /dev/null -m 20 -w 'code=%{http_code} bytes=%{size_download} t=%{time_total}s' https://codeload.github.com/torvalds/linux/ -r 0-1023 2>&1 | tr '\n' ' ')"
printf '  %-24s %s\n' "gh-proxy 镜像（境内那条）" \
  "$(curl -sS -o /dev/null -m 20 -w 'code=%{http_code} bytes=%{size_download} t=%{time_total}s' https://gh-proxy.com/https://github.com/torvalds/linux 2>&1 | tr '\n' ' ')"

echo "== 6 这发有没有留东西（应当 0）"
echo "  /root 下 .sh 计数（不含本探针）: $(ls /root/*.sh 2>/dev/null | grep -vc drift)"
