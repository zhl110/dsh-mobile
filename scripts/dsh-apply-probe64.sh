#!/bin/bash
# 探针 64（有写）—— 三件他点头的事一次做完，每件都留可对账的读数：
#   ① git 把 GitHub 换成 Gitee 镜像（他原话"连不上就直接换成镜像地址也可以"）
#   ② 清掉 /root 下我留的一次性脚本 + /tmp 里我自己造的残留（他原话"没用的话就直接清掉"）
#   ③ 四批工具包到底各是什么：带 recommends 与不带 两套数 + 下载量 + 装完占多少（只算不装）
# 红线：只删自己建的；删之前逐个校 md5 与本地孪生件；不碰 /data/local/tmp 他那批；不 reboot。
set -u
cd / || exit 1        # 坑（AGENTS.md 铁律 2）：别在要删的目录里删它
echo "chroot 内时刻: $(date '+%F %T %Z')  HOME=$HOME"

echo
echo "== ① git 换镜像"
echo "-- 配之前：$(git config --global --list 2>/dev/null | wc -l) 条全局配置"
git config --global url."https://gitee.com/mirrors/".insteadOf "https://github.com/"
echo "-- 配之后（原文）："
git config --global --list 2>/dev/null | sed 's/^/   /'
echo "-- 退回命令（他要撤的时候照抄）：git config --global --unset url.https://gitee.com/mirrors/.insteadOf"
echo "-- 生效吗：拿五个仓各 ls-remote 一次（不带 --resolve，走真解析）"
for R in git/git golang/go rust-lang/rust deepseek-ai/dsh-market zhl110/dsh-mobile; do
  T0=$(date +%s)
  OUT=$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false timeout 25 git ls-remote "https://github.com/$R.git" 2>&1); RC=$?
  N=$(printf '%s\n' "$OUT" | grep -c 'refs/')
  ERR=$(printf '%s\n' "$OUT" | grep -iE 'fatal|error|could not|not found|Authentication' | head -1 | cut -c1-90)
  printf '   %-26s rc=%-3s refs=%-4s %ss  %s\n' "$R" "$RC" "$N" "$(( $(date +%s) - T0 ))" "${ERR:-（无错误行）}"
done
echo "   （判据照 AGENTS.md：refs>0 才算真读到；rc=128 可能是'要口令'被 GIT_ASKPASS 顶回来的假失败）"

echo
echo "== ② 清 /root 一次性脚本（先校本地孪生件，再删）"
EXPECT="dsh-ask.sh:732:417cf35c7e85 dsh-auth-host-probe.sh:1464:4a5d05d0b8da dsh-probe.sh:3681:7dce4ef64aa1 dsh-sbx-probe.sh:3318:fc58a2ce75e1 dsh-setup-in-chroot.sh:5958:eb6fa9be909b dsh-terminal-probe.sh:1189:e64f40929ad5"
DELETED=0; KEPT=0
for E in $EXPECT; do
  F=${E%%:*}; REST=${E#*:}; SZ=${REST%%:*}; MD=${REST#*:}
  P=/root/$F
  if [ ! -f "$P" ]; then echo "   $F 机上没有，跳过"; KEPT=$((KEPT+1)); continue; fi
  ASZ=$(wc -c < "$P"); AMD=$(md5sum "$P" | cut -c1-12)
  if [ "$ASZ" = "$SZ" ] && [ "$AMD" = "$MD" ]; then
    rm -f "$P"; echo "   删 $F（$ASZ B md5 $AMD = 本地孪生件）"; DELETED=$((DELETED+1))
  else
    echo "   !! 留 $F：机上 $ASZ B/md5 $AMD ≠ 本地 $SZ B/md5 $MD ⇒ 不是同一份，不删"
    KEPT=$((KEPT+1))
  fi
done
echo "   两份留着不删：/root/doh-hosts.sh（/root/.dsh-env 引用它）与 /root/dsh-entry-check.sh（deploy-entry.sh 每次都推的那份交付件）"
for KEEP in doh-hosts.sh dsh-entry-check.sh; do printf "   %-22s %s B  md5 %s
" "$KEEP" "$(wc -c < /root/$KEEP 2>/dev/null)" "$(md5sum /root/$KEEP 2>/dev/null | cut -c1-12)"; done
echo "-- 删完 /root/*.sh 还剩："
ls -l /root/*.sh 2>/dev/null | awk '{printf "   %8s B  %s\n", $5, $7}'; echo "   计数: $(ls /root/*.sh 2>/dev/null | wc -l)（删掉 $DELETED 个、留下 $KEPT 个）"

echo
echo "== ②b /tmp 残留：谁造的、谁在用"
ls -l --time-style=+%m-%d_%H:%M /tmp 2>/dev/null | awk 'NR>1 && NF>=7 {printf "   %8s B  %s  %s\n", $5, $6, $7}'
echo "   顶层计数: $(ls -A /tmp 2>/dev/null | wc -l)"
echo "-- 活着的 dsh/node 进程攥着哪些 /tmp 路径："
HELD=0
for P in $(pgrep -f 'dsh|node' 2>/dev/null); do
  [ -r "/proc/$P/cmdline" ] || continue
  FD=$(ls -l "/proc/$P/fd" 2>/dev/null | grep -o '/tmp/[^ ]*' | sort -u | tr '\n' ' ')
  if [ -n "$FD" ]; then echo "   pid $P 攥着: $FD"; HELD=$((HELD+1)); fi
done
echo "   有攥着的 pid 数: $HELD（0 = 没人用，但下面的名单我照样只删自己造的）"
MINE=$(ls -A /tmp 2>/dev/null | grep -E '^(p[0-9]+|probe|dsh-side|dsh-prep|cdp-)' | tr '\n' ' ')
echo "-- 名字对得上是我造的（p*/probe*/cdp-*）: ${MINE:-无}"
for X in $MINE; do
  SZ=$(wc -c < "/tmp/$X" 2>/dev/null); rm -f "/tmp/$X"; echo "   删 /tmp/$X（$SZ B）"
done
echo "-- 清完还剩 $(ls -A /tmp 2>/dev/null | wc -l) 个顶层条目："
ls -A /tmp 2>/dev/null | sed 's/^/   /'

echo
echo "== ③ 四批工具包：两套数（simulate，一个不装）"
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
for spec in \
  "文档办公|libreoffice-writer pandoc|写 docx/odt 的办公软件 + 文档格式转换" \
  "OCR|tesseract-ocr|图片里认字" \
  "语言栈|rustc golang-go default-jdk|编译 Rust/Go/Java" \
  "容器|docker.io podman|跑容器（这台起不来）"; do
  LBL=$(echo "$spec" | cut -d'|' -f1); PKGS=$(echo "$spec" | cut -d'|' -f2); NOTE=$(echo "$spec" | cut -d'|' -f3)
  echo "-- $LBL（$PKGS）＝ $NOTE"
  for MODE in "" "--no-install-recommends"; do
    RAW=$(apt-get -s install $MODE $PKGS 2>/dev/null); RC=$?
    N=$(printf '%s\n' "$RAW" | grep -c '^Inst ')
    GET=$(printf '%s\n' "$RAW" | grep -oE 'Need to get [0-9., ]+[kB/MB/GB]+' | head -1)
    [ -z "$GET" ] && GET=$(printf '%s\n' "$RAW" | grep -m1 'Need to get' | cut -c1-70)
    AFT=$(printf '%s\n' "$RAW" | grep -m1 'After this operation' | sed 's/.*operation, //')
    printf '   %-22s rc=%s 包数=%-4s %s  %s\n' "${MODE:-含 recommends}" "$RC" "$N" "${GET:-（无下载行）}" "${AFT:-}"
  done
done
echo "   （两套数只差在 recommends。哪一套对得上我上一轮报给他的 84/6/61/29，看上面两列读数，不猜）"
echo "-- 磁盘：$(df -h / | awk 'NR==2{print "根分区 "$4" 可用（"$2" 总）"}')"
echo "-- apt 缓存：$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)  个 .deb: $(ls /var/cache/apt/archives/*.deb 2>/dev/null | wc -l)"

echo
echo "== ④ 这发有没有留东西"
echo "   /root 下 .sh 计数: $(ls /root/*.sh 2>/dev/null | wc -l)   /tmp 顶层: $(ls -A /tmp 2>/dev/null | wc -l)"
echo "   （探针自己由 tools/run-probe.sh 删）"
