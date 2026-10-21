#!/bin/bash
# scripts/dsh-plugins-probe32.sh —— 只读：为"把电脑上那两发插件也装进手机"量前置条件。
#
# 为什么先探再装：装机那一步的成败全在这几条盘外话上，一条条量出来比"跑跑看"省一整轮 ——
#   ① `dsh plugin` 只是把参数转给 **pnpm**，chroot 里没有 pnpm 就直接不通（电脑上系统是 pnpm 11.28.5，手机是 npm 装的 dsh，两回事）；
#   ② `dshmarket` 除自己之外还要 **undici + js-yaml**，那是**联网取**的（purge 只有 peer，实测零下载）⇒ 得先量手机上 registry 通不通、多快；
#   ③ profile 的 `pnpm-workspace.yaml` 里 `nodeLinker: hoisted` / `autoInstallPeers: false` 这两条决定 peer 会不会被拉进来；
#   ④ 装完要不要重启引擎（层栈是启动时组合的；电脑上那发是 HMR 2 秒接住的，**手机这台能不能同样接住没验过**）。
# 全程只读：不改任何文件、不装任何东西、不重启服务。
# 用法：bash tools/run-probe.sh scripts/dsh-plugins-probe32.sh downloads/p32.txt

echo "=== 0. 时刻与身份（chroot 是 UTC，比北京时间差 8 小时）"
date -Is; id -u; uname -m; echo

echo "=== 1. 三个运行件在不在、什么版本"
for c in node npm npx pnpm corepack dsh; do
  p=$(command -v $c 2>/dev/null)
  printf '%-9s %-40s' "$c" "${p:-（不在 PATH）}"
  [ -n "$p" ] && timeout 25 $c --version 2>&1 | head -1 || echo
done
echo

echo "=== 2. dsh 装在哪、可写吗、有没有自带 pnpm"
D=$(command -v dsh 2>/dev/null)
if [ -n "$D" ]; then
  RP=$(readlink -f "$D"); echo "dsh 实际 = $RP"
  ROOT=$(dirname "$(dirname "$RP")")
  echo "npm 全局前缀推断 = $ROOT"
  stat -c '  %n  mode=%a uid=%u gid=%g' "$ROOT" 2>&1
  echo "  这个前缀下有没有 pnpm 相关件（只数三种命名）："
  ls -1 "$ROOT"/lib/node_modules 2>/dev/null | grep -iE '^pnpm|pnpmc' | sed 's/^/    /'
  find "$ROOT" -maxdepth 5 -name 'pnpm.cjs' -o -maxdepth 5 -name 'pnpm' -type f 2>/dev/null | head -3 | sed 's/^/    /'
  echo "  它自己的 node_modules 顶层（前 12 条，看 @deepseek-ai 那套在不在同一棵树里）："
  ls -1 "$ROOT"/lib/node_modules/@deepseek-ai 2>/dev/null | head -12 | sed 's/^/    /'
else
  echo "!! PATH 里没有 dsh —— 后面 profile 那些都白测，先看第 1 节"
fi
echo

echo "=== 3. profile 名单与 web profile 现状"
ls -l /root/.dsh/profiles/ 2>&1
P=/root/.dsh/profiles/web
echo "--- $P/package.json（$(stat -c %s "$P/package.json" 2>/dev/null || echo 0) B）"
cat "$P/package.json" 2>&1
echo "--- $P/cordis.patch.yml（$(stat -c %s "$P/cordis.patch.yml" 2>/dev/null || echo 0) B）"
cat "$P/cordis.patch.yml" 2>&1
echo "--- $P/pnpm-workspace.yaml"
cat "$P/pnpm-workspace.yaml" 2>&1
echo "--- $P/node_modules 顶层"
ls -1 "$P/node_modules" 2>/dev/null | head -15
echo "    条目数 = $(ls -1A "$P/node_modules" 2>/dev/null | wc -l)"
stat -c '    .pnpm → %F %s B（不存在会直接报 No such file，不用 test -e 判）' "$P/node_modules/.pnpm" 2>&1
echo

echo "=== 4. 插件 CLI 到底存不存在、认不认这个 profile（只跑 list，不写盘）"
timeout 20 dsh plugin --help 2>&1 | head -8
echo "--- dsh plugin --profile web list（超时 60 秒）"
timeout 60 dsh plugin --profile web list 2>&1 | head -12
echo "list_rc=$?"
echo

echo "=== 5. registry 配置与出口速度（Range 只取 2 KB，认落字节不认 200）"
npm config get registry 2>&1 | head -1
echo "--- /etc/hosts 里跟包管理相关的行"
grep -iE 'npmmirror|npmjs|jsdelivr|github' /etc/hosts 2>/dev/null | sed 's/^/  /'
for u in https://registry.npmmirror.com/js-yaml https://cdn.npmmirror.com/js-yaml/-/js-yaml-4.1.0.tgz; do
  printf '  %-64s ' "$u"
  timeout 25 curl -s -o /dev/null -w 'http=%{http_code} 拿到 %{size_download} B %{speed_download} B/s\n' \
    --max-time 24 -r 0-2047 "$u" 2>&1 || echo "curl 失败"
done
echo

echo "=== 6. 空间与引擎现状（装两发要多少地方）"
df -h /root 2>&1 | tail -2
echo "  /root/.dsh 总计 $(du -sh /root/.dsh 2>/dev/null | cut -f1)   profiles 计 $(du -sh "$P" 2>/dev/null | cut -f1)"
echo "--- 谁在听 3080 / 3081"
(ss -lntp 2>/dev/null || netstat -lntp 2>/dev/null) | grep -E '3080|3081' | sed 's/^/  /'
echo "--- 我的进程（重启引擎会碰到哪些）"
ps -eo pid,etimes,args 2>/dev/null | grep -E 'dsh|node' | grep -v grep | head -8
echo

echo "=== 7. 已经在这台机上的插件痕迹（有没有早轮装过东西）"
echo "  profiles/web/node_modules 里有几个非隐藏目录 = $(ls -1 "$P/node_modules" 2>/dev/null | grep -vc '^\.' )"
find /root/.dsh -maxdepth 3 -iname '*purge*' -o -maxdepth 3 -iname '*market*' 2>/dev/null | head -5 | sed 's/^/  /'
echo "  /root/dsh-plugins 在 = $([ -d /root/dsh-plugins ] && echo yes || echo no)"
echo "=== 完（这条探针没写任何盘：唯一可能的落点是 curl -o /dev/null）==="
