#!/bin/bash
# 探针 79（只读）：把"还有哪些网页 API 需要壳侧接线"这一问，用**前端到底写没写**来回答。
#
# 为什么还要再扫一遍（78 号已经扫过全屏与下载了）：他这一轮的口令是"把所有功能全部都接上，
# 是有什么隐患吗"。要答这句，不能只答他点出来的那三条（剪贴板 / 全屏 / 下载），
# 得把 WebView 那一族"默认实现会静默丢掉"的回调**一次列全**，每条配一个"页面用不用"的读数。
# 用法与判据照 78 号：`grep -l` 只问"哪些文件命中"（0 行 + rc1 = 全量里真没有，这个数能当场判死），
# 不用 `grep -c`（多文件时输出是"路径:次数"，求和那步会加出恒 0 —— 77 号踩过，已进 AGENTS.md）。
set -u

ROOT=/usr/local/lib/node_modules/@deepseek-ai/dsh
DIST=$ROOT/node_modules/@deepseek-ai/dsh-web-frontend/dist
ALL=/tmp/p79.all
say() { printf '\n=== %s\n' "$1"; }

timeout 90 find "$DIST" -type f \( -name '*.js' -o -name '*.css' -o -name '*.html' \) 2>/dev/null > "$ALL"
echo "全量 js/css/html=$(wc -l <"$ALL") 个（$(xargs -a "$ALL" cat 2>/dev/null | wc -c | tr -d ' ') B）"

has() {   # 只问"哪些文件命中"
  local pat="$1" out rc
  timeout 60 xargs -a "$ALL" grep -l -F -- "$pat" > /tmp/p79.o 2>/dev/null; rc=$?
  out=$(wc -l </tmp/p79.o)
  printf '  %-26s 命中文件=%s (rc%s)  %s\n' "$pat" "$out" "$rc" "$(head -2 /tmp/p79.o | xargs -r -n1 basename | tr '\n' ' ' | cut -c1-60)"
}

say '① 定位（要接的是 onGeolocationPermissionsShowPrompt，我们没接）'
for p in 'navigator.geolocation' getCurrentPosition watchPosition; do has "$p"; done

say '② 通知 / 后台常驻 / 屏幕常亮（WebView 里这三条没有壳侧回调可接，属"结构上不通"）'
for p in 'new Notification' requestPermission serviceWorker 'navigator.wakeLock' requestWakeLock; do has "$p"; done

say '③ 剪贴板读（写已实测通；读要 Android 10+ 的前台限制，且我们没有 read 的壳侧回调）'
for p in 'clipboard.readText' 'clipboard.read('; do has "$p"; done

say '④ 文件访问 API（这条若被用，走的是 File System Access，不是 <input type=file>，壳得另接）'
for p in showOpenFilePicker showSaveFilePicker showDirectoryPicker requestFileSystem; do has "$p"; done

say '⑤ 媒体与语音（麦克风已端到端；这几条是"还有没有别的入口要放行"）'
for p in getUserMedia MediaRecorder speechSynthesis SpeechRecognition RTCPeerConnection 'webkitAudioContext'; do has "$p"; done

say '⑥ 其他系统级出口（分享 / 震动 / 蓝牙 / 打印 / 锁屏方向）'
for p in 'navigator.share' 'navigator.vibrate' 'navigator.bluetooth' PaymentRequest 'window.print' 'orientation.lock'; do has "$p"; done

say '⑦ 顺手复点：这一代前端文件的指纹（下轮比对"前端有没有换过"）'
timeout 60 xargs -a "$ALL" md5sum 2>/dev/null | md5sum | sed 's/^/  全量清单的合并 md5=/'
timeout 60 xargs -a "$ALL" cat 2>/dev/null | wc -c | tr -d ' ' | sed 's/^/  全量字节=/'

say '收尾'
rm -f "$ALL" /tmp/p79.o
echo '本探针只读：没写、没改、没装；两个临时件都就地删了。'
