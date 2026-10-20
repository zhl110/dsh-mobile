#!/bin/bash
# scripts/dsh-voice-picker-probe15.sh —— 把上一发那个"连不上"钉死成可执行的结论，全只读。
#   ① huggingface.co 拿到的是一个 IPv6（2a03:2880… 那串是脸书段的形状），这台机的路由表里只有
#      rmnet_data4 一条 IPv4 ⇒ 怀疑是"解析给了一条走不通的地址"而不是"域名被墙"。判据：
#      getent ahostsv4 有没有 v4 答案、/etc/hosts 里有没有它的行、ip -6 route 有没有默认路由、
#      强制 -4 再 HEAD 一次（还是 0 字节 body）。
#   ② 那个 SenseVoice 插件自己写的下载地址与"识别服务"选项长什么样 —— 直接读装在盘上的那份代码，
#      不猜 method 名（14 那一发猜了五个，全 not found，那五个读数只能证明"我没读到它的真名"）。
# 红线：口令不进 argv、不打印；不下载任何模型字节；本文件跑完由外部 rm 掉。
set -u
B=http://127.0.0.1:3081

echo "=== ① 解析与路由的形状 ==="
echo "  nsswitch hosts 行：$(grep '^hosts:' /etc/nsswitch.conf 2>/dev/null)"
echo "  /etc/hosts 里含 huggingface/hf 的行：$(grep -icE 'huggingface|hf-' /etc/hosts 2>/dev/null) 行"
grep -inE 'huggingface|hf-' /etc/hosts 2>/dev/null | sed 's/^/      /'
echo "  已钉住的行数与头三条："
grep -vE '^\s*#|^\s*$' /etc/hosts 2>/dev/null | head -3 | sed 's/^/      /'
for h in huggingface.co hf-mirror.com cdn-lfs.huggingface.co cdn-lfs-us-1.huggingface.co; do
  v4=$(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1; exit}')
  all=$(getent hosts "$h" 2>/dev/null | awk '{print $1; exit}')
  printf '  %-32s v4=%-16s 首选=%s\n' "$h" "${v4:-无}" "${all:-查不到}"
done
echo "  ip -6 route 前 3 行："; ip -6 route 2>/dev/null | head -3 | sed 's/^/      /' || echo '      （没有 ip 命令）'
echo "  强制 IPv4 再 HEAD（0 字节 body）："
for h in huggingface.co hf-mirror.com; do
  printf '      %-22s -> %s\n' "$h" "$(curl -4 -s -o /dev/null -m 12 -w '%{http_code} ip=%{remote_ip} err=%{errormsg}' "https://$h" 2>&1 || echo 连不上)"
done

echo
echo "=== ② 装在盘上的语音那几份包，它们自己写的地址与选项 ==="
for d in /usr/local/lib/node_modules/@deepseek-ai /root/.dsh/plugins /root/.dsh/patches; do
  printf '  %s -> ' "$d"
  if [ -d "$d" ]; then
    printf '在位，%s 个条目，语音相关：\n' "$(ls -A "$d" | wc -l)"
    ls "$d" 2>/dev/null | grep -iE 'speech|voice|asr|audio' | sed 's/^/      /'
  else
    printf '不存在\n'
  fi
done
echo
echo "  这些包里出现的下载地址（原样抄，最多 12 条）："
grep -rhoE 'https?://[A-Za-z0-9._~%/-]+' /usr/local/lib/node_modules/@deepseek-ai/*speech*/lib/*.js /usr/local/lib/node_modules/@deepseek-ai/*speech*/*.js 2>/dev/null \
  | grep -viE 'deepseek\.com|github\.com|localhost|npmjs|registry' | sort -u | head -12 | sed 's/^/      /'
echo "  里面跟"模型/下载/文件大小"有关的原文行（挑 12 行，判它要下什么、多大、下到哪）："
grep -rnoiE '.{0,60}(sensevoice|model_?id|filename|\.onnx|download|sha256|size|targetDir|cacheDir).{0,90}' /usr/local/lib/node_modules/@deepseek-ai/*speech* 2>/dev/null \
  | grep -vE '\.map:|node_modules/.*node_modules' | head -12 | cut -c1-190 | sed 's/^/      /'
echo "  识别服务可选项（它自己列出来的 provider / 服务名，原样抄）："
grep -rnoiE '.{0,40}(providers?|services?|engines?|recognizer)["a-zA-Z]*\s*[:=]\s*\[[^]]{0,200}' /usr/local/lib/node_modules/@deepseek-ai/*speech* 2>/dev/null | head -6 | cut -c1-200 | sed 's/^/      /'
