#!/bin/bash
# dsh-probe.sh — 在 chroot 内部跑的只读探针，专门用来出读数（不装不改不删）
# 用法（Android root shell，走总控脚本最省事）：
#   sh /data/local/sh/dsh-chroot.sh --run 'bash /root/dsh-probe.sh'
# 手动进也行：
#   chroot /data/local/dsh-rootfs /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
#     HOME=/root TMPDIR=/tmp /bin/bash /root/dsh-probe.sh
echo "=== 身份 ==="
uname -m; head -1 /etc/os-release 2>/dev/null; echo "TMPDIR=${TMPDIR:-未设置}"

echo "=== Node ==="
command -v node && node -v || echo "  node 不在 PATH"
command -v npm  && npm -v  || echo "  npm 不在 PATH"
echo "  npm prefix -g : $(npm prefix -g 2>/dev/null)"
echo "  npm root  -g  : $(npm root -g 2>/dev/null)"
echo "  registry      : $(npm config get registry 2>/dev/null)"

echo "=== dsh 本体 ==="
ROOT=$(npm root -g 2>/dev/null)
ls -d "$ROOT/@deepseek-ai/dsh" 2>/dev/null && echo "  dsh 包在位" || echo "  !! dsh 包不在 $ROOT/@deepseek-ai/dsh"
command -v dsh || echo "  dsh 不在 PATH"
dsh --version 2>&1 | head -2
ls -1 "$ROOT/@deepseek-ai/" 2>/dev/null | wc -l | sed 's/^/  全局 node_modules 里 @deepseek-ai 顶层条目: /'
ls -1 "$ROOT/@deepseek-ai/dsh/node_modules/@deepseek-ai/" 2>/dev/null | wc -l | sed 's/^/  dsh 自带的 dsh-* 子包数: /'

echo "=== 平台敏感件 ==="
if [ -d "$ROOT/@deepseek-ai" ]; then
  for d in $(find "$ROOT/@deepseek-ai" -maxdepth 4 -type d -name koffi 2>/dev/null); do
    if node -e "require('$d')" >/dev/null 2>&1; then echo "  koffi OK   $d"; else echo "  koffi FAIL $d"; fi
  done
  for r in $(find "$ROOT/@deepseek-ai" -maxdepth 6 -type f -name rg 2>/dev/null); do
    echo -n "  rg $r → "; "$r" --version 2>/dev/null | head -1 || echo "跑不起来"
  done
fi

echo "=== 运行态（端口为准，pgrep 会因为 cmdline 自匹配而假阳性）==="
if ss -lnt 2>/dev/null | grep -q ':3080'; then echo "  :3080 LISTEN"; else echo "  :3080 未监听"; fi
if [ -f /root/dsh.pid ]; then
  p=$(cat /root/dsh.pid)
  if [ -d "/proc/$p" ]; then echo "  pidfile=$p 活着: $(tr '\0' ' ' < /proc/$p/cmdline | cut -c1-80)"; else echo "  pidfile=$p 已死"; fi
else
  echo "  没有 /root/dsh.pid"
fi
curl -s -o /dev/null -w "  裸 / http=%{http_code}（401 是对的：dsh web 强制鉴权）\n" --max-time 8 http://127.0.0.1:3080/ || echo "  curl 连不上"
echo "  真页面读数要在 Android 侧带 token 走一遍，见 dsh-chroot.sh --status"

echo "=== 编译工具链（本轮实测一个都没装，koffi 走的是预编译）==="
for t in cmake gcc g++ make git python3; do
  printf "  %-8s %s\n" "$t" "$(command -v $t || echo 未安装)"
done

echo "=== 出口与证书 ==="
wc -c < /etc/ssl/certs/ca-certificates.crt 2>/dev/null | sed 's/^/  CA bundle 字节: /'
for h in registry.npmmirror.com api.deepseek.com; do
  printf "  %-24s " "$h"
  curl -s -o /dev/null -w "https=%{http_code}\n" --max-time 12 "https://$h/" || echo "不可达"
done
echo "  /etc/hosts 钉住的条目数: $(grep -vc '^#' /etc/hosts 2>/dev/null)"

echo "=== apt 源与实际装过的包（写这份脚本时是靠 adb 嵌套引号试的，读数全被打乱，只能落成文件跑才准）==="
ls -1 /etc/apt/sources.list.d/ 2>/dev/null | sed 's/^/  sources.list.d: /'
grep -h '^URIs:' /etc/apt/sources.list.d/*.sources 2>/dev/null | sed 's/^/  /'
for p in ca-certificates curl xz-utils iproute2 gnupg build-essential cmake git; do
  v=$(dpkg-query -W -f='${Version}' "$p" 2>/dev/null)
  printf "  %-20s %s\n" "$p" "${v:-未装}"
done

echo "=== 磁盘 ==="
df -h / | awk 'NR==2{print "  根分区空闲 "$4}'
du -sh "$ROOT" 2>/dev/null | sed 's/^/  node_modules /'
