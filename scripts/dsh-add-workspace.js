// dsh-add-workspace.js —— 直接往 dsh 的工作区登记表里加一条（绕开手机浏览器里坏掉的"选目录"弹窗）
// 为什么要有这个脚本：一加 13 上预装的 HeyTap 浏览器内核太老，页面里点"添加工作区"直接报
//   AbortSignal.any is not a function
// （AbortSignal.any 要 Chrome 116+）。登记表本身就是一个普通 JSON：
//   $DSH_HOME/storages/workspace.json，schema 见
//   node_modules/@deepseek-ai/dsh-workspace/lib/types/spec.js:workspaceRecord
// 用法（chroot 里，服务必须先停，否则内存里的旧状态会在退出时把这份文件盖回去）：
//   node /root/dsh-add-workspace.js /phone 手机存储
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const FILE = process.env.DSH_WS_FILE || "/root/.dsh/storages/workspace.json";
const [target, title] = [process.argv[2], process.argv[3]];
if (!target) {
  console.error("用法: node dsh-add-workspace.js <目录> [显示名]");
  process.exit(2);
}
const name = title || path.basename(target.replace(/\/+$/, "")) || target;

const st = JSON.parse(fs.readFileSync(FILE, "utf8"));
if (st.unit?.name !== "workspace") {
  console.error(`!! ${FILE} 不是 workspace 登记表，不敢改`);
  process.exit(3);
}
const real = fs.realpathSync(target);
if (!fs.statSync(real).isDirectory()) {
  console.error(`!! ${real} 不是目录`);
  process.exit(4);
}
for (const [id, rec] of Object.entries(st.tables?.workspaces || {})) {
  if (rec.path === real) {
    console.log(`[skip] 已登记：${real} (id=${id.slice(0, 8)} title=${rec.title})`);
    process.exit(0);
  }
}
const id = crypto.randomUUID();
const now = new Date().toISOString();
st.global = st.global || {};
st.global.initialized = true;
st.global.workspaceIds = [...(st.global.workspaceIds || []), id];
st.tables = st.tables || {};
st.tables.workspaces = st.tables.workspaces || {};
st.tables.workspaces[id] = {
  path: real,
  title: name,
  sessionIds: [],
  createdAt: now,
  updatedAt: now,
};
fs.writeFileSync(FILE + ".bak", fs.readFileSync(FILE));
fs.writeFileSync(FILE, JSON.stringify(st, null, 2) + "\n");
console.log(`[ok] 登记 ${real} 显示名「${name}」id=${id}`);
console.log(`     原文件备份在 ${FILE}.bak（要退回去：cp 回来再重启服务）`);
console.log(`     现在表里共 ${st.global.workspaceIds.length} 条`);
