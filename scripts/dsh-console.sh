#!/system/bin/sh
# dsh-console.sh —— 手机上的 DeepSeek Harness 控制台（看得见的开/关/状态/日志/终端）
#
# 为什么有这个文件：他要的是「一个桌面软件，点开就能用，想关就关，进程我看得见」。
# dsh 0.2.1-rc.2 实测没有终端界面（dsh --profile tui → profile "tui" does not exist），
# headless 是「一次性任务」不是 REPL，所以交互面只有 Web；而服务本身在后台，看不见也杀不掉。
# 这个菜单把「起停 + 观测 + 一个真终端」收进 Termux 的窗口里，全部走已实测过的 dsh-chroot.sh。
#
# 装法：本文件放 /data/local/sh/，权限 0755，root 执行；Termux 的 .bashrc 里自动调它（见 RUNBOOK 第 12 步）。
# 只读不写他文件：这里只有起停我们自己的服务与读日志，不碰 /data/local/tmp 下他自己的东西。

CTRL=/data/local/sh/dsh-chroot.sh
ROOTFS=/data/local/dsh-rootfs
LOG=/data/local/dsh.log
BOOT=/data/adb/service.d/50-dsh.sh
BOOT_OFF=/data/adb/service.d/50-dsh.sh.off
ENV_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[ "$(id -u)" = 0 ] || { echo "这个菜单要 root：先 su"; exit 1; }
[ -f "$CTRL" ] || { echo "找不到 $CTRL"; exit 1; }

menu() {
  printf '\n'
  printf '  DeepSeek Harness · 手机控制台\n'
  printf '  ─────────────────────────────\n'
  printf '   1) 状态      进程 / 端口 / 页面 HTTP / 入口自述\n'
  printf '   2) 启动      起入口(:3081)+引擎(:3080)，之后 App 点开就能用\n'
  printf '   3) 打开      开桌面上的 DSH 图标（写死地址，不用贴 token）\n'
  printf '   4) 日志      实时看输出，Ctrl-C 回菜单\n'
  printf '   5) 终端      进 Ubuntu 命令行（exit 回菜单）\n'
  printf '   6) 停止      杀掉入口与引擎，省电流\n'
  printf '   7) 收尾      停止 + 卸挂载，恢复原状\n'
  printf '   8) 自启      开关「开机就自己起来」\n'
  printf '   9) 跑一句    不进浏览器，命令行里问一句话\n'
  printf '   w) 裸引擎    只起 3080 并打带 token 的 URL（对照路线，token 用过即废）\n'
  printf '   0) 退出      回 Termux 普通 shell\n'
  printf '\n  选一项: '
}

run() { printf '\n$ %s\n' "$*"; "$@"; printf '\n(回车回菜单)'; read _ ; }

while :; do
  menu
  read c
  case "$c" in
    1) run sh "$CTRL" --status ;;
    2) run sh "$CTRL" --entry ;;
    3) am start -n com.zhl.dsh/.MainActivity >/dev/null 2>&1 \
         && echo "已交给 App（它打的是写死的 http://127.0.0.1:3081/，不需要 token）" \
         || echo "App 没接住：先确认装好了（pm list packages | grep com.zhl.dsh），没装就跑 app/build.sh --install"
       printf '\n(回车回菜单)'; read _ ;;
    4) echo "Ctrl-C 回菜单"; echo "（这份是引擎日志 $LOG；入口那份在 chroot 的 /root/.dsh/entry.log，它自己脱过敏）"; tail -n 60 -f "$LOG" ;;
    5) echo "exit 退出这个终端"; chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH="$ENV_PATH" /bin/bash -l ;;
    6) run sh "$CTRL" --entry-stop; run sh "$CTRL" --stop ;;
    7) run sh "$CTRL" --entry-stop; run sh "$CTRL" --stop; run sh "$CTRL" --umount ;;
    8) if [ -f "$BOOT" ]; then
         mv "$BOOT" "$BOOT_OFF" && echo "自启已关：开机后不会自己在后台跑（现在在跑的进程不受影响）"
       elif [ -f "$BOOT_OFF" ]; then
         mv "$BOOT_OFF" "$BOOT" && echo "自启已开：开机后服务自己在后台起来"
       else
         echo "两个位置都没有 50-dsh.sh，无从切换：$BOOT / $BOOT_OFF"
       fi
       printf '\n(回车回菜单)'; read _ ;;
    9) printf '  要问的话: '; read -r q
       [ -n "$q" ] || continue
       printf '%s' "$q" > "$ROOTFS/tmp/dsh-task"
       echo "（headless 是一次性任务，不读 Web 里登录的账号，只认 /root/.dsh-env 里的 DEEPSEEK_API_KEY）"
       run sh "$CTRL" --run '/bin/bash /root/dsh-ask.sh' ;;
    w) run sh "$CTRL" --web
       U=$(sh "$CTRL" --url)
       [ -n "$U" ] && { echo "$U"; am start -a android.intent.action.VIEW -d "$U" >/dev/null 2>&1 \
         && echo "已交给浏览器" || echo "浏览器没接住，手动把这行粘进去"; }
       echo "（这条是对照路线：token 一次性，用过就废，重启就得重新贴）"
       printf '\n(回车回菜单)'; read _ ;;
    0) echo; exit 0 ;;
    *) printf '\n(回车回菜单)'; read _ ;;
  esac
done
