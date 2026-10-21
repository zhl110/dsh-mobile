#!/bin/bash
# scripts/dsh-plugin-loaded-probe36.sh —— 手机上那台**没重启的引擎**到底吃不到了这两发插件（判「要不要重启」只认这一发）。
#
# 为什么要这一发（p35 留下的岔口）：
#   p35 见 /root/.dsh/dsh-purge/{override-state.json,installed-rev}、/root/.dsh/prompt-inject.md(24455 B)、
#   /root/.dsh/redteam/skills/*、/root/.dsh/.agent-presets/redteam/* 全在 **09:51:06Z** 出生，
#   /root/.dsh/profiles/web/.dsh-market/{state.json,log.ndjson} 在 **09:51:12Z** 出生 ——
#   而 pnpm add 的 package.json 是 09:51:07Z，引擎进程是 10-20 13:27Z 生的（活 73,712 秒），没重启过。
#   两发 tarball 都没有 preinstall/postinstall（本地 tar -xOf 查过）⇒ 这些写盘只能是**某个 dsh 进程跑了插件的代码**。
#   对照 PC（北京时间）：14:30 装 ⇒ 15:23 才出 applied.json/installed-rev 与 .dsh-market/state.json，
#   那 53 秒差是客户端真去 mount 层栈的时刻。手机这边装完 6 秒就写了 ⇒ 要么它一直在轮询/监听（热加载），
#   要么另有进程。这条只能从引擎的 stdout、它开的 inotify 监视表、和它自己 --dump-config 三条上分。
#
# 只读承诺：唯一的"执行类"是 `dsh --profile web --dump-config`（它 --help 明写 print the composed profile tree and exit）。
# 我不信承诺，所以调它之前/之后各取一次"最近 20 秒被动过的项目"，有写入就如实报，不隐藏。
set -u
export LANG=C
PROFILE=web
P=/root/.dsh/profiles/$PROFILE
EP=17611     # 常驻入口 node /usr/local/bin/dsh-entry.js --start
EG=17637     # 引擎   node /usr/local/bin/dsh web --port 3080

echo "== 0. 时刻（UTC；北京 = UTC+8）"
date -u '+  now %F %T.%N'

echo "== 1. 引擎与入口的 stdout/stderr 接到哪儿（日志不在那儿就别猜）"
for pid in $EP $EG; do
  echo "  --- pid $pid $(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | cut -c1-50)"
  for n in 1 2; do
    printf '    fd %s → ' "$n"; readlink "/proc/$pid/fd/$n" 2>&1
  done
done
LOGS=$(for pid in $EP $EG; do for n in 1 2; do readlink "/proc/$pid/fd/$n" 2>/dev/null; done; done | grep -E '^/' | sort -u)
echo "  落盘日志候选：$(printf '%s\n' "$LOGS" | grep -c .)"
printf '%s\n' "$LOGS" | sed 's/^/    /'

echo "== 2. 装插件那 20 秒（09:51:0x）引擎日志里说了什么（只取带插件名/层字样的行，不 cat 全文）"
for l in $LOGS; do
  [ -f "$l" ] || continue
  echo "  --- $l  $(stat -c '%s B  mtime=%y' "$l")"
  echo "    全文行数 = $(wc -l <"$l")"
  grep -inE 'purge|dshmarket|bundle|layer|patch|mount|reload|watch|plugin' "$l" 2>/dev/null | tail -25 | sed 's/^/      /'
done

echo "== 3. 引擎在 inotify 上监视了哪些 inode（拿 inode 号去撞 profile 里的文件）"
Watches=0
for fd in /proc/$EG/fd/*; do
  t=$(readlink "$fd" 2>/dev/null)
  case "$t" in
    anon_inode:inotify)
      N=$(basename "$fd")
      echo "  --- fd $N 是 inotify，fdinfo："
      grep '^inotify' "/proc/$EG/fdinfo/$N" 2>/dev/null | sed 's/^/      /'
      Watches=$(grep -c '^inotify' "/proc/$EG/fdinfo/$N" 2>/dev/null)
      echo "    监视条目数 = $Watches"
      ;;
  esac
done
echo "  --- 候选 inode 对照表"
for f in "$P" "$P/package.json" "$P/cordis.yml" "$P/cordis.patch.yml" "$P/node_modules" /root/.dsh /root/.dsh/profiles; do
  printf '    %-42s ino=' "$f"; stat -c '%i' "$f" 2>&1
done
echo "  --- 撞上了没（inotify fdinfo 里若出现上面某个 ino ⇒ 引擎确实在听它）"
for ino in $(for f in "$P" "$P/package.json" "$P/node_modules"; do stat -c '%i' "$f" 2>/dev/null; done); do
  hit=$(for fd in /proc/$EG/fd/*; do case "$(readlink "$fd" 2>/dev/null)" in anon_inode:inotify) grep -l "ino=$ino " "/proc/$EG/fdinfo/$(basename "$fd")" ;; esac; done 2>/dev/null | wc -l)
  echo "    ino $ino 命中 $hit 个 inotify fd"
done

echo "== 4. .plugin-manager/logs/operation-* 里面到底写了什么（p35 只列了目录名，没进去）"
find "$P/.plugin-manager" -mindepth 2 -printf '%y TY=%TY-%Tm-%Td %TH:%TM:%TS size=%s %p\n' 2>/dev/null | sort -k2 | sed 's/^/  /'
for f in $(find "$P/.plugin-manager" -type f 2>/dev/null | head -12); do
  echo "  --- $f  ($(stat -c '%s B  mtime=%y' "$f"))"
  head -c 1200 "$f" 2>&1 | sed 's/^/      /'
  echo
done

echo "== 5. 插件自己写到 ~/.dsh 下的那几份（内容都小，给全文 —— 这决定它是不是已经生效）"
echo "  --- /root/.dsh/dsh-purge 目录全貌"
find /root/.dsh/dsh-purge -maxdepth 2 -printf '%y TY=%TY-%Tm-%Td %TH:%TM:%TS size=%s %p\n' 2>/dev/null | sed 's/^/    /'
for f in /root/.dsh/dsh-purge/installed-rev /root/.dsh/dsh-purge/override-state.json /root/.dsh/dsh-purge/applied.json; do
  [ -f "$f" ] || { echo "  $f = 没有"; continue; }
  echo "  --- $f（$(stat -c '%s B  mtime=%y' "$f")）"
  head -c 700 "$f" | sed 's/^/      /'; echo
done
echo "  --- /root/.dsh/prompt-inject.md（$(stat -c '%s B  mtime=%y' /root/.dsh/prompt-inject.md 2>&1)）前 12 行"
head -12 /root/.dsh/prompt-inject.md 2>&1 | sed 's/^/      /'
echo "  --- /root/.dsh/redteam/preset-declare.json（$(stat -c '%s B  mtime=%y' /root/.dsh/redteam/preset-declare.json 2>&1)）"
head -c 700 /root/.dsh/redteam/preset-declare.json 2>&1 | sed 's/^/      /'; echo
echo "  --- /root/.dsh/.agent-presets/redteam/preset.yml（$(stat -c '%s B  mtime=%y' /root/.dsh/.agent-presets/redteam/preset.yml 2>&1)）"
head -20 /root/.dsh/.agent-presets/redteam/preset.yml 2>&1 | sed 's/^/      /'

echo "== 6. redteam 那套件到底多大（第三方插件往 ~/.dsh 里塞了一个 agent 预设，这条要报给他）"
echo "  /root/.dsh/redteam = $(du -sh /root/.dsh/redteam 2>/dev/null | cut -f1)  件数=$(find /root/.dsh/redteam -type f 2>/dev/null | wc -l)"
echo "  /root/.dsh/.agent-presets = $(du -sh /root/.dsh/.agent-presets 2>/dev/null | cut -f1)  件数=$(find /root/.dsh/.agent-presets -type f 2>/dev/null | wc -l)"
find /root/.dsh/.agent-presets -type f -printf '    %10s  %p\n' 2>/dev/null | sed 's/^/  /'

echo "== 7. 引擎自己组的层栈里有几个人（--dump-config；调前后各扫一次写入）"
echo "  --- 调用前：最近 20 秒被动过的（应为空）"
find /root/.dsh "$P" -maxdepth 3 -newermt '-20 seconds' 2>/dev/null | sed 's/^/    /'
echo "  --- dsh --profile $PROFILE --dump-config（超时 180 s，只打不装；只跑一次，计数取同一份输出）"
D=$(timeout 180 dsh --profile $PROFILE --dump-config 2>&1); RC=$?
printf '%s\n' "$D" | head -120 | sed 's/^/      /'
echo "  dump_rc=$RC"
echo "    dsh-purge 命中行 = $(printf '%s\n' "$D" | grep -c 'dsh-purge')"
echo "    dshmarket 命中行 = $(printf '%s\n' "$D" | grep -c 'dshmarket')"
echo "    @deepseek-ai/dsh-* 命中行 = $(printf '%s\n' "$D" | grep -c '@deepseek-ai/dsh-')"
echo "    输出总行数 = $(printf '%s\n' "$D" | wc -l)"
echo "  --- 调用后：最近 25 秒被动过的（若非空 ⇒ 它确实写了盘，如实报）"
find /root/.dsh "$P" -maxdepth 3 -newermt '-25 seconds' 2>/dev/null | sed 's/^/    /'

echo "== 8. 与 p35 的接力点（把两次读数并排，避免我下次又忘了）"
echo "  package.json mtime      = $(stat -c '%y' "$P/package.json" 2>&1)"
echo "  .dsh-market/state.json  = $(stat -c '%y' "$P/.dsh-market/state.json" 2>&1)"
echo "  dsh-purge/installed-rev = $(stat -c '%y' /root/.dsh/dsh-purge/installed-rev 2>&1)"
echo "  引擎 17637 出生          = $(stat -c '%y' /proc/$EG 2>&1)"
echo "  完（除第 7 节那条 --dump-config，没别的动作；它有没有写盘看第 7 节最后一段）"
