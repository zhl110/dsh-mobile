#!/bin/sh
# tools/deploy-phone-control.sh —— 把壳 0.12 手机控制环的引擎侧接上（桥 + cordis 接线），带备份与逐字节对账。
#
# 两件产物：
#   1) scripts/dsh-phone-bridge.js  → 机上 chroot /usr/local/bin/dsh-phone-bridge.js（零依赖 MCP stdio 桥）
#   2) config/cordis-phone-mcp.snippet.yml → 追加到 /root/.dsh/profiles/web/cordis.patch.yml 末尾
#      （`- insert:` 插一个 @deepseek-ai/dsh-mcp-client 实例，serverName=phone ⇒ 工具 mcp__phone__*）
#
# 模式（照 deploy-env.sh 的三段式）：
#   sh tools/deploy-phone-control.sh --check    只读：比桥 md5、数 cordis 与组合配置里的接线命中，不写
#   sh tools/deploy-phone-control.sh            写：推桥（md5 复点）→ 备份 cordis（sha256 撞上才动）→ 追加接线
#                                             → `dsh --profile web --dump-config` 数命中（≥1 才算接对，铁律 14）
#   sh tools/deploy-phone-control.sh --revert /root/.dsh/cordis.patch.yml.bak.<UTC时间戳>   逐字节还原 cordis
#
# 纪律：
#   · 本脚本**不重启引擎**（重启要他在场；只 SIGTERM `dsh web`，照 scripts/dsh-engine-restart-and-verify44.sh）。
#     --dump-config 打印完就退、不 mount 不起服务 ⇒ 不用重启就能判接对没接对。
#   · adb 只能 shell 身份 push ⇒ 先落 /data/local/tmp 再 su 搬进 rootfs（deploy-env.sh 同款）。
#   · 备份没撞上原文件就停手不写。
#   · chroot 内那条命令（CH）里不许有单引号与 $()：四层引号会被宿主 shell 先求值（AGENTS.md 已知坑）。
set -u
ADB=${ADB:-}
if [ -z "$ADB" ]; then
  for c in /d/mycode/.agent-tools/platform-tools/adb.exe "$HOME/.agent-tools/platform-tools/adb.exe"; do
    [ -f "$c" ] && { ADB=$c; break; }
  done
fi
[ -n "$ADB" ] && [ -x "$ADB" ] || { echo "!! 找不到 adb（可用 ADB=/路径/adb.exe 指定）"; exit 2; }
export MSYS2_ARG_CONV_EXCL='*'

ROOTFS=/data/local/dsh-rootfs
RUNNER=/data/local/sh/dsh-chroot.sh
BRIDGE_SRC=scripts/dsh-phone-bridge.js
INJ_SRC=scripts/dsh-uinput.py
SNIPPET=config/cordis-phone-mcp.snippet.yml
BRIDGE_DEV="$ROOTFS/usr/local/bin/dsh-phone-bridge.js"   # 宿主视角；chroot 里看是 /usr/local/bin/dsh-phone-bridge.js
INJ_DEV="$ROOTFS/usr/local/bin/dsh-uinput.py"            # 同上；/dev/uinput 注入器（python3）
CORDIS="$ROOTFS/root/.dsh/profiles/web/cordis.patch.yml" # 宿主视角；chroot 里看是 /root/.dsh/profiles/web/cordis.patch.yml
BAKDIR="$ROOTFS/root/.dsh"
STAGE=/data/local/tmp
MODE=${1:---write}
S() { "$ADB" shell "su -c \"$1\"" </dev/null 2>&1 | tr -d '\r'; }
# chroot 内跑一条（命令里不许有单引号/$()）；dump-config 打印完就退，不起服务
CH() { "$ADB" shell "su -c \"$RUNNER --run '$1'\"" </dev/null 2>&1 | tr -d '\r'; }

[ -f "$BRIDGE_SRC" ] || { echo "!! 仓库里读不到 $BRIDGE_SRC（要在项目根目录跑）"; exit 2; }
[ -f "$INJ_SRC" ] || { echo "!! 仓库里读不到 $INJ_SRC"; exit 2; }
[ -f "$SNIPPET" ] || { echo "!! 仓库里读不到 $SNIPPET"; exit 2; }
for f in "$BRIDGE_SRC" "$INJ_SRC" "$SNIPPET"; do
  CR=$(tr -cd '\r' < "$f" | wc -c)
  [ "$CR" = "0" ] || { echo "!! $f 有 $CR 个 CR：设备 bash/ YAML 会断在 CR 上，先 sed -i 's/\r\$//'"; exit 2; }
done
LOC_MD5=$(md5sum "$BRIDGE_SRC" | cut -d' ' -f1)
LOC_BYTES=$(wc -c < "$BRIDGE_SRC" | tr -d ' ')
INJ_MD5=$(md5sum "$INJ_SRC" | cut -d' ' -f1)
INJ_BYTES=$(wc -c < "$INJ_SRC" | tr -d ' ')

# 组合配置里数接线命中（不重启）。输出带标签的几行，肉眼/脚本都能读。
# grep 模式一律无引号无 $()：四层引号里带单引号会被宿主 shell 先求值（AGENTS.md 已知坑）。
dump_hits() {
  CH "dsh --profile web --dump-config > /tmp/phone-dump.yml 2>&1; echo ==dump_bytes; wc -c < /tmp/phone-dump.yml; echo ==phone_mcp_hits; grep -c phone-mcp /tmp/phone-dump.yml; echo ==bridge_hits; grep -c dsh-phone-bridge /tmp/phone-dump.yml"
}

case "$MODE" in
  --check)
    echo "-- 只读对账（不写）"
    printf '  仓库桥  %s B  md5 %s\n' "$LOC_BYTES" "$LOC_MD5"
    printf '  仓库注入器 %s B  md5 %s\n' "$INJ_BYTES" "$INJ_MD5"
    R=$(S "md5sum $BRIDGE_DEV 2>/dev/null | cut -d' ' -f1")
    B=$(S "wc -c < $BRIDGE_DEV 2>/dev/null | tr -d ' '")
    if [ -z "$R" ]; then echo "  机上桥  读不到（还没推）"; else
      printf '  机上桥  %s B  md5 %s\n' "$B" "$R"
      [ "$R" = "$LOC_MD5" ] && echo "  [ok] 桥逐字节相同" || echo "  [不等] 桥上那份与仓库不同"
    fi
    IR=$(S "md5sum $INJ_DEV 2>/dev/null | cut -d' ' -f1")
    IB=$(S "wc -c < $INJ_DEV 2>/dev/null | tr -d ' '")
    if [ -z "$IR" ]; then echo "  机上注入器  读不到（还没推）"; else
      printf '  机上注入器 %s B  md5 %s\n' "$IB" "$IR"
      [ "$IR" = "$INJ_MD5" ] && echo "  [ok] 注入器逐字节相同" || echo "  [不等] 注入器与仓库不同"
    fi
    H=$(S "grep -c phone-mcp $CORDIS 2>/dev/null")
    echo "  cordis.patch.yml 里 phone-mcp 命中：${H:-0}（0=还没接线）"
    echo "-- 组合配置命中（--dump-config，不重启）："
    dump_hits
    ;;
  --revert)
    BAK=${2:-}
    [ -n "$BAK" ] || { echo "!! 用法：sh tools/deploy-phone-control.sh --revert /root/.dsh/cordis.patch.yml.bak.<时间戳>"; exit 2; }
    case "$BAK" in
      /root/*) BAKHOST="$ROOTFS${BAK}" ;;
      *)       BAKHOST="$BAK" ;;
    esac
    echo "   （按宿主视角去找：$BAKHOST）"
    EX=$(S "test -f $BAKHOST && echo 在 || echo 不在")
    [ "$EX" = "在" ] || { echo "!! 备份不在位：$BAKHOST"; exit 1; }
    SB=$(S "sha256sum $BAKHOST | cut -d' ' -f1")
    S "cp -p $BAKHOST $CORDIS; chmod 644 $CORDIS; chown root:root $CORDIS"
    SA=$(S "sha256sum $CORDIS | cut -d' ' -f1")
    [ "$SB" = "$SA" ] && echo "[ok] cordis 已还原，sha256 与备份相同：$SA"
    [ "$SB" != "$SA" ] && { echo "!! 还原后 sha256 不撞：备份 $SB 现值 $SA"; exit 1; }
    echo "   桥文件留着没删（无害；要删手动 rm $BRIDGE_DEV）。还原后要重启引擎才吃得进。"
    ;;
  --write|"")
    # 1) 推桥
    EX=$(S "test -f $BRIDGE_DEV && echo 在 || echo 不在")
    echo "[..] 推桥到 chroot /usr/local/bin/dsh-phone-bridge.js（机上原来：$EX）"
    name=".dshtmpbridge.$$"
    PO=".pushout.$$"
    "$ADB" push "$BRIDGE_SRC" "$STAGE/$name" > "$PO" 2>&1; RC=$?
    PP=$(tr -d '\r' < "$PO"); rm -f "$PO"
    echo "  push：$PP"
    [ "$RC" = "0" ] || { echo "!! push 退出码 $RC，停手不搬"; exit 1; }
    S "cp $STAGE/$name $BRIDGE_DEV; chmod 755 $BRIDGE_DEV; chown root:root $BRIDGE_DEV; rm -f $STAGE/$name"
    R=$(S "md5sum $BRIDGE_DEV 2>/dev/null | cut -d' ' -f1")
    [ "$R" = "$LOC_MD5" ] || { echo "!! 桥 md5 不撞：仓库 $LOC_MD5 机上 $R"; exit 1; }
    echo "[ok] 桥逐字节相同（md5 $LOC_MD5，755 root:root）"

    # 1b) 推注入器（python3，/dev/uinput）
    name2=".dshtmpuinput.$$"
    PO0=".pushout0.$$"
    "$ADB" push "$INJ_SRC" "$STAGE/$name2" > "$PO0" 2>&1; RC0=$?
    PP0=$(tr -d '\r' < "$PO0"); rm -f "$PO0"
    echo "  push 注入器：$PP0"
    [ "$RC0" = "0" ] || { echo "!! 注入器 push 退出码 $RC0，停手不搬"; exit 1; }
    S "cp $STAGE/$name2 $INJ_DEV; chmod 755 $INJ_DEV; chown root:root $INJ_DEV; rm -f $STAGE/$name2"
    IR=$(S "md5sum $INJ_DEV 2>/dev/null | cut -d' ' -f1")
    [ "$IR" = "$INJ_MD5" ] || { echo "!! 注入器 md5 不撞：仓库 $INJ_MD5 机上 $IR"; exit 1; }
    PY=$(CH "python3 -V")
    echo "[ok] 注入器逐字节相同（$INJ_BYTES B，md5 $INJ_MD5，755 root:root）；chroot python：$PY"

    # 2) 备份 cordis（撞上才动）
    CEX=$(S "test -f $CORDIS && echo 在 || echo 不在")
    [ "$CEX" = "在" ] || { echo "!!机上没有 $CORDIS（web profile 不在？）停手"; exit 1; }
    TS=$(S "date -u +%Y%m%d-%H%M%S")
    BAK="$BAKDIR/cordis.patch.yml.bak.$TS"
    S "mkdir -p $BAKDIR; cp -p $CORDIS $BAK"
    OS=$(S "sha256sum $CORDIS | cut -d' ' -f1")
    BS=$(S "sha256sum $BAK | cut -d' ' -f1")
    [ "$OS" = "$BS" ] || { echo "!! 备份没撞上原文件，停手不写：原 $OS 备份 $BS"; exit 1; }
    OB=$(S "wc -c < $CORDIS | tr -d ' '")
    echo "[ok] cordis 先逐字节备份到 $BAK（chroot 里 /root/.dsh/cordis.patch.yml.bak.$TS；原来 $OB B，sha256 $OS）"

    # 3) 追加接线（幂等：已接就跳过）
    AL=$(S "grep -c phone-mcp $CORDIS 2>/dev/null")
    if [ "${AL:-0}" != "0" ]; then
      echo "[skip] cordis 里已有 phone-mcp（命中 $AL）⇒ 不重复追加"
    else
      sn=".dshtmpsnippet.$$"
      PO2=".pushout2.$$"
      "$ADB" push "$SNIPPET" "$STAGE/$sn" > "$PO2" 2>&1; RC2=$?
      PP2=$(tr -d '\r' < "$PO2"); rm -f "$PO2"
      echo "  push snippet：$PP2"
      [ "$RC2" = "0" ] || { echo "!! snippet push 退出码 $RC2；cordis 已备份未改，可 --revert $BAK"; exit 1; }
      S "cat $STAGE/$sn >> $CORDIS; rm -f $STAGE/$sn"
      NB=$(S "wc -c < $CORDIS | tr -d ' '")
      NH=$(S "grep -c phone-mcp $CORDIS 2>/dev/null")
      echo "[ok] 追加后 cordis $NB B（原 $OB B），phone-mcp 命中 $NH"
      [ "${NH:-0}" != "0" ] || { echo "!! 追加后仍 0 命中，--revert $BAK 还原"; exit 1; }
    fi

    # 4) 组合配置判接对（铁律 14：命中 0 就别重启）
    echo "-- 组合配置命中（--dump-config，不重启）："
    DUMP=$(dump_hits)
    echo "$DUMP"
    PH=$(echo "$DUMP" | awk '/==phone_mcp_hits/{getline; print}')
    BH=$(echo "$DUMP" | awk '/==bridge_hits/{getline; print}')
    echo "  解读：phone-mcp 命中=${PH:-?}  bridge 命中=${BH:-?}（都要 ≥1）"
    case "${PH:-0}" in 0|'') echo "!! 组合配置里 phone-mcp 命中 0 ⇒ 接线被静默丢掉，别重启；--revert $BAK 还原后查形状"; exit 1;; esac
    echo "[ok] 接线进组合配置了。下一步（要他在场）：只 SIGTERM 引擎换代，照 scripts/dsh-engine-restart-and-verify44.sh；"
    echo "     换代后在 DSH 聊天里应能看到 mcp__phone__screen 等 6 个工具。撤法：--revert $BAK"
    ;;
  *)
    echo "用法：sh tools/deploy-phone-control.sh [--check | --revert /root/.dsh/cordis.patch.yml.bak.<时间戳>]"
    ;;
esac