#!/usr/bin/env bash
# dsh-phone-visibility-probe40.sh —— 只读：把"引擎到底看得见 /phone 多少个条目"这一件事对清
#
# 为什么要这一发：今晚同一件事出现了**三个数**
#   p33 第 8 节（17:57Z，本探针的同一条路）说 /phone 顶层 **135**；
#   `dsh-chroot.sh --status` 第 55 行（18:2x）打的是 "chroot 内 /phone，顶层条目 **117** 个；服务实际 cwd=无在跑的服务"；
#   而我刚才随手用 `--run 'ls /phone'` 回的是 **No such file or directory**（0）。
# 三者不可能同时都对 ⇒ 要么挂载随会话有/没有，要么计数口径不同（含不含隐藏、谁的 mount namespace）。
# 这一发把四种视图一次取全，逐个标"是谁的眼"：
#   ① 本探针自己的 mountinfo（runner --run 起的那个 shell）
#   ② 引擎进程 17637 的 mountinfo（它才是真正在给用户干活的那个）
#   ③ 入口 17611 的
#   ④ 各自 root 下 /phone 的条目数（可见 / 含隐藏两种口径，与 p33 对齐）
# 只读：不 mount、不 umount、不写任何文件。
set -u
echo "== 0. 时刻"
date -u '+  UTC  %F %T'

echo "== 1. 有哪些 node 进程（先认 pid，别看错人）"
pgrep -af 'node' 2>/dev/null | sed 's/^/    /' | head -8
EG=$(pgrep -f 'dsh web' | head -1)
EN=$(pgrep -f 'dsh-entry.js' | head -1)
echo "    引擎 pid=${EG:-读不到}  入口 pid=${EN:-读不到}"

echo "== 2. /phone 在谁的 mountinfo 里"
echo "  --- ① 本探针这个 shell"
grep ' /phone ' /proc/self/mountinfo 2>/dev/null | sed 's/^/      /'
echo "      命中行数 = $(grep -c ' /phone ' /proc/self/mountinfo 2>/dev/null)"
for who in "$EG" "$EN"; do
  [ -n "$who" ] || continue
  echo "  --- pid $who 的 mountinfo 里那行（这就是它自己的眼）"
  awk '$5=="/phone" || $5 ~ /^\/phone/ {print "      " $0}' "/proc/$who/mountinfo" 2>/dev/null | head -3
  echo "      命中行数 = $(awk '$5 ~ /^\/phone/' "/proc/$who/mountinfo" 2>/dev/null | wc -l)"
done

echo "== 3. 各自的 root 下数 /phone 条目（两种口径）"
for who in self "$EG" "$EN"; do
  [ -n "$who" ] || continue
  if [ "$who" = "self" ]; then P=/phone; TAG="本 shell"; else P="/proc/$who/root/phone"; TAG="pid $who"; fi
  VIS=$(ls -1  "$P" 2>/dev/null | wc -l)
  ALL=$(ls -1A "$P" 2>/dev/null | wc -l)
  ERR=$(ls -1 "$P" 2>&1 >/dev/null | head -1)
  printf '    %-12s 可见=%-4s 含隐藏=%-4s  %s\n' "$TAG" "$VIS" "$ALL" "${ERR:+（stderr: $ERR）}"
done

echo "== 4. 与 p33 那记 135 对齐：本 shell 的顶层名字（名字会落进本地读数文件，不外传）"
ls -1A /phone 2>/dev/null | tr '\n' ' ' | fold -w 96 | sed 's/^/      /'
echo ""
echo "    顶层含隐藏计数 = $(ls -1A /phone 2>/dev/null | wc -l)"

echo "== 5. 引擎的工作目录与它自己的 env 里那条 WORKDIR（只取键名相关行，不 dump 全 env）"
if [ -n "$EG" ]; then
  echo "    cwd = $(ls -l /proc/$EG/cwd 2>/dev/null | sed 's/.*-> //')"
  tr '\0' '\n' < /proc/$EG/environ 2>/dev/null | grep -E '^(DSH_WORKDIR|HOME|PWD)=' | sed 's/^/      /'
fi
echo "  完（一个字节没写；不 mount 不 umount）"
