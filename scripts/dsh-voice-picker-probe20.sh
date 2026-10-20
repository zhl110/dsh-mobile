#!/bin/bash
# scripts/dsh-voice-picker-probe20.sh —— 只读，为回答一个问题：
#   三份文件已经按清单推到盘上了，插件自己会不会重新认它？
# 靠猜不行，得看宿主侧那段代码：preparation 这个状态存在哪、是不是每次 catalog/prepare 都重新 access()+校验，
# 还是把上一次失败的记录原样返回。
# 本脚本只 grep 与 ls，不发 RPC、不写盘。口令不参与。
set -u
ROOT=/usr/local/lib/node_modules/@deepseek-ai
echo "== 1. 哪些文件里出现 Unable to prepare / SenseVoiceSmall（宿主侧逻辑在哪）"
grep -rl "Unable to prepare\|SenseVoiceSmall" "$ROOT" --include=*.js 2>/dev/null | head -20

echo
echo "== 2. 语音那块的宿主数据目录里到底有什么（除了我推的 models）"
ls -lR /root/.dsh/speech-to-text 2>&1 | head -40

echo
echo "== 3. 有没有状态文件（preparation 若落盘，这里会有 json）"
find /root/.dsh -maxdepth 4 -name "*.json" -printf "%s %p\n" 2>/dev/null | head -20
