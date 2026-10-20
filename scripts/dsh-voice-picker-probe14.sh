#!/bin/bash
# scripts/dsh-voice-picker-probe14.sh —— 把 13 里那条"连不上"分清楚是哪一种连不上，再看那 14 KB 是什么。
#   ① huggingface.co / hf-mirror.com 是解析不到（这台机 53 端口出站被拦，靠 /etc/hosts 钉 IP，
#      没钉过的名字就查不到），还是解析到了但路由不通？两种"连不上"给他的做法完全不同：
#      前者补一条 hosts 就行，后者补不了。判据：getent 能不能给出地址 + curl 的 errormsg。
#   ② /root/.dsh/speech-to-text/sensevoice 那 14 KB 到底是配置还是权重碎片（只读盘，不动它）。
#   ③ 插件那边有没有"换识别服务"这条路（能选云端就不必非下载不可）：只读地试两个 method 名，
#      认不出来就原样把引擎的报错抄回来，不猜。
# 红线：口令不进 argv、不打印；全程只读；本文件跑完由外部 rm 掉。
set -u
B=http://127.0.0.1:3081
K=$(tr -d '\r\n' < /root/.dsh/entry.key)

echo "=== ① 名字解析 vs 路由 ==="
echo "  /etc/hosts 行数：$(wc -l < /etc/hosts)（钉过的那几台才解析得到）"
for h in api.deepseek.com huggingface.co hf-mirror.com cdn-lfs.hf-mirror.com; do
  ip=$(getent hosts "$h" 2>/dev/null | awk '{print $1; exit}')
  printf '  %-22s getent -> %s\n' "$h" "${ip:-查不到}"
done
for h in huggingface.co hf-mirror.com; do
  m=$(curl -s -o /dev/null -m 10 -w '%{http_code} %{errormsg}' "https://$h" 2>&1)
  printf '  %-22s curl  -> %s\n' "$h" "$m"
done
echo "  对照：这台机现在的默认路由与 DNS"
ip route 2>/dev/null | head -3 | sed 's/^/      /'
echo "  resolv.conf:"; sed 's/^/      /' /etc/resolv.conf 2>/dev/null | head -5
echo "  拿一个明文端口试出站（53 应该被拦）：$(timeout 6 sh -c 'exec 3<>/dev/tcp/223.5.5.5/53 && echo 53能连' 2>/dev/null || echo '53 连不上/超时')"
echo "  拿 443 试同一台：$(timeout 6 sh -c 'exec 3<>/dev/tcp/223.5.5.5/443 && echo 443能连' 2>/dev/null || echo '443 连不上/超时')"

echo
echo "=== ② 那 14 KB 是什么 ==="
find /root/.dsh/speech-to-text -maxdepth 3 -printf '%y %10s %p\n' 2>/dev/null | head -20
echo "  —— 逐个看头几个字节的形状（判它是 json/文本还是 onnx 权重）："
find /root/.dsh/speech-to-text -maxdepth 3 -type f 2>/dev/null | head -6 | while read -r f; do
  printf '      %s (%s B) 头: %s\n' "${f#/root/.dsh/speech-to-text/}" "$(wc -c <"$f")" "$(head -c 60 "$f" | tr -cd '\40-\176' | cut -c1-50)"
done

echo
echo "=== ③ 有没有'换识别服务'这条路（认不出来就抄报错原文）==="
call() {
  printf '  %s -> ' "$1"
  printf 'cookie = dsh-entry=%s\n' "$K" | curl -s -m 12 -K - -X POST \
    -H 'content-type: application/json' -H "origin: $B" -H "referer: $B/" \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p14\",\"method\":\"$1\",\"payload\":{\"args\":{}}}" \
    "$B/api/$1" 2>&1 | head -c 420
  printf '\n'
}
for m in speechToText/listProviders speechToText/status speechToText/getConfig sensevoice/status pluginManager/getPlugin; do
  call "$m"
done
