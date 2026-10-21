#!/usr/bin/env bash
# dsh-traffic-and-cleanup-probe39.sh —— 收尾那一发：流量、现场、我自己留了什么（全只读）
#
# 为什么要这一发（2026-10-21 傍晚，插件装完之后）：
#   1) 今晚 17:47 开工时我**没取 /proc/net/dev 基线** —— 探针 32～38 一个都没带这一项。
#      所以"这轮走了多少网"这句话，按现有读数答不出**整轮增量**，只能答"我点得出的字节"
#      （探针 33 里那三次显式 curl：572,420 + 1,319 + 22,488 = 596,227 B，写在 14.27 七）。
#      这是事实，写在第一节，不糊。能诚实量的是"引擎空转 45 秒进出多少字节"
#      —— 那正是 14.13 那条流量口径留着要回答的问题（手机在不在偷跑）。
#   2) 我自己的临时件按读数清，不靠记忆：run-probe.sh 只删它自己推的那份探针，
#      /root/dsh-plugins/ 那两发 tarball 是我有意留的（package.json 里是 file: 引用）。
#   3) 三层栈的现场值留一格，给下次冷启动的人当"最后读数"。
#
# 只读边界：**不跑 --dump-config**（那一条会重写 profiles/web/cordis.yml，见 14.27 第四节），
# 不装不删不重启不动他的东西。本脚本只写 /tmp/p39_a 与 /tmp/p39_b 两个临时件，末尾删掉。
set -u

SNAP() { awk 'NR>2 {n=$1; sub(/:/,"",n); if (n ~ /^rmnet/ || n=="lo") printf "%s %d %d\n", n, $2, $10}' /proc/net/dev; }

echo "== 0. 时刻（chroot 本地时区是 UTC；北京 = UTC+8，见 14.22 那条时钟差）"
echo "  UTC  $(date -u '+%F %T')"
echo "  北京 $(TZ=Asia/Shanghai date '+%F %T')"

echo "== 1. 流量：snap A（$(date -u '+%T')）"
SNAP > /tmp/p39_a
awk '{printf "  A %-16s rx=%-13d tx=%-13d\n", $1, $2, $3}' /tmp/p39_a
SA=$(awk '{s+=$2} END {printf "%d", s}' /tmp/p39_a)
echo "  A 表内接口 rx 合计 = $SA B"

echo "== 2. 这 45 秒我这边的动作：只有这一支探针在手机上 sleep（ADB 走 USB，不占 rmnet）"
sleep 45

echo "== 3. 流量：snap B（$(date -u '+%T')）与差值（差值由 awk 算，我不口算）"
SNAP > /tmp/p39_b
awk '{printf "  B %-16s rx=%-13d tx=%-13d\n", $1, $2, $3}' /tmp/p39_b
SB=$(awk '{s+=$2} END {printf "%d", s}' /tmp/p39_b)
echo "  B 表内接口 rx 合计 = $SB B"
echo "  --- 逐接口 45 秒增量"
awk 'NR==FNR {rx[$1]=$2; tx[$1]=$3; next} ($1 in rx) {printf "    %-16s Δrx=%-10d Δtx=%-10d\n", $1, $2-rx[$1], $3-tx[$1]}' /tmp/p39_a /tmp/p39_b
echo "    rmnet 合计增量 = $(awk 'NR==FNR {r[$1]=$2; next} ($1 in r) && ($1 ~ /^rmnet/) {s+=$2-r[$1]} END {printf "%d", s}' /tmp/p39_a /tmp/p39_b) B / 45 s"

echo "== 4. 引擎与入口：现场值（出生时刻按 /proc/pid/stat 第 22 字段算，不用目录 mtime —— 14.27 四的第三个坑）"
# ↑ 这一节第一发（p39.txt）我算反了：把「出生=UP − 启动tick」当成自boot起的秒数直接喂给 date，
#   于是打出 1970-01-01；而「活着」那格取的是启动tick本身（=boot 后第几秒出生），不是进程年龄。
#   正确关系：boot 的 epoch = /proc/stat 的 btime；进程年龄 = UP − stat22/HZ。这里按这个重算，带箭头。
HZ=$(getconf CLK_TCK 2>/dev/null); [ -n "$HZ" ] || HZ=100
UP=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
BOOT=$(awk '/^btime/ {print $2}' /proc/stat)
[ -n "$BOOT" ] && echo "    开机时刻 = $(date -u -d "@$BOOT" '+%F %T') UTC（/proc/stat btime）；机器已活 $((UP/3600)) 小时"
for p in $(pgrep -f 'dsh-entry.js|dsh web' 2>/dev/null); do
  CMD=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | cut -c1-52)
  ST=$(awk '{print $22}' /proc/$p/stat 2>/dev/null)
  if [ -n "$ST" ] && [ -n "$UP" ] && [ -n "$BOOT" ]; then
    SINCE_BOOT=$(( ST / HZ ))
    printf '    pid %-7s 出生 %s UTC  活着 %s 秒（%s 小时）  cmd=%s\n' \
      "$p" "$(date -u -d "@$((BOOT + SINCE_BOOT))" '+%F %T')" "$((UP - SINCE_BOOT))" "$(( (UP - SINCE_BOOT) / 3600 ))" "$CMD"
  else
    echo "    pid $p  出生读不到（stat 第 22 字段或 btime 为空）cmd=$CMD"
  fi
done
echo "  --- 两个端口（只列监听，不发起请求）"
ss -ltn 2>/dev/null | awk '$4 ~ /:(3080|3081)$/ {print "    监听 " $4}'
# ↑ 第一发这里另有一行「命中行数 = 0」，与上面两条自相矛盾：grep 我按 `:(3080|3081)$` 匹配整行末尾，
#   而 ss 的行末还有 peer/process 列 —— 匹配不到不等于没监听。改用同一个 awk 数，两次读数同源。
echo "    监听命中数（与上面同源，awk 数第 4 列）= $(ss -ltn 2>/dev/null | awk '$4 ~ /:(3080|3081)$/' | wc -l)"

echo "== 4b. lo 上那 82 KB 是谁在说（回环有增量但 rmnet 为 0 ⇒ 只在本机内部）"
echo "  --- 现在活着的 TCP 连接（ss -tn；列：State Recv-Q Send-Q 本端 对端）"
ss -tn 2>/dev/null | awk 'NR>1 {printf "    %-10s %-8s 本端=%s 对端=%s\n", $1, $2, $4, $5}' | head -14
PORTS=':(3080|3081)$'
MYCONN=$(ss -tn 2>/dev/null | awk -v re="$PORTS" 'NR>1 && ($4 ~ re || $5 ~ re)' | wc -l)
echo "    与 :3081/:3080 相关的连接数 = $MYCONN"
echo "  --- 谁开着这些口/连接（-p 要 root；本探针在 chroot 里就是 root）"
ss -ttnp 2>/dev/null | grep -E "$PORTS" | head -8 | sed 's/^/    /'

echo "== 5. 这 45 秒里引擎有没有写盘（有写没流量 = 本地动作；两者都没有 = 真在睡觉）"
W=$(find /root/.dsh -newermt '-60 seconds' 2>/dev/null | wc -l)
echo "    最近 60 秒被动过的 /root/.dsh 条目数 = $W"
[ "$W" != "0" ] && find /root/.dsh -newermt '-60 seconds' 2>/dev/null | head -8 | sed 's/^/      /'

echo "== 6. 我自己留在机上的文件（按读数分「我建的」与「不是我建的」）"
echo "  --- chroot /root 下的 .sh（run-probe.sh 只删它自己推的那份）"
# ↑ 第一发这里字段取错过：--time-style=long-iso 的 ls -l 是 $1权限 $2硬链 $3主 $4组 $5大小 $6日期 $7时刻 $8名字，
#   我按「$6 $5 $1」打，把大小印在了日期后面、还把 B 挂在了权限串尾巴上。数据没丢，标签错了，这里改回来。
ls -l --time-style=long-iso /root/*.sh 2>/dev/null | awk '{printf "    %s %s  %7s B  %s\n", $6, $7, $5, $NF}'
echo "    计数 = $(ls -1 /root/*.sh 2>/dev/null | wc -l)（本探针跑的时候自己也在列表里 ⇒ 这一格含它自己一份；外层 run-probe.sh 删完再数的数才是残留真值）"
echo "  --- 有意留的两发 tarball（file: 引用指这里，删了下次重装就断）"
ls -l --time-style=long-iso /root/dsh-plugins/*.tgz 2>/dev/null | awk '{printf "    %6s B  %s\n", $5, $NF}'
echo "    计数 = $(ls -1 /root/dsh-plugins/*.tgz 2>/dev/null | wc -l)"
echo "  --- 本探针的临时件（下面删）"
ls -l --time-style=long-iso /tmp/p39_a /tmp/p39_b 2>/dev/null | awk '{printf "    %6s B  %s\n", $5, $NF}'
rm -f /tmp/p39_a /tmp/p39_b
echo "    删后复查：$(ls /tmp/p39_a /tmp/p39_b 2>&1 | head -2 | tr '\n' ' ')"

echo "== 7. 体积现值（上一记是 14.27 一的 /root/.dsh = 245 M）"
for d in /root/.dsh /root/.dsh/profiles/web /root/.dsh/redteam /root/.dsh/.agent-presets /root/.dsh/dsh-purge /root/.local/share/pnpm/store; do
  V=$(du -sh "$d" 2>/dev/null | cut -f1); [ -n "$V" ] || V='读不到'
  printf '    %-34s %s\n' "$d" "$V"
done
# ↑ 第一发这里把「剩」取了 $6 —— df -h 的列是 $1设备 $2总 $3已用 $4可用 $5使用率 $6挂载点，
#   $6 是挂载点 "/"，所以 p39.txt 打出来是「剩 /」。数据没错，列号错了，按 $4 重取。
df -h / 2>/dev/null | awk 'NR==2 {print "    盘：" $2 " 总，已用 " $3 "（" $5 "），可用 " $4 "，挂载点 " $6}'

echo "  完（只写了本探针那 /tmp 两件并已删；没跑 --dump-config，没重启，没点「应用」）"
