#!/usr/bin/env bash
# dsh-inline-integrity-probe52.sh —— 把探针 51 里我自己写歪的那两条判据按读数改回来，并补一条真判据。
#
# 51 第 2 节我数「未转义 <script src=」要 0、「已转义 <\/script>」要 ≥1，两条都不符 —— 但这**是我的探针写错了**，
# 不是页面坏了：① `grep -o '<\\\\/script>'` 传下去的模式匹配的是**两个**反斜杠，而实际转义产物只有一个；
# ② `<script src=` 在页面上本来就合法（上游自己的 module script 就是它，compat 注释里那句也只是文本），
#   2026-10-20 那次事故的真判据是**内联段里出现没转义的 `</script>` 会提前闭合**，与 `<script src=` 无关。
# 所以这一发改用 python3（这轮刚装上的）做**精确子串计数**，并把入口自己的计数器读出来当硬证：
# injected 在涨、injectMiss 必须是 0。
set -u
KEY=/root/.dsh/entry.key
CF=/root/.dsh/entry-compat.js

echo "== 0. 时刻"
echo "  UTC  $(date -u '+%F %T')   北京 $(TZ=Asia/Shanghai date '+%F %T' 2>/dev/null)"

echo "== 1. 取两页面：带口令的 :3081（内联过）与 :3080（引擎原样，不内联）"
A=/root/.dsh/p52-3081.html; B=/root/.dsh/p52-3080.html
printf 'cookie = dsh-entry=%s\nurl = "http://127.0.0.1:3081/"\noutput = "%s"\n' "$(cat "$KEY")" "$A" \
  | curl -sS -K - --max-time 20 -o "$A" -w '  :3081 http=%{http_code} bytes=%{size_download}\n'
printf 'url = "http://127.0.0.1:3080/"\noutput = "%s"\n' "$B" \
  | curl -sS -K - --max-time 20 -o "$B" -w '  :3080 http=%{http_code} bytes=%{size_download}（401 是设计，不带 token 就这样）\n'
echo "  :3081 那份 = $(stat -c %s "$A" 2>/dev/null) B   :3080 那份 = $(stat -c %s "$B" 2>/dev/null) B"

echo "== 2. python3 精确计数（这是本轮新装的工具，正好用上）"
python3 - "$A" "$CF" <<'PY' | sed 's/^/  /'
import sys
page = open(sys.argv[1], 'rb').read()
src  = open(sys.argv[2], 'rb').read()
opentag = b'<script data-dsh-entry-compat="1">'
print('页面字节          =', len(page))
print('compat 字节       =', len(src))
print('我们的开标签      =', page.count(opentag), '（要 1）')
print('未转义 </script>  =', page.count(b'</script>'), '（这是页面上真正会闭合的标签数）')
print('转义 <\\/script>   =', page.count(b'<\\/script>'), '（内联段里那个注释的产物，要 >=1）')
print('未转义 <!--       =', page.count(b'<!--'), '（内联段里若有裸注释会改变解析，上游页面自己带的算合法）')
print('data-dsh-side-scroll 在页面里 =', page.count(b'data-dsh-side-scroll'))
# 关键判据：把内联段整块剥掉，剩下的应当与「上游那一份」同形状（这里没有引擎原页可比，
# 所以退一步验：开标签之后紧跟的内容字节，去掉转义差异后应与 compat 同长度级）
i = page.find(opentag)
if i >= 0:
    j = page.find(b'\n</script>\n', i)
    seg = page[i+len(opentag)+1:j]
    print('内联段字节        =', len(seg), '（compat', len(src), 'B；差 =', len(seg)-len(src), '，差来自转义后变长的部分）')
    print('内联段闭合于      =', 'OK 找到了换行+</script>' if j > 0 else '!! 没找到闭合 —— 这段会吞掉后面的标签')
PY

echo "== 3. 入口自己的计数器（injected 要涨、injectMiss 必须是 0）"
printf 'cookie = dsh-entry=%s\nurl = "http://127.0.0.1:3081/__entry_status"\n' "$(cat "$KEY")" \
  | curl -sS -K - --max-time 15 2>/dev/null > /root/.dsh/p52-status.txt
echo "  自述页 = $(stat -c %s /root/.dsh/p52-status.txt 2>/dev/null) B"
python3 - /root/.dsh/p52-status.txt <<'PY' | sed 's/^/  /'
import sys,re
t=open(sys.argv[1],encoding='utf-8',errors='replace').read()
for k in ["req","denied","injected","injectMiss","up401","reauth","ws","engineStart","exit"]:
    m=re.search(r"\b%s\b\s*=\s*(\d+)"%k,t)
    if m: print("%-11s = %s"%(k,m.group(1)))
for pat in [r"兼容脚本[^\n]*", r"lastErr[^\n]*", r"最近请求[^\n]*"]:
    m=re.search(pat,t)
    if m: print(m.group(0)[:150])
PY

echo "== 4. 最近请求流水里这轮的 market 路由还在不在（上一发 200 的证据别掉出窗口）"
grep -a 'dsh-market' /root/.dsh/p52-status.txt 2>/dev/null | head -4 | sed 's/^/      /'

echo "== 5. 服务复点"
echo "  引擎 pid = $(pgrep -f 'dsh web' | head -1)（要仍是 21363）  含 'dsh web' 进程数 = $(pgrep -f 'dsh web' | wc -l)"
echo "  hosts 生效行数 = $(grep -vc '^#\|^$' /etc/hosts)（要 28）"
rm -f "$A" "$B" /root/.dsh/p52-status.txt; echo "  已删三份临时件；残留 = $(ls -1 /root/.dsh/p52* 2>/dev/null | wc -l)（要 0）"
echo " 完（探针 52 全只读 + 只删自己的临时页；没重启、没改文件、没点屏幕）"
