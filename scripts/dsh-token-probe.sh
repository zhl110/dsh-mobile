#!/system/bin/sh
# dsh-token-probe.sh — 只读：确认那条带 token 的 URL 能不能重复用（决定给用户怎么进 Web UI）
ROOTFS=/data/local/dsh-rootfs
PORT=3080
LOG=/data/local/dsh.log
TOK=$(grep -o 'token=[A-Za-z0-9_-]*' "$LOG" 2>/dev/null | tail -1)

echo "=== 1. 全新请求（不带 cookie）打带 token 的 URL:"
curl -sS -o /dev/null -w '  HTTP=%{http_code}  重定向=%{redirect_url}\n' --max-time 8 "http://127.0.0.1:$PORT/?$TOK"

echo "=== 2. 再用已存下的 cookie 打裸 /:"
curl -sS -o /dev/null -w '  HTTP=%{http_code}  bytes=%{size_download}\n' --max-time 8 -b /data/local/tmp/dsh_cj "http://127.0.0.1:$PORT/"

echo "=== 3. 不带 token、不带 cookie 打裸 /（预期 401）:"
curl -sS -o /dev/null -w '  HTTP=%{http_code}  bytes=%{size_download}\n' --max-time 8 "http://127.0.0.1:$PORT/"

echo "=== 4. 同一个 token 连打两次，看第二次还认不认:"
curl -sS -o /dev/null -w '  第一次 HTTP=%{http_code}\n' --max-time 8 "http://127.0.0.1:$PORT/?$TOK"
curl -sS -o /dev/null -w '  第二次 HTTP=%{http_code}\n' --max-time 8 "http://127.0.0.1:$PORT/?$TOK"

echo "=== 5. DSH_ 开头的可调环境变量（从包里扫出来的 knob 名单）:"
chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /bin/bash -lc "grep -rhoE --include='*.js' 'process\.env\.DSH_[A-Z0-9_]+' /usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules 2>/dev/null | sort -u | head -30"
