#!/usr/bin/env bash
# install-apk.sh — **只装机、不重打** app/out/dsh-app.apk
#
# 为什么要有这一支（2026-10-21 插手机当晚想清的）：
#   `bash app/build.sh --install` 那一条**一定会先重打**（build.sh 第 1~6 步无条件跑，装机只是第 7 步），
#   而"APK 打包不是逐字节可复现"是记在 AGENTS 已知坑里的事实（同源码重打 sha 也会变）。
#   ⇒ 只要跑过它，之前报给用户的那串 sha 就作废了。PROGRESS 里"别为了装它重打"这句话，
#     用 build.sh --install 是**做不到**的 —— 这条脚本就是把它变成可执行的形状。
#
# 用法：
#   bash tools/install-apk.sh              # 推 + 逐字节撞 sha + pm install -r + 清两处副本 + 复读机上指纹
#   bash tools/install-apk.sh --verify     # 只比指纹（本地 out/dsh-app.apk vs 机上 base.apk），一个字节都不写
#
# 铁律对得上的地方：三个数要相等（本地 1 发 / 推上去 1 发 / sha256 撞上 1 发）；
# 判"装好了"只认落下来的字节与 base.apk 的 sha，不认 pm 回的那句 Success；
# 口令与 token 一律不进这条链路（包里烤的是入口地址与口令，值不在本脚本里出现）。
set -u

APK=app/out/dsh-app.apk
PKG=com.zhl.dsh
ADB="${DSH_ADB:-/d/mycode/.agent-tools/platform-tools/adb.exe}"
[ -x "$ADB" ] || ADB="C:/Users/周海龙/DeskBox/我的桌面/platform-tools/adb.exe"
[ -f "$APK" ] || { echo "!! 没有成品：$APK（要重打就自己跑 bash app/build.sh，但那会让已报的 sha 作废）"; exit 1; }
command -v sha256sum >/dev/null || { echo "!! 要 git-bash 的 sha256sum"; exit 1; }
export MSYS2_ARG_CONV_EXCL='*'

S() { "$ADB" shell "su -c '$1'" 2>&1 | tr -d '\r'; }

LOC_SHA=$(sha256sum "$APK" | cut -d' ' -f1)
LOC_SZ=$(wc -c <"$APK" | tr -d ' ')
BASE=$(S "find /data/app -name base.apk -path '*$PKG*' | head -1")

echo "== 0. 指纹 =="
echo "  本地 $APK  $LOC_SZ B  sha256 $LOC_SHA"
if [ -n "$BASE" ]; then
  D=$(S "sha256sum $BASE"); INST_SHA=${D%% *}
  D2=$(S "wc -c < $BASE"); INST_SZ=$(printf '%s' "$D2" | tr -dc '0-9')
  echo "  机上 $BASE  $INST_SZ B  sha256 $INST_SHA"
  VER=$(S "dumpsys package $PKG | grep -m1 versionName" | tr -dc '0-9.')
  LU=$(S "dumpsys package $PKG | grep -m1 lastUpdateTime")
  echo "  现装 $VER ｜ $LU"
  [ "$LOC_SHA" = "$INST_SHA" ] && echo "  [already] 字节已经是这一发 ⇒ 不用装"
else
  echo "  机上：没找到 $PKG 的 base.apk（第一次装？）"
fi

if [ "${1:-}" = "--verify" ]; then
  [ -n "${INST_SHA:-}" ] && [ "$LOC_SHA" = "$INST_SHA" ] && { echo "[ok] 一致"; exit 0; } || { echo "!! 不一致（或没装过）"; exit 1; }
fi

echo "== 1. 推 =="
"$ADB" push "$APK" /data/local/tmp/dsh-app.apk >/dev/null || { echo "!! push 失败"; exit 1; }
PUSHED=1
DEV_SHA=$(S "sha256sum /data/local/tmp/dsh-app.apk" | cut -d' ' -f1)
DEV_SZ=$(S "wc -c < /data/local/tmp/dsh-app.apk" | tr -dc '0-9')
echo "  机上 /data/local/tmp/dsh-app.apk  $DEV_SZ B  sha $DEV_SHA"
if [ "$LOC_SHA" != "$DEV_SHA" ] || [ "$LOC_SZ" != "$DEV_SZ" ]; then
  echo "!! 不撞：本地 $LOC_SZ/$LOC_SHA 设备 $DEV_SZ/$DEV_SHA ⇒ 停，不装"
  S "rm -f /data/local/tmp/dsh-app.apk" >/dev/null
  exit 1
fi
echo "  [ok] 逐字节相同（清单 1 / 推上去 $PUSHED / 撞上 1）"

echo "== 2. 装（走那条实测唯一通的路：cp 进 /data 根 + restorecon + pm install -r）=="
echo "     不通的两条留档：adb install -r → Failure [-99]（这台机的 USB 安装闸口）；"
echo "     pm install /data/local/tmp/… → System server 读不到 shell_test_data_file 标签（Android 11+ 的规矩，与有没有 root 无关）"
S "cp /data/local/tmp/dsh-app.apk /data/dsh-app.apk; restorecon /data/dsh-app.apk >/dev/null 2>&1; echo label=\$(ls -Z /data/dsh-app.apk | cut -d' ' -f1); pm install -r /data/dsh-app.apk 2>&1 | head -2; echo pm_rc=\$?; rm -f /data/dsh-app.apk /data/local/tmp/dsh-app.apk"

echo "== 3. 复读（认字节，不认 Success）=="
BASE2=$(S "find /data/app -name base.apk -path '*$PKG*' | head -1")
D3=$(S "sha256sum $BASE2"); NEW_SHA=${D3%% *}
NEW_SZ=$(S "wc -c < $BASE2" | tr -dc '0-9')
echo "  机上 $BASE2  $NEW_SZ B  sha256 $NEW_SHA"
echo "  $(S "dumpsys package $PKG | grep -m1 versionName")  /  $(S "dumpsys package $PKG | grep -m1 lastUpdateTime")"
echo "  副本残留：$(S "ls /data/dsh-app.apk /data/local/tmp/dsh-app.apk 2>&1 | head -2" | tr '\n' ' ')"
if [ "$LOC_SHA" = "$NEW_SHA" ]; then
  echo "[ok] 装进手机的就是这一发（$NEW_SZ B）"
else
  echo "!! 装完再读不撞：本地 $LOC_SHA 机上 $NEW_SHA"
  exit 1
fi
