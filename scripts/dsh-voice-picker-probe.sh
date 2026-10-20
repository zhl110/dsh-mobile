#!/usr/bin/env bash
# scripts/dsh-voice-picker-probe.sh —— 只读地查两件事：
#   甲）「添加工作区 → 选择工作区目录」那一屏为什么是空的：目录选择器默认从哪个路径开始列、
#       那个路径下到底有没有子目录、手机存储在 chroot 里挂在哪。
#   乙）「语音输入」插件要下载的那个模型是什么、写在哪、是不是必须下载（还是能走云端）。
#
# 全程只读：只 grep 已装好的包、只 POST 列表类接口（list/describe），不写盘、不改配置。
# 口令红线：值只从 /root/.dsh/entry.key 读进变量、经 stdin 交给 curl -K -，不进 argv、不进输出。
set -u

PKGROOT=""
echo "=== 0. 包装在哪 ==="
for d in /usr/local/lib/node_modules/@deepseek-ai /usr/lib/node_modules/@deepseek-ai; do
  [ -d "$d" ] && echo "在位: $d  ($(ls "$d" | wc -l) 个包)" && PKGROOT=$d
done
[ -d "$PKGROOT" ] || { echo "找不到 @deepseek-ai 目录，后面的 grep 全免了"; exit 1; }

echo "=== 1. 目录选择器的实现文件 ==="
grep -rl "directoryPicker" "$PKGROOT" 2>/dev/null | head -6

echo "=== 2. 默认根路径与列表逻辑（挑含 directoryPicker 的行，只打前 240 字符）==="
grep -rhoE ".{0,120}directoryPicker.{0,120}" "$PKGROOT" 2>/dev/null | head -8
echo "--- 找 defaultRoot / home 之类 ---"
grep -rhoE ".{0,80}(defaultPath|initialPath|defaultRoot|homeDir|os\.homedir)[^,;]{0,80}" "$PKGROOT" 2>/dev/null | head -10

echo "=== 3. chroot 里几个候选路径的实际内容 ==="
for p in / /root /phone /phone/Download /root/storage; do
  printf '%-16s ' "$p"
  if [ -d "$p" ]; then
    echo -n "在，子目录: "
    ls -1 "$p" 2>/dev/null | head -8 | tr '\n' ' '
    echo "(共 $(ls -1 "$p" 2>/dev/null | wc -l) 项)"
  else
    echo "不存在"
  fi
done

echo "=== 4. 真打一次接口：列 / 、列 /phone、不带 path 各一次 ==="
KEY=$(cat /root/.dsh/entry.key 2>/dev/null)
[ -n "$KEY" ] || { echo "读不到口令，这一节跳过"; exit 1; }
call() {
  # 口令经 stdin 交给 `curl -K -`：不进 argv（ps 看得见）、不落盘（不留可被读的临时件）、不打印。
  printf 'cookie = dsh-entry=%s\n' "$KEY" | curl -sS -m 6 -K - -X POST -H 'content-type: application/json' \
    -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
    -d "$1" http://127.0.0.1:3081/api/directoryPicker/list 2>&1 | head -c 420
  printf '\n'
}
echo "--- 不带 path ---"; call '{}'
echo "--- path=/ ---";    call '{"path":"/"}'
echo "--- path=/phone ---"; call '{"path":"/phone"}'
unset KEY

echo "=== 5. 语音输入：模型从哪来 ==="
grep -rlE "语音输入|voiceInput|voice-input" "$PKGROOT" 2>/dev/null | head -6
echo "--- 下载相关的行（URL / 文件名 / 大小）---"
grep -rhoE ".{0,60}(silero|whisper|vad|asr|sherpa|onnx|\.bin|modelUrl|downloadModel)[^\"',;]{0,90}" "$PKGROOT" 2>/dev/null | head -14
echo "=== 完 ==="
