#!/bin/bash
# dsh-unshare-run — bwrap 方言的只读 runner，用 mount namespace 实现，不吃 user namespace
#
# 为什么需要它（2026-10-20 三条实测）：
#   # CONFIG_USER_NS is not set          ⇒ bwrap 建不出命名空间（实测 bwrap: Creating new namespace failed）
#   # CONFIG_SECURITY_LANDLOCK is not set ⇒ landlock 那条也死
#   CONFIG_NAMESPACES=y                 ⇒ 但 mount namespace 是开的；root 直接 unshare -m 就行（实测 exit=0）
# 上游 0.2.1-rc.2 的 PLATFORM_CHAINS 里没有 android 这一档，但 dsh 给运维留了官方口子（不用改一行源码）：
#   @deepseek-ai/dsh-sandbox-local/lib/index.js:311-321  confine()
#     if (this.runnerCommand !== void 0) return { argv: [...this.runnerCommand, ...bwrapProfileArgs(policy), "--", ...argv], enforcement: "full", ... }
#   同文件 :22-39  bwrapProfileArgs() 打出来的参数就是：
#     --ro-bind / /  --dev /dev  --unshare-pid  --proc /proc  --die-with-parent
#     [workspace-write 时] --tmpfs /tmp  --bind <workspaceRoot> <workspaceRoot>
#     --  <真正的命令>
# 所以只要把这个脚本伪装成 bwrap 挂进 dsh 的 runnerCommand 即可（见 config/sandbox-runner-cordis-snippet.yml）。
#
# 物理前提（不在这里做，做不到）：chroot 里 `unshare -m` 会报
#   cannot change root filesystem propagation: Invalid argument
# 真因是 $ROOTFS 自己不是一个挂载点；dsh-chroot.sh 的 mount_fs 里那句
#   mount --rbind $ROOTFS $ROOTFS
# 就是为这一步准备的（必须是 --rbind：非递归的 --bind 会把新 chroot 的 /proc 影子成空的）。
# 前提不在位时本脚本会明确报错，不静默降级成"没围"。
#
# 报错口径（2026-10-20 查到的一条硬约束，别改）：dsh 把 runnerFailureSignatures 装配成
#   { fatalSignatures: [...] }   —— 见 lib/index.js:320，**没有 allowedExitCodes**
# 而内置 windows-acl 那条是 { allowedExitCodes: [127], fatalSignatures: ["windows-acl-run: "] }（:239-242），
# 上游注释明说"用退出码兜住，免得一条只是**打印**了签名的命令被误判成 runner 挂了"。
# 我们这档没有退出码闸门 ⇒ 签名匹配的是"输出里出现过这句话"。所以词表必须分两家：
#   dsh-unshare-run:      只给致命错误（同时 exit 127）——这是要喂给 runnerFailureSignatures 的签名
#   dsh-unshare-run-notice:  只给不影响本次执行的降级提示，每发都会打，绝不能撞上签名
# 否则配好 runnerCommand 之后，每一次围堵都会被当成"runner 失败"，档位等于全废。
#
# 和 bwrap 不等价的四处，全写在明面上：
#   1. 根目录只读的做法是"把 / 下顶层目录逐个 bind 成只读"，不是 `mount --bind / /` 一把整体 remount。
#      后者实测会把 /dev 一起影子掉，被围命令连 /dev/null 都开不开（probe-ns-sandbox.sh v3/v4 读数）。
#   2. --die-with-parent 做不到（那要 PR_SET_PDEATHSIG，中间隔着 unshare 和 bash）。收下并忽略，
#      后果：被围命令留下的后台进程不会随父进程退出而死。
#   3. dev/proc/run/sys 这些本来就是独立挂载点的，保持原样不重挂，所以 --dev/--proc 只认不仿。
#   4. --unshare-pid 在这台内核做不到（# CONFIG_PID_NS is not set），要机主显式授权才降级，见下面 UA 那段。
set -u

RO_BINDS=()
RW_BINDS=()
TMPFSES=()
DEV_PATHS=()
PROC_PATHS=()
UNSHARE_PID=0

die() { echo "dsh-unshare-run: $*" >&2; exit 127; }

while [ $# -gt 0 ]; do
  case "$1" in
    --ro-bind) [ $# -ge 3 ] || die "--ro-bind 缺参数"; RO_BINDS+=("$2	$3"); shift 3 ;;
    --bind)    [ $# -ge 3 ] || die "--bind 缺参数";    RW_BINDS+=("$2	$3"); shift 3 ;;
    --tmpfs)   [ $# -ge 2 ] || die "--tmpfs 缺参数";   TMPFSES+=("$2"); shift 2 ;;
    --dev)     [ $# -ge 2 ] || die "--dev 缺参数";     DEV_PATHS+=("$2"); shift 2 ;;
    --proc)    [ $# -ge 2 ] || die "--proc 缺参数";    PROC_PATHS+=("$2"); shift 2 ;;
    --unshare-pid) UNSHARE_PID=1; shift ;;
    --die-with-parent) shift ;;
    --) shift; break ;;
    *) die "不认识的参数 $1（拒绝继续，免得静默少围一层）" ;;
  esac
done
[ $# -gt 0 ] || die "-- 后面没有命令"

# --ro-bind 收下但不重放（第一步的"全量冻"本来就覆盖了它）。留一个自检的唯一理由：
# 上游 bwrapProfileArgs() 现在只发一条 `--ro-bind / /`，我们这套逐目录冻的形状是照它写的。
# 哪天它变成多条或别的样子（比如 --ro-bind /usr /new-usr），逐目录冻就不再等价 —— 宁可响亮拒绝，
# 也不静默按一个对不上号的方言去"围"。
for e in "${RO_BINDS[@]}"; do
  IFS=$'\t' read -r rosrc rodst <<<"$e"
  { [ "$rosrc" = "/" ] && [ "$rodst" = "/" ]; } \
    || die "--ro-bind 的形状和写死的前提不一致（收到 $rosrc -> $rodst，本实现只认 / -> /）"
done

# 只查一样硬前提：unshare 在不在。传播策略那道坎（no rootfs 自 rbind 时
# cannot change root filesystem propagation）由下面 ns 内第一句 mount --make-rprivate 兜，
# 失败就 127 走人，不会静默降级成"没围"。
# 这里刻意不拿 /proc/self/mountinfo 当前提：chroot 里那份 procfs 受 Android 的
# hidepid=invisible 影响，读数时有时无（本轮就被它骗过一次"文件不存在"），
# 拿一个不可靠的读数去判生死，等于给自己造一个假失败。
command -v unshare >/dev/null || die "chroot 里没有 unshare（util-linux）"

SCRIPT="set -u
mount --make-rprivate / || { echo 'dsh-unshare-run: make-rprivate 失败' >&2; exit 127; }
"
# ── 第一步：/ 下顶层目录**全部**冻成只读 ────────────────────────────────
# 跳过 dev|proc|sys|run|tmp 这五个名字：它们本来就是独立挂载点，冻了会把 /dev/null、/proc
# 一起打死（v3 那次实测就是 `cannot create /dev/null: Read-only file system`）。
# 其余的——包括 /phone 这种"也是挂载点"的——一律先冻住，谁要可写第二步再明确叠回来。
# 早先这里有一句 grep /proc/self/mountinfo && continue（"是挂载点就跳过"），实测后果是
# read-only 档下 /phone 直接漏出去（没人 --bind 它，就没人把它挂回可写），所以改成
# "先全冻、后点名"。
SCRIPT+='
for d in /*/; do
  d=${d%/}
  case "${d##*/}" in dev|proc|sys|run|tmp) continue ;; esac
  mount --bind "$d" "$d" && mount -o remount,bind,ro "$d" || { echo "dsh-unshare-run: 只读围不住 $d" >&2; exit 127; }
done
'
# ── 第二步：把调用方点名要可写的东西叠在只读层之上 ──────────────────────
# 顺序是硬要求，不能倒过来。2026-10-20 实测过反面：先叠工作区、最后再 `mount --bind / /`
# 把整棵 / 影子一遍，先前叠的挂载全被盖掉，/phone 变成"只读的空目录"，
# workspace-write 档位直接废掉（连 mkdir 都失败）。
for e in "${RW_BINDS[@]}"; do
  IFS=$'	' read -r src dst <<<"$e"
  SCRIPT+="mkdir -p $(printf '%q' "$dst")
mount --bind $(printf '%q' "$src") $(printf '%q' "$dst") && mount -o remount,bind,rw $(printf '%q' "$dst") || { echo 'dsh-unshare-run: 工作区没能挂成可写' >&2; exit 127; }
"
done
for e in "${TMPFSES[@]}"; do
  q=$(printf '%q' "$e")
  SCRIPT+="mkdir -p $q
mount -t tmpfs tmpfs $q || { echo 'dsh-unshare-run: tmpfs 挂不上' >&2; exit 127; }
"
done
# ── 第三步：/ 根自己 ────────────────────────────────────────────────────
# 只能试不改视图的 remount。实测 `mount -o remount,ro /` 在这台的 ns 里报 mount point is busy；
# 失败不致命（顶层目录已经全冻住），但缺口要说实话：被围的命令还能在 / 根上**新建一个顶层条目**。
# 另外 / 根上的点开头条目（/.cache 这种）第一步的 /*/ glob 根本匹配不到，只有这一发能盖住它们
# ——所以这句 remount 真挂了就等于把那条缺口一起堵上了，挂不上时报的是 notice，不装成成功。
SCRIPT+='
mount -o remount,bind,ro / 2>/dev/null || echo "dsh-unshare-run-notice: / 自身没能冻住（已知缺口：可在 / 根上新建顶层文件；所有顶层目录本身已只读）" >&2
'
SCRIPT+='exec "$@"'

UA=(-m)
if [ "$UNSHARE_PID" = "1" ]; then
  # 这台内核 # CONFIG_PID_NS is not set（zcat /proc/config.gz 实测），unshare -p -f 直接
  # 报 Invalid argument（实测读数）。没有 pid namespace 的代价很具体：被围命令能看见宿主所有 pid，
  # 而且它和 dsh 同为 uid 0，所以能 kill 掉 dsh 服务进程自己。这不影响"只读围得住"这件事，
  # 但绝不能由我们替机主默认吞掉 —— 所以默认**带 -p -f 起、起不来就 1 退出**（ Loud 失败 ），
  # 只有显式设了 DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=1 才降级到"只围文件系统"。
  if [ "${DSH_UNSHARE_RUN_ALLOW_NO_PIDNS:-0}" = "1" ]; then
    echo "dsh-unshare-run-notice: --unshare-pid 没能生效（本机 # CONFIG_PID_NS is not set）。后果：被围命令可看见并可 kill 宿主 pid（含 dsh 自己）。只读围堵不受影响，这条是显式接受的降级。" >&2
  else
    UA+=(-p -f)
  fi
fi

# 脚本走 argv 传进 ns，不依赖 ns 里任何路径还存在（/tmp 已经被我们换成新 tmpfs 了）。
exec unshare "${UA[@]}" bash -c "$SCRIPT" dsh-unshare-run "$@"
