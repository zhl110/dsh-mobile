#!/system/bin/sh
# scripts/dsh-voice-picker-probe10.sh —— 两件：
#   ① 语音模型那份目录里到底有没有字节（上一发只看到 sensevoice 这一层存在）；
#   ② 把页面里"录音输入"那个插件的 client.js 抓下来，读它到底调哪几个接口、是不是真用 getUserMedia。
#      —— 上一发我试 /plugins/??@... 抓到 0 B，所以这里一次试三种 URL 形状，认哪个给字节。
set -u
K=/data/local/tmp/p7.key
B=http://127.0.0.1:3081

printf '=== 1. sensevoice 那层里有什么 ===\n'
curl -s -m 12 -K "$K" -X POST -H 'content-type: application/json' \
  -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
  -d '{"type":"client-request","rpcId":"p10","method":"directoryPicker/list","payload":{"args":{"path":"/root/.dsh/speech-to-text/sensevoice"}}}' \
  "$B/api/directoryPicker/list" 2>&1 | head -c 1200
printf '\n'

printf '\n=== 2. 三种 URL 形状各给多少字节 ===\n'
for u in "/plugins/??@deepseek-ai/dsh-experimental-client-ui-voice-input/lib/client.js" \
         "/plugins/?@deepseek-ai/dsh-experimental-client-ui-voice-input/lib/client.js" \
         "/plugins/@deepseek-ai/dsh-experimental-client-ui-voice-input/lib/client.js"; do
  n=$(curl -s -m 15 -g --noproxy '*' -K "$K" "$B$u" 2>/dev/null | wc -c)
  printf '  %-84s → %s B\n' "$(printf %s "$u" | cut -c1-84)" "$n"
done
printf '--- 用第一个形状抓下来存文件 ---\n'
curl -s -m 20 -g --noproxy '*' -K "$K" \
  "$B/plugins/??@deepseek-ai/dsh-experimental-client-ui-voice-input/lib/client.js" \
  >/data/local/tmp/p10-voice.js 2>/dev/null
printf '  存了 %s B 到 /data/local/tmp/p10-voice.js\n' "$(wc -c </data/local/tmp/p10-voice.js)"

printf '\n=== 3. 这份 client.js 里的三件事：getUserMedia / 调的接口名 / 有没有"下载模型"那句 ===\n'
printf -- "-- getUserMedia --\n"
grep -oE '.{0,90}getUserMedia.{0,110}' /data/local/tmp/p10-voice.js 2>/dev/null | head -3
printf -- "-- mediaDevices / audio 约束 --\n"
grep -oE 'mediaDevices.{0,80}|audio:[^,}]{0,40}' /data/local/tmp/p10-voice.js 2>/dev/null | head -4
printf -- "-- 它 POST 到哪些 api 方法（找 rpc method 字符串）--\n"
grep -oE '"(speech[A-Za-z]*|apiSpeech[A-Za-z]*|[a-zA-Z]+/[a-zA-Z]+)"' /data/local/tmp/p10-voice.js 2>/dev/null | sort -u | head -20
printf -- "-- 模型/下载相关字样 --\n"
grep -oE '.{0,60}(下载|模型|model|SenseVoice|sensevoice).{0,90}' /data/local/tmp/p10-voice.js 2>/dev/null | head -4
