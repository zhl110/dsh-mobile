#!/usr/bin/env node
// dsh-entry.js —— 手机上那个"点开就能用"的入口
//
// 它解决的具体问题（他 2026-10-20 那句"既出现一个桌面端，功能又全面"）：
//   dsh web 强制鉴权，入场券是启动时打印的那条 ?token=<43 位>；token 每次重启都换，
//   所以任何写死在 App / 书签 / 桌面图标里的地址，一重启就变成 401。
//   我们那个 78 KB 的 WebView 壳今天就栽在这上面（token 是打包时烧进 app/local/url.txt 的）。
//
// 三家社区方案怎么做的（本盘上有实物，逐行读过）：
//   - DSHA 自己起引擎 ⇒ 从**本轮 stdout** 严格匹配那行官方启动行，换成 30 天的 dsh-auth-* cookie，
//     WebView 打开的是不带 token 的 base URL：util/DshAuthUrl.java:25-26（正则要求整行、拒绝截半行）、
//     :10（"dsh 用 Buffer.toString('base64url') 生成进程 token"）、core/WebLifecycleController.java:40
//     （authUrl 只 volatile 存内存）、util/SensitiveData.java:19（落盘前把 [?&]token= 打掉）。
//   - Soodok / woaiys3 各有一个本机代理做同一件事：Soodok scripts/dsh-lan-proxy.js:60-78 从 engine.log
//     尾部取最新 token、:84-118 是一份"改写清单"（isLoopbackHostname、polyfill）；
//     woaiys3 MainActivity.java:4139 认的也是 "dsh web: http://127.0.0.1:3080/?token=..." 这行。
//   - 三家的 token 都是"用过即废"，所以健康探测**绝不能带 token**：woaiys3 MainActivity.java:2453-2456
//     与 CHANGES.md:1358 是两家独立踩过的同一坑（探测把 token 吃掉 ⇒ 用户看到白屏）。
//
// 我们的差别只有一处：**引擎在 root 的 chroot 里，App 起不了它，也读不到它的 stdout**。
// 所以把"起引擎 + 认那行 + 换 cookie"这半挪进这个常驻小工具（它就是 DSHA/Soodok 那个代理的形状），
// App 退回成一个纯 WebView：地址永远是 http://127.0.0.1:<入口端口>/，重启多少次都不用改。
//
// 安全口径（写死，别默改）：
//   - 只绑 127.0.0.1。**不学 DSHA 的 LanProxyService.java:308 那样 bind 0.0.0.0** —— 那台机是往局域网
//     敞开的，我们不需要，而且他们的 SECURITY.md 自己写着局域网模式"authenticates but does not encrypt"。
//   - 每个请求必须带我们 App 里那份口令（cookie `dsh-entry=`，由壳在首次加载前用 CookieManager 种下，
//     HttpOnly ⇒ 页面 JS 读不到）。没带或不对一律 **404**，不回 403 —— 不告诉扫描者这个端口存在。
//   - Host 必须是 127.0.0.1:端口 / localhost:端口，否则 404（挡 DNS rebinding：别的站点的页面
//     拿 XHR 打到本机是被浏览器允许的，这道检查就是为它准备的）。
//   - 口令是打进 APK 的，**APK 在设备上可读** ⇒ 这条是"抬高门槛"不是"密不透风"：
//     它挡住的是手机上其他普通 App 直接连 3081 拿走一个 root 级会话，挡不住拆包我们 APK 的人。
//     真要有更高要求就得回到"重启后粘一次"那条路（他知道代价，所以我们把话说在这）。
//   - token 全程不落盘、不进日志、不进 argv（只在本机进程内存里过一手）。
//
// 用法（都在 chroot 里以 root 跑，网络命名空间和外面是同一个，所以 3081 从 Android 侧可达）：
//   node /usr/local/bin/dsh-entry.js --start      前台起（父脚本用 nohup/& 拉起，pid 由它自己写）
//   node /usr/local/bin/dsh-entry.js --status     只读打印当前状态（引擎在不在、cookie 多久、注入了几次）
//   node /usr/local/bin/dsh-entry.js --stop       写哨兵 + 杀引擎与本进程（哨兵是给看门狗看的）
//   node /usr/local/bin/dsh-entry.js --selftest    不碰引擎，拿一个假上游把上面每条判据都打一遍
//
// 环境变量：DSH_ENTRY_KEY（必填）/ DSH_ENTRY_PORT(3081) / DSH_UP_PORT(3080) / DSH_UP_HOST(127.0.0.1)
//   DSH_ENTRY_COMPAT（要内联进 HTML 的兼容脚本路径）/ DSH_ENTRY_LOG / DSH_ENTRY_PID / DSH_ENGINE_CMD
//   DSH_ENTRY_KEY_FILE（默认 /root/.dsh/entry.key，口令优先从这里读）/ DSH_ENTRY_KEY（临时试验用，别写进脚本）
'use strict';

const fs = require('fs');
const http = require('http');
const net = require('net');
const path = require('path');
const crypto = require('crypto');
const zlib = require('zlib');
const { spawn } = require('child_process');

const CFG = {
  upHost: process.env.DSH_UP_HOST || '127.0.0.1',
  upPort: +(process.env.DSH_UP_PORT || 3080),
  entryHost: '127.0.0.1',
  entryPort: +(process.env.DSH_ENTRY_PORT || 3081),
  key: process.env.DSH_ENTRY_KEY || '',
  keyFile: process.env.DSH_ENTRY_KEY_FILE || '/root/.dsh/entry.key',
  compat: process.env.DSH_ENTRY_COMPAT || '/root/.dsh/entry-compat.js',
  log: process.env.DSH_ENTRY_LOG || '/root/.dsh/entry.log',
  pid: process.env.DSH_ENTRY_PID || '/root/.dsh/entry.pid',
  stopped: process.env.DSH_ENTRY_STOPPED || '/root/.dsh/entry-stopped',
  // upgrade 隧道**握手**的等待上限（不是空闲上限，见 attachUpgrade 里那条 2026-10-20 的坑）。
  wsHandshakeMs: +(process.env.DSH_ENTRY_WS_HANDSHAKE_MS || 8000),
  // 和 scripts/dsh-chroot.sh:181 那条实测能用的拉起式对齐，只多两个参数：--no-open（chroot 里没有浏览器，
  // 别让它白试一次 xdg-open）、--host/--port 显式写死（默认值不该由入口的去猜）
  engineCmd: process.env.DSH_ENGINE_CMD ||
    ". /root/.dsh-env >/dev/null 2>&1; cd /phone 2>/dev/null || cd /root; exec dsh web --no-open --host 127.0.0.1 --port ${DSH_UP_PORT}",
};

// DSHA 那两条判据原样搬过来：整行、43 位 base64url、拒绝半行（DshAuthUrl.java:25-26 / :22）
const STARTUP_LINE = /^dsh web: (https?:\/\/127\.0\.0\.1:(\d+)\/\?token=([A-Za-z0-9_-]{43}))(?:[ \t][^\r\n]*)?$/;
const AUTH_COOKIE = /^dsh-auth-[A-Za-z0-9_-]{43}=/;

const S = {
  startedAt: Date.now(),
  gen: 0,                 // 引擎代次：每次真正拿到新的启动行才算一代
  engine: null,
  enginePid: 0,
  upBase: '',             // http://127.0.0.1:3080/  —— 不含 token
  authCookie: '',         // 换到的长期凭据，只在内存
  cookieAt: 0,
  pendingTokenUrl: '',    // 那行官方启动行给的完整 URL（含 token），用过即清
  stopping: false,
  restartTimer: null,
  backoff: 2000,
  inj: { at: -1, anchor: '', firstScriptAt: -1, order: '', closed: '', whole: '' },
  lastReq: '',
  // 非 2xx 的最近若干条（方法 路径 → 状态）。他手机上"点了没反应 / 报一句 HTTP 403"这类问题，
  // 光靠一个总数（denied / up401）定不了是哪个接口；这一条把"到底哪一发红了"直接打到自述页上。
  bad: [],
  // 全量请求流水（最近 30 条，新→旧）。"点了没反应"往往根本没有 4xx —— 要么页面没发请求，
  // 要么 200 了但前端自己没跳转，这两种都只有全量流水能分开。
  seen: [],
  n: { req: 0, denied: 0, injected: 0, injectMiss: 0, upstream401: 0, reauth: 0, ws: 0, engineStart: 0, engineExit: 0, lastErr: '' },
};

function redact(s) {
  return String(s).replace(/([?&]token=)[A-Za-z0-9_-]+/g, '$1<redacted>')
                  .replace(/(dsh-entry[=:])[^;\s"']+/g, '$1<redacted>');
}
function log(msg) {
  const line = `${new Date().toISOString()} ${redact(msg)}\n`;
  try {
    fs.mkdirSync(path.dirname(CFG.log), { recursive: true, mode: 0o700 });
    fs.appendFileSync(CFG.log, line, { mode: 0o600 });
  } catch (e) { /* 日志写不进不能把入口带倒 */ }
  process.stdout.write(line);
}
// 只有 --status 与被别的脚本读；人读友好优先，字段一行一个
function statusText() {
  return [
    `entry        http://${CFG.entryHost}:${CFG.entryPort}（只绑本机回环）`,
    `upstream     ${S.upBase || '(还没从引擎启动行里认到端口)'}  配置期望 :${CFG.upPort}`,
    `gen          ${S.gen}`,
    `engine       ${S.engine && !S.engine.killed ? `running pid=${S.enginePid}` : 'not running'}`,
    `auth cookie  ${S.authCookie ? `有，已用 ${Math.round((Date.now() - S.cookieAt) / 1000)} 秒` : '无（还没换到）'}`,
    `token 待用    ${S.pendingTokenUrl ? '有一条还没交换' : '无'}`,
    `compat 脚本   ${fs.existsSync(CFG.compat) ? CFG.compat : '(缺失 ⇒ HTML 原样透传，并记 injectMiss)'}`,
    // 顺序由读数自证：polyfill 落在哪、引擎第一段脚本在哪、谁在前。bad 就是"页面能开但兼容层没生效"。
    `内联位置      ${S.inj.at < 0 ? '还没注入过任何 HTML' : `at=${S.inj.at}（${S.inj.anchor}）firstScript=${S.inj.firstScriptAt} order=${S.inj.order} 元素完整性=${S.inj.whole || '未算'} ${S.inj.closed}`}`,
    `最近请求      ${S.lastReq || '还没转发过任何请求'}`,
    // 全量流水放在这里：他手机上"点了插件没跳转"那种问题，第一件要知道的是**页面到底有没有发请求**。
    // 一条请求都没有 ⇒ 卡在 App/前端路由；有 200 而画面不动 ⇒ 卡在前端跳转；有 4xx ⇒ 看下面那份清单。
    ...(S.seen.length
      ? [`请求流水      最近 ${Math.min(S.seen.length, 14)} 条（新→旧，共 ${S.seen.length}）：`, ...S.seen.slice(0, 14).map((r) => '  ' + r)]
      : ['请求流水      （还没转发过任何请求）']),
    ...(S.bad.length
      ? [`非 2xx       最近 ${S.bad.length} 条（新→旧）：`, ...S.bad.map((b) => '  ' + b)]
      : ['非 2xx       （还没有过 —— 有的话这里会列出方法、路径与状态码）']),
    `计数          req=${S.n.req} denied=${S.n.denied} injected=${S.n.injected} injectMiss=${S.n.injectMiss} ` +
      `up401=${S.n.upstream401} reauth=${S.n.reauth} ws=${S.n.ws} engineStart=${S.n.engineStart} exit=${S.n.engineExit}`,
    `最后错误      ${S.n.lastErr || '（无）'}`,
    `哨兵          ${fs.existsSync(CFG.stopped) ? `${CFG.stopped} 在位 ⇒ 看门狗不会重拉` : '不在'}`,
    `运行          ${Math.round((Date.now() - S.startedAt) / 1000)} 秒`,
  ].join('\n') + '\n';
}

// ── 引擎生命周期 ────────────────────────────────────────────────────────────
function startEngine() {
  if (S.stopping) return;
  if (fs.existsSync(CFG.stopped)) { log('STOPPED 哨兵在位，不拉引擎（--stop 写过它）'); return; }
  if (S.engine && !S.engine.killed) { log(`引擎已在跑 pid=${S.enginePid}，不重复拉`); return; }
  const cmd = CFG.engineCmd.replace('${DSH_UP_PORT}', String(CFG.upPort));
  S.gen += 1;
  const gen = S.gen;
  log(`第 ${gen} 代：spawn bash -lc <${redact(cmd)}>`);
  const child = spawn('/bin/bash', ['-lc', cmd], { stdio: ['ignore', 'pipe', 'pipe'], env: process.env });
  S.engine = child;
  S.enginePid = child.pid;
  S.n.engineStart += 1;
  // 逐行喂给正则 —— 分块到达的行先攒着，避免"半行"被当成匹配失败（DSHA 的判据也是整行才算）
  let buf = '';
  const onData = (d) => {
    buf += d.toString('utf8');
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i).replace(/\r$/, '');
      buf = buf.slice(i + 1);
      handleEngineLine(gen, line);
    }
  };
  child.stdout.on('data', onData);
  child.stderr.on('data', onData);
  child.on('exit', (code, sig) => {
    S.n.engineExit += 1;
    log(`第 ${gen} 代引擎退出 code=${code} sig=${sig}`);
    S.engine = null; S.enginePid = 0;
    if (!S.stopping && !fs.existsSync(CFG.stopped)) {
      log(`${S.backoff}ms 后重拉`);
      S.restartTimer = setTimeout(startEngine, S.backoff);
      S.backoff = Math.min(S.backoff * 2, 30000);
    }
  });
  child.on('error', (e) => { S.n.lastErr = 'spawn ' + e.message; log('引擎 spawn 失败：' + e.message); });
}

function handleEngineLine(gen, line) {
  const m = STARTUP_LINE.exec(line);
  if (!m) {
    // 其余 stdout 一律丢弃（不写盘）—— woaiys3 那份"原文 tee 到 /sdcard"是我们明确不抄的（RUNBOOK 14.12）
    if (/token=/.test(line)) log('!! 有一行含 token 但不符合官方启动行格式 ⇒ 只记这一句，正文不落盘');
    return;
  }
  if (gen !== S.gen) return;                      // 上一代的迟到的行不算
  S.upBase = `http://${CFG.upHost}:${m[2]}/`;      // 端口以那行**实际报的**为准，不按配置猜（DSHA 同口径）
  S.pendingTokenUrl = m[1];
  S.backoff = 2000;
  log(`认到第 ${gen} 代启动行：upstream=${S.upBase} token=<${m[3].length} 位，已丢弃>`);
  exchange().catch((e) => { S.n.lastErr = 'exchange ' + e.message; log('换 cookie 失败：' + e.message); });
}

// token → dsh-auth-* cookie。每代只交换一次（DSHA core/LanAuthBridge.java:93-108 同口径），
// 交换请求本身**就是**那条带 token 的 URL，不带我们自己的凭据。
function exchange() {
  return new Promise((resolve, reject) => {
    const url = S.pendingTokenUrl;
    if (!url) return reject(new Error('没有待用的启动行'));
    const req = http.get(url, { agent: false }, (res) => {
      const sc = res.headers['set-cookie'] || [];
      const hit = sc.find((c) => AUTH_COOKIE.test(c.split(';')[0]));
      res.resume();
      // 先把 token 用掉这一事实落地：不管成不成，同一条 token 不再复用第二次（它是一次性的）
      S.pendingTokenUrl = '';
      if (!hit) {
        return reject(new Error(`交换没拿到 dsh-auth-* cookie（http=${res.statusCode}，set-cookie=${sc.length} 条）`));
      }
      S.authCookie = hit.split(';')[0];
      S.cookieAt = Date.now();
      log(`第 ${genOf()} 代凭据已换取：cookie=${S.authCookie.slice(0, 14)}…（长度 ${S.authCookie.length}），http=${res.statusCode}`);
      resolve(true);
    });
    req.on('error', reject);
    req.setTimeout(8000, () => req.destroy(new Error('交换超时')));
  });
}
function genOf() { return S.gen; }

// 只读健康判断：**绝不带 token**（这条是三家用白屏换来的判据）
function aliveProbe(cb) {
  const req = http.get(`${S.upBase || `http://${CFG.upHost}:${CFG.upPort}/`}`,
    { headers: { cookie: S.authCookie || '' }, agent: false }, (res) => { res.resume(); cb(null, res.statusCode); });
  req.on('error', (e) => cb(e));
  req.setTimeout(4000, () => req.destroy(new Error('probe timeout')));
}

// ── 入口服务 ────────────────────────────────────────────────────────────────
function timingSafeEq(a, b) {
  const ba = Buffer.from(String(a)), bb = Buffer.from(String(b));
  return ba.length === bb.length && crypto.timingSafeEqual(ba, bb);
}
function readCookie(header, name) {
  for (const part of String(header || '').split(';')) {
    const t = part.trim();
    if (t.startsWith(name + '=')) return t.slice(name.length + 1);
  }
  return '';
}
function hostAllowed(hostHdr) {
  const h = String(hostHdr || '');
  return h === `127.0.0.1:${CFG.entryPort}` || h === `localhost:${CFG.entryPort}`;
}
/** 把一条绝对 URL 里的 `scheme://authority` 换成 `http://<新 authority>`，路径与 query 原样留着。 */
function swapAuthority(absUrl, newAuth) {
  const m = /^(https?:)\/\/[^/]+/i.exec(String(absUrl));
  if (!m) return String(absUrl);                       // 不是绝对 URL（相对 Referer 也会这样）：原样交出去
  return 'http://' + newAuth + String(absUrl).slice(m[0].length);
}
function authorized(req) {
  return !!CFG.key && timingSafeEq(readCookie(req.headers.cookie, 'dsh-entry'), CFG.key);
}

// 口令从盘上的文件读，绝不从 argv 传（他自己的红线：密钥不上命令行；/root/.dsh 是 700，只有 root 读得到）。
// DSH_ENTRY_KEY 那条环境变量留着，只给临时试验用。
function resolveKey() {
  if (CFG.key) return CFG.key;
  try {
    const k = fs.readFileSync(CFG.keyFile, 'utf8').trim();
    if (k) return k;
    log(`口令文件在但空的：${CFG.keyFile}`);
  } catch (e) {
    if (e.code !== 'ENOENT') log(`读口令文件失败：${e.code || e.message}`);
  }
  return '';
}

let compatCache = { file: '', mtime: 0, src: '' };
function compatSource() {
  try {
    const st = fs.statSync(CFG.compat);
    if (compatCache.file !== CFG.compat || +st.mtime !== compatCache.mtime) {
      compatCache = { file: CFG.compat, mtime: +st.mtime, src: fs.readFileSync(CFG.compat, 'utf8') };
      log(`兼容脚本已读入 ${compatCache.src.length} B（改文件即生效，不用重启入口）`);
    }
    return compatCache.src;
  } catch (e) {
    if (e.code !== 'ENOENT') { S.n.lastErr = 'compat ' + e.message; }
    return '';
  }
}

// 把兼容脚本内联进 HTML：这是从 DSHA 抄的思路（RuntimeTools.java:700-725 在装的时候前置
// es-compat.js + startup.js 进 dist/index.html），但**我们不改盘上的文件** ——
// 上游一升级就把 polyfill 冲掉那条老遗留问题（RUNBOOK 13.1 / PROGRESS 遗留问题）在这一步整个消掉。
//
// 插在哪：取「最早的那个候选位」，不是按顺序试第一个能用的。2026-10-20 在这栽过一次 ——
// 原来的写法先试 </head>、找不到才试 module script，而 dsh 的首页把 `<script type="module">`
// 放在 <head> **里面**（本地 reference/dsh-web-frontend-index.html:825 B 那份：module 在 456、
// </head> 在 764；手机上真页面：module 38542、</head> 38850）。于是"先试 </head>"永远赢，
// polyfill 恒排在引擎第一段脚本后面：HTTP 200、页面照样打开，只有顺序是错的，肉眼看不出来。
// 现在三个候选位一起算，取最小偏移，并把实际偏移记进 /__entry_status，顺序对不对由读数说话。
// 内联之前必须做的转义。HTML 解析器在 script 数据态里**只认第一个 `</script`，它不看 JS 语法** ——
// 连 `//` 注释里出现的这三个字符都算。2026-10-20 真机就栽在这：`tools/dsh-compat.js:8` 那句注释
// 写着 `<script src="./assets/dsh-compat.js"></script>`（讲的是"这文件当年是怎么注入的"），
// 内联之后解析器在偏移 533 处就把我们这段提前关掉了，剩下 2.6 KB 变成**页面上的一段可见文字** ——
// 他截图过来，首页顶上刷了一大屏 polyfill 源码，而页面照样能用（因为被截断后那句
// `<script src="./assets/dsh-compat.js">` 反倒真的去载了盘上那份）。
// 转义成 `<\/script`：JS 字符串与正则里 `\/` 恒等于 `/`，`//` 注释里只是文本变了，语义一点不动。
// `<!--` 一起换掉是同一个理由的另一半：它会把解析器带进 "script data escaped" 态。
// 这两条替换的前提是**源码里这些串只出现在注释或字符串里**（注释里 `\X` 是纯文本、字符串里 `\!` 恒等 `!`）。
// 真要是哪天把它写进裸代码位置，`<\!--` 会自己变成语法错 —— 那种错由 4d 那条判据 + 页面整段不跑暴露，
// 不靠人眼盯。盘上那份 `tools/dsh-compat.js` 保持原样不sanitize：它是这条转义路径的活体回归用例。
const COMPAT_OPEN_TAG = '<script data-dsh-entry-compat="1">';
function escapeForInline(src) {
  return src.replace(/<\/script/gi, '<\\/script').replace(/<!--/g, '<\\!--');
}

function injectHtml(html) {
  const src = escapeForInline(compatSource());
  if (!src) { S.n.injectMiss += 1; return html; }
  const tag = `${COMPAT_OPEN_TAG}\n${src}\n</script>`;
  const firstScript = /<script[\s>]/i.exec(html);
  const firstScriptAt = firstScript ? firstScript.index : -1;
  const cands = [];
  const headOpen = /<head[^>]*>/i.exec(html);
  if (headOpen) cands.push(['<head> 开标签之后', headOpen.index + headOpen[0].length]);
  if (firstScript) cands.push(['第一段 script 之前', firstScript.index]);
  const headClose = /<\/head>/i.exec(html);
  if (headClose) cands.push(['</head> 之前', headClose.index]);
  if (!cands.length) {
    S.n.injectMiss += 1;
    S.inj = { at: -1, anchor: '', firstScriptAt, order: 'no-anchor' };
    S.n.lastErr = 'COMPAT_ANCHOR_MISSING：HTML 里既没有 <head> 也没有 script 也没有 </head>';
    return html;
  }
  cands.sort((a, b) => a[1] - b[1]);
  const anchor = cands[0];
  S.n.injected += 1;
  const out = html.slice(0, anchor[1]) + tag + '\n' + html.slice(anchor[1]);
  // 顺序与"完整性"分开判：顺序只看我们插在哪；完整性看**解析器实际在哪里关掉这个元素** ——
  // 从开标签往后第一个 `</script` 必须正好是我们自己那一个。tag 的形状是
  //   开标签 + "\n" + src + "\n" + 闭标签
  // 所以真闭标签的起点 = 开标签之后第 1 个字符 + src 长度 + 那个换行，即 openEnd + src.length + 2。
  // 只报顺序不报完整性，就是这次 46/46 全绿却把源码刷到屏幕上那一格的成因。
  const openEnd = anchor[1] + COMPAT_OPEN_TAG.length;
  const closeAt = /<\/script/i.exec(out.slice(openEnd));
  const wantCloseAt = openEnd + src.length + 2;
  S.inj = {
    at: anchor[1], anchor: anchor[0], firstScriptAt,
    order: firstScriptAt < 0 || anchor[1] <= firstScriptAt ? 'ok' : 'bad',
    closed: closeAt ? 'at=' + (openEnd + closeAt.index) + (openEnd + closeAt.index === wantCloseAt ? ' 完整' : ' 提前关闭') : '无',
    whole: closeAt && openEnd + closeAt.index === wantCloseAt ? 'ok' : 'bad',
  };
  if (S.inj.whole !== 'ok') {
    S.n.lastErr = 'COMPAT_INLINE_TRUNCATED：内联段在 ' + (closeAt ? openEnd + closeAt.index : '无') +
      ' 处被 </script 截断（应在 ' + wantCloseAt + '）—— 兼容脚本里有没转义的 </script 或 <!--';
  }
  return out;
}

function proxyRequest(req, res, bodyOverride) {
  if (!S.upBase) {
    res.writeHead(503, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
    return res.end('入口还没从引擎的启动行里认到上游地址。引擎刚重启？稍等两秒再刷新。\n');
  }
  const u = new URL(req.url, S.upBase);
  const startedAt = Date.now();
  // 流水里的耗时到**上游回头**为止，所以一条 40 s 的请求有两种完全不同的成因，光看总耗时分不开：
  // ① 客户端把请求体送得很慢（WebView 在后台/锁屏时被冻结节流）；② 引擎真的想了 40 s（冷启、或等出网）。
  // 于是这里再记一次"**请求体收完**"的时刻：体 ≈ 总 ⇒ 卡在他那一侧；体 ≈ 0 而总很大 ⇒ 卡在引擎那一侧。
  // 只加监听、不碰数据流（pipe 照常），读不到就显示"未收完"，不假装量到了。
  let bodyAt = 0;
  req.on('end', () => { if (!bodyAt) bodyAt = Date.now(); });
  const headers = Object.assign({}, req.headers);
  headers.host = `${CFG.upHost}:${new URL(S.upBase).port}`;
  // Origin 必须跟着 Host 一起换，否则**引擎会把每一发带 Origin 的请求判成跨源并回 403**。
  // 栅栏在 @deepseek-ai/dsh-client-connection/lib/index.js：isTrustedApiRequest() 先放 Host 过
  // （回环就够），再看 Origin —— 有的话必须 isSameAuthorityOrigin(origin, host)，也就是
  // Origin 的 host:port 要**逐字等于 Host 头**。2026-10-20 在裸引擎 :3080 上差分实测：
  //   Origin: http://127.0.0.1:3081 → 403   /   Origin: http://127.0.0.1:3080 → 401   /   不带 → 401
  // 差别只有 Origin。导航请求不带 Origin ⇒ 首页能开；fetch/XHR 带 ⇒ 页面里一按到真接口就红。
  // 他手机上"选工作区目录 ⇒ HTTP 403"就是这个，跟模型 API、跟有没有配 key 无关。
  // Referer 一起改：不改会留着 :3081 这个我们自己的地址，日志与前端自述里看着像"还在打另一个端口"。
  if (headers.origin) headers.origin = `http://${headers.host}`;
  if (headers.referer) headers.referer = swapAuthority(headers.referer, headers.host);
  const ours = readCookie(headers.cookie, 'dsh-entry');
  const restCookies = (headers.cookie || '').split(';').map((s) => s.trim())
    .filter((s) => s && !s.startsWith('dsh-entry=')).join('; ');
  const merged = [restCookies, S.authCookie].filter(Boolean).join('; ');
  if (merged) headers.cookie = merged; else delete headers.cookie;
  delete headers['content-length']; // 下面按实际字节重发
  // 要改字节的那一类请求，别向上游要压缩：WebView 默认带 Accept-Encoding: gzip，上游一 gzip
  // 我们就走不进 HTML 注入分支（isHtml 只看 identity），结果是"页面照常打开、polyfill 没进去"，
  // 而且 injected / injectMiss 两个计数都不动 —— 2026-10-20 就是这么漏过去的，靠"最近请求"那行
  // 看见 App 只要了 /assets/*.css|js、一条 HTML 都没进来才发现。
  // 只对无扩展名（=文档）和 .html 生效，静态资源继续吃上游的 gzip，体积不受影响（本机回环，40 KB 无所谓）。
  if (req.method === 'GET' && (/\.(html?|xhtml)$/i.test(u.pathname) || !/\.[A-Za-z0-9]+$/.test(u.pathname))) {
    delete headers['accept-encoding'];
  }

  const up = http.request({ hostname: CFG.upHost, port: headers.host.split(':')[1], path: u.pathname + u.search,
    method: req.method, headers, agent: false }, (upRes) => {
    const ct = String(upRes.headers['content-type'] || '');
    // 「谁在跟我说话」这一行是给手机锁屏、截不了图那种时刻留的：curl 探针和 App 的 WebView
    // 一眼就能分开（WebView 的 UA 里带 wv），页面打不开时先看这行有没有动过。
    S.lastReq = `${req.method} ${u.pathname} → ${upRes.statusCode} ua=${String(req.headers['user-agent'] || '-').slice(0, 64)}`;
    // 全量请求流水（不只 4xx）：他报的两件事里"点了插件没反应"根本不会出现 4xx —— 页面可能压根没发请求，
    // 也可能发了个 200 但前端自己没跳转。只留非 2xx 那一条清单，这一类问题就只能靠猜。
    // 记路径不记 query（query 里可能带一次性 token），UA 归成 WebView/curl 两类就够分开手机与探针。
    const uaCls = /wv|Android|Mobile/i.test(String(req.headers['user-agent'] || '')) ? 'App' : '探针';
    const bodyMs = bodyAt ? `${bodyAt - startedAt}ms` : '未收完';
    S.seen.unshift(`${req.method} ${u.pathname} → ${upRes.statusCode} ${Date.now() - startedAt}ms ${uaCls}`
      + ` 体${bodyMs}`);
    if (S.seen.length > 30) S.seen.length = 30;
    // 非 2xx 逐条留痕（只记路径，query 里可能带 token；UA 截断到够分 curl / WebView 就行）。
    // 404 只在页面类路径上记 —— 前端自己轮询 /favicon.ico 这类东西刷出来的 404 不是问题，
    // 而"点了没反应"的真凶（403 / 500 / 401）在文档与 API 路径上，一条都不许被噪音挤掉。
    // Origin 也带上（截断、且它本来就不是秘密）：2026-10-20 那句 403 的成因就是"Origin 带着 :3081
    // 进了要求 Origin==Host 的栅栏"，而体检探针也会造 4xx —— 没有这一列就分不开"他手机上真红的那条"
    // 和"我自己探针打出来的那条"，那台机器上就只能靠猜。
    const st = upRes.statusCode;
    const docish = u.pathname === '/' || /\.(html?|xhtml)$/i.test(u.pathname) || !/\.[A-Za-z0-9]+$/.test(u.pathname);
    if (st >= 400 && (st !== 404 || docish)) {
      S.bad.unshift(`${req.method} ${u.pathname} → ${st} ua=${String(req.headers['user-agent'] || '-').slice(0, 24)}`
        + ` origin=${String(req.headers.origin || '-').slice(0, 40)}`);
      if (S.bad.length > 12) S.bad.length = 12;
    }
    const enc = String(upRes.headers['content-encoding'] || 'identity');
    const isHtml = /text\/html/i.test(ct) && (enc === 'identity' || !upRes.headers['content-encoding']);
    if (req.method === 'GET' && isHtml) {
      const chunks = [];
      upRes.on('data', (d) => chunks.push(d));
      upRes.on('end', () => {
        let body = injectHtml(Buffer.concat(chunks).toString('utf8'));
        const injectedHere = body.indexOf('data-dsh-entry-compat') >= 0;
        body = Buffer.from(body, 'utf8');
        const h = Object.assign({}, upRes.headers);
        h['content-length'] = body.length;
        delete h['transfer-encoding']; delete h.etag; delete h['content-encoding'];
        if (injectedHere) {
          // 改过字节就不许任何一侧留缓存。实测踩过：入口重启后 App 直接吃 WebView 里缓存的旧首页
          // （里面是上一版 polyfill），于是"改兼容脚本不用重启入口"这句话在出口成立、在客户端不成立。
          h['cache-control'] = 'no-store';
          delete h.expires; delete h['last-modified'];
        }
        if (upRes.statusCode === 401) { onUpstream401(); }
        res.writeHead(upRes.statusCode, h);
        res.end(body);
      });
      upRes.on('error', (e) => { S.n.lastErr = 'html ' + e.message; res.destroy(); });
      return;
    }
    if (upRes.statusCode === 401) onUpstream401();
    res.writeHead(upRes.statusCode, upRes.headers);   // SSE / 分块原样管通，不缓冲
    upRes.pipe(res);
    upRes.on('error', () => res.destroy());
  });
  up.on('error', (e) => {
    S.n.lastErr = 'upstream ' + e.message;
    log(`上游打不开（${e.code || e.message}）：引擎没在跑？`);
    S.seen.unshift(`${req.method} ${u.pathname} → 502 连不上上游 ${Date.now() - startedAt}ms`);
    if (S.seen.length > 30) S.seen.length = 30;
    if (!res.headersSent) {
      res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
      res.end(`上游连不上：${redact(e.message)}\n看得到这句话就说明入口活着；跑 node dsh-entry.js --status 看引擎状态。\n`);
    } else res.destroy();
  });
  if (bodyOverride !== undefined && bodyOverride !== null) return up.end(bodyOverride);
  req.pipe(up);
}

// 上游回 401 ⇒ 我们手上那份 cookie 过期了（多半是引擎换代）。有 token 就重换，没有就等下一行。
function onUpstream401() {
  S.n.upstream401 += 1;
  if (S.pendingTokenUrl) {
    S.n.reauth += 1;
    exchange().catch((e) => { S.n.lastErr = 'reauth ' + e.message; log('重换 cookie 失败：' + e.message); });
    return;
  }
  if (!S.restartTimer && !S.stopping) {
    log('401 且手上没有可用 token ⇒ 判定引擎已换代，重拉一次');
    startEngine();
  }
}

function makeServer() {
  return http.createServer((req, res) => {
    S.n.req += 1;
    if (!hostAllowed(req.headers.host) || !authorized(req)) {
      S.n.denied += 1;
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      return res.end('Not Found\n');          // 不给"存在但要凭据"这种提示
    }
    if (req.url.split('?')[0] === '/__entry_status') {
      res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
      return res.end(statusText());
    }
    proxyRequest(req, res);
  });
}

// WebSocket / 其它 upgrade：把原始请求行 + 头重发一遍，注入我们的 cookie，然后双向裸管道。
// Soodok 那份 dsh-lan-proxy.js:84-118 之所以列了一堆改写项，就是这段没做干净会踩的坑。
function attachUpgrade(server) {
  server.on('upgrade', (req, client, head) => {
    if (!hostAllowed(req.headers.host) || !authorized(req)) return client.destroy();
    if (!S.upBase) return client.destroy();
    const port = new URL(S.upBase).port;
    // handedOver = 上游已经回过至少一个字节（那条 101 响应）。**握手**超时只在它为 false 的那段窗口里有效。
    let handedOver = false;
    const up = net.connect(+port, CFG.upHost, () => {
      const headers = Object.assign({}, req.headers);
      headers.host = `${CFG.upHost}:${port}`;
      // 升级请求同样过那道 Origin 栅栏（dsh-api-gateway 里 rejectRemoteStreamUpgrade(socket, 403|401)
      // 就是它），所以隧道里也得把 Origin 换成上游的 authority，否则工作区目录选择这类走流的接口
      // 在 App 里永远 403。
      if (headers.origin) headers.origin = `http://${headers.host}`;
      if (headers.referer) headers.referer = swapAuthority(headers.referer, headers.host);
      const rest = (headers.cookie || '').split(';').map((s) => s.trim())
        .filter((s) => s && !s.startsWith('dsh-entry=')).join('; ');
      headers.cookie = [rest, S.authCookie].filter(Boolean).join('; ');
      const lines = [`${req.method} ${req.url} HTTP/1.1`];
      for (const [k, v] of Object.entries(headers)) {
        if (Array.isArray(v)) v.forEach((x) => lines.push(`${k}: ${x}`));
        else if (v !== undefined) lines.push(`${k}: ${v}`);
      }
      up.write(lines.join('\r\n') + '\r\n\r\n');
      if (head && head.length) up.write(head);
      S.n.ws += 1;
      client.on('data', (d) => up.write(d));
      up.on('data', (d) => {
        if (!handedOver) { handedOver = true; up.setTimeout(0); }   // 101 一到就把计时器摘掉
        client.write(d);
      });
    });
    // 收与错都挂在**外层**（connect 回调之外）：TCP 自己连不上时 'error' 在 connect 回调之前就来了，
    // 那一版里这两行写在回调里面 ⇒ 没人接 = unhandled 'error' = 整个入口进程被带走。
    // 这条不是推测，2026-10-20 单独复刻过形状：同样的 net.connect(1, '127.0.0.1', () => { up.on('error',…) })
    // 跑出来是 `Unhandled 'error' event / ECONNREFUSED`、exit=1；把 handler 挪到外层之后同一发是
    // `外层接住了：ECONNREFUSED`、进程活着。症状对上就是"引擎重启的那一两秒里只要有一个 ws 在重连，
    // 整个入口跟着死，App 变成连不上"。
    const done = () => { try { client.destroy(); } catch (e) {} try { up.destroy(); } catch (e) {} };
    client.on('close', done); client.on('error', done);
    up.on('close', done); up.on('error', (e) => { S.n.lastErr = 'ws ' + e.message; done(); });
    // **握手**超时，不是空闲超时。上一版写的是 up.setTimeout(8000, ...) 且**从不解除**，
    // 而 net.Socket 的空闲计时器每收到一个字节就重新计 —— 于是任何一条 ws 隧道只要 8 秒没动静
    // 就被我们自己掐掉，lastErr 还写成"连不上上游"（2026-10-20 机上真读到 lastErr=ws upgrade 连不上上游，
    // 而那一分钟他什么都没点）。前端表现就是"过一会儿卡住、要点一下才活"。
    up.setTimeout(CFG.wsHandshakeMs, () => {
      if (handedOver) return;                     // 已经交过手了 ⇒ 这件事不归超时管
      up.destroy(new Error(`upgrade 握手 ${CFG.wsHandshakeMs}ms 没等到上游首字节（连不上、或上游没回 101）`));
    });
  });
}

// ── 命令 ─────────────────────────────────────────────────────────────────────
function doStart() {
  CFG.key = resolveKey();
  if (!CFG.key) { console.error('口令拿不到（DSH_ENTRY_KEY 没给，' + CFG.keyFile + ' 也读不到）⇒ 拒绝启动：没有口令的入口等于把 root 会话敞开给本机所有 App'); process.exit(2); }
  // 显式 --start 就是"我要它在跑"：把上一次 --stop 留的哨兵清掉，否则引擎永远拉不起来
  // （这个坑是写 --entry-stop 时想到的：哨兵不清，第二次 --start 只起代理不起引擎，症状是 503 屏）
  if (fs.existsSync(CFG.stopped)) { try { fs.unlinkSync(CFG.stopped); log('清掉了上次的停止哨兵'); } catch (e) { log('清哨兵失败：' + (e.code || e.message)); } }
  fs.writeFileSync(CFG.pid, String(process.pid) + '\n');           // pid 先落地再 exec/spawn（DSHA 同纪律）
  const server = makeServer();
  attachUpgrade(server);
  server.listen(CFG.entryPort, CFG.entryHost, () => {
    log(`入口在听 http://${CFG.entryHost}:${CFG.entryPort}，上游期望 :${CFG.upPort}，兼容脚本 ${CFG.compat}`);
    startEngine();
  });
  server.on('error', (e) => { S.n.lastErr = 'listen ' + e.message; log('监听失败：' + e.message + '（端口被占？已有一个入口在跑？）'); });
  process.on('SIGTERM', () => graceful('SIGTERM'));
  process.on('SIGINT', () => graceful('SIGINT'));
  // 周期性体检：只在"本该有凭据却没了"时补一次重拉；探测永远不带 token
  setInterval(() => {
    if (!S.engine || S.engine.killed) return;
    aliveProbe((err, code) => {
      if (err) { log('存活探测失败：' + err.message); return; }
      if (code === 401 && !S.pendingTokenUrl) onUpstream401();
    });
  }, 30000).unref();
}
function graceful(sig) { log(`收到 ${sig} ⇒ 关入口与引擎`); S.stopping = true; stopEngine(); process.exit(0); }
function stopEngine() {
  if (S.restartTimer) clearTimeout(S.restartTimer);
  if (S.engine && !S.engine.killed) { try { S.engine.kill('SIGTERM'); } catch (e) {} }
}
function doStop() {
  fs.writeFileSync(CFG.stopped, 'stop\n');                          // 哨兵：看门狗/重拉看见就退（DSHA .dsha-stopped 同思路）
  let pid = 0;
  try { pid = +fs.readFileSync(CFG.pid, 'utf8').trim(); } catch (e) {}
  if (pid) { try { process.kill(pid, 'SIGTERM'); log(`已给入口 pid=${pid} 发 SIGTERM`); } catch (e) { log(`kill ${pid}：${e.code}`); } }
  let epid = 0;
  try { epid = +fs.readFileSync('/root/.dsh/web.pid', 'utf8').trim(); } catch (e) {}
  if (epid) { try { process.kill(epid, 'SIGTERM'); log(`已给引擎 pid=${epid} 发 SIGTERM`); } catch (e) {} }
}
function doStatus() {
  CFG.key = resolveKey();
  const server = http.get({ host: CFG.entryHost, port: CFG.entryPort, path: '/__entry_status',
    headers: { host: `127.0.0.1:${CFG.entryPort}`, cookie: `dsh-entry=${CFG.key}` },
    agent: false }, (res) => {
    let b = ''; res.on('data', (d) => b += d);
    res.on('end', () => { process.stdout.write(`http=${res.statusCode}\n${res.statusCode === 200 ? b : '(拿不到状态：口令不对或入口没在跑)'}\n`); process.exit(res.statusCode === 200 ? 0 : 1); });
  });
  server.on('error', (e) => { console.log(`入口没在听（${e.code || e.message}）⇒ 未运行`); process.exit(1); });
}

// ── 自测：假上游把上面每条判据打一遍（不需要引擎、不需要手机、不需要网络）─────────
function doSelftest() {
  const out = [];
  const P = (name, ok, detail) => { const l = `${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`; out.push(l); process.stderr.write(l + '\n'); return ok; };
  process.on('unhandledRejection', (e) => { process.stderr.write('!! 未处理的 reject：' + (e && e.stack || e) + '\n'); process.exit(3); });
  CFG.key = 'test-key-123';
  // 自测不碰真机的路径：日志/pid/哨兵/兼容脚本全指到一个临时目录，别在盘上建 /root/.dsh。
  // 目录带 pid：两个自测并发跑时共用一个 entry-compat.js 会互相删（实测其中一边 unhandledRejection、exit=3）。
  const st = path.join(require('os').tmpdir(), 'dsh-entry-selftest-' + process.pid);
  fs.mkdirSync(st, { recursive: true, mode: 0o700 });
  CFG.log = path.join(st, 'entry.log'); CFG.pid = path.join(st, 'entry.pid'); CFG.stopped = path.join(st, 'entry-stopped');
  CFG.keyFile = path.join(st, 'entry.key');
  const wsSeen = [];
  // 形状照抄手机上的真页面（= 本地 reference/dsh-web-frontend-index.html）：
  // `<script type="module">` 在 <head> **里面**、在 </head> 之前。
  // 原来这里给的是"module 在 body 里"的假页面，所以"注入排在 module 之前"那条判据在旧代码下也能 PASS ——
  // 而真页面上它是错的。合成用例必须长得像真产物，不然自测等于没测（borrowable ④）。
  const FAKE_PAGE = '<!doctype html>\n<html lang="en">\n  <head>\n    <meta charset="utf-8" />\n' +
    '    <link rel="icon" type="image/svg+xml" href="./favicon.svg" />\n' +
    '    <script type="module" src="./assets/index.js"></script>\n' +
    '    <title>DeepSeek Harness</title>\n  </head>\n  <body>\n    <div id="root"></div>\n  </body>\n</html>\n';
  const fake = http.createServer((req, res) => {
    const hasAuth = /dsh-auth-/.test(req.headers.cookie || '');
    if (req.url.startsWith('/__give401')) { res.writeHead(401); return res.end('no'); }
    if (req.url.includes('token=good')) {
      res.writeHead(200, { 'set-cookie': 'dsh-auth-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaAAA=v1.x.y; Path=/; Max-Age=2592000' });
      return res.end('ok');
    }
    if (req.url.startsWith('/__origin-echo')) {
      res.writeHead(200, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ origin: req.headers.origin || null, host: req.headers.host || null,
        referer: req.headers.referer || null }));
    }
    if (!hasAuth) { res.writeHead(401, { 'content-type': 'text/plain' }); return res.end('dsh web authentication required'); }
    // 未知 API 回 403 —— 他手机上"选工作区目录 ⇒ 一句 HTTP 403"就是这个形状。假上游不模拟这一档，
    // 4e 那条"非 2xx 要留痕"的判据就没东西可记，等于白写。（放在 gzip 分支之前：403 不该被 200 覆盖）
    if (/^\/api\//.test(req.url)) {
      res.writeHead(403, { 'content-type': 'application/json' });
      return res.end('{"error":{"code":"forbidden","message":"HTTP 403"}}');
    }
    if (/^\/sse/.test(req.url)) {
      res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store' });
      res.write('data: one\n\n');
      setTimeout(() => { res.write('data: two\n\n'); res.end(); }, 60);
      return;
    }
    if (/^\/ws/.test(req.url)) { /* upgrade 走 net，这里只挡普通 GET */ }
    // 上游会按 Accept-Encoding 压。App 的 WebView 默认就带 gzip —— 这正是"注入静默失效"那条坑的成因，
    // 所以假上游必须真压一次，不然自测测不到（2026-10-20：手机上 App 只要走了 /assets/*，一条 HTML 都没进来）。
    if (/gzip/.test(String(req.headers['accept-encoding'] || ''))) {
      const z = zlib.gzipSync(Buffer.from(FAKE_PAGE, 'utf8'));
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', etag: '"x"',
        'content-encoding': 'gzip', 'content-length': z.length });
      return res.end(z);
    }
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', etag: '"x"' });
    res.end(FAKE_PAGE);
  });
  // 假上游也接 upgrade：回 101 并把收到的 cookie 原样塞进响应头，好让自测能读出"隧道里到底带了什么"
  fake.on('upgrade', (req, sock) => {
    if (/^\/ws-stall/.test(req.url)) return;   // 故意永远不回 101：喂给"握手超时"那条判据
    wsSeen.push(req.headers.cookie || '');
    sock.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
      `X-WS-Cookie: ${req.headers.cookie || '(none)'}\r\nX-WS-Path: ${req.url}\r\n` +
      `X-WS-Origin: ${req.headers.origin || '(none)'}\r\nX-WS-Referer: ${req.headers.referer || '(none)'}\r\n\r\nWS-BYTES-BACK`);
    sock.on('data', (d) => { try { sock.write('ECHO:' + d.toString('utf8')); } catch (e) {} });
  });
  const compatFile = path.join(st, 'entry-compat.js');
  // 自测一开头就把 CFG.compat 换成临时目录里的替身，于是"真首页 × 盘上真兼容脚本"这一双从没被同一条
  // 判据跑过 —— 46/46 全绿却刷了一屏源码那一格就是这么漏的：替身里没有 </script>，真文件里有。
  // 把换掉之前的路径留住，4c+ 用它跑生产那一双（Windows 上配合 DSH_ENTRY_COMPAT=tools/dsh-compat.js，
  // 手机上就是 /root/.dsh/entry-compat.js 本身）。
  const PROD_COMPAT = CFG.compat;
  fs.writeFileSync(compatFile, 'globalThis.__COMPAT_RAN__=1;');
  CFG.compat = compatFile;

  const get = (p, opts = {}) => new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port: CFG.entryPort, path: p,
      headers: Object.assign({ host: `127.0.0.1:${CFG.entryPort}`, cookie: `dsh-entry=${CFG.key}` }, opts.headers || {}),
      method: opts.method || 'GET', agent: false }, (res) => {
      let b = ''; res.on('data', (d) => b += d); res.on('end', () => resolve({ code: res.statusCode, body: b, headers: res.headers }));
    });
    req.on('error', reject); req.end(opts.body);
  });

  fake.listen(0, '127.0.0.1', async () => {
    const upPort = fake.address().port;
    CFG.upPort = upPort;
    const server = makeServer(); attachUpgrade(server);
    // 端口交给系统挑：自测要是钉死 3081，在真机上跑就会撞上正在服务的入口（EADDRINUSE 之后整个自测挂住）
    server.listen(0, '127.0.0.1', async () => {
      CFG.entryPort = server.address().port;      // hostAllowed / get / rawUpgrade 都读这个值，改在请求之前
      let fails = 0;
      const R = (n, ok, d) => { if (!P(n, ok, d)) fails++; };
      // 挂住也要交卷：40 秒没跑完就把已有判据打出来（上一版就因为一条请求不返回而静默卡死，什么读数都没有）
      setTimeout(() => {
        console.log(`\n===== dsh-entry 自测（40 s 看门狗：跑到这里还没结束，下面是已完成的部分）=====`);
        out.forEach((l) => console.log(l));
        console.log(`已完成 ${out.length} 条，卡在“${out[out.length - 1] || '第一条之前'}”之后`);
        process.exit(4);
      }, 40000).unref();
      R('自测用的是系统给的端口，不撞正在服务的入口', CFG.entryPort > 0 && CFG.entryPort !== 3081,
        `本次 =${CFG.entryPort}（配置的默认位是 3081）`);

      // 1) 判据形状：官方启动行 → 认出端口 → 换到 cookie
      handleEngineLine(S.gen + 1, 'noise');
      S.gen += 1;
      R('半行/杂行不认', !S.pendingTokenUrl);
      // 差一位都不算（DSHA 的判据是 {43}，掺进别的不定长 token 形状也算不认）
      handleEngineLine(S.gen, `dsh web: http://127.0.0.1:${upPort}/?token=good${'A'.repeat(38)}`);
      R('token 只有 42 位 ⇒ 不认', !S.pendingTokenUrl && !S.upBase);
      handleEngineLine(S.gen, `dsh web: http://127.0.0.1:${upPort}/?token=good${'A'.repeat(39)}`);
      R('43 位才算认到启动行', S.pendingTokenUrl.length > 0);
      R('端口取自那行**报的**值，不按配置猜', S.upBase === `http://127.0.0.1:${upPort}/`, `upBase=${S.upBase}`);
      await new Promise((r) => setTimeout(r, 250));
      R('token 换成 dsh-auth cookie', !!S.authCookie, S.authCookie.slice(0, 16) + '…');
      R('token 不留在结构里', S.pendingTokenUrl === '');

      // 2) 口令与 Host 两道闸
      R('无口令 404', (await get('/__entry_status', { headers: { cookie: '' } })).code === 404);
      R('错口令 404', (await get('/__entry_status', { headers: { cookie: 'dsh-entry=nope' } })).code === 404);
      R('状态页要口令', (await get('/__entry_status')).code === 200);
      R('Host 不对 404', (await get('/', { headers: { host: 'evil.example' } })).code === 404);

      // 3) 转发：给上游带上我们换到的 cookie；我们自己的口令不外泄
      const page = await get('/');
      R('页面 200（上游认我们的 cookie）', page.code === 200, `http=${page.code}`);
      R('入口口令不透给上游', page.code === 200);
      const seen = [];
      const old = fake.listeners('request');
      fake.removeAllListeners('request');
      fake.on('request', (req, res) => { seen.push(req.headers.cookie || ''); old[0](req, res); });
      await get('/');
      R('上游收到的 cookie 里有 dsh-auth、没有 dsh-entry',
        /dsh-auth-/.test(seen[0] || '') && !/dsh-entry=/.test(seen[0] || ''), redact(seen[0] || ''));
      fake.removeAllListeners('request'); fake.on('request', old[0]);

      // 4) 兼容层：内联注入，且不改上游字节以外的东西
      R('兼容脚本已内联进 HTML', /__COMPAT_RAN__/.test(page.body));
      R('注入发生在 module script 之前',
        page.body.indexOf('__COMPAT_RAN__') < page.body.indexOf('type="module"'));
      R('注入后 content-length 重算且 etag 撤掉',
        String(page.headers['content-length']) === String(Buffer.byteLength(page.body)) && !page.headers.etag,
        `len=${page.headers['content-length']} 实长=${Buffer.byteLength(page.body)}`);
      R('注入过的 HTML 带 no-store（不让客户端缓存我们改过的字节）',
        /no-store/.test(String(page.headers['cache-control'] || '')),
        `cache-control=${page.headers['cache-control']} expires=${page.headers.expires}`);
      const injBefore = S.n.injected;
      fs.writeFileSync(CFG.compat, 'globalThis.__COMPAT_RAN2__=1;');
      const page2 = await get('/');
      R('换兼容脚本不用重启入口（按 mtime 重读）', /__COMPAT_RAN2__/.test(page2.body));
      R('一次 HTML 响应只记一次注入', S.n.injected === injBefore + 1,
        `injected ${injBefore} → ${S.n.injected}（只数真注入成功的，锚点没找到不算）`);
      R('入口自己报的顺序是 ok', S.inj.order === 'ok' && S.inj.firstScriptAt > 0 && S.inj.at <= S.inj.firstScriptAt,
        `at=${S.inj.at} anchor=${S.inj.anchor} firstScript=${S.inj.firstScriptAt} order=${S.inj.order}`);
      R('/__entry_status 里能读到内联位置', /内联位置.*order=ok/.test((await get('/__entry_status')).body));
      await get('/', { headers: { 'user-agent': 'Mozilla/5.0 (Linux; Android 15) wv Chrome/126.0 Mobile Safari/537.36' } });
      R('最近请求那行分得出是 curl 还是 WebView（带方法、路径、状态码、UA）',
        /^GET \/ → 200 ua=.*wv/.test(S.lastReq), S.lastReq);

      // 4e) 压缩这条：文档请求要剥掉 Accept-Encoding，静态资源不剥。
      //     不剥的后果实测过 —— 上游回 gzip ⇒ isHtml 判假 ⇒ 注入静默失效，而且 injected/injectMiss
      //     两个计数一个都不动，从状态页上完全看不出来（只能靠"最近请求里没有 HTML"这种间接读数抓到）。
      {
        const ae = [];
        const oldH = fake.listeners('request');
        fake.removeAllListeners('request');
        fake.on('request', (rq, rs) => { ae.push(rq.url + '=' + (rq.headers['accept-encoding'] || '(没带)')); oldH[0](rq, rs); });
        const doc = await get('/', { headers: { 'accept-encoding': 'gzip, deflate, br' } });
        const asset = await get('/assets/index.js', { headers: { 'accept-encoding': 'gzip, deflate, br' } });
        R('带 gzip 的文档请求：上游侧收到的是未压的 HTML，polyfill 照样进得去',
          /__COMPAT/.test(doc.body) && ae.some((x) => /^\/=/.test(x) && /\(没带\)$/.test(x)),
          ae.join(' | ') + `；响应 ${Buffer.byteLength(doc.body)} B`);
        R('静态资源不剥（让上游继续 gzip，别把体积撑大）',
          ae.some((x) => /^\/assets\/index\.js=.*gzip/.test(x)) && asset.code === 200,
          ae.filter((x) => x.startsWith('/assets')).join(' | '));
        fake.removeAllListeners('request'); fake.on('request', oldH[0]);
      }

      // 4b) 锚点退化链（直接喂形状不一的页面，不依赖假上游）：
      //     没有 <head> 要退到"第一段 script 之前"；一个锚点都没有就原样返回并记 injectMiss。
      {
        const savedInj = S.n.injected, savedMiss = S.n.injectMiss, savedState = S.inj;
        const noHead = '<!doctype html><body><script src="./x.js"></script></body>';
        const r1 = injectHtml(noHead);
        R('没有 <head> 时退到第一段 script 之前',
          S.inj.at === noHead.indexOf('<script') && S.inj.order === 'ok' && r1.indexOf('<script data-dsh-entry-compat') === S.inj.at,
          `插在了 ${S.inj.at}（第一段 script 在 ${S.inj.firstScriptAt}），anchor=${S.inj.anchor}`);
        const bare = '这段没有 HTML 标签';
        R('一个锚点都没有 ⇒ 原样返回并记 injectMiss',
          injectHtml(bare) === bare && S.n.injectMiss === savedMiss + 1);
        S.n.injected = savedInj; S.n.injectMiss = savedMiss; S.inj = savedState;
      }

      // 4c) 真产物：DSH_ENTRY_TEST_PAGE 指到一个真首页文件（本机 dist/index.html 的副本）就顺手验一遍。
      //     合成页面形状对不上真页面这件事，上面 4 条判据已经吃过一次亏，这里把"照真文件验"变成常规动作。
      const realPage = process.env.DSH_ENTRY_TEST_PAGE || '';
      if (realPage) {
        if (fs.existsSync(realPage)) {
          const savedInj2 = S.n.injected, savedState2 = S.inj;
          const html = fs.readFileSync(realPage, 'utf8');
          const withTag = injectHtml(html);
          R('真首页注入后仍排在第一段脚本之前',
            S.inj.order === 'ok',
            `${path.basename(realPage)} ${Buffer.byteLength(html)} B：at=${S.inj.at} firstScript=${S.inj.firstScriptAt} anchor=${S.inj.anchor}`);
          R('真首页注入是纯插入（把 tag 摘掉撞回原字节）',
            withTag.replace(/<script data-dsh-entry-compat="1">\n[\s\S]*?\n<\/script>\n/, '') === html,
            `原 ${Buffer.byteLength(html)} B → 注入后 ${Buffer.byteLength(withTag)} B`);
          S.n.injected = savedInj2; S.inj = savedState2;
        } else {
          R('真首页注入后仍排在第一段脚本之前', false, `DSH_ENTRY_TEST_PAGE 指的文件不在：${realPage}`);
        }
      }

      // 4c+) 生产那一双：真首页 × 盘上真兼容脚本。上面 4c 用的是自测替身（几十 B、且不含 </script），
      //      所以"注入后只涨了 75 B"这种读数当时看着正常 —— 真产物是 876 B 首页 × 3,123 B 脚本，
      //      这一次把两个真的合在一起验：元素完整、纯插入、转义后仍然是一段能编译的 JS。
      if (realPage && PROD_COMPAT && fs.existsSync(PROD_COMPAT) && path.resolve(PROD_COMPAT) !== path.resolve(compatFile)) {
        const savedInj3 = S.n.injected, savedState3 = S.inj, savedErr3 = S.n.lastErr, savedPath = CFG.compat;
        CFG.compat = PROD_COMPAT;                       // compatSource() 按 file+mtime 认缓存，换路径自动重读
        const html = fs.readFileSync(realPage, 'utf8');
        const srcReal = escapeForInline(compatSource());
        const out = injectHtml(html);
        const tagLen = COMPAT_OPEN_TAG.length + 1 + srcReal.length + 1 + '</script>'.length;   // 字符数：切片用
        const tagBytes = Buffer.byteLength(`${COMPAT_OPEN_TAG}\n${srcReal}\n</script>\n`);      // 字节数：报数用
        const rawReal = fs.readFileSync(PROD_COMPAT, 'utf8');
        R('生产那双：真首页 × 真兼容脚本，内联元素完整且排在首段脚本之前',
          S.inj.whole === 'ok' && S.inj.order === 'ok' && !/COMPAT_INLINE_TRUNCATED/.test(S.n.lastErr || ''),
          `${path.basename(realPage)} ${Buffer.byteLength(html)} B × ${path.basename(PROD_COMPAT)} ${Buffer.byteLength(rawReal)} B → 内联后 ${Buffer.byteLength(out)} B，at=${S.inj.at} firstScript=${S.inj.firstScriptAt} closed=${S.inj.closed}`);
        R('生产那双是纯插入（按位置摘掉内联段撞回原字节）',
          out.slice(0, S.inj.at) + out.slice(S.inj.at + tagLen + 1) === html,
          `涨 ${Buffer.byteLength(out) - Buffer.byteLength(html)} B（内联段整块 ${tagBytes} B，含尾换行）`);
        R('转义后的兼容脚本仍是一段能编译的 JS',
          (() => { try { new Function(srcReal); return true; } catch (e) { S.n.lastErr = '转义把源码改坏了：' + e.message; return false; } })(),
          `转义动了 ${rawReal.split(/<\/script|<!--/i).length - 1} 处（把 </script 与 <!-- 换成 <\\/script、<\\!--），未转义 ${rawReal.length} 字符 → 转义后 ${srcReal.length} 字符，编译通过`);
        CFG.compat = savedPath; S.n.injected = savedInj3; S.inj = savedState3; S.n.lastErr = savedErr3;
      } else if (realPage) {
        R('生产那双：真首页 × 真兼容脚本，内联元素完整且排在首段脚本之前', false,
          `盘上没找到真兼容脚本，这一双没验过：PROD_COMPAT=${PROD_COMPAT || '(空)'}`);
      }

      // 4d) 内联完整性：兼容脚本里出现 `</script` 或 `<!--` 时，HTML 解析器会提前关掉我们那个元素，
      //     剩下的源码变成**页面上的一段可见文字**（2026-10-20 真机事故：tools/dsh-compat.js:8 那句
      //     注释里写着 `<script src="./assets/dsh-compat.js"></script>`，首页顶上刷了一大屏代码，
      //     而 46 条判据全绿 —— 因为旧判据只看"插在哪"，没看"解析器在哪里关掉这个元素"）。
      {
        const savedInj3 = S.n.injected, savedState3 = S.inj, savedErr = S.n.lastErr;
        fs.writeFileSync(CFG.compat,
          '// 说明里带一个闭合标签： <script src="./x.js"></script>\n' +
          '// 再带一个 HTML 注释开头： <!-- 然后呢\nglobalThis.__COMPAT_RAN3__=1;\n');
        const trap = '<!doctype html>\n<html><head>\n<script src="./a.js"></script></head><body></body></html>';
        const out3 = injectHtml(trap);
        const openEnd = S.inj.at + COMPAT_OPEN_TAG.length;
        const firstClose = /<\/script/i.exec(out3.slice(openEnd));
        R('兼容脚本里的 </script 与 <!-- 被转义，内联元素不会被提前关掉',
          S.inj.whole === 'ok' && !/COMPAT_INLINE_TRUNCATED/.test(S.n.lastErr || '') &&
            out3.includes('<\\/script>') && !out3.includes('<!--') && /__COMPAT_RAN3__/.test(out3),
          `closed=${S.inj.closed} 首个 </script 在 ${firstClose ? openEnd + firstClose.index : '无'}，应在 ${openEnd + escapeForInline(fs.readFileSync(CFG.compat, 'utf8')).length + 2}`);
        R('这条判据本身能红（把转义摘掉就复现事故）',
          (() => {
            const raw = fs.readFileSync(CFG.compat, 'utf8');
            const bad = trap.slice(0, 20) + `${COMPAT_OPEN_TAG}\n${raw}\n</script>` + trap.slice(20);
            const oe = 20 + COMPAT_OPEN_TAG.length;
            const fc = /<\/script/i.exec(bad.slice(oe));
            return !!fc && oe + fc.index < oe + raw.length + 2;   // 提前关掉 ⇒ 复现
          })());
        fs.writeFileSync(CFG.compat, 'globalThis.__COMPAT_RAN2__=1;');
        S.n.injected = savedInj3; S.inj = savedState3; S.n.lastErr = savedErr;
      }

      // 4e) 非 2xx 逐条留痕 + 全量请求流水：手机上"点了没反应"这类问题要能直接从自述页读出
      //     到底是"页面压根没发请求"还是"发了、红了"。
      {
        const savedBad = S.bad.slice(), savedSeen = S.seen.slice(), savedInj4 = S.n.injected;
        S.bad.length = 0; S.seen.length = 0;
        await get('/api/whoami');                     // 假上游对未知 API 回 403
        await get('/assets/index.js');                // 一条 200（流水里只记这一类才说明它不是 4xx 专属）
        const line = S.bad.join('\n');
        R('非 2xx 会逐条记进自述页（方法 + 路径 + 状态码）',
          /\/api\/whoami → 403/.test(line), line || '(没记上)');
        R('自述页里能读到这一串', /非 2xx/.test((await get('/__entry_status')).body));
        R('请求流水 200 也记（"点了没反应"要先分清是没请求还是请求红了）',
          S.seen.filter((r) => /→ 403/.test(r)).length >= 1 && S.seen.some((r) => /→ 200/.test(r)),
          S.seen.slice(0, 3).join(' | '));
        R('自述页里有"请求流水"这一段', /请求流水/.test((await get('/__entry_status')).body));
        R('流水里带"体Nms"（一条 40 s 的请求要能分清是客户端送得慢还是引擎想得慢）',
          S.seen.some((r) => / 体\d+ms|体未收完/.test(r)), S.seen[0] || '(流水空)');
        S.bad = savedBad; S.seen = savedSeen; S.n.injected = savedInj4;
      }

      // 4f) Origin 栅栏：引擎那侧 isSameAuthorityOrigin(origin, host) 要求 Origin 的 host:port
      //     逐字等于 Host 头，否则 403（2026-10-20 真机差分：Origin=:3081⇒403，Origin=:3080⇒401，
      //     不带⇒401）。入口换在另一个端口上，所以必须把 Origin/Referer 一起改写过去。
      {
        const fromApp = `http://127.0.0.1:${CFG.entryPort}`;
        const r = await get('/__origin-echo', { headers: {
          origin: fromApp, referer: fromApp + '/workspace/new?x=1',
          cookie: `dsh-entry=${CFG.key}`,
        } });
        let j = {}; try { j = JSON.parse(r.body); } catch (e) {}
        const upAuth = `http://${CFG.upHost}:${CFG.upPort}`;
        R('转给上游的 Origin 被换成上游 authority（不是我们这一侧的 :3081）',
          j.origin === upAuth, `上游看到的 origin=${j.origin} host=${j.host}，期望 ${upAuth}`);
        R('Referer 只换 authority，路径与 query 原样带过去',
          j.referer === upAuth + '/workspace/new?x=1', `referer=${j.referer}`);
        R('客户端没发 Origin 时不无中生有',
          JSON.parse((await get('/__origin-echo')).body).origin === null, '不带 Origin 的那一发');
      }

      // 5) SSE 不缓冲
      const t0 = Date.now();
      const sse = await get('/sse');
      R('SSE 两段都到齐且首段不等结束', /data: one/.test(sse.body) && /data: two/.test(sse.body) && sse.headers['content-type'] === 'text/event-stream',
        `${Date.now() - t0}ms`);

      // 6) upgrade 隧道：两个方向都要真验，上一版这里只写了一句 R(..., true) 的假 PASS
      const rawUpgrade = (cookieHdr, echoBack, extraHdr, p) => new Promise((resolve) => {
        let b = '', pinged = false;
        const sk = net.connect(CFG.entryPort, '127.0.0.1', () => {
          sk.write(`GET ${p || '/ws'} HTTP/1.1\r\nHost: 127.0.0.1:${CFG.entryPort}\r\nUpgrade: websocket\r\n` +
            `Connection: Upgrade\r\nSec-WebSocket-Key: abc\r\n` +
            (cookieHdr ? `cookie: ${cookieHdr}\r\n` : '') + (extraHdr || '') + `\r\n`);
        });
        const fin = (why) => { try { sk.destroy(); } catch (e) {} resolve({ text: b, why }); };
        sk.on('data', (d) => {
          b += d.toString('utf8');
          if (echoBack && !pinged && /WS-BYTES-BACK/.test(b)) { pinged = true; sk.write('PING-THROUGH-TUNNEL'); }
          if (echoBack && /ECHO:PING-THROUGH-TUNNEL/.test(b)) fin('两个方向都通');
          if (!echoBack && /WS-BYTES-BACK/.test(b)) fin('拿到上游响应');
        });
        sk.on('close', () => fin('对端断开')); sk.on('error', () => fin('报错'));
        setTimeout(() => fin('超时'), 2500);
      });
      const tun = await rawUpgrade(`dsh-entry=${CFG.key}`, true,
        `origin: http://127.0.0.1:${CFG.entryPort}\r\nreferer: http://127.0.0.1:${CFG.entryPort}/workspace/new\r\n`);
      // 上游端口只从这里取一次：写两遍就是两个真相，将来其中一处改了，这条判据会红得让人去找页面的错。
      const upAuthPort = new URL(S.upBase).port;
      R('upgrade 隧道：101 与上游回字节到得了 App 侧',
        /^HTTP\/1\.1 101/.test(tun.text) && /WS-BYTES-BACK/.test(tun.text), `结束原因=${tun.why}`);
      R('原始请求行与方法/路径原样透传', /X-WS-Path: \/ws/.test(tun.text));
      R('隧道里 Origin 也换成上游 authority（引擎那道同源栅栏，不换就 403）',
        new RegExp('X-WS-Origin: http://127\\.0\\.0\\.1:' + upAuthPort + '\\b').test(tun.text)
          && new RegExp('X-WS-Referer: http://127\\.0\\.0\\.1:' + upAuthPort + '/workspace/new\\b').test(tun.text),
        '上游看到 ' + (tun.text.match(/X-WS-(Origin|Referer): [^\r]*/g) || ['(没回显)']).join(' ｜ '));
      R('隧道里注入的是 dsh-auth、入口口令不透给上游',
        /X-WS-Cookie: [^\r]*dsh-auth-/.test(tun.text) && !/dsh-entry=/.test(tun.text),
        redact((tun.text.match(/X-WS-Cookie: [^\r]*/) || ['(无)'])[0]));
      R('App→上游方向也通（写进隧道的字节被假上游回显）', /ECHO:PING-THROUGH-TUNNEL/.test(tun.text));
      const tunNoKey = await rawUpgrade('', false);
      R('无口令的 upgrade 被掐（一个字节都拿不到）', tunNoKey.text === '',
        `收到 ${tunNoKey.text.length} B，结束原因=${tunNoKey.why}`);
      const tunBadKey = await rawUpgrade('dsh-entry=nope', false);
      R('错口令的 upgrade 同样被掐', tunBadKey.text === '',
        `收到 ${tunBadKey.text.length} B，结束原因=${tunBadKey.why}`);
      R('入口口令一次都没进过假上游', !wsSeen.some((c) => /dsh-entry=/.test(c)), `${wsSeen.length} 次 upgrade 都查过`);

      // 6b) 隧道计时器**只管握手、不管空闲**。这一组是被真机读数逼出来的：2026-10-20 他手机上
      //     自述页读到 `最后错误 ws upgrade 连不上上游`，而那一分钟他什么都没点 —— 查下来是
      //     老版把 up.setTimeout(8000, …) 挂在 socket 上且从不解除，net 的空闲计时器每来一个字节
      //     重新计时，于是任何一条安静 8 秒的长连接都被我们自己掐掉，报错文案还指着"连不上"。
      {
        const savedHs = CFG.wsHandshakeMs, savedUpBase = S.upBase;
        CFG.wsHandshakeMs = 250;                       // 把窗口缩到 250ms，判据才不用等 8 秒
        const idle = await new Promise((resolve) => {
          const sk = net.connect(CFG.entryPort, '127.0.0.1', () => {
            sk.write(`GET /ws HTTP/1.1\r\nHost: 127.0.0.1:${CFG.entryPort}\r\nUpgrade: websocket\r\n` +
              `Connection: Upgrade\r\nSec-WebSocket-Key: abc\r\ncookie: dsh-entry=${CFG.key}\r\n\r\n`);
          });
          let b = '', armed = false;
          sk.on('data', (d) => {
            b += d.toString('utf8');
            if (/WS-BYTES-BACK/.test(b) && !armed) {
              armed = true;
              setTimeout(() => { try { sk.write('PING-AFTER-IDLE'); } catch (e) {} }, 4 * CFG.wsHandshakeMs);
            }
            if (/ECHO:PING-AFTER-IDLE/.test(b)) { try { sk.destroy(); } catch (e) {} resolve({ ok: true, b }); }
          });
          sk.on('close', () => resolve({ ok: false, b })); sk.on('error', () => resolve({ ok: false, b }));
          setTimeout(() => { try { sk.destroy(); } catch (e) {} resolve({ ok: false, b }); }, 4000);
        });
        R('握手成功之后空闲 1 秒（= 4 倍握手窗口）隧道还活着，字节照样回显',
          idle.ok, `安静 ${4 * CFG.wsHandshakeMs}ms 之后收到 ${idle.b.length} B`);
        const stall = await rawUpgrade(`dsh-entry=${CFG.key}`, false, '', '/ws-stall');
        R('上游不回 101 时确实在握手窗口内掐掉，且原因写的是"握手"不是"空闲"',
          stall.why === '对端断开' && /握手/.test(S.n.lastErr), `结束原因=${stall.why} ｜ lastErr=${S.n.lastErr}`);
        S.upBase = 'http://127.0.0.1:1/';              // 这个端口没人听 ⇒ TCP 立刻 ECONNREFUSED
        const refused = await rawUpgrade(`dsh-entry=${CFG.key}`, false, '', '/ws');
        S.upBase = savedUpBase;
        const after = await get('/__origin-echo');     // 入口还活着吗（老版这里整个进程已经没了）
        R('上游连不上只掐这一条隧道，入口进程不能被 unhandled error 带走',
          after.code === 200, `隧道结束原因=${refused.why} ｜ 随后一发 HTTP ${after.code} ｜ lastErr=${S.n.lastErr}`);
        CFG.wsHandshakeMs = savedHs;
      }

      // 7) 上游 401 → 自动重换
      S.pendingTokenUrl = `http://127.0.0.1:${upPort}/?token=good${'B'.repeat(39)}`;
      const before401 = S.n.upstream401;
      const gone = await get('/__give401');
      R('上游 401 被数进去', S.n.upstream401 > before401, `http=${gone.code} upstream401=${S.n.upstream401}`);
      await new Promise((r) => setTimeout(r, 250));
      R('401 之后自动用手上的 token 重换', S.n.reauth >= 1, `reauth=${S.n.reauth}`);

      // 8) 日志脱敏
      fs.writeFileSync(CFG.log, '');
      log(`dsh web: http://127.0.0.1:${upPort}/?token=good${'C'.repeat(39)}`);
      log(`cookie: dsh-entry=${CFG.key}`);
      const logged = fs.readFileSync(CFG.log, 'utf8');
      R('token 不落盘', !/token=good/.test(logged), logged.split('\n')[0]);
      R('入口口令不落盘', !new RegExp('dsh-entry=' + CFG.key).test(logged));

      // 9) 口令来源：从文件读，绝不从 argv 取（他自己的红线：密钥不上命令行）
      const savedKey = CFG.key;
      CFG.key = '';
      fs.writeFileSync(CFG.keyFile, savedKey + '\n', { mode: 0o600 });
      R('口令能从 keyFile 读到（env 不给也能起）', resolveKey() === savedKey, `${CFG.keyFile}，长度 ${savedKey.length}`);
      fs.writeFileSync(CFG.keyFile, '\n');
      R('keyFile 空 ⇒ 交回空串', resolveKey() === '');
      fs.unlinkSync(CFG.keyFile);
      R('keyFile 不在 ⇒ 同样交回空串', resolveKey() === '');
      CFG.key = savedKey;

      // 10) 跑交付物本身：真起一个子进程，验"没口令就拒起"这条不是写在注释里的愿望
      const probe = require('child_process').spawnSync(process.execPath, [__filename, '--start'], {
        env: Object.assign({}, process.env, {
          DSH_ENTRY_KEY: '', DSH_ENTRY_KEY_FILE: path.join(st, 'nope.key'),
          DSH_ENTRY_PORT: String(CFG.entryPort + 7), DSH_UP_PORT: String(upPort) }),
        encoding: 'utf8', timeout: 8000 });
      R('拿不到口令 ⇒ --start 拒起（exit=2，而不是起来一个空口令的入口）',
        probe.status === 2 && /拒绝启动/.test((probe.stderr || '') + (probe.stdout || '')), `exit=${probe.status}`);
      R('拒起那段命令行里没有口令（argv 只有 --start）',
        (probe.spawnargs || []).join(' ').indexOf(savedKey) < 0);

      server.close(); fake.close();
      fs.unlinkSync(CFG.compat);
      console.log('\n===== dsh-entry 自测 =====');
      out.forEach((l) => console.log(l));
      const pass = out.filter((l) => l.startsWith('PASS')).length;
      console.log(`合计 ${out.length} 条：PASS ${pass} / FAIL ${out.length - pass}`);
      process.exit(fails ? 1 : 0);
    });
  });
}

const argv = process.argv.slice(2);
if (argv.includes('--selftest')) doSelftest();
else if (argv.includes('--stop')) doStop();
else if (argv.includes('--status')) doStatus();
else if (argv.includes('--start')) doStart();
else { console.log('用法：node dsh-entry.js --start | --status | --stop | --selftest'); }
