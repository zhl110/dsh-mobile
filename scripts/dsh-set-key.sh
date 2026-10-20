#!/system/bin/sh
# dsh-set-key.sh — 把 DeepSeek API key 写进 chroot 里的 /root/.dsh-env（0600）
# 三条硬要求（都是为这个场景定的）：key 不进命令行参数、不回显、不进任何日志。
#   - 命令行参数会被同机 root 用 /proc/<pid>/cmdline 看到，也会留在 adb/终端的 history 里
#   - 所以只从 stdin 收：交互式就 read -s（输入不显示），管道就 cat
#   - 写完只报"长度"和文件权限，绝不报值
#
# 用法（root，两种都行）：
#   sh /data/local/sh/dsh-set-key.sh            # 提示你亲手粘贴/输入，屏幕不回显
#   printf '%s' 'sk-你的key' | sh /data/local/sh/dsh-set-key.sh   # 管道；注意这行会进 history
#
# 写完接着：sh /data/local/sh/dsh-chroot.sh --stop && sh /data/local/sh/dsh-chroot.sh --web
# （服务是在自己的环境里 source 这个文件的，改完必须重启才生效）
ROOTFS=/data/local/dsh-rootfs
ENV_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ -x "$ROOTFS/bin/sh" ] || { echo "!! rootfs 不在位：$ROOTFS"; exit 1; }
[ "$(id -u)" = "0" ] || { echo "!! 需要 root：先 su"; exit 1; }

# 交互式 tty 就在 chroot 里用 bash 的 read -s 收；非 tty（管道）就 cat 收
if [ -t 0 ]; then
  MODE=interactive
else
  MODE=pipe
fi

if [ "$MODE" = interactive ]; then
  echo "请输入 DeepSeek API key（屏幕不回显，输完回车）："
  chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH="$ENV_PATH" /bin/bash -c '
    set -u
    read -rs k
    [ -n "$k" ] || { echo "!! 空输入，没写"; exit 1; }
    umask 077
    printf "export DEEPSEEK_API_KEY=%q\n" "$k" > /root/.dsh-env
    echo "[ok] 已写入 /root/.dsh-env  长度=${#k}（值不回显、不落日志）"
    ls -l /root/.dsh-env
  '
else
  chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH="$ENV_PATH" /bin/bash -c '
    set -u
    k=$(cat)
    k=${k%$'"'"'\n'"'"'}
    k=${k%$'"'"'\r'"'"'}
    [ -n "$k" ] || { echo "!! stdin 是空的，没写"; exit 1; }
    umask 077
    printf "export DEEPSEEK_API_KEY=%q\n" "$k" > /root/.dsh-env
    echo "[ok] 已写入 /root/.dsh-env  长度=${#k}（值不回显、不落日志）"
    ls -l /root/.dsh-env
  '
fi

echo
echo "自检（不打印值，只确认服务真拿得到）：起服务后跑"
echo "  sh /data/local/sh/dsh-chroot.sh --status"
echo "或直接看进程的 env 里有没有这条：见脚本 dsh-keychain-test.sh 的 5/6 段"
