#!/bin/bash
# scripts/dsh-voice-picker-probe26.sh —— 回答他那句"以后在手机上要下 GitHub 项目、下模型，是不是全得靠电脑"。
# 这个问题不能靠嘴答，要分层量：解析层 / 建连层 / TLS 层 / 有没有更干净的解析路（DoH）。
# 哪一层是坏的，决定解法完全不同：
#   只坏解析 ⇒ chroot 里起个本地解析转发就全通了（git clone、npm、模型都能手机自走）；
#   连 IP 直连都不通 ⇒ 手机端出站本身被拦，那才真的只能电脑下 + adb push，或走他电脑做代理。
# 出网计量：本探针会发若干**极小**请求（DNS 查询若干条 + 每域名一发 TLS HEAD），字节数在结果里报出来。
# 只读：不写 /etc、不改 resolv.conf、不装东西、不动他的 hosts。口令不参与。
set -u
echo "== 1. 解析配置现状（chroot 视角）"
printf '  resolv.conf：\n'; sed 's/^/    /' /etc/resolv.conf 2>&1 | head -8
printf '  /etc/hosts 里钉了几行非注释：%s\n' "$(grep -cvE '^\s*#|^\s*$' /etc/hosts 2>/dev/null)"
grep -vE '^\s*#|^\s*$' /etc/hosts 2>/dev/null | sed 's/^/    /' | head -8
printf '  proxy 类环境变量：%s\n' "$(env | grep -iE 'proxy' | tr '\n' ' ' || true)"
printf '  默认路由：\n'; ip route show 2>/dev/null | grep default | sed 's/^/    /'
printf '  IPv6 默认路由条数：%s\n' "$(ip -6 route show 2>/dev/null | grep -cE '^default|^::/0')"
ip -6 route show 2>/dev/null | grep -E '^default|^::/0' | sed 's/^/    /' | head -2

echo
echo "== 2. 解析层：一批域名各问 IPv4 / IPv6（getent 走的就是上面那个 resolv.conf）"
# 每条 getent 都套 timeout：这台机的解析器被污染时会**挂住**而不是报错，
# 上一发没套，整条探针在 200 秒上限里跑不完（这是我这次跑出来的读数，不是猜的）。
for H in baidu.com www.qq.com api.deepseek.com github.com api.github.com codeload.github.com raw.githubusercontent.com objects.githubusercontent.com registry.npmjs.org registry.npmmirror.com hf-mirror.com huggingface.co dl.google.com; do
  V4=$(timeout 6 getent ahostsv4 "$H" 2>/dev/null | awk '{print $1; exit}')
  V6=$(timeout 6 getent ahostsv6 "$H" 2>/dev/null | awk '{print $1; exit}')
  RC4=$?
  printf '  %-32s v4=%-16s v6=%s\n' "$H" "${V4:-无}" "${V6:-无}"
done

echo
echo "== 3. 建连 + TLS 层：拿上一段的 v4 答案直接连 443，发一发 HEAD（每域名最多一发，超时 6 秒）"
for H in baidu.com github.com raw.githubusercontent.com registry.npmmirror.com hf-mirror.com; do
  IP=$(timeout 6 getent ahostsv4 "$H" 2>/dev/null | awk '{print $1; exit}')
  if [ -z "$IP" ]; then printf '  %-26s 没答案，跳过\n' "$H"; continue; fi
  R=$(curl -s -o /dev/null -m 6 --resolve "$H:443:$IP" -w 'http=%{http_code} time=%{time_total}s size=%{size_download}' \
      --connect-timeout 4 "https://$H/" 2>&1)
  printf '  %-26s 连 %s ⇒ %s\n' "$H" "$IP" "${R:-curl 报错}"
done

echo
echo "== 4. 有没有更干净的解析路：DoH 问一发 github.com（-k 只为测路，不拿它当长期方案）"
for D in 1.1.1.1 8.8.8.8 223.5.5.5; do
  T0=$(date +%s)
  R=$(curl -sk -m 6 -H 'accept: application/dns-json' "https://$D/dns-query?name=github.com&type=A" 2>&1 | head -c 160)
  printf '  %-10s %ss ⇒ %s\n' "$D" "$(( $(date +%s) - T0 ))" "${R:-空/连不上}"
done

echo
echo "== 5. rootfs 这份 resolv.conf 是谁写的（chroot 里改它没意义，除非确认它是挂载时生成的）"
ls -l /etc/resolv.conf 2>&1 | sed 's/^/  /'
head -3 /root/.dsh-env 2>/dev/null | sed 's/^/  .dsh-env 前 3 行（值不外带）: /' | cut -c1-60
