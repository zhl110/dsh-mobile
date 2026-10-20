#!/bin/bash
# scripts/dsh-voice-picker-probe13.sh —— 落在 chroot 里跑（root），验两件事 + 顺手把两条待查读数取回来。
#   ① 家目录那条软链建好之后，「选择工作区目录」那一发（不带 path 的 directoryPicker/list）里
#      到底出没出现「手机存储」这一条、它带的是目录标记还是文件标记（这决定界面点不点得进去）；
#   ② 顺着这条软链进去列一次（path=/root/手机存储），他真实的 DCIM/Download 那层在不在。
#   ③ 语音那份模型的缓存目录里有没有字节（只看盘，绝不触发下载）。
#   ④ 出网能力：只发 HEAD，不取 body —— 这条是本轮唯一出网的动作，三发、body 0 字节。
#      为什么要问：插件要下载 SenseVoice 权重，得先知道这台机能不能碰到那两台站。
# 红线：入口口令只从 /root/.dsh/entry.key 读进变量、经 stdin 交给 curl -K -，不进 argv、不打印；
#       全程只读，除了我自己这份探针文件之外不落任何文件，跑完由外部 rm 掉。
set -u
B=http://127.0.0.1:3081
K=$(tr -d '\r\n' < /root/.dsh/entry.key)

call() {  # $1=method $2=args-json $3=截断字节 $4=标签
  printf '\n--- %s ---\n' "$4"
  printf 'cookie = dsh-entry=%s\n' "$K" | curl -s -m 15 -K - -X POST \
    -H 'content-type: application/json' -H "origin: $B" -H "referer: $B/" \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p13\",\"method\":\"$1\",\"payload\":{\"args\":$2}}" \
    "$B/api/$1" 2>&1 | head -c "$3"
  printf '\n'
}

echo "=== 0. 盘上那条链（宿主看到的形状）==="
ls -l /root | grep -E '手机存储|total' || echo '  （grep 没匹配到 —— 那这条链没建成）'
echo "  readlink = $(readlink /root/手机存储)"
echo "  /phone 顶层条目 = $(ls /phone 2>/dev/null | wc -l) 个"

call directoryPicker/list '{}' 900 '① 不带 path 那一发（= 引擎的 HOME，界面打开时看到的就是这一屏）'
call directoryPicker/list '{"path":"/root/手机存储"}' 1200 '② 顺着软链进去列一层'
call directoryPicker/list '{"path":"/root/手机存储/Download"}' 600 '②-2 再点进 Download 一层（他真往手机里放东西的地方）'

echo
echo "=== 3. 语音模型的盘上情况（只读，不触发下载）==="
for d in /root/.dsh/speech-to-text /root/.dsh/speech-to-text/models /root/.dsh/speech-to-text/models/sensevoice-onnx; do
  if [ -e "$d" ]; then
    printf '  %s  存在，条目 %s 个，占 %s KB\n' "$d" "$(ls -A "$d" 2>/dev/null | wc -l)" "$(du -sk "$d" 2>/dev/null | cut -f1)"
    ls -l "$d" 2>/dev/null | head -6 | sed 's/^/      /'
  else
    printf '  %s  不存在\n' "$d"
  fi
done

echo
echo "=== 4. 出网（三发 HEAD，body 0 字节）==="
for h in https://api.deepseek.com https://huggingface.co https://hf-mirror.com; do
  printf '  %-32s -> %s\n' "$h" "$(curl -sI -m 12 -o /dev/null -w 'http=%{http_code} body=%{size_download}B tls=%{time_total}s' "$h" 2>&1 || echo 连不上)"
done
