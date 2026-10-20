#!/usr/bin/env bash
# scripts/dsh-voice-picker-probe5.sh —— 两件：把目录选择器的返回真读出来；把"下载源不通"到底是
# 完全没网还是只有 HF 不通分开（这条直接决定语音那条路能不能修）。全程只读，最多几发 HEAD，不下字节。
# 口令红线：值只从 /root/.dsh/entry.key 读进变量、经 stdin 交给 curl -K -，不进 argv、不进输出。
set -u
P=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai
SV=$P/dsh-experimental-speech-to-text-sensevoice

echo "=== 1. 目录选择器：method 要写全名 ==="
KEY=$(cat /root/.dsh/entry.key 2>/dev/null)
if [ -n "$KEY" ]; then
call() {
  printf 'cookie = dsh-entry=%s\n' "$KEY" | curl -sS -m 8 -K - -X POST -H 'content-type: application/json' \
    -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p5-$2\",\"method\":\"directoryPicker/list\",\"payload\":$1}" \
    http://127.0.0.1:3081/api/directoryPicker/list 2>&1 | head -c 1200
  printf '\n'
}
echo "--- 不带 path ---";  call '{}' np
echo "--- path=/root ---"; call '{"path":"/root"}' root
echo "--- path=/phone ---"; call '{"path":"/phone"}' phone
fi
unset KEY

echo "=== 2. /root 里到底有什么（点开头的那些是关键：选择器一般不显示点目录）==="
ls -a /root | head -24
echo "--- 其中非点开头的目录：---"
find /root -maxdepth 1 -type d ! -name '.*' ! -path /root -printf '%f\n' | head -6
echo "(以上为空 ⇒ 从家目录出发一层都点不进去)"

echo "=== 3. SenseVoice 的文件清单（在整个包里找 .onnx / tokens.txt）==="
grep -rhoE '[A-Za-z0-9._/-]{2,60}\.(onnx|txt)' "$SV" 2>/dev/null | sort -u | head -12
grep -rhoE '(SenseVoiceSmall|speech_onnx|silero_vad|model_int8|model_fp32)[^"'"'"',;]{0,40}' "$SV" 2>/dev/null | sort -u | head -12
echo "--- 资产定义在哪个文件 ---"
grep -rln "sha256" "$SV" 2>/dev/null | head -6

echo "=== 4. 分清楚：这台机是彻底没外网，还是只有 HF 不通 ==="
for h in huggingface.co hf-mirror.com api.deepseek.com; do
  ip=$(getent hosts "$h" 2>/dev/null | head -1 | awk '{print $1}')
  printf '%-18s DNS=%-16s ' "$h" "${ip:-解不出}"
  curl -s -o /dev/null -m 6 -w 'HEAD=%{http_code} %{time_total}s\n' -I "https://$h" 2>&1 || echo "curl 失败"
done
echo "--- 引擎真在用的那条推理地址（他刚才聊通过，所以这条应当是通的）---"
grep -rhoE 'https://[a-z0-9.-]{4,40}' /root/.dsh/profiles 2>/dev/null | sort -u | head -5
echo "=== 完 ==="
