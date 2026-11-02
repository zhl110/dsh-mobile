#!/bin/bash
# 探针 77（只读）：把 76 号那堆"命中=0"复点成能分的读数。
#
# 76 号错在哪（这就是它为什么要再来一发）：我用了 `grep -c -E ".{0,55}模式.{0,55}"` 的**全文件计数**，
# 对 2 MB 一行的 minified 包跑不完，被我自己写的 `timeout 90` 杀掉 ⇒ 输出空 ⇒ awk 求和得 0。
# 于是"0"这个数**分不清"没用过"和"没跑完"** —— 同一次跑里上下文那几发明明命中了
#（navigator.clipboard?.writeText、typeof document.execCommand），计数却报 0，就是这个形状。
# 规矩（AGENTS 已知坑那条"空读数不能读成没有"）要求：每条读数把**退出码**一起印出来，
# 124=超时、1=真没命中、0=有命中，三个数分开写。
#
# 这版另外两处收窄：只扫真正的前端入口 chunk（index-*/vendor*，Shiki 那 50 多个语法块不参与），
# 计数一律用 -F 定长串匹配（比 -E 带上下文窗口快一个量级）。
set -u

ROOT=/usr/local/lib/node_modules/@deepseek-ai/dsh
DIST=$ROOT/node_modules/@deepseek-ai/dsh-web-frontend/dist
say() { printf '\n=== %s\n' "$1"; }

say '① 目录与资产构成（先把要扫的那几摞指认出来）'
[ -d "$DIST" ] || { echo "!! $DIST 不在位 ⇒ 后面全作废，不能读成前端没用这些 API"; exit 0; }
ls -1 "$DIST" | head -10 | sed 's/^/  /'
echo "  assets/ 下最大的 8 个文件："
timeout 60 find "$DIST" -type f -printf '%s %f\n' 2>/dev/null | sort -rn | head -8 | sed 's/^/    /'

L=/tmp/p77.list
timeout 60 find "$DIST" -type f \( -name 'index-*.js' -o -name 'vendor-*.js' -o -name 'index.html' -o -name '*.css' \) 2>/dev/null > "$L"
: > /tmp/p77.all
timeout 60 find "$DIST" -type f \( -name '*.js' -o -name '*.css' -o -name '*.html' \) 2>/dev/null > /tmp/p77.all
echo "  入口 chunk 数=$(wc -l < "$L")｜全量 js/css/html 数=$(wc -l < /tmp/p77.all)"

# 一个模式：先只扫入口 chunk，再扫全量；每次带上退出码（124=超时、1=确实没命中、0=有命中）
# 计数口径：用 -c，它数的是**命中行数** —— minified 包就一行，所以这里的数读作"命中文件数"，
# 不是出现次数（要出现次数得 -o，而 -o 在大文件上就是 76 号那种跑不完的法子）。
probe() {
  local pat="$1"
  local r1 r2 rc1 rc2
  timeout 45 xargs -a "$L" grep -F -c -- "$pat" >/tmp/p77.o1 2>/dev/null; rc1=$?
  r1=$(awk '{s+=$1} END{print s+0}' /tmp/p77.o1)
  timeout 45 xargs -a /tmp/p77.all grep -F -c -- "$pat" >/tmp/p77.o2 2>/dev/null; rc2=$?
  r2=$(awk '{s+=$1} END{print s+0}' /tmp/p77.o2)
  printf '  %-24s 入口块=%s(rc%s)｜全量=%s(rc%s)\n' "$pat" "$r1" "$rc1" "$r2" "$rc2"
}
winc() {   # 只取前两处命中，用 -o：命中的那一小串单独打出来，不给整行
           # （76 号那种 ".{0,55}模式.{0,55}" 上下文窗口就是它把 2 MB 单行文件跑不完的原因）
  local pat="$1" out rc
  timeout 45 xargs -a "$L" grep -F -m2 -o -- "$pat" >/tmp/p77.o3 2>/dev/null; rc=$?
  out=$(head -2 /tmp/p77.o3)
  printf '      └ 命中样例(rc%s)：%s\n' "$rc" "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-90)"
}

say '② 全屏那条路（onShowCustomView 到底有没有真实用户）'
for p in requestFullscreen webkitRequestFullscreen fullscreenElement exitFullscreen fullscreenchange; do probe "$p"; done
winc requestFullscreen; winc fullscreenElement

say '③ 下载那条路（决定接 DownloadManager 还是只能页面自取 blob）'
for p in createObjectURL revokeObjectURL 'download=' 'new Blob' 'navigator.share' 'application/octet-stream'; do probe "$p"; done
winc createObjectURL; winc 'download='

say '④ 剪贴板那条路（它自己有没有写降级）'
for p in 'navigator.clipboard' 'writeText' 'readText' 'clipboard-write' 'permissions.query' 'execCommand'; do probe "$p"; done
# 降级那一句要看原文：把含 execCommand 的那一段切出来（tr 先把行拆碎，避免 2 MB 单行）
echo '  └─ execCommand 附近原文（拆行后取一处）：'
timeout 45 xargs -a "$L" cat 2>/dev/null | tr ',' '\n' | timeout 20 grep -F -m1 execCommand | cut -c1-140 | sed 's/^/      /'
echo '  └─ clipboard 附近原文（拆行后取两处）：'
timeout 45 xargs -a "$L" cat 2>/dev/null | tr ';' '\n' | timeout 20 grep -F -m2 'navigator.clipboard' | cut -c1-160 | sed 's/^/      /'

say '⑤ 服务端有没有"带附件头的下载口"（引擎侧，不是页面侧）'
LIB=$ROOT/lib
if [ -d "$LIB" ]; then
  echo "  lib/ 下 js 文件数=$(timeout 60 find "$LIB" -name '*.js' -type f 2>/dev/null | wc -l)"
  for p in 'Content-Disposition' 'attachment; filename' 'form-data'; do
    r=$(timeout 60 find "$LIB" -name '*.js' -type f -exec grep -F -o -- "$p" {} + 2>/dev/null | wc -l)
    printf '  %-24s 命中=%s\n' "$p" "$r"
  done
else
  echo "  !! $LIB 不在位 ⇒ 这一节空读数"
fi

say '⑥ index.html 里有没有硬写的 <a download>（少数入口会留静态链接）'
timeout 30 xargs -a "$L" grep -F -o -m5 'download' 2>/dev/null | wc -l | sed 's/^/  download 字样出现次数（入口块）=/'
timeout 30 cat "$DIST/index.html" 2>/dev/null | cut -c1-400 | sed 's/^/  │ /'

say '收尾'
rm -f "$L" /tmp/p77.all /tmp/p77.o1 /tmp/p77.o2 /tmp/p77.o3
echo '本探针只读：没写、没改、没装；三份临时列表与两个临时输出都就地删了。'
