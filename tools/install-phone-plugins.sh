#!/bin/bash
# tools/install-phone-plugins.sh —— 把电脑上那两发插件（dsh-purge / dshmarket）装进**手机 chroot 里的 dsh web profile**。
#
# 为什么不手搓 adb：这个坑我摔过三次（MSYS 把 /data/... 改写、adb 输出带 CRLF、推上去的文件忘在机上），
# 所以这里沿用 tools/run-probe.sh 那套：MSYS2_ARG_CONV_EXCL='*'、每条输出 tr -d '\r'、su -c 三层引号统一走 S()。
#
# 规矩（AGENTS.md 铁律 2）：**报数只认能对上的数** —— 清单 N 发 ⇒ 推上去 N 发 ⇒ sha256 逐字节撞上 N 发，三个数必须相等才算"落进手机了"。
# 这脚本**只装不启用**：装完 purge 仍是"在列表里"，真改提示词要他在 App 里点它那记「应用」；
# 引擎重启也不在这里自动做（打印出该跑哪条，等他/我看完读数再动）。
#
# 用法：
#   bash tools/install-phone-plugins.sh --check    # 只做本地清单 + 设备与 pnpm 前置，一个字节不写
#   bash tools/install-phone-plugins.sh            # 真装（默认那两发）
#   bash tools/install-phone-plugins.sh <别的路径.tgz> …
set -u
cd "$(dirname "$0")/.." || exit 2
export MSYS2_ARG_CONV_EXCL='*'

ADB=${ADB:-}
[ -n "$ADB" ] || for c in /d/mycode/.agent-tools/platform-tools/adb.exe "$HOME/.agent-tools/platform-tools/adb.exe"; do
  [ -f "$c" ] && { ADB=$c; break; }; done
[ -n "$ADB" ] && [ -x "$ADB" ] || { echo "!! 找不到 adb（可 ADB=/路径/adb.exe 指定）"; exit 2; }

ROOTFS=/data/local/dsh-rootfs
RUNNER=/data/local/sh/dsh-chroot.sh
DEVPLUGINS=dsh-plugins                       # chroot 里就是 /root/$DEVPLUGINS
DEVROOT=$ROOTFS/root
PROFILE=web                                  # 手机上那台 dsh 用的 profile（电脑上叫 desktop，别混）
MODE=${1:-}
[ "$MODE" = "--check" ] && shift || MODE=

if [ $# -gt 0 ]; then TARBALLS=("$@"); else
  TARBALLS=(/d/tools/dsh-plugins/dsh-purge-1.1.72-dsh021rc2.4.tgz
            /d/tools/dsh-plugins/dshmarket-1.66.45.tgz)
fi

STAMP=$(date +%Y%m%d-%H%M%S)
OUT=downloads/plugin-install-$STAMP.txt
mkdir -p downloads
S() { "$ADB" shell "su -c \"$1\"" </dev/null 2>&1 | tr -d '\r'; }        # 进宿主 root
R() { "$ADB" shell "su -c \"$RUNNER --run 'bash -lc \\\"$1\\\"'\"" </dev/null 2>&1 | tr -d '\r'; }  # 进 chroot
L() { echo "$@" | tee -a "$OUT"; }

L "== 0. 本地清单（$MODE）"
LISTED=0
for f in "${TARBALLS[@]}"; do
  if [ -f "$f" ]; then
    L "  $(wc -c <"$f" | tr -d ' ') B  sha256 $(sha256sum "$f" | cut -c1-16)  $(basename "$f")"
    LISTED=$((LISTED+1))
  else
    L "  !! 本地就没这个文件：$f"
  fi
done
L "  清单计数 = $LISTED"
[ "$LISTED" = "${#TARBALLS[@]}" ] || { L "!! 清单不齐，停"; exit 1; }

L "== 1. 设备前置"
DEVN=$("$ADB" devices | tail -n +2 | tr -d '\r' | grep -c 'device$')
L "  adb 里 device 计数 = $DEVN（要恰好 1）"
[ "$DEVN" = "1" ] || { L "!! 手机没连或连了多台，停（这脚本不猜设备）"; exit 1; }
L "  runner 在 = $(S "ls $RUNNER >/dev/null 2>&1 && echo yes || echo no")"
HASPNPM=$(R "command -v pnpm || true")
L "  chroot 里 pnpm = ${HASPNPM:-（没有）}"
L "  chroot 里 dsh  = $(R "command -v dsh || true")"
L "  registry       = $(R "npm config get registry 2>/dev/null || echo 空")"
if [ -z "$HASPNPM" ]; then
  L "!! chroot 里没有 pnpm ⇒ \`dsh plugin add\` 必然不通（它只是把参数转给 pnpm）。"
  L "   补它的动作是**往他机器上装包**，按规矩要他点头：npm i -g pnpm@10（走 npmmirror，手机自己能下，解析已在状态 25 修好）。"
  exit 1
fi
[ "$MODE" = "--check" ] && { L "== --check 完，一个字节没写"; exit 0; }

L "== 2. 落点目录（chroot /root/$DEVPLUGINS，0700）"
S "mkdir -p $DEVROOT/$DEVPLUGINS; chmod 700 $DEVROOT/$DEVPLUGINS; chown root:root $DEVROOT/$DEVPLUGINS; ls -ld $DEVROOT/$DEVPLUGINS" | tee -a "$OUT"

PUSHED=0; MATCHED=0
L "== 3. 逐条推 + 逐字节撞 sha256（清单 $LISTED）"
for f in "${TARBALLS[@]}"; do
  b=$(basename "$f"); STAGE=/data/local/tmp/$b
  # **坑（2026-10-21 当晚真摔）**：`adb.exe` 是原生 Windows 程序，喂它 git-bash 的 POSIX 路径
  # （`/d/tools/...`）它看不见，直接 `cannot stat`；而第 0 步本地 `wc -c` / `sha256sum` 用的却是同一串路径且**读得到**，
  # 所以症状是"清单说 2 发都在、推的时候两发都找不到"。⇒ 过 adb 之前一律 `cygpath -w` 转成 `D:\...`。
  # `--check` 那条分支不推文件，所以它**永远抓不到这个坑**，别拿 --check 绿了当"这条路通"。
  WIN=$(cygpath -w "$f" 2>/dev/null || printf '%s' "$f")
  PO=$("$ADB" push "$WIN" "$STAGE" </dev/null 2>&1); PR=$?
  L "  push $WIN → $STAGE rc=$PR  $(printf '%s' "$PO" | tr -d '\r' | tail -1)"
  [ "$PR" = "0" ] || { L "!! push 失败，停（不往下撞 sha、不装）"; exit 1; }
  S "cp $STAGE $DEVROOT/$DEVPLUGINS/$b; rm -f $STAGE; stat -c '  %n %s B' $DEVROOT/$DEVPLUGINS/$b" | tee -a "$OUT"
  LOC=$(sha256sum "$f" | cut -d' ' -f1)
  DEV=$(S "sha256sum $DEVROOT/$DEVPLUGINS/$b" | cut -d' ' -f1)
  if [ "$LOC" = "$DEV" ]; then L "  [ok] $b 逐字节相同（sha256 ${LOC:0:16}…）"; MATCHED=$((MATCHED+1)); else L "  !! $b 不撞：本地 ${LOC:0:16} 设备 ${DEV:0:16}"; fi
  PUSHED=$((PUSHED+1))
done
L "  三个计数：清单 $LISTED / 推上去 $PUSHED / sha 撞上 $MATCHED"
[ "$LISTED" = "$PUSHED" ] && [ "$LISTED" = "$MATCHED" ] || { L "!! 三个数不相等 ⇒ 不往下装"; exit 1; }

L "== 4. 装（dsh plugin --profile $PROFILE add，逐个）"
for f in "${TARBALLS[@]}"; do
  b=$(basename "$f")
  L "--- add $b"
  R "cd /root/.dsh/profiles/$PROFILE && timeout 900 dsh plugin --profile $PROFILE add /root/$DEVPLUGINS/$b 2>&1 | tail -18" | tee -a "$OUT"
done

L "== 5. 装完复测（只看盘，不看退出码）"
# 坑（2026-10-21 17:51 我自己踩的）：**R() 的字符串里不能出现 \$( )**。
# 三层引号送到机上后，那个命令替换是被最外层 /system/bin/sh 求值的（它的 cwd 是 /，没有 package.json），
# 于是第一轮这里打出 `package.json= B`（空）和 `非隐藏条目=0` —— 而同一行上面 5 个条目正列在那儿。
# 修法：让远端自己打印数字（wc -l 单独一行、stat 直接给文件），要计数就另跑一支探针（scripts/dsh-plugins-verify34.sh）。
R "cd /root/.dsh/profiles/$PROFILE; echo '--- package.json（wc -c 直接给文件，不走重定向）'; wc -c package.json; cat package.json; echo '--- node_modules 顶层'; ls -1 node_modules 2>/dev/null; echo '--- 可见条目数'; ls -1 node_modules 2>/dev/null | wc -l; echo '--- 含隐藏条目数'; ls -1A node_modules 2>/dev/null | wc -l; echo '--- .dsh-market'; ls -l .dsh-market 2>/dev/null || echo '（还没有 .dsh-market）'; echo '--- profile 体积'; du -sh ." | tee -a "$OUT"

L "== 6. 剩下的两件事"
L "  ① **重启引擎这台大概率不需要**（2026-10-21 17:51 复核，见 RUNBOOK 14.27）：装完 6 秒 /root/.dsh 下就长出了"
L "     dsh-purge/{installed-rev,override-state.json}、prompt-inject.md、redteam 预设，12 秒后 .dsh-market/state.json —— 而 package.json 是 09:51:07Z 落的；"
L "     引擎（pid 17637）10-20 13:27Z 生、没重启过，它 fd 23 的 inotify 正监视着 package.json 那个 inode，层栈里 hmr 那层在位。"
L "     原先这里写的是「新 bundle 要进层栈得重启」——那是照电脑上那条推的，**手机上这次没等到重启就先接住了**（14.27 有对账）。"
L "     真判据看 App：插件页有这两发、侧边栏有「插件市场」入口、预设列表有「红队模式」。看不见再重启（入口和引擎都要：--stop && --entry）。"
L "  ② **没点「应用」**：purge 真改提示词那一步在 App 的插件页上，按它 README 不该由助手代点。"
L "     另外这台机上 purge 落盘时顺手注册了一个第三方 agent 预设（红队模式，25 件 231K）并写了 24,455 B 的 prompt-inject.md，内容是把系统提示换成'有问必答'人格 —— 要不要留，归他定。"
L "  回滚：dsh plugin --profile $PROFILE remove dsh-purge；remove dshmarket；推上去的两份在 /root/$DEVPLUGINS/（要删说一句我再删，那是我建的文件）"
L "== 读数全文在 $OUT"
