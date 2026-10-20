#!/system/bin/sh
# scripts/dsh-voice-picker-probe11.sh —— 收尾三条读数：
#   ① models 那层里有没有文件（选择器默认只列目录，所以这里同时试 includeFiles 这种参数，
#      参不成就看它报的错误里有没有列出可用字段）；
#   ② 上一发存下来的插件清单（/data/local/tmp/p9-plugins.json）里，语音这几条的完整字段；
#   ③ 页面引插件脚本的 URL 到底是什么形状（index.html 里那句带 &rev=，我上一发把 rev 丢了所以抓到 0 B）。
set -u
K=/data/local/tmp/p7.key
B=http://127.0.0.1:3081
MV=/root/.dsh/speech-to-text/sensevoice/models

pl() {  # $1=args
  curl -s -m 12 -K "$K" -X POST -H 'content-type: application/json' \
    -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p11\",\"method\":\"directoryPicker/list\",\"payload\":{\"args\":$1}}" \
    "$B/api/directoryPicker/list" 2>&1 | head -c 700; printf '\n'
}
printf '=== ①-1 只给 path（默认只列目录）===\n'; pl "{\"path\":\"$MV\"}"
printf '\n=== ①-2 加 includeFiles ===\n'; pl '{"path":"/root","includeFiles":true}'
printf '\n=== ①-3 加 files ===\n';        pl '{"path":"/root","files":true}'
printf '\n=== ①-4 参数名错了它会怎么说（拿一个明显错的键）===\n'; pl '{"path":"/root","zzz":1}'

printf '\n=== ② 插件清单里语音这几条的完整字段（原文，截 2400 字节）===\n'
if [ -s /data/local/tmp/p9-plugins.json ]; then
  printf '  文件 %s B\n' "$(wc -c </data/local/tmp/p9-plugins.json)"
  printf '  顶层形状前 160 B：'; head -c 160 /data/local/tmp/p9-plugins.json; printf '\n'
  printf '  带 voice/speech 的那几条：\n'
  grep -oE '\{"entryId":"include:[^}]*(voice|speech|Voice|Speech)[^{}]*\}?\}' /data/local/tmp/p9-plugins.json 2>/dev/null | head -6
  printf '  -- 里面出现过的 URL/路径字段名 --\n'
  grep -oE '"(client|entry|asset|assets|url|rev|version|manifest)":' /data/local/tmp/p9-plugins.json 2>/dev/null | sort | uniq -c | head -12
else
  printf '  p9-plugins.json 不在了（重抓一发）\n'
fi

printf '\n=== ③ index.html 里那条插件 URL 的原样 + 三种带 rev 的取法各多少字节 ===\n'
REV=$(grep -oE 'rev=[0-9a-f]{6,}' /data/local/tmp/p9-index.html 2>/dev/null | head -1 | cut -d= -f2)
printf '  （本地没有 p9-index.html 时 REV 为空：%s）\n' "${REV:-空}"
for u in "/plugins/??@deepseek-ai/dsh-client-modules/client.js&rev=${REV:-8254dd338a14}" \
         "/plugins/??@deepseek-ai/dsh-experimental-client-ui-voice-input/lib/client.js&rev=${REV:-8254dd338a14}"; do
  printf '  %-88s ' "$(printf %s "$u" | cut -c1-88)"
  curl -s -m 15 -g --noproxy '*' -K "$K" -o /dev/null -w 'http=%{http_code} bytes=%{size_download}\n' "$B$u" 2>&1
done
