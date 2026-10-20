#!/bin/bash
# dsh-entry-check.sh —— 入口这条链路的现场体检（在 chroot 里以 root 跑，全程只读、零出网）
#
# 为什么要有这个文件：一次「页面 200 了」不够。上一轮真出事的是**顺序**（polyfill 落到引擎脚本后面），
# 那种问题 HTTP 码看不出来，只有把字节偏移、上游盘上是什么、入口自己的计数摆在一起才看得见。
# 所以这份脚本把五件事一次报齐：环境 / 门禁 / 真首页的字节顺序 / 入口自述 / 上游文件有没有被我们动过。
#
# 跑法（Windows 侧一条命令，或直接 sh tools/deploy-entry.sh --check）：
#   adb shell "su -c 'sh /data/local/sh/dsh-chroot.sh --run bash /root/dsh-entry-check.sh'"
# 注意：--run 后面不能再出现分号或单引号 —— 那层会被 Android 侧的 sh 先切走，后半截就在手机上跑了
# （2026-10-20 实测：wc 在 chroot 里给出 876，紧跟其后的 grep 却在 Android 侧报 No such file）。
# 要多条命令就写进这个文件，别在命令行上串。
#
# 红线：口令值与 token 值一律不打印；只读，不改任何盘上文件。
set -u
KEY_FILE=${KEY_FILE:-/root/.dsh/entry.key}
ENTRY=${ENTRY:-http://127.0.0.1:3081/}
UP=${UP:-http://127.0.0.1:3080/}
DIST=${DIST:-/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-web-frontend/dist/index.html}
PAGE=/tmp/dsh-entry-check-page.html

sec() { printf '\n=== %s ===\n' "$*"; }
key() { tr -d '\r\n' < "$KEY_FILE"; }
# 带口令取一次：cookie 从 stdin 交给 curl -K -，这样口令不进 argv（ps 看得见）、不进命令行历史
get() { # get <url> <额外 -K 行>
  printf 'cookie = dsh-entry=%s\n%s\n' "$(key)" "${2:-}" | curl -sS -K - --max-time 20 "$1"
}

sec '环境'
echo "  node  $(node --version 2>&1)"
echo "  dsh   $(dsh --version 2>&1 | tail -1)"
echo "  内核  $(uname -m) $(cut -d' ' -f3 /proc/version 2>/dev/null)"

sec '入口口令文件'
if [ -r "$KEY_FILE" ]; then
  echo "  在位 $(wc -c < "$KEY_FILE") B，mode $(stat -c '%a %U:%G' "$KEY_FILE")（值不打印）"
  [ -s "$KEY_FILE" ] && echo "  内容非空" || echo "  !! 空文件 ⇒ 入口起不来"
else
  echo "  !! 读不到 $KEY_FILE"
fi

sec '门禁（三种不该放行的，都要 404 而不是 403）'
echo "  无 cookie        -> $(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "$ENTRY" 2>/dev/null || echo 连不上)"
echo "  错 cookie        -> $(printf 'cookie = dsh-entry=wrongvalue\n' | curl -sS -K - -o /dev/null -w '%{http_code}' --max-time 8 "$ENTRY" 2>/dev/null || echo 连不上)"
echo "  错 Host(DNS 重绑) -> $(printf 'cookie = dsh-entry=%s\n' "$(key)" | curl -sS -K - -H "Host: evil.example" -o /dev/null -w '%{http_code}' --max-time 8 "$ENTRY" 2>/dev/null || echo 连不上)"
echo "  裸上游 :3080      -> $(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "$UP" 2>/dev/null || echo 连不上)（401 才是对的，那是 dsh 自己的鉴权）"

sec '同源栅栏差分（他手机上那句 HTTP 403 的判据）'
# 引擎里 isTrustedApiRequest() 要求 Origin 的 host:port 逐字等于 Host 头，否则 403；入口换 Host 时
# 必须连 Origin 一起换。裸引擎上实测（2026-10-20）：Origin=:3081 ⇒ 403，Origin=:3080 ⇒ 401，不带 ⇒ 401。
# 穿过入口这一侧同一天量到：修之前「带 Origin ⇒ 403 / 不带 ⇒ 404」，修之后两条都 404。
# 这一节每次跑都重打一遍：它是那种「一次修好、dsh 一升级又可能坏回去」的判据。
BASE=${ENTRY%/}
probe() { # probe <路径> <说明> <额外的 -H 参数...>
  p="$1"; label="$2"; shift 2
  printf 'cookie = dsh-entry=%s\n' "$(key)" | curl -sS -K - -o /dev/null --max-time 8 -w "  ${label}  %{http_code}   ${p}\n" "$@" "${BASE}${p}"
}
probe /api/session/list '对照·带 Origin=:3081（浏览器视角）' -H 'origin: http://127.0.0.1:3081'
probe /api/session/list '对照·不带 Origin（导航请求）   '
# 对照那两条只证明"栅栏放没放行"（这条路径本来就不存在，放行了就是 404）。他那句 403 报的是
# 目录选择器那一族，而这一族**不是 GET 路径**：盘上抓到的字面量是 RPC 方法名
# （2026-10-20 读数：directoryPicker/list ×9、directoryPicker/pick ×6、directoryPicker/createDirectory ×18，
# 出处 ce-controller/src/directory-picker.ts 与 api/workspace-controller/src/directory-picker.ts）。
# 所以这里两件事分开做：① 确认这些方法名还在盘上（升级改名了这段就该变红）；
# ② 拿一条** POST + 带 Origin** 的请求打差分 —— 浏览器点选择器时发的就是这一形状。
RPCLIKE=$(timeout 30 grep -rhoE 'directoryPicker/[a-zA-Z]+' /usr/local/lib/node_modules/@deepseek-ai/dsh --include='*.js' 2>/dev/null | sort | uniq -c | sort -rn | head -3)
if [ -z "$RPCLIKE" ]; then
  echo "  !! 盘上没抓到 directoryPicker/* 方法名（dsh 换了实现或搜超时）⇒ 这一段没量到，别读成通过"
else
  printf '  盘上的选择器方法名：%s\n' "$(printf '%s\n' "$RPCLIKE" | tr '\n' ' ')"
fi
probe /api/rpc 'POST·带 Origin=:3081（选择器形状）' -X POST -H 'content-type: application/json' -H 'origin: http://127.0.0.1:3081' -d '{"method":"directoryPicker/list"}'
probe /api/rpc 'POST·不带 Origin                  ' -X POST -H 'content-type: application/json' -d '{"method":"directoryPicker/list"}'
printf '  读法：403 = 引擎的同源栅栏把这行拦在门外（Origin 的 host:port 没等于 Host 头），\n'
printf '        跟"没连 API / 没登录"无关 —— 这三条都带着口令，走的是鉴权之后那一层。\n'
printf '        404/401/200 都算栅栏放行；真机上最有价值的那条读数不在这里，而在入口自述的\n'
printf '        「非 2xx」环里：他在 App 里点一次选择器，哪条路径、什么码就落在环里（下面那段有打印）。\n'

sec '带口令取真首页 + 字节顺序'
printf 'cookie = dsh-entry=%s\n' "$(key)" \
  | curl -sS -K - -o "$PAGE" -w '  http=%{http_code} bytes=%{size_download} time=%{time_total}s\n' --max-time 20 "$ENTRY"
[ -s "$PAGE" ] || { echo "  !! 首页取回来是空的"; exit 1; }
# 这段 JS 整块包在 shell 的单引号里 ⇒ **体内出现任何一个单引号都会把外层引号截断**，
# 症状是 node 报语法错并把后面几行原样打到屏幕上（2026-10-20 我自己在这摔了一次：
# 判据里写了 s.indexOf('<' + ...)）。要写字符串一律用双引号；需要反斜杠时用 String.fromCharCode(92)。
node -e '
const fs=require("fs");
const s=fs.readFileSync(process.argv[1],"utf8");
const noTag=s.replace(/<script data-dsh-entry-compat="1">\n[\s\S]*?\n<\/script>\n/,"");
const ours=/<script data-dsh-entry-compat/.exec(s);
const firstUp=/<script[\s>]/i.exec(noTag);
const mod=/<script[^>]+type=["\x27]module["\x27][^>]*>/i.exec(noTag);
console.log("  页面 "+Buffer.byteLength(s)+" B；摘掉我们的 tag 是 "+Buffer.byteLength(noTag)+" B（差 "+(Buffer.byteLength(s)-Buffer.byteLength(noTag))+" B）");
console.log("  我们的内联      at="+(ours?ours.index:-1));
console.log("  上游第一段脚本  at="+(firstUp?firstUp.index:-1)+"  "+(firstUp?JSON.stringify(noTag.slice(firstUp.index,firstUp.index+62)):"(无)"));
console.log("  第一段 module   at="+(mod?mod.index:-1)+"  "+(mod?JSON.stringify(noTag.slice(mod.index,mod.index+68)):"(无)"));
const ok=ours&&firstUp&&ours.index<firstUp.index;
console.log("  顺序  "+(ok?"ok：polyfill 排在引擎任何脚本之前":"BAD：polyfill 没排在最前"));
// 2026-10-20 真机事故那一条的判据：内联元素**关得对不对**，以及关掉之后紧跟的是不是标签。
// 解析器在 script 数据态里只认第一个 </script（不看 JS 语法），源码里漏一个就整段提前关掉，
// 剩下的字节变成页面上的一段可见文字 —— 上面那条"顺序 ok"照样绿，所以顺序判据管不了这件事。
const closeTag=/<script data-dsh-entry-compat="1">\n[\s\S]*?\n<\/script>\n/;
const m=closeTag.exec(s);
const after=m?s.slice(m.index+m[0].length,m.index+m[0].length+58):"(没匹配到我们的整段)";
console.log("  我们这段之后紧跟  "+JSON.stringify(after)+"  → "+(/^</.test(after)?"是标签，没漏出裸文本":"BAD：漏出裸文本，屏幕上会刷代码"));
const bare=s.replace(/<script[\s\S]*?<\/script>/g,"").replace(/<style[\s\S]*?<\/style>/g,"");
console.log("  摘掉所有 script/style 之后，正文里还有 polyfill 源码吗  "
  +(/AbortSignal|doAbort/.test(bare)?"BAD：有（这段会被当文字显示）":"没有（应为没有）")
  +"；正文可见文本 "+bare.replace(/<[^>]*>/g,"").trim().length+" 字符");
console.log("  内联段里 </script 的转义形式  "+(s.indexOf("<" + String.fromCharCode(92) + "/script") >= 0 ? "在（对，注释里那个被转义了）" : "不在（BAD：转义没生效）"));
console.log("  页面里引用 dsh-compat.js  "+(noTag.match(/dsh-compat\.js/g)||[]).length+" 处（2026-10-20 起应为 0：就地补丁已还原成上游原样）");
console.log("  页面里出现明文入口口令吗  "+(s.match(/dsh-entry=[A-Za-z0-9_-]{6,}/g)||[]).length+" 处（应为 0）");
' "$PAGE"

sec '静态资源耗时（"点起来迟钝"要有数，不能只凭手感）'
# 为什么单列这一段：2026-10-20 入口新加的请求流水里，App 一次冷加载的四条静态资源全是 ~160 ms
# （css 77 KB 与 js 940 KB 都是 157-163 ms —— 这个"跟体积无关的固定值"要么是引擎每请求有固定开销，
# 要么是 WebView 并发排队，两种的治法完全不同）。curl 单条串行地量一遍，就能把"WebView 的并发"
# 这一项先减掉。量出来若仍是固定 ~160 ms，那开销在引擎侧，不在我们这一层。
# 资源名从**出口实际发出去的那一页**上抓（dsh 一升级哈希就变，钉死名字等于下次跑空）。
BASE=${ENTRY%/}
# 但抓之前必须先摘掉我们内联的那段：polyfill 注释里原样写着
# `<script src="./assets/dsh-compat.js"></script>`（tools/dsh-compat.js:8），照着整页抓就会把这句
# 注释当成一条真资源去请求，量出一个 404 —— 2026-10-20 第一次跑就是这样，看着像"资源挂了"，其实是我们自己的注释。
CLEAN=/tmp/dsh-entry-check-clean.html
awk '/<script data-dsh-entry-compat="1">/{skip=1} skip{if (/<\/script>/) {skip=0}; next} {print}' "$PAGE" > "$CLEAN" \
  || { echo "  !! 摘内联没成功（chroot 里没 awk？），退回用整页抓 ⇒ 会多出一条注释里的 dsh-compat.js，那是 404 但不是故障"; cp "$PAGE" "$CLEAN"; }
echo "  抓名字用的干净页 $(wc -c < "$CLEAN") B（整页 $(wc -c < "$PAGE") B；差就是我们那段内联）"
ASSETS=$(sed -n 's/.*href="\.\(\/assets\/[^"]*\)".*/\1/p;s/.*src="\.\(\/assets\/[^"]*\)".*/\1/p' "$CLEAN" 2>/dev/null | sort -u | head -4)
[ -n "$ASSETS" ] || ASSETS=$(grep -o 'assets/[A-Za-z0-9._-]*' "$CLEAN" | sort -u | head -4 | sed 's|^|/|')
if [ -z "$ASSETS" ]; then
  echo "  !! 页面上没抓到 /assets/* 名字，这一段没量到（别把没量到读成没问题）"
else
  for p in $ASSETS; do
    printf 'cookie = dsh-entry=%s\n' "$(key)" | curl -sS -K - -o /dev/null --max-time 30 \
      -w "  ${p}  %{http_code}  %{size_download} B  总 %{time_total}s（连 %{time_connect}s）\n" "${BASE}${p}"
  done
  FIRST=$(printf '%s\n' "$ASSETS" | tail -1)
  printf '  最后那条再来一次（看有没有热起来）：'
  printf 'cookie = dsh-entry=%s\n' "$(key)" | curl -sS -K - -o /dev/null --max-time 30 \
    -w "%{http_code} %{size_download} B  %{time_total}s\n" "${BASE}${FIRST}"
fi

sec '入口自述'
get "${ENTRY}__entry_status" | sed 's/^/  /'

sec '上游盘上的首页（我们不该动它）'
if [ -f "$DIST" ]; then
  echo "  $(wc -c < "$DIST") B  mode $(stat -c '%a %U:%G' "$DIST")  $DIST"
  echo "  引用 dsh-compat：$(grep -c dsh-compat "$DIST") 行"
  echo "  我们的内联标记：$(grep -c data-dsh-entry-compat "$DIST") 行（必须是 0 —— 内联只在出口做，不落盘）"
  ls -l "$DIST".orig "$DIST".bak 2>/dev/null | sed 's/^/  旧备份 /'
  # 2026-10-20 把当年那句就地补丁还原掉了：盘上首页回到上游原样，polyfill 只在出口内联。
  # 两个方向各留一份逐字节副本，还原这件事本身要可逆：
  BK=/root/.dsh/index.html.patched-876.bak
  [ -f "$BK" ] && echo "  补丁那版(876 B)的备份 $(wc -c < "$BK") B  md5 $(md5sum "$BK" | cut -c1-8)…  $BK" \
    || echo "  !! 补丁那版(876 B)的备份不在 ⇒ 只能从 Windows 侧 reference/dsh-web-frontend-index.html 推回去"
  [ -f /data/local/sh/index.html.orig-dshmobile ] \
    && echo "  上游原样(825 B)的备份 $(wc -c < /data/local/sh/index.html.orig-dshmobile) B  md5 $(md5sum /data/local/sh/index.html.orig-dshmobile | cut -c1-8)…  /data/local/sh/index.html.orig-dshmobile"
  [ -f "$(dirname "$DIST")/assets/dsh-compat.js" ] \
    && echo "  assets/dsh-compat.js 在位：$(wc -c < "$(dirname "$DIST")/assets/dsh-compat.js") B（这是历史遗留的就地补丁文件）" \
    || echo "  assets/dsh-compat.js 不在 ⇒ 上游没被我们塞过文件"
else
  echo "  !! 找不到 $DIST"
fi

sec '日志与残留'
echo "  入口日志 $(ls -l /root/.dsh/entry.log 2>/dev/null | tr -s ' ' || echo '(无)')"
echo "  引擎日志 $(ls -l /data/local/dsh.log 2>/dev/null | tr -s ' ' || echo '(宿主侧，chroot 里看不见，正常)')"
echo "  体检页落盘 $(ls -l "$PAGE" 2>/dev/null | tr -s ' ' || echo '(无)') —— 里面只有 HTML，不含口令"
