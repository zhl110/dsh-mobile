#!/bin/bash
# 探针 78（只读）：把 77 号那三个"命中文件数"里唯一还分不清的两问，用 -l 一次问死。
#
# 77 号留下的坑（为什么不能直接拿它的数下结论）：我用 `grep -c` 配多文件参数，输出形状是"路径:次数"，
# 而求和那步是 `awk '{s+=$1}'` ⇒ 加的是"路径"这个非数字 ⇒ **全表恒等于 0**。
# 退出码那半边还是好的，所以能定的是"有命中"（rc0）：navigator.clipboard / writeText / execCommand /
# fullscreenchange 这四条 rc=0 ⇒ 前端确实写了。分不清的是 rc=123 那一族：
# xargs 只要**有一个**文件没命中就回 123，它不告诉我另一个文件命中了没有。
# 这版改成 `grep -l`（只列命中的文件名）：列出 0 行 + rc=1 = 当场判死"全量里真没有"，
# 列出文件名 = 有。再补一条 `-o | wc -l` 只在两个入口块上数出现次数（1.7 MB，跑得起）。
set -u

ROOT=/usr/local/lib/node_modules/@deepseek-ai/dsh
DIST=$ROOT/node_modules/@deepseek-ai/dsh-web-frontend/dist
ALL=/tmp/p78.all
ENT=/tmp/p78.ent
say() { printf '\n=== %s\n' "$1"; }

timeout 90 find "$DIST" -type f \( -name '*.js' -o -name '*.css' -o -name '*.html' \) 2>/dev/null > "$ALL"
timeout 90 find "$DIST" -type f \( -name 'index-*.js' -o -name 'vendor-*.js' \) 2>/dev/null > "$ENT"
echo "全量 js/css/html=$(wc -l <"$ALL") 个｜入口块=$(wc -l <"$ENT") 个（$(xargs -a "$ENT" cat 2>/dev/null | wc -c | tr -d ' ') B）"

has() {   # 只问"哪些文件命中"，不问次数：0 行 + rc1 就是"没有"，这个读数能当场判死
  local pat="$1" out rc
  timeout 60 xargs -a "$ALL" grep -l -F -- "$pat" > /tmp/p78.o 2>/dev/null; rc=$?
  out=$(wc -l </tmp/p78.o)
  printf '  %-24s 命中文件=%s (rc%s)  %s\n' "$pat" "$out" "$rc" "$(head -2 /tmp/p78.o | xargs -r -n1 basename | tr '\n' ' ' | cut -c1-70)"
}
occ() {   # 出现次数：只在入口块上数（这两个文件 1.7 MB，-o 跑得完）
  local pat="$1" n rc
  timeout 60 xargs -a "$ENT" grep -F -o -- "$pat" >/tmp/p78.n 2>/dev/null; rc=$?
  n=$(wc -l </tmp/p78.n)
  printf '  %-24s 入口块出现次数=%s (rc%s)\n' "$pat" "$n" "$rc"
}

say '① 全屏：这套 UI 自己有没有要走 requestFullscreen 的地方'
for p in requestFullscreen webkitRequestFullscreen fullscreenElement exitFullscreen 'fullscreen'; do has "$p"; done
for p in requestFullscreen fullscreenElement; do occ "$p"; done

say '② 下载：blob 路（页面自取）还是 http 路（DownloadManager）'
for p in createObjectURL revokeObjectURL 'new Blob' 'download:' 'download=' 'hrefset' toDataURL 'navigator.share'; do has "$p"; done
for p in createObjectURL 'new Blob' 'download:' 'download='; do occ "$p"; done

say '③ 剪贴板：把 77 号那两段原文取全一点（拆行后各取三处）'
timeout 60 xargs -a "$ENT" cat 2>/dev/null | tr '{}' '\n\n' | timeout 30 grep -F -m3 -o 'navigator\.clipboard[^,;)]\{0,80\}' | sed 's/^/  │ /'
echo '  └ execCommand 降级那段（拆行取一处）：'
timeout 60 xargs -a "$ENT" cat 2>/dev/null | tr '{' '\n' | timeout 30 grep -F -m1 execCommand | cut -c1-200 | sed 's/^/  │ /'

say '④ 页面里那 3 处"download"字样到底在哪（77 号数到过但没定位）'
timeout 60 xargs -a "$ALL" grep -l -F 'download' 2>/dev/null | head -6 | sed 's/^/  命中文件 /'
timeout 60 xargs -a "$ENT" grep -F -o -m20 '[a-zA-Z_.:"]\{0,12\}download[a-zA-Z_.:"=]\{0,12\}' 2>/dev/null | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'

say '收尾'
rm -f "$ALL" "$ENT" /tmp/p78.o /tmp/p78.n
echo '本探针只读：没写、没改、没装；四个临时件都就地删了。'
