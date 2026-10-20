#!/usr/bin/env bash
# scripts/dsh-voice-picker-probe2.sh —— 接上一版没问完的三件事（全程只读）：
#   甲）目录选择器**默认从哪个路径开始列**、是不是只列目录（/root 下真没有子目录 ⇒ 空屏的最直接解释）；
#   乙）语音输入那个插件到底要下什么模型、多大、落到哪、是不是必须下载；
#   丙）页面拿麦克风走的是不是 getUserMedia（决定"壳要不要补权限"）。
# 上一版把接口打错了形状（要 client-request 信封），这版按信封打。
# 口令红线：值只从 /root/.dsh/entry.key 读进变量、经 stdin 交给 curl -K -，不进 argv、不进输出。
set -u
P=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai

echo "=== 1. 选择器：默认根与过滤逻辑 ==="
grep -nE "defaultRoot|mkdtemp|homedir|readdir|withFileTypes|isDirectory|kind === 'directory'" \
  "$P/dsh-api-workspace-controller/lib/types/directory-picker.js" 2>/dev/null | head -18
echo "--- 这个文件里 capability / roots 那几行 ---"
grep -nE "capability|roots|startPath|home" "$P/dsh-api-workspace-controller/lib/types/directory-picker.js" 2>/dev/null | head -12

echo "=== 2. 按对的信封真打一次 ==="
KEY=$(cat /root/.dsh/entry.key 2>/dev/null)
[ -n "$KEY" ] || { echo "读不到口令，跳过"; exit 1; }
call() {
  body="{\"type\":\"client-request\",\"rpcId\":\"probe-$1\",\"method\":\"list\",\"params\":{\"path\":\"$1\"}}"
  printf 'cookie = dsh-entry=%s\n' "$KEY" | curl -sS -m 6 -K - -X POST -H 'content-type: application/json' \
    -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
    -d "$body" http://127.0.0.1:3081/api/directoryPicker/list 2>&1 | head -c 700
  printf '\n'
}
echo "--- 不带 path（看它默认给哪）---"
printf 'cookie = dsh-entry=%s\n' "$KEY" | curl -sS -m 6 -K - -X POST -H 'content-type: application/json' \
  -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
  -d '{"type":"client-request","rpcId":"probe-np","method":"list","params":{}}' \
  http://127.0.0.1:3081/api/directoryPicker/list 2>&1 | head -c 700; printf '\n'
echo "--- path=/root ---";  call /root
echo "--- path=/phone ---"; call /phone
unset KEY

echo "=== 3. 语音插件要下什么 ==="
ls "$P" | grep -i speech
for f in "$P"/dsh-experimental-speech-to-text-sensevoice/README.zh.md "$P"/dsh-experimental-speech-to-text/README.md; do
  echo "----- $f -----"
  head -46 "$f" 2>/dev/null
done

echo "=== 4. 麦克风：页面走的是不是 getUserMedia ==="
grep -rlE "getUserMedia|mediaDevices" "$P"/dsh-experimental-speech-to-text* "$P"/dsh-client-ui-plugin-manager 2>/dev/null | head -5
grep -rhoE ".{0,50}getUserMedia.{0,70}" "$P" 2>/dev/null | head -4
echo "=== 完 ==="
