#!/bin/bash
# 探针 68（有写，但不重启）—— 把 runner 接到 sandbox 这一档上，并在**不动服务**的前提下先验接对没接对。
#
# 为什么要先验再重启（这一发最值钱的就是这一步）：
#   归档 RUNBOOK-archived.md:878 那段接线形状把两行写在 `- id: sandbox-policy` 底下，**那是错的**：
#   runnerCommand 是 dsh-sandbox-local 的 Config，而机上上游 base 那份 cordis（探针 67 第 ③ 节读回的原文）
#   把 id 分得很清楚 —— `- id: sandbox` = @deepseek-ai/dsh-sandbox-local，`- id: sandbox-policy` = 只吃 mode。
#   zod object 不设 strict（67 第 ③ 节：strict( 命中 0） ⇒ 键放错 id 底下**不报错、静默丢掉**，
#   于是"接了线其实没接"，而这正是 :311-321 那条"不探测、不验证"最怕的形状。
#   dsh 自带 `--dump-config`（打印组合后的 profile 树就退出，不 mount、不起服务） ⇒ 重启前就能判死这一条。
#
# 三条纪律：动盘前先逐字节备份并比 sha256；dump 出来的树可能带凭据，只打 sandbox 附近且滤掉
# key/token/cred/secret/password 这些行（滤了几行也报出来）；本发**不重启**，引擎还是 21363 那份老配置。
set -u
export DEBIAN_FRONTEND=noninteractive LC_ALL=C HOME=/root
echo "chroot 内时刻: $(date '+%F %T %Z')"

F=/root/.dsh/profiles/web/cordis.patch.yml
TS=$(date -u +%Y%m%d-%H%M%S)
BAK=/root/.dsh/cordis.patch.yml.bak.$TS
NOHIST='key|token|cred|secret|password'

echo "== ① 备份（sha256 撞上才动盘）"
[ -f "$F" ] || { echo "!! $F 不存在，停手"; exit 1; }
cp -p "$F" "$BAK" || { echo "!! 备份失败，停手"; exit 1; }
A=$(sha256sum "$F" | cut -d' ' -f1); B=$(sha256sum "$BAK" | cut -d' ' -f1)
echo "   原件 $(stat -c %s "$F") B  sha256 ${A:0:16}…"
echo "   备份 $BAK  $(stat -c %s "$BAK") B  sha256 ${B:0:16}…"
if [ "$A" != "$B" ]; then echo "!! 备份没撞上，停手不动盘"; exit 1; fi
echo "   [ok] 逐字节相同 ⇒ 可以动盘"
echo "   撤法（一条）：cp -p $BAK $F"

echo
echo "== ② 追加接线两行（挂在 - id: sandbox 底下，不是 sandbox-policy）"
if grep -q '^-' "$F" && [ -n "$(sed -n '$p' "$F")" ]; then printf '\n' >> "$F"; fi
cat >> "$F" <<'YML'
# dsh-mobile 接线（2026-10-21）：这台内核 USER_NS/LANDLOCK 都没有 ⇒ 上游两条内置后端起不来，
# workspace-write 下 Bash 明确拒绝执行。用官方 runnerCommand 口子把我们自己的
# mount-namespace runner 接进来（id 必须是 sandbox = @deepseek-ai/dsh-sandbox-local；
# 放到 sandbox-policy 底下会被 zod 静默丢掉）。runner 未验前先降级可见：见 /root/.dsh-env。
- id: sandbox
  config:
    runnerCommand: ["/usr/local/bin/dsh-unshare-run"]
    runnerFailureSignatures: ["dsh-unshare-run: "]
YML
echo "   改完 $(stat -c %s "$F") B（原 508 B）  新增行:"
grep -n "id: sandbox\|runnerCommand\|runnerFailureSignatures" "$F" | sed 's/^/     /'

echo
echo "== ③ --dump-config：组合后的树里 sandbox 那段（滤凭据，只看这一段）"
D=$(timeout 90 dsh --profile web --dump-config 2>&1); RC=$?
echo "   rc=$RC  输出行数=$(printf '%s\n' "$D" | wc -l)"
printf '%s\n' "$D" | grep -n -A12 -B2 'id: sandbox' | grep -viE "$NOHIST" | head -40 | sed 's/^/   /'
echo "   -- dump 里 runnerCommand 命中行数=$(printf '%s\n' "$D" | grep -c runnerCommand)  dsh-unshare-run 命中=$(printf '%s\n' "$D" | grep -c dsh-unshare-run)"

echo
echo "== ④ --dump-config-schema：这两键归在哪个 id（反证 ② 放对了）"
S=$(timeout 90 dsh --profile web --dump-config-schema 2>&1); SRC=$?
echo "   rc=$SRC  输出行数=$(printf '%s\n' "$S" | wc -l)"
printf '%s\n' "$S" | grep -n 'runnerCommand' | head -4 | sed 's/^/   /'
echo "     runnerCommand 这条键在 schema 里出现在哪个 id 底下（往上找最近的 id/name 行）："
printf '%s\n' "$S" | grep -n -B60 'runnerCommand' 2>/dev/null | grep -E '"?(sandbox|sandbox-policy)"?:|dsh-sandbox' | tail -6 | sed 's/^/     /'
printf '%s\n' "$S" > /tmp/p68-schema.txt
echo "     schema 里含 sandbox 的行（前 12 条）："
grep -n 'sandbox' /tmp/p68-schema.txt | head -12 | sed 's/^/     /'

echo
echo "== ⑤ 有没有一次性跑一句的入口（不靠 App 也能端到端）"
H=$(timeout 60 dsh --profile web --help 2>&1); HC=$?
echo "   rc=$HC"
printf '%s\n' "$H" | grep -nE -- '--[a-z-]+ .*(print|prompt|exec|one-shot|non-interactive|command|stdin|ci)' | head -12 | sed 's/^/   /'
printf '%s\n' "$H" | sed -n '1,40p' | sed 's/^/   | /'

echo
echo "== ⑥ 服务这一侧现在还是老的（本发没重启）"
EP=$(pgrep -f 'dsh web' | head -1)
echo "   引擎 pid=$EP 起于=$(ps -o lstart= -p ${EP:-0} 2>/dev/null | tr -d '\n')  档位=$(tr '\0' '\n' < /proc/${EP:-0}/environ 2>/dev/null | grep '^DSH_PERMISSION_MODE=' )"
echo "   入口 pid=$(pgrep -f 'dsh-entry.js' | tr '\n' ' ')"
echo "   :3080 还在听吗=$(ss -lnt 2>/dev/null | grep -c ':3080')"

echo
echo "== ⑦ 这发留没留东西"
rm -f /tmp/p68-schema.txt
echo "   /tmp 顶层=$(ls -A /tmp 2>/dev/null | wc -l)  p68 残留=$(ls /tmp/p68-* 2>/dev/null | wc -l)  备份件=$(ls /root/.dsh/cordis.patch.yml.bak.* 2>/dev/null | wc -l) 份"
