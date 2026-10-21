#!/bin/bash
# 探针 75（只动 /tmp 自己那份临时件，跑完删）—— 74 那发把 44 条 tool/call 的名字提出来了，命令串全是空。
# 原因是键路径 root.data.arguments：**arguments 是个字符串**（JSON 编码），我的递归只认对象里的 command 键 ⇒ 抓空。
# 这是"错误进到了我要数的字段"那一族（AGENTS.md 第 2 条），按读数改口重来一次，不猜。
# 只要一件事：那 44 条工具调用里到底发了哪些命令 —— 用来判它自述的四条（备份/接线/三个 YES/延迟 kill）。
set -u
export DEBIAN_FRONTEND=noninteractive LC_ALL=C HOME=/root
echo "chroot 内时刻: $(date '+%F %T %Z')   北京 $(TZ=Asia/Shanghai date '+%F %T')"
S=/root/.dsh/sessions/--phone-mycode-oneplus--/session-9dcf2bed-9793-4c6a-bed7-5859a9ebf38a/session.v4.jsonl.zstd
H=/tmp/p75-read.mjs
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
const SECRET = /(token|cookie|authorization|api[-_]?key|secret|password)/i;
const pick = (o, out) => {
  if (!o) return;
  if (typeof o === 'string') return;
  if (Array.isArray(o)) { o.forEach((x) => pick(x, out)); return; }
  for (const [k, v] of Object.entries(o)) {
    if (SECRET.test(k)) continue;
    if (typeof v === 'string' && (k === 'command' || k === 'file_path' || k === 'pattern')) out.push(k + ': ' + v.replace(/\s+/g, ' ').slice(0, 220));
    else if (v && typeof v === 'object') pick(v, out);
  }
};
let n = 0;
lines.forEach((l) => {
  let o; try { o = JSON.parse(l); } catch (e) { return; }
  if (o.type !== 'tool/call') return;
  const d = o.data || {};
  let a = d.arguments;
  const out = [];
  if (typeof a === 'string') { try { a = JSON.parse(a); } catch (e) { out.push('ARG_RAW: ' + a.replace(/\s+/g, ' ').slice(0, 160)); } }
  pick(a, out);
  if (!out.length && typeof a === 'object' && a) out.push('键名: ' + Object.keys(a).join(','));
  console.log(String(n).padStart(3) + ' [' + (d.name || '?') + '] ' + out.join(' ⏎ ').slice(0, 300));
  n++;
});
console.log('TOTAL=' + n);
MJS
timeout 150 node "$H" "$S" 2>&1 | sed 's/^/   /'
rm -f "$H"
echo "   /tmp 顶层=$(ls -A /tmp 2>/dev/null | wc -l)  p75 残留=$(ls -1 /tmp/p75-* 2>/dev/null | grep -c .)  /root/*.sh=$(ls -1 /root/*.sh 2>/dev/null | wc -l)"
