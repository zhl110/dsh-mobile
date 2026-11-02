#!/bin/bash
# dsh-payload-survey-probe89.sh —— 只读，补 88 那两个 bug 的数：rootfs 本体的真实体积与结构计数。
# 88 错在哪（就地记着，别再犯）：
#   1) du/find 只靠 -x 不够 —— /phone 是他手机存储的 bind 挂载，跟 / 在同一块 dm-74 f2fs 上，
#      -x 不跳"同一设备的另一个挂载点"，于是 375 GB 里全是他相册的录屏。这一发显式排除四项。
#   2) du 的 -s 与 --max-depth=1 一起用，两处都打出空读数（空读数不能读成"没有"）；这发不带 -s 并打 rc。
#   3) /proc/uptime 第一字段带小数，塞进 $(( )) 报 invalid arithmetic operator；先砍小数。
#   4) 顺带：-prune 是 find 的谓词，du 不认 —— du 要用 --exclude。
# 不写任何文件、不装包、不动 hosts、不重启进程。
set -u
Q() { printf '\n== %s\n' "$1"; }
# du 用这个；find 用那个（别混）
DX="--exclude=/phone --exclude=/proc --exclude=/sys --exclude=/dev"
FP="-path /phone -prune -o -path /proc -prune -o -path /sys -prune -o -path /dev -prune -o"

Q "0 时间与排除口径"
echo "chroot 钟 : $(date '+%F %T %Z')   （UTC，换北京时间 +8）"
echo "量之前排掉这四项：/phone /proc /sys /dev"

Q "1 rootfs 总体积与一级目录大头（字节）"
T0=$(date +%s)
TOT=$(du -sbx $DX -P / 2>/dev/null | cut -f1); RC1=$?
echo "总计 : ${TOT:-空读数} B   rc=$RC1   du 耗时 $(( $(date +%s) - T0 )) 秒"
L1=$(du -bx $DX --max-depth=1 -P / 2>/dev/null | sort -rn | head -16); RC2=$?
echo "一级目录 rc=$RC2（字节 B / 路径，从大到小）："
printf '%s\n' "$L1" | sed 's/^/  /'

Q "2 树内最大文件前 15（tar 真正要吃的单文件）"
F=$(find / $FP -type f -printf '%s %p\n' 2>/dev/null | sort -rn | head -15)
printf '%s\n' "$F" | sed 's/^/  /'

Q "3 结构计数（只算 rootfs 本体）"
N_ALL=$(find / $FP -print 2>/dev/null | wc -l)
N_DIR=$(find / $FP -type d 2>/dev/null | wc -l)
N_LINK=$(find / $FP -type l 2>/dev/null | wc -l)
N_DEV=$(find / $FP \( -type b -o -type c \) 2>/dev/null | wc -l)
N_SUID=$(find / $FP -type f -perm /6000 2>/dev/null | wc -l)
echo "条目总数     : $N_ALL（其中目录 $N_DIR）"
echo "符号链接     : $N_LINK   ← git 能存"
echo "设备节点 b/c : $N_DEV    ← git 存不了；若为 0 说明 /dev 是运行时 tmpfs，本来不在树里"
echo "setuid/setgid: $N_SUID   ← git 只保可执行位，这两位会丢"
SUL=$(find / $FP -type f -perm /6000 -printf '  %m %u %p\n' 2>/dev/null | head -10)
printf '%s\n' "$SUL"
echo "属主分布前 8（git 没有存 uid/gid 的字段）："
OWN=$(find / $FP -printf '%u:%g\n' 2>/dev/null | sort | uniq -c | sort -rn | head -8)
printf '%s\n' "$OWN" | sed 's/^/  /'

Q "4 /usr 一发实测压缩（估算整包能不能塞进一发 Release 附件）"
USR=$(du -sbx $DX -P /usr 2>/dev/null | cut -f1)
T1=$(date +%s)
GZSZ=$(tar -cf - /usr 2>/dev/null | gzip -6 2>/dev/null | wc -c); RC3=$?
T2=$(( $(date +%s) - T1 ))
RATIO=$(awk -v a="${USR:-0}" -v b="${GZSZ:-1}" 'BEGIN{if(b>0)printf "%.2f", a/b; else print "读不到"}')
echo "/usr 原始(du 口径) : ${USR:-空读数} B"
echo "tar+gzip -6        : ${GZSZ:-空读数} B   rc=$RC3   耗时 $T2 秒（tar 会把每个文件补到 512 的整倍数，所以这数含补位）"
echo "原始/压缩比        : $RATIO"

Q "5 引擎现场与手机侧那个 dsh 写的东西"
CF=/root/.dsh/profiles/web/cordis.patch.yml
CFSZ=$(wc -c <"$CF" 2>/dev/null)
CFN=$(grep -c '^- id:' "$CF" 2>/dev/null)
echo "cordis 字节 : ${CFSZ:-读不到}   层栈条目数 : ${CFN:-读不到}（508＝我撤干净 / 1627＝死配置 / 1712＝88 刚读到）"
IDS=$(sed -n 's/^- id: \([A-Za-z0-9_-]*\).*/  \1/p' "$CF" 2>/dev/null)
echo "层栈 id（只有 id，不打印 config）："; printf '%s\n' "$IDS"
II=$(dpkg -l 2>/dev/null | awk '$1=="ii"{n++}END{print n+0}')
echo "dpkg ii 数  : ${II:-读不到}（411 / 415 / 428 是最近三个值）"
EP=$(pgrep -f 'dsh web' | head -1); EN=$(pgrep -f 'dsh-entry.js' | head -1)
echo "引擎 pid ${EP:-无}   入口 pid ${EN:-无}"
BT=$(awk '/^btime/{print $2}' /proc/stat)
if [ -n "${EP:-}" ]; then
  REST=$(sed 's/^.*) //' "/proc/$EP/stat" 2>/dev/null)
  ST=$(printf '%s' "$REST" | cut -d' ' -f20)
  BORN=$(( BT + ST / 100 ))
  # 年龄 = 当场 date +%s − 出生（BORN 是**纪元秒**，UP 是**开机后秒数**，两者不同基；
  # 上一版写 $UP-$BORN 打出 -1792327680 秒那种负数 —— 同一个"取数不同基"坑的第四种形状，铁律 2）
  AGE=$(( $(date +%s) - BORN ))
  echo "引擎出生 UTC : $(date -u -d "@$BORN" '+%F %T')   年龄 : $AGE 秒（now 与 born 都在打印那一刻取）"
fi

Q "6 /root/.dsh 逐层与会话字节（要剥的东西得知道多大）"
DD=$(du -bx --max-depth=1 /root/.dsh 2>/dev/null | sort -rn | head -14); RC4=$?
echo "rc=$RC4"; printf '%s\n' "$DD" | sed 's/^/  /'
SSN=$(find /root/.dsh -name 'session.v4.jsonl.zstd' 2>/dev/null | wc -l)
SSB=$(find /root/.dsh -name 'session.v4.jsonl.zstd' -printf '%s\n' 2>/dev/null | awk '{n+=$1}END{print n+0}')
echo "会话记录     : $SSN 份，合计 $SSB B"
KSZ=$(wc -c </root/.dsh/entry.key 2>/dev/null)
echo "entry.key    : ${KSZ:-不在} B（值不打印、不进包）"
PR=$(ls -1 /root/.dsh/profiles 2>/dev/null)
echo "profiles 目录："; printf '%s\n' "$PR" | sed 's/^/  /'

Q "7 可剥缓存复核"
for D in /root/.npm /root/.cache /var/cache/apt/archives /var/lib/apt/lists /tmp /var/log /root/.dsh /var/lib/dpkg/info; do
  SZ=$(du -sbx $DX -P "$D" 2>/dev/null | cut -f1)
  echo "  $D : ${SZ:-空读数} B"
done

Q "8 解析补丁那份 hosts（装机要带着走的）"
HN=$(awk '!/^[[:space:]]*#/ && NF>=2' /etc/hosts 2>/dev/null | wc -l)
echo "hosts 带域名行数 : $HN"
HD=$(awk '!/^[[:space:]]*#/ && NF>=2 {print "  " $2}' /etc/hosts 2>/dev/null | head -30)
echo "钉的域名（只列域名）："; printf '%s\n' "$HD"
