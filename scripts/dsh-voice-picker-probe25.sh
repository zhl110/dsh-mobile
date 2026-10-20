#!/bin/bash
# scripts/dsh-voice-picker-probe25.sh —— 只读：把 speech/transcribe 这条 RPC 的**参数描述符**从代码里挖出来。
# 上一发（p24）被判 wire field "request" failed boundary validation，说明我猜的 audio 形状不对
# （我按 base64 字符串送的）。不猜第二发 —— 直接 grep 出定义它的那几行，看它要什么类型。
# 只 grep、只读文件，不发 RPC、不写盘。口令不参与。
set -u
ROOT=/usr/local/lib/node_modules/@deepseek-ai
echo "== 1. 哪些文件里定义/声明了 speech 这些端点"
grep -rl "speech/transcribe" "$ROOT" --include=*.js 2>/dev/null | head -10
echo
echo "== 2. transcribe 那条描述符附近（含 audio 类型）：逐文件打上下文"
for f in $(grep -rl "speech/transcribe" "$ROOT" --include=*.js 2>/dev/null | head -6); do
  echo "--- $f"
  grep -n "speech/transcribe" "$f" | head -5
  for ln in $(grep -n "speech/transcribe" "$f" | cut -d: -f1 | head -3); do
    echo "  [上下文 $ln]"
    sed -n "$((ln>40?ln-40:1)),$((ln+25))p" "$f" | sed 's/^/    /'
  done
done
echo
echo "== 3. 语音那侧 audio 的声明（在 speech-to-text 包里找 audio 附近的 z./typert 关键字）"
grep -rn "audio" "$ROOT"/dsh/node_modules/@deepseek-ai/dsh-experimental-speech-to-text*/lib/*.js 2>/dev/null | head -20
