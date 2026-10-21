#!/usr/bin/env bash
# dsh-engine-restart-and-verify44.sh —— 重启一次引擎（让他 19:0x 点头的那条），并把两件事复点干净
#
# 为什么要重启：入口 spawn 引擎那条命令是 `. /root/.dsh-env >/dev/null 2>&1; cd /phone; exec dsh web …`
# （scripts/dsh-entry.js:70）—— 这个文件只在 spawn 那一刻 source 一次，所以刚推进去的
# DSHM_NPM_MIRROR 必须等一次引擎重启才吃进去。
# 为什么不用 --stop/--entry：入口自己有监管（child.on('exit') ⇒ S.backoff ms 后重拉，
# scripts/dsh-entry.js:168-177），杀引擎就够了，入口不动 ⇒ 他手机上的 cookie/门禁都不用重新换。
#
# 四条纪律：
#   1. 杀之前先认身份：cmdline 里必须有 'dsh web'，并且「这样的进程恰好 1 个」才杀；入口（dsh-entry.js）绝不杀。
#      这条同时给待办 #45 攒证据：PID 会复用，光看 pid 不看 cmdline 就会杀错人。
#   2. 验收解析**不带 --resolve**（p43 用 --resolve 只验了"那个 IP 通不通"，这一发要的是"钉进 hosts 之后
#      这条路自己通不通"）。
#   3. dsh-env 里可能有 key ⇒ 只列 export 的键名，值一个字符都不印。
#      （这一版第一稿这里写的是 cut -d= -f2，那正好把值打出来了 ⇒ 改口：键名要用 sed 从 = 左边取。）
#   4. 流量按 /proc/net/dev 全表读，rx=$2 tx=$10（第一稿误用过 $4−$2，$4 是第二个快照的接口名，会减出负数）。
#      有基线就报差集，没基线就把现值全表打出来当下一发的基线。
set -u
LOG=/root/.dsh/entry.log
ENVF=/root/.dsh-env

echo "== 0. 时刻（chroot 是 UTC；北京 = UTC+8）"
echo "  UTC  $(date -u '+%F %T')"
echo "  北京 $(TZ=Asia/Shanghai date '+%F %T' 2>/dev/null || date '+%F %T')"

BOOT=$(awk '/^btime/ {print $2}' /proc/stat); UP=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
HZ=$(getconf CLK_TCK 2>/dev/null); [ -n "$HZ" ] || HZ=100
who() { # pid ⇒ "出生UTC 已活秒 cmd"
  # 改口（跑完 p44 之后就地补的）：第一版这里用的是脚本开头那次 `UP` 快照，
  # 于是"重启后新生的引擎"算出 **活着 -3 秒** —— 不是设备的问题，是**年龄用了过期的现在时刻**。
  # 正确写法：年龄要在打的那一刻重新读 /proc/uptime，出生时刻才是可以用开机后秒数反推的。
  local p=$1 ST CMD UPNOW
  UPNOW=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
  ST=$(awk '{print $22}' "/proc/$p/stat" 2>/dev/null); CMD=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | cut -c1-58)
  [ -n "$ST" ] && printf 'pid %-7s 出生 %s UTC 活着 %5s 秒  %s\n' "$p" "$(date -u -d "@$((BOOT + ST / HZ))" '+%F %T')" "$((UPNOW - ST / HZ))" "$CMD"
}

echo "== 1. 重启前现场（先把「要杀谁」数清楚，只杀那一个）"
ALL=$(pgrep -f 'dsh web' | tr '\n' ' ')
N=0; EG=''
for p in $ALL; do
  if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'dsh web'; then N=$((N+1)); [ -z "$EG" ] && EG=$p; fi
done
EN=$(pgrep -f 'dsh-entry.js' | head -1)
echo "  cmdline 含 'dsh web' 的进程数 = $N（pgrep 候选：${ALL:-无}）"
echo "  引擎  ${EG:-（没抓到）}  $( [ -n "$EG" ] && who "$EG" )"
echo "  入口  ${EN:-（没抓到）}  $( [ -n "$EN" ] && who "$EN" )"
[ "$N" = "1" ] || { echo "  !! 不是恰好 1 个引擎 ⇒ 按纪律停手不杀（先看清这几个各是谁）"; exit 1; }
[ -n "$EN" ] || { echo "  !! 没抓到入口进程 ⇒ 杀了引擎没人重拉，停手"; exit 1; }
[ "$EN" != "$EG" ] || { echo "  !! 引擎与入口同一个 pid（不该发生）⇒ 停手"; exit 1; }
echo "  STOPPED 哨兵：$( [ -e /root/.dsh/entry-stopped ] && echo '在位（那入口不会重拉，得先清）' || echo 不在位 )"
echo "  监听：$(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:(3080|3081)$/ {printf "%s ", $4}')命中数 $(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:(3080|3081)$/' | wc -l)"

echo "== 2. 解析层复点（不带 --resolve）"
printf '  awesome-dsh-plugin.com  hosts 行 = %s\n' "$(awk '$2=="awesome-dsh-plugin.com" {print $1}' /etc/hosts | tr '\n' ' ')"
printf '  %-32s %s\n' "plugins.json（HEAD）" "$(curl -sI -o /dev/null -m 12 -w 'code=%{http_code} dns=%{time_namelookup}s ttfb=%{time_starttransfer}s total=%{time_total}s' https://awesome-dsh-plugin.com/plugins.json 2>&1)"
printf '  %-32s %s\n' "npmmirror 目录包元数据" "$(curl -s -o /dev/null -m 12 -w 'code=%{http_code} dns=%{time_namelookup}s ttfb=%{time_starttransfer}s total=%{time_total}s' https://registry.npmmirror.com/dsh-plugin-catalog/latest 2>&1)"

echo "== 3. dsh-env 里现在有哪些 export 键（只列键名，值不印）"
sed -n 's/^export \([A-Za-z0-9_]*\)=.*/    \1/p' "$ENVF" 2>/dev/null
echo "  export 行数 = $(grep -c '^export' "$ENVF" 2>/dev/null)  文件 = $(stat -c %s "$ENVF" 2>/dev/null) B  权限 $(stat -c '%a %U:%G' "$ENVF" 2>/dev/null)"
echo "  DSHM_NPM_MIRROR 那行在不在（只看命中行数）：$(grep -c '^export DSHM_NPM_MIRROR=' "$ENVF" 2>/dev/null)"

echo "== 4. 杀引擎（只认 cmdline 含 'dsh web' 的那一个；入口不动）"
CMD=$(tr '\0' ' ' < "/proc/$EG/cmdline" 2>/dev/null)
case "$CMD" in
  *'dsh web'*)
    echo "    认到人：pid $EG 的 cmdline 里有 'dsh web' ⇒ 杀"
    kill "$EG" && echo "    [ok] 已 SIGTERM $EG"
    ;;
  *) echo "    !! pid $EG 的 cmdline 里没有 'dsh web'（=[$CMD]）⇒ 不杀，这一格到此为止"; exit 1;;
esac

echo "== 5. 等入口自己重拉（最多 120 秒；每 5 秒点一次端口与进程）"
i=0; NEW=''
while [ $i -lt 24 ]; do
  i=$((i+1)); sleep 5
  NEW=$(pgrep -f 'dsh web' | head -1)
  L=$(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:3080$/' | wc -l)
  echo "    第 ${i} 次（已过 $((i*5)) 秒）：引擎 pid=${NEW:-没起来}  :3080 命中=$L"
  [ -n "$NEW" ] && [ "$NEW" != "$EG" ] && [ "$L" -ge 1 ] && break
done
if [ -n "$NEW" ] && [ "$NEW" != "$EG" ]; then
  echo "  [ok] 换代成功：$EG ⇒ $NEW（$(who "$NEW")）"
else
  echo "  !! 120 秒里没看到新引擎在 :3080 上监听 ⇒ 要人工看入口日志与哨兵，先别当成重启完成"
fi

echo "== 6. 新引擎吃没吃到那行 env"
if [ -n "$NEW" ]; then
  tr '\0' '\n' < "/proc/$NEW/environ" 2>/dev/null | sed -n 's/^\(DSHM[A-Za-z0-9_]*\)=.*/    \1=<有值>/p'
  echo "    DSHM_ 键计数 = $(tr '\0' '\n' < "/proc/$NEW/environ" 2>/dev/null | grep -c '^DSHM')"
  echo "    DSH_PERMISSION_MODE 在不在（只看键，值不看）：$(tr '\0' '\n' < "/proc/$NEW/environ" 2>/dev/null | grep -c '^DSH_PERMISSION_MODE=')"
  echo "    cwd=$(readlink "/proc/$NEW/cwd" 2>/dev/null)  入口 pid 还是不是 $EN：$( [ -d "/proc/$EN" ] && echo 是 || echo '入口变了' )"
  echo "  --- 换代后市场路由还在不在（直接打 :3080，不带 cookie ⇒ 401=挂着且要登录，404=没挂上）"
  for R in /dsh-market/status /dsh-market/registry; do
    printf '    3080 %-24s %s\n' "$R" "$(curl -s -o /dev/null -m 8 -w 'code=%{http_code} got=%{size_download}B' http://127.0.0.1:3080$R 2>&1)"
  done
fi

echo "== 7. 入口日志最后 10 行（这文件落盘前已过 redact；token 与门禁值都不在正文里）"
tail -10 "$LOG" 2>/dev/null | sed 's/^/      /'

echo "== 8. 市场那侧现在什么形状"
echo "  state.json：$(cat /root/.dsh/profiles/web/.dsh-market/state.json 2>/dev/null)"
echo "  log.ndjson = $(stat -c %s /root/.dsh/profiles/web/.dsh-market/log.ndjson 2>/dev/null) B，改于 $(stat -c %y /root/.dsh/profiles/web/.dsh-market/log.ndjson 2>/dev/null | cut -d. -f1)"
echo "  --- 最后一条"
tail -1 /root/.dsh/profiles/web/.dsh-market/log.ndjson 2>/dev/null | sed 's/^/      /'

echo "== 9. 现场网络计数（口径：/proc/net/dev 全表，rx=\$2 tx=\$10）"
# 改口：BSL 这个路径是**手机 chroot 里的 /tmp**，而 18:56 那份基线当时是我在 PC 的 git-bash /tmp 里重定向存的
# —— 两个 /tmp 不是一回事，所以这一格设备侧永远报"基线不在"。这一轮的差集在 PC 上算（见 RUNBOOK 14.28），
# 基线也已从 PC /tmp 抄进项目：downloads/net-full-20261021-185612.txt（`名字 rx tx` 三列，30 行）。
BSL=/tmp/net_full_before.txt
if [ -f "$BSL" ]; then
  echo "  基线 = $BSL（$(stat -c %s "$BSL") B）⇒ 下面每行是「现在减基线」，只数 wlan* 与 rmnet*，负数按 0 截"
  awk 'NR==FNR { if (FNR>2) { n=$1; sub(/:/,"",n); brx[n]=$2; btx[n]=$10 } ; next }
       FNR>2 { n=$1; sub(/:/,"",n)
               if (n ~ /^(wlan|rmnet)/ && (n in brx)) { r=$2-brx[n]; s=$10-btx[n]
                     if (r<0) r=0; if (s<0) s=0
                     if (r>0 || s>0) printf "    %-14s rx+%d  tx+%d  合计%d B\n", n, r, s, r+s
                     t += r+s } }
       END { printf "    wlan+rmnet 增量总计 = %d B（约 %.2f MiB）\n", t+0, (t+0)/1048576 }' "$BSL" /proc/net/dev
else
  echo "  基线不在（$BSL 没有）⇒ 这一发只给现值；下面全表就是下一发的基线"
fi
echo "  --- 全表现值（只列 rx/tx 两列）"
awk 'NR>2 {n=$1; sub(/:/,"",n); printf "    %-16s rx=%-14d tx=%-14d\n", n, $2, $10}' /proc/net/dev
echo " 完（这一发动了两个东西：SIGTERM 旧引擎、由入口自己重拉出新引擎；没动 hosts、没动入口、没重启手机、没点「应用」、没替他开任何页面）"
