#!/bin/bash
# scripts/dsh-voice-picker-probe27.sh —— 把 p26 那两条读数钉死，顺便把"以后手机能不能自己下东西"的候选源一次测完。
#
# p26 留下的两个必须复测的点（都是我自己可能测错的地方）：
#   甲：baidu.com / www.qq.com / registry.npmjs.org 全报 v4=无 —— 可我把 getent 套了 timeout 6，
#       而 resolv.conf 写的是 timeout:2 attempts:2 且三条 nameserver 轮着试，最坏能拖到 12 秒以上。
#       所以"无答案"可能只是"6 秒内没等到"。这一发把上限放到 25 秒并**逐条报耗时**，
#       才能分清"DNS 彻底不通"和"DNS 慢"这两种完全不同的病。
#   乙：p26 里凡是"解析成功"的域名，除 huggingface.co 那一条外，**全都在 /etc/hosts 里被我钉过**
#       （libc 先查 hosts）⇒ 那批答案不能算 DNS 的功劳。这一发把 hosts 命中与否一起报出来。
# 候选源那一段是他问题的正解所在：这台机的形状是"境外 IP 连不上、国内 IP 通"，
# 所以要的不是"每次靠电脑"，而是"手机能不能直接够到国内镜像"。逐条 HEAD，超时 8 秒。
# 只读：不写 resolv.conf、不动 hosts、不装包、不改他的任何东西。口令不参与。
set -u
echo "== 甲. 慢查询复测（每条最多 25 秒，报出真实耗时；同时报这条域名在不在 hosts 里）"
for H in baidu.com www.qq.com registry.npmjs.org api.github.com mirrors.aliyun.com modelscope.cn; do
  HIT=$(grep -cE "[[:space:]]$H\$" /etc/hosts 2>/dev/null)
  T0=$(date +%s%N)
  A=$(timeout 25 getent ahostsv4 "$H" 2>/dev/null | awk '{print $1; exit}')
  RC=$?
  MS=$(( ($(date +%s%N) - T0) / 1000000 ))
  printf '  %-22s hosts命中=%s  %sms  退出=%s  v4=%s\n' "$H" "$HIT" "$MS" "$RC" "${A:-无}"
done

echo
echo "== 乙. 国内候选端点逐个 HEAD（8 秒上限；这一条就是「手机能不能自己下」的直接答案）"
for U in \
  https://mirrors.aliyun.com/ubuntu/ \
  https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ \
  https://registry.npmmirror.com/ \
  https://registry.npmjs.org/ \
  https://modelscope.cn/ \
  https://gitee.com/ \
  https://gh-proxy.com/ \
  https://ghfast.top/ \
  https://mirror.ghproxy.com/ \
  https://cdn.jsdelivr.net/ \
  https://github.com/ \
  https://huggingface.co/ \
  https://hf-mirror.com/ \
  https://deb.debian.org/ ; do
  R=$(curl -s -o /dev/null -m 8 --connect-timeout 5 -w 'http=%{http_code} time=%{time_total}s' "$U" 2>&1)
  printf '  %-52s %s\n' "$U" "${R:-报错}"
done

echo
echo "== 丙. 阿里的 DoH 正确端点（p26 我打的是 Cloudflare 那种 /dns-query，223.5.5.5 回的是「没有 dns 参数」）"
for Q in github.com huggingface.co registry.npmjs.org; do
  R=$(curl -sk -m 8 "https://223.5.5.5/resolve?name=$Q&type=A" 2>&1 | head -c 220)
  printf '  %-22s ⇒ %s\n' "$Q" "${R:-连不上}"
done

echo
echo "== 丁. 真拉一小发，验「通」是不是真通（npmmirror 上取一个包，看字节落没落盘）"
curl -s -m 15 -o /tmp/p27-probe.tgz -w '  http=%{http_code} size=%{size_download} time=%{time_total}s\n' \
  "https://registry.npmmirror.com/is-odd/-/is-odd-3.0.1.tgz" 2>&1
ls -l /tmp/p27-probe.tgz 2>&1 | sed 's/^/  /'
tar -tzf /tmp/p27-probe.tgz 2>&1 | head -3 | sed 's/^/  包内: /'
rm -f /tmp/p27-probe.tgz
