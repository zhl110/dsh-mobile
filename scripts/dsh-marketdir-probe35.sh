#!/bin/bash
# scripts/dsh-marketdir-probe35.sh —— 谁在手机上生出了 .plugin-manager 与 .dsh-market，以及**在跑的引擎到底吃没吃到这两发插件**。
#
# 为什么要这一发：p34（17:55）读出来 profiles/web 下已经有 .plugin-manager 与 .dsh-market，
# 而 p32（17:49）明写着「（还没有 .dsh-market）」。这中间只跑过三样东西：两次 pnpm add（17:50–51）、
# 装完复测、一次 dsh plugin list（17:55）。两发 tarball 里都**没有 preinstall/postinstall**（本地 tar -xOf 查过），
# 所以"装包脚本自己生的"这条不成立 —— 要么是本机 dsh CLI 自己引导 profile 时生的，要么是**没重启的引擎热加载了**。
# 这两种结论完全不一样，只能靠时刻、内容、以及引擎那侧的可观测面分开。
#
# 顺带修我自己的读数坑：p34 里 `stat -c 'mtime=%F'` 打出来是 "regular file" —— %F 是**文件类型**不是时间，
# 时间要用 %y/%Y。这一发全用 %y。
#
# 全程只读。跑法：bash tools/run-probe.sh scripts/dsh-marketdir-probe35.sh downloads/p35.txt
set -u
export LANG=C
PROFILE=web
P=/root/.dsh/profiles/$PROFILE
NOW=$(date +%s)

echo "== 0. 时刻（UTC；北京时间 = UTC+8）"
date -u '+  now UTC %F %T  epoch=%s'

echo "== 1. 最近一小时被动过的东西（只看 profiles/web 与 .dsh 顶层，maxdepth 3）"
find "$P" /root/.dsh -maxdepth 3 -newermt '-1 hour' -printf '%TY-%Tm-%Td %TH:%TM:%TS  %10s  %p\n' 2>/dev/null | sort | sed 's/^/  /'

echo "== 2. 那两个新目录里每个文件的出生时刻与全文（都很小，直接给）"
for d in .plugin-manager .dsh-market; do
  echo "  --- $d"
  find "$P/$d" -maxdepth 2 -printf '%y TY=%TY-%Tm-%Td %TH:%TM:%TS size=%s %p\n' 2>/dev/null | sed 's/^/    /'
done
for f in "$P/.dsh-market/state.json" "$P/.dsh-market/log.ndjson"; do
  echo "  --- $f（$(stat -c '%s B，mtime %y' "$f" 2>&1)）"
  head -c 900 "$f" 2>&1 | sed 's/^/      /'
  echo
done
echo "  --- .plugin-manager/logs 里的每一个（全文，超过 60 行截）"
for l in "$P/.plugin-manager/logs"/*; do
  [ -f "$l" ] || continue
  echo "    $l  $(stat -c '%s B  mtime=%y' "$l")  行数=$(wc -l <"$l")"
  tail -60 "$l" | sed 's/^/      | /'
done

echo "== 3. 引擎（在跑的那两个 node）现在开着哪些与插件有关的文件"
for pid in 17611 17637; do
  echo "  --- pid $pid  cmdline=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | cut -c1-60)"
  FD=$(ls -l /proc/$pid/fd 2>/dev/null | grep -cE 'profiles/web')
  echo "    fd 里落在 profiles/web 的条数 = $FD"
  ls -l /proc/$pid/fd 2>/dev/null | grep -E 'profiles/web|dsh-purge|dshmarket|plugin' | sed 's/^/      /' | head -10
done

echo "== 4. dsh CLI 自己怎么说（只问不写）"
cd "$P" 2>/dev/null
echo "  --- dsh --help 的子命令名单"
timeout 60 dsh --help 2>&1 | sed 's/^/      /' | head -40
echo "  --- dsh plugin --profile $PROFILE --help"
timeout 60 dsh plugin --help 2>&1 | sed 's/^/      /' | head -30

echo "== 5. 层栈里现在到底有几个人（这是「要不要重启」的真判据）"
echo "  --- 引擎进程打开/映射过 dsh-purge 的件没有（maps 里搜）"
echo "      17637 maps 命中 dsh-purge = $(grep -c 'dsh-purge' /proc/17637/maps 2>/dev/null)"
echo "      17637 maps 命中 dshmarket = $(grep -c 'dshmarket' /proc/17637/maps 2>/dev/null)"
echo "  --- profiles/web 下这两发的 client 入口在不在、多大"
for f in dsh-purge/client.js dshmarket/client; do
  printf '      %-22s ' "$f"; stat -c '%s B  %F' "$P/node_modules/$f" 2>&1
done
ls -1 "$P/node_modules/dshmarket/client" 2>/dev/null | sed 's/^/        dshmarket\/client: /'

echo "== 6. 引擎有没有在听 package.json（inotify 看不着就按「看不见」处理，不假装量到）"
echo "  17637 打开的 inotify 实例数 = $(ls -l /proc/17637/fd 2>/dev/null | grep -c inotify)"
echo "  17611 打开的 inotify 实例数 = $(ls -l /proc/17611/fd 2>/dev/null | grep -c inotify)"
echo "  17637 fd 总数 = $(ls -1 /proc/17637/fd 2>/dev/null | wc -l)"
echo "  完（没写盘）"
