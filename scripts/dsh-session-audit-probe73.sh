#!/bin/bash
# 探针 73（只动 /tmp 里我自己那两份临时件，跑完删）—— 把"手机里那个 dsh 到底执行过什么"从它自己的会话记录里读出来，
# 而不是转述它的自述。71/72 已经把配置层与代码层量清了，剩下三件只能从记录与会话目录拿：
#   ① 它这份会话（--phone-mycode-oneplus--/session-9dcf2bed…，292,649 B @14:44:43）里真跑过哪些工具调用
#      ⇒ dpkg.log 那四个包（jq/ripgrep，14:39:47）是不是它装的、它说的那三个 YES 是哪条命令跑出来的、
#         它有没有真在 /data/local/tmp 或手机存储写过东西（自述说"实测写成功"，但 72 第 ③ 节那里最新一件还是 10-19）。
#   ② /phone/mycode-oneplus 这个工作区现在有什么（它挂的工作目录），以及 /data/local/tmp 的目录 mtime。
#   ③ 我 10-19 落在他 /data/local/tmp 里那批一次性件的 md5（要清就得先与仓库孪生件撞上，证明删了还得回来）。
#
# 纪律：会话正文不整段往外抄，只提工具调用里的命令串（截 170 字符）与计数；凭据/tokens 一律滤掉不打印；
#       md5 先打原始行；探针自己数自己的 .sh；只读，不改任何配置、不删任何文件。
set -u
export DEBIAN_FRONTEND=noninteractive LC_ALL=C HOME=/root
echo "chroot 内时刻: $(date '+%F %T %Z')   北京 $(TZ=Asia/Shanghai date '+%F %T')"
S=/root/.dsh/sessions/--phone-mycode-oneplus--/session-9dcf2bed-9793-4c6a-bed7-5859a9ebf38a/session.v4.jsonl.zstd
echo "== ① 会话记录里它真跑了什么"
if [ -f "$S" ]; then
  echo "   $S  $(stat -c %s "$S") B  mtime=$(stat -c '%y' "$S" | cut -c1-19)"
  H=/tmp/p73-read.mjs
  cat > "$H" <<'MJS'
import { readFileSync } from 'node:fs';
import zlib from 'node:zlib';
const buf = readFileSync(process.argv[2]);
const MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);
const offs = [];
for (let i = 0; ; i = buf.indexOf(MAGIC, i + 1)) { if (i < 0) break; offs.push(i); }
let txt = '';
let fails = 0;
for (let k = 0; k < offs.length; k++) {
  const end = k + 1 < offs.length ? offs[k + 1] : buf.length;
  try { txt += zlib.zstdDecompressSync(buf.subarray(offs[k], end)).toString('utf8'); }
  catch (e) { fails++; }
}
console.log('FRAMES=' + offs.length + ' DECOMP_FAILS=' + fails + ' BYTES=' + txt.length);
const lines = txt.split('\n').filter((s) => s.trim());
console.log('LINES=' + lines.length);
const SECRET = /(token|cookie|authorization|api[-_]?key|secret|password)/i;
const cmds = [];
let roleCount = {};
const walk = (o, key) => {
  if (!o || typeof o !== 'object') return;
  if (Array.isArray(o)) { o.forEach((x) => walk(x, key)); return; }
  for (const [k, v] of Object.entries(o)) {
    if (SECRET.test(k)) continue;
    if (typeof v === 'string') {
      if ((k === 'command' || k === 'cmd' || k === 'script' || (k === 'description' && v.length > 3)) && v.length > 0) {
        cmds.push([key || '?', k, v.replace(/\s+/g, ' ').slice(0, 170)]);
      }
      if (k === 'name' && /^(Bash|Read|Write|Edit|Glob|Grep|WebSearch|Task|Agent|notebook|AskUser)$/.test(v)) cmds.push(['TOOL', v, '']);
    } else walk(v, k);
  }
};
lines.forEach((l, i) => {
  let o; try { o = JSON.parse(l); } catch (e) { return; }
  const r = (o.role || (o.message && o.message.role) || o.type || '?');
  roleCount[r] = (roleCount[r] || 0) + 1;
  walk(o, r);
});
console.log('ROLES=' + JSON.stringify(roleCount));
console.log('命中 unshare=' + lines.filter((l) => l.includes('unshare')).length +
  '  命中 confine=' + lines.filter((l) => l.includes('confine')).length +
  '  命中 cordis=' + lines.filter((l) => l.includes('cordis')).length +
  '  命中 purge=' + lines.filter((l) => l.includes('purge')).length +
  '  命中 apt=' + lines.filter((l) => /apt(-get)? /.test(l)).length +
  '  命中 data-local-tmp=' + lines.filter((l) => l.includes('data/local/tmp')).length +
  '  命中 kill=' + lines.filter((l) => /kill /.test(l)).length);
console.log('-- 工具调用与命令串（按出现顺序，最多 60 条）：');
cmds.slice(0, 60).forEach((c, i) => console.log(String(i).padStart(3) + ' [' + c[0] + '/' + c[1] + '] ' + c[2]));
console.log('CMD_TOTAL=' + cmds.length);
MJS
  timeout 120 node "$H" "$S" 2>&1 | sed 's/^/   /'
  rm -f "$H"
else
  echo "   !! 会话件不在（不猜，这条标未验）：$S"
  echo "   -- 换个办法：列最近改过的 3 个会话"
  find /root/.dsh/sessions -maxdepth 3 -name 'session.v4*' -printf '%T@ %10s %p\n' 2>/dev/null | sort -rn | head -3 | sed 's/^/   /'
fi

echo
echo "== ② 两处目录的现场（它自述写过，我看目录 mtime 与内容）"
echo "   /proc/1/root/data/local/tmp 目录本身：$(stat -c '%y' /proc/1/root/data/local/tmp 2>&1 | cut -c1-19)"
echo "   /phone/mycode-oneplus：$(stat -c '%y %s' /phone/mycode-oneplus 2>&1 | cut -c1-30)"
echo "   -- mycode-oneplus 顶层（最多 15 项，按时间）："
ls -lt /phone/mycode-oneplus 2>/dev/null | head -16 | sed 's/^/      /'
echo "      条目总数=$(ls -A /phone/mycode-oneplus 2>/dev/null | grep -c .)"
echo "   -- 今天（10-21 UTC 14:00 之后）改过的手机存储顶层件（它若真写过，这里应当出现）："
find /phone -maxdepth 2 -newermt '2026-10-21 14:00' -printf '%TY-%Tm-%Td %TH:%TM %10s %p\n' 2>/dev/null | head -14 | sed 's/^/      /'
echo "   -- 同样口径在 chroot 里的 /tmp 与 /root（它跑实验留没留件）："
find /tmp /root -maxdepth 1 -newermt '2026-10-21 14:00' -printf '%TY-%Tm-%Td %TH:%TM %10s %p\n' 2>/dev/null | head -18 | sed 's/^/      /'

echo
echo "== ③ 我 10-19 落在他 /data/local/tmp 的那批（md5 原始行，等与仓库孪生件撞）"
for f in dsh-devnull-inner.sh dsh-dev-node-probe.sh verify-unshare-run.sh dsh-sbx-probe.sh cfg-before.txt cfg-after.txt env10150.txt w.xml; do
  X=/proc/1/root/data/local/tmp/$f
  if [ -f "$X" ]; then
    RAW=$(md5sum "$X")
    SZ=$(stat -c %s "$X")
    MT=$(stat -c '%y' "$X" | cut -c1-19)
    printf '   %-24s %7s B  %s  原始行=[%s]\n' "$f" "$SZ" "$MT" "$RAW"
  else
    printf '   %-24s 不在（按读数）\n' "$f"
  fi
done
echo "   /data/local/tmp 条目总数=$(ls -1 /proc/1/root/data/local/tmp 2>/dev/null | grep -c .)（他那一批 boot_b.img/init_boot_b.img/kpatch/magiskboot/*.ko 我一个不碰）"

echo
echo "== ④ 这发留没留东西"
rm -f /tmp/p73-read.mjs
echo "   /tmp 顶层=$(ls -A /tmp 2>/dev/null | wc -l)  p73 残留=$(ls -1 /tmp/p73-* 2>/dev/null | grep -c .)"
echo "   /root/*.sh=$(ls -1 /root/*.sh 2>/dev/null | wc -l)（含本探针自己）"
