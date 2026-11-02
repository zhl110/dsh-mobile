#!/bin/bash
# 探针 81（只读）：80 号把我 79 号那张表打脸了 —— 语音那条 `getUserMedia` 根本不在前端 dist 里，
# 而在另一个包 `@deepseek-ai/dsh-experimental-client-ui-voice-input/lib/client.js`。
# 所以"页面用不用某个网页 API"这一问，**只扫前端 dist 会漏**：凡是往页面里注入 UI 的包都算页面。
# 这一发把范围摆正：先数清"有哪些 client-ui 包"，再在这些包 + 前端 dist 上加一遍 79 号那批字面量。
#
# 判据仍照 78 号：`grep -l` 只问命中文件名（0 行 + rc1 = 真没有），不用 `grep -c` 配多文件（77 号那个恒 0 坑）。
set -u
ROOT=/usr/local/lib/node_modules/@deepseek-ai
DIST=$ROOT/node_modules/@deepseek-ai/dsh-web-frontend/dist
SAY() { printf '\n=== %s\n' "$1"; }
FILES=/tmp/p81.files

SAY '① 有哪些"会往页面里塞 UI"的包（client-ui 族）'
timeout 120 find "$ROOT" -maxdepth 4 -type d -name '*client-ui*' 2>/dev/null > /tmp/p81.pkgs
timeout 30 sed 's/^/  /' < /tmp/p81.pkgs
echo "  计数=$(wc -l </tmp/p81.pkgs)（前端 dist 另算，它不在这个名里但一定是页面代码）"

SAY '② 这些包里的 js 文件（前端 dist 之外的那些才是"新面"）'
: > "$FILES"
timeout 90 find "$DIST" -type f \( -name '*.js' -o -name '*.css' -o -name '*.html' \) 2>/dev/null >> "$FILES"
while read -r d; do
  [ -n "$d" ] || continue
  timeout 60 find "$d" -type f -name '*.js' 2>/dev/null >> "$FILES"
done < /tmp/p81.pkgs
sort -u "$FILES" -o "$FILES"
echo "  待扫文件=$(wc -l <"$FILES")（其中前端 dist $(timeout 30 grep -c '/dsh-web-frontend/' "$FILES") 个）"
timeout 30 grep -v '/dsh-web-frontend/' "$FILES" | head -12 | sed 's/^/    非前端 dist：/'

SAY '③ 在这一整摊里重跑 79 号那张表（命中=有文件用了这个 API）'
has() {
  local pat="$1" out rc
  timeout 200 xargs -a "$FILES" grep -l -F -- "$pat" > /tmp/p81.o 2>/dev/null; rc=$?
  out=$(wc -l </tmp/p81.o)
  printf '  %-26s 命中文件=%s (rc%s)  %s\n' "$pat" "$out" "$rc" "$(head -2 /tmp/p81.o | xargs -r -n1 basename | tr '\n' ' ' | cut -c1-56)"
}
for p in getUserMedia mediaDevices MediaRecorder speechSynthesis; do has "$p"; done
for p in 'navigator.geolocation' 'new Notification' serviceWorker 'navigator.wakeLock'; do has "$p"; done
for p in 'clipboard.readText' 'clipboard.writeText' 'navigator.clipboard'; do has "$p"; done
for p in showOpenFilePicker showSaveFilePicker requestFileSystem; do has "$p"; done
for p in requestFullscreen fullscreenElement 'document.exitFullscreen'; do has "$p"; done
for p in createObjectURL 'new Blob' toDataURL 'navigator.share' PaymentRequest 'window.print'; do has "$p"; done

SAY '④ 语音那个包到底怎么起的（它自己写没写"要壳配合"的话）'
V=$ROOT/node_modules/@deepseek-ai/dsh-experimental-client-ui-voice-input
timeout 30 ls -l "$V" 2>/dev/null | sed 's/^/  /'
timeout 30 grep -F -o -m6 'getUserMedia[^,;{}]\{0,60\}' "$V/lib/client.js" 2>/dev/null | sed 's/^/    │ /'
timeout 30 grep -F -o -m4 'mediaDevices[^,;{}]\{0,50\}' "$V/lib/client.js" 2>/dev/null | sed 's/^/    │ /'

SAY '收尾'
rm -f "$FILES" /tmp/p81.o /tmp/p81.pkgs
echo '本探针只读：没写、没改、没装；三个临时件都就地删了。'
