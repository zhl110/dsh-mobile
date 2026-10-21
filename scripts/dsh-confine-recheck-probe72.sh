#!/bin/bash
# 探针 72（只动 /tmp 里我自己那份临时件，跑完删）—— 把 71 里两处失败的读数补成能作数的。
#
# 71 第 ④ 节那两条为什么必须重来：手机里的 dsh 说它接好了 runnerCommand，并交了三个 YES
# （工作区可写 /etc 只读 /root 只读）。那三条只证明**手工调 runner** 这一层，
# 证明不了 dsh 会不会把命令交给 runner —— 判这一条只能调它自己那份 confine() 看 argv。
# 而 71 那次我把模块路径写成了 /usr/local/lib/node_modules/@deepseek-ai/dsh-sandbox-local/…，
# 真件在 **dsh/node_modules/ 那一层**（69 第 27 行的读数），于是 node 报 ERR_MODULE_NOT_FOUND、
# stat 回空、"命中="空 —— 三条都是"路径不存在"造成的空读数，不能读成"没打补丁"或"围住了"。
#
# 这一发要拿到的四件事：
#   ① 机上到底有几份 sandbox 相关模块、哪份是 purge 改过的（md5+mtime+标记命中）
#   ② 逐份调 confine()：ARGV_HAS_RUNNER=yes/no ⇒ 它接的那条线现在到底活不活（唯一硬判据）
#   ③ 它写在 cordis 注释里的那条 /proc/1/root 缺口：围内/围外各读一遍，并查它在 /data/local/tmp 与
#      手机存储上"实测写成功"留没留件（只列，不删不碰 —— 那是他的目录）
#   ④ dpkg 411 ⇒ 415 多了哪四个包、几点装的（71 第 ⑦ 节顺手量到的，来源没人交代）
#
# 纪律：md5/sha 先打原始行；口令不进 argv；探针自己数自己的 .sh；只读，不杀不写配置。
set -u
export DEBIAN_FRONTEND=noninteractive LC_ALL=C HOME=/root
echo "chroot 内时刻: $(date '+%F %T %Z')   北京 $(TZ=Asia/Shanghai date '+%F %T')"
G=/usr/local/lib/node_modules/@deepseek-ai
P=/root/.dsh/profiles/web
RUN=/usr/local/bin/dsh-unshare-run

echo "== ① 机上所有 sandbox 相关模块副本（三条来源分开看）"
ls -1 $G/dsh/node_modules/@deepseek-ai/dsh-sandbox-local/lib/index.js \
      $G/dsh-sandbox-local/lib/index.js \
      $P/node_modules/@deepseek-ai/dsh-sandbox-local/lib/index.js 2>/dev/null | sort -u > /tmp/p72-list.txt
find $G $P -maxdepth 7 -path '*dsh-sandbox-local/lib/index.js' 2>/dev/null >> /tmp/p72-list.txt
sort -u /tmp/p72-list.txt | grep . > /tmp/p72-uniq.txt
NC=$(grep -c . /tmp/p72-uniq.txt)
echo "   副本计数=$NC"
while read -r X; do
  [ -n "$X" ] || continue
  SZ=$(stat -c %s "$X")
  MT=$(stat -c '%y' "$X" | cut -c1-19)
  RAW=$(md5sum "$X")
  MD=$(printf '%s\n' "$RAW" | cut -d' ' -f1)
  MK=$(grep -c '\[dsh-purge\]' "$X")
  printf '   %s\n      %s B  mtime=%s  md5=%s  [dsh-purge] 命中=%s\n' "$X" "$SZ" "$MT" "$MD" "$MK"
done < /tmp/p72-uniq.txt
echo "   -- 各层另外两个包的标记命中（fs 层与 bash 层）："
for PKG in dsh-fs-sandbox dsh-bash-sandbox dsh-sandbox-policy; do
  LI=$(grep -F "/$PKG/lib/index.js" /tmp/p72-uniq.txt | head -1)
  [ -n "$LI" ] || LI=$(find $G $P -maxdepth 7 -path "*/$PKG/lib/index.js" 2>/dev/null | head -1)
  [ -n "$LI" ] || { echo "      $PKG：没找到副本（不猜）"; continue; }
  SZ=$(stat -c %s "$LI")
  MK=$(grep -c '\[dsh-purge\]' "$LI")
  echo "      $PKG  $(echo "$LI" | sed "s|$G/||")  $SZ B  标记=$MK"
done

echo
echo "== ② 那份 confine() 现在到底是直通还是包装（逐份调，不 spawn）"
H=/tmp/p72-confine.mjs
cat > "$H" <<'MJS'
import { pathToFileURL } from 'node:url';
const LIB = process.argv[2];
const WS = process.argv[3];
const mod = await import(pathToFileURL(LIB).href);
const P = mod.LocalSandboxProvider ?? mod.default;
if (!P) { console.log('NO_EXPORT=1'); process.exit(0); }
const cfg = { runnerCommand: ['/usr/local/bin/dsh-unshare-run'], runnerFailureSignatures: ['dsh-unshare-run: '], probeTimeoutMs: 5000 };
let provider, route = 'new P(ctx,cfg)';
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
console.log('ARGV0..2=' + JSON.stringify(r.argv.slice(0, 3)));
console.log('ENFORCEMENT=' + r.enforcement);
console.log('FAILURE_RULES=' + JSON.stringify(r.runnerFailureRules));
console.log('DENIAL_SIGNATURES=' + JSON.stringify(r.denialSignatures));
MJS
. /root/.dsh-env 2>/dev/null
while read -r X; do
  [ -n "$X" ] || continue
  echo "   [$X]"
  timeout 60 node "$H" "$X" /phone 2>&1 | sed 's/^/      /'
done < /tmp/p72-uniq.txt
rm -f "$H"
echo "   -- 函数体现场读（真读了才算，注释别抄）："
L1=$(head -1 /tmp/p72-uniq.txt)
grep -n -A12 'confine(command' "$L1" 2>/dev/null | head -16 | sed 's/^/      /'

echo
echo "== ③ /proc/1/root 这条缺口：围内 / 围外 各读一遍（只读，不写）"
IN='echo LINK=$(readlink /proc/1/root 2>&1); echo LS=$(ls /proc/1/root 2>&1 | head -3 | tr "\n" " "); echo TOP=$(ls -1 /proc/1/root/data/local/tmp 2>&1 | wc -l); echo ST=$(ls -1 /proc/1/root/storage 2>&1 | head -3 | tr "\n" " ")'
IN2='echo LS_OUT=$(ls -1 / 2>/dev/null | wc -l); echo LS_PH=$(ls -1 /phone 2>/dev/null | wc -l); echo FINDMNT_PH=$(findmnt -no SOURCE,TARGET --target /phone 2>&1 | head -1)'
OUT=$(timeout 60 "$RUN" --ro-bind / / -- bash -c "$IN" 2>&1)
RC=$?
echo "   围内（runner，rc=$RC）："
printf '%s\n' "$OUT" | sed 's/^/      > /'
OUT2=$(timeout 30 bash -c "$IN" 2>&1)
echo "   围外（chroot 直接，rc=$?）："
printf '%s\n' "$OUT2" | sed 's/^/      > /'
echo '   -- 它说「经 /proc/1/root 在 /data/local/tmp 与 /storage/emulated/0 实测写成功」，这两处现在有什么（只列不碰）：'
LT=$(ls -lt /proc/1/root/data/local/tmp 2>/dev/null | head -12)
echo "$LT" | sed 's/^/      /'
echo "      条目总数=$(ls -1 /proc/1/root/data/local/tmp 2>/dev/null | grep -c .)"
PH=$(timeout 30 bash -c "$IN2" 2>&1)
printf '%s\n' "$PH" | sed 's/^/      /'
echo "      /phone 顶层最近 8 项："; ls -lt /phone 2>/dev/null | head -9 | sed 's/^/      /'

echo
echo "== ④ dpkg 从 411 到 415：多出来的那四个与时刻（只读 dpkg.log）"
echo "   现在已装=$(dpkg -l 2>/dev/null | grep -c '^ii')"
tail -400 /var/log/dpkg.log 2>/dev/null | grep -E ' (install|remove|configure) ' | tail -18 | sed 's/^/   /'

echo
echo "== ⑤ 现场服务：第 6 代还在不在位、有没有真在跑 runner"
BOOT=$(awk '/^btime/{print $2}' /proc/stat)
HZ=$(getconf CLK_TCK 2>/dev/null); HZ=${HZ:-100}
UPNOW=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
EG=$(pgrep -f 'dsh web' | head -1)
EN=$(pgrep -f 'dsh-entry.js' | head -1)
ST=$(awk '{print $22}' /proc/$EG/stat 2>/dev/null)
AGE=$((UPNOW - ST / HZ))
B=$(date -u -d "@$((BOOT + ST / HZ))" '+%F %T')
BB=$(TZ=Asia/Shanghai date -d "@$((BOOT + ST / HZ))" '+%F %T')
echo "   引擎 pid=${EG:-没抓到} 出生 $B UTC（= $BB 北京）活着 $AGE 秒"
echo "   入口 pid=${EN:-没抓到}（71 那次是 17611）"
NR=$(pgrep -f 'dsh-unshare-run' 2>/dev/null | grep -c .)
echo "   现场 dsh-unshare-run 进程数=$NR"
R1=$(curl -s -o /dev/null -m 12 -w '%{http_code} %{size_download}B' http://127.0.0.1:3080/ 2>&1)
echo "   :3080 裸打=$R1"
echo "   入口日志末 6 行："; tail -6 /root/.dsh/entry.log 2>/dev/null | sed 's/^/     /'

echo
echo "== ⑥ 我那三层复点（71 把入口路径写错了：入口在 /usr/local/bin，不在 /root）"
for X in /usr/local/bin/dsh-entry.js /root/.dsh/entry-compat.js /root/.dsh-env /root/doh-hosts.sh /root/dsh-entry-check.sh; do
  if [ -f "$X" ]; then
    SZ=$(stat -c %s "$X")
    MT=$(stat -c '%y' "$X" | cut -c1-19)
    RAW=$(md5sum "$X")
    printf '   %-34s %7s B  %s  原始行=[%s]\n' "$X" "$SZ" "$MT" "$RAW"
  else
    printf '   %-34s 不在（按读数）\n' "$X"
  fi
done
echo "   -- hosts 对账（doh-hosts.sh --check，只读）："
timeout 90 bash /root/doh-hosts.sh --check 2>&1 | tail -12 | sed 's/^/      /'

echo
echo '== ⑦ 会话有没有断点（它说「存在 session.v4.jsonl.zstd 里」）'
find /root/.dsh/sessions -maxdepth 3 -name 'session.v4*' -printf '%T@ %10s %p\n' 2>/dev/null | sort -rn | head -6 > /tmp/p72-sess.txt
echo "   全部命中数=$(find /root/.dsh/sessions -maxdepth 3 -name 'session.v4*' 2>/dev/null | grep -c .)"
while read -r T S X; do
  [ -n "$X" ] || continue
  printf '   %s  %s B  %s\n' "$(date -u -d "@${T%.*}" '+%F %T')" "$S" "$X"
done < /tmp/p72-sess.txt
echo "   目录分组（每个分组下几个会话）："
for D in /root/.dsh/sessions/*/; do
  N=$(ls -1 "$D" 2>/dev/null | grep -c 'session.v4')
  printf '      %-46s 会话数=%s\n' "$(basename "$D")" "$N"
done

echo
echo "== ⑧ 这发留没留东西"
rm -f /tmp/p72-list.txt /tmp/p72-uniq.txt /tmp/p72-sess.txt /tmp/p72-confine.mjs
echo "   /tmp 顶层=$(ls -A /tmp 2>/dev/null | wc -l)  p72 残留=$(ls -1 /tmp/p72-* 2>/dev/null | grep -c .)"
echo "   /root/*.sh=$(ls -1 /root/*.sh 2>/dev/null | wc -l)（含本探针自己，run-probe.sh 收尾删）"
echo "   /phone 与 /etc 与 /root 下我这次的自测件=$(ls -1 /phone/dsh-* /etc/dsh-* /root/dsh-sbx-* 2>/dev/null | grep -c .)"
