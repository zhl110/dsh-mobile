#!/bin/bash
# 探针 67（只读）—— 接线前的四处复点 + 四批合起来的并集 + 引擎有没有可编程的那扇。
# 为什么先跑这个不直接写：
#   ① 归档里那条接线形状（RUNBOOK-archived.md:878 那段）把 runnerCommand 写在了 `- id: sandbox-policy` 底下，
#      而 runnerCommand 是 **dsh-sandbox-local** 的 Config（本机实测只有 ./dsh-sandbox-local/lib/index.js 引它），
#      sandbox-policy 那个包只吃 mode。zod 的 object 默认**不 strict** ⇒ 键放错 id 底下会被静默丢掉，
#      配置"看着接了其实没接"。所以先把两个 id 的真名与现有那份文件的形状读回来，再决定插哪。
#   ② 四批各自量的时候有重复（systemd 同时出现在语言栈与容器的差集里），并起来才是他要的那个总数。
#   ③ 端到端只靠"他在 App 里发一句话"太慢，先看引擎有没有能提交一轮的路由。
# 全程不写盘、不重启、不读凭据内容（.dsh-env 与 cordis 只按锚定正则取需要的行，并报被滤掉的行数）。
set -u
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
echo "chroot 内时刻: $(date '+%F %T %Z')"
MB=1048576
ALL="libreoffice-writer pandoc tesseract-ocr rustc golang-go default-jdk docker.io podman"

names() {
  apt-get -s install $1 $2 2>/dev/null \
    | awk '/^Inst /{n=$2; sub(/:.*/,"",n); if(!(n in seen)){seen[n]=1; print n}}'
}
uris() {
  local T=0 C=0 N=0 F SZ B
  while read -r U F SZ REST; do
    [ -n "${SZ:-}" ] || continue
    N=$((N+1)); T=$((T+SZ)); B=${F##*/}
    if [ -f "/var/cache/apt/archives/$B" ] || [ -f "$F" ]; then C=$((C+SZ)); fi
  done < <(apt-get install --print-uris -qq $1 $2 2>/dev/null)
  echo "$T $C $N"
}
kbmap() {
  apt-cache show $1 2>/dev/null | awk '
    /^Package: /{p=$2; next}
    /^Installed-Size: /{ if(!(p in s)){s[p]=$2+0} }
    END{for(q in s) printf "%d %s\n", s[q], q}'
}

echo "== ① 四批合起来（并集，去掉互相重复的那部分）"
for MODE in "" "--no-install-recommends"; do
  NM=$(names "$MODE" "$ALL"); N=$(printf '%s\n' "$NM" | grep -c .)
  read -r T C UN <<<"$(uris "$MODE" "$ALL")"
  KB=$(kbmap "$NM"); TOT=$(printf '%s\n' "$KB" | awk '{s+=$1} END{print s+0}')
  printf '   %-24s 包数=%-5s 需下载 %7.1f MB（缓存里已有 %5.1f MB）装完占盘 %7.1f MB\n' \
    "${MODE:-含 recommends}" "$N" \
    "$(awk -v x=$T -v m=$MB 'BEGIN{print x/m}')" "$(awk -v x=$C -v m=$MB 'BEGIN{print x/m}')" \
    "$(awk -v x=$TOT 'BEGIN{print x/1024}')"
done
echo "   对照：四批各量各的加起来是 161+6+103+78=348（含）/ 84+6+63+29=182（不含），上面这个数才是真数"
DF=$(df -h / | awk 'NR==2{print $4" 可用 / 共 "$2}')
INST=$(dpkg -l 2>/dev/null | grep -c '^ii')
echo "   磁盘：$DF   dpkg 已装 $INST 个"

echo
echo "== ② 接线位复点 A：机上那份 profile cordis（只看结构，凭据行滤掉）"
F=/root/.dsh/profiles/web/cordis.patch.yml
if [ -f "$F" ]; then
  echo "   $F  $(stat -c '%s B  mtime=%y' "$F")"
  echo "   总行数=$(wc -l < "$F")  含 key/token/cred/secret/password 的行数=$(grep -icE 'key|token|cred|secret|password' "$F")（这些行我不打）"
  grep -nvE 'key|token|cred|secret|password' "$F" | sed 's/^/   /'
  echo "   runnerCommand 命中=$(grep -c runnerCommand "$F") 条"
else echo "   !! $F 不存在"; fi

echo
echo "== ③ 接线位复点 B：上游这两个包各吃什么键（决定那两行插在哪个 id 底下）"
BASE=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai
[ -d "$BASE" ] || BASE=$(ls -d /usr/local/lib/node_modules/@deepseek-ai/*/node_modules/@deepseek-ai 2>/dev/null | head -1)
echo "   包树根：$BASE"
for P in dsh-sandbox-local dsh-sandbox-policy; do
  LI="$BASE/$P/lib/index.js"
  CFG=$(grep -oE 'Config = z\.object\(\{[^}]*\}' "$LI" 2>/dev/null | head -2)
  ST=$(grep -c 'strict(' "$LI" 2>/dev/null)
  UK=$(grep -oE 'unknownKeys[^,)]{0,24}' "$LI" 2>/dev/null | head -2 | tr '\n' ' ')
  echo "   -- $P 的 Config（z.object 里的键，原文）与 unknown-keys 行为："
  printf '%s\n' "$CFG" | sed 's/^/      /'
  echo "      strict( 命中=$ST  unknownKeys 命中=${UK:-无}"
done
echo "   -- cordis 里这两个插件的 id（从上游 base 那份 yml 读，不猜）："
grep -n -B1 -A3 "dsh-sandbox" "$BASE/dsh-base/cordis.patch.yml" 2>/dev/null | grep -E "id:|name:|config:|mode:|sandbox" | head -24 | sed 's/^/      /'

echo
echo "== ④ 接线位复点 C：runner 在不在位、服务 env 里那两行"
R=/usr/local/bin/dsh-unshare-run
if [ -f "$R" ]; then
  echo "   $R  $(stat -c '%s B  mode=%a owner=%U:%G' "$R")  mtime=$(stat -c %y "$R" | cut -c1-19)"
  echo "   sha256=$(sha256sum "$R" | cut -c1-16)…  本地孪生件对账要在电脑侧做，这里只报读数"
else echo "   !! $R 不在"; fi
echo "   -- /root/.dsh-env 里档位与 runner 相关行（只锚定这两条）："
grep -nE 'DSH_PERMISSION_MODE|DSH_UNSHARE_RUN_ALLOW_NO_PIDNS' /root/.dsh-env 2>/dev/null | sed 's/^/      /'
echo "      .dsh-env: $(stat -c '%s B mode=%a mtime=%y' /root/.dsh-env 2>/dev/null)"
echo "   -- 引擎 pid 与它 exec 时吃到的档位："
for PF in /root/.dsh/web.pid /root/dsh.pid; do
  [ -f "$PF" ] && echo "      pidfile $PF = $(cat "$PF")"
done
EP=$(pgrep -f 'dsh web' | head -1)
if [ -n "$EP" ]; then
  echo "      引擎 pid=$EP 父=$(ps -o ppid= -p $EP | tr -d ' ') 起于=$(ps -o lstart= -p $EP)"
  echo "      它 env 里 DSH_PERMISSION_MODE=$(tr '\0' '\n' < /proc/$EP/environ 2>/dev/null | grep '^DSH_PERMISSION_MODE=' || echo 没有这一行)"
  echo "      它 env 里 DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=$(tr '\0' '\n' < /proc/$EP/environ 2>/dev/null | grep -c '^DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=')"
else echo "      !! 没抓到 dsh web 进程"; fi
echo "   -- 入口 pid：$(pgrep -f 'dsh-entry.js' | tr '\n' ' ')"

echo
echo "== ⑤ 引擎有没有可编程的那扇（不猜，从安装件里把路由字符串捞出来）"
D=$(ls -d /usr/local/lib/node_modules/@deepseek-ai/dsh 2>/dev/null)
echo "   包根：$D  node_modules 下包数=$(ls -d $D/node_modules/@deepseek-ai/* 2>/dev/null | wc -l)"
echo "   -- 含 /api/ 字符串的包与条数："
for X in $D/node_modules/@deepseek-ai/*/lib/index.js $D/dist/*.js; do
  [ -f "$X" ] || continue
  C=$(grep -oc '"/api/[a-z0-9_/-]*"' "$X" 2>/dev/null | head -1)
  if [ "${C:-0}" != "0" ] && [ -n "$C" ]; then echo "      $(echo "$X" | sed "s|$D/||")  命中=$C"; fi
done
grep -roh '"/api/[a-zA-Z0-9_./-]*"' $D 2>/dev/null | sort | uniq -c | sort -rn | head -14 | sed 's/^/      /'
echo "   -- dsh 有没有一次性跑一句的 CLI 入口："
timeout 20 dsh --help 2>&1 | head -22 | sed 's/^/      /'

echo
echo "== ⑥ 这发留没留东西"
echo "   /root 下除探针外的 .sh: $(ls /root/*.sh 2>/dev/null | grep -vc dsh-size)   /tmp 顶层: $(ls -A /tmp 2>/dev/null | wc -l)"
