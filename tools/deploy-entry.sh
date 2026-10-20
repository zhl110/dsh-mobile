#!/bin/sh
# tools/deploy-entry.sh —— 把入口守护与两份壳脚本推到真机上，并把口令拉回 Windows 侧烤进 APK
#
# 为什么单独一个脚本：这几件东西落点是三种（chroot 的 /usr/local/bin、chroot 的 /root/.dsh、宿主的
# /data/local/sh），权限也不同（0755 / 目录 0700 + 文件 0644 / 0755），而 adb 只能以 shell 身份 push，
# 必须两段式：push 到 /data/local/tmp 再 su 搬过去。少一步就会出现"文件在但权限不对"那种半死状态。
#
# 行尾：这四份文件实测**零 CR 字节**（tr -dc '\r' | wc -c = 0，2026-10-20 读数），本来就不用剥。
# 但我第一版在这里写过一段"仓库里是 CRLF，推上去会把 \r 带进 PORT=3080 的值里"的判断 —— 那是**假读数**：
# 我当时用 `grep -c $'\r'` 数，而这个脚本是 /bin/sh(dash)，不认 $'\a' 那套 ANSI-C 引用，模式退化成空串，
# 空串匹配每一行，于是"346 行有 CR"其实是"这文件有 346 行"。tr 数出来是 0。
# 剥 CR 那一步留着当护栏（无 CR 时是恒等操作，一个字节都不动），但它不是这次的成因，别照着这句话去改仓库。
#
# 只写我们自己建的东西：/data/local/tmp 下用 .dshdeploy.<pid> 这种唯一名字，搬完立刻没了；
# 他放在 /data/local/tmp 的那一堆（boot 镜像、kpatch、magiskboot…）一个字节都不碰。
#
# 「搬完立刻没了」第一版是没做到的：剥 CR 那条分支 mv 走的是 $name.lf，**原件 $name 没人删**，
# 于是每跑一次留一份（2026-10-20 实测盘上堆了 4 份 .dshdeploy.*，19:22 那批）。现在两条分支都补了
# `rm -f $STAGE/$name`，机上那 4 份连同旧的 /data/local/tmp/probe-page.sh（我写的探针，已被
# scripts/dsh-entry-check.sh 取代）一起删掉并复点。
#
# 用法（在 D:\mycode\dsh-mobile 下跑）：
#   sh tools/deploy-entry.sh              推四件 + 校字节 + 把 /data/local/dsh.log 收到 0600 + chroot 里自测
#   sh tools/deploy-entry.sh --entry      推完顺手起入口（= sh dsh-chroot.sh --entry）
#   sh tools/deploy-entry.sh --status     只读：跑一遍 dsh-chroot.sh --status 的读数
#   sh tools/deploy-entry.sh --check      只读：现场体检（门禁 / 真首页字节顺序 / 入口自述 / 上游文件有没有被动过）
#   sh tools/deploy-entry.sh --pull-key   把机上的入口口令拉到 app/local/entry.key（之后要重建 APK）
set -u

ADB="${DSH_ADB:-C:/Users/周海龙/DeskBox/我的桌面/platform-tools/adb.exe}"
[ -x "$ADB" ] || ADB="/d/mycode/.agent-tools/platform-tools/adb.exe"
[ -x "$ADB" ] || { echo "!! 找不到 adb（两条路径都试过）"; exit 1; }

# Git-Bash 会把 /data/local/tmp/x 这种参数改写成 D:/program files/Git/data/local/tmp/x 再交给 adb
# （2026-10-20 实测："remote secure_mkdirs() failed: No such file or directory"）。
# MSYS2_ARG_CONV_EXCL='*' 关掉这个自动转换；目标端写 //data/... 双斜杠也行，但那是撞运气，这条是明写的。
export MSYS2_ARG_CONV_EXCL='*'

ROOT=/data/local/dsh-rootfs
STAGE=/data/local/tmp
S() { "$ADB" shell "su -c '$*'" ; }

echo "== adb 读数：$("$ADB" devices | sed -n '2p')"
"$ADB" get-state >/dev/null 2>&1 || { echo "!! 设备不在 device 状态"; exit 1; }

# push2 <本地文件> <目标绝对路径> <模式> <剥CR? yes/no>
push2() {
  src="$1"; dst="$2"; mode="$3"; crlf="$4"
  name=".dshdeploy.$$"
  "$ADB" push "$src" "$STAGE/$name" >/dev/null 2>&1 || { echo "!! push $src 失败"; return 1; }
  if [ "$crlf" = yes ]; then
    S "tr -d \\\\r < $STAGE/$name > $STAGE/$name.lf; mv $STAGE/$name.lf $dst; chmod $mode $dst; rm -f $STAGE/$name"
  else
    S "mv $STAGE/$name $dst; chmod $mode $dst; rm -f $STAGE/$name"
  fi
  # CR 个数用 tr 数，不用 grep -c：grep 没匹配时退出码是 1，"|| echo 0" 会让它自己再印一遍，
  # 于是 C 变成 "0\n0"，后面 $((L - C)) 直接算术报错（2026-10-20 实测就是这个崩的）。
  L=$(wc -c < "$src"); C=$(tr -dc '\r' < "$src" | wc -c)
  [ "$crlf" = yes ] && L=$((L - C))
  R=$(S "wc -c < $dst" 2>/dev/null | tr -d ' \r\n')
  if [ "$L" = "$R" ]; then
    echo "[ok] $(basename "$dst") 机上 $R B（本地 $L B，CR 字节 $C，剥CR=$crlf）mode=$mode"
  else
    echo "!! 字节不等：期望 $L 机上 $R（$dst）"; return 1
  fi
}

for want in scripts/dsh-entry.js tools/dsh-compat.js scripts/dsh-chroot.sh scripts/dsh-console.sh scripts/dsh-entry-check.sh; do
  [ -f "$want" ] || { echo "!! 本地缺 $want"; exit 1; }
done

S "mkdir -p $ROOT/usr/local/bin $ROOT/root/.dsh /data/local/sh"
echo "-- 推四件（入口脚本 / 兼容脚本 / 控制脚本 / 菜单）"
push2 scripts/dsh-entry.js   "$ROOT/usr/local/bin/dsh-entry.js" 755 no  || exit 1
push2 tools/dsh-compat.js    "$ROOT/root/.dsh/entry-compat.js"  644 no  || exit 1
push2 scripts/dsh-chroot.sh  /data/local/sh/dsh-chroot.sh       755 yes || exit 1
push2 scripts/dsh-console.sh /data/local/sh/dsh-console.sh      755 yes || exit 1
push2 scripts/dsh-entry-check.sh "$ROOT/root/dsh-entry-check.sh" 644 no || exit 1
S "chmod 700 $ROOT/root/.dsh; chown -R root:root $ROOT/root/.dsh $ROOT/usr/local/bin/dsh-entry.js"
# 宿主侧那两份 .sh 里如果还留着 CR，把旧的也一并纠正（只改我们自己这两个名字）
S "ls -l /data/local/sh/dsh-chroot.sh /data/local/sh/dsh-console.sh"

# 引擎日志收权限：实测 /data/local/dsh.log 是 0644 root:root 且里面有 token 行（RUNBOOK 14.13）
# 拦在门外的是 SELinux Enforcing（run-as com.termux 读它被拒），但权限位没理由留成 0644。
echo "-- 日志权限"
S "if [ -f /data/local/dsh.log ]; then chmod 600 /data/local/dsh.log; fi; ls -l /data/local/dsh.log 2>/dev/null || echo '  （/data/local/dsh.log 还没生成过）'"

echo "-- chroot 里跑交付物自身的自测（不碰网络、不起服务、端口挑随机的）"
# 注意：S() 把命令塞进单引号里交给 adb，所以这一串里绝不能再出现单引号（会出现就是静默截断）。
# \$? 只反斜杠一次：本机 sh 把它吐成 $? 交给设备层；设备层和 su 那层都在单引号里，原样传到最里层，
# 由最里层的 sh 展开成真正的退出码。（写成了 \\\\$? 的话里层会打印字面量 $?，读数就是假的。）
SELF=$ROOT/tmp/entry-selftest.out
# 拿真产物当用例：dsh 自带的首页文件在位时，把它交给自测（只读）。
# 为什么要在机上也验这一条 —— 上一版合成页面把 module script 放在 <body> 里，真页面却放在 <head> 里，
# 于是"注入排在 module 之前"这条在 Windows 上绿、在手机上错。合成用例的形状不算证据，真文件的形状才算。
PAGEFILE=$ROOT/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-web-frontend/dist/index.html
EXTRA=$(S "test -f $PAGEFILE && echo DSH_ENTRY_TEST_PAGE=${PAGEFILE#$ROOT}" 2>/dev/null | tr -d ' \r\n')
[ -n "$EXTRA" ] && echo "   （真页面在位，自测顺手对它验一遍注入顺序）" || echo "   （真页面不在位，跳过那条 —— 别把跳过读成通过）"
S "chroot $ROOT /usr/bin/env HOME=/root TMPDIR=/tmp PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin $EXTRA node /usr/local/bin/dsh-entry.js --selftest > $SELF 2>&1; echo exit=\$?; tail -1 $SELF"
S "grep -c ^FAIL $SELF 2>/dev/null | tr -d ' \r\n'"
S "grep ^FAIL $SELF 2>/dev/null | head -5"

case "${1:-}" in
  --entry)  echo "-- 起入口"; S "sh /data/local/sh/dsh-chroot.sh --entry" ;;
  --status) echo "-- 读数";   S "sh /data/local/sh/dsh-chroot.sh --status" ;;
  --check)  echo "-- 现场体检（只读、零出网：门禁 / 真首页字节顺序 / 入口自述 / 上游文件）"
            S "sh /data/local/sh/dsh-chroot.sh --run bash /root/dsh-entry-check.sh" ;;
  --pull-key)
    mkdir -p app/local
    S "cat $ROOT/root/.dsh/entry.key" 2>/dev/null | tr -d '\r' > app/local/entry.key
    if [ -s app/local/entry.key ]; then
      echo "[ok] 口令已拉到 app/local/entry.key（$(wc -c < app/local/entry.key) B，值不打印，目录在 .gitignore 里）"
      echo "     下一步：cd app && sh build.sh --install"
    else
      echo "!! 机上还没有口令文件；先在手机上跑 --entry（它会自动造）：sh tools/deploy-entry.sh --entry"
      rm -f app/local/entry.key
    fi
    ;;
  *) echo "[note] 没带 --entry/--status/--pull-key：只部署。口令要等第一次 --entry 时才造。" ;;
esac
