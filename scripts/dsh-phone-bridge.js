#!/usr/local/bin/node
'use strict';
/*
 * dsh-phone-bridge.js —— 零依赖 MCP stdio 服务器（壳 0.12 手机控制环的引擎侧）。
 *
 * 为什么手写：chroot 里只有 @modelcontextprotocol/client@2.2.0 + core@2.2.0，没有 server SDK
 * （探针 92 量的）⇒ 不引任何包，自己按 MCP 的 newline-delimited JSON-RPC 形状起一个 stdio server。
 * 引擎的内置插件 @deepseek-ai/dsh-mcp-client（loader 名 mcp-client）以 stdio 方式 spawn 本进程，
 * 把这里的工具注册成 mcp__phone__<name>（serverName=phone，探针 91/93 量的接线形状）。
 *
 * 每个 tools/call 现连一次壳服务的 abstract unix socket（'\0dsh-mobile-tree'），发一行 JSON、
 * 读一行 JSON、关连接。壳服务（TreeService.java 0.12）以 root 放行 chroot 引擎（uid 0）。
 * chroot 不 unshare net ⇒ abstract socket 按 netns 直达，不需要 TCP。
 *
 * 纪律：stdout 只走 JSON-RPC（SDK 逐行解析 stdout），一切日志走 stderr，否则协议会被脏行打断。
 * 自检：node dsh-phone-bridge.js --selftest（不需要手机，验协议层与工具映射）。
 */
const net = require('net');
const readline = require('readline');
const { spawn } = require('child_process');

const SOCKET = '\0dsh-mobile-tree';
const SERVER_INFO = { name: 'dsh-phone', version: '0.13.0' };
const CALL_TIMEOUT_MS = 30000;
const UINPUT = '/usr/local/bin/dsh-uinput.py';

// 内核输入层注入器：指纹（deviceId 真实、flags=0）比无障碍手势干净。壳侧连不上就自己退回无障碍。
let injector = null;
let injectorTries = 0;
function ensureInjector() {
  if (injector && injector.exitCode === null) return;
  if (injectorTries++ > 20) return;              // 连续起不来就别无限刷
  try {
    injector = spawn('/usr/bin/python3', [UINPUT, '--serve'], { stdio: ['ignore', 'ignore', 'pipe'] });
    injector.stderr.on('data', (d) => process.stderr.write('[uinput] ' + d));
    injector.on('error', (e) => process.stderr.write('[uinput] spawn 失败 ' + e.message + '\n'));
    injector.on('exit', (c) => {
      process.stderr.write('[uinput] 退出 ' + c + '，3 秒后重起\n');
      injector = null;
      setTimeout(ensureInjector, 3000).unref();
    });
  } catch (e) {
    process.stderr.write('[uinput] ' + e.message + '\n');
  }
}

// 固定工具集（与 TreeService.java 的命令一一对应）。描述进每个请求，别随权限状态变。
const TOOLS = [
  {
    name: 'screen',
    description: '读当前手机屏幕：每行一个控件，[编号] 只在本次屏幕里有效，屏幕一变就要重读。编号用于 tap/type/scroll。密码框只标「密码框」、不渲染内容。默认不带坐标；要坐标（给 tap_xy 用）就 detail:true。',
    inputSchema: {
      type: 'object',
      properties: {
        detail: { type: 'boolean', description: '附带每个控件的像素坐标 @(left,top-right,bottom)，默认 false' },
      },
      additionalProperties: false,
    },
  },
  {
    name: 'tap',
    description: '点一个控件（编号取自最近一次 screen），返回操作结果与新屏幕。long:true 为长按。控件不可点时自动退到可点父控件或坐标手势。',
    inputSchema: {
      type: 'object',
      properties: {
        id: { type: 'integer', description: '控件编号（来自 screen）' },
        long: { type: 'boolean', description: '长按，默认 false' },
      },
      required: ['id'],
      additionalProperties: false,
    },
  },
  {
    name: 'tap_xy',
    description: '按屏幕像素坐标点击，只在控件树里找不到目标时用。坐标来自 screen 行尾的 @(left,top-right,bottom)。返回新屏幕。',
    inputSchema: {
      type: 'object',
      properties: {
        x: { type: 'integer', description: '横坐标（像素，从 0 起）' },
        y: { type: 'integer', description: '纵坐标（像素，从 0 起）' },
      },
      required: ['x', 'y'],
      additionalProperties: false,
    },
  },
  {
    name: 'type',
    description: '往输入框输入文字（替换原内容），返回回读与新屏幕。密码框拒绝代填。编号取自最近一次 screen 里的输入框。',
    inputSchema: {
      type: 'object',
      properties: {
        id: { type: 'integer', description: '输入框编号（来自 screen）' },
        text: { type: 'string', description: '要输入的文字' },
      },
      required: ['id', 'text'],
      additionalProperties: false,
    },
  },
  {
    name: 'scroll',
    description: '滚动屏幕，返回新屏幕。id 是要滚的列表（省略时滚主内容区）。direction 是要浏览的方向：down 看下面、up 看上面、left/right 横向。',
    inputSchema: {
      type: 'object',
      properties: {
        id: { type: 'integer', description: '列表编号（来自 screen），省略滚主区' },
        direction: { type: 'string', enum: ['up', 'down', 'left', 'right'], description: '滚动方向，默认 down' },
      },
      required: ['direction'],
      additionalProperties: false,
    },
  },
  {
    name: 'key',
    description: '按系统键，返回新屏幕。back 返回 / home 回桌面 / recents 最近任务 / notifications 通知栏。',
    inputSchema: {
      type: 'object',
      properties: {
        key: { type: 'string', enum: ['back', 'home', 'recents', 'notifications'], description: '按键' },
      },
      required: ['key'],
      additionalProperties: false,
    },
  },
  {
    name: 'handoff',
    description: '遇到需要用户决定、或无法安全继续的步骤（弹窗要选、登录、验证码、支付、授权、你没把握的）就调用我：我会把 DSH 切到前台、把控制权交回聊天。调用之后就在聊天里把问题和可选项告诉用户、等他回答，然后（用 open 工具）重新打开原来的 App 继续。reason 用一句话说清要用户决定什么。',
    inputSchema: {
      type: 'object',
      properties: {
        reason: { type: 'string', description: '要用户决定什么，一句话' },
      },
      required: ['reason'],
      additionalProperties: false,
    },
  },
  {
    name: 'open',
    description: '打开一个 App（包名或名称，如 com.tencent.mm 或"微信"），返回打开后的新屏幕。用于用户回答后回到原来的 App 继续，或主动切到某个 App。',
    inputSchema: {
      type: 'object',
      properties: {
        app: { type: 'string', description: '包名或应用名' },
      },
      required: ['app'],
      additionalProperties: false,
    },
  },
];

/** MCP 工具名 + 参数 → 壳服务 JSON 命令。未知工具回 null。 */
function toPayload(name, a) {
  a = a || {};
  switch (name) {
    case 'screen': return { cmd: 'screen', detail: !!a.detail };
    case 'tap':    return { cmd: 'tap', id: a.id, long: !!a.long };
    case 'tap_xy': return { cmd: 'tap_xy', x: a.x, y: a.y };
    case 'type':   return { cmd: 'type', id: a.id, text: a.text };
    case 'scroll': {
      const p = { cmd: 'scroll', direction: a.direction || 'down' };
      if (a.id !== undefined) p.id = a.id;
      return p;
    }
    case 'key':    return { cmd: 'key', key: a.key };
    case 'handoff': return { cmd: 'handoff', reason: a.reason || '' };
    case 'open':    return { cmd: 'open', app: a.app };
    default: return null;
  }
}

/** 现连一次 abstract socket，发一行 JSON、读一行 JSON。 */
function phoneCall(payload) {
  return new Promise((resolve, reject) => {
    const sock = net.connect({ path: SOCKET });
    let buf = '';
    let settled = false;
    const timer = setTimeout(() => finish(new Error('壳服务响应超时（无障碍开关开了吗？操作可能仍在跑）')), CALL_TIMEOUT_MS);
    function finish(err, val) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { sock.destroy(); } catch (e) {}
      if (err) reject(err); else resolve(val);
    }
    sock.on('connect', () => { sock.write(JSON.stringify(payload) + '\n'); });
    sock.on('data', (d) => {
      buf += d.toString('utf8');
      const nl = buf.indexOf('\n');
      if (nl >= 0) {
        const line = buf.slice(0, nl);
        try { finish(null, JSON.parse(line)); }
        catch (e) { finish(new Error('壳服务响应不是 JSON：' + line.slice(0, 120))); }
      }
    });
    sock.on('error', (e) => finish(new Error('连不上壳服务（' + (e.code || e.message) + '）：确认「屏幕辅助」无障碍开关已开')));
    sock.on('close', () => { if (!settled) finish(new Error('壳服务连接提前关闭')); });
  });
}

// ---- JSON-RPC 输出（stdout 只走协议） --------------------------------------------------------------

let sink = (s) => process.stdout.write(s);
function write(obj) { sink(JSON.stringify(obj) + '\n'); }
function reply(id, result) { if (id !== undefined && id !== null) write({ jsonrpc: '2.0', id, result }); }
function replyError(id, code, message) { if (id !== undefined && id !== null) write({ jsonrpc: '2.0', id, error: { code, message } }); }

async function callTool(id, params) {
  const name = params && params.name;
  const payload = toPayload(name, params && params.arguments);
  if (!payload) return reply(id, { content: [{ type: 'text', text: '未知工具：' + name }], isError: true });
  try {
    const r = await phoneCall(payload);
    if (r && r.ok) {
      let text = '';
      if (r.result) text += r.result;
      if (r.screen) text += (text ? '\n\n' : '') + r.screen;
      return reply(id, { content: [{ type: 'text', text: text || '(空屏幕)' }] });
    }
    return reply(id, { content: [{ type: 'text', text: (r && r.error) || '壳服务返回失败' }], isError: true });
  } catch (e) {
    return reply(id, { content: [{ type: 'text', text: String((e && e.message) || e) }], isError: true });
  }
}

async function handle(msg) {
  const id = msg.id;
  const method = msg.method;
  const params = msg.params || {};
  if (method === 'initialize') {
    return reply(id, {
      // 回客户端报的版本（SDK 把它当协商结果）；本机没有版本表，echo 最稳。
      protocolVersion: params.protocolVersion || '2024-11-05',
      capabilities: { tools: { listChanged: false } },
      serverInfo: SERVER_INFO,
    });
  }
  if (method === 'notifications/initialized' || method === 'initialized') return; // 通知，无响应
  if (method === 'ping') return reply(id, {});
  if (method === 'tools/list') return reply(id, { tools: TOOLS });
  if (method === 'tools/call') return await callTool(id, params);
  if (id !== undefined && id !== null) return replyError(id, -32601, 'Method not found: ' + method);
}

// ---- 自检（不需要手机） ----------------------------------------------------------------------------

async function selftest() {
  const out = [];
  sink = (s) => out.push(s);
  let pass = 0, fail = 0;
  const check = (name, cond) => { if (cond) { pass++; console.error('[PASS] ' + name); } else { fail++; console.error('[FAIL] ' + name); } };
  const last = () => JSON.parse(out[out.length - 1]);

  await handle({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18' } });
  check('initialize 回客户端版本', last().result.protocolVersion === '2025-06-18');
  check('initialize 声明 tools 能力', !!last().result.capabilities.tools);
  check('initialize serverInfo 名', last().result.serverInfo.name === 'dsh-phone');

  await handle({ jsonrpc: '2.0', id: 2, method: 'tools/list' });
  check('tools/list 共 8 个', last().result.tools.length === 8);
  check('工具名集合与顺序', JSON.stringify(last().result.tools.map((t) => t.name)) === JSON.stringify(['screen', 'tap', 'tap_xy', 'type', 'scroll', 'key', 'handoff', 'open']));
  check('每个工具有 inputSchema', last().result.tools.every((t) => t.inputSchema && t.inputSchema.type === 'object'));

  await handle({ jsonrpc: '2.0', id: 3, method: 'ping' });
  check('ping 回 {}', JSON.stringify(last().result) === '{}');

  const before = out.length;
  await handle({ jsonrpc: '2.0', method: 'notifications/initialized' });
  check('initialized 通知无响应', out.length === before);

  await handle({ jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'nope', arguments: {} } });
  check('未知工具 isError', last().result.isError === true);

  await handle({ jsonrpc: '2.0', id: 5, method: 'no/such/method' });
  check('未知方法回 -32601', last().error && last().error.code === -32601);

  check('toPayload tap', JSON.stringify(toPayload('tap', { id: 5, long: true })) === JSON.stringify({ cmd: 'tap', id: 5, long: true }));
  check('toPayload tap 默认 long=false', toPayload('tap', { id: 5 }).long === false);
  check('toPayload scroll 省略 id', !('id' in toPayload('scroll', { direction: 'down' })));
  check('toPayload scroll 带 id', toPayload('scroll', { direction: 'up', id: 3 }).id === 3);
  check('toPayload screen 默认不带坐标', JSON.stringify(toPayload('screen', {})) === JSON.stringify({ cmd: 'screen', detail: false }));
  check('toPayload screen detail', toPayload('screen', { detail: true }).detail === true);
  check('toPayload 未知回 null', toPayload('nope', {}) === null);
  check('toPayload handoff', JSON.stringify(toPayload('handoff', { reason: '选A还是B' })) === JSON.stringify({ cmd: 'handoff', reason: '选A还是B' }));
  check('toPayload open', JSON.stringify(toPayload('open', { app: 'com.tencent.mm' })) === JSON.stringify({ cmd: 'open', app: 'com.tencent.mm' }));

  console.error('合计 ' + (pass + fail) + ' 条：PASS ' + pass + ' / FAIL ' + fail);
  process.exit(fail ? 1 : 0);
}

// ---- 入口 ----------------------------------------------------------------------------------------

if (process.argv.includes('--selftest')) {
  selftest();
} else {
  ensureInjector();
  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  rl.on('line', (line) => {
    line = line.trim();
    if (!line) return;
    let msg;
    try { msg = JSON.parse(line); } catch (e) { return; } // 脏行忽略，不打断协议
    Promise.resolve(handle(msg)).catch((e) => {
      if (msg && msg.id !== undefined) replyError(msg.id, -32603, String((e && e.message) || e));
    });
  });
  rl.on('close', () => process.exit(0));
  process.stdin.on('error', () => {});
  process.stdout.on('error', () => {});
}