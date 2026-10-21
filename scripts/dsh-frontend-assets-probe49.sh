#!/usr/bin/env bash
# dsh-frontend-assets-probe49.sh —— 只读：找出「横屏时左边那一栏不能滚」这件事要写选择器所依据的那几份产物
#
# 为什么要单独一发：要改的是上游打包好的前端（我们不能改它的盘上文件，只能在出口注 CSS），
# 而出口注 CSS 必须有锚点。锚点只有两种来源：① 宿主自己标在 DOM 上的 data-* 属性（DSHA 用的就是这个，稳）；
# ② CSS Module 哈希出来的类名（`_rail_1a2b3` 这种，升级就变）。这一发就是要把这两样各取到什么数出来，
# 好决定我那一段 CSS 到底挂在谁身上 —— 不靠猜（他 14.20 那句"先去看那两个已克隆的项目怎么适配手机，看完再做"的下半句就是这个）。
set -u
NPM=${NPM:-/usr/local/lib/node_modules/@deepseek-ai}

echo "== 0. 时刻"
echo "  UTC $(date -u '+%F %T')  北京 $(TZ=Asia/Shanghai date '+%F %T' 2>/dev/null)"

echo "== 1. web 前端这份产物在哪、有多大、mtime 是什么时候"
for d in $NPM/dsh-web $NPM/dsh-web-frontend $NPM/dsh; do
  [ -d "$d" ] || continue
  echo "  $d 存在"
  find "$d" -maxdepth 3 -type d -name dist 2>/dev/null | sed 's/^/    dist: /'
done
for f in $(find $NPM -type d -name dist 2>/dev/null | head -4); do
  echo "  --- $f"
  ls -la "$f" 2>/dev/null | awk 'NR>1{printf "      %-34s %10s B  %s %s %s\n", $9, $5, $6, $7, $8}' | head -12
  ls -la "$f/assets" 2>/dev/null | awk 'NR>1{printf "      assets/%-30s %10s B\n", $9, $5}' | head -12
done

echo "== 2. CSS 产物里与「左栏 / 导航 / 滚动」有关的选择器命中情况"
CSS=$(find $NPM -name '*.css' 2>/dev/null | head -1)
echo "  取的第一份 CSS = ${CSS:-没找到}"
if [ -n "$CSS" ]; then
  echo "  CSS 字节 = $(stat -c %s "$CSS")"
  for pat in 'aside' 'nav' 'sidebar' 'rail' 'overflow-y' 'overflow:auto' 'orientation' 'max-height' 'dvh'; do
    printf '    %-14s 命中次数 = %s\n' "$pat" "$(grep -o "$pat" "$CSS" 2>/dev/null | wc -l)"
  done
  echo "  --- 含 sidebar/rail 的那几条规则原文（每条截 200 字，最多 8 条）"
  tr '}' '}\n' < "$CSS" 2>/dev/null | grep -iE 'sidebar|rail|aside' | head -8 | cut -c1-200 | sed 's/^/      /'
fi

echo "== 3. JS 产物里宿主自己标的 data-* 锚点（这一份才是能挂 CSS 的稳锚点）"
JS=$(find $NPM -path '*dist/assets*' -name '*.js' 2>/dev/null | head -1)
[ -n "$JS" ] || JS=$(find $NPM -name 'index*.js' -path '*dist*' 2>/dev/null | head -1)
echo "  取的第一份 JS = ${JS:-没找到}"
if [ -n "$JS" ]; then
  echo "  JS 字节 = $(stat -c %s "$JS")"
  echo "  --- data- 属性去重列表（截前 60 个）"
  grep -oE 'data-[a-zA-Z0-9_-]+' "$JS" 2>/dev/null | sort -u | head -60 | tr '\n' ' ' | fold -w 116 | sed 's/^/      /'
  echo "  --- 与侧栏/导航相关的几个各命中几次（同一条管道里的 grep -o 逐行相加）"
  for pat in 'data-sidebar[a-z-]*' 'data-nav[a-z-]*' 'data-mobile[a-z-]*' 'data-seat[a-z-]*'; do
    printf '      %-28s = %s\n' "$pat" "$(grep -oE "$pat" "$JS" 2>/dev/null | wc -l)"
  done
fi

echo "== 4. 页面上真写了什么（出口拿到的那份 HTML，只读一发）"
printf '  index.html = %s B，md5 %s\n' "$(find $NPM -name 'index.html' -path '*dist*' 2>/dev/null | head -1 | xargs stat -c %s 2>/dev/null)" \
  "$(find $NPM -name 'index.html' -path '*dist*' 2>/dev/null | head -1 | xargs md5sum 2>/dev/null | cut -c1-12)"
find $NPM -name 'index.html' -path '*dist*' 2>/dev/null | head -1 | xargs cat 2>/dev/null | cut -c1-600 | sed 's/^/      /'

echo "== 5. 服务侧现场（这一发不该动任何东西）"
echo "  含 'dsh web' 的进程数 = $(pgrep -f 'dsh web' | wc -l)  引擎 pid = $(pgrep -f 'dsh web' | head -1)"
echo "  兼容层那份 = $(stat -c %s /root/.dsh/entry-compat.js 2>/dev/null) B，改于 $(stat -c %y /root/.dsh/entry-compat.js 2>/dev/null | cut -d. -f1)"
echo " 完（探针 49 全只读：没 pull、没写盘、没重启）"
