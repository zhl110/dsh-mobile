#!/bin/bash
# scripts/dsh-voice-picker-probe16.sh —— 只干一件事：把语音那两套包自己注册的 RPC 方法名抄出来，
# 好让"模型放对之后插件判不判得过"这件事能用一次调用读到，而不是只能靠他手动开关插件去猜。
# （前一版我在命令行上猜了五个名字，五个全 not found —— 那五个读数只能证明我没读到真名，见 14.20 ④。）
# 全只读；跑完由外部 rm 掉。
set -u
P=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai
for pkg in dsh-experimental-speech-to-text dsh-experimental-voice-input-bundle dsh-experimental-api-speech-to-text dsh-experimental-client-ui-voice-input; do
  echo "=== $pkg ==="
  [ -d "$P/$pkg" ] || { echo "  （包不在位）"; continue; }
  # 方法名在这些包里是 "名字空间/动词" 这种带斜杠的字符串；先把带斜杠的字面量全捞出来再去重
  grep -rhoE '"[a-zA-Z][a-zA-Z]*\/[a-zA-Z][a-zA-Z]*"' "$P/$pkg/lib" 2>/dev/null \
    | tr -d '"' | grep -vE '^(https|http|node|npm|text|application|image|audio|video|utf-8|X-PINGOTHER|multipart)' \
    | sort | uniq -c | sort -rn | head -14 | sed 's/^/  /'
done
echo
echo "=== 缓存这三份现在长什么样（chroot 视角，插件 access() 的就是这几个路径）==="
for f in models/sensevoice-onnx/model.int8.onnx models/sensevoice-onnx/tokens.txt models/silero/silero_vad.onnx; do
  p=/root/.dsh/speech-to-text/sensevoice/$f
  if [ -f "$p" ]; then
    printf '  %-58s %12s B  sha=%s\n' "$f" "$(wc -c <"$p")" "$(sha256sum "$p" | cut -c1-16)"
  else
    printf '  %-58s 不在\n' "$f"
  fi
done
