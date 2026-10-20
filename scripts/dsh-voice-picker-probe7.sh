#!/system/bin/sh
# scripts/dsh-voice-picker-probe7.sh —— 不靠 root 的那条路：从设备本机的 curl 直接打入口 :3081。
# 目的两件：① 把 directoryPicker/list 的信封形状试对（上一轮卡在 "exactly one plain-object args field"）；
#           ② 从页面自己那份 client 代码里读它到底怎么调这个接口，别让我猜。
# 口令红线：值只从 /data/local/tmp/p7.key（0600、shell 自己所有、用完即删）读进 curl -K 的配置，
#          不进 argv、不打印、不进本脚本的任何输出。
set -u
K=/data/local/tmp/p7.key
B=http://127.0.0.1:3081
say() { printf '%s\n' "$*"; }

say "=== 1. 页面那份 client 里到底有没有 directoryPicker（先找调用方，不猜形状）==="
for u in "/plugins/??@deepseek-ai/dsh-client-modules/client.js" "/assets/vendor-DcuzkuQH.js"; do
  n=$(curl -s -m 20 -K "$K" "$B$u" 2>/dev/null | wc -c)
  say "  $u → $n B"
done
say "--- 直接抓 client-modules 那份，grep 选择器相关 ---"
curl -s -m 20 -K "$K" "$B/plugins/??@deepseek-ai/dsh-client-modules/client.js" >/data/local/tmp/p7-cm.js 2>/dev/null
say "  抓到 $(wc -c </data/local/tmp/p7-cm.js) B"
grep -oE '.{0,80}(directoryPicker|DirectoryPicker|pickDirectory).{0,120}' /data/local/tmp/p7-cm.js 2>/dev/null | head -4
say "  （上面为空 ⇒ 这个 bundle 里没有选择器代码，形状只能靠 2 的读数）"

say
say "=== 2. 信封形状：一次只改一处，错误原文照打（截 220 字节）==="
try() {
  printf '%-46s ' "$1"
  body=$(curl -s -m 10 -K "$K" -X POST -H 'content-type: application/json' \
    -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p7-$2\",\"method\":\"$3\",\"payload\":$4}" \
    "$B/api/$3" 2>&1 | head -c 220)
  printf '%s\n' "$body"
}
# 用同一个配置文件走口令：把 -K - 换成 -K $K，下面每条都读同一个 0600 文件
try 'payload={"path":"/root"}' a '"directoryPicker/list"' '{"path":"/root"}'
try 'payload={"args":{"path":"/root"}}' b '"directoryPicker/list"' '{"args":{"path":"/root"}}'
try 'payload={"args":{}}' c '"directoryPicker/list"' '{"args":{}}'
try 'payload={"list":{"path":"/root"}}' d '"directoryPicker/list"' '{"list":{"path":"/root"}}'
try 'payload={"path":"/phone"}' e '"directoryPicker/list"' '{"path":"/phone"}'

say
say "=== 3. 从入口自述里读最近这几发的返回码（它只报方法名与码，不报内容）==="
curl -s -m 8 -K "$K" "$B/__entry_status" 2>&1 | sed -n '1,6p;/请求流水/,/^  GET/p' | head -14

say
say "=== 4. 引擎家目录这件事换个问法：不带 path 的那一发返回里有没有 home 字段 ==="
curl -s -m 10 -K "$K" -X POST -H 'content-type: application/json' \
  -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
  -d '{"type":"client-request","rpcId":"p7-f","method":"directoryPicker/list","payload":{"args":{}}}' \
  "$B/api/directoryPicker/list" 2>&1 | head -c 900
say ""
say "=== 完 ==="
