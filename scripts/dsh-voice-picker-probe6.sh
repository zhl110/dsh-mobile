#!/usr/bin/env bash
# scripts/dsh-voice-picker-probe6.sh —— 参照仓库给了两条待验的结论，这里只验它们：
#   甲 DSHA 那条「往 /root 建一个指向存储的软链」到底能不能让目录选择器列出来 ——
#       取决于选择器用的是 stat（跟软链）还是 lstat/dirent（不跟），所以要把它的列目录代码读死。
#   乙 上一轮被 head 截掉的那段出网读数（彻底没网 vs 只有 HF 不通），补上 api.deepseek.com 作对照。
# 全程只读：不建链、不写文件、不下字节。口令红线：值只从盘上读进变量、经 stdin 交 curl -K -，不进 argv、不进输出。
set -u
P=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai
WP=$P/dsh-api-workspace-controller
SV=$P/dsh-experimental-speech-to-text-sensevoice

echo "=== 1. 选择器列目录的代码：到底 stat 还是 lstat，跟不跟软链，过不过滤点目录 ==="
ls -la "$WP/lib/types/" 2>/dev/null | grep -i director | head -6
for f in $(grep -rln "directoryPicker\|DirectoryPicker" "$WP/lib" 2>/dev/null | head -8); do
  echo "--- $f ($(wc -c <"$f") B) ---"
done
echo "--- 真正干活的那份实现（找 readdir 出现在哪个文件）---"
grep -rln "readdir" "$WP/lib" 2>/dev/null | head -8
for f in $(grep -rln "readdir" "$WP/lib" 2>/dev/null | head -4); do
  echo "######## $f"
  grep -nE "readdir|withFileTypes|isDirectory|isSymbolicLink|stat|lstat|startsWith\\('\\.'\\)|startsWith\\(\"\\.\"\\)|hidden|home|process\\.env\\.HOME|homedir" "$f" 2>/dev/null | head -28
done

echo
echo "=== 2. directoryPicker/list 的入参形状（上一轮报「payload 只能有恰好一个 plain-object args 字段」）==="
grep -rnE "directoryPicker/list" "$WP/lib" 2>/dev/null | head -6
F=$(grep -rln "directoryPicker/list" "$WP/lib" 2>/dev/null | head -1)
echo "--- 命中文件：$F ---"
[ -n "$F" ] && grep -n -A12 '"directoryPicker/list"' "$F" 2>/dev/null | head -30
echo "--- 它的 args 对象字段名（path? 还是别的）---"
[ -n "$F" ] && grep -nE "Object\\.keys|expected exactly one|plain-object args|args field" "$F" 2>/dev/null | head -8

echo
echo "=== 3. 家目录与 /root 的形状（带类型字母，软链会显示成 l）==="
echo "HOME=${HOME:-未设}  PWD=${PWD:-未设}  USER=$(id -un 2>/dev/null)"
echo "--- ls -la /root ---"
ls -la /root 2>/dev/null | head -20
echo "--- 不带 -L（find 自己不跟软链）---"
find /root -maxdepth 1 -type d ! -path /root -printf '%f\n' 2>/dev/null | head -8
echo "（上面若为空 ⇒ 光靠 lstat 视角，软链不算目录）"
echo "--- 带 -L（跟软链）---"
find -L /root -maxdepth 1 -type d ! -path /root -printf '%f\n' 2>/dev/null | head -8
echo "--- Node 侧两种读法各给什么（这才是选择器真正会拿到的）---"
node -e 'const fs=require("fs"),p="/root";
const es=fs.readdirSync(p,{withFileTypes:true});
console.log("readdirSync entries =",es.length);
let dir=0,lnk=0,lnkDir=0;
for(const e of es){if(e.isDirectory())dir++;if(e.isSymbolicLink()){lnk++;try{if(fs.statSync(p+"/"+e.name).isDirectory())lnkDir++;}catch(_){}}}
console.log("dirent.isDirectory() 计数 =",dir,"| isSymbolicLink() 计数 =",lnk,"| 其中 stat 后是目录的 =",lnkDir);
console.log("/phone 存在吗 =",fs.existsSync("/phone"),"| /sdcard 存在吗 =",fs.existsSync("/sdcard"));
console.log("家目录条目数 =",fs.readdirSync(process.env.HOME||"/root").length);' 2>&1 | head -10

echo
echo "=== 4. 出网：把上一轮截掉的那段补全，并加两条对照 ==="
for h in api.deepseek.com huggingface.co hf-mirror.com github.com; do
  ip=$(getent hosts "$h" 2>/dev/null | head -1 | awk '{print $1}')
  printf '%-20s DNS=%-18s ' "$h" "${ip:-解不出}"
  curl -s -o /dev/null -m 8 -w 'HEAD=%{http_code} %{time_total}s\n' -I "https://$h" 2>/dev/null || echo 'HEAD=curl失败'
done
echo "--- SenseVoice 要下的那条具体资产路径能不能碰到（只 HEAD，不下字节）---"
curl -s -o /dev/null -m 8 -w 'hf-mirror HEAD=%{http_code} %{time_total}s size=%{size_download}\n' \
  -I "https://hf-mirror.com/FunAudioLLM/SenseVoiceSmall/resolve/main/tokens.txt" 2>/dev/null || echo 'curl 失败'

echo
echo "=== 5. 语音这条的平台闸门：本机 Node 报的是什么平台 ==="
node -e 'console.log("process.platform="+process.platform," arch="+process.arch," report="+JSON.stringify(process.report.report.header))' 2>&1 | head -3
echo "--- 上游那句平台白名单原文 ---"
grep -rnE "darwin|win32|android|platform" "$SV/lib/index.js" 2>/dev/null | grep -iE "platform|darwin|win32|android" | head -10
echo "--- 本地模型缓存目录现状（有没有已经下好的字节）---"
for d in /root/.cache/dsh /root/.dsh/models /root/.local/share/dsh /root/.sensevoice; do
  printf '%-28s ' "$d"; [ -e "$d" ] && du -sh "$d" 2>/dev/null | awk '{print $1}' || echo 不存在
done
find /root -maxdepth 3 -name '*.onnx' 2>/dev/null | head -4
echo "=== 完 ==="
