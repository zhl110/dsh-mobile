#!/bin/bash
# dsh-payload-survey-probe88.sh —— 只读：为"把 rootfs / Node / dsh 本体做成别人能装的产物"量三件事
#   ① 这棵树到底多大、大头在哪、最大单文件多大（决定产物放哪儿）
#   ② 打成 tar 之前，git 树为什么装不下：设备节点 / 属主 / setuid 三个计数（决定性证据，不靠配额）
#   ③ 打包时必须剥掉哪些含凭证与用户数据的路径（只报路径、字节、条数，绝不打印内容与键值）
# 这一发不写任何文件、不装包、不动 hosts、不重启进程。跑法：
#   bash tools/run-probe.sh scripts/dsh-payload-survey-probe88.sh downloads/p88.txt
# 注意：chroot 里 / 就是那棵 rootfs；/proc /sys /dev /phone 是别的文件系统，所以统一用 -x 跳过。
set -u
Q() { printf '\n== %s\n' "$1"; }

Q "0 设备与时间（chroot 内 UTC，换北京时间 +8）"
echo "uname      : $(uname -m -o 2>/dev/null)"
echo "chroot 钟  : $(date '+%F %T %Z')"
echo "挂载（本探针按 -x 跳过下面这些非 rootfs 的项）："
sed -n 's/^\S* \(\S*\) \(\S*\) .*/  \1  \2/p' /proc/mounts | sort -u | head -14

Q "1 接班三数（铁律 18：现场可能被手机侧那个 dsh 自己动过）"
CF=/root/.dsh/profiles/web/cordis.patch.yml
CFSZ=$(wc -c <"$CF" 2>/dev/null)
echo "cordis 字节 : ${CFSZ:-读不到}   （508＝我撤干净 / 1627＝它接回的死配置）"
II=$(dpkg -l 2>/dev/null | awk '$1=="ii"{n++}END{print n+0}')
echo "dpkg ii 数  : ${II:-读不到}   （411 / 415 是最近两个已知值）"
EP=$(pgrep -f 'dsh web' | head -1)
EN=$(pgrep -f 'dsh-entry.js' | head -1)
echo "引擎 pid    : ${EP:-无}      入口 pid : ${EN:-无}"
if [ -n "${EP:-}" ]; then
  BT=$(awk '/^btime/{print $2}' /proc/stat)
  UP=$(cut -d' ' -f1 /proc/uptime)
  # /proc/<pid>/stat 的 comm 可能带空格，所以先 greedy 抹到最后一个 ')' 再数：抹掉 pid+comm 后 field 22 → 第 20 个
  REST=$(sed 's/^.*) //' "/proc/$EP/stat" 2>/dev/null)
  ST20=$(printf '%s' "$REST" | cut -d' ' -f20)
  BORN=$(( BT + ST20 / 100 ))
  echo "引擎出生    : epoch=$BORN  UTC=$(date -u -d "@$BORN" '+%F %T' 2>/dev/null)"
  echo "引擎年龄    : $(( UP - BORN )) 秒（当场读的 /proc/uptime，不是快照）"
fi

Q "2 rootfs 有多大、大头在哪（字节；-x 只算这棵树）"
TOT=$(du -sbx / 2>/dev/null | cut -f1)
echo "总计        : ${TOT:-读不到} B"
echo "一级目录（前 14）："
du -sbx --max-depth=1 / 2>/dev/null | sort -rn | head -14 | sed 's/^/  /'
NODESZ=$(stat -c '%s' /usr/local/bin/node 2>/dev/null)
echo "node 本体   : ${NODESZ:-不在 /usr/local/bin/node} B"
DSHSZ=$(du -sbx /usr/local/lib/node_modules/@deepseek-ai 2>/dev/null | cut -f1)
echo "@deepseek-ai: ${DSHSZ:-读不到} B（dsh 本体 + 它自己 node_modules 那一棵）"
VER=$(dsh --version 2>&1 | head -1)
echo "dsh --version : $VER"
ENTRYJS=/usr/local/bin/dsh-entry.js
echo "入口脚本    : $(stat -c '%s' "$ENTRYJS" 2>/dev/null) B  md5 $(md5sum "$ENTRYJS" 2>/dev/null | cut -c1-32)"

Q "3 最大单文件前 12（决定 tar 要不要拆卷）"
find / -xdev -type f -printf '%s %p\n' 2>/dev/null | sort -rn | head -12 | sed 's/^/  /'

Q "4 git 树装不下这棵树的三个计数（不是配额，是格式存不了）"
N_ALL=$(find / -xdev 2>/dev/null | wc -l)
N_BLK=$(find / -xdev \( -type b -o -type c \) 2>/dev/null | wc -l)
N_SOCK=$(find / -xdev \( -type s -o -type p \) 2>/dev/null | wc -l)
N_LINK=$(find / -xdev -type l 2>/dev/null | wc -l)
N_SUID=$(find / -xdev -type f -perm /6000 2>/dev/null | wc -l)
echo "条目总数（含目录与链接）: $N_ALL"
echo "设备节点 b/c            : $N_BLK   ← git 完全不存这种对象"
echo "socket + fifo           : $N_SOCK  ← 同样存不了"
echo "符号链接                : $N_LINK"
echo "setuid/setgid 普通文件  : $N_SUID  ← git 只保可执行位，这两位会丢"
echo "属主分布前 6（git 不存属主，全变 checkout 的人）："
find / -xdev -printf '%u:%g\n' 2>/dev/null | sort | uniq -c | sort -rn | head -6 | sed 's/^/  /'

Q "5 打包必须剥的路径（只报字节与条数；键名可以列，键值一律不打印）"
K=/root/.dsh/entry.key
KSZ=$(wc -c <"$K" 2>/dev/null)
echo "entry.key   : ${KSZ:-不在} B（值不打印、不进包）"
echo "/root/.dsh 下一层（前 12，按字节）："
du -sbx --max-depth=1 /root/.dsh 2>/dev/null | sort -rn | head -12 | sed 's/^/  /'
SSN=$(find /root/.dsh -name 'session.v4.jsonl.zstd' 2>/dev/null | wc -l)
echo "会话记录件数: $SSN   ← 他的对话原文，一律不进包"
echo "/root/.dsh-env 里的键名（只取等号左边的名字，绝不取右边的值）："
sed -n 's/^export \([A-Za-z0-9_]*\)=.*/  \1/p' /root/.dsh-env 2>/dev/null
echo "可剥的缓存（能省体积，剥了不影响起服务）："
for D in /root/.npm /root/.cache /var/cache/apt/archives /var/lib/apt/lists /tmp /var/log; do
  echo "  $D : $(du -sbx "$D" 2>/dev/null | cut -f1) B / $(find "$D" -xdev 2>/dev/null | wc -l) 项"
done
echo "hosts 里带域名的行数 : $(awk '!/^[[:space:]]*#/ && NF>=2' /etc/hosts 2>/dev/null | wc -l)   ← 这台机的解析补丁，别人也要（保留，但要单独说明）"
HB=$(ls -1 /etc/hosts.bak* 2>/dev/null | wc -l)
echo "/etc/hosts.bak* 份数 : $HB"
MID=$(wc -c </etc/machine-id 2>/dev/null)
echo "/etc/machine-id      : ${MID:-读不到} B   ← 机器特定，进包前应清空让 systemd 重生成"

Q "6 /root 里的 .sh 计数（含本探针自己，别读成残留）"
SH=$(ls -1 /root/*.sh 2>/dev/null | wc -l)
echo "/root/*.sh : $SH 条（这发探针就在里面；run-probe.sh 跑完会删掉它和 /data/local/tmp 的副本）"

Q "7 /data 还剩多少（产物要在机上落地才有体积；口径写死）"
echo "df -k / 整行（chroot 里这个 / 就是 /data 那棵树，所以是整分区统计）："
df -k / 2>/dev/null | sed 's/^/  /'
