#!/bin/bash
# 只读探针：查「登录不了」这件事的网络根因
# 依据：/data/local/dsh.log 里 sign-in failed 的那条 request path 是 /auth-api/v0/dsh/auth_init，
# 而账号包里的常量只有 api.deepseek.com 与 platform.deepseek.com 两个 origin。
# 本脚本要在 chroot 内部跑：/etc/hosts 才是 rootfs 那份，getent/curl 的解析结果才算数。
echo "=== /etc/hosts 里现在钉了哪些域名 ==="
grep -v '^\s*#' /etc/hosts | grep -v '^\s*$'

echo
echo "=== 这两个 origin 在 chroot 里各自解析成什么 ==="
for h in api.deepseek.com platform.deepseek.com; do
  printf '%-26s getent=%s' "$h" "$(getent hosts "$h" 2>/dev/null | head -1)"
  printf '  curl=%s\n' "$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 "https://$h/" 2>&1)"
done

echo
echo "=== 账号包里的常量与 auth-api 拼接方式（原样读，不改） ==="
A=$(find /usr/local/lib/node_modules/@deepseek-ai -maxdepth 1 -type d -name '*account*')
echo "包目录: $A"
grep -rhoE 'https://[a-z.]*deepseek[a-z.]*' "$A" 2>/dev/null | sort | uniq -c | sed 's/^/  /'
grep -rn 'auth-api' "$A" 2>/dev/null | head -6 | sed 's/^/  /'

echo
echo "=== 直接打一发 auth_init，看是 DNS 死还是 HTTP 死 ==="
for h in api.deepseek.com platform.deepseek.com; do
  printf '  %-24s ' "$h"
  curl -s -o /dev/null -w 'http=%{http_code} exit=%{exitcode}\n' --max-time 12 \
    "https://$h/auth-api/v0/dsh/auth_init" 2>&1 || echo "curl 失败"
done
