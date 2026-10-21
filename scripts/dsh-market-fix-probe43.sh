#!/usr/bin/env bash
# dsh-market-fix-probe43.sh —— 只读：把「插件市场」的三条修法在同一次跑里量出绿不绿
#
# 前情（p42.txt 已经判死的）：手机上 .dsh-market/state.json 记的是 region=global（09:51:12Z 那次
# 「network check chose global」），global 区的目录源只有 awesome-dsh-plugin.com + registry.npmjs.org，
# 这两个 host 都不在 /etc/hosts 的钉表里 ⇒ 每回 4 次尝试、42 秒、"catalog fetch failed"。
# 前端那句「正在加载插件目录…」就是这 42 秒。路由本身是活的（:3080/dsh-market/* 回 401 要凭证，不是 404）。
#
# 这一发只量三条修法，一条都不落地：
#   A) 把市场导到 npmmirror（引擎 env 加一行 DSHM_NPM_MIRROR=https://registry.npmmirror.com）。
#      插件源码自己的话：「Every China npm mirror already carries it」，且它跟 dist.tarball 走、
#      镜像会把这字段改写成自己的 host ⇒ registry.npmmirror.com 与 cdn.npmmirror.com 都在钉表里就够了。
#   B) 把 awesome-dsh-plugin.com 钉进 hosts（= 往 doh-hosts.sh 名单里加一条；设备侧写盘，要他点头）。
#   C) 区改成 china 再把 mirrors.cloud.tencent.com 钉进 hosts。
# B 与 C 都要先知道「钉了 IP 连不连得通」——本机 doh-hosts.sh 自己的注释就写着 WATCH 那摞「钉了也连不通」，
# 所以这里用 --resolve 逐 host 试（口径写清楚：--resolve 是故意绕开解析、单独验 IP 通不通；
# 真落地的验收不能带 --resolve，得等 hosts 里真有那行再复点）。
set -u

NPMM=https://registry.npmmirror.com
PKG=dsh-plugin-catalog
DOH=https://223.5.5.5/resolve

echo "== 0. 时刻（chroot 是 UTC；北京 = UTC+8）"
echo "  UTC  $(date -u '+%F %T')"
echo "  北京 $(TZ=Asia/Shanghai date '+%F %T' 2>/dev/null || date '+%F %T')"

echo "== 1. 修法 A 第一步：npmmirror 上有没有这个包（这一发只取元数据 JSON，几十 KB）"
J=/tmp/p43_meta.json
curl -s -m 15 -H 'accept: application/json' -o "$J" \
  -w '  meta: code=%{http_code} dns=%{time_namelookup}s ttfb=%{time_starttransfer}s total=%{time_total}s got=%{size_download}B\n' \
  "$NPMM/$PKG/latest"
VER=$(node -e 'const j=require("'$J'");console.log(j.version||"")' 2>/dev/null)
TAR=$(node -e 'const j=require("'$J'");console.log((j.dist&&j.dist.tarball)||"")' 2>/dev/null)
echo "  version   = ${VER:-（没读到）}"
echo "  tarball   = ${TAR:-（没读到）}"
echo "  tarball 那个 host 在 hosts 里钉了吗：$(printf '%s' "$TAR" | awk -F/ '{print $3}' | while read -r h; do c=$(awk -v d="$h" '$2==d{n++} END{print n+0}' /etc/hosts); echo "$h ⇒ $([ "$c" -gt 0 ] && echo 在 || echo 不在)"; done)"

echo "== 2. 修法 A 第二步：真下那个 tarball，只跑 8 秒就断（正文丢掉；这是他的流量）"
if [ -n "$TAR" ]; then
  T=$(curl -sL -o /dev/null --max-time 8 -w '%{http_code} %{time_total} %{size_download}' "$TAR" 2>&1)
  set -- $T
  printf '  tarball: code=%s total=%ss got=%sB ⇒ %s B/s\n' \
    "$1" "$2" "$3" "$(awk -v b="$3" -v t="$2" 'BEGIN {if (t+0>0) printf "%.0f", b/t; else print "—"}')"
  # 改口（p43 读数回来后就地标的）：第一版把这格印成"8 秒截断，不是完整体积"，那是我写完就当它一定跑满 8 秒 ——
  # 实测 total=1.53s、code=200、got=2,582,974 B，是**整个包下完了**，不是截断。截不截断要由 code 与 total 判，不能由 --max-time 猜。
  echo "  （完整与否看上面：total 远小于 8 秒且 code=200 ⇒ got 就是完整体积；跑满 8 秒才是截断）"
else
  echo "  !! 第 1 步没拿到 tarball 地址，这一格跳过"
fi

echo "== 3. hosts 钉表现状（只数这几条相关的）"
for h in registry.npmmirror.com cdn.npmmirror.com mirrors.cloud.tencent.com awesome-dsh-plugin.com cdn.jsdelivr.net registry.npmjs.org; do
  c=$(awk -v d="$h" '!/^#/ && $2==d {n++} END {print n+0}' /etc/hosts)
  printf '  %-30s hosts 行数 = %s %s\n' "$h" "$c" "$([ "$c" -gt 0 ] && echo 已钉 || echo 未钉)"
done

echo "== 4. 修法 B / C：先问 DoH 要 IP，再拿 --resolve 单独验这个 IP 连不连得通（各 8 秒）"
for spec in \
  "B|awesome-dsh-plugin.com|https://awesome-dsh-plugin.com/plugins.json" \
  "C|mirrors.cloud.tencent.com|https://mirrors.cloud.tencent.com/npm/$PKG/latest" \
  "参考|cdn.jsdelivr.net|https://cdn.jsdelivr.net/npm/$PKG/index.json"
do
  LBL=$(printf '%s' "$spec" | cut -d'|' -f1); H=$(printf '%s' "$spec" | cut -d'|' -f2); U=$(printf '%s' "$spec" | cut -d'|' -f3)
  IPS=$(curl -sk -m 10 -H 'accept: application/dns-json' "$DOH?name=$H&type=A" 2>/dev/null |
        node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);console.log((j.Answer||[]).filter(x=>x.type===1).map(x=>x.data).join(","));}catch(e){console.log("")}});')
  if [ -z "$IPS" ]; then echo "  [$LBL] $H ⇒ DoH 没给 A 记录，跳过"; continue; fi
  IP=$(printf '%s' "$IPS" | cut -d, -f1)
  R=$(curl -s -o /dev/null -m 8 --resolve "$H:443:$IP" -w 'code=%{http_code} connect=%{time_connect}s ttfb=%{time_starttransfer}s got=%{size_download}B' "$U" 2>&1)
  printf '  [%s] %-26s DoH⇒%s  %s\n' "$LBL" "$H" "$IPS" "$R"
done

echo "== 5. 引擎现在这套 env 里 DSHM_ 开头的键有几个（只列键名与是否有值，不 dump 别的）"
EG=$(pgrep -f 'dsh web' | head -1)
if [ -n "$EG" ]; then
  tr '\0' '\n' < "/proc/$EG/environ" | grep '^DSHM' | sed 's/=.*$/=<有值>/' | sed 's/^/    /'
  echo "    DSHM_ 键计数 = $(tr '\0' '\n' < "/proc/$EG/environ" | grep -c '^DSHM')"
  echo "  --- 入口给它的那条命令（DSH_ENGINE_CMD，整条可读，里面没凭证）"
  tr '\0' '\n' < "/proc/$EG/environ" | grep '^DSH_ENGINE_CMD=' | sed 's/^/    /'
  echo "  --- 出生时刻与已活秒数（第 22 字段 + btime）"
  BOOT=$(awk '/^btime/ {print $2}' /proc/stat); UP=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1); HZ=$(getconf CLK_TCK 2>/dev/null); [ -n "$HZ" ] || HZ=100
  ST=$(awk '{print $22}' "/proc/$EG/stat" 2>/dev/null)
  [ -n "$ST" ] && printf '    pid %s 出生 %s UTC 活着 %s 秒\n' "$EG" "$(date -u -d "@$((BOOT + ST / HZ))" '+%F %T')" "$((UP - ST / HZ))"
else
  echo "    !! 没抓到 'dsh web' 进程"
fi

echo "== 6. 复点：路由还在不在（不带凭证打引擎；401=在且要登录，404=路由没挂上）"
for p in /dsh-market/status /dsh-market/registry; do
  printf '  3080 %-21s %s\n' "$p" "$(curl -s -o /dev/null --max-time 10 -w 'code=%{http_code} got=%{size_download}B' "http://127.0.0.1:3080$p" 2>&1)"
done

echo "== 7. 这 42 秒那一格：把 log.ndjson 最后三条再取一次（看第 6 节这几发有没有惊动它）"
tail -3 /root/.dsh/profiles/web/.dsh-market/log.ndjson 2>/dev/null | sed 's/^/      /'
echo "  log.ndjson = $(stat -c %s /root/.dsh/profiles/web/.dsh-market/log.ndjson 2>/dev/null) B，改于 $(stat -c %y /root/.dsh/profiles/web/.dsh-market/log.ndjson 2>/dev/null | cut -d. -f1)"
rm -f "$J"
echo "== 8. 本探针临时件删了吗"
ls -1 /tmp/p43_* 2>&1 | sed 's/^/  /'
echo " 完（只写了 /tmp/p43_meta.json 一件并已删；没动 hosts、没改 env、没重启引擎、没点「应用」、没替他开任何页面）"
