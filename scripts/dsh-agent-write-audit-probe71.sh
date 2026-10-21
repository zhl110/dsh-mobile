#!/bin/bash
# 探针 71（**只动 /tmp 里我自己那几份临时件，跑完删**；不写机上任何配置、不杀进程、不重启）——
# 手机里那个 dsh 自己动了一次盘，它交给我一份"做了什么"的说明，
# 我要把说明里每一条与盘上读数撞一遍，而不是照抄它的措辞。
#
# 它交代的四件事，各自对应下面哪一节：
#   A "备份到 cordis.patch.yml.bak-20261021-144328"           ⇒ ②（备份件在不在、是接线前还是接线后那份）
#   B "把 runnerCommand 挂到 - id: sandbox 底下"              ⇒ ②③（文件现状 + 不重启的 --dump-config 判据）
#   C "接线前独立实测：工作区可写 YES / /etc 只读 YES / /root 只读 YES" ⇒ ④（这三条只能证明**手工调 runner** 那一层，
#      证明不了 dsh 会不会走它 —— 69 那次量到 confine() 被 dsh-purge 换成直通，两件事必须分开判）
#   D "15 秒后 kill -TERM 26114，入口自动拉第 6 代"            ⇒ ⑤（换代读数 + 入口日志时刻，它说断 5–8 秒）
# 另加它自己留的"/proc/1/root 缺口"那一问（④ 里用只读法复点：能不能透过 /proc/1/root 读到宿主文件），
# 因为它给的"堵不上"这个结论要落进决定，我不能凭它的陈述转述。
#
# 纪律（都是以前摔过的）：
#   · 只用 tools/run-probe.sh 送；本地先 bash -n。
#   · 设备侧一律按 chroot 视角读（这发全在 --run 里跑，不混宿主路径）。
#   · md5/sha 先把原始那一行打出来再取字段（错误消息进过我要数的字段，14.32 三 撞过）。
#   · 口令只从 /root/.dsh/entry.key 读进变量、经 stdin 交 curl -K -，不进 argv 不回显。
#   · 探针自己数自己的 .sh，不报"残留=0"。
set -u
export DEBIAN_FRONTEND=noninteractive LC_ALL=C HOME=/root
echo "chroot 内时刻: $(date '+%F %T %Z')   北京 $(TZ=Asia/Shanghai date '+%F %T')"
TREE=/usr/local/lib/node_modules/@deepseek-ai
F=/root/.dsh/profiles/web/cordis.patch.yml
RUN=/usr/local/bin/dsh-unshare-run

echo "== ① 盘上那份 cordis 现在到底长什么样（它说它写了）"
if [ -f "$F" ]; then
  SZ=$(stat -c %s "$F")
  MT=$(stat -c '%y' "$F" | cut -c1-19)
  LINES=$(wc -l < "$F")
  RAW=$(md5sum "$F")
  MD=$(printf '%s\n' "$RAW" | cut -d' ' -f1)
  CRED=$(grep -ciE 'key|token|cred|secret|password' "$F")
  echo "   $F  $SZ B  mtime=$MT  行数=$LINES"
  echo "   md5 原始那一行：[$RAW]"
  echo "   含凭据字样的行数=$CRED（0 才整份打印；不为 0 只打结构）"
  if [ "$CRED" = "0" ]; then sed 's/^/   | /' "$F"; fi
  echo "   runnerCommand 命中=$(grep -c runnerCommand "$F")  dsh-unshare-run 命中=$(grep -c dsh-unshare-run "$F")"
else
  echo "   !! $F 不在这条路径下（不猜，这条标未验）"
fi

echo
echo "== ② 它交的那个备份件在不在、是哪一份（两种命名都扫）"
ls -1 /root/.dsh/cordis*.bak* "$F".bak* /root/.dsh/profiles/web/cordis*.bak* 2>/dev/null | sort -u > /tmp/p71-bak.txt
NB=$(grep -c . /tmp/p71-bak.txt)
echo "   计数=$NB"
while read -r X; do
  [ -n "$X" ] || continue
  SZ=$(stat -c %s "$X")
  MT=$(stat -c '%y' "$X" | cut -c1-19)
  RAW=$(md5sum "$X")
  MD=$(printf '%s\n' "$RAW" | cut -d' ' -f1)
  SHA=$(sha256sum "$X" | cut -d' ' -f1)
  RC=$(grep -c runnerCommand "$X")
  printf '   %-72s %6s B  %s  md5=%s  sha=%s…  runnerCommand=%s\n' "$(basename "$X")" "$SZ" "$MT" "$MD" "${SHA:0:16}" "$RC"
done < /tmp/p71-bak.txt
echo "   对账锚点：68 之前那份原件 = 508 B / sha256 29d79784b8ee48ed…"
echo "   ⇒ 上面哪个 sha 以 29d79784 开头，哪个就是「接线前」；runnerCommand=2 的是「接线后」"

echo
echo "== ③ 不重启的判据：组合树里那段真吃进去了没（--dump-config 只组合不挂载）"
D=$(timeout 90 dsh --profile web --dump-config 2>&1)
DR=$?
DL=$(printf '%s\n' "$D" | grep -c .)
HIT=$(printf '%s\n' "$D" | grep -c runnerCommand)
UNR=$(printf '%s\n' "$D" | grep -c dsh-unshare-run)
echo "   rc=$DR  组合树行数=$DL  runnerCommand 命中=$HIT  dsh-unshare-run 命中=$UNR"
printf '%s\n' "$D" | grep -n -A8 'id: sandbox$' | head -22 | sed 's/^/   /'

echo
echo "== ④ 关键那一层：dsh 自己会不会把命令交给 runner（它给的 YES 三条不构成这条的证据）"
echo "   -- 4a purge 的短路标记在不在位（先读正文再下结论，AGENTS.md 铁律 15）"
grep -rl '\[dsh-purge\]' "$TREE" 2>/dev/null > /tmp/p71-mark.txt
NM=$(grep -c . /tmp/p71-mark.txt)
echo "      正文含 [dsh-purge] 的文件数=$NM"
SB=$TREE/dsh-sandbox-local/lib/index.js
echo "      $SB  $(stat -c '%s B  mtime=%y' "$SB" 2>/dev/null | cut -c1-60)"
MARK=$(grep -c 'dsh-purge' "$SB" 2>/dev/null)
echo "      这份里 [dsh-purge] 命中=$MARK"
grep -n -A10 'confine(' "$SB" 2>/dev/null | head -24 | sed 's/^/      /'
echo "   -- 4b 直接调 confine()，看它算出来的 argv 包没包（不 spawn，零副作用）"
H=/tmp/p71-confine.mjs
cat > "$H" <<'MJS'
import { pathToFileURL } from 'node:url';
const LIB = process.argv[2];
const WS = process.argv[3];
const mod = await import(pathToFileURL(LIB).href);
const P = mod.LocalSandboxProvider ?? mod.default;
const cfg = { runnerCommand: ['/usr/local/bin/dsh-unshare-run'], runnerFailureSignatures: ['dsh-unshare-run: '], probeTimeoutMs: 5000 };
let provider, route = 'new LocalSandboxProvider(ctx, cfg)';
try {
  provider = new P({ inject() {}, effect() {}, register() {}, provide() {} }, cfg);
} catch (e) {
  route = 'prototype.confine.call(手搭 this)';
  provider = Object.create(P.prototype);
  provider.runnerCommand = cfg.runnerCommand;
  provider.configuredRunnerFailureSignatures = cfg.runnerFailureSignatures;
}
const r = await provider.confine(['bash', '-c', 'echo hi'], { mode: 'workspace-write', workspaceRoot: WS }, undefined);
console.log('ROUTE=' + route);
console.log('ARGV_HAS_RUNNER=' + (String(r.argv[0]) === '/usr/local/bin/dsh-unshare-run' ? 'yes' : 'no'));
console.log('ARGV0..3=' + JSON.stringify(r.argv.slice(0, 4)));
console.log('ENFORCEMENT=' + r.enforcement);
console.log('FAILURE_RULES=' + JSON.stringify(r.runnerFailureRules));
console.log('DENIAL_SIGNATURES=' + JSON.stringify(r.denialSignatures));
MJS
. /root/.dsh-env 2>/dev/null
timeout 60 node "$H" "$SB" /phone 2>&1 | sed 's/^/      /'
rm -f "$H"
echo "   -- 4c 手工调 runner 本身跑得起来吗（它给的那三个 YES 只能证明这一层）"
# 只围不叠工作区：runner 的参数方言是 bwrap 那一套（--ro-bind / / … -- 命令），
# 不认识的参数它自己 die 127（scripts/dsh-unshare-run.sh:61），所以必须照方言给。
# 判"冻住没冻住"用 findmnt 读挂载选项，不靠 touch —— 这发一个字节都不往盘上写。
INNER='echo UID=$(id -u); echo TOP=$(ls / | wc -l); echo PID1=$(cat /proc/1/comm 2>&1 | head -1); echo PSCOUNT=$(ps -e 2>/dev/null | grep -c .); echo ETC_OPT=$(findmnt -no OPTIONS --target /etc 2>&1); echo PHONE_OPT=$(findmnt -no OPTIONS --target /phone 2>&1); echo TMP_OPT=$(findmnt -no OPTIONS --target /tmp 2>&1)'
if [ -x "$RUN" ]; then
  echo "      $RUN  $(stat -c '%s B  mtime=%y' "$RUN" | cut -c1-40)  sha=$(sha256sum "$RUN" | cut -d' ' -f1 | cut -c1-16)…"
  . /root/.dsh-env 2>/dev/null
  OUT=$("$RUN" --ro-bind / / -- bash -c "$INNER" 2>&1)
  RC=$?
  echo "      rc=$RC"
  printf '%s\n' "$OUT" | sed 's/^/      > /'
else
  echo "      !! $RUN 不可执行或不在（不猜）"
fi
echo "   -- 4d 它那条「/proc/1/root 缺口还在不在」——同一发里只读复点"
IN2='echo PR1LINK=$(readlink /proc/1/root 2>&1); echo PR1HOST=$(cat /proc/1/root/etc/hostname 2>&1 | head -1); echo PR1LS=$(ls /proc/1/root 2>&1 | head -2 | tr "\n" " ")'
OUT2=$("$RUN" --ro-bind / / -- bash -c "$IN2" 2>&1)
printf '%s\n' "$OUT2" | sed 's/^/      > /'
OUTSIDE=$(readlink /proc/1/root 2>/dev/null)
echo "      对照（不围时）readlink /proc/1/root = ${OUTSIDE:-读不到}"
echo "   -- 4e 现场有没有真在跑的 runner 进程（dsh 走过一发的痕迹）"
NR=$(pgrep -f 'dsh-unshare-run' 2>/dev/null | grep -c .)
echo "      pgrep -f dsh-unshare-run 命中=$NR"

echo
echo "== ⑤ 换代：它说 15 秒后 kill 26114、入口自动拉第 6 代"
BOOT=$(awk '/^btime/{print $2}' /proc/stat)
HZ=$(getconf CLK_TCK 2>/dev/null); HZ=${HZ:-100}
UPNOW=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
who() {
  local p=$1 ST CMD AGE
  [ -d "/proc/$p" ] || { printf 'pid %s 已不在\n' "$p"; return; }
  ST=$(awk '{print $22}' "/proc/$p/stat" 2>/dev/null)
  CMD=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | cut -c1-52)
  AGE=$((UPNOW - ST / HZ))
  printf 'pid %-7s 出生 %s UTC（=%s 北京）活着 %6s 秒  %s\n' "$p" "$(date -u -d "@$((BOOT + ST / HZ))" '+%F %T')" "$(TZ=Asia/Shanghai date -d "@$((BOOT + ST / HZ))" '+%F %T')" "$AGE" "$CMD"
}
N=0; EG=""
for p in $(pgrep -f 'dsh web'); do
  C=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
  case "$C" in *'dsh web'*) N=$((N+1)); [ -z "$EG" ] && EG=$p ;; esac
done
EN=$(pgrep -f 'dsh-entry.js' | head -1)
echo "   cmdline 含 'dsh web' 的进程数=$N"
echo "   引擎  $( [ -n "$EG" ] && who "$EG" )"
echo "   入口  $( [ -n "$EN" ] && who "$EN" )"
echo "   26114 还在吗=$( [ -d /proc/26114 ] && echo 在 || echo 不在了)   入口还是 17611 吗=$( [ -d /proc/17611 ] && echo 是 || echo 变了 )"
if [ -n "$EG" ]; then
  MODE=$(tr '\0' '\n' < /proc/$EG/environ 2>/dev/null | grep -c '^DSH_PERMISSION_MODE=')
  ALLOW=$(tr '\0' '\n' < /proc/$EG/environ 2>/dev/null | grep -c '^DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=')
  DSHM=$(tr '\0' '\n' < /proc/$EG/environ 2>/dev/null | grep -c '^DSHM_')
  CWD=$(readlink /proc/$EG/cwd 2>/dev/null)
  echo "   新引擎 env 命中：DSH_PERMISSION_MODE=$MODE  ALLOW_NO_PIDNS=$ALLOW  DSHM_*=$DSHM  cwd=${CWD:-读不到}"
fi
P80=$(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:3080$/' | wc -l)
P81=$(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:3081$/' | wc -l)
echo "   :3080=$P80  :3081=$P81"
R1=$(curl -s -o /dev/null -m 12 -w '%{http_code} %{size_download}B' http://127.0.0.1:3080/ 2>&1)
R2=$(curl -s -o /dev/null -m 12 -w '%{http_code} %{size_download}B' http://127.0.0.1:3081/ 2>&1)
echo "   :3080 裸打=$R1（401 才对）  :3081 不带口令=$R2（按设计 404）"
KEY=$(cat /root/.dsh/entry.key 2>/dev/null)
if [ -n "$KEY" ]; then
  R3=$(printf 'cookie = dsh-entry=%s\n' "$KEY" | curl -sS -m 20 -K - -o /tmp/p71-page.html -w '%{http_code} %{size_download}B' http://127.0.0.1:3081/ 2>&1)
  SIDE=$(grep -c 'data-dsh-side-scroll' /tmp/p71-page.html 2>/dev/null)
  echo "   :3081 带口令=$R3  侧栏那段属性命中=$SIDE"
  unset KEY
else
  echo "   !! 读不到 entry.key ⇒ 带口令这条标未验（不猜）"
fi
echo "   入口日志末 10 行（换代与凭据重换的时刻都在这）："
tail -10 /root/.dsh/entry.log 2>/dev/null | sed 's/^/     /'

echo
echo "== ⑥ 我那三层有没有被这次改动带到（三份 md5 与仓库对账要在电脑侧做，这里只报读数）"
for X in /root/.dsh/entry-compat.js /root/dsh-entry.js /root/.dsh-env /etc/hosts; do
  if [ -f "$X" ]; then
    SZ=$(stat -c %s "$X")
    MT=$(stat -c '%y' "$X" | cut -c1-19)
    RAW=$(md5sum "$X")
    printf '   %-34s %7s B  %s  原始行=[%s]\n' "$X" "$SZ" "$MT" "$RAW"
  else
    printf '   %-34s 不在（按读数，不当成 0）\n' "$X"
  fi
done
HL=$(wc -l < /etc/hosts)
PIN=$(grep -c 'awesome-dsh-plugin.com' /etc/hosts 2>/dev/null)
echo "   /etc/hosts 行数=$HL  市场那个 host 命中=$PIN"

echo
echo "== ⑦ 它和这发留没留东西（它说「会话记录没断点，存在 session.v4.jsonl.zstd」一并复点）"
SH=$(ls -1 /root/*.sh 2>/dev/null | wc -l)
TMP=$(ls -A /tmp 2>/dev/null | wc -l)
echo "   /root/*.sh=$SH（含本探针自己）  /tmp 顶层=$TMP"
echo "   它那句实测留没留自测件：/etc=$(ls -1 /etc/dsh-* 2>/dev/null | wc -l) /root=$(ls -1 /root/dsh-sbx-* 2>/dev/null | wc -l) /phone=$(ls -1 /phone/dsh-* 2>/dev/null | wc -l)"
find /root/.dsh -maxdepth 5 -path '*node_modules*' -prune -o -name 'session.v4*' -print 2>/dev/null | head -8 > /tmp/p71-sess.txt
NS=$(grep -c . /tmp/p71-sess.txt)
echo "   session.v4* 命中=$NS（只列最近 3 个）"
head -3 /tmp/p71-sess.txt | while read -r X; do
  SZ=$(stat -c %s "$X" 2>/dev/null)
  MT=$(stat -c '%y' "$X" 2>/dev/null | cut -c1-19)
  printf '      %-64s %10s B  %s\n' "$X" "${SZ:-?}" "$MT"
done
MTS=$(wc -l < /proc/mounts)
echo "   /proc/mounts 行数=$MTS（手工跑过 mount 类实验会留在这里）"
echo "   dpkg 已装=$(dpkg -l 2>/dev/null | grep -c '^ii')"

echo
echo "== ⑧ 如果要退它这次改动（一条，先 sha 复点再动；这发不执行）"
CB2=$(ls -1 /root/.dsh/cordis.patch.yml.bak.* 2>/dev/null | tail -1)
echo "   我这边的原件备份：${CB2:-没找到}"
echo "   它的备份：$(ls -1 "$F".bak* /root/.dsh/profiles/web/cordis*.bak* 2>/dev/null | head -1)（这份是接线前还是接线后，看 ② 的 runnerCommand 计数）"
echo "   撤法形状：cp -p <接线前那份> $F  ⇒ 再重启引擎才吃得进（铁律 13）"

echo
echo "== ⑨ 这发的临时件收拾"
rm -f /tmp/p71-bak.txt /tmp/p71-mark.txt /tmp/p71-page.html /tmp/p71-sess.txt /tmp/p71-confine.mjs
LEFT=$(ls -A /tmp 2>/dev/null | wc -l)
echo "   /tmp 顶层=$LEFT（⑦ 之后已删本探针 5 份）  /root/*.sh 仍是 $SH（run-probe.sh 收尾会删设备侧副本）"
