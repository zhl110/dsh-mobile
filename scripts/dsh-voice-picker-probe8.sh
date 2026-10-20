#!/system/bin/sh
# scripts/dsh-voice-picker-probe8.sh —— 上一发把信封试对了（payload:{"args":{...}}），这一发只问三件事：
#   ① 选择器把「软链接指向的目录」算不算可点的目录（Ubuntu 的 /bin /lib /sbin 天然就是软链，
#      拿它们做自然实验，不用我为了验证去建任何东西）；
#   ② /phone 那棵树列得出来吗、能进到他的真实文件夹吗；
#   ③ 不带 path 与带 path 返回的 home 字段各是什么。
# 全程只读：只调 directoryPicker/list，一个字节都不写。口令走 0600 的 /data/local/tmp/p7.key，不进 argv。
set -u
K=/data/local/tmp/p7.key
B=http://127.0.0.1:3081

ask() {   # $1 = args JSON（可以空），$2 = 标签
  printf '\n--- %s ---\n' "$2"
  curl -s -m 12 -K "$K" -X POST -H 'content-type: application/json' \
    -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p8\",\"method\":\"directoryPicker/list\",\"payload\":{\"args\":${1}}}" \
    "$B/api/directoryPicker/list" 2>&1 | head -c "${3:-1500}"
  printf '\n'
}

ask '{}'                       '不带 path（这就是他点开「选择工作区目录」时看到的那一发）' 900
ask '{"path":"/"}'             'path=/ —— 这里的 bin/lib/sbin/proc 都是软链，看它们算不算目录' 1800
ask '{"path":"/phone"}'        'path=/phone（手机存储 bind 进来的那棵树）' 1800
ask '{"path":"/phone/Download"}' 'path=/phone/Download（他真实文件夹能不能进去）' 700
ask '{"path":"/root/.dsh"}'    'path=/root/.dsh（隐藏目录能不能直接进）' 700

printf '\n=== 选择器这套接口还有没有别的方法（list 之外）===\n'
for m in directoryPicker/home directoryPicker/roots directoryPicker/recent directoryPicker/stat; do
  printf '%-26s ' "$m"
  curl -s -m 8 -K "$K" -X POST -H 'content-type: application/json' \
    -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p8m\",\"method\":\"$m\",\"payload\":{\"args\":{}}}" \
    "$B/api/$m" 2>&1 | head -c 180
  printf '\n'
done
