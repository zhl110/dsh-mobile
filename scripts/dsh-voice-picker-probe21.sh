#!/bin/bash
# scripts/dsh-voice-picker-probe21.sh —— 只读，跑 prepare 之前先把"谁在吃内存、现在什么样"记下来。
# 为什么要在 chroot 里看：引擎进程就在 chroot 里，宿主机 ps 看不到它的 cmdline 全貌。
# 不发 RPC、不写盘、不 kill。口令不参与。
set -u
echo "== 1. chroot 里跟 dsh 有关的 node 进程（PID / RSS_MB / ETIMES / 头 100 字命令）"
for p in $(ls /proc | grep -E '^[0-9]+$'); do
  # 枚举到的 pid 里必然有正在消失的（探针自己起的子进程就是），读不到就跳过，不要把报错混进读数
  [ -r /proc/$p/cmdline ] || continue
  cmd=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
  case "$cmd" in *dsh*|*entry*) ;; *) continue ;; esac
  rss=$(awk '/VmRSS/{print $2}' /proc/$p/status 2>/dev/null)
  et=$(ps -o etimes= -p "$p" 2>/dev/null | tr -d ' ')
  printf '  pid=%-7s rss_mb=%-8s etimes=%-8s %s\n' "$p" "$(( ${rss:-0} / 1024 ))" "${et:-?}" "${cmd:0:100}"
done
echo
echo "== 2. 机器内存"
grep -E 'MemTotal|MemAvailable' /proc/meminfo 2>/dev/null | sed 's/^/  /'
echo
echo "== 3. 缓存目录现状（应当是 3 份，共 241,357,257 B）"
du -sb /root/.dsh/speech-to-text 2>/dev/null | sed 's/^/  /'
ls -1 /root/.dsh/speech-to-text/sensevoice/models/*/ 2>/dev/null | sed 's/^/  /'
echo
echo "== 4. sherpa 那两件 native 装在不在（prepare 之后真识别要用它们）"
ls -d /usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/sherpa-onnx* 2>/dev/null | sed 's/^/  /'
