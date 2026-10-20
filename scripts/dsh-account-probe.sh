#!/system/bin/sh
# dsh-account-probe.sh — 只读：把「网页里点登录为什么没反应」那件事查到底
ROOTFS=/data/local/dsh-rootfs
NM=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules
R() { chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -lc "$1"; }
echo "=== 1. auth-api / auth_init 这几个请求打到哪个域名:"
R "grep -rhoE --include='*.js' 'https://[a-zA-Z0-9._-]+(/auth-api)?' $NM 2>/dev/null | sort | uniq -c | sort -rn | head -12"
echo "=== 2. account 平台插件里的 baseUrl 定义:"
R "grep -rnE --include='*.js' 'auth-api|auth_init|baseUrl|accountBase' $NM/dsh-deepseek-account-platform/lib 2>/dev/null | head -12"
echo "=== 3. 这些域名在 /etc/hosts 里钉了没:"
R "grep -oE '[a-z0-9.-]+$' /etc/hosts | sort -u | tr '\n' ' '"
echo
echo "=== 4. 有没有终端界面(tui)的 profile 可选:"
R "ls -d $NM/*tui* $NM/*cli* 2>/dev/null; echo '---'; dsh --profile tui --help 2>&1 | head -6"
