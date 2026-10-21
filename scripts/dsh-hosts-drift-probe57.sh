#!/bin/bash
# dsh-hosts-drift-probe57.sh —— 探针 56 报了"钉过的 IP 漂了"，这一发判**漂了到底坏没坏**。
#
# 为什么必须补这一发（读数 downloads/p56.txt 第 4 节）：
#   hosts 里 29 条，DoH 现在给的答案与钉进去的那条**对不上**的有 3 条：
#     registry.npmmirror.com  钉 111.62.184.148 / DoH 120.226.59.135
#     awesome-dsh-plugin.com  钉 185.199.108.153 / DoH 185.199.111.153
#     github.com              钉 20.205.243.165 / DoH 20.205.243.166
#   但"对不上"不等于"连不上"：钉的是 CDN 池里另一个边缘节点，很可能照样落字节。
#   ⇒ 判据只能是**真落字节**，不能是 IP 撞不撞。这一发把三条各测三遍（走 hosts / 走钉的旧 IP / 走 DoH 新 IP）。
# 只读：不写 hosts、不 --sync、不装包、不重启。
# 另一件事顺手量：--sync 的语义是"清单里**没有**的才钉"（脚本里 grep 到就 SKIP），
#   所以**漂了的条它一条也不会更新** —— 这条要写进文档，别让人以为跑一次 --sync 就修好了。
set -u
DOH=https://223.5.5.5/resolve
m() { # m <标签> <URL> <额外 curl 参数…>
  local tag=$1 url=$2; shift 2
  local out
  out=$(curl -s -o /dev/null -m 15 --max-filesize 200000 -w 'code=%{http_code} bytes=%{size_download} connect=%{time_connect}s ttfb=%{time_starttransfer}s' "$@" "$url" 2>&1)
  printf '  %-22s %s\n' "$tag" "$out"
}
doh_a() { curl -sk -m 10 "$DOH?name=$1&type=A" 2>/dev/null | sed -n 's/.*"data":"\([0-9.]*\)".*/\1/p' | head -1; }
pin_of() { awk -v d="$1" '!/^[[:space:]]*#/ && $0 ~ d {print $1}' /etc/hosts | head -1; }

echo "== 1 全场对账（这就是常规体检该跑的那条命令，只读）"
bash /root/doh-hosts.sh --check

echo
echo "== 2 漂了的三条：走 hosts / 走钉的旧 IP / 走 DoH 新 IP，各打一发看字节"
for H in registry.npmmirror.com awesome-dsh-plugin.com github.com; do
  P=$(pin_of "$H"); N=$(doh_a "$H")
  echo "--- $H（钉 $P / DoH $N）"
  m '不带 --resolve' "https://$H/"
  m "钉的旧 IP $P" "https://$H/" --resolve "$H:443:$P"
  [ -n "$N" ] && [ "$N" != "$P" ] && m "DoH 新 IP $N" "https://$H/" --resolve "$H:443:$N"
done

echo
echo "== 3 DSH 真正依赖的那几条，只问一句：不带 --resolve 能不能落字节"
for H in api.deepseek.com platform.deepseek.com registry.npmmirror.com cdn.npmmirror.com \
         mirrors.tuna.tsinghua.edu.cn pypi.tuna.tsinghua.edu.cn awesome-dsh-plugin.com \
         codeload.github.com objects.githubusercontent.com; do
  P=$(pin_of "$H")
  printf '  %-34s 钉=%-16s %s\n' "$H" "${P:-没钉}" \
    "$(curl -s -o /dev/null -m 15 --max-filesize 200000 -w 'code=%{http_code} bytes=%{size_download} t=%{time_total}s' "https://$H/" 2>&1)"
done

echo
echo "== 4 这发有没有在机上留东西（应当 0：脚本由 runner 跑完即删，本探针不写文件）"
echo "chroot /tmp 下 dsh-* 计数 : $(ls -d /tmp/dsh-* 2>/dev/null | wc -l)"
echo "chroot /root 下 *.sh 计数 : $(ls /root/*.sh 2>/dev/null | wc -l)  （探针 56 那发把自己也数进去了，runner 删完实际是 8）"
