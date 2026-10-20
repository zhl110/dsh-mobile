#!/bin/bash
# scripts/dsh-voice-picker-probe23.sh —— 只问一句：speech/transcribe 到底要哪些参数。
# 故意拿空 args 发一发，让网关自己把描述符要求念出来（arguments-invalid 里写着缺哪个键），
# 这比我照着别处的例子猜字段名硬。transcribe 缺音频必然被网关挡在门外，不会真跑识别。
# speech/configure 与 speech/follow 这轮**不问**：configure 是写（改的是他 App 里那份语音设置），
# follow 是订阅流；要拿它们的参数形状应该去读代码而不是空发，别为了少读几行代码去赌一次写。
# 口令只经 stdin 给 curl -K -，不进 argv、不打印。
set -u
B=http://127.0.0.1:3081
K=$(tr -d '\r\n' < /root/.dsh/entry.key)
for M in speech/transcribe; do
  echo "== $M"
  printf 'cookie = dsh-entry=%s\n' "$K" | curl -s -m 15 -K - -X POST \
    -H 'content-type: application/json' -H "origin: $B" -H "referer: $B/" \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p23\",\"method\":\"$M\",\"payload\":{\"args\":{}}}" \
    "$B/api/$M" 2>&1 | head -c 700
  echo; echo
done
