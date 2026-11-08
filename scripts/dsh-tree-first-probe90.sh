#!/bin/bash
# p90 — 壳 0.11 控件树服务首验（纯只读，不点不输不手势）
# 判据：① 服务真在无障碍名单里 ② chroot 的 Node 连得上 abstract socket（ping→pong）
#       ③ screen 真回一棵带编号的树（头行/编号行数/字节数三个数同源）
# 前提：用户已在系统里开启「DSH 控件树（只读）」。没开就是 ① 空、② 连不上——如实报，不算失败。
set -u
echo "== ① 无障碍服务名单（宿主侧读） =="
# 这条在 chroot 里读不到 Android settings，改由 run-probe 外层补；这里只读 /proc 侧证据
echo "（settings 名单由 PC 侧复点，见输出文件头）"

echo "== ② abstract socket 连通性（chroot Node → App 服务） =="
node -e '
const net = require("net");
const s = net.connect({ path: "\u0000dsh-mobile-tree" });
let buf = "";
const t = setTimeout(() => { console.log("PING_TIMEOUT"); s.destroy(); process.exit(2); }, 5000);
s.on("connect", () => s.write("ping\n"));
s.on("data", (d) => {
  buf += d.toString("utf8");
  if (buf.includes("\n\n")) {
    clearTimeout(t);
    console.log("PING_REPLY=" + JSON.stringify(buf.trim()));
    s.end();
    process.exit(buf.trim() === "pong" ? 0 : 3);
  }
});
s.on("error", (e) => { clearTimeout(t); console.log("CONNECT_ERR=" + e.code); process.exit(4); });
'
PING_RC=$?
echo "ping_rc=$PING_RC"
[ "$PING_RC" -eq 0 ] || { echo "== 服务没起或连不上：到此为止（先确认无障碍开关已开） =="; exit 0; }

echo "== ③ 读一屏控件树 =="
node -e '
const net = require("net");
const s = net.connect({ path: "\u0000dsh-mobile-tree" });
let buf = "";
const t = setTimeout(() => { console.log("SCREEN_TIMEOUT"); s.destroy(); process.exit(2); }, 8000);
s.on("connect", () => s.write("screen\n"));
s.on("data", (d) => {
  buf += d.toString("utf8");
  if (buf.endsWith("\n\n")) {
    clearTimeout(t);
    const body = buf.slice(0, -2);
    const lines = body.split("\n");
    const items = lines.filter((l) => /^\s*\[\d+\]/.test(l)).length;
    console.log("BYTES=" + Buffer.byteLength(body, "utf8"));
    console.log("HEAD=" + lines[0]);
    console.log("ITEM_LINES=" + items);
    console.log("---- 树原文（前 40 行） ----");
    console.log(lines.slice(0, 40).join("\n"));
    s.end();
    process.exit(0);
  }
});
s.on("error", (e) => { clearTimeout(t); console.log("CONNECT_ERR=" + e.code); process.exit(4); });
'
echo "screen_rc=$?"
echo "== 完 =="