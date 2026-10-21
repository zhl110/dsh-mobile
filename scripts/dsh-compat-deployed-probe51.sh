#!/usr/bin/env bash
# dsh-compat-deployed-probe51.sh —— 只读复点：兼容层换新一份之后，出口内联出来的 HTML 里到底有没有那段侧栏补丁。
#
# 为什么单独一发：他报的横屏那个症状发生在**页面里**，curl 看不见渲染，但能看见两件事：
#   ① 盘上 /root/.dsh/entry-compat.js 是不是我本地那一份（按字节 + md5 撞）；
#   ② 出口 :3081 吐出来的 HTML 里内联段带不带新加的那段（数 data-dsh-side-scroll 这个属性名出现几次）。
# 这两条过了，剩下的"横屏能不能划"就只能在屏幕上验 —— 那是他的手指，不是我能在终端里替的。
#
# 顺带把老账再守一遍：内联段里那句注释含一个 script 开标签（tools/dsh-compat.js 第 8 行，
# 2026-10-20 真机就是栽在它上面，源码漏成屏幕上一片代码），所以这里专门数一下
# "转义后的形态在不在、没转义的形态有没有混进来"。
set -u
LOCAL_MD5=${1:-}
KEY=/root/.dsh/entry.key
CF=/root/.dsh/entry-compat.js

echo "== 0. 时刻"
echo "  UTC  $(date -u '+%F %T')   北京 $(TZ=Asia/Shanghai date '+%F %T' 2>/dev/null)"

echo "== 1. 盘上那份兼容脚本"
echo "  $CF = $(stat -c %s "$CF" 2>/dev/null) B，改于 $(stat -c %y "$CF" 2>/dev/null | cut -d. -f1)，mode=$(stat -c %a "$CF") owner=$(stat -c %U "$CF")"
echo "  md5 = $(md5sum "$CF" 2>/dev/null | cut -d' ' -f1)   （Windows 侧那份的 md5 我带进来了：${LOCAL_MD5:-没传}）"
[ -n "$LOCAL_MD5" ] && [ "$(md5sum "$CF" | cut -d' ' -f1)" = "$LOCAL_MD5" ] \
  && echo "  [ok] 逐字节相同" || { [ -n "$LOCAL_MD5" ] && echo "  !! 与本地不等"; }
echo "  里面有没有那段补丁：data-dsh-side-scroll 出现 $(grep -o 'data-dsh-side-scroll' "$CF" | wc -l) 次；__DSH_SIDE__ 出现 $(grep -o '__DSH_SIDE__' "$CF" | wc -l) 次"

echo "== 2. 出口内联出来的 HTML（带口令从 stdin 递，口令不进 argv）"
PAGE=/root/.dsh/p51-page.html
printf 'cookie = dsh-entry=%s\nurl = "http://127.0.0.1:3081/"\noutput = "%s"\n' "$(cat "$KEY" 2>/dev/null)" "$PAGE" \
  | curl -sS -K - --max-time 20 -w '  http=%{http_code} bytes=%{size_download} time=%{time_total}s\n' || echo "  !! 取不到（入口没在听？）"
echo "  取到的这份 = $(stat -c %s "$PAGE" 2>/dev/null) B"
echo "  --- 内联标记与那段补丁"
echo "      data-dsh-entry-compat 开标签 = $(grep -o 'data-dsh-entry-compat' "$PAGE" | wc -l)（要 1）"
echo "      data-dsh-side-scroll 出现     = $(grep -o 'data-dsh-side-scroll' "$PAGE" | wc -l)"
echo "      __DSH_SIDE__ 出现             = $(grep -o '__DSH_SIDE__' "$PAGE" | wc -l)"
echo "      锚点文字「新会话」在那份 HTML 里 = $(grep -o '新会话' "$PAGE" | wc -l)（这是补丁要抓的文字，它在 dsh 自己的 JS 里，不在 HTML —— 0 不说明失败）"
echo "  --- 老那一条事故：注释里的 script 开标签必须是被转义过的形态"
echo "      未转义 <script src= 形态 = $(grep -o '<script src=' "$PAGE" | wc -l)（要 0）"
echo "      已转义 <\\/script> 形态  = $(grep -o '<\\\\/script>' "$PAGE" | wc -l)（要 ≥1）"
echo "      HTML 里 script 标签总数  = $(grep -o '<script' "$PAGE" | wc -l)"
echo "  --- 首页该有的三样还在不在（证明我没把注入搞坏）"
for w in 'index-CN7NIWNw.js' 'vendor-DcuzkuQH.js' 'index-BxpfOGf3.css' 'id="root"'; do
  echo "      $w = $(grep -o "$w" "$PAGE" | wc -l)"
done

echo "== 3. 服务侧复点（兼容层是热读，这一发不该有任何换代）"
echo "  含 'dsh web' 进程数 = $(pgrep -f 'dsh web' | wc -l)  引擎 pid = $(pgrep -f 'dsh web' | head -1)（14.28 那格起是 21363，变了就是换代了）"
echo "  入口 pid = $(pgrep -f dsh-entry.js | head -1)  监听命中数 = $(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:(3080|3081)$/' | wc -l)"
echo "  入口日志（CFG.log=/root/.dsh/entry.log）里最近两条兼容脚本行："
grep -a '兼容脚本' /root/.dsh/entry.log 2>/dev/null | tail -2 | sed 's/^/      /'
for f in /root/.dsh/entry.log /data/local/dsh.log; do
  [ -f "$f" ] && echo "      （$f 存在 = $(stat -c %s "$f") B，改于 $(stat -c %y "$f" | cut -d. -f1)）"
done

echo "== 4. 顺手复点这一轮装的东西还在不在（apt 与服务互不相干，验一遍安心）"
for c in git python3 pip3 gcc make cmake ffmpeg convert pdftoppm sqlite3 unzip tmux rsync wget file; do
  printf '    %-10s %s\n' "$c" "$(command -v $c 2>/dev/null || echo 缺)"
done
echo "    dpkg ii 计数 = $(dpkg -l 2>/dev/null | awk '$1=="ii"' | wc -l)（装这轮之前是 141）"

echo "== 5. 删掉我自己留的这份临时页"
rm -f "$PAGE" && echo "  已删 $PAGE；/root/.dsh 下现在 p51* 计数 = $(ls -1 /root/.dsh/p51* 2>/dev/null | wc -l)（要 0）"
echo " 完（探针 51 全只读 + 只删自己这一份临时页；没重启、没改 hosts、没点屏幕）"
