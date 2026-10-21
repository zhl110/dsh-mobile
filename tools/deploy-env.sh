#!/bin/sh
# tools/deploy-env.sh —— 把仓库里的 config/dsh-env 推到机上 /root/.dsh-env（两段式，带备份与逐字节对账）
#
# 为什么单独一支：入口自己拉引擎那条命令是 `. /root/.dsh-env >/dev/null 2>&1; exec dsh web …`
# （scripts/dsh-entry.js:70），所以这一个文件就是引擎 env 的真源。此前它只被 deploy-entry.sh 的
# 名单**外面**管着——14.25 那轮改档位是手推的，没有可复点的备份步骤，盘上那份与仓库那份对不对得上
# 只能靠记忆。2026-10-21 晚上要给市场加 DSHM_NPM_MIRROR 这一行，先把它变成有备份、有 sha 对账的常规动作。
#
# 两种模式：
#   sh tools/deploy-env.sh --check    只读：比仓库那份与机上那份的 md5 与字节数，不写、不推
#   sh tools/deploy-env.sh            写：先把机上那份逐字节备份到 /root/.dsh/dsh-env.bak.<UTC时间戳>
#                                     并比 sha256 确认备份真撞上了，才推新的；推完再比 md5
#   sh tools/deploy-env.sh --revert /root/.dsh/dsh-env.bak.20261021-191500   原样还原并复点 sha256
#
# 三条纪律：
#   1. 这个文件里可能有 DEEPSEEK_API_KEY（现在是注释掉的）⇒ 本脚本**不回显正文**，只报字节数与摘要。
#   2. adb 只能以 shell 身份 push ⇒ 必须先落 /data/local/tmp 再 su 搬；少那一步就成了"文件在但属主不对"的半死态。
#   3. 备份没撞上原文件就停手不写（这条是 doh-hosts.sh --sync 里验过的形状，照搬）。
set -u
ADB=${ADB:-}
if [ -z "$ADB" ]; then
  for c in /d/mycode/.agent-tools/platform-tools/adb.exe "$HOME/.agent-tools/platform-tools/adb.exe"; do
    [ -f "$c" ] && { ADB=$c; break; }
  done
fi
[ -n "$ADB" ] || { echo "!! 找不到 adb（可用 ADB=/路径/adb.exe 指定）"; exit 2; }

SRC=config/dsh-env
ROOTFS=/data/local/dsh-rootfs
DEV="$ROOTFS/root/.dsh-env"          # 宿主视角的机上那份
BAKDIR="$ROOTFS/root/.dsh"           # 备份也放这里：S() 是 su -c，跑在**宿主**视角，看不见 chroot 的 /root
STAGE=/data/local/tmp
MODE=${1:---write}
S() { "$ADB" shell "su -c \"$1\"" </dev/null 2>&1 | tr -d '\r'; }

# git-bash 会把 /data/... 这类参数改写成 D:\program files\Git\data\...（run-probe.sh 的"坑 1"，同一形状）。
# 第一版没设这个开关，push 直接报 "remote secure_mkdirs() failed"，而错误被我 >/dev/null 2>&1 咽了，
# 只剩一句"!! push 失败"——手顺里静音错误就等于让自己下次再猜一遍。现在：设开关 + push 不静音 + 记退出码。
export MSYS2_ARG_CONV_EXCL='*'

[ -f "$SRC" ] || { echo "!! 仓库里读不到 $SRC（要在项目根目录跑）"; exit 2; }
CR=$(tr -cd '\r' < "$SRC" | wc -c)
if [ "$CR" != "0" ]; then echo "!! $SRC 有 $CR 个 CR：source 时 export 那行会断在 CR 上，先 sed -i 's/\r$//'"; exit 2; fi
LOC_BYTES=$(wc -c < "$SRC" | tr -d ' ')
LOC_MD5=$(md5sum "$SRC" | cut -d' ' -f1)

case "$MODE" in
  --check)
    echo "-- 只读对账（不写）"
    printf '  仓库  %-14s %8s B  md5 %s\n' "$SRC" "$LOC_BYTES" "$LOC_MD5"
    R=$(S "md5sum $DEV 2>/dev/null | cut -d' ' -f1")
    B=$(S "wc -c < $DEV 2>/dev/null | tr -d ' '")
    P=$(S "stat -c '%a %U:%G' $DEV 2>/dev/null")
    if [ -z "$R" ]; then
      echo "  机上  /root/.dsh-env 读不到（不存在？）⇒ 引擎那侧现在用的是空环境"
      exit 1
    fi
    printf '  机上  %-14s %8s B  md5 %s  权限 %s\n' "/root/.dsh-env" "$B" "$R" "$P"
    [ "$R" = "$LOC_MD5" ] && [ "$B" = "$LOC_BYTES" ] && echo "  [ok] 逐字节相同 ⇒ 不用推" || echo "  [不等] 机上那份与仓库不同（要写就跑不带参数的）"
    ;;
  --revert)
    BAK=${2:-}
    [ -n "$BAK" ] || { echo "!! 用法：sh tools/deploy-env.sh --revert /root/.dsh/dsh-env.bak.<时间戳>"; exit 2; }
    # 他（和我）习惯按 chroot 视角写这个路径，而 S() 跑在宿主视角 ⇒ 这里翻一次，别让他去记两套路径
    case "$BAK" in
      /root/*) BAKHOST="$ROOTFS${BAK}" ;;
      *)       BAKHOST="$BAK" ;;
    esac
    echo "   （按宿主视角去找：$BAKHOST）"
    EX=$(S "test -f $BAKHOST && echo 在 || echo 不在")
    [ "$EX" = "在" ] || { echo "!! 备份不在位：$BAKHOST"; exit 1; }
    SB=$(S "sha256sum $BAKHOST | cut -d' ' -f1")
    S "cp -p $BAKHOST $DEV; chmod 600 $DEV; chown root:root $DEV"
    SA=$(S "sha256sum $DEV | cut -d' ' -f1")
    [ "$SB" = "$SA" ] && echo "[ok] 已还原，sha256 与备份相同：$SA"
    [ "$SB" != "$SA" ] && { echo "!! 还原后 sha256 不撞：备份 $SB 现值 $SA"; exit 1; }
    echo "   注意：还原后要重启引擎才吃得进（入口只在自己 spawn 那一次 source）"
    ;;
  --write|"")
    EX=$(S "test -f $DEV && echo 在 || echo 不在")
    if [ "$EX" = "在" ]; then
      TS=$(S "date -u +%Y%m%d-%H%M%S")
      BAK="$BAKDIR/dsh-env.bak.$TS"
      # 第一版这里写的是 BAK="/root/.dsh/..."（chroot 视角），而 S() 是 su -c、跑在宿主视角 ⇒
      # mkdir 建的是 $ROOTFS/root/.dsh、cp 的目标却是宿主的 /root/.dsh（不存在），那句 cp 又被
      # >/dev/null 咽掉了错误，结果是"备份没生成"。真撞上这份文件时是靠 sha256 对账挡住的（它确实停手不写了），
      # 但错误消息被我自己静音了，得再跑一遍才知道原因 ⇒ 现在两条都不静音。
      S "mkdir -p $BAKDIR; cp -p $DEV $BAK"
      SRC_SHA=$(S "sha256sum $DEV | cut -d' ' -f1")
      BAK_SHA=$(S "sha256sum $BAK | cut -d' ' -f1")
      if [ "$SRC_SHA" != "$BAK_SHA" ]; then echo "!! 备份没撞上原文件，停手不写：原 $SRC_SHA 备份 $BAK_SHA"; exit 1; fi
      echo "[ok] 先逐字节备份到 $BAK（chroot 里看是 /root/.dsh/dsh-env.bak.$TS；sha256 与机上那份相同：$SRC_SHA）"
      OLD_B=$(S "wc -c < $DEV | tr -d ' '")
      echo "     机上原来 $OLD_B B ⇒ 换成仓库这发 $LOC_BYTES B"
    else
      echo "[..] 机上本来没有 /root/.dsh-env（那引擎一直是空环境），直接写"
    fi
    name=".dshtmpenv.$$"
    # 退出码要的是 adb 的，不是管道里 tr 的 ⇒ 先落临时文件再读（上一版写成 $(... | tr) 接 $?，数的就是 tr）
    PO=".pushout.$$"
    "$ADB" push "$SRC" "$STAGE/$name" > "$PO" 2>&1; RC=$?
    PP=$(tr -d '\r' < "$PO"); rm -f "$PO"
    echo "  push：$PP"
    [ "$RC" = "0" ] || { echo "!! push 退出码 $RC（上面是原话），停手不搬"; exit 1; }
    S "mv $STAGE/$name $DEV; chmod 600 $DEV; chown root:root $DEV"
    R=$(S "md5sum $DEV 2>/dev/null | cut -d' ' -f1")
    B=$(S "wc -c < $DEV 2>/dev/null | tr -d ' '")
    P=$(S "stat -c '%a %U:%G' $DEV 2>/dev/null")
    LEFT=$(S "ls -1 $STAGE 2>/dev/null | grep -c dshtmpenv")
    printf '  落点 %s  %s B  md5 %s  权限 %s\n' "/root/.dsh-env" "$B" "$R" "$P"
    [ "$R" = "$LOC_MD5" ] || { echo "!! md5 不撞：仓库 $LOC_MD5 机上 $R"; exit 1; }
    [ "$LEFT" = "0" ] || echo "!! /data/local/tmp 里我这次的临时件没清干净（计数 $LEFT）"
    echo "[ok] 逐字节相同（md5 $LOC_MD5），临时件已清"
    echo "   生效条件：引擎重启一次（入口的 engineCmd 在 spawn 时才 source 这个文件）"
    ;;
  *)
    echo "用法：sh tools/deploy-env.sh [--check | --revert /root/.dsh/dsh-env.bak.<时间戳>]"
    ;;
esac
