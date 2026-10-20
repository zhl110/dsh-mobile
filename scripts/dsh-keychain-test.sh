#!/system/bin/sh
# dsh-keychain-test.sh — 用一个一眼假的哑 key 端到端验「env → dsh → 出站 HTTPS → api.deepseek.com 应答」
# 为什么这么验：真 key 在他手上，我不该拿去试。但"这条链通不通"和"key 对不对"是两件事——
# 哑 key 打出去，对面回的是鉴权失败，那就正好证明请求真的离开了手机、TLS 校验过了、
# 应答被 dsh 读回来了；这三件事才是这轮要在手机上证明的东西。
# 哑 key 只在命令行环境里存在这一条命令的生命周期内，不写盘、不进 /root/.dsh-env。
# 用法（root）：sh /data/local/sh/dsh-keychain-test.sh
ROOTFS=/data/local/dsh-rootfs
ENV_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
DUMMY=sk-dummy-invalid-do-not-use
R() { chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH="$ENV_PATH" /bin/bash -lc "$1"; }

echo "=== 0. 现在有没有 /root/.dsh-env（有就说明真 key 已经填过了）:"
R "ls -l /root/.dsh-env 2>&1"

echo
echo "=== 1. 移动网络计数（前）:"
awk '/rmnet/{s+=$2} END{print "  rx 合计="s}' /proc/net/dev

echo
echo "=== 2. 带哑 key 跑一次 headless（只跑一句 pong，看它把什么话吐回来）:"
R "DEEPSEEK_API_KEY=$DUMMY timeout 300 dsh --profile headless 'reply with exactly one word: pong' 2>&1 | tail -40"
echo "  （退出码 $?）"

echo
echo "=== 3. 移动网络计数（后）:"
awk '/rmnet/{s+=$2} END{print "  rx 合计="s}' /proc/net/dev

echo
echo "=== 4. 有没有把哑 key 落进任何文件（应当一个都没有）:"
R "grep -rl $DUMMY /root 2>/dev/null | head -5; echo '  --- 以上为空即未落盘'"

echo
echo "=== 5. 正在跑的那个服务进程，env 里到底有没有 DEEPSEEK_API_KEY（只看有无与长度，不打印值）:"
PID=$(cat "$ROOTFS/root/dsh.pid" 2>/dev/null)
if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
  tr '\0' '\n' < "/proc/$PID/environ" 2>/dev/null | awk -F= '
    /^DEEPSEEK_API_KEY=/{print "  pid='"$PID"' 里有 DEEPSEEK_API_KEY，值长度="length($2)}
    END{if(NR==0)print "  读不到 environ"}' | head -3
  tr '\0' '\n' < "/proc/$PID/environ" 2>/dev/null | grep -q '^DEEPSEEK_API_KEY=' \
    || echo "  env 里没有 DEEPSEEK_API_KEY ⇒ /root/.dsh-env 还没填真 key（或没重启服务）"
else
  echo "  服务没在跑，起一下：sh /data/local/sh/dsh-chroot.sh --web"
fi

echo
echo "=== 6. /root/.dsh-env 现在的权限与变量名（只列名）:"
R "ls -l /root/.dsh-env 2>&1; cut -d= -f1 /root/.dsh-env 2>/dev/null"

