#!/system/bin/sh
# dsh-smoke.sh — 一次性验收：手机上的 dsh 到底能不能真跑出模型回答
# 它走的正是服务用的那条路：source /root/.dsh-env（真 key 在那儿）→ dsh --profile headless 打一句话
# → 对面必须回一个字。回出来了就是"手机本体 + 联网调 DeepSeek"整条链成立。
# 用法（root）：sh /data/local/sh/dsh-smoke.sh
# 说明：headless 是一次性会话，只吃这一句 prompt；它会往 /root/.dsh 里建自己的 profile 目录，
#      不动 web profile，也不动 pidfile，跟正在跑的服务互不打扰。
ROOTFS=/data/local/dsh-rootfs
ENV_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LOG=/data/local/dsh.log
PORT=3080
PROMPT='reply with exactly one word: pong'

R() { chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH="$ENV_PATH" /bin/bash -lc "$1"; }

echo "=== 1. 服务读数:"
echo "  监听: $(ss -lnt 2>/dev/null | grep -q ":$PORT" && echo ":$PORT LISTEN" || echo 不监听)"
PID=$(cat "$ROOTFS/root/dsh.pid" 2>/dev/null)
echo "  pidfile: ${PID:-无}"
if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
  if tr '\0' '\n' < "/proc/$PID/environ" 2>/dev/null | grep -q '^DEEPSEEK_API_KEY='; then
    echo "  服务 env: DEEPSEEK_API_KEY 在位，长度=$(tr '\0' '\n' < "/proc/$PID/environ" | awk -F= '/^DEEPSEEK_API_KEY=/{print length($2)}')"
  else
    echo "  服务 env: 没有 DEEPSEEK_API_KEY ⇒ 填完 /root/.dsh-env 后要 --stop 再 --web"
  fi
fi

echo
echo "=== 2. /root/.dsh-env:"
R "ls -l /root/.dsh-env 2>&1; cut -d= -f1 /root/.dsh-env 2>/dev/null | sed 's/^/  变量名: /'"

echo
echo "=== 3. 移动网络计数（前）:"
awk '/rmnet/{s+=$2} END{print "  rx 合计="s}' /proc/net/dev

echo
echo "=== 4. 真打一句给模型（走的就是 .dsh-env 里那条 key）:"
R ". /root/.dsh-env 2>/dev/null; timeout 300 dsh --profile headless '$PROMPT' 2>&1 | tail -25"

echo
echo "=== 5. 移动网络计数（后）:"
awk '/rmnet/{s+=$2} END{print "  rx 合计="s}' /proc/net/dev

echo
echo "判读：第 4 段出现 pong（或模型正常答话）⇒ 通了；"
echo "      出现 Authentication Fails / invalid ⇒ key 没填对；出现 fetch/ENOTFOUND/TLS 错 ⇒ 是网络那头的毛病，见 RUNBOOK §9。"
