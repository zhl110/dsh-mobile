#!/bin/bash
# scripts/dsh-plugin-loaded-probe37.sh —— 把 p36 剩下的两个洞补上：①引擎的 inotify 监视表我读错了（fdinfo 里 ino 是**十六进制**，
# 我拿十进制去撞，所以三发全"命中 0"，那是假阴性）；②引擎进程的 PATH 里到底有没有 pnpm（今早 App 插件页那两次操作
# 就是这么死的：.plugin-manager/logs/operation-yUm4kv/pnpm.log 写着 "Command failed with ENOENT: pnpm why '@deepseek-ai/dsh-base' / spawn pnpm ENOENT"）。
#
# 只读。唯一写入风险：无（不跑 --dump-config —— p36 那次它把 profiles/web/cordis.yml 重写了，mtime 从 09:55 跳到 10:00，字节数没变 223 B）。
set -u
export LANG=C
P=/root/.dsh/profiles/web
EG=17637; EP=17611

echo "== 0. 时刻（UTC；北京 = UTC+8）"
date -u '+  now %F %T'

echo "== 1. 引擎与入口的 PATH（只取 ^PATH= 这一行，别的键不外传）"
for pid in $EG $EP; do
  printf '  pid %s PATH = ' "$pid"
  tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^PATH=//p'
done
echo "  --- 对照：登录 shell（bash -lc）的 PATH"
echo "      $PATH"
echo "  --- pnpm 在哪、node 在哪"
echo "      $(command -v pnpm)  $(command -v node)"

echo "== 2. 引擎 inotify 监视表：十六进制 inode 换算成十进制再撞（p36 的假阴性就在这儿）"
for fd in /proc/$EG/fd/*; do
  case "$(readlink "$fd" 2>/dev/null)" in
    anon_inode:inotify)
      N=$(basename "$fd")
      echo "  --- fd $N"
      while read -r line; do
        hx=$(printf '%s' "$line" | sed -n 's/.*ino=\([0-9a-f]*\).*/\1/p')
        [ -n "$hx" ] || continue
        dec=$(printf '%d' "0x$hx")
        hit=$(find /root/.dsh /root/.dsh/profiles -maxdepth 4 -inum "$dec" -printf '%p\n' 2>/dev/null | head -3 | tr '\n' ' ')
        printf '    ino=%s(hex)=%s(dec)  →  %s\n' "$hx" "$dec" "${hit:-（这三个目录深度里没找到，可能在上层或已换 inode）}"
      done < "/proc/$EG/fdinfo/$N"
      ;;
  esac
done

echo "== 3. 装完之后（09:51:12 之后）盘上还有没有新增/改写 —— 这是「运行中的引擎吃到了没」的时间判据"
echo "  基准：install 收尾 09:51:07（package.json），市场写盘 09:51:12"
find /root/.dsh -maxdepth 4 -newermt '2026-10-21 09:51:13' -printf '%TY-%Tm-%Td %TH:%TM:%TS %10s %p\n' 2>/dev/null | sort | sed 's/^/  /'
echo "  （上面若只有 cordis.yml ⇒ 那是我 p36 的 --dump-config 写的，不是引擎加载；有 applied.json ⇒ 引擎或 CLI 真 mount 过）"
echo "  --- applied.json 在不在（PC 那台客户端真加载时 15:23:30 生成了它；手机现在没有）"
stat -c '    %n %s B mtime=%y' /root/.dsh/dsh-purge/applied.json 2>&1
echo "  --- 手机侧 dsh-purge 与 .dsh-market 现有全部文件"
find /root/.dsh/dsh-purge "$P/.dsh-market" -type f -printf '    %10s  %TY-%Tm-%Td %TH:%TM:%TS  %p\n' 2>/dev/null | sort -k3

echo "== 4. 引擎到底加载过几层：它自己的 stdout 接到入口，入口日志是 /root/.dsh/entry.out"
echo "  entry.out $(stat -c '%s B  mtime=%y' /root/.dsh/entry.out 2>&1)"
echo "  装插件（09:51）之后 entry.out 有没有新行 ⇒ 看 mtime 是否晚于 09:51:07"
echo "  --- entry.out 里最后 12 行（这文件是入口自己写的流水，不含凭据）"
tail -12 /root/.dsh/entry.out 2>/dev/null | sed 's/^/    /'
echo "  完（只读）"
