#!/bin/bash
# 探针 85（只读）：把"页面到底怎么把一个 blob 交出去"这一问一次问死。
# 84 号那四个窗口全空是我自己的判据太严：`\.download=` 撞不上 `a.download = url`（等号两边有空格），
# 也撞不上 React 里那种 `jsx("a",{download:名字,href:url})`（那是**对象键**，不是赋值）。
# 这一发把三种写法都按宽松正则取原文，并**在 186 个文件整摊上跑**（不再只挑五个文件）。
set -u
ROOT=/usr/local/lib/node_modules/@deepseek-ai/dsh
PKGS=$ROOT/node_modules/@deepseek-ai
DIST=$PKGS/dsh-web-frontend/dist
FILES=/tmp/p85.files
SAY() { printf '\n=== %s\n' "$1"; }

: > "$FILES"
timeout 90 find "$DIST" -type f \( -name '*.js' -o -name '*.html' \) 2>/dev/null >> "$FILES"
timeout 120 find "$PKGS" -maxdepth 3 -type f -name '*.js' -path '*client-ui*' 2>/dev/null >> "$FILES"
sort -u "$FILES" -o "$FILES"
echo "待扫文件=$(wc -l <"$FILES") 个"

win() {   # 宽松正则取原文窗口：先只列命中的文件（一遍），再在命中的那几个文件里取前后各 70 字符
  local re="$1" label="$2"
  printf '\n--- %s（正则 %s）\n' "$label" "$re"
  timeout 200 xargs -a "$FILES" grep -l -E "$re" 2>/dev/null > /tmp/p85.hit
  echo "    └ 命中文件数=$(wc -l </tmp/p85.hit)"
  timeout 30 sed "s|$PKGS/||; s|dsh-web-frontend/dist/|前端dist/|" /tmp/p85.hit | head -4 | sed 's/^/      文件 /'
  timeout 120 xargs -a /tmp/p85.hit grep -H -o -m2 -E ".{0,70}$re.{0,70}" 2>/dev/null \
    | timeout 30 sed "s|$PKGS/||; s|dsh-web-frontend/dist/|前端dist/|" | head -5 | cut -c1-190 | sed 's/^/      │ /'
}

win '\.download[[:space:]]*=' 'JS 里给 a.download 赋值（这种写法名字在页面手里）'
win 'download:[[:space:]]' '对象键 download:（React 里就是 <a download=…>）'
win 'download=[^=]' 'HTML 属性 download='
win 'window\.open\(' 'window.open（blob 若这么开，走的是壳的 onCreateWindow）'
win 'target:"_blank"|target=\\?"_blank' '新窗口/target=_blank'
win 'createElement\("a"\)|createElement\('"'"'a'"'"'\)' '自己造一个 <a>（下载最常见的写法）'
win 'dispatchEvent\(new MouseEvent' '用事件派发代替真点击（这条壳收不收得到？）'

SAY '收尾'
rm -f "$FILES" /tmp/p85.hit
echo '本探针只读：没写、没改、没装；临时件就地删了。'
