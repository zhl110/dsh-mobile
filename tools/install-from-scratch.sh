#!/usr/bin/env bash
# tools/install-from-scratch.sh —— PC 侧一键：把 payload 装成"点开就能用"的三层（rootfs → 入口 → 壳 App）
#
# 谁来跑、跑之前要有什么：
#   一台 **已 root** 的 arm64 Android（本项目实测：一加 13 / Android 15 / KernelSU），USB 调试放行，
#   git-bash + adb + JDK（打 APK 用，见 app/build.sh 那套工具链），以及这份仓。
#   payload 那发 tar.gz 不在仓里（GB 级 + git 存不了属主，理由见 tools/make-payload.sh 头注释），
#   要么本地 release-assets/ 里已有，要么从 GitHub Release 下（走 gh；没有 gh 就把 URL 当参数传进来）。
#
# 顺序不能换的三处（下一个人最容易在这里省事然后撞）：
#   · 解压必须**在设备上以 root** 解 —— PC 侧解出来的属主全丢，chroot 里 passwd/su 那族就废了；
#   · tools/deploy-entry.sh 推的四件里有两件落点在 chroot 里面 ⇒ 必须先解压；
#   · APK 要烤入口口令 ⇒ 必须先 --entry 造出 entry.key，再 --pull-key，再 build.sh（首装的鸡生蛋）。
#
# ⚠ 这脚本会往 /data/local/dsh-rootfs 写东西；第 6 步只在这台机上**还没有** /root/.dsh-env 时才部署模板，
#   已有就只对账不覆写。现役那台机（现场有会话、有他自己改过的 .dsh-env）别拿它跑 ——
#   第 3 步还有"rootfs 目录非空就停"的闸。要在那台机上重部署 env 请单独走 tools/deploy-env.sh。
#
# 用法：
#   bash tools/install-from-scratch.sh                      # 全流程（本地有包用本地，没有就 gh 拉 Release）
#   bash tools/install-from-scratch.sh <本地 tar.gz 或 URL>  # 指定包
#   bash tools/install-from-scratch.sh --skip-app           # 只装到"入口 + 引擎起来"，不打/不装 APK
#   bash tools/install-from-scratch.sh --verify             # 只跑现场体检（dsh-entry-check.sh），一个字节都不写
set -u
export MSYS2_ARG_CONV_EXCL='*'
cd "$(dirname "$0")/.."

ADB="${DSH_ADB:-/d/mycode/.agent-tools/platform-tools/adb.exe}"
[ -x "$ADB" ] || ADB="C:/Users/周海龙/DeskBox/我的桌面/platform-tools/adb.exe"
[ -x "$ADB" ] || { echo "!! 找不到 adb（两条路径都试过；用 DSH_ADB=... 指一下）"; exit 1; }
command -v sha256sum >/dev/null || { echo "!! 要 git-bash 的 sha256sum"; exit 1; }

ROOT=/data/local/dsh-rootfs
REPO=zhl110/dsh-mobile
OUTDIR=release-assets
ARG=${1:-}
SKIP_APP=0; VERIFY=0
[ "$ARG" = "--skip-app" ] && { SKIP_APP=1; ARG=${2:-}; }
[ "$ARG" = "--verify" ] && { VERIFY=1; ARG=${2:-}; }

# 引号形状照 tools/run-probe.sh:45：外层双引号给 adb、转义双引号给 su -c ⇒ 串里可以出现单引号
S() { "$ADB" shell "su -c \"$1\"" </dev/null 2>&1 | tr -d '\r'; }

check() { echo "== 现场体检（真产物：首页字节、门禁、入口自述、上游文件）"; S "sh /data/local/sh/dsh-chroot.sh --run 'bash /root/dsh-entry-check.sh'" | sed 's/^/  /'; }
if [ "$VERIFY" = 1 ]; then check; exit 0; fi

echo "== 0 前置"
"$ADB" get-state >/dev/null 2>&1 || { echo "!! 设备不在 device 状态（插好、解锁、放行 USB 调试）"; exit 1; }
echo "  设备  : $(S "getprop ro.product.model; getprop ro.build.version.release" | tr '\n' ' ')"
ID=$(S "id"); case "$ID" in *"uid=0"*) echo "  root  : ok" ;; *) echo "!! su 拿不到 root：$ID"; exit 1 ;; esac
ABI=$(S "getprop ro.product.cpu.abi")
case "$ABI" in *arm64*) echo "  架构  : $ABI（payload 是 arm64 那棵树）" ;; *) echo "!! 架构 $ABI ≠ arm64 ⇒ 这发 payload 装上去起不来"; exit 1 ;; esac
echo "  /data 剩 : $(S "df -k /data | tail -1 | tr -s ' ' | cut -d' ' -f4") KB（包体 + 解出来约 5.5 GB）"
for c in tar gzip; do echo "  设备上 $c : $(S "command -v $c || echo 没有")"; done

echo "== 1 取 payload 并逐字节撞 sha256"
[ -n "$ARG" ] && [ ! -f "$ARG" ] && [ "${ARG:0:4}" != "http" ] && { echo "!! 给的包不存在：$ARG"; exit 1; }
PKG=$ARG
if [ -f "$PKG" ]; then :; elif [ "${PKG:0:4}" = "http" ]; then
  mkdir -p "$OUTDIR"; OUT=$OUTDIR/$(basename "$PKG"); echo "  下载 → $OUT"
  curl --ssl-no-revoke -L --fail -o "$OUT" "$PKG" || { echo "!! 下载失败"; exit 1; }; PKG=$OUT
else
  mkdir -p "$OUTDIR"
  PKG=$(ls -1S "$OUTDIR"/dsh-rootfs-*.tar.gz 2>/dev/null | head -1)
  if [ -z "$PKG" ]; then
    echo "  本地没有 ⇒ gh release download"
    command -v gh >/dev/null || { echo "!! 既没有本地包也没有 gh；把 tar.gz 的路径或下载 URL 当参数传进来"; exit 1; }
    gh release download --repo "$REPO" --pattern 'dsh-rootfs-*' --dir "$OUTDIR" || { echo "!! gh 拉不下来"; exit 1; }
    PKG=$(ls -1S "$OUTDIR"/dsh-rootfs-*.tar.gz 2>/dev/null | head -1)
  fi
fi
[ -n "$PKG" ] && [ -f "$PKG" ] || { echo "!! 没有 payload 包（给路径、给 URL，或先在本机跑 tools/make-payload.sh）"; exit 1; }
if ls "${PKG}"-part-* >/dev/null 2>&1; then
  echo "  合卷：$(ls -1 "${PKG}"-part-* | wc -l | tr -dc '0-9') 卷"
  cat $(ls -1 "${PKG}"-part-* | sort) > "${PKG}.m" && mv "${PKG}.m" "${PKG}" || { echo "!! 合卷失败"; exit 1; }
fi
SZ=$(wc -c <"$PKG" | tr -dc '0-9'); GOT=$(sha256sum "$PKG" | cut -d' ' -f1)
EXP=$(grep -m1 " $(basename "$PKG")\$" "$OUTDIR/SHA256SUMS" 2>/dev/null | cut -d' ' -f1)
if [ -n "$EXP" ]; then
  [ "$GOT" = "$EXP" ] && echo "  [ok] sha256 撞上 $GOT（$SZ B）" || { echo "!! sha 不撞：包 $GOT / 清单 $EXP ⇒ 停"; exit 1; }
else
  echo "  !! SHA256SUMS 里没有这一发的行 ⇒ 指纹与包不同源（认它=自担风险）：$GOT"
fi

echo "== 2 推包到设备"
T0=$(date +%s)
"$ADB" push "$PKG" /data/local/tmp/dsh-rootfs.tar.gz >/dev/null || { echo "!! push 失败"; exit 1; }
DS=$(S "wc -c < /data/local/tmp/dsh-rootfs.tar.gz" | tr -dc '0-9')
[ "$DS" = "$SZ" ] || { echo "!! 设备侧 $DS B ≠ 本地 $SZ B ⇒ 停，不解压"; exit 1; }
echo "  [ok] 逐字节相同（$SZ B，$(( $(date +%s) - T0 )) 秒）"

echo "== 3 设备上以 root 解压"
EXIST=$(S "ls -A $ROOT 2>/dev/null | wc -l" | tr -dc '0-9')
if [ "${EXIST:-0}" != "0" ]; then
  echo "!! $ROOT 非空（$EXIST 个条目）⇒ 这上面已经有东西，本脚本不替你决定覆不覆盖。"
  echo "   确认要让位：adb shell su -c \"mv $ROOT ${ROOT}.old.<时间戳>\" 之后再跑一遍。（mv 不删，随时能挪回来）"
  exit 1
fi
S "mkdir -p $ROOT && tar -xzf /data/local/tmp/dsh-rootfs.tar.gz -C $ROOT; echo tar_rc=\$?"
S "rm -f /data/local/tmp/dsh-rootfs.tar.gz"
echo "  解出来 : $(S "du -sb $ROOT 2>/dev/null | cut -f1") B / $(S "ls -A $ROOT | wc -l" | tr -dc '0-9') 个一级条目"
echo "  关键件 : $(S "ls -l $ROOT/usr/local/bin/node $ROOT/usr/local/lib/node_modules/@deepseek-ai 2>&1 | head -4" | tr '\n' ' ')"
echo "  属主抽样（这两发必须有 0:0 与 setuid 位）:"
S "ls -l -n $ROOT/usr/bin/passwd $ROOT/usr/bin/su" | sed 's/^/    /'

echo "== 4 挂载点与 tmp 权限（runner 要目录先存在：scripts/dsh-chroot.sh:89-98）"
S "mkdir -p $ROOT/proc $ROOT/sys $ROOT/dev $ROOT/dev/shm $ROOT/run $ROOT/tmp; chmod 1777 $ROOT/tmp $ROOT/run; echo rc=\$?"
S "ls -ld $ROOT/proc $ROOT/sys $ROOT/dev $ROOT/run $ROOT/tmp" | sed 's/^/  /'

echo "== 5 推入口那四件（落点有两件在 chroot 里，所以排在解压之后）"
sh tools/deploy-entry.sh || { echo "!! deploy-entry.sh 没过"; exit 1; }

echo "== 6 引擎环境变量"
echo "  payload 里**不含** /root/.dsh-env、入口口令、任何 API key（剥除清单单一真源在 scripts/dsh-payload-pack.sh）。"
echo "  模型 provider 的 key 装机后在网页「设置」里自己加 —— 这是设计，不是漏装。"
if [ -n "$(S "ls $ROOT/root/.dsh-env 2>/dev/null")" ]; then
  echo "  机上已经有 /root/.dsh-env ⇒ 不覆写它，先对账："
  sh tools/deploy-env.sh --check || true
else
  echo "  新机没有 /root/.dsh-env ⇒ 把仓库模板 config/dsh-env 部署过去（档位、npm 镜像那三条）"
  sh tools/deploy-env.sh || { echo "!! deploy-env.sh 没写成"; exit 1; }
fi

echo "== 7 起入口（第一次会造 entry.key，0600，值不打印）"
sh tools/deploy-entry.sh --entry || { echo "!! 入口没起来"; exit 1; }
sleep 8; check
if [ "$SKIP_APP" = 1 ]; then
  echo "[done] --skip-app：没打也没装 APK。浏览器打开 http://127.0.0.1:3081/ 后进口令即可，口令在 $ROOT/root/.dsh/entry.key"
  exit 0
fi

echo "== 8 拉口令 → 烤进 APK → 只装机不重打之外的动作都交给现成脚本"
sh tools/deploy-entry.sh --pull-key || { echo "!! 口令没拉下来"; exit 1; }
bash app/build.sh || { echo "!! APK 重打失败（工具链见 app/build.sh 顶部）"; exit 1; }
bash tools/install-apk.sh || { echo "!! 装机失败"; exit 1; }

echo "== 9 交付"
echo "  桌面多出 'dsh' 图标，点开就是首页；不想装壳就手机 Chrome 开 http://127.0.0.1:3081/ 进口令。"
echo "  口令文件：$ROOT/root/.dsh/entry.key（44 B，别外发）。"
check
