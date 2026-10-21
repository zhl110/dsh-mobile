#!/usr/bin/env bash
# dsh-market-check-probe45.sh —— 只读复点：换代之后市场这一格动了没有（他有没有真打开过页面），顺带把流量全表抄一份
#
# 为什么单独一发：14.28 那格我写的最后一句是"log.ndjson 停在 6,606 B / 10:40:50Z ⇒ 换代后没人请求过目录"，
# 铁律 3 说"没报错不算通过"，那"通过"长什么样得有人真打开一次页面才算数。这一发不问凭证、不触发任何请求，
# 只看他手上那一下留没留痕。
set -u
M=/root/.dsh/profiles/web/.dsh-market

echo "== 0. 时刻（chroot 是 UTC；北京 = UTC+8）"
echo "  UTC  $(date -u '+%F %T')"
echo "  北京 $(TZ=Asia/Shanghai date '+%F %T' 2>/dev/null || date '+%F %T')"

echo "== 1. 三层现场（引擎该是第 4 代 21363；UP 现读，不拿开头快照算年龄）"
BOOT=$(awk '/^btime/ {print $2}' /proc/stat)
UP=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
HZ=$(getconf CLK_TCK 2>/dev/null); [ -n "$HZ" ] || HZ=100
for P in $(pgrep -f 'dsh web|dsh-entry.js'); do
  CMD=$(tr '\0' ' ' < "/proc/$P/cmdline" 2>/dev/null | cut -c1-56)
  ST=$(awk '{print $22}' "/proc/$P/stat" 2>/dev/null)
  case "$CMD" in *'dsh web'*) TAG=引擎;; *dsh-entry.js*) TAG=入口;; *) TAG=别的;; esac
  [ -n "$ST" ] && printf '  %s pid %-7s 出生 %s UTC 活着 %6s 秒  %s\n' "$TAG" "$P" "$(date -u -d "@$((BOOT + ST / HZ))" '+%F %T')" "$((UP - ST / HZ))" "$CMD"
done
echo "  监听命中数（与下面同一 awk 同源）= $(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:(3080|3081)$/' | wc -l)"
ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:(3080|3081)$/ {printf "    %s\n", $4}'

echo "== 2. 市场那两个文件（state.json 与 log.ndjson）"
echo "  state.json：$(cat $M/state.json 2>/dev/null)"
echo "  log.ndjson = $(stat -c %s $M/log.ndjson 2>/dev/null) B，改于 $(stat -c %y $M/log.ndjson 2>/dev/null | cut -d. -f1)（UTC）"
echo "  行数 = $(wc -l < $M/log.ndjson 2>/dev/null)（14.28 那记是 6,606 B；10-21 探针 42 数过它是 20 行上下）"
echo "  --- 最后 3 行"
tail -3 $M/log.ndjson 2>/dev/null | sed 's/^/      /'
echo "  --- 有没有 info/成功形状的行（只数列）"
for K in '"level":"info"' '"level":"warn"' 'catalog fetch failed' 'fetch failed'; do
  printf '    %-24s 命中行数 = %s\n' "$K" "$(grep -c "$K" $M/log.ndjson 2>/dev/null)"
done

echo "== 3. 目录那两个 host 现在还在钉表里吗（只看行，不发请求）"
awk '$2=="awesome-dsh-plugin.com" || $2=="registry.npmmirror.com" {printf "    %-26s %s\n", $2, $1}' /etc/hosts
echo "    hosts 生效行数 = $(grep -vc '^#\|^$' /etc/hosts)"

echo "== 4. 流量全表现值（口径：/proc/net/dev，rx=\$2 tx=\$10；这一发不改任何东西，抄回去当基线）"
awk 'NR>2 {n=$1; sub(/:/,"",n); printf "%s %s %s\n", n, $2, $10}' /proc/net/dev | sed 's/^/    /'

echo "== 5. 机上现在跑着的探针之外有没有我留的临时件（自查）"
ls -1 /tmp 2>/dev/null | head -8
echo "    /tmp 条目数 = $(ls -1 /tmp 2>/dev/null | wc -l)  chroot /root 里 .sh 数 = $(ls -1 /root/*.sh 2>/dev/null | wc -l)"
echo " 完（全只读：没发任何会取目录的请求、没点「应用」、没重启、没写盘）"
