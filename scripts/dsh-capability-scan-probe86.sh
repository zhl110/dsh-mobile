#!/bin/bash
# 探针 86（只读）：把 0.10 那条 `onShowCustomView` 到底"给谁用"这一问补死。
# 82 号量到"全摊 186 个文件里 requestFullscreen 0 命中"⇒ 没人走 HTML5 全屏 API；
# 但 WebView 里 `<video>` 点全屏**不走 Fullscreen API**，走的就是 onShowCustomView（原生把那个 View 交给我们）。
# 所以"有没有真实用户"要问的是：**页面里有没有 video / 播放器**。这一发数这个。
set -u
ROOT=/usr/local/lib/node_modules/@deepseek-ai/dsh
PKGS=$ROOT/node_modules/@deepseek-ai
DIST=$PKGS/dsh-web-frontend/dist
FILES=/tmp/p86.files
SAY() { printf '\n=== %s\n' "$1"; }

: > "$FILES"
timeout 90 find "$DIST" -type f \( -name '*.js' -o -name '*.html' \) 2>/dev/null >> "$FILES"
timeout 120 find "$PKGS" -maxdepth 3 -type f -name '*.js' -path '*client-ui*' 2>/dev/null >> "$FILES"
sort -u "$FILES" -o "$FILES"
echo "待扫文件=$(wc -l <"$FILES") 个"

hit() {
  local re="$1" label="$2"
  timeout 200 xargs -a "$FILES" grep -l -E "$re" 2>/dev/null > /tmp/p86.hit
  printf '  %-34s 命中文件=%s\n' "$label" "$(wc -l </tmp/p86.hit)"
  timeout 20 sed "s|$PKGS/||; s|dsh-web-frontend/dist/|前端dist/|" /tmp/p86.hit | head -3 | sed 's/^/      ／ /'
}

hit '<video'                        'HTML 里写 <video'
hit 'createElement\("video"\)|createElement\(.'"'"'video'"'"'\)'  'JS 造 video 元素'
hit 'HTMLVideoElement'              '类型里出现 HTMLVideoElement'
hit 'srcObject'                     'MediaSource/getUserMedia 挂到元素上（srcObject）'
hit 'requestVideoFrameCallback'     '逐帧回调（播放器才会用）'
hit 'new Audio\(|createElement\("audio"\)' '音频元素'
hit 'controlsList|disablePictureInPicture' '播放器控制条相关属性'
hit 'PictureInPicture|requestPictureInPicture' '画中画（WebView 里结构上不通，先看有没有人调）'

SAY '收尾'
rm -f "$FILES" /tmp/p86.hit
echo '本探针只读：没写、没改、没装；两个临时件就地删了。'
