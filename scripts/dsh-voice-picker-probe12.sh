#!/system/bin/sh
# scripts/dsh-voice-picker-probe12.sh —— 引擎现在认的工作区根到底是哪（这条决定"塞一个软链进 /root"
# 是不是真的只是"看得见"而不是"多给了权限"）。只调读接口。
K=/data/local/tmp/p7.key; B=http://127.0.0.1:3081
q() { printf '\n--- %s ---\n' "$1"
  curl -s -m 10 -K "$K" -X POST -H 'content-type: application/json' \
    -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p12\",\"method\":\"$2\",\"payload\":{\"args\":$3}}" \
    "$B/api/$2" 2>&1 | head -c 900; printf '\n'; }
q 'workspace/list 不带参数' 'workspace/list' '{}'
q 'config/get 读 sandbox-policy 那一段' 'config/get' '{"key":"sandbox"}'
