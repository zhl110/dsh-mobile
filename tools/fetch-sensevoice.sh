#!/bin/sh
# tools/fetch-sensevoice.sh —— 在他电脑上把语音模型那三个文件取回来，取完当场校验，不校验就不算拿到
#
# 为什么要写成脚本而不是手敲 curl：这套东西的"下没下对"只有一种判据 —— 字节数与 SHA-256 同时撞上
# dsh 包里 runtime/assets.json 那几条钉死的值（插件自己在 lib/index.js:270-312 也是这么判的，
# 多一个字节就 reason:"integrity" 抛掉）。手敲的话下次接手的人只能看见三个文件，看不见撞没撞上。
#
# 为什么走 hf-mirror.com 而不是 huggingface.co：2026-10-20 实测同一批 URL，他电脑上
# huggingface.co 的 HEAD 是 http=000（0.15 s 就断），hf-mirror.com 是 200（跟重定向落到
# cas-bridge.xethub.hf.co）。而他手机上两家都连不上（RUNBOOK 14.20 ④(d)）⇒ 电脑下、数据线推进手机，
# 手机全程零出网。URL 只把主机名换掉，路径与那一串固定 revision 一个字符不动，因为校验值是按那个修订钉的。
#
# 用法（在 D:\mycode\dsh-mobile 下跑）：
#   sh tools/fetch-sensevoice.sh                 # int8 那档（默认，239,233,841 B）
#   DSH_MODEL_PRECISION=fp32 sh tools/fetch-sensevoice.sh    # 换参考权重那档（937,617,178 B，他自己选的较大值）
#   DSH_MODEL_ORIGIN=https://huggingface.co sh tools/fetch-sensevoice.sh   # 哪天主站通了再换
#   sh tools/fetch-sensevoice.sh --verify        # 只看盘上这三份撞不撞上校验值，一个字节都不下
# 中断了直接重跑：半成品写 *.part，续传用 -C -，已通过的原件不重下、不覆盖。
set -u

OUT=${DSH_MODEL_DIR:-downloads/sensevoice-onnx}
ASSETS=${DSH_ASSETS:-$OUT/assets.json}
ORIGIN=${DSH_MODEL_ORIGIN:-https://hf-mirror.com}
PRECISION=${DSH_MODEL_PRECISION:-int8}
ADB=${DSH_ADB:-}
VERIFY_ONLY=0
[ "${1:-}" = "--verify" ] && VERIFY_ONLY=1

[ -f "$ASSETS" ] || { echo "!! 清单不在位：$ASSETS"; echo "   先从手机上把包里那份拉下来（脚本下面这条，只读）："; echo "   $ADB -s f22aa1e1 shell \"su -c 'cat /data/local/dsh-rootfs/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-experimental-speech-to-text-sensevoice/runtime/assets.json'\" | tr -d '\\r' > $ASSETS"; exit 1; }
command -v curl.exe >/dev/null 2>&1 || { echo "!! 这台机没有 curl.exe"; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "!! 这台机没有 sha256sum（Git-Bash 自带）"; exit 1; }

mkdir -p "$OUT"
echo "== 清单：$ASSETS（$(wc -c < "$ASSETS") B） 主机名换成 $ORIGIN  精度档 $PRECISION"

# 用 node 解析（这份 JSON 是包里的产物，字段位置会变，不拿 sed 猜）
LIST=$(node -e '
const fs=require("fs");
const a=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
const origin=process.argv[2], prec=process.argv[3];
if(!a.models||!a.models[prec]){ console.error("清单里没有 precision="+prec+" 这一档"); process.exit(1); }
const pick=[["模型",a.models[prec]],["词表",a.tokens],["VAD",a.vad]];
for(const [role,x] of pick){
  console.log([role,x.name,x.url.replace(/^https:\/\/huggingface\.co/,origin),x.bytes,x.sha256].join("\t"));
}' "$ASSETS" "$ORIGIN" "$PRECISION") || { echo "!! 解析清单失败"; exit 1; }
printf '%s\n' "$LIST" | sed 's/^/   /' | cut -f1,2,4

fail=0
# 走临时文件而不是管道：管道右边的 while 在子 shell 里，fail=1 传不出来，
# 那样最后这句"全部通过"就成了假读数（2026-10-20 写完第一版当场发现）。
LIST_FILE=$OUT/.fetch-list.tsv
printf '%s\n' "$LIST" > "$LIST_FILE"
while IFS='	' read -r role name url bytes sha; do
  [ -n "$name" ] || continue
  dest="$OUT/$name"
  if [ -f "$dest" ]; then
    got_b=$(wc -c < "$dest"); got_s=$(sha256sum "$dest" | cut -d' ' -f1)
    if [ "$got_b" = "$bytes" ] && [ "$got_s" = "$sha" ]; then
      echo "[skip] $role $name：盘上已是那份（$got_b B，sha 撞上，不重下不覆盖）"; continue
    fi
    echo "!! $role $name：盘上有同名文件但校验不撞上（$got_b/$bytes B），删掉重取"
    rm -f "$dest"
  fi
  [ "$VERIFY_ONLY" = "1" ] && { echo "!! $role $name：--verify 模式下盘上没有这一份"; fail=1; continue; }
  part="$dest.part"
  echo "[..] $role $name <- $url"
  resume=""
  [ -f "$part" ] && resume="-C -"
  # --fail 让 4xx/5xx 直接非零退出（别把一张 404 页面当成模型收下）；retry 只重试网络这一类
  if curl.exe -fL $resume --retry 3 --retry-delay 3 --connect-timeout 15 --max-time 7200 \
       -o "$part" "$url"; then
    mv -f "$part" "$dest"
  else
    echo "   （半成品留在 $part，重跑会续传）"; fail=1; continue
  fi
  got_b=$(wc -c < "$dest"); got_s=$(sha256sum "$dest" | cut -d' ' -f1)
  if [ "$got_b" = "$bytes" ] && [ "$got_s" = "$sha" ]; then
    echo "[ok] $role $name：$got_b B，sha256 与清单那条撞上"
  else
    echo "!! $role $name：对不上 —— 清单要 $bytes B / $sha，拿到 $got_b B / $got_s"
    fail=1
  fi
done < "$LIST_FILE"
rm -f "$LIST_FILE"
if [ "$fail" = "0" ]; then
  echo "[done] 三份全部撞上清单里的字节数与 SHA-256，目录 $OUT"
  echo "       总字节 $(ls -l $OUT/*.onnx $OUT/tokens.txt 2>/dev/null | awk '{s+=$5} END {print s}')，下一步：sh tools/push-sensevoice.sh"
else
  echo "!! 有项没过校验，别往手机上推（半成品停在 *.part，重跑续传）"
  exit 1
fi
