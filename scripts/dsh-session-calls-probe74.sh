#!/bin/bash
# 探针 74（只动 /tmp 自己那份临时件，跑完删）—— 73 那次我从会话记录里只捞到工具"说明书"（schema 里的 description 字段），
# 没捞到它**真发出去的那一条条命令**。这一发按记录里的 type 分两步取：先看一条 tool/call 的键形状，再照形状提命令。
# 要回答的三件事都只能从记录里拿，不能转述它的自述：
#   ① 它到底跑了哪些 Bash 命令（dpkg.log 14:39:47 那四个包是不是它装的；kill 那条是不是它发的；
#      它交给我的那三个 YES 是哪条命令的量出来的；它说"在 /data/local/tmp 与存储实测写成功"到底写过没有）
#   ② 它有没有在 14:44 前后又"应用"过一次 purge（若真重打过补丁，npm 树里那份模块的 mtime 会变；
#      72 第 ① 节读到的是 10:35:16，这里用 /tmp/dsh-purge-desktop.log（48,365 B，改于 14:44）再对一次时刻）
#   ③ /tmp 现在这 6 项分别是什么、哪些不是我建的（我建的一次性件 71/72/73 都跑完即删）
#
# 纪律：会话正文（他和它的对话原文）一律不打印，只打工具名+命令串，截 200 字符；键名命中 token/cookie/key 的整条丢掉；
#       只读，不改配置不删文件；探针自己数自己的 .sh。
set -u
export DEBIAN_FRONTEND=noninteractive LC_ALL=C HOME=/root
echo "chroot 内时刻: $(date '+%F %T %Z')   北京 $(TZ=Asia/Shanghai date '+%F %T')"
S=/root/.dsh/sessions/--phone-mycode-oneplus--/session-9dcf2bed-9793-4c6a-bed7-5859a9ebf38a/session.v4.jsonl.zstd

echo "== ① 会话记录里 tool/call 的真实形状与命令串"
H=/tmp/p74-read.mjs
cat > "$H" <<'MJS'
import { readFileSync } from 'node:fs';
import zlib from 'node:zlib';
const buf = readFileSync(process.argv[2]);
const MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);
const offs = [];
for (let i = 0; ; i = buf.indexOf(MAGIC, i + 1)) { if (i < 0) break; offs.push(i); }
let txt = '';
for (let k = 0; k < offs.length; k++) {
  const end = k + 1 < offs.length ? offs[k + 1] : buf.length;
  try { txt += zlib.zstdDecompressSync(buf.subarray(offs[k], end)).toString('utf8'); } catch (e) {}
}
const lines = txt.split('\n').filter((s) => s.trim());
const SECRET = /(token|cookie|authorization|api[-_]?key|secret|password|entry\.key)/i;
const KEYS = new Set();
const scan = (o, path) => {
  if (!o || typeof o !== 'object') return;
  if (Array.isArray(o)) { o.forEach((x) => scan(x, path + '[]')); return; }
  for (const [k, v] of Object.entries(o)) {
    if (SECRET.test(k)) continue;
    KEYS.add(path + '.' + k);
    if (v && typeof v === 'object') scan(v, path + '.' + k);
  }
};
let calls = [];
lines.forEach((l, i) => {
  let o; try { o = JSON.parse(l); } catch (e) { return; }
  if (o.type === 'tool/call') calls.push([i, o]);
});
console.log('TOOL_CALLS=' + calls.length);
if (calls.length) {
  const first = JSON.parse(JSON.stringify(calls[0][1]));
  scan(first, 'root');
  console.log('第一条 tool/call 的键路径（前 20 条）：');
  [...KEYS].slice(0, 20).forEach((p) => console.log('   ' + p));
}
const grab = (o, out) => {
  if (!o || typeof o !== 'object') return;
  if (Array.isArray(o)) { o.forEach((x) => grab(x, out)); return; }
  for (const [k, v] of Object.entries(o)) {
    if (SECRET.test(k)) continue;
    if (typeof v === 'string' && (k === 'command' || k === 'cmd' || k === 'script' || k === 'file_path' || k === 'pattern')) out.push(k + '=' + v.replace(/\s+/g, ' ').slice(0, 200));
    else if (v && typeof v === 'object') grab(v, out);
  }
};
const TOOLNAME = /"name":"([A-Za-z0-9_\-]{1,40})"/;
calls.forEach(([i, o], n) => {
  let nm = '';
  const raw = JSON.stringify(o);
  const m = TOOLNAME.exec(raw);
  if (m) nm = m[1];
  const out = [];
  grab(o.args ?? o.input ?? o.call ?? o, out);
  if (!out.length) grab(o, out);
  console.log(String(n).padStart(3) + ' [line ' + i + '] tool=' + nm + ' :: ' + out.join(' ⏎ ').slice(0, 260));
});
MJS
timeout 150 node "$H" "$S" 2>&1 | sed 's/^/   /'
rm -f "$H"

echo
echo "== ② purge 今天有没有被再应用一次（模块 mtime + 那份日志的时刻与尾部）"
LI=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-sandbox-local/lib/index.js
echo "   $LI  $(stat -c '%s B  mtime=%y' "$LI" | cut -c1-56)"
echo "   备份件 *.dshpurge.bak* 计数=$(find /usr/local/lib/node_modules/@deepseek-ai -name '*dshpurge*' 2>/dev/null | grep -c .)（70 那次量到 56）"
L=/tmp/dsh-purge-desktop.log
echo "   $L  $(stat -c '%s B  mtime=%y' "$L" 2>/dev/null | cut -c1-56)"
echo "   -- 尾部 6 行（只打形状，凭据行滤掉）："
tail -6 "$L" 2>/dev/null | grep -viE 'token|cookie|key|secret' | cut -c1-160 | sed 's/^/      /'
echo "   -- 今天 14:00 之后的行有几条：$(grep -cE '2026-10-21T14:' "$L" 2>/dev/null)"

echo
echo "== ③ /tmp 现在 6 项是什么（哪些不是我建的）"
ls -lt /tmp 2>/dev/null | head -10 | sed 's/^/   /'
echo "   dsh-spill-* 目录内容："; ls -l /tmp/dsh-spill-* 2>/dev/null | head -6 | sed 's/^/      /'

echo
echo "== ④ 服务与配置现场一句话复点（它接的线、我接的层）"
F=/root/.dsh/profiles/web/cordis.patch.yml
echo "   cordis $(stat -c %s "$F" 2>/dev/null) B  runnerCommand 命中=$(grep -c runnerCommand "$F" 2>/dev/null)  mtime=$(stat -c '%y' "$F" 2>/dev/null | cut -c1-19)"
EG=$(pgrep -f 'dsh web' | head -1)
echo "   引擎 pid=${EG:-没抓到}  入口 pid=$(pgrep -f 'dsh-entry.js' | head -1)  现场 dsh-unshare-run 进程=$(pgrep -f 'dsh-unshare-run' 2>/dev/null | grep -c .)"
echo "   :3080 裸打=$(curl -s -o /dev/null -m 12 -w '%{http_code}' http://127.0.0.1:3080/ 2>&1)"

echo
echo "== ⑤ 这发留没留东西"
rm -f /tmp/p74-read.mjs
echo "   /tmp 顶层=$(ls -A /tmp 2>/dev/null | wc -l)  p74 残留=$(ls -1 /tmp/p74-* 2>/dev/null | grep -c .)"
echo "   /root/*.sh=$(ls -1 /root/*.sh 2>/dev/null | wc -l)（含本探针自己）"
