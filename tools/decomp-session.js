const fs = require('fs'), zlib = require('zlib');
const p = process.argv[2];
const buf = fs.readFileSync(p);
const MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);
const offs = [];
for (let i = 0; ; i = buf.indexOf(MAGIC, i + 1)) { if (i < 0) break; offs.push(i); }
console.log('FRAMES=' + offs.length + ' SIZE=' + buf.length);
let txt = '';
for (let k = 0; k < offs.length; k++) {
  const end = k + 1 < offs.length ? offs[k + 1] : buf.length;
  try { txt += zlib.zstdDecompressSync(buf.subarray(offs[k], end)).toString('utf8'); }
  catch (e) { console.log('FRAME' + k + ' FAIL ' + e.message); }
}
console.log('BYTES=' + txt.length);
const lines = txt.split('\n').filter(s => s.trim());
console.log('LINES=' + lines.length);
lines.forEach((l, i) => { let o; try { o = JSON.parse(l); } catch (e) { console.log(i, 'RAW', l.slice(0, 150)); return; }
  const s = JSON.stringify(o);
  const tools = (s.match(/"name":"([^"]{1,30})"/g) || []).join(',');
  const sandbox = /sandbox backend is usable|danger-full-access|workspace-write|unconfined/.test(s) ? ' <<<SANDBOXWORDS' : '';
  console.log(i, o.type || '?', (o.role || (o.message && o.message.role) || '').slice(0, 12), 'len=' + s.length, tools.slice(0, 120), sandbox);
});
