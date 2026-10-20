#!/system/bin/sh
# dsh-chroot.sh — 在已 root 的 Android 上进入/拉起 Ubuntu chroot 里的 DeepSeek Harness
# 实测机型：一加 13(PJZ110) / Android 15 / KernelSU / SELinux Enforcing（2026-10-19）
#
# 用法（都要在 root shell 里跑：先 su，或 adb shell su -c）：
#   sh /data/local/sh/dsh-chroot.sh              进入 chroot 交互 shell
#   sh /data/local/sh/dsh-chroot.sh --web        后台拉起 dsh web（127.0.0.1:3080，裸跑，要自己贴 token）
#   sh /data/local/sh/dsh-chroot.sh --entry      起入口守护（:3081）并由它拉引擎 —— App 点开就能用走这条
#   sh /data/local/sh/dsh-chroot.sh --entry-stop 停入口（连它拉的引擎一起停）
#   sh /data/local/sh/dsh-chroot.sh --status     看挂载/SELinux/端口/HTTP/入口/引擎 六样读数
#   sh /data/local/sh/dsh-chroot.sh --url        打日志里那条带 token 的入场 URL（只有 --web 那条路有）
#   sh /data/local/sh/dsh-chroot.sh --run '<命令>'  在 chroot 里跑一条命令就出来
#   sh /data/local/sh/dsh-chroot.sh --stop       停服务（照 pidfile 杀）
#   sh /data/local/sh/dsh-chroot.sh --umount     卸载挂载点（含手机存储），按需复原 SELinux
#
# 网页端"工作区"到底是什么（2026-10-20 查清）：dsh 的 sandbox-policy 配置写的是
#   workspaceRoot: !!js process.cwd()      （见 reference/dsh-web-default-config.txt:137）
# 也就是服务进程开在哪，工作区就是哪。以前服务从 chroot 的 / 起步，那里只有 Ubuntu 自己的目录，
# 手机上真实的照片/下载根本不在那棵树上 —— 这就是"工作区读不到手机"的成因。
# 现在 mount_fs 把 /data/media/0 bind 到 chroot 的 /phone，--web 拉起前先 cd /phone。
# 不想让 Agent 碰到整个存储：DSH_WORKDIR=/phone/Download sh ... --web，或 DSH_NO_PHONE=1 完全不挂。
#
# 四条实测踩过的坑，脚本里已经改掉：
#   1. TMPDIR 必须显式给 /tmp。adb 的 shell 环境带着 TMPDIR=/data/local/tmp，继承进 chroot
#      后那个路径不存在，ca-certificates 的 postinst 会挂在 mktemp 上。
#   2. 判断"在不在跑"不能拿 pgrep 去匹配 dsh 的 cmdline——包住它的那层 bash -c 自身就带着
#      这个字符串，pgrep 永远匹配到自己，实测就是这句假阳性。改成看端口 + pidfile。
#   3. SELinux 不用关。KernelSU 的 su 域(u:r:su:s0)在 Enforcing 下就能 rbind、chroot、
#      执行 /data 里的 node。要关就显式 DSH_SETENFORCE0=1。
#   4. 端口在听 ≠ 页面能打开。dsh web 强制鉴权，裸 http://127.0.0.1:3080 实测恒 401，
#      能用的入场券是它自己在 /data/local/dsh.log 里打的那条 ?token= URL（实测可反复用，
#      浏览器打开一次拿到 cookie 后裸地址也通，cookie 有效期到盘上的 expiresAt）。

ROOTFS=/data/local/dsh-rootfs
LOG=/data/local/dsh.log
PIDFILE=$ROOTFS/root/dsh.pid
SELPATH=/data/local/.dsh-selinux-backup
ENV_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PORT=3080
# 工作区：手机内部存储的真身是 /data/media/0（不是 /sdcard——那是给 App 的 FUSE 视图，chroot 里拿不到）。
# 2026-10-20 实测：把它 bind 进 chroot 的 /phone，root 能读能写（touch 成功，落盘 root:1023 + ACL，
# SELinux 域 u:r:su:s0，Enforcing 没动）。dsh 的 sandbox-policy 里 workspaceRoot = process.cwd()，
# 所以拉起服务前 cd 到哪，网页端"工作区"就是哪。DSH_NO_PHONE=1 可以不放这块存储进来。
PHONE_SRC=/data/media/0
PHONE_DST=$ROOTFS/phone
WORKDIR=${DSH_WORKDIR:-/phone}

# 入口守护（scripts/dsh-entry.js）：把"起引擎 + 认那条启动行 + 换 30 天 cookie"收在 root 侧，
# 让手机上的 WebView 壳能用一个写死的地址点开就能用。设计依据与三家先例见 RUNBOOK 14.13/14.14。
ENTRY_JS=$ROOTFS/usr/local/bin/dsh-entry.js          # 装到 chroot 里（宿主 push 到这里）
ENTRY_HOME=$ROOTFS/root/.dsh                          # 0700：口令、自测日志都只 root 看得到
ENTRY_KEY=$ENTRY_HOME/entry.key                       # 0600，同一个值烤进 App
ENTRY_COMPAT=$ENTRY_HOME/entry-compat.js              #  serve 时内联进 HTML 的 polyfill
ENTRY_OUT=$ENTRY_HOME/entry.out                       #  node 崩溃栈落这里（日志它自己写 entry.log）
ENTRY_PIDFILE=$ENTRY_HOME/entry.pid
ENTRY_PORT=${DSH_ENTRY_PORT:-3081}
UP_PORT=${DSH_UP_PORT:-$PORT}

die() { echo "!! $*" >&2; exit 1; }
need_root() { [ "$(id -u)" = "0" ] || die "需要 root：先 su 再执行本脚本"; }
[ -x "$ROOTFS/bin/sh" ] || die "rootfs 不在位：$ROOTFS"

# AOSP 很多机型不带 /system/bin/chroot；setsid 同理。按顺序找退路。
if command -v chroot >/dev/null 2>&1; then CHROOT=chroot
elif [ -x /data/local/sh/busybox ]; then CHROOT="/data/local/sh/busybox chroot"
elif command -v busybox >/dev/null 2>&1; then CHROOT="busybox chroot"
else CHROOT=""; fi
if command -v setsid >/dev/null 2>&1; then DAEMON=setsid; else DAEMON=nohup; fi
have_chroot() { [ -n "$CHROOT" ] || die "找不到 chroot：Termux 里 pkg install busybox，再 cp \$PREFIX/bin/busybox /data/local/sh/busybox && chmod 0755 /data/local/sh/busybox"; }

mount_fs() {
  # 把 rootfs 自己 bind 成一个挂载点。这一步是给沙箱 runner 铺路的，不影响别的任何东西：
  # 实测 chroot 里 `unshare -m` 会报 `cannot change root filesystem propagation: Invalid argument`，
  # 唯一成因就是 $ROOTFS 不是挂载点；bind 自己一次之后同一句 unshare -m 返回 exit=0（2026-10-20 读数）。
  # 不做这一步，scripts/dsh-unshare-run.sh（workspace-write 的真围堵 runner）在这台机器上永远起不来。
  # 幂等：已经是挂载点就跳过（靠 mountinfo 判，不靠 findmnt——chroot 里 findmnt 读数不可信，实测过）。
  if ! grep -q " $ROOTFS " /proc/self/mountinfo; then
    # 必须 --rbind（递归），不能 --bind。2026-10-20 实测栽过一次：非递归的 `mount --bind $ROOTFS $ROOTFS`
    # 只搬 rootfs 自己那层目录，$ROOTFS/proc、/dev、/sys 这些子挂载不会跟着进来，于是之后每一个新
    # chroot 进去都看到一个**空的 /proc**（`ls /proc` 无输出、/proc/self/mountinfo 直接 No such file），
    # 而已经跑着的服务毫无影响（它拿的是旧视图）——所以坏得很安静，只有下一次拉起才发现。
    # 换成 --rbind 后：chroot 内 /proc 恢复（能列出 pid），且 unshare -m 仍然 exit=0（前提没丢）。
    mount --rbind "$ROOTFS" "$ROOTFS" \
      && echo "[ok] rootfs 自 rbind（为 chroot 内 unshare -m 铺路，且带上 /proc /dev /sys 子挂载）" \
      || echo "!! rootfs 自 rbind 失败：workspace-write 的沙箱 runner 起不来，档位只能退回 danger-full-access"
  else
    echo "[ok] rootfs 已是挂载点，自 bind 跳过"
  fi
  for p in proc sys dev; do
    grep -q " $ROOTFS/$p " /proc/mounts || {
      mount --rbind "/$p" "$ROOTFS/$p" || die "--rbind /$p 失败"
    }
  done
  mkdir -p "$ROOTFS/dev/shm" "$ROOTFS/run" "$ROOTFS/tmp"
  chmod 1777 "$ROOTFS/tmp"
  grep -q " $ROOTFS/dev/shm " /proc/mounts || mount -t tmpfs shm "$ROOTFS/dev/shm"
  grep -q " $ROOTFS/run " /proc/mounts || mount -t tmpfs run "$ROOTFS/run"

  # 实测本机 53 端口(UDP+TCP)出站被拦，resolv.conf 单独不足以解析；真正生效的是 /etc/hosts
  # 里按 DoH 结果钉的 IP（tools/pin-hosts.py）。这份 resolv.conf 留着，等哪天 53 通了自动可用。
  [ -f "$ROOTFS/etc/resolv.conf" ] || cat > "$ROOTFS/etc/resolv.conf" <<'EOF'
nameserver 223.5.5.5
nameserver 119.29.29.29
options timeout:3 attempts:2
EOF
  # 把手机存储放进 chroot，网页端的工作区才"读得到手机"（见上面 PHONE_* 那三行的实测）
  if [ "${DSH_NO_PHONE:-0}" = "1" ]; then
    echo "[skip] DSH_NO_PHONE=1，没挂手机存储"
  else
    mkdir -p "$PHONE_DST"
    if grep -q " $PHONE_DST " /proc/mounts; then
      echo "[ok] /phone 已挂（$(ls "$PHONE_DST" 2>/dev/null | wc -l) 个顶层条目）"
    else
      mount --bind "$PHONE_SRC" "$PHONE_DST" \
        && echo "[ok] 手机存储 $PHONE_SRC -> chroot /phone" \
        || echo "!! bind $PHONE_SRC 失败：工作区退回 chroot 自己的目录"
    fi
  fi
}

# 给网页端的「选择工作区目录」在家目录里放一个看得见的入口（2026-10-20 照 DSHA 补）。
# 为什么需要它：dsh 的目录选择器不带 path 时列的就是引擎进程的 HOME（这里 = /root），
# 实测那一发返回 entries 只有 .dsh 与 .npm 两条、且都标着 hidden:true
# （读数：POST /api/directoryPicker/list {"args":{}} → {"path":"/root","home":"/root",
#   "entries":[{"name":".dsh","hidden":true},{"name":".npm","hidden":true}]}）
# ⇒ 手机上那一屏就是"空的"，不是接口挂了。他的真实文件夹在 /phone（bind 自 /data/media/0），
#   从 / 出发是点得到的（path=/ 那条读数里 phone 是 hidden:false），只是从 /root 出发一步都走不动。
# 为什么是软链而不是真目录/bind：先例是这么做的（DSHA RuntimeExecution.java:102-108 在每次
#   ensurePatches 时往 rootfs 的 /root 建一条名为「手机存储」的软链指向 /sdcard，失败只记
#   OPTIONAL_STORAGE_LINK_UNAVAILABLE 不阻断启动），而"软链目录能不能被选择器当成目录进去"
#   我们在自己这台机上验过了：path=/lib（/lib 是 usr/lib 的软链）正常列出 aarch64-linux-gnu、
#   apt、dpkg… ⇒ 跟。所以一条软链就够，不用动挂载表，删起来就是一个 rm 那条链。
# 这条不新增任何权限：引擎的工作区本来就是 /phone（见上面 PHONE_* 那三行与 RUNBOOK），
#   软链只改变"界面上点得到点不到"。不想放就别挂 /phone（DSH_NO_PHONE=1），下面自动跳过。
home_entry_ensure() {
  [ "${DSH_NO_PHONE:-0}" = "1" ] && { echo "[skip] DSH_NO_PHONE=1，家目录里不放存储入口"; return 0; }
  LINK=$ROOTFS/root/手机存储
  if [ -e "$LINK" ] || [ -L "$LINK" ]; then
    echo "[ok] 家目录入口在位：/root/手机存储 -> $(readlink "$LINK" 2>/dev/null || echo '（不是软链，是个真目录/文件，没动它）')"
    return 0
  fi
  if ln -s /phone "$LINK" 2>/dev/null; then
    echo "[ok] 已建 /root/手机存储 -> /phone（网页端选择器从这里点进手机存储）"
  else
    echo "!! 建 /root/手机存储 失败（可选：不影响服务起来，只是那一屏还是空的）"
  fi
}

permissive() {

  [ "${DSH_SETENFORCE0:-0}" = "1" ] || { echo "[ok] SELinux 保持 $(getenforce)（Enforcing 实测可用）"; return 0; }
  [ -f "$SELPATH" ] || getenforce > "$SELPATH" 2>/dev/null
  if [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
    setenforce 0 && echo "[ok] SELinux: Enforcing -> Permissive（--umount 复原）"
  else
    echo "[ok] SELinux 当前: $(getenforce)"
  fi
}

# 注意 TMPDIR=/tmp，别把 Android 那份带进来
in_chroot() { $CHROOT "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp TERM="${TERM:-xterm-256color}" PATH="$ENV_PATH" /bin/bash -lc "$1"; }

# 拉服务前先确认工作区目录真读得到（读不到就直说，别让网页端空转）
chroot_ls_workdir() {
  $CHROOT "$ROOTFS" /usr/bin/env PATH="$ENV_PATH" /bin/sh -c "ls -d $WORKDIR >/dev/null 2>&1 && ls $WORKDIR 2>/dev/null | wc -l || echo 读不到" 2>/dev/null
}

port_up() { ss -lnt 2>/dev/null | grep -q ":$PORT"; }
pid_alive() { [ -f "$PIDFILE" ] && [ -d "/proc/$(cat "$PIDFILE" 2>/dev/null)" ]; }
entry_up() { ss -lnt 2>/dev/null | grep -q ":$ENTRY_PORT"; }
entry_pid_alive() { [ -f "$ENTRY_PIDFILE" ] && [ -d "/proc/$(cat "$ENTRY_PIDFILE" 2>/dev/null)" ]; }

# 入口口令：造一次，落 0600，全程不打印值。生成器和 dsh 自己的 token 同源（32 随机字节 → base64url 43 位），
# 这样它对得上 DSHA 那条判据的形状，也不用我们另发明一套字符集。
entry_key_ensure() {
  mkdir -p "$ENTRY_HOME" && chmod 700 "$ENTRY_HOME" || die "建 $ENTRY_HOME 失败"
  if [ -s "$ENTRY_KEY" ]; then
    echo "[ok] 入口口令已在位：$ENTRY_KEY（$(wc -c <"$ENTRY_KEY") B，值不打印）"
    return 0
  fi
  $CHROOT "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH="$ENV_PATH" node -e \
    'process.stdout.write(require("crypto").randomBytes(32).toString("base64url")+"\n")' > "$ENTRY_KEY" \
    || die "造口令失败"
  chmod 600 "$ENTRY_KEY"
  [ -s "$ENTRY_KEY" ] || die "造出来的口令是空的（不退回空口令：那是敞开给本机所有 App）"
  echo "[ok] 造了入口口令 $(wc -c <"$ENTRY_KEY") B -> $ENTRY_KEY（值不打印；烤进 App 要跑 tools/deploy-entry.sh --pull-key）"
}

# 入口的自述：走它自己的 --status（同一个口令、同一个来源），不带 token、不打印凭据
entry_status() {
  $CHROOT "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH="$ENV_PATH" \
    DSH_ENTRY_KEY_FILE=/root/.dsh/entry.key DSH_ENTRY_PORT="$ENTRY_PORT" DSH_UP_PORT="$UP_PORT" \
    node /usr/local/bin/dsh-entry.js --status 2>&1
}

# 服务的真实工作区 = dsh 的 workspaceRoot（sandbox-policy 里写的是 process.cwd()），直接读它的 /proc/<pid>/cwd
cwd_of_pid() {
  P=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$P" ] && [ -d "/proc/$P" ]; then
    echo "(宿主视角)$(readlink "/proc/$P/cwd" 2>/dev/null) -> (chroot 视角)$(readlink "/proc/$P/cwd" 2>/dev/null | sed "s|^$ROOTFS||;s|^$|/|")"
  else
    echo "无在跑的服务"
  fi
}

# dsh web 的入场券：它自己在日志里打的那条带 token 的 URL（服务不停时同一个 token 可反复用）
# 这份 cookie jar 只给自检用，验完就删；名字和 dsh-restart-check.sh 那份隔开，免得互相抹证据
CJ=/data/local/tmp/dsh_status_cj
token_url() {
  T=$(grep -o 'token=[A-Za-z0-9_-]*' "$LOG" 2>/dev/null | tail -1)
  [ -n "$T" ] && echo "http://127.0.0.1:$PORT/?$T"
}

status() {
  echo "--- 挂载 ---"; grep " $ROOTFS/" /proc/mounts | awk '{print "  "$2}' || echo "  无挂载"
  echo "--- 工作区 ---"; echo "  chroot 内 $WORKDIR，顶层条目 $(chroot_ls_workdir) 个；服务实际 cwd=$(cwd_of_pid)"
  echo "--- SELinux ---"; getenforce
  echo "--- 监听 ---"; port_up && echo "  :$PORT LISTEN" || echo "  不监听"
  echo "--- pidfile ---"; pid_alive && echo "  $(cat "$PIDFILE") 活着" || echo "  无活进程"
  echo "--- HTTP ---"
  # 实测：裸 / 永远 401（dsh web 强制鉴权，这不是故障），要拿日志里那条 ?token= 的 URL
  # 走一遍 303→cookie 才是真页面。所以这里两行都打，认第二行。
  echo "  裸 /(预期401): $(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://127.0.0.1:$PORT/" 2>/dev/null || echo 连不上)"
  TOK=$(token_url)
  if [ -n "$TOK" ]; then
    rm -f "$CJ"
    echo "  带token走完: $(curl -sSL -c "$CJ" -b "$CJ" -o /dev/null -w 'http=%{http_code} bytes=%{size_download}' --max-time 15 "$TOK" 2>/dev/null || echo 连不上)"
    rm -f "$CJ"
  else
    echo "  带token走完: 日志里没有 token（$LOG）"
  fi
  echo "--- 入口(:$ENTRY_PORT) ---"
  if entry_up; then
    echo "  LISTEN  pid=$(cat "$ENTRY_PIDFILE" 2>/dev/null || echo 未知)"
    entry_status 2>&1 | sed 's/^/  /'
  else
    echo "  不监听 ⇒ 手机上的 App 会停在「连不上工作台」那一屏；起它：sh $0 --entry"
  fi
  echo "--- dsh ---"; in_chroot "command -v dsh && dsh --version" 2>/dev/null || echo "  chroot 里查不到 dsh"
}

case "${1:-}" in
  --web)
    need_root; have_chroot; permissive; mount_fs; home_entry_ensure
    port_up && { echo "[skip] :$PORT 已在听，pid=$(cat "$PIDFILE" 2>/dev/null || echo 未知)"; U=$(token_url); [ -n "$U" ] && echo "        $U"; exit 0; }
    pid_alive && { echo "[警告] pidfile 有活进程但端口没听，先 --stop"; exit 1; }
    in_chroot "command -v dsh >/dev/null" || die "chroot 里没装 dsh"
    echo "[..] 后台拉起 dsh web，日志 $LOG"
    echo "     工作区(chroot 视角) = $WORKDIR  实测可读条目 $(chroot_ls_workdir)"
    # chroot→bash→exec dsh 是一条 exec 链，最外层 pid 就是 node 本身，可以直接记 pidfile
    # /root/.dsh-env 是放密钥的地方（chmod 600）。实测 dsh 包里的默认值就是读这个环境变量：
    #   @deepseek-ai/dsh-llm-deepseek-api-key/lib/index.js:9  apiKeyEnv 默认 "DEEPSEEK_API_KEY"
    # 端点 https://api.deepseek.com（从包内 *.js 扫出来的），所以那文件里一行就够：
    #   export DEEPSEEK_API_KEY=...
    $DAEMON sh -c "$CHROOT $ROOTFS /usr/bin/env HOME=/root TMPDIR=/tmp PATH=$ENV_PATH /bin/bash -lc '. /root/.dsh-env >/dev/null 2>&1; cd $WORKDIR 2>/dev/null || cd /root; exec dsh web' >> $LOG 2>&1 < /dev/null & echo \$! > $PIDFILE" \
      || die "$DAEMON 启动失败"
    i=0
    while [ $i -lt 30 ]; do
      if port_up; then
        echo "[ok] :$PORT 已监听  pid=$(cat "$PIDFILE")"
        sleep 1
        U=$(token_url)
        if [ -n "$U" ]; then
          C=$(curl -sSL -c "$CJ" -b "$CJ" -o /dev/null -w '%{http_code}' --max-time 15 "$U" 2>/dev/null)
          rm -f "$CJ"
          echo "[ok] 页面实测 HTTP=$C"
          echo "     手机浏览器打开这条（带 token，实测可反复用）："
          echo "     $U"
          echo "     打开一次后浏览器会拿到 cookie，之后收藏裸地址也行；裸地址单独打开是 401。"
        else
          echo "!! 端口在听但日志里没有 token URL，看 $LOG"
        fi
        exit 0
      fi
      i=$((i+1)); sleep 2
    done
    echo "!! 60 秒内没监听，日志尾巴："; tail -30 "$LOG"
    exit 1
    ;;
  --entry)
    need_root; have_chroot; permissive; mount_fs; home_entry_ensure
    [ -f "$ENTRY_JS" ] || die "入口脚本不在位：$ENTRY_JS（先从 Windows 跑 sh tools/deploy-entry.sh）"
    in_chroot "command -v node >/dev/null" || die "chroot 里没有 node，入口跑不起来"
    entry_key_ensure
    if entry_up; then
      echo "[skip] :$ENTRY_PORT 已在听，pid=$(cat "$ENTRY_PIDFILE" 2>/dev/null || echo 未知)"
      entry_status | sed 's/^/        /'
      exit 0
    fi
    # 引擎由入口自己拉，所以 :$PORT 上如果已经有一个 --web 起的裸引擎，得先停掉：
    # 不然入口那一次 spawn 会绑不上 3080 而退避重拉，症状是 App 停在"入口活着，引擎没接上"那一屏。
    if port_up; then
      echo "[..] :$PORT 上有 --web 起的裸引擎，先停（引擎的爹改成入口，一个来源一条启动行）"
      sh "$0" --stop >/dev/null 2>&1
      i=0; while port_up && [ $i -lt 10 ]; do i=$((i+1)); sleep 1; done
    fi
    echo "[..] 起入口（node，只绑 127.0.0.1:$ENTRY_PORT），它再拉引擎 :$UP_PORT"
    $DAEMON sh -c "$CHROOT $ROOTFS /usr/bin/env HOME=/root TMPDIR=/tmp PATH=$ENV_PATH DSH_ENTRY_KEY_FILE=/root/.dsh/entry.key DSH_ENTRY_PORT=$ENTRY_PORT DSH_UP_PORT=$UP_PORT node /usr/local/bin/dsh-entry.js --start >> $ENTRY_OUT 2>&1 < /dev/null &" \
      || die "$DAEMON 启动失败"
    i=0
    while [ $i -lt 20 ]; do
      entry_up && break
      i=$((i+1)); sleep 1
    done
    entry_up || { echo "!! 20 秒内 :$ENTRY_PORT 没听，$ENTRY_OUT 尾巴："; tail -20 "$ENTRY_OUT"; exit 1; }
    echo "[ok] 入口在听 :$ENTRY_PORT  pid=$(cat "$ENTRY_PIDFILE" 2>/dev/null || echo 未知)"
    # 等它从引擎那条启动行里认到端口（引擎冷启在真机上实测要 3~8 秒）
    i=0
    while [ $i -lt 25 ]; do
      entry_status 2>/dev/null | grep -Eq "^upstream[[:space:]]+http" && break
      i=$((i+1)); sleep 1
    done
    echo "--- 入口自述 ---"; entry_status | sed 's/^/  /'
    echo
    echo "手机上的 App「DSH」直接点开就用，地址是写死的 http://127.0.0.1:$ENTRY_PORT/"
    echo "（这一屏不打印 token：入口已经把它换成 30 天的 dsh-auth cookie 了）"
    ;;
  --entry-stop)
    need_root
    if ! entry_pid_alive; then
      echo "[no-op] 入口没在跑（pidfile 无活进程）"
      in_chroot "node /usr/local/bin/dsh-entry.js --stop" >/dev/null 2>&1   # 顺手把哨兵写了，防重拉
      exit 0
    fi
    in_chroot "node /usr/local/bin/dsh-entry.js --stop" && echo "[ok] 已让入口自己停（写哨兵 + SIGTERM 自己与引擎）"
    i=0; while entry_pid_alive && [ $i -lt 10 ]; do i=$((i+1)); sleep 1; done
    entry_pid_alive && { kill -9 "$(cat "$ENTRY_PIDFILE")" 2>/dev/null; echo "[ok] 兜底 SIGKILL 入口"; }
    rm -f "$ENTRY_PIDFILE"
    entry_up && echo "!! :$ENTRY_PORT 还在听" || echo "[ok] :$ENTRY_PORT 已关闭"
    # 引擎是入口的子孙，入口死了之后它还要一两秒才退。2026-10-20 连着两次跑 --entry-stop，
    # 这一行都当场报"!! :3080 还在听（那不是入口起的？）"，而 3 秒后 ss 读数两条端口全空 ——
    # 那句"那不是入口起的"是假警报，读的人却会去找一个不存在的进程。改成轮询，等不到再报。
    i=0; while port_up && [ $i -lt 10 ]; do i=$((i+1)); sleep 1; done
    port_up && echo "!! :$PORT 还在听（等了 10 秒；那确实不是入口起的，别乱杀，先看 ps -A | grep dsh）" \
      || echo "[ok] :$PORT 已关闭（等了 ${i}s）"
    ;;
  --stop)
    need_root
    if pid_alive; then
      kill "$(cat "$PIDFILE")" && echo "[ok] 已 SIGTERM $(cat "$PIDFILE")"
      i=0; while pid_alive && [ $i -lt 10 ]; do i=$((i+1)); sleep 1; done
      pid_alive && { kill -9 "$(cat "$PIDFILE")"; echo "[ok] 兜底 SIGKILL"; }
      rm -f "$PIDFILE"
    else
      in_chroot "pkill -f 'bin.js web' 2>/dev/null" && echo "[ok] 无 pidfile，按 cmdline 清掉了" || echo "[no-op] 本来就没在跑"
    fi
    port_up && echo "!! :$PORT 还在听" || echo "[ok] :$PORT 已关闭"
    ;;
  --status)
    need_root; have_chroot; status
    ;;
  --url)
    U=$(token_url); [ -n "$U" ] && echo "$U" || { echo "!! 日志里没有 token（服务可能还没起）" >&2; exit 1; }
    ;;
  --run)
    # 在 chroot 里跑一条命令就把结果打到 stdout，不用先 --进 shell 再敲：
    #   sh /data/local/sh/dsh-chroot.sh --run 'dsh --version'
    need_root; have_chroot
    [ $# -ge 2 ] || die "--run 后面要跟一条命令"
    shift; in_chroot "$*"
    ;;
  --umount)
    need_root
    grep -q " $PHONE_DST " /proc/mounts && { umount -l "$PHONE_DST" && echo "[ok] 卸载 phone（手机存储不再进 chroot）"; }
    for p in dev/shm run proc sys dev; do
      grep -q " $ROOTFS/$p " /proc/mounts && { umount -l "$ROOTFS/$p" && echo "[ok] 卸载 $p"; }
    done
    if [ -f "$SELPATH" ]; then
      setenforce "$(cat "$SELPATH")" && echo "[ok] SELinux 复原为 $(cat "$SELPATH")"; rm -f "$SELPATH"
    fi
    ;;
  "")
    need_root; have_chroot; permissive; mount_fs; home_entry_ensure
    echo "[..] 进入 chroot（exit 退出，挂载点留着）"
    exec $CHROOT "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp TERM="${TERM:-xterm-256color}" PATH="$ENV_PATH" /bin/bash -l
    ;;
  *)
    die "未知参数：$1（可用：无参 / --web / --entry / --entry-stop / --status / --url / --run / --stop / --umount）"
    ;;
esac
