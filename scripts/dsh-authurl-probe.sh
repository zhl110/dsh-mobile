#!/system/bin/sh
# dsh-authurl-probe.sh — 只读：把 auth_init 那个请求的完整域名挖出来（日志里只有 path，没 host）
ROOTFS=/data/local/dsh-rootfs
NM=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai
R() { chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -lc "$1"; }
echo "=== 1. 哪个包里出现 auth_init:"
R "grep -rl auth_init $NM 2>/dev/null | head -6"
echo "=== 2. auth-api 附近的完整域名/常量:"
R "grep -rhoE --include='*.js' '.{0,60}auth-api.{0,60}' $NM 2>/dev/null | head -12"
echo "=== 3. account 平台包里的 host/base 常量:"
R "grep -rhoE --include='*.js' 'https://[a-zA-Z0-9._-]{6,}' $NM/dsh-deepseek-account-platform/lib $NM/dsh-llm-deepseek-account/lib 2>/dev/null | sort | uniq -c | sort -rn | head -10"
