#!/usr/bin/env bash
# scripts/dsh-voice-picker-probe4.sh —— 把上一轮没问完的三件问死（只读 + 最多两发 HEAD，不下载任何字节）：
#   甲）目录选择器**按对的信封**（method 与 payload 都在顶层）列 /root 与 /phone 各一次 —— 直接看它给不给手机里的文件夹；
#   乙）SenseVoice 要下的那几个文件的**名字/字节数/来源仓库/修订**；
#   丙）麦克风这一侧：页面到底调不调 getUserMedia；
#   丁）那两个下载源从这台机**通不通**（只发 HEAD，量状态码与耗时，不取正文）。
# 口令红线：值只从 /root/.dsh/entry.key 读进变量、经 stdin 交给 curl -K -，不进 argv、不进输出。
set -u
P=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai
SV=$P/dsh-experimental-speech-to-text-sensevoice/lib/index.js

echo "=== 1. 选择器：按对的信封列两次 ==="
KEY=$(cat /root/.dsh/entry.key 2>/dev/null)
[ -n "$KEY" ] || { echo "读不到口令，跳过 1 与 4"; }
if [ -n "$KEY" ]; then
call() {
  printf 'cookie = dsh-entry=%s\n' "$KEY" | curl -sS -m 8 -K - -X POST -H 'content-type: application/json' \
    -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p4-$2\",\"method\":\"list\",\"payload\":$1}" \
    http://127.0.0.1:3081/api/directoryPicker/list 2>&1 | head -c 900
  printf '\n'
}
echo "--- 不带 path（= 它说的 home）---"; call '{}' np
echo "--- path=/root ---";               call '{"path":"/root"}' root
echo "--- path=/phone ---";              call '{"path":"/phone"}' phone
fi
unset KEY

echo "=== 2. SenseVoice 的资产清单（名字 / 字节 / 仓库 / 修订）==="
grep -oE '(name|bytes|sha256|repo|revision|path|file|huggingface[^"]*)"?[:=]"?[^",}]{1,70}' "$SV" 2>/dev/null | head -24
echo "--- 直接找那几个文件名 ---"
grep -oE '[A-Za-z0-9._/-]{3,60}\.(onnx|txt|bin)' "$SV" 2>/dev/null | sort -u | head -12
echo "--- 默认源 ---"
grep -oE 'https?://[a-z0-9.-]{4,40}' "$SV" 2>/dev/null | sort -u | head -6
echo "--- 总量：把这些字节数加起来 ---"
grep -oE 'bytes: *[0-9]+' "$SV" 2>/dev/null | awk -F'[: ]+' '{s+=$2; n++} END {printf "%d 个文件，合计 %d 字节 = %.1f MB\n", n, s, s/1048576}'

echo "=== 3. 麦克风：getUserMedia 在哪 ==="
grep -rl "getUserMedia" "$P" 2>/dev/null | head -6
grep -rho "getUserMedia.\{0,60\}" "$P" 2>/dev/null | head -4

echo "=== 4. 下载源通不通（只 HEAD，不取正文）==="
for host in https://huggingface.co https://hf-mirror.com; do
  code=$(curl -s -o /dev/null -m 6 -w '%{http_code} %{time_total}s' -I "$host" 2>&1)
  echo "$host -> $code"
done
echo "=== 完 ==="
