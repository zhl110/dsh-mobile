#!/usr/bin/env bash
# scripts/dsh-voice-picker-probe3.sh —— 把上一轮差一步的三件事问死（全程只读）：
#   甲）目录选择器"不带 path 就列 home"这句话在**我们这台机上**具体指哪个目录（读引擎进程的 HOME），
#       以及按对的信封（payload，不是 params）真列一次 /phone，看它给不给手机里的文件夹；
#   乙）SenseVoice 那套要下哪几个文件、多大、落到哪个 dataRoot、现在下没下；
#       以及跑它要的 sherpa-onnx 原生件在 arm64 chroot 里到底有没有；
#   丙）页面拿麦克风走的是不是 getUserMedia（决定壳要不要补 RECORD_AUDIO + onPermissionRequest）。
# 口令红线：值只从 /root/.dsh/entry.key 读进变量、经 stdin 交给 curl -K -，不进 argv、不进输出。
set -u
P=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai

echo "=== 1. 引擎进程眼里的家目录与工作目录 ==="
for pid in 17637 17611; do
  if [ -r /proc/$pid/environ ]; then
    printf 'pid %s: ' "$pid"
    tr '\0' '\n' < /proc/$pid/environ | grep -E '^(HOME|PWD|USER)=' | tr '\n' ' '
    printf '| 该家目录下子目录数: '
    H=$(tr '\0' '\n' < /proc/$pid/environ | sed -n 's/^HOME=//p' | head -1)
    [ -d "$H" ] && find "$H" -maxdepth 1 -type d | wc -l || echo -n "目录不存在"
    printf '，文件数: '
    [ -d "$H" ] && find "$H" -maxdepth 1 -type f | wc -l || echo -n "-"
    printf '\n'
  else
    echo "pid $pid 的 environ 读不到（可能已换进程）"
  fi
done

echo "=== 2. 按对的信封列一次（payload 而不是 params）==="
KEY=$(cat /root/.dsh/entry.key 2>/dev/null)
[ -n "$KEY" ] || { echo "读不到口令，跳过"; exit 1; }
call() {
  printf 'cookie = dsh-entry=%s\n' "$KEY" | curl -sS -m 8 -K - -X POST -H 'content-type: application/json' \
    -H 'origin: http://127.0.0.1:3081' -H 'referer: http://127.0.0.1:3081/' \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p3-$2\",\"payload\":{\"method\":\"list\",\"params\":$1}}" \
    http://127.0.0.1:3081/api/directoryPicker/list 2>&1 | head -c 600
  printf '\n'
}
echo "--- payload{method:list,params:{}} ---";        call '{}' np
echo "--- payload{method:list,params:{path:/phone}} ---"; call '{"path":"/phone"}' phone
echo "--- 上面若还报形状错，就把网关那边认的字段名找出来 ---"
grep -rhoE ".{0,70}(client-request|ClientRequestSchema)[^;]{0,90}" "$P/dsh-client-connection/lib" 2>/dev/null | head -6
unset KEY

echo "=== 3. SenseVoice 要下什么、落到哪、下没下 ==="
grep -rhoE ".{0,40}(SenseVoice|silero|sherpa)[^\"']{0,70}" "$P/dsh-experimental-speech-to-text-sensevoice/lib" 2>/dev/null | head -8
echo "--- 文件清单/大小/校验（找 modelFiles 之类）---"
grep -rn -A2 -E "modelFiles|fileName|sizeBytes|sha256" "$P/dsh-experimental-speech-to-text-sensevoice/lib" 2>/dev/null | head -24
echo "--- dataRoot：voice-input-bundle 给的绝对路径 ---"
grep -rhoE ".{0,60}(dataRoot|voice-input)[^\"';]{0,70}" "$P"/dsh-experimental-speech-to-text-sensevoice/lib 2>/dev/null | head -8
echo "--- 现在盘上下了没 ---"
for d in /root/.dsh /root/.cache /root/.local/share; do
  echo "[$d]"; ls -1 "$d" 2>/dev/null | head -8
done
du -sh /root/.dsh/* 2>/dev/null | head -8
echo "--- sherpa-onnx 原生件在不在（arm64 linux）---"
ls -d "$P"/dsh/node_modules/sherpa-onnx* "$P"/sherpa-onnx* /usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/sherpa-onnx* 2>/dev/null | head -6
find /usr/local/lib/node_modules/@deepseek-ai -maxdepth 4 -iname "*sherpa*" 2>/dev/null | head -8

echo "=== 4. 麦克风：getUserMedia 在哪一侧 ==="
grep -rlE "getUserMedia|mediaDevices" "$P" 2>/dev/null | head -8
grep -rhoE ".{0,45}getUserMedia.{0,60}" "$P" 2>/dev/null | head -5
echo "=== 完 ==="
