const fs = require('fs'), zlib = require('zlib');
const buf = fs.readFileSync(process.argv[2]);
const want = process.argv.slice(3).map(Number);
const MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);
const offs = []; for (let i = 0; ; i = buf.indexOf(MAGIC, i + 1)) { if (i < 0) break; offs.push(i); }
let txt = '';
for (let k = 0; k < offs.length; k++) { const end = k + 1 < offs.length ? offs[k + 1] : buf.length; try { txt += zlib.zstdDecompressSync(buf.subarray(offs[k], end)).toString('utf8'); } catch (e) {} }
const lines = txt.split('\n').filter(s => s.trim());
for (const i of want) { console.log('===== [' + i + '] ====='); try { console.log(JSON.stringify(JSON.parse(lines[i]), null, 1).slice(0, 2600)); } catch (e) { console.log('ERR'); } }
