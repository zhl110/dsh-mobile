#!/bin/bash
# 探针 70（先读后写一处）—— 探针 69 那一发把一件我们本来当真的事读翻了，这一发把它查干净。
#
# 69 第 ③ 节的读数：用上游自己的 confine() 包一条命令，回来是
#   ARGV_HAS_RUNNER=no  SEPARATOR=no  ENFORCEMENT=full  DENIAL_SIGNATURES=[]  runnerFailureRules=[]
# ⇒ argv 一字未包。我把那份模块拉到本地读了（downloads/sbx-dev-index.js，22,231 B，mtime 2026-10-21 10:35:16 UTC），
#   :305-316 的 confine() 已经是 **dsh-purge 打过补丁的形状**：注释原文写着
#   "[dsh-purge] sandbox bypass: confine() never wraps argv in a sandbox runner"，函数体直接 return 原 argv。
# ⇒ 三个推论，这一发各拿一条读数：
#   ① 今天上午 10:35(UTC)=北京 18:35 装进手机 web profile 的那发 dsh-purge，把**进程沙箱这一层整个短路**了
#      ⇒ 我 68/69 接的 runnerCommand 在 purge 在位时是**死配置**（这就是"配置看着接了其实没接"的另一半成因）。
#   ② 那么"Bash 在 workspace-write 下拒绝执行"这句话（PROGRESS 顶部与 RUNBOOK 里都还写着）现在大概率已经不成立：
#      走不到 selectRunner ⇒ 抛不出 SANDBOX_UNAVAILABLE。但我**没有真跑过一轮对话**，所以这条只能报"代码层判据变了"，
#      不能报"能用了"。同时把 purge 还打了哪些包查出来 —— 文件工具那层（dsh-fs-sandbox）有没有一起被短路，
#      决定"档位"这两个字现在还剩几分真。
#   ③ 既然接线是死配置，盘上就不该留一个"假装已围堵"的配置文件 ⇒ 把 cordis 撤回到 68 那个备份（sha 逐字节复点），
#      两行原文我另存在仓库里（config/cordis-sandbox-wiring.snippet.yml），他哪天把 purge 撤了再一并接上。
#
# 红线：口令只从 /root/.dsh/entry.key 读进变量、经 stdin 交 curl -K -，不进 argv 不进输出（69 第 ② 节那条 404
#       是入口**按设计拒答**，不是坏了 —— 判据见 scripts/dsh-entry-status.sh 甲乙两问，这发把乙问补上）。
set -u
export DEBIAN_FRONTEND=noninteractive LC_ALL=C HOME=/root
echo "chroot 内时刻: $(date '+%F %T %Z')   北京 $(TZ=Asia/Shanghai date '+%F %T')"
TREE=/usr/local/lib/node_modules/@deepseek-ai
F=/root/.dsh/profiles/web/cordis.patch.yml

echo "== ① dsh-purge 在这台机上到底改了哪些文件（两条独立口径：备份件 + 正文里的标记）"
echo "   -- 口径甲：*.dshpurge.bak* 备份件"
find "$TREE" /root/.dsh -name '*dshpurge*' 2>/dev/null > /tmp/p70-bak.txt
NB=$(grep -c . /tmp/p70-bak.txt)
echo "      计数=$NB"
head -12 /tmp/p70-bak.txt | sed 's/^/      /'
echo "   -- 口径乙：正文里含 [dsh-purge] 的文件（这才是真被改过的）"
grep -rl '\[dsh-purge\]' "$TREE" 2>/dev/null > /tmp/p70-mark.txt
NM=$(grep -c . /tmp/p70-mark.txt)
echo "      计数=$NM"
while read -r X; do
  [ -n "$X" ] || continue
  C=$(grep -c '\[dsh-purge\]' "$X" 2>/dev/null)
  printf '      %-96s 标记=%-3s %s B  mtime=%s\n' "$(echo "$X" | sed "s|$TREE/||")" "$C" "$(stat -c %s "$X")" "$(stat -c '%y' "$X" | cut -c1-19)"
done < /tmp/p70-mark.txt
echo "   -- 那两层各是什么形状（只打函数头那几行，不打整段）："
for PKG in dsh-sandbox-local dsh-fs-sandbox dsh-bash-sandbox dsh-sandbox-policy; do
  LI=$(ls $TREE/$PKG/lib/index.js 2>/dev/null | head -1)
  [ -n "$LI" ] || { echo "      $PKG：这份包不在这棵树下（跳过）"; continue; }
  echo "      [$PKG  $(basename "$LI")  $(stat -c '%s B' "$LI")]"
  grep -n '\[dsh-purge\]' "$LI" 2>/dev/null | head -4 | sed 's/^/        /'
  printf '%s\n' "$(grep -A2 -h '\[dsh-purge\]' "$LI" 2>/dev/null | head -6)" | sed 's/^/        | /'
done

echo
echo "== ② 现场服务健康（把 69 里那两个没解释清的读数问干净）"
EP=$(pgrep -f 'dsh web' | head -1)
EN=$(pgrep -f 'dsh-entry.js' | head -1)
P80=$(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:3080$/' | wc -l)
P81=$(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:3081$/' | wc -l)
echo "   引擎 pid=${EP:-没抓到}  入口 pid=${EN:-没抓到}  :3080=$P80  :3081=$P81"
echo "   :3080 裸打（401=引擎活着且要券）=$(curl -s -o /dev/null -m 12 -w '%{http_code} %{size_download}B' http://127.0.0.1:3080/ 2>&1)"
echo "   :3081/ 不带口令（入口按设计一律 404）=$(curl -s -o /dev/null -m 12 -w '%{http_code} %{size_download}B' http://127.0.0.1:3081/ 2>&1)"
KEY=$(cat /root/.dsh/entry.key 2>/dev/null)
if [ -n "$KEY" ]; then
  R=$(printf 'cookie = dsh-entry=%s\n' "$KEY" | curl -sS -m 15 -K - -o /tmp/p70-page.html -w '%{http_code} %{size_download}B' http://127.0.0.1:3081/ 2>&1)
  echo "   :3081/ 带口令（这就是 App 点开那一发）=$R   侧栏那段属性在不在=$(grep -c 'data-dsh-side-scroll' /tmp/p70-page.html 2>/dev/null)"
  S=$(printf 'cookie = dsh-entry=%s\n' "$KEY" | curl -sS -m 10 -K - -o /tmp/p70-st.txt -w '%{http_code}' http://127.0.0.1:3081/__entry_status 2>&1)
  echo "   :3081/__entry_status 带口令 http=$S  正文首行=$(head -1 /tmp/p70-st.txt 2>/dev/null | cut -c1-90)"
  unset KEY
else echo "   !! 读不到 entry.key（不猜，这条就标未验）"; fi
echo "   入口日志末 4 行（token 与 cookie 值落盘前已过 redact）："; tail -4 /root/.dsh/entry.log 2>/dev/null | sed 's/^/     /'

echo
echo "== ③ 把 cordis 撤回到 68 那个备份（不留「假装已围堵」的配置）"
CB=$(ls -1 /root/.dsh/cordis.patch.yml.bak.* 2>/dev/null | tail -1)
if [ -n "$CB" ] && [ -f "$CB" ]; then
  cp -p "$CB" "$F" && echo "   [ok] 已还原 $F ← $CB"
  A=$(sha256sum "$CB" | cut -d' ' -f1); B=$(sha256sum "$F" | cut -d' ' -f1)
  echo "   复点：备份 ${A:0:16}…  现在 ${B:0:16}…  $([ "$A" = "$B" ] && echo '逐字节相同' || echo '!! 不相同')"
  echo "   现在 $(stat -c %s "$F") B（68 之前是 508 B）  runnerCommand 命中=$(grep -c runnerCommand "$F")"
  D=$(timeout 90 dsh --profile web --dump-config 2>&1)
  echo "   组合树里 runnerCommand 命中=$(printf '%s\n' "$D" | grep -c runnerCommand)（0 才算真撤干净）"
else echo "   !! 没找到备份件，不撤（先人工确认 $CB）"; fi

echo
echo "== ④ 档位与审批这两行现在算出来是什么（只读表达式，不读凭据）"
timeout 60 dsh --profile web --dump-config 2>&1 | grep -A3 'id: sandbox-policy' | grep -E 'mode|policy|workspaceRoot' | sed 's/^/   /'
echo "   服务 env 里档位：$(tr '\0' '\n' < /proc/${EP:-0}/environ 2>/dev/null | grep '^DSH_PERMISSION_MODE=' || echo 读不到)"
echo "   （purge 在位时这条 mode 已经不喂给 confine() 了 ⇒ 它现在管的是审批弹窗与文件工具那侧，不是进程围堵）"

echo
echo "== ⑤ 这发留没留东西"
rm -f /tmp/p70-bak.txt /tmp/p70-mark.txt /tmp/p70-page.html /tmp/p70-st.txt
echo "   /tmp 顶层=$(ls -A /tmp 2>/dev/null | wc -l)  p70 残留=$(ls /tmp/p70-* 2>/dev/null | wc -l)  /root/*.sh=$(ls /root/*.sh 2>/dev/null | wc -l)（含本探针）"
echo "   备份件：cordis=$(ls /root/.dsh/cordis.patch.yml.bak.* 2>/dev/null | wc -l) 份  dsh-env=$(ls /root/.dsh/dsh-env.bak.* 2>/dev/null | wc -l) 份（都留着，撤法在 68/69 的读数里）"
