#!/system/bin/sh
# dsh-restart-check.sh — 重启服务，验「关掉再点开还能不能直接进」
# 为什么单独查这个：dsh web 强制鉴权，裸 http://127.0.0.1:3080 恒 401，入场券只有两种——
# 日志里那条 ?token= 的 URL，和浏览器用它换到的 cookie。这两种券各自能不能扛过一次重启，
# 直接决定"当 App 用"这件事到底成不成立。本脚本把两条都测出来。
# 用法（root）：sh /data/local/sh/dsh-restart-check.sh
ROOTFS=/data/local/dsh-rootfs
LOG=/data/local/dsh.log
CTRL=/data/local/sh/dsh-chroot.sh
PORT=3080
CJ=/data/local/tmp/dsh_cj
PIDFILE=$ROOTFS/root/dsh.pid

tok() { grep -o 'token=[A-Za-z0-9_-]*' "$LOG" 2>/dev/null | tail -1; }
hit() { curl -sS -o /dev/null -w '%{http_code}' --max-time 12 -b "$CJ" "http://127.0.0.1:$PORT/" 2>/dev/null || echo 连不上; }

[ -f "$CTRL" ] || { echo "!! 找不到 $CTRL"; exit 1; }

# 第 0 步：先用当前 token 换一份确定的 cookie，作为"上一会话的券"
T0=$(tok)
C0=$(curl -sSL -c "$CJ" -b "$CJ" -o /dev/null -w '%{http_code}' --max-time 15 "http://127.0.0.1:$PORT/?$T0")
echo "--- 重启前: pid=$(cat "$PIDFILE" 2>/dev/null) token尾6=${T0: -6}  新换cookie=$C0"
ls -l "$ROOTFS/root/.dsh/.credentials.yaml" 2>/dev/null | awk '{print "    .credentials.yaml 大小="$5" mtime="$6" "$7" "$8}'

echo "--- 执行 --stop / --web"
sh "$CTRL" --stop
sh "$CTRL" --web
T1=$(tok)
echo
echo "--- 重启后: pid=$(cat "$PIDFILE" 2>/dev/null) token尾6=${T1: -6}"
[ "$T0" = "$T1" ] && echo "    token 与重启前【同一个】" || echo "    token 换新的 ⇒ 旧 URL 作废（每次重启都要重取）"
echo "    旧 token 全新请求: $(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "http://127.0.0.1:$PORT/?$T0")"
echo "    上一会话的 cookie 打裸 /: $(hit)"
ls -l "$ROOTFS/root/.dsh/.credentials.yaml" 2>/dev/null | awk '{print "    .credentials.yaml 大小="$5" mtime="$6" "$7" "$8}'
echo
echo "判读：「上一会话的 cookie 打裸 /」这一行是 200 ⇒ 浏览器收藏一次就长期能用；"
echo "      是 401 ⇒ 每次重启都得重跑 --url 拿新 token，那就不能靠收藏裸地址。"
