#!/system/bin/sh
# dsh-key-probe.sh — 只读：确认「填 DEEPSEEK_API_KEY」这条路在包里的真实实现与端点
# 用法（root）：sh /data/local/sh/dsh-key-probe.sh
ROOTFS=/data/local/dsh-rootfs
ENV_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
NM=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules
R() { chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH="$ENV_PATH" /bin/bash -lc "$1"; }

echo "=== 1. 相关插件包在不在位:"
R "ls -d $NM/dsh-llm-deepseek-api-key $NM/dsh-llm-deepseek-account $NM/dsh-web-deepseek-api $NM/dsh-deepseek-account-platform 2>&1"

echo
echo "=== 2. 包里出现 DEEPSEEK_API_KEY 的文件:"
R "grep -rl DEEPSEEK_API_KEY $NM 2>/dev/null | head -20"

echo
echo "=== 3. 模型端点/默认 baseUrl（只看含 deepseek.com 或 baseUrl 的行）:"
R "grep -rhoE --include='*.js' 'https://[a-zA-Z0-9._-]*deepseek[a-zA-Z0-9._/-]*' $NM 2>/dev/null | sort | uniq -c | sort -rn | head -15"

echo
echo "=== 4. deepseek-official 这个 provider 到底怎么解析 key（找 apiKeyEnv / env 读取）:"
R "grep -rn 'apiKeyEnv' $NM --include='*.js' 2>/dev/null | head -12"

echo
echo "=== 5. 默认模型 deepseek-flash 的取值处:"
R "grep -rn 'deepseek-flash' $NM --include='*.js' 2>/dev/null | head -8"

echo
echo "=== 6. /etc/hosts 里现在钉了哪些 IP（只列域名，不改动）:"
R "grep -v '^#' /etc/hosts | grep -v '^\$' | head -20"
