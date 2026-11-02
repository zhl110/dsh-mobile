#!/bin/bash
# 探针 76（只读）：手机上这套 Web UI 到底用了哪些"要壳配合"的浏览器能力。
#（75 号被我自己中断了：那版对 minified 包用了 `grep -o -E ".{0,70}download.{0,70}"`，
#  一个 3 MB 单行文件 + 上千次命中 ⇒ 一条命令跑了 10 分钟没完。这版改成三条：
#  文件列表只算一次 / 每个模式只取前 3 处命中 / 每条 grep 都套 timeout。）
#
# 为什么要它：他 10-22 晚的原话是"把所有的功能全部都接上"。我要接的三件事
#（HTML5 全屏 / 页面下载 / 剪贴板）里，前两件在壳侧接哪一种出口、第三件到底需不需要接，
# 取决于**前端实际调的是什么**：
#   · 全屏：`requestFullscreen()`（才有 onShowCustomView 那一发）还是只用 CSS 铺满；
#   · 下载：`<a href=http(s)://… download>`（DownloadManager 取到动）还是 `blob:`（取不到，只能页面自取）；
#   · 剪贴板：`navigator.clipboard.write*`（native 侧根本没有回调可接）还是 `execCommand('copy')`。
# 猜不得：接错形状 = 我"接上了"，他一点还是没反应。
set -u

say() { printf '\n=== %s\n' "$1"; }
L=/tmp/p76.list

# 一个模式两件事：总共命中多少次（跨文件求和）、头两处窗口读数（截 60 字符，minified 一行几 MB，整行打出来会撑爆）
scan() {
  local p="$1"
  local n
  n=$(timeout 90 xargs -a "$L" grep -c -E -- "$p" 2>/dev/null | awk '{s+=$1} END{print s+0}')
  printf '  %-26s 命中文件行数=%s\n' "$p" "${n:-0}"
  timeout 90 xargs -a "$L" grep -m3 -o -E -H -- ".{0,55}${p}.{0,55}" 2>/dev/null | head -2 | sed 's/^/      │ /' | cut -c1-190
}

say '① dsh 包装到哪一层（当场量，不照文档抄路径）'
B=$(command -v dsh 2>/dev/null)
[ -n "$B" ] && echo "which dsh → $B → $(readlink -f "$B" 2>/dev/null)"
ROOT=""
for d in /usr/local/lib/node_modules/@deepseek-ai /usr/lib/node_modules/@deepseek-ai \
         /usr/local/lib/node_modules /root/dsh/node_modules/@deepseek-ai; do
  [ -d "$d" ] || continue
  hit=$(find "$d" -maxdepth 2 -type d -name 'dsh*' 2>/dev/null | head -1)
  if [ -n "$hit" ]; then ROOT="$hit"; break; fi
done
[ -n "$ROOT" ] || { echo '!! 没定位到包目录 ⇒ ②③④⑤全部作废（不能读成"前端没用这些 API"）'; exit 0; }
echo "ROOT=$ROOT"

say '② 前端资产在哪一摞（按 index.html 定位，再收同目录的 js）'
timeout 60 find "$ROOT" -maxdepth 5 -type f -name '*.html' 2>/dev/null | head -6 | while read -r f; do
  printf '%9d B  %s\n' "$(wc -c <"$f")" "$f"
done
DIR=$(timeout 60 find "$ROOT" -maxdepth 5 -type f -name 'index.html' 2>/dev/null | head -1 | xargs -r dirname 2>/dev/null)
[ -n "$DIR" ] || DIR="$ROOT"
echo "扫描目录 DIR=$DIR"
timeout 90 find "$DIR" -type f \( -name '*.js' -o -name '*.mjs' \) -size -6M 2>/dev/null > "$L"
N=$(wc -l < "$L")
echo "候选 js 文件数=$N（单文件 >6M 的先跳开，75 号慢下来的原因之一就是这个）"
head -6 "$L" | while read -r f; do printf '%9d B  %s\n' "$(wc -c <"$f")" "$(basename "$f")"; done
[ "$N" = "0" ] && echo '!! 该目录没有像样的 js ⇒ 前端不在这条路上（那就只看 ⑥ 入口脚本，别把 0 读成"没用"）'

say '③ 全屏那条路（决定 onShowCustomView 到底有没有真实用户）'
for p in requestFullscreen webkitRequestFullscreen fullscreenElement fullscreenchange; do scan "$p"; done

say '④ 下载那条路（决定接 DownloadManager 还是只能让页面自取）'
for p in createObjectURL revokeObjectURL 'download=' 'new Blob' 'navigator\.share' 'text/markdown'; do scan "$p"; done

say '⑤ 剪贴板那条路（决定要不要往页面里垫一层）'
for p in 'navigator\.clipboard' 'clipboard-write' 'clipboard-read' 'permissions\.query' 'writeText' 'readText' 'execCommand'; do scan "$p"; done

say '⑥ 入口脚本这一侧：它自己发不发 Content-Disposition（那是 http 下载的线索）'
E=/usr/local/bin/dsh-entry.js
if [ -f "$E" ]; then
  echo "入口件：$(wc -c <"$E") B"
  for p in 'Content-Disposition' 'attachment' 'download'; do
    printf '  %-22s 命中行数=%s\n' "$p" "$(grep -c -E -- "$p" "$E" 2>/dev/null)"
    timeout 30 grep -n -m2 -E -- "$p" "$E" 2>/dev/null | cut -c1-160 | sed 's/^/    │ /'
  done
else
  echo '!! 入口件不在位 ⇒ 这一节空读数，不能读成"入口不发这个头"'
fi

say '收尾'
rm -f "$L"
echo '本探针只读：没写、没改、没装；临时文件列表已就地删掉。'
