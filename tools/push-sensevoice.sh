#!/bin/sh
# tools/push-sensevoice.sh —— 把电脑上校验过的三个模型文件推进手机里插件自己的缓存目录，推完在手机上再算一遍校验
#
# 为什么手机上还要再算一遍：电脑上过校验只证明"我电脑那份是对的"。中间这一路是 adb push 到 /data/local/tmp
# 再以 root 搬进 chroot（两段式，理由与 tools/deploy-entry.sh 一样：adb 只能以 shell 身份写），
# 任何一段坏了都会留下一个"看着在、插件判不过"的文件。插件那侧的判据是字节数 + SHA-256 同时撞上
# （@deepseek-ai/dsh-experimental-speech-to-text-sensevoice/lib/index.js:270-312），所以我也按同一条判。
#
# 为什么落点是那几层目录：lib/index.js:209-217 里写死了三处（这轮直接读它自己的代码，不靠猜）——
#   modelRoot = config.modelDirectory ?? join(config.dataRoot,"models","sensevoice-onnx")
#   paths.model  = modelRoot/<清单里的模型名>          ← 跟 modelRoot
#   paths.tokens = modelRoot/tokens.txt                ← 跟 modelRoot
#   paths.vad    = config.vadModelPath ?? join(dataRoot,"models","silero",清单里的 vad 名)
#                  ↑ 这条**不在 sensevoice-onnx 那一层**，是平级的 silero 目录。
#                    （我第一版把三份都塞进 sensevoice-onnx 了，读到这一行才改过来 —— 症状会是
#                     "缓存检查永远不通过、插件还是要你点下载"，那种放错了比没放更费解。）
# 这台机上 dataRoot 实测是 /root/.dsh/speech-to-text/sensevoice（2026-10-20 读数：那四层目录早在位、里面零文件）。
# 文件由部署者负责这一条是它自己 README.zh 写的（"显式部署路径只检查可访问性"），不是我自己发明的用法。
# 判据同插件：paths 三处都能 access()，且没被 config 覆盖的那几份要字节数+SHA-256 同时撞上（index.js:220-236）。
#
# 用法（在 D:\mycode\dsh-mobile 下跑）：
#   sh tools/push-sensevoice.sh           # 校验电脑上那三份 → 推 → 手机上再校验
#   sh tools/push-sensevoice.sh --dry     # 只读：报两边的位置与现有文件，一个字节都不写
# 前提：手机连着 adb、root 可用、入口/引擎在跑与否都不影响（这一步不动服务）。
set -u

ADB="${DSH_ADB:-/d/mycode/.agent-tools/platform-tools/adb.exe}"
SRC=${DSH_MODEL_DIR:-downloads/sensevoice-onnx}
ASSETS=$SRC/assets.json
ROOTFS=/data/local/dsh-rootfs
SVPKG="$ROOTFS/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-experimental-speech-to-text-sensevoice"
CACHE="$ROOTFS/root/.dsh/speech-to-text/sensevoice/models"          # 宿主视角（= chroot 里 /root/.dsh/…）
DEST_MODEL="$CACHE/sensevoice-onnx"                                  # paths.model 与 paths.tokens 落这
DEST_VAD="$CACHE/silero"                                             # paths.vad 落这 —— 平级，不在上一层！
STAGE=/data/local/tmp
PRECISION=${DSH_MODEL_PRECISION:-int8}
export MSYS2_ARG_CONV_EXCL='*'

S() { "$ADB" shell "su -c \"$1\"" </dev/null 2>&1 | tr -d '\r'; }
[ -f "$ASSETS" ] || { echo "!! 清单不在位：$ASSETS（先跑 tools/fetch-sensevoice.sh 之前先把它拉下来）"; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "!! 这台机没有 sha256sum"; exit 1; }

# 清单里挑这档要的三个文件，tab 分隔：role  name  bytes  sha256（role 决定它落哪一层，见上面那段）
LIST=$(node -e '
const fs=require("fs");
const a=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
const p=process.argv[2];
if(!a.models||!a.models[p]){ console.error("清单没有 precision="+p); process.exit(1); }
for(const [role,x] of [["model",a.models[p]], ["tokens",a.tokens], ["vad",a.vad]])
  console.log([role,x.name,x.bytes,x.sha256].join("\t"));
' "$ASSETS" "$PRECISION") || { echo "!! 解析清单失败"; exit 1; }
LIST_FILE=$SRC/.push-list.tsv
printf '%s\n' "$LIST" > "$LIST_FILE"

echo "== 两个目标目录现状（宿主视角）"
S "ls -l $DEST_MODEL 2>&1 | head -6"
S "ls -l $DEST_VAD 2>&1 | head -6"
if [ "${1:-}" = "--dry" ]; then
  echo "-- dry：只读，不写盘"; rm -f "$LIST_FILE"; exit 0
fi

fail=0
pushed=0
verified=0
want=$(wc -l < "$LIST_FILE" | tr -dc '0-9')
# 循环里的 adb 会把它父进程的 stdin 吃掉（2026-10-20 实测：三份只推了第一份，后两份连尝试都没有，
# 而退出码是 0 —— 所以那句"三份都在位"是假的）。两条一起改：列表从 FD 3 读，每条 adb 再喂 /dev/null。
while IFS='	' read -r role name bytes sha <&3; do
  [ -n "$name" ] || continue
  case "$role" in
    vad) dest_dir="$DEST_VAD"; in_dir="/root/.dsh/speech-to-text/sensevoice/models/silero" ;;
    *)   dest_dir="$DEST_MODEL"; in_dir="/root/.dsh/speech-to-text/sensevoice/models/sensevoice-onnx" ;;
  esac
  f="$SRC/$name"
  if [ ! -f "$f" ]; then echo "!! 电脑上缺 $name"; fail=1; continue; fi
  gb=$(wc -c < "$f"); gs=$(sha256sum "$f" | cut -d' ' -f1)
  if [ "$gb" != "$bytes" ] || [ "$gs" != "$sha" ]; then
    echo "!! 电脑上这份就不对（$name：$gb/$bytes B），拒绝推 —— 先重跑 tools/fetch-sensevoice.sh"; fail=1; continue
  fi
  echo "[ok] 电脑上 $role $name 撞上清单（$gb B）⇒ 推到 $(basename "$dest_dir")/ 那一层"
  "$ADB" push "$f" "$STAGE/$name" </dev/null >/dev/null 2>&1 || { echo "!! adb push 失败：$name"; fail=1; continue; }
  pushed=$((pushed+1))
  rb=$(S "wc -c < $STAGE/$name" | tr -dc '0-9')
  if [ "$rb" != "$bytes" ]; then echo "!! 暂存字节不对（$STAGE/$name：$rb/$bytes），搬之前先停"; fail=1; continue; fi
  S "mkdir -p $dest_dir && cp $STAGE/$name $dest_dir/$name && chmod 644 $dest_dir/$name && chown root:root $dest_dir/$name && rm -f $STAGE/$name"
  # 手机上算：在 chroot 里跑，路径用 chroot 视角 —— 这样连"这层目录插件看不看得见"一起验了
  ds=$(S "chroot $ROOTFS /usr/bin/env PATH=/usr/bin:/bin sha256sum $in_dir/$name" | cut -d' ' -f1 | tr -dc 'a-f0-9')
  db=$(S "stat -c %s $dest_dir/$name" | tr -dc '0-9')
  if [ "$ds" = "$sha" ] && [ "$db" = "$bytes" ]; then
    verified=$((verified+1))
    echo "[ok] 手机上 $role $name：$db B，sha256 撞上 ⇒ 这一份插件判得过了"
  else
    echo "!! 手机上对不上：$db/$bytes B，sha=$ds"; fail=1
  fi
done 3< "$LIST_FILE"
rm -f "$LIST_FILE"

echo "== 推完之后这两层的样子（chroot 视角，插件自己 access() 的就是这几个路径）"
S "chroot $ROOTFS /usr/bin/env PATH=/usr/bin:/bin ls -l /root/.dsh/speech-to-text/sensevoice/models/sensevoice-onnx /root/.dsh/speech-to-text/sensevoice/models/silero"
# 结论按计数说，不按"退出码 0"说：这一版第一跑就是三份里只推成一份而退出码还是 0（原因见上面那段 adb 吃 stdin）
echo "== 计数：清单 $want 份 ⇒ 推了 $pushed 份 ⇒ 手机上校验通过 $verified 份"
if [ "$fail" = "0" ] && [ "$verified" = "$want" ]; then
  echo "[done] $verified/$want 全部在位且撞上校验。下一步在 App 里：把语音那个插件关掉再打开一次（或重启服务），"
  echo "       它自己会 access()+校验这三份，直接就绪，不用再点下载。"
else
  echo "!! 没成：$verified/$want 份过校验（fail=$fail）。别当成功，看上面哪一条打了 !!。"
  exit 1
fi
