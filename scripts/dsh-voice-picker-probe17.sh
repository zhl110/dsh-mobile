#!/bin/bash
# scripts/dsh-voice-picker-probe17.sh —— 用真名把"模型放对之后插件判不判得过"这一发读出来。
# 16 里从 …-client-ui-voice-input 包里抄到真名：speech/catalog、speech/prepare、speech/transcribe、
# speech/configure、speech/follow、speech/cancelPreparation。这一发只碰读的那两条（catalog 与 transcribe 的
# 参数形状，transcribe 只问一次不给音频、看它报什么形状的错误），**不调 prepare**（那是要它去下载的那条），
# 也不调 configure/cancel（那是写）。口令不进 argv、不打印；跑完由外部 rm 掉。
set -u
B=http://127.0.0.1:3081
K=$(tr -d '\r\n' < /root/.dsh/entry.key)
P=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-experimental-client-ui-voice-input

call() {  # $1=method $2=args json $3=标签
  printf '\n--- %s ---\n' "$3"
  printf 'cookie = dsh-entry=%s\n' "$K" | curl -s -m 20 -K - -X POST \
    -H 'content-type: application/json' -H "origin: $B" -H "referer: $B/" \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p17\",\"method\":\"$1\",\"payload\":{\"args\":$2}}" \
    "$B/api/$1" 2>&1 | head -c 1500
  printf '\n'
}

echo "=== 0. 这两个方法在包里的声明（原样抄上下文，判它要什么参数）==="
grep -n -A 3 'speech/catalog' "$P/lib/index.js" 2>/dev/null | head -14
grep -n -A 3 'speech/transcribe' "$P/lib/index.js" 2>/dev/null | head -10

call speech/catalog '{}' '① speech/catalog（不带参数）'
call speech/catalog '{"sessionId":""}' '② speech/catalog 带一个空 sessionId（看它怎么报参数不对）'
