#!/bin/bash
# 探针 82（只读）：81 号扫出来的那张表**范围是错的**（我把前端 dist 的路径拼错 ⇒ 那一摊 0 个文件进表，
# 只有 57 个 client-ui 包进了），但它顺手把一件更要紧的事翻出来了：**页面不只有前端 dist，
# 是 57 个 client-ui 包拼起来的**，而且这些包里真的在用 createObjectURL / new Blob / toDataURL /
# clipboard.readText / fullscreenElement。⇒ 我上一轮"前端根本不用 blob / 不用全屏"那句要按范围改口。
# 这一发把两摊合在一起重扫一遍，并把命中**落到是哪个包**（只印 basename 会撞名，看不出是谁用的）。
set -u
ROOT=/usr/local/lib/node_modules/@deepseek-ai/dsh
PKGS=$ROOT/node_modules/@deepseek-ai
DIST=$PKGS/dsh-web-frontend/dist
FILES=/tmp/p82.files
SAY() { printf '\n=== %s\n' "$1"; }

SAY '① 两摊各多少个文件（这次路径按 80 号量出来的真位置写）'
: > "$FILES"
timeout 90 find "$DIST" -type f \( -name '*.js' -o -name '*.css' -o -name '*.html' \) 2>/dev/null >> "$FILES"
NDIST=$(wc -l <"$FILES")
timeout 120 find "$PKGS" -maxdepth 3 -type f -name '*.js' -path '*client-ui*' 2>/dev/null >> "$FILES"
sort -u "$FILES" -o "$FILES"
echo "  前端 dist=$NDIST 个｜client-ui 族 js=$(( $(wc -l <"$FILES") - NDIST )) 个｜合计=$(wc -l <"$FILES")"
echo "  合计字节=$(xargs -a "$FILES" cat 2>/dev/null | wc -c | tr -d ' ')"

has() {   # 命中哪些文件 + 把公共前缀削掉，直接看出是哪个包在用
  local pat="$1" out rc
  timeout 200 xargs -a "$FILES" grep -l -F -- "$pat" > /tmp/p82.o 2>/dev/null; rc=$?
  out=$(wc -l </tmp/p82.o)
  printf '  %-24s 命中文件=%s (rc%s)\n' "$pat" "$out" "$rc"
  timeout 20 sed "s|$PKGS/||; s|dsh-web-frontend/dist/|前端dist/|" /tmp/p82.o | head -4 | sed 's/^/      ／ /'
}

SAY '② 下载那一族（blob / dataURL / a.download / saveAs）——决定"壳接了才有反应"的那批'
for p in createObjectURL 'new Blob' toDataURL 'download:' 'download=' '.download' saveAs FileSaver; do has "$p"; done

SAY '③ 全屏那一族（onShowCustomView 与 document.fullscreenElement 都算）'
for p in requestFullscreen fullscreenElement exitFullscreen fullscreenchange webkitRequestFullscreen orientation.type; do has "$p"; done

SAY '④ 剪贴板（写已实测通；readText 在 Android 上是"前台才行"，且 WebView 里这条没有壳侧回调）'
for p in 'clipboard.writeText' 'clipboard.readText' 'clipboard.write(' 'clipboard.read(' execCommand 'navigator.clipboard'; do has "$p"; done

SAY '⑤ 麦克风/摄像头与别的系统出口（语音包已确认用 getUserMedia）'
for p in getUserMedia mediaDevices MediaRecorder enumerateDevices 'navigator.geolocation' 'new Notification' serviceWorker 'navigator.wakeLock' 'navigator.share' 'window.print'; do has "$p"; done

SAY '⑥ 目录/文件夹上传与拖拽（这两条若被用，走的路和 <input type=file> 不同）'
for p in webkitdirectory 'DataTransfer' 'dragover' "'drop'" 'clipboardData' '"paste"'; do has "$p"; done

SAY '⑦ 语音包原文（81 号那条路径拼错 ⇒ 那节是空的，这里补上）'
V=$PKGS/dsh-experimental-client-ui-voice-input
timeout 30 ls -l "$V"/lib 2>/dev/null | sed 's/^/  /'
timeout 30 grep -F -o -m4 'mediaDevices[.a-zA-Z]\{0,40\}' "$V/lib/client.js" 2>/dev/null | sed 's/^/    │ /'
timeout 30 grep -F -o -m3 'getUserMedia([^)]\{0,60\}' "$V/lib/client.js" 2>/dev/null | sed 's/^/    │ /'

SAY '收尾'
rm -f "$FILES" /tmp/p82.o
echo '本探针只读：没写、没改、没装；两个临时件就地删了。'
