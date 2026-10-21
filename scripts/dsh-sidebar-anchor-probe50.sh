#!/usr/bin/env bash
# dsh-sidebar-anchor-probe50.sh —— 只读：把「横屏左栏要能滚」这一段 CSS 的锚点取出来（宿主 data-* + 真产物里的类名）
#
# 上一发（探针 49）取错了文件：`find -name '*.css' | head -1` 命中的是 devtools 的 tokens.css，
# `dist/assets/*.js | head -1` 命中的是 langs/asciidoc（语法包）。这一发按 index.html 里真写的那三个文件名取：
#   assets/index-CN7NIWNw.js  assets/vendor-DcuzkuQH.js  assets/vendor-DV2921Zo.css  assets/index-BxpfOGf3.css
set -u
D=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-web-frontend/dist
A=$D/assets

echo "== 0. 时刻"
echo "  UTC $(date -u '+%F %T')"

echo "== 1. dist/assets 顶层清单（只列这一层，langs/icons 那些子目录不进）"
ls -la "$A" 2>/dev/null | awk 'NR>1 && $9!=""{printf "  %-38s %10s B\n", $9, $5}' | head -24
echo "  顶层文件数 = $(find "$A" -maxdepth 1 -type f 2>/dev/null | wc -l)  子目录数 = $(find "$A" -maxdepth 1 -type d 2>/dev/null | tail -n +2 | wc -l)"
echo "  dist 总字节（du -sk）= $(du -sk "$D" 2>/dev/null | cut -f1) KB"

JS=$(ls -1 "$A"/index-*.js 2>/dev/null | head -1)
VD=$(ls -1 "$A"/vendor-*.js 2>/dev/null | head -1)
CSS=$(ls -1 "$A"/index-*.css 2>/dev/null | head -1)
VCSS=$(ls -1 "$A"/vendor-*.css 2>/dev/null | head -1)
echo "  取到的四份：JS=${JS:-无} VENDOR_JS=${VD:-无} CSS=${CSS:-无} VENDOR_CSS=${VCSS:-无}"

echo "== 2. 宿主自己标的 data-* 锚点（在 index.js 与 vendor.js 两份里各数一遍）"
for f in "$JS" "$VD"; do
  [ -n "$f" ] || continue
  echo "  --- $(basename "$f")（$(stat -c %s "$f") B）data- 命中总次数 = $(grep -oE 'data-[a-zA-Z0-9_-]+' "$f" 2>/dev/null | wc -l)"
  grep -oE 'data-[a-zA-Z0-9_-]+' "$f" 2>/dev/null | sort | uniq -c | sort -rn | head -30 | awk '{printf "      %5s  %s\n", $1, $2}'
done

echo "== 3. 与侧栏/导航/滚动有关的 CSS 规则原文（选择器 + 截 220 字）"
for f in "$CSS" "$VCSS"; do
  [ -n "$f" ] || continue
  echo "  --- $(basename "$f")（$(stat -c %s "$f") B）"
  for pat in 'sidebar' 'side-bar' '_rail' 'nav' 'aside' 'overflow' 'orientation' 'dvh' 'vh'; do
    printf '      %-12s 命中次数 = %s\n' "$pat" "$(grep -o "$pat" "$f" 2>/dev/null | wc -l)"
  done
done
echo "  --- index CSS 里含 sidebar 的规则（最多 12 条）"
[ -n "$CSS" ] && tr '}' '}\n' < "$CSS" | grep -i 'sidebar' | head -12 | cut -c1-220 | sed 's/^/      /'
echo "  --- index CSS 里含 竖排导航那一段（找「新会话/插件」那一列的容器：含 nav 且含 flex 或 overflow 的）"
[ -n "$CSS" ] && tr '}' '}\n' < "$CSS" | grep -i 'nav' | grep -iE 'flex|overflow|height' | head -12 | cut -c1-220 | sed 's/^/      /'

echo "== 4. 把 index 那份 CSS 复制一份到宿主 /data/local/tmp 供 Windows 侧 pull（唯一名字，pull 完我删）"
TAG=$(date -u +%H%M%S)
STAGED=/data/local/dsh-rootfs/tmp/p50-$(basename "$CSS").$TAG.css
cp "$CSS" "$STAGED" 2>/dev/null && echo "  已复制 → $STAGED（$(stat -c %s "$STAGED") B）" || echo "  !! 复制失败（这台机 rootfs/tmp 不可写？），那就改在 chroot 内 grep，结论已在第 3 节"

echo " 完（探针 50：只在 /data/local/dsh-rootfs/tmp 下留了一份 CSS 副本，没动 dist 一个字节、没重启）"
