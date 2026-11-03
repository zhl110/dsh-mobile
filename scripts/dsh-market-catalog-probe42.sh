#!/usr/bin/env bash
# dsh-market-catalog-probe42.sh —— 只读：手机上「插件市场一直在加载插件目录」到底卡在哪一层
#
# 他 18:4x 报的：进 App → 插件市场 → 「正在加载插件目录…」一直不消失。
# 读 PC 侧那份 dshmarket 的源码（本机 desktop profile 下的 node_modules/dshmarket/lib/，各人路径不同）
# 先知道了这三件事，所以这一发是去验它们在他机上成不成立：
#   1) 目录不是打包在前端的，是**每次请求都现取**：regions.js 里 china 区先取
#      mirrors.cloud.tencent.com/npm 上那个 dsh-plugin-catalog 包，取不到才回 awesome-dsh-plugin.com/plugins.json；
#      global 区只有后面那一个地址。区是**首次启动时按 npm registry 的响应速度选一次、写死进 state.json**（源码注释自己写了这是盲区：
#      探针只量 registry，不量目录那个 host ⇒ "catalog fetch failed" forever）。
#   2) 目录体积在 1 MB 级以上（PC 上那份 discovery-compatibility-v1.json = 1,084,602 B；
#      源码注释记的实测：允许跑完是 89.9 s，15 s 总超时会在还在下的时候掐断）。
#   3) 前端取的是 /dsh-market/*（host 路由），由引擎那台 :3080 提供，入口 :3081 转发。
#
# 这一发一个字节不写盘（curl 全 -o /dev/null），不下整份目录：只 HEAD 拿大小、
# 再拿 --max-time 12 截一段算吞吐。凭证不进 argv：门禁 cookie 一律不带，
# 被门禁挡本身就是要读的数（哪一层挡的）。日志只 grep 含关键字的行，入口那份已过 redact。
set -u

S() { command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | awk 'NR>1 {print $4}'; }

echo "== 0. 时刻（chroot 是 UTC；北京 = UTC+8）"
echo "  UTC  $(date -u '+%F %T')"
echo "  北京 $(TZ=Asia/Shanghai date '+%F %T' 2>/dev/null || date '+%F %T')"

echo "== 1. 区是怎么定的：手机上那份 state.json 与 log.ndjson 原文（都是小文件，整读）"
for f in /root/.dsh/profiles/web/.dsh-market/state.json /root/.dsh/profiles/web/.dsh-market/log.ndjson; do
  if [ -f "$f" ]; then
    printf '  --- %s（%s B，改于 %s）\n' "$f" "$(stat -c %s "$f")" "$(stat -c %y "$f" | cut -d. -f1)"
    sed 's/^/      /' "$f"
  else
    printf '  --- %s 不存在\n' "$f"
  fi
done

echo "== 2. 目录那三个地址，从 chroot 里量（HEAD 拿声称大小，不下载正文）"
for u in \
  "https://mirrors.cloud.tencent.com/npm/dsh-plugin-catalog" \
  "https://awesome-dsh-plugin.com/plugins.json" \
  "https://registry.npmjs.org/dsh-plugin-catalog" \
  "https://gh-proxy.com/https://raw.githubusercontent.com/dsh-market/dsh-market/main/README.md"
do
  R=$(curl -sI -o /dev/null --max-time 12 \
        -w 'code=%{http_code} dns=%{time_namelookup}s total=%{time_total}s len=%{size_download}B' "$u" 2>&1)
  printf '  %-96s %s\n' "${u##https://}" "$R"
done

echo "== 3. 真取一段算吞吐：只跑 8 秒就断，正文丢掉（这一发花的是他的流量，故意截短）"
# 第一版写的是 12 秒（7568 B 那版），改成 8 是替他省流量：腾讯那面要是快，12 秒能下好几 MB，
# 而 8 秒足够把「解析失败/连不上」和「连上了但在慢慢下」分开（KB/s = 拿到的字节 / 8）。
for u in \
  "https://mirrors.cloud.tencent.com/npm/dsh-plugin-catalog/latest" \
  "https://awesome-dsh-plugin.com/plugins.json"
do
  R=$(curl -s -o /dev/null --max-time 8 \
        -w 'code=%{http_code} dns=%{time_namelookup}s connect=%{time_connect}s ttfb=%{time_starttransfer}s total=%{time_total}s got=%{size_download}B' "$u" 2>&1)
  printf '  %-56s %s\n' "${u##https://}" "$R"
done

echo "== 4. /etc/hosts 里钉了谁（钉进 hosts 的 IP 会漂；这里只列域名，够判这两个 host 在不在名单里）"
if [ -f /etc/hosts ]; then
  awk '!/^#/ && NF>=2 && $2 !~ /^(localhost|ip6-localhost|localhost.localdomain|ip6-loopback)$/ {print "      " $1 "  " $2}' /etc/hosts | sort -u
  awk '!/^#/ && NF>=2 {n++} END {print "  hosts 生效条目数 = " n+0}' /etc/hosts
  for h in mirrors.cloud.tencent.com awesome-dsh-plugin.com registry.npmjs.org; do
    C=$(awk -v h="$h" '!/^#/ && $2==h {n++} END {print n+0}' /etc/hosts)
    echo "      $h 在 hosts 里？$([ "$C" -gt 0 ] && echo 在 || echo 不在)"
  done
fi

echo "== 5. 引擎那台 :3080 上 /dsh-market/* 路由在不在（直接打引擎，不过门禁）"
for p in /dsh-market/status /dsh-market/registry /dsh-market/logs; do
  R=$(curl -s -o /dev/null --max-time 12 -w 'code=%{http_code} total=%{time_total}s got=%{size_download}B' "http://127.0.0.1:3080$p" 2>&1)
  printf '  3080 %-22s %s\n' "$p" "$R"
done
echo "  --- 同一批发给入口 :3081（不带门禁 cookie ⇒ 预期被门禁挡；挡在哪一层就是要看的）"
for p in /dsh-market/status /dsh-market/registry; do
  R=$(curl -s -o /dev/null --max-time 12 -w 'code=%{http_code} total=%{time_total}s got=%{size_download}B' "http://127.0.0.1:3081$p" 2>&1)
  printf '  3081 %-22s %s\n' "$p" "$R"
done

echo "== 6. 入口流水里最近那几条 dsh-market（他打开市场页时前端到底请了哪些路径、各拿到什么码）"
LOG=/root/.dsh/entry.log
if [ -f "$LOG" ]; then
  echo "  entry.log = $(stat -c %s "$LOG") B，$(wc -l < "$LOG") 行"
  echo "  --- 含 dsh-market 的行（全量，最多 30 条；这文件落盘前已过 redact，token/门禁值都不在正文里）"
  grep -a 'dsh-market' "$LOG" | tail -30 | sed 's/^/      /'
  M=$(grep -ac 'dsh-market' "$LOG" 2>/dev/null); echo "  含 dsh-market 的行数 = ${M:-0}"
else
  echo "  entry.log 不在位（$(ls -1 /root/.dsh/*.log 2>/dev/null | tr '\n' ' ')）"
fi

echo "== 7. profile 侧：dshmarket 在不在 bundles 里、装到了哪、版本多少"
PJ=/root/.dsh/profiles/web/package.json
if [ -f "$PJ" ]; then
  echo "  bundles 里 dshmarket 命中行 = $(grep -c 'dshmarket' "$PJ")"
  grep -o 'dshmarket[^"]*' "$PJ" | sed 's/^/      /'
fi
M=/root/.dsh/profiles/web/node_modules/dshmarket
if [ -d "$M" ]; then
  echo "  落盘：$(stat -c %y "$M" | cut -d. -f1)  package.json 里 version = $(grep -m1 '"version"' "$M/package.json" | tr -d ' ,"' | cut -d: -f2)"
  echo "  lib/registry.js 在位？$([ -f "$M/lib/registry.js" ] && echo 在 || echo 不在)；client/client.js 在位？$([ -f "$M/client/client.js" ] && echo 在 || echo 不在)"
else
  echo "  !! $M 不存在"
fi

echo "== 8. 引擎与入口进程现场（出生按 /proc/pid/stat 第 22 字段 + btime 算）"
BOOT=$(awk '/^btime/ {print $2}' /proc/stat); UP=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1); HZ=$(getconf CLK_TCK 2>/dev/null); [ -n "$HZ" ] || HZ=100
for p in $(pgrep -f 'dsh web|dsh-entry.js'); do
  ST=$(awk '{print $22}' "/proc/$p/stat" 2>/dev/null)
  CMD=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | cut -c1-64)
  [ -n "$ST" ] && printf '    pid %-7s 出生 %s UTC  活着 %s 秒  cmd=%s\n' "$p" "$(date -u -d "@$((BOOT + ST / HZ))" '+%F %T')" "$((UP - ST / HZ))" "$CMD"
done
echo "  --- 监听（awk 数第 4 列，与上面同源）"
command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | awk 'NR>1 && ($4 ~ /:(3080|3081)$/) {print "    监听 " $4}'
echo "  --- dshmarket 有没有在 node_modules 里被别的包软链引用（只数一下）"
find /root/.dsh/profiles/web/node_modules/.pnpm -maxdepth 1 -name 'dshmarket*' 2>/dev/null | wc -l | sed 's/^/    .pnpm 里命中 = /'

echo "== 9. 引擎自己有没有为 market 写过日志文件（只列名与大小，不 cat 全文）"
find /root/.dsh -maxdepth 3 -newermt '-3 hours' \( -name '*.log' -o -name '*.ndjson' -o -name '*.json' \) 2>/dev/null | while read -r f; do
  printf '  %s  %8s B  %s\n' "$(stat -c %y "$f" | cut -d. -f1)" "$(stat -c %s "$f")" "$f"
done | head -20
echo " 完（一个字节没写；curl 全打 /dev/null；没重启引擎、没点「应用」、没替他开任何页面）"
