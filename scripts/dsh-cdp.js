#!/usr/bin/env node
// scripts/dsh-cdp.js —— 从 Windows 直接看/驱动手机上那个 WebView 里的页面（Chrome DevTools Protocol）
//
// 为什么要有这个：他报的三件事（"点插件没反应""选目录报 HTTP 403""操作起来迟钝"）都属于
// **页面里发生了什么**，而手机屏幕上看不见。已有的两条观测面各差一截：
//   · 入口自述页(:3081/__entry_status) 只看得到穿过入口的请求，看不见前端自己的报错；
//   · logcat 只记壳的 6 个步骤，而且这台机 1 分钟就把缓冲区冲满（实测 13,927 行 OEM 日志）。
// CDP 是第三条：DOM、console、网络三样都在页面这一侧，能问出"这个按钮的 href/target 是什么"
// "这一发请求打到哪个路径、回了什么码"。前提是 App 里那行 setWebContentsDebuggingEnabled(true)。
//
// 用法（在 D:\mycode\dsh-mobile 下）：
//   node scripts/dsh-cdp.js --list                       列目标（页面 URL、标题、ws 地址）
//   node scripts/dsh-cdp.js --eval "1+1"                 在页面里求值并打印
//   node scripts/dsh-cdp.js --eval "<js>" --await         等 Promise（默认开）
//   node scripts/dsh-cdp.js --watch 12                   盯 12 秒：打印这期间所有请求(方法 路径 状态)与 console
//   node scripts/dsh-cdp.js --click "a[href*=plugin]"    在页面里对第一个匹配元素 dispatch 一次真点击，
//                                                        然后自动带 6 秒 --watch（点了没反应时看它到底发了什么）
//   node scripts/dsh-cdp.js --tapsel ".uV2eYG_input"      对元素中心发一次"真触摸"（要弹软键盘只能用它，
//                                                        --click/focus() 都不算用户操作，键盘不出来）
//   node scripts/dsh-cdp.js --pid 23670                  手动指定 WebView 进程号（默认自己从 /proc/net/unix 找）
//
// 前提：手机亮着且 App 在前台 —— 屏幕一灭，Activity 走 onPause，壳里那句 pauseTimers() 会把页面
// 定时器停掉，渲染进程也可能被冻结；那时候的"没反应"是我们的判据在骗人，不是页面的事实。
// 所以本脚本第一件事就是查 mWakefulness，Dozing/Asleep 直接拒绝跑（除非 --force）。
//
// 只读优先：--eval / --watch 不动状态；--click 与 --tapsel 会真的点一下，用它之前想清楚点的是哪个元素。
// 本脚本不打印 cookie 与 Authorization 头（口令与 token 都在里头）。

const { execFileSync } = require('child_process');
const http = require('http');

const ADB = process.env.DSH_ADB || 'D:/mycode/.agent-tools/platform-tools/adb.exe';
const LOCAL_PORT = +(process.env.DSH_CDP_PORT || 9333);

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  return i >= 0 && process.argv[i + 1] !== undefined && !process.argv[i + 1].startsWith('--')
    ? process.argv[i + 1] : (process.argv.includes('--' + name) ? true : dflt);
}
function adb(argsArr, opts) {
  return execFileSync(ADB, argsArr, Object.assign({ encoding: 'utf8', timeout: 60000 }, opts || {}));
}
function sh(cmd) { return adb(['shell', 'su', '-c', cmd]); }

// ── 找到手机上那个可调试的 WebView ────────────────────────────────────────────
function findSocket(pid) {
  let out = '';
  try { out = sh(`cat /proc/net/unix | grep -o "webview_devtools_remote_[0-9]*" | sort -u`); }
  catch (e) { throw new Error('读 /proc/net/unix 失败：' + e.message.split('\n')[0]); }
  const names = out.split('\n').map((s) => s.trim()).filter(Boolean);
  if (!names.length) throw new Error('手机上没有可调试的 WebView：App 没在前台，或壳里没开 setWebContentsDebuggingEnabled');
  if (pid) {
    const hit = names.find((n) => n.endsWith('_' + pid));
    if (!hit) throw new Error(`pid=${pid} 没有对应的调试套接字（在位的：${names.join(' ')}）`);
    return hit;
  }
  return names[0];
}
function wakefulness() {
  try {
    const m = /mWakefulness=(\w+)/.exec(sh('dumpsys power 2>/dev/null | grep -m1 mWakefulness'));
    return m ? m[1] : '未知';
  } catch (e) { return '未知'; }
}
function httpJson(path) {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port: LOCAL_PORT, path, timeout: 6000 }, (res) => {
      let b = ''; res.on('data', (d) => b += d);
      res.on('end', () => { try { resolve(JSON.parse(b)); } catch (e) { reject(new Error('不是 JSON：' + b.slice(0, 120))); } });
    }).on('error', reject).on('timeout', function () { this.destroy(new Error('CDP HTTP 超时')); });
  });
}

// ── 一个最小 CDP 客户端 ──────────────────────────────────────────────────────
class Cdp {
  constructor(wsUrl) { this.wsUrl = wsUrl; this.id = 0; this.pending = new Map(); this.listeners = []; }
  connect() {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(this.wsUrl);
      this.ws.onopen = () => resolve();
      this.ws.onerror = (e) => reject(new Error('WS 连不上：' + (e.message || 'onerror')));
      this.ws.onmessage = (ev) => {
        let m; try { m = JSON.parse(String(ev.data)); } catch (e) { return; }
        if (m.id && this.pending.has(m.id)) {
          const { res, rej } = this.pending.get(m.id); this.pending.delete(m.id);
          m.error ? rej(new Error(m.error.message || JSON.stringify(m.error))) : res(m.result);
        } else if (m.method) this.listeners.forEach((f) => f(m));
      };
    });
  }
  send(method, params) {
    const id = ++this.id;
    return new Promise((res, rej) => {
      this.pending.set(id, { res, rej });
      this.ws.send(JSON.stringify({ id, method, params: params || {} }));
      setTimeout(() => { if (this.pending.has(id)) { this.pending.delete(id); rej(new Error(method + ' 超时')); } }, 20000);
    });
  }
  on(f) { this.listeners.push(f); }
  close() { try { this.ws.close(); } catch (e) {} }
}

// 请求行：只留方法 + 路径 + 状态；query 里可能带一次性 token，头里有 cookie —— 都不打。
function reqLine(e) {
  let p = '';
  try { p = new URL(e.request ? e.request.url : e.url).pathname; } catch (err) { p = '(解析不出路径)'; }
  const st = e.response ? e.response.status : (e.type === 'XHR' ? '' : '');
  const t = e.timestamp ? Math.round(e.timestamp) : 0;
  return `${(e.request && e.request.method) || 'GET'} ${p}${st ? ' → ' + st : ''}${t ? ' @' + t : ''}`;
}

async function main() {
  const force = !!arg('force', false);
  const wake = wakefulness();
  if (!/^\bAwake\b/i.test(wake) && !force) {
    console.log(`!! 屏幕状态 ${wake} ⇒ 页面定时器被 pauseTimers() 停着，这时候的读数不作数。\n   请把手机解锁并停在「DSH 工作台」这一屏，再跑一次（真要在灭屏下硬试：加 --force）`);
    process.exit(1);
  }
  const sock = findSocket(arg('pid'));
  adb(['forward', `tcp:${LOCAL_PORT}`, `localabstract:${sock}`]);
  const list = await httpJson('/json/list');
  const pages = list.filter((t) => t.type === 'page');
  if (arg('list')) {
    console.log(`套接字 ${sock}，目标 ${list.length} 个：`);
    pages.forEach((t, i) => console.log(`  [${i}] ${t.url}｜${t.title}`));
    adb(['forward', '--remove', `tcp:${LOCAL_PORT}`]);
    return;
  }
  const want = String(arg('url', ''));
  const page = pages.find((t) => want && t.url.includes(want))
    || pages.find((t) => /127\.0\.0\.1:3081/.test(t.url)) || pages[0];
  if (!page) { console.log('!! 没有 page 类型的目标'); adb(['forward', '--remove', `tcp:${LOCAL_PORT}`]); return; }
  console.log(`目标：${page.url}｜标题=${page.title}`);

  const cdp = new Cdp(page.webSocketDebuggerUrl);
  await cdp.connect();
  await cdp.send('Runtime.enable');
  await cdp.send('Page.enable');
  await cdp.send('Log.enable').catch(() => {});

  const lines = [];
  cdp.on((m) => {
    if (m.method === 'Network.requestWillBeSent') lines.push('  请求  ' + reqLine(m.params));
    else if (m.method === 'Network.responseReceived') lines.push('  响应  ' + reqLine(m.params));
    else if (m.method === 'Runtime.consoleAPICalled') {
      const txt = (m.params.args || []).map((a) => String(a.value !== undefined ? a.value : (a.description || a.type))).join(' ');
      if (/error|warning/.test(m.params.type)) lines.push(`  console.${m.params.type}  ${txt.slice(0, 200)}`);
    } else if (m.method === 'Log.entryAdded') {
      const e = m.params.entry;
      if (/error|warning/i.test(e.level)) lines.push(`  ${e.source}  ${String(e.text).slice(0, 200)}`);
    } else if (m.method === 'Runtime.exceptionThrown') {
      const d = m.params.exceptionDetails;
      lines.push('  JS 异常  ' + String(d.exception && (d.exception.description || d.exception.value) || d.text).split('\n')[0].slice(0, 200));
    }
  });
  await cdp.send('Network.enable').catch(() => {});

  const ev = arg('eval');
  const click = arg('click');
  const watch = +(arg('watch', 0) || 0);

  if (typeof ev === 'string') {
    const r = await cdp.send('Runtime.evaluate', {
      expression: ev, returnByValue: true, awaitPromise: true, userGesture: true,
    });
    if (r.exceptionDetails) console.log('求值抛错：' + (r.exceptionDetails.exception || {}).description);
    else console.log(JSON.stringify(r.result.value, null, 2));
  }
  if (typeof click === 'string') {
    const js = `(() => { const el = document.querySelector(${JSON.stringify(click)});
      if (!el) return '没找到元素：' + ${JSON.stringify(click)};
      const a = el.closest('a') || el.querySelector('a');
      const info = { tag: el.tagName, text: (el.innerText||'').trim().slice(0,24),
        href: a ? a.getAttribute('href') : null, target: a ? a.getAttribute('target') : null };
      el.click();
      return JSON.stringify(info); })()`;
    const r = await cdp.send('Runtime.evaluate', { expression: js, returnByValue: true, awaitPromise: true, userGesture: true });
    console.log('点击：' + (r.result ? r.result.value : JSON.stringify(r.exceptionDetails || {})));
  }
  // --tapsel <选择器>：量出元素中心，再用 CDP 的 Input.dispatchTouchEvent 发一次"真触摸"。
  // 为什么不用 --click：那是 el.click()，DOM 层的事件，安卓不认它是用户操作 ⇒ 软键盘不会弹。
  // 实测（2026-10-21 晚，探针 downloads/kbd-212522/）：focus() 之后 mInputShown 仍 false，
  // 页面 innerHeight 一动不动 —— 那不是"窗口没被压小"的证据，是键盘压根没出来。
  // 所以量键盘这件事必须走触摸通道，不能用 focus，也不能用 adb input tap（那是物理像素，dpr=4 还得换算）。
  const tapsel = arg('tapsel');
  if (typeof tapsel === 'string') {
    const q = `(() => { const el = document.querySelector(${JSON.stringify(tapsel)});
      if (!el) return 'NO'; const r = el.getBoundingClientRect();
      return Math.round((r.left + r.width / 2) * 10) / 10 + ',' + Math.round((r.top + r.height / 2) * 10) / 10; })()`;
    const rc = await cdp.send('Runtime.evaluate', { expression: q, returnByValue: true });
    const pt = rc.result && rc.result.value;
    if (!pt || pt === 'NO') console.log('!! 页面上没有这个元素：' + tapsel);
    else {
      const xy = String(pt).split(',');
      const X = parseFloat(xy[0]), Y = parseFloat(xy[1]);
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: X, y: Y }] });
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
      console.log(`对 ${tapsel} 的中心 ${X},${Y}（页面 CSS 坐标）发了一次真触摸 touchStart+touchEnd`);
    }
  }
  // --scroll "x,y,dy"：让 WebView 自己合成一次**真触摸滚动**（CDP 的 synthesizeScrollGesture）。
  // 为什么不用 scrollTop 赋值代替：那只能证明"这层能滚"，证明不了"手指划得动"。
  // dy 负数 = 内容往下走（往下看），正数 = 往上。坐标是页面 CSS 像素。
  const scroll = arg('scroll');
  if (typeof scroll === 'string') {
    const pp = String(scroll).split(',');
    const SX = parseFloat(pp[0]), SY = parseFloat(pp[1]), SDY = parseFloat(pp[2]);
    if (![SX, SY, SDY].every(isFinite)) console.log('!! --scroll 要 "x,y,dy"');
    else {
      const r = await cdp.send('Input.synthesizeScrollGesture', {
        x: SX, y: SY, xDistance: 0, yDistance: SDY, gestureSourceType: 'touch', speed: 1200, preventFling: true,
      });
      console.log('已合成一次触摸滚动 x=' + SX + ' y=' + SY + ' dy=' + SDY + ' ⇒ ' + JSON.stringify(r || {}));
    }
  }
  // --setfile "选择器=设备上的绝对路径"：绕过系统选择器，直接往 input[type=file] 里塞一个文件。
  // 为什么要它：选择器开不开，logcat 已经能看了；但"页面到底能不能读出这玩意的字节"这一格，
  // 原来只能靠他在手机上真点一下才能验。这一发把最后这条链路拆开问：DOM 里有没有这个 File、
  // JS 能不能 slice 出内容、页面接着发了什么请求 —— 全是机器读数，不用碰他的相册。
  // 注意它给的是 **文件路径**（走 file 通道），不是 content:// ⇒ 它证的是"读出字节 + 上传通道"这两段，
  // content:// 那一格仍需他真点一次选择器才算数。
  const setfile = arg('setfile');
  if (typeof setfile === 'string') {
    await cdp.send('DOM.enable').catch(() => {});
    const eq = setfile.lastIndexOf('=');
    const sel = setfile.slice(0, eq), fp = setfile.slice(eq + 1);
    const doc = await cdp.send('DOM.getDocument', { depth: -1 });
    const hit = await cdp.send('DOM.querySelector', { nodeId: doc.root.nodeId, selector: sel });
    if (!hit || !hit.nodeId) console.log('!! 页面上没有这个元素：' + sel);
    else {
      // 先挂一个 change 探针：塞完文件页面到底有没有"收到通知"，这是前端那一侧的读数，
      // 和 files.length 那种 DOM 读数分开看，才知道断在哪一段。
      // 元素引用要**当场存进 window**：这个输入框是 React 渲染的，塞完之后它可能整只换掉，
      // 再去 querySelector 拿到的是新壳（files 自然是 0），那读的是"我们没塞进去"的假证。
      await cdp.send('Runtime.evaluate', { expression: `(() => { const el = document.querySelector(${JSON.stringify(sel)});
        if (!el) return 'NO'; window.__dshFileEv = []; window.__dshFileEl = el; window.__dshCaptured = [];
        el.addEventListener('change', () => { window.__dshFileEv.push('change ⇒ files=' + el.files.length);
          window.__dshCaptured = [...el.files]; });
        return 'hooked'; })()`, returnByValue: true });
      await cdp.send('DOM.setFileInputFiles', { nodeId: hit.nodeId, files: [fp] });
      // 这一发是浏览器进程 → 渲染进程的一条异步 IPC：setFileInputFiles 立刻 resolve，
      // 但 FileList 落到 DOM 上是晚一点的事。所以读回要分三次隔时问，别把"还没到"读成"上不去"。
      const js = `(async () => { const f = (window.__dshCaptured || [])[0];
        const live = window.__dshFileEl && window.__dshFileEl.files ? window.__dshFileEl.files.length : 'no ref';
        if (!f) return JSON.stringify({captured: (window.__dshCaptured || []).length, live, ev: window.__dshFileEv || '-'});
        let head = '读不出';
        try { head = (await f.slice(0, 64).text()).slice(0, 64); }
        catch (e) { head = 'ERR ' + e.name + ': ' + String(e.message).slice(0, 90); }
        return JSON.stringify({captured: (window.__dshCaptured || []).length, live, name: f.name, size: f.size, type: f.type || '-', head}); })()`;
      const waits = [120, 1200, 2500];
      for (let i = 0; i < waits.length; i++) {
        await new Promise((r) => setTimeout(r, waits[i]));
        const r = await cdp.send('Runtime.evaluate', { expression: js, returnByValue: true, awaitPromise: true, userGesture: true });
        const v = r.result ? r.result.value : JSON.stringify((r.exceptionDetails || {}).exception || r.exceptionDetails);
        console.log(`+${waits[i]}ms 页面读到：${v}`);
        if (v && !/"captured":0/.test(v)) break;
      }
    }
  }
  const secs = (click || typeof setfile === 'string') && !watch ? 6 : watch;
  if (secs > 0) {
    console.log(`盯着页面 ${secs} 秒（这期间请在手机上操作）…`);
    const until = Date.now() + secs * 1000;
    let shown = 0;
    while (Date.now() < until) {
      await new Promise((r) => setTimeout(r, 250));
      if (lines.length > shown) { process.stdout.write(lines.slice(shown).join('\n') + '\n'); shown = lines.length; }
    }
    console.log(`—— ${secs} 秒里共 ${lines.length} 条（请求/响应/console/异常）`);
  }
  cdp.close();
  adb(['forward', '--remove', `tcp:${LOCAL_PORT}`]);
}

main().catch((e) => { console.log('!! ' + e.message); try { adb(['forward', '--remove', `tcp:${LOCAL_PORT}`]); } catch (x) {} process.exit(1); });
