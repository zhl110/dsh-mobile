#!/bin/bash
# tools/run-probe.sh —— 把一条只读探针送进手机 chroot 跑一遍，结果落成项目里的文本件。
#
# 为什么要有这个文件：这轮我在同一个坑里摔了三次 ——
#   1) adb 的参数被 git-bash 的 MSYS 路径转换改写过（/data/local/tmp → D:/program files/Git/data/...），
#      不报"路径不存在"，只报 secure_mkdirs() failed，看着像手机的问题；
#   2) adb 的输出全是 CRLF，直接看会把中文截成乱码；
#   3) 探针文件推去 chroot /root 就忘在那儿了（一轮数出 9 份，删的时候还得逐个确认是我建的）。
# 这个包装把三件事一次性按死：MSYS2_ARG_CONV_EXCL 强制设、输出统一 tr -d '\r'、
# 默认跑完就地删掉设备侧那两份副本（/data/local/tmp 与 chroot /root），并在结束时数一遍残留。
#
# 用法：
#   bash tools/run-probe.sh scripts/dsh-voice-picker-probe21.sh downloads/p21.txt
#   bash tools/run-probe.sh --keep <探针> <输出>        # 留着副本以便连着跑几条
set -u
ADB=${ADB:-}
KEEP=0
if [ "${1:-}" = "--keep" ]; then KEEP=1; shift; fi
PROBE=${1:-}; OUT=${2:-}; shift $(( $# >= 2 ? 2 : $# ))
EXTRA="$*"   # 设备侧那条命令后面还要跟什么参数（比如 doh-hosts.sh --sync）；空就是纯 bash 跑一遍
[ -n "$PROBE" ] && [ -n "$OUT" ] || { echo "用法：bash tools/run-probe.sh [--keep] <本地探针> <本地输出> [传给探针的参数…]"; exit 2; }
[ -f "$PROBE" ] || { echo "!! 探针不存在：$PROBE"; exit 2; }
[ -d "$(dirname "$OUT")" ] || { echo "!! 输出目录不存在：$(dirname "$OUT")"; exit 2; }

if [ -z "$ADB" ]; then
  for c in /d/mycode/.agent-tools/platform-tools/adb.exe "$HOME/.agent-tools/platform-tools/adb.exe"; do
    [ -f "$c" ] && { ADB=$c; break; }
  done
fi
[ -n "$ADB" ] && [ -x "$ADB" ] || { echo "!! 找不到 adb（可用 ADB=/路径/adb.exe 指定）"; exit 2; }
command -v tr >/dev/null && command -v md5sum >/dev/null || { echo "!! 要 git-bash 的 tr/md5sum"; exit 2; }

ROOTFS=/data/local/dsh-rootfs
RUNNER=/data/local/sh/dsh-chroot.sh
NAME=$(basename "$PROBE"); STAGE=/data/local/tmp/$NAME
DEVROOT=$ROOTFS/root        # 宿主视角看进去就是 chroot 的 /root
INCHROOT=/root/$NAME                # 探针自己在 chroot 里被 bash 时用的路径
export MSYS2_ARG_CONV_EXCL='*'      # 坑 1：不让 git-bash 改写 /data/... 这类参数

CR=$(tr -cd '\r' < "$PROBE" | wc -c)
[ "$CR" = "0" ] || { echo "!! $NAME 有 $CR 个 CR：设备上的 bash 会把 \\r 当命令的一部分，先 sed -i 's/\\r\$//'"; exit 2; }
bash -n "$PROBE" || { echo "!! $NAME 语法不过"; exit 2; }

# shell 里跑 su -c 时，命令串里的引号要嵌三层，这里统一走 S()：外层双引号给 adb、内层单引号给 su
S() { "$ADB" shell "su -c \"$1\"" </dev/null 2>&1 | tr -d '\r'; }   # 坑 2 + adb 在循环里吃 stdin（</dev/null）

echo "== 送探针（$(wc -c < "$PROBE") B）"
"$ADB" push "$PROBE" "$STAGE" </dev/null 2>&1 | tr -d '\r'
S "cp $STAGE $DEVROOT/$NAME; chmod 755 $DEVROOT/$NAME; chown root:root $DEVROOT/$NAME; rm -f $STAGE"
S "ls -l $DEVROOT/$NAME"
LOC=$(md5sum "$PROBE" | cut -d' ' -f1)
DEV=$(S "md5sum $DEVROOT/$NAME" | cut -d' ' -f1)
[ "$LOC" = "$DEV" ] && echo "[ok] 设备侧那份与本地逐字节相同（md5 $LOC）" || { echo "!! md5 不撞：本地 $LOC 设备 $DEV"; exit 1; }

echo "== 跑（chroot 内 bash $INCHROOT）"
# 三层引号：给 Windows 的一层双引号、给设备 shell 的一层转义双引号（su -c 的参）、给 runner 的一层单引号（--run 的参）
"$ADB" shell "su -c \"$RUNNER --run 'bash $INCHROOT $EXTRA'\"" </dev/null > "$OUT.raw" 2>&1
RC=$?
tr -d '\r' < "$OUT.raw" > "$OUT"; rm -f "$OUT.raw"
echo "[ok] 读数写进 $OUT（$(wc -c < "$OUT") B，runner 退出码 $RC）"

if [ "$KEEP" = "1" ]; then
  echo "[keep] 副本留在 $INCHROOT（--keep）"
else
  S "rm -f $STAGE $DEVROOT/$NAME" >/dev/null
  echo "[ok] 设备侧两份副本都当场删了"
fi
LEFT=$(S "ls -1 $DEVROOT/*.sh 2>/dev/null | wc -l" | tr -d ' ')
echo "== chroot /root 里残留的 .sh 计数：$LEFT"
if [ "$LEFT" != "0" ]; then S "ls -l $DEVROOT/*.sh"; fi
exit 0
