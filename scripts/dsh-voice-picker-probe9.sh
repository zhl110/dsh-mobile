#!/system/bin/sh
# scripts/dsh-voice-picker-probe9.sh —— 三条待验，全走 directoryPicker/list 与 pluginManager，只读：
#   ① 软链目录能不能"进去"：Ubuntu 24.04 的 /bin /lib /sbin 就是软链，直接 list /bin 看它给不给内容
#      （这条决定 DSHA 那条"往家目录塞一个指向存储的软链"在我们这儿成不成立）；
#   ② 语音插件那份模型缓存目录里到底有没有字节：/root/.dsh/speech-to-text；
#   ③ 插件清单里语音那条的状态与它自己报的要求（能不能不走本地模型）。
set -u
K=/data/local/tmp/p7.key
B=http://127.0.0.1:3081

call() {   # $1=method $2=args json $3=截断字节 $4=标签
  printf '\n--- %s ---\n' "$4"
  curl -s -m 12 -K "$K" -X POST -H 'content-type: application/json' \
    -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p9\",\"method\":\"$1\",\"payload\":{\"args\":$2}}" \
    "$B/api/$1" 2>&1 | head -c "$3"
  printf '\n'
}

call directoryPicker/list '{"path":"/bin"}' 700 '①-1 path=/bin（/bin 本身是 usr/bin 的软链）'
call directoryPicker/list '{"path":"/lib"}' 500 '①-2 path=/lib（usr.lib 的软链）'
call directoryPicker/list '{"path":"/root/.dsh/speech-to-text"}' 1200 '② 语音模型缓存目录里有什么'
call directoryPicker/list '{"path":"/root/.dsh/speech-to-text/models"}' 900 '②-2 里面的 models 一层（不存在就看错误原文）'

printf '\n--- ③ 插件清单：只把语音/模型相关的字段挑出来 ---\n'
curl -s -m 15 -K "$K" -X POST -H 'content-type: application/json' \
  -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
  -d '{"type":"client-request","rpcId":"p9p","method":"pluginManager/listPlugins","payload":{"args":{}}}' \
  "$B/api/pluginManager/listPlugins" 2>&1 > /data/local/tmp/p9-plugins.json
printf '  返回 %s B\n' "$(wc -c </data/local/tmp/p9-plugins.json)"
printf '  插件总条数（按 "id" 出现次数粗算）：%s\n' "$(grep -o '"id":' /data/local/tmp/p9-plugins.json | wc -l)"
printf '  语音那几条原文（截 1600 字节）：\n'
grep -oE '.{0,120}(voice|speech|Voice|Speech|sensevoice|SenseVoice|asr|ASR).{0,220}' /data/local/tmp/p9-plugins.json 2>/dev/null | head -8
