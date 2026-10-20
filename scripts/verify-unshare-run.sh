#!/system/bin/sh
# verify-unshare-run.sh — 验 scripts/dsh-unshare-run.sh：真围得住、工作区真能写、别把外面带崩、
#                        也别把自己配死（报错词表和 dsh 的 runnerFailureSignatures 撞不撞）
#
# 为什么要单独验它：dsh 一旦配了 runnerCommand，它就把 enforcement 直接记成 "full"
# （reference/dsh-sandbox-local-index.js:318 那句），**不探测、不验证**。也就是说这个 runner 要是
# 偷偷没围住，dsh 那边看不出来，日志上还是"已围堵"。所以围没围必须由我们自己对天验。
#
# 写法约束（两条都是本轮踩出来的）：
#   1. 跑在手机宿主侧，/system/bin/sh = mksh，没数组，参数表只能当一个普通字符串拼。
#   2. 判据不许在四层引号里现写——所有"往 chroot 里塞带引号的判断"都塞进 dsh-sbx-probe.sh，
#      外层只拼参数 + grep KEY=。第一版就是第 57 行那句 mount | grep " /tmp " 把 bash 打成
#      unexpected EOF，12 条 FAIL 全是我测试件的锅，不是 runner 的。
#
# 用法（root，宿主侧）：sh /data/local/tmp/verify-unshare-run.sh
# 全程只造带 dsh-sbx-probe 前缀的文件，跑完自己删干净并复验删除结果。
set -u
ROOTFS=/data/local/dsh-rootfs
EP=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUNNER=/usr/local/bin/dsh-unshare-run          # chroot 内 runner 路径
# 探针放 /data/local/tmp：本机 su 域(u:r:su:s0)往 /data/local/sh 里新建/改权限是**间歇性 EPERM**
# （2026-10-20 实测：同一句 cp 成功、紧跟着的 chmod 就报 Permission denied，下一条 su 会话连
#  create 都不行；同一个 root 在 /data/local/tmp 和 chroot 里 chmod 全是 rc=0）。不追那条政策的来源，
#  只把测试件放到读数稳定的一侧，免得把自己的验收做成"随机 FAIL"。
PROBE_SRC=/data/local/tmp/dsh-sbx-probe.sh
PROBE_DST=$ROOTFS/root/dsh-sbx-probe.sh        # chroot 内探针路径（/root 只读≠读不到，围住后仍能读它）
PH=$(wc -l < /proc/self/mountinfo)
PASS=0; FAIL=0

ok()   { echo "  PASS  $*"; PASS=$((PASS+1)); }
bad()  { echo "  !! FAIL $*"; FAIL=$((FAIL+1)); }
note() { echo "  --    $*"; }

# dsh 会喂给 runner 的参数，逐字照抄 bwrapProfileArgs()（workspace-write，工作区 /phone）
BWARGS="--ro-bind / / --dev /dev --unshare-pid --proc /proc --die-with-parent --tmpfs /tmp --bind /phone /phone --"
PROBE=/root/dsh-sbx-probe.sh
# 这台内核 # CONFIG_PID_NS is not set ⇒ --unshare-pid 永远开不了。测试必须显式接受这条降级，
# 否则每一发围堵都会先撞在 unshare 的 Invalid argument 上，后面全没法验。
NS_ENV=DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=1

inchroot() { chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH="$EP" /bin/bash -lc "$1"; }
inchroot_ns() { chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp $NS_ENV PATH="$EP" /bin/bash -lc "$1"; }
# 围住之后跑探针：返回 KEY=VALUE 若干行（stderr 一起收，报错口径也要看）
probe() { inchroot_ns "$RUNNER $BWARGS /bin/sh $PROBE $1 2>&1"; }
pget() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

echo "=== 0 前置 ==="
[ -f "$PROBE_SRC" ] || { bad "探针源不在位：$PROBE_SRC（先从 PC push）"; exit 1; }
if [ -f "$PROBE_DST" ] && cmp -s "$PROBE_SRC" "$PROBE_DST"; then
  note "chroot 内探针已是最新，没重写"
else
  # 不做 chmod：探针一律由 `/bin/sh $PROBE` 调用，执行位根本不参与（runner 那边才需要 0755，
  # 因为 dsh 是直接 exec runnerCommand[0]）。
  cp "$PROBE_SRC" "$PROBE_DST" && note "探针已装入 chroot:/root/dsh-sbx-probe.sh" \
    || { bad "探针装不进 $PROBE_DST"; exit 1; }
fi
inchroot "[ -x $RUNNER ] && echo 有 || echo 无" | grep -q 有 && ok "runner 在位可执行" || { bad "runner 不在位，后面全不用看"; exit 1; }
inchroot "bash -n $RUNNER && echo 语法OK" | grep -q 语法OK && ok "runner bash -n 语法通过" || bad "runner 有语法错"
inchroot "sh -n $PROBE && echo 语法OK" | grep -q 语法OK && ok "探针 sh -n 语法通过" || bad "探针有语法错"
note "宿主 mountinfo 起点 $PH 行"

echo "=== 1 对照组：不围的时候这些靶子必须都写得进（否则第 2 节的挡住不作数） ==="
C=$(inchroot "/bin/sh $PROBE ctl 2>&1")
printf '%s\n' "$C" | sed 's/^/    /'
for k in ETC USR ROOT ROOTDIR; do
  v=$(pget "$C" $k)
  case "$v" in OPEN) ok "$k 靶裸写能进（靶有效）" ;; *) bad "$k 对照组就写不进：这台机那个位置本来就不可写，靶无效（$v）" ;; esac
done
inchroot "mkdir -p /phone/dsh-sbx-probe-dir && echo ctl > /phone/dsh-sbx-probe-dir/w3" >/dev/null 2>&1 \
  && ok "/phone 裸写能进（靶有效）" || bad "/phone 裸写就失败：靶无效"

echo "=== 2 围得住吗（四条都得是 BLOCK，且报的是 read-only，dsh 认这条 denial 签名） ==="
R=$(probe ro)
printf '%s\n' "$R" | sed 's/^/    /'
for k in ETC USR ROOT ROOTDIR; do
  v=$(pget "$R" $k)
  case "$v" in
    BLOCK:*Read-only\ file\ system) ok "$k 写不进，报错原文就是 read-only file system" ;;
    BLOCK:*) ok "$k 写不进（$v）" ;;
    OPEN)    bad "$k 被围住还能写：这是假围堵" ;;
    *)       bad "$k 没读数（探针没跑起来？）：[$v]" ;;
  esac
done
printf '%s\n' "$R" | grep -qi 'read-only file system' \
  && ok "denial 文案命中上游 runnerCommand 签名之一（lib/index.js:216 read-only file system / permission denied）" \
  || bad "denial 文案不在 dsh 认的签名里：它会当成命令失败而不是权限拒绝"

echo "=== 3 工作区还能写吗（挡过头档位等于不可用） ==="
R=$(probe ws); printf '%s\n' "$R" | sed 's/^/    /'
[ "$(pget "$R" WS)" = hi ] && ok "工作区 /phone 可写可读" || bad "工作区写不进（WS=$(pget "$R" WS)）：围过头，档位废了"

echo "=== 4 /dev /proc /tmp 还没坏 ==="
R=$(probe dev); printf '%s\n' "$R" | sed 's/^/    /'
[ "$(pget "$R" DEVNULL)" = OPEN ] && ok "/dev/null 能写" || bad "/dev/null 被打挂（v3 那次整体影子 / 的老毛病）：$(pget "$R" DEVNULL)"
[ "$(pget "$R" PROC)" = OPEN ] && ok "/proc 能用（读得到 /proc/self/stat）" || bad "/proc 被打挂"
R=$(probe tmp); printf '%s\n' "$R" | sed 's/^/    /'
[ "$(pget "$R" TMP)" = OPEN ] && ok "/tmp 可写" || bad "/tmp 不可写（$(pget "$R" TMP)）"
[ "$(pget "$R" TMPFS)" = tmpfs ] && ok "/tmp 是 runner 新挂的 tmpfs（--tmpfs 照做了）" || bad "/tmp 的挂载来源读数是 $(pget "$R" TMPFS)，不是 tmpfs"
inchroot "test -e /tmp/dsh-sbx-probe-c && echo 漏 || echo 没漏" | grep -q 没漏 \
  && ok "ns 里写的 /tmp 文件没漏到外面（tmpfs 只在本次 ns 内）" || bad "ns 内的 /tmp 写漏到宿主了"

echo "=== 5 只读≠读不到；pid namespace 这条按本机事实验 ==="
R=$(probe read); n=$(pget "$R" LS | tr -cd '0-9')
[ "${n:-0}" -gt 50 ] 2>/dev/null && ok "只读下 /usr/bin 还能列（$n 项）" || bad "只读把读也一起废了（LS=$n）"
# 本机 # CONFIG_PID_NS is not set ⇒ --unshare-pid 不可能生效。这里不假验"开了没开"，验两条真约束：
#   (a) 没显式授权时 runner 必须**响亮失败**（不产出任何围堵后的读数），不许静默当成没这条要求；
#   (b) 授权了才降级，并把降级那句打到 stderr。
BARE=$(inchroot "$RUNNER $BWARGS /bin/sh $PROBE pid 2>&1; echo RC=\$?")
printf '%s\n' "$BARE" | sed 's/^/    /'
printf '%s\n' "$BARE" | grep -q '^SELF=' && bad "没授权降级却跑起来了：说明 --unshare-pid 被静默忽略（最坏那种假围堵）" \
  || ok "没授权降级时 runner 拒绝执行（本机无 PID_NS ⇒ 宁可不跑也不静默少围一层）"
printf '%s\n' "$BARE" | grep -q 'RC=0' && bad "拒绝执行却返回 0" || ok "拒绝执行返回非 0"
DGR=$(inchroot "env $NS_ENV $RUNNER $BWARGS true 2>&1")
printf '%s\n' "$DGR" | grep -q 'unshare-pid 没能生效' && ok "授权后打出那句降级提示（写清后果：被围命令可 kill 宿主 pid）" \
  || bad "降级没提示：机主会以为 pid 也围住了"

echo "=== 6 退出码、stdout 干净、报错词表不自己咬自己 ==="
RC=$(inchroot_ns "$RUNNER $BWARGS bash -c 'exit 42'; echo RC=\$?" 2>&1)
printf '%s\n' "$RC" | grep -q 'RC=42' && ok "被围命令的退出码原样传回（42）" || bad "退出码被 runner 吃掉：$RC"
CLEAN=$(inchroot_ns "$RUNNER $BWARGS echo PLAIN 2>/dev/null")
[ "$CLEAN" = PLAIN ] && ok "stdout 干净（降级提示走的是 stderr，不搅工具读数）" || bad "runner 往 stdout 吐了东西：[$CLEAN]"
# 这条是给第 ① 步接线兜底的：配置的 runnerFailureRules 是 { fatalSignatures: [...] }，**没有
# allowedExitCodes 闸门**（lib/index.js:320 vs windows-acl 的 :239-242）。所以签名一旦写成
# "dsh-unshare-run: "，任何一次成功围堵里出现这句话都会被当成 runner 挂了——而每发都要打的降级
# 提示正是最可能撞上的那句。这里按"签名 = dsh-unshare-run: "验：成功围堵的输出里不许出现它。
SIG=FAIL
inchroot_ns "$RUNNER $BWARGS echo ok 2>&1" | grep -q "^dsh-unshare-run: " && SIG=BAD || SIG=GOOD
[ "$SIG" = GOOD ] && ok "成功围堵的输出里不含签名 dsh-unshare-run: （降级提示走 -notice: 这个另起的词）" \
  || bad "致命签名和每发都打的提示撞词了：配上 runnerFailureSignatures 之后每一发都会被判成 runner 失败，档位全废"
inchroot_ns "$RUNNER --frobnicate / -- true 2>&1" | grep -q '^dsh-unshare-run: ' \
  && ok "真出错时确实打的是带签名前缀那句" || bad "真错误没走签名前缀：dsh 侧永远看不到 runner 失败"

echo "=== 7 参数表不全时的行为（宁可报错也不静默少围一层） ==="
inchroot_ns "$RUNNER --frobnicate / -- true; echo RC=\$?" 2>&1 | grep -q 'RC=127' \
  && ok "不认识的参数直接 127 拒绝" || bad "不认识的参数被静默吞了：这是最危险的一种假围堵"
inchroot_ns "$RUNNER --ro-bind / ; echo RC=\$?" 2>&1 | grep -q 'RC=127' \
  && ok "--ro-bind 缺参数时报 127" || bad "缺参数没拦住"
inchroot_ns "$RUNNER --ro-bind / / -- ; echo RC=\$?" 2>&1 | grep -q 'RC=127' \
  && ok "-- 后面没命令时报 127" || bad "-- 后空命令没拦住"

echo "=== 8 收拾 + 复验没把外面带崩 ==="
inchroot "rm -f /etc/dsh-sbx-probe-a /etc/dsh-sbx-probe-b /usr/dsh-sbx-probe-a /usr/dsh-sbx-probe-b /root/dsh-sbx-probe-a /root/dsh-sbx-probe-b /dsh-sbx-probe-a /dsh-sbx-probe-b; rm -rf /phone/dsh-sbx-probe-dir; true"
LEFT=$(inchroot "for f in /etc/dsh-sbx-probe-a /usr/dsh-sbx-probe-a /root/dsh-sbx-probe-a /dsh-sbx-probe-a /tmp/dsh-sbx-probe-c; do test -e \$f && echo 残留:\$f; done; ls -d /phone/dsh-sbx-probe-dir 2>/dev/null; true")
printf '%s\n' "$LEFT" | grep -q '残留\|dsh-sbx-probe-dir' && { printf '%s\n' "$LEFT" | sed 's/^/    /'; bad "有探针文件残留"; } \
  || ok "探针文件清干净了（宿主侧与 chroot 侧都复验过）"
PH2=$(wc -l < /proc/self/mountinfo)
[ "$PH" = "$PH2" ] && ok "宿主 mountinfo 行数回到 $PH2（没往外面漏挂载）" || bad "宿主挂载表被改动：$PH -> $PH2"
inchroot "echo ctl2 > /etc/dsh-sbx-probe-z 2>&1 && rm -f /etc/dsh-sbx-probe-z && echo 外面还是可写的" | grep -q '外面还是可写的' \
  && ok "ns 外 /etc 照样可写（只读没泄漏到全局）" || bad "全局被冻了：这会连带把 dsh 自己也写不了盘"
inchroot "test -e /dev/null && echo 在 || echo 没了" | grep -q '在' && ok "/dev/null 设备节点还在（探针绝不 rm 它）" || bad "/dev/null 被删了"
echo "=== 总计 PASS=$PASS FAIL=$FAIL ==="
