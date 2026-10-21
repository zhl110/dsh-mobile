#!/bin/bash
# 探针 63（只读）—— 为他说这四件事取现场读数：
#   ① GitHub 换镜像：git 全局配置现在有什么、HOME 是哪
#   ② 四批工具包到底装了什么：逐批 apt-get -s（simulate，一个不装）列包名 + 下载量 + 装完占多少
#   ③ /root 那 8 个脚本与 /tmp 那 4 个临时件：谁在用（引擎 fd）——删之前要有依据
#   ④ 键盘顶输入框 / 整栏可滑：安卓侧软键盘模式与 WebView 调试通道在不在
# 铁律：只读。不 rm、不 install、不写配置。计数一律逐行相加，不用 test -e 猜。
set -u
echo "chroot 内时刻: $(date '+%F %T %Z')   HOME=$HOME   whoami=$(id -un)"

echo
echo "== 1 git 全局配置现状（换镜像前）"
if [ -f "$HOME/.gitconfig" ]; then
  echo "  文件在，$(wc -c < "$HOME/.gitconfig") B，内容："
  sed 's/^/    /' "$HOME/.gitconfig"
else
  echo "  $HOME/.gitconfig 不存在（一次配置都没写过）"
fi
echo "  git: $(git --version 2>&1 | head -1)"

echo
echo "== 2 四批包：逐批 simulate（-s 只算不装）"
export DEBIAN_FRONTEND=noninteractive
batch_names=""
for spec in \
  "文档办公|libreoffice-writer pandoc" \
  "OCR|tesseract-ocr" \
  "语言栈|rustc golang-go default-jdk" \
  "容器|docker.io podman"; do
  LBL=${spec%%|*}; PKGS=${spec#*|}
  RAW=$(apt-get -s install $PKGS 2>/dev/null); RC=$?
  echo "-- $LBL  输入包：$PKGS  rc=$RC"
  if [ "$RC" != 0 ]; then echo "   !! 这条没算出来，原文首 3 行："; printf '%s\n' "$RAW" | head -3 | sed 's/^/     /'; continue; fi
  printf '%s\n' "$RAW" | grep '^Inst ' | sed 's/^Inst \([^ ]*\).*/\1/' | sort > "/tmp/p63-$LBL.lst"
  N=$(wc -l < "/tmp/p63-$LBL.lst")
  echo "   要装的包数: $N   （新装 $(printf '%s\n' "$RAW" | grep -c '^Inst [^ ]* \[') 个是升级、其余全新）"
  echo "   $(printf '%s\n' "$RAW" | grep -E 'Need to get|After this operation' | tr '\n' ' ')"
  echo "   包名: $(tr '\n' ' ' < "/tmp/p63-$LBL.lst")"
  batch_names="$batch_names$LBL=$N "
done
echo "-- 逐行相加对账: $batch_names"
TOT=0; for L in 文档办公 OCR 语言栈 容器; do [ -f "/tmp/p63-$L.lst" ] && TOT=$(( TOT + $(wc -l < "/tmp/p63-$L.lst") )); done
echo "-- 四批合计（含重复）: $TOT"
sort /tmp/p63-*.lst | uniq -d | tr '\n' ' ' | sed 's/^/-- 跨批重复的包: /'
echo

echo
echo "== 3 /root 下的 .sh（我留下的那批）与 /tmp 残留：谁持有"
echo "-- /root/*.sh 清单（大小 / 时刻）:"
ls -l --time-style=+%m-%d_%H:%M /root/*.sh 2>/dev/null | awk '{printf "   %8s B  %s  %s\n", $5, $6, $7}'
NSH=$(ls /root/*.sh 2>/dev/null | wc -l); echo "   计数: $NSH"
echo "-- 这些脚本有没有被别的脚本/服务引用（排除自己）:"
for f in /root/*.sh; do
  B=$(basename "$f")
  HITS=$(grep -rl --exclude="$B" -e "$B" /root /data/local/sh /root/.dsh 2>/dev/null | tr '\n' ' ')
  echo "   $B → 引用者: ${HITS:-无}"
done
echo "-- /tmp 顶层残留:"
ls -l --time-style=+%m-%d_%H:%M /tmp 2>/dev/null | awk 'NR>1{printf "   %s  %s %s\n", $6, $5, $9}'
echo "-- 正在跑的进程手里攥着哪些 /tmp 路径（删前必看）:"
for p in $(pgrep -f 'dsh|node' 2>/dev/null); do
  CMD=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | cut -c1-60)
  FD=$(ls -l /proc/$p/fd 2>/dev/null | grep -o '/tmp/[^ ]*' | sort -u | tr '\n' ' ')
  [ -n "$FD" ] && echo "   pid $p [$CMD] → $FD"
done
echo "   （上面没行的 pid 表示它没攥 /tmp 文件）"

echo
echo "== 4 软键盘与 WebView 调试通道（改 UI 前）"
echo "-- 壳 APK 进程:"
ps -A -o PID,NAME 2>/dev/null | grep -iE 'zhl.dsh|dsh' | head -5 | sed 's/^/   /'
echo "-- 调试 socket（webview_devtools_remote_<pid>）:"
grep -o 'webview_devtools_remote_[0-9]*' /proc/net/unix 2>/dev/null | sort -u | sed 's/^/   /'
echo "   计数: $(grep -c webview_devtools_remote /proc/net/unix 2>/dev/null)"
echo "-- 屏幕状态:"
dumpsys power 2>/dev/null | grep -E 'mWakefulness|mScreenOn' | head -3 | sed 's/^/   /'
echo "-- 当前焦点窗口 / 软键盘模式:"
dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus|mSoftInputMode|softInputMode' | head -6 | sed 's/^/   /'
echo "-- 输入法窗口有没有起（imm state）:"
dumpsys input_method 2>/dev/null | grep -E 'mInputShown|mIsInputViewShown|isInputViewShown|mCurModality' | head -5 | sed 's/^/   /'

echo
echo "== 5 出口页现在什么样（不带 --resolve，凭证走 stdin）"
KEY=/root/.dsh/entry.key
if [ -f "$KEY" ]; then
  OUT=$(printf 'cookie = dsh-entry=%s\nurl = "http://127.0.0.1:3081/"\n' "$(cat "$KEY")" | curl -s -K - -o /tmp/p63-page.html -w '%{http_code} %{size_download}' 2>&1)
  echo "   页: code/bytes = $OUT"
  if [ -s /tmp/p63-page.html ]; then
    echo "   标记计数: compat=$(grep -c 'data-dsh-entry-compat' /tmp/p63-page.html) side_attr=$(grep -c 'data-dsh-side-scroll' /tmp/p63-page.html) side_var=$(grep -c '__DSH_SIDE__' /tmp/p63-page.html)"
  fi
  echo "   设备侧兼容层: $(wc -c < /root/.dsh/entry-compat.js) B md5=$(md5sum /root/.dsh/entry-compat.js | cut -c1-32)"
else
  echo "   !! 钥匙文件不在，这节跳过"
fi
echo "-- 入口/引擎进程:"
pgrep -af 'dsh-entry|dsh web' 2>/dev/null | head -4 | sed 's/^/   /'

echo
echo "== 6 这发有没有留东西"
echo "   /root 下 .sh 计数（不含本探针）: $(ls /root/*.sh 2>/dev/null | grep -v dsh-final-probe63 | wc -l)"
rm -f /tmp/p63-*.lst /tmp/p63-page.html
echo "   /tmp 里 p63 残留: $(ls /tmp/p63-* 2>/dev/null | wc -l)"
echo "   （探针自己由 tools/run-probe.sh 负责删）"
