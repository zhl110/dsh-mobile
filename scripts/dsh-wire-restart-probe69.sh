#!/bin/bash
# 探针 69（有写、动服务）—— 接线之后重启一次引擎，并把"dsh 自己那一层到底围没围"验穿。
#
# 三件事要在这发里各拿到读数：
#   ① 换代：入口（17611）不动，只 SIGTERM 引擎 ⇒ 入口按监管重拉，新引擎吃进 /root/.dsh-env 里那行降级授权。
#      杀之前照 44 那四条纪律认身份（cmdline 必须含 'dsh web' 且恰好 1 个），年龄现场重读 /proc/uptime。
#   ② 端到端：以前所有验收都是"我在 chroot 里直接调 runner"，**dsh 那一层一个字没跑过**（14.11 四·3）。
#      这一发不靠猜：直接 require 机上那份 @deepseek-ai/dsh-sandbox-local，调它自己的 confine()，
#      拿它算出来的 argv 去 spawn —— 于是"policy→包装→执行"整条都是上游的代码，我只负责点_fire_。
#      为什么这条比"在 App 里发一句话"更硬：它不用花一次推理、不动他的会话，而且判据是我定死的四条。
#   ③ 致命签名正反两条（归档 14.11 三·1）：成功围堵的 stderr 里**不能**出现 "dsh-unshare-run: "，
#      只允许出现 "dsh-unshare-run-notice:"；真失败时才必须带前者。配的就是 runnerFailureSignatures 那个值，
#      搞反了每一次 Bash 都会被 dsh 判成"沙箱启动失败"。
#
# 纪律：档位与授权只报命中数不印值；两个备份件（cordis / dsh-env）与一条撤法都在末尾交出来；
#       工作区里那个自测文件写完就删并复点已删；不碰 /phone 下他任何现有文件。
set -u
export DEBIAN_FRONTEND=noninteractive LC_ALL=C HOME=/root
echo "chroot 内时刻: $(date '+%F %T %Z')   北京 $(TZ=Asia/Shanghai date '+%F %T')"

BOOT=$(awk '/^btime/{print $2}' /proc/stat); HZ=$(getconf CLK_TCK 2>/dev/null); HZ=${HZ:-100}
who() {
  local p=$1 ST CMD UPNOW
  UPNOW=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
  ST=$(awk '{print $22}' "/proc/$p/stat" 2>/dev/null); CMD=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | cut -c1-56)
  [ -n "$ST" ] && printf 'pid %-7s 出生 %s UTC 活着 %5s 秒  %s\n' "$p" "$(date -u -d "@$((BOOT + ST / HZ))" '+%F %T')" "$((UPNOW - ST / HZ))" "$CMD"
}

echo "== ① 重启前现场"
N=0; EG=""
for p in $(pgrep -f 'dsh web'); do
  tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'dsh web' && { N=$((N+1)); [ -z "$EG" ] && EG=$p; }
done
EN=$(pgrep -f 'dsh-entry.js' | head -1)
echo "   cmdline 含 'dsh web' 的进程数 = $N"
echo "   引擎  ${EG:-（没抓到）}  $( [ -n "$EG" ] && who "$EG" )"
echo "   入口  ${EN:-（没抓到）}  $( [ -n "$EN" ] && who "$EN" )"
[ "$N" = "1" ] || { echo "   !! 不是恰好 1 个引擎 ⇒ 按纪律停手不杀"; exit 1; }
[ -n "$EN" ] || { echo "   !! 没入口 ⇒ 杀了没人重拉，停手"; exit 1; }
[ "$EN" != "$EG" ] || { echo "   !! 引擎与入口同 pid ⇒ 停手"; exit 1; }
echo "   老引擎吃到的两行（只报命中数）：DSH_PERMISSION_MODE=$(tr '\0' '\n' < /proc/$EG/environ | grep -c '^DSH_PERMISSION_MODE=')  DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=$(tr '\0' '\n' < /proc/$EG/environ | grep -c '^DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=')"
echo "   老引擎 cwd=$(readlink /proc/$EG/cwd)（这就是 sandbox-policy 的 workspaceRoot）"

echo
echo "== ② 只杀引擎，等入口重拉（最多 120 秒）"
kill "$EG" && echo "   [ok] 已 SIGTERM $EG"
i=0; NEW=""
while [ $i -lt 24 ]; do
  i=$((i+1)); sleep 5
  NEW=$(pgrep -f 'dsh web' | head -1)
  L=$(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:3080$/' | wc -l)
  E=$(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:3081$/' | wc -l)
  echo "   第 ${i} 次（$((i*5)) 秒）：引擎=${NEW:-没起来}  :3080=$L  :3081=$E"
  [ -n "$NEW" ] && [ "$NEW" != "$EG" ] && [ "$L" -ge 1 ] && break
done
if [ -z "$NEW" ] || [ "$NEW" = "$EG" ]; then echo "   !! 120 秒内没换代成功 ⇒ 后面几节不不作数，先看入口日志"
else
  echo "   [ok] 换代 $EG ⇒ $NEW  $(who "$NEW")"
  echo "   入口还是不是 $EN：$( [ -d "/proc/$EN" ] && echo 是 || echo 变了 )"
  echo "   新引擎 env：DSH_PERMISSION_MODE 命中=$(tr '\0' '\n' < /proc/$NEW/environ | grep -c '^DSH_PERMISSION_MODE=')  ALLOW_NO_PIDNS 命中=$(tr '\0' '\n' < /proc/$NEW/environ | grep -c '^DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=')  cwd=$(readlink /proc/$NEW/cwd)"
  echo "   :3081 首页（入口那条，App 用的就是它）=$(curl -s -o /dev/null -m 12 -w '%{http_code} %{size_download}B' http://127.0.0.1:3081/ 2>&1)"
  echo "   :3080 裸打（401 是对的，说明引擎要券）=$(curl -s -o /dev/null -m 12 -w '%{http_code}' http://127.0.0.1:3080/ 2>&1)"
  echo "   入口日志末 6 行："; tail -6 /root/.dsh/entry.log 2>/dev/null | sed 's/^/     /'
fi

echo
echo "== ③ 上游 confine() 端到端：拿它自己算出来的 argv 去跑四条判据"
H=/tmp/dsh-confine-selftest.mjs
cat > "$H" <<'MJS'
// 用机上那份 dsh-sandbox-local 的真代码把命令包一层，再 spawn 它。
// 上游 confine() 返回 {argv, enforcement, denialSignatures, runnerFailureRules}，
// 而 :311-321 明写着"配了 runnerCommand 就直接用、不探测不验证" ⇒ 围没围只能这么自己点。
import { spawnSync } from 'node:child_process';
const LIB = process.argv[2];
const WS = process.argv[3];
const mod = await import('file://' + LIB);
const P = mod.LocalSandboxProvider ?? mod.default;
const cfg = { runnerCommand: ['/usr/local/bin/dsh-unshare-run'], runnerFailureSignatures: ['dsh-unshare-run: '], probeTimeoutMs: 5000 };
let provider, route = 'new LocalSandboxProvider(ctx, cfg)';
try {
  provider = new P({ inject() {}, effect() {}, register() {}, provide() {} }, cfg);
} catch (e) {
  route = 'prototype.confine.call(手搭的 this)（构造要真 ctx，退一步只验 confine 本身）';
  provider = Object.create(P.prototype);
  provider.runnerCommand = cfg.runnerCommand;
  provider.configuredRunnerFailureSignatures = cfg.runnerFailureSignatures;
}
const policy = { mode: 'workspace-write', workspaceRoot: WS };
const SCRIPT = [
  'echo INSIDE=$(echo sbx-ok > ' + WS + '/dsh-sbx-selftest.txt && cat ' + WS + '/dsh-sbx-selftest.txt)',
  'for t in /etc /root /; do',
  '  err=$( { echo x > "$t/dsh-sbx-selftest" ; } 2>&1 ); rc=$?',
  '  if [ $rc -eq 0 ]; then echo "OUTSIDE-$t=OPEN"; else echo "OUTSIDE-$t=BLOCK:$err"; fi',
  'done',
  'echo LIST_USR_BIN=$(ls /usr/bin 2>/dev/null | wc -l)',
  'echo PPID1=$(cat /proc/1/comm 2>/dev/null)',
  'echo KILL_TEST=$(ps -e -o pid= | tr -d " " | grep -c .)',
  'exit 42',
].join('; ');
const r = await provider.confine(['bash', '-c', SCRIPT], policy, undefined);
console.log('ROUTE=' + route);
console.log('ENFORCEMENT=' + r.enforcement);
console.log('ARGV0..3=' + JSON.stringify(r.argv.slice(0, 4)));
console.log('ARGV_HAS_RUNNER=' + (r.argv[0] === '/usr/local/bin/dsh-unshare-run' ? 'yes' : 'no'));
console.log('SEPARATOR=' + (r.argv.includes('--') ? 'yes' : 'no'));
console.log('FAILURE_RULES=' + JSON.stringify(r.runnerFailureRules));
console.log('DENIAL_SIGNATURES=' + JSON.stringify(r.denialSignatures));
const sp = spawnSync(r.argv[0], r.argv.slice(1), { encoding: 'utf8', timeout: 90000, cwd: WS });
console.log('SP_RC=' + sp.status);
console.log('STDOUT=' + (sp.stdout || '').trim().replace(/\n/g, ' | '));
console.log('STDERR_HAS_FATAL=' + (/dsh-unshare-run: /.test(sp.stderr || '') ? 'yes' : 'no'));
console.log('STDERR_HAS_NOTICE=' + (/dsh-unshare-run-notice:/.test(sp.stderr || '') ? 'yes' : 'no'));
console.log('STDERR_HEAD=' + (sp.stderr || '').trim().split('\n').slice(0, 3).join(' ⏎ ').slice(0, 300));
MJS
SB=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-sandbox-local/lib/index.js
if [ ! -f "$SB" ]; then
  SB=$(ls /usr/local/lib/node_modules/@deepseek-ai/*/node_modules/@deepseek-ai/dsh-sandbox-local/lib/index.js 2>/dev/null | head -1)
fi
echo "   上游模块：$SB  $( [ -f "$SB" ] && stat -c '%s B mtime=%y' "$SB" )"
. /root/.dsh-env 2>/dev/null   # 模拟服务那侧的 env（runner 继承的就是这一层）
timeout 150 node "$H" "$SB" /phone 2>&1 | sed 's/^/   /'
echo "   -- 自测件收拾："
rm -f /phone/dsh-sbx-selftest.txt /tmp/dsh-confine-selftest.mjs
echo "      /phone/dsh-sbx-selftest.txt 还在吗=$( [ -e /phone/dsh-sbx-selftest.txt ] && echo 在 || echo 不在)   /tmp 那个 mjs 还在吗=$( [ -e /tmp/dsh-confine-selftest.mjs ] && echo 在 || echo 不在)"

echo
echo "== ④ 对照：不围的时候那四处本来就能写（靶有效，③ 的 BLOCK 才作数）"
for t in /etc /root /; do
  if echo x > "$t/dsh-sbx-selftest" 2>/dev/null; then echo "   $t=OPEN（未围时可写）"; rm -f "$t/dsh-sbx-selftest"; else echo "   $t=写不进 rc=$?"; fi
done
echo "   /phone=可写：$(echo x > /phone/dsh-sbx-ctrl && rm -f /phone/dsh-sbx-ctrl && echo 是)"

echo
echo "== ⑤ 撤法（两条都在盘上）"
CB=$(ls -1 /root/.dsh/cordis.patch.yml.bak.* 2>/dev/null | tail -1)
EB=$(ls -1 /root/.dsh/dsh-env.bak.* 2>/dev/null | tail -1)
echo "   cordis：$CB  $( [ -f "$CB" ] && stat -c '%s B' "$CB" )  ⇒ cp -p $CB /root/.dsh/profiles/web/cordis.patch.yml 后再重启引擎"
echo "   dsh-env：$EB  $( [ -f "$EB" ] && stat -c '%s B' "$EB" )  ⇒ cp -p $EB /root/.dsh-env 后再重启引擎"
echo "   档位单独退（不接 runner 也想回到有 Bash 的旧形状）：/root/.dsh-env 那行改成 danger-full-access 后重启引擎"

echo
echo "== ⑥ 这发留没留东西"
echo "   /root/*.sh=$(ls /root/*.sh 2>/dev/null | wc -l)（含本探针自己）  /tmp 顶层=$(ls -A /tmp 2>/dev/null | wc -l)"
echo "   /phone 下我建的自测件残留=$(ls /phone/dsh-sbx-* 2>/dev/null | wc -l)  /etc 与 /root 下自测件=$(ls /etc/dsh-sbx-selftest /root/dsh-sbx-selftest 2>/dev/null | wc -l)"
echo "   备份件计数：cordis=$(ls /root/.dsh/cordis.patch.yml.bak.* 2>/dev/null | wc -l) dsh-env=$(ls /root/.dsh/dsh-env.bak.* 2>/dev/null | wc -l)"
