// dsh-compat.js —— 给老内核浏览器补几个 dsh 前端要用的 API
// 为什么要有这个文件：一加 13 预装的 HeyTap 浏览器(com.heytap.browser 40.10.23.1)内核低于
// Chromium 116，没有 AbortSignal.any。dsh 的浏览器侧模块（如
// @deepseek-ai/dsh-api-session-controller/lib/client.js）用了它，实测后果是：
//   ① 工作区下拉永远停在"正在加载工作区…"；② "添加工作区"的选目录弹窗里直接红字报
//   AbortSignal.any is not a function。服务端(node v22.20)本身有这个 API，坏的是页面。
// 注入方式：在 dsh-web-frontend/dist/index.html 的 module script 之前加
//   <script src="./assets/dsh-compat.js"></script>
// 服务端没有下发 CSP（实测响应头只有 content-type/cache-control/referrer-policy），所以能注入。
// 升级 dsh 或换浏览器(Chrome/Edge 116+)后这个文件可以整个删掉，还原见 RUNBOOK。
(function () {
  if (typeof AbortSignal === "undefined") return;
  var S = AbortSignal;

  function doAbort(controller, reason) {
    if (controller.signal.aborted) return;
    try { controller.abort(reason); }
    catch (e) { try { controller.abort(); } catch (e2) {} }
  }

  // AbortSignal.any(iterable)：任一信号 abort，合并信号就 abort（Chrome 116+）
  if (!S.any) {
    S.any = function (iterable) {
      var controller = new AbortController();
      var list = [];
      try {
        for (var it = iterable[Symbol.iterator](); ;) {
          var n = it.next();
          if (n.done) break;
          list.push(n.value);
        }
      } catch (e) {}
      for (var j = 0; j < list.length; j++) {
        var sig = list[j];
        if (!sig) continue;
        if (sig.aborted) { doAbort(controller, sig.reason); return controller.signal; }
        (function (s) {
          try {
            s.addEventListener("abort", function () { doAbort(controller, s.reason); }, { once: true });
          } catch (e) {}
        })(sig);
      }
      return controller.signal;
    };
  }

  if (!S.abort) {
    S.abort = function (reason) {
      var c = new AbortController();
      doAbort(c, reason);
      return c.signal;
    };
  }

  // AbortSignal.timeout(ms)：到点自动 abort，reason 是 TimeoutError（Chrome 97+）
  if (!S.timeout) {
    S.timeout = function (ms) {
      var c = new AbortController();
      setTimeout(function () {
        var r;
        try { r = new DOMException("The operation timed out.", "TimeoutError"); } catch (e) { r = undefined; }
        doAbort(c, r);
      }, ms);
      return c.signal;
    };
  }

  // Promise.withResolvers()（Chrome 119+）
  if (!Promise.withResolvers) {
    Promise.withResolvers = function () {
      var resolve, reject;
      var promise = new Promise(function (res, rej) { resolve = res; reject = rej; });
      return { promise: promise, resolve: resolve, reject: reject };
    };
  }

  // Object.hasOwn(obj, key)（Chrome 93+）
  if (!Object.hasOwn) {
    Object.hasOwn = function (obj, key) {
      return obj != null && Object.prototype.hasOwnProperty.call(obj, key);
    };
  }
})();

// ============================================================================
// 第二段：把左边那一列改成"整列自己滚"（2026-10-21 他提了两次）。
//
// 第一版只做了一半，失败了，这里把两次的话和读数都留着：
//   ① 他先说「横屏的时候左边这里是固定的，你得让它能自由上下移动，否则下面的看不到、划不出来」。
//      我当时找"被裁掉的那一层"给它放开 overflow —— 结果那层本来就有 overflow-y:auto，等于没动
//      （__DSH_SIDE__ 里那句 fallback:1、h 360 / c 360 就是当时的自证读数：压根没量到"被裁"）。
//   ② 他试完说「目前只有工作区底下那些会话记录能滑，我要的是整列都能滑，否则横屏时选不到下面的会话」。
//      CDP 打子树（downloads/cdp-rail-tree-2.txt，横屏视口 792×360，列宽 280）给的原因是这样：
//        div.bhn1Oq_list   overflow-y:auto  内容 402 px  可视 **16 px**   ← 记录就装在这一条缝里
//        它到列根之间 6 层全是 flex-grow:1 + min-height:0；列根 hHd-Xa_root 里
//        logo 60 + 新会话 38 + 三个入口 116 + 工作区标题 36 + 底部设置 52 = 296，360 减去这些只剩 16。
//      ⇒ 病不是"没给滚动"，是"给滚动的那层被压扁了"。所以这一段做两件事：
//        ① 找到列里"内容比可视高一截"的那层（=被压扁的那层），② 把它到列根之间所有 flex-grow 的层
//        松成 flex:0 0 auto / height:auto / overflow:visible —— 列根本身就成了滚动的人。
//      现场验的读数（downloads/cdp-side-fix-1.txt，改完立刻撤干净）：列内容高 360→746，
//      那层可视 16→402，rail.scrollTop=160 真吃到 160（可滚余量 386 px）。
//
// 为什么不写死选择器：上游产物没有语义类名 —— 探针 50（downloads/p50.txt）在真机那份
// index-BxpfOGf3.css（77,343 B）里数 sidebar / _rail / aside 命中全是 0，137 个 data-* 也全是
// dockkit/window/modal 一族。hHd-Xa_ / bhn1Oq_ 这种前缀换个构建就变 ⇒ 一律靠页面上真实存在的
// 文字（四个入口 + 「工作区」）和几何量定位，属性选择器 + !important 才不会被 React 重渲染冲掉。
//
// 什么时候不动手：只有"那一层可视高不足列高 35%、且内容比可视高 24 px 以上"才改。
// 竖屏时列表本来有地方 ⇒ 三个属性一个都不挂，样式表也不插；
// 竖屏真装不下了（会话多的时候）同样让它整列滚 —— 那就是他要的效果，不算越界。
//
// 自己别把自己的活拆了（这个坑踩过一次，写在下面 kept 那条读数上）：改完之后再跑一轮，
// "压扁"这件事已经不存在了（那层已经展开、余量 0），照原逻辑会把属性摘掉、打回 16 px，
// 跟着 MutationObserver 又是一轮 ⇒ 反复抖动。所以先看列根上是不是我们挂的 ATTR、
// 整列此刻是不是真能滚，是就保持不动，只更新读数。
//
// 自证：window.__DSH_SIDE__ 留了最后一次跑的读数（锚点数、定到的层、中间松掉几层、改前后各层高度），
// node scripts/dsh-cdp.js --eval "JSON.stringify(window.__DSH_SIDE__)" 一发就能看见，不用猜。
(function () {
  var NAV = ["新会话", "插件", "插件市场", "自动化任务"];
  var W_WORKSPACE = "工作区";
  var ATTR = "data-dsh-side-scroll";      // 挂到列根：它自己滚
  var ATTR_IN = "data-dsh-side-inner";    // 挂到被压扁的那层：内容展开
  var ATTR_G = "data-dsh-side-grow";      // 挂到中间那些 flex-grow 的层：不再压它
  var STYLE_ID = "dsh-side-scroll-style";
  var info = { runs: 0, anchors: 0, rail: null, inner: null, layers: 0, applied: false,
               before: null, after: null, last: 0 };
  window.__DSH_SIDE__ = info;

  function norm(s) { return (s || "").replace(/\s+/g, ""); }

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) return;
    var st = document.createElement("style");
    st.id = STYLE_ID;
    // 只放开竖向；横向一律不动，免得把列里的按钮挤出可点区域
    st.textContent =
      "[" + ATTR + "]{overflow-y:auto !important;-webkit-overflow-scrolling:touch;" +
      "overscroll-behavior:contain;touch-action:pan-y}" +
      "[" + ATTR_IN + "],[" + ATTR_G + "]{flex:0 0 auto !important;height:auto !important;" +
      "min-height:0 !important;max-height:none !important;overflow:visible !important}";
    (document.head || document.documentElement).appendChild(st);
  }

  function leavesFor(word) {
    var all = document.getElementsByTagName("*");
    var out = [];
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (el.childElementCount) continue;              // 只要叶子，避免抓到整页
      if (norm(el.textContent) !== word) continue;
      var r = el.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0) continue;      // 没渲染出来的不算
      out.push(el);
    }
    return out;
  }

  function chain(el) {
    var a = [];
    while (el && el.nodeType === 1) { a.push(el); el = el.parentElement; }
    return a;
  }

  function label(el) {
    return el.tagName.toLowerCase() +
      (typeof el.className === "string" && el.className ? "." + el.className.trim().split(/\s+/)[0] : "") +
      (el.id ? "#" + el.id : "");
  }

  function stripAttrs(nodes) {
    var sel = "[" + ATTR + "],[" + ATTR_IN + "],[" + ATTR_G + "]";
    var had = nodes ? nodes.querySelectorAll(sel) : document.querySelectorAll(sel);
    for (var i = 0; i < had.length; i++) {
      had[i].removeAttribute(ATTR); had[i].removeAttribute(ATTR_IN); had[i].removeAttribute(ATTR_G);
    }
  }

  function clearAll() { stripAttrs(null); info.applied = false; }

  function read(el) {
    if (!el) return null;
    return { el: label(el), ch: el.clientHeight, sh: el.scrollHeight };
  }

  function run() {
    info.runs++;
    info.last = Date.now();
    var sets = [], i, j, k, has;
    for (k = 0; k < NAV.length; k++) {
      var s = leavesFor(NAV[k]);
      if (!s.length) { clearAll(); info.anchors = 0; return; }   // 少一个锚点就不敢下手，宁可不改
      sets.push(s);
    }
    info.anchors = sets.length;
    var ws = leavesFor(W_WORKSPACE);
    if (!ws.length) { clearAll(); return; }
    // 列根 = 同时装着那四个入口和「工作区」的最小祖先（从第一个入口的叶子往上走，第一个命中就是最小的）
    var anc = chain(sets[0][0]), rail = null;
    for (i = 0; i < anc.length; i++) {
      var el = anc[i];
      var ok = el !== document.body && el !== document.documentElement;
      for (j = 0; ok && j < sets.length; j++) {
        has = false;
        for (k = 0; k < sets[j].length; k++) if (el.contains(sets[j][k])) { has = true; break; }
        if (!has) ok = false;
      }
      if (ok) {
        has = false;                                    // ← 这里必须重新置 false：var 是函数作用域，
        for (j = 0; j < ws.length; j++) if (el.contains(ws[j])) { has = true; break; }  //   上一循环留下的 true 会装成"也含工作区"
        if (!has) ok = false;
      }
      if (ok) { rail = el; break; }
    }
    if (!rail) { clearAll(); return; }
    info.rail = label(rail);
    // 先看是不是我们已经在管这一列，而且整列此刻真能滚 —— 是就保持，别再按"压扁没压扁"重判
    var mine = rail.querySelector("[" + ATTR_IN + "]");
    if (rail.getAttribute(ATTR) === "1" && mine && rail.scrollHeight > rail.clientHeight + 24) {
      info.applied = true;
      info.inner = label(mine);
      info.after = { railCH: rail.clientHeight, railSH: rail.scrollHeight, innerCH: mine.clientHeight,
                     innerSH: mine.scrollHeight, room: rail.scrollHeight - rail.clientHeight, kept: 1 };
      return;
    }
    // 列里"内容比可视高一截、自己又带 overflow"的那层 = 被压扁的那层（取余量最大的）
    var inner = null, gain = 0, all = rail.querySelectorAll("*");
    for (i = 0; i < all.length; i++) {
      var e = all[i], oy = window.getComputedStyle(e).overflowY;
      if (e.clientHeight < 8) continue;
      if (oy !== "auto" && oy !== "scroll" && oy !== "hidden" && oy !== "clip") continue;
      var g = e.scrollHeight - e.clientHeight;
      if (g > gain) { gain = g; inner = e; }
    }
    info.before = { railCH: rail.clientHeight, railSH: rail.scrollHeight, inner: read(inner), gain: gain };
    // 条件不到就不动手：压得不狠（可视高还有列高 35% 以上）或余量不足 24 px ⇒ 原样
    if (!inner || gain < 24 || inner.clientHeight > rail.clientHeight * 0.35) { clearAll(); return; }
    var layers = chain(inner), cut = layers.length;
    for (i = 0; i < layers.length; i++) if (layers[i] === rail) { cut = i; break; }
    layers = layers.slice(0, cut);
    ensureStyle();
    stripAttrs(rail);                       // 只清这一列里的旧属性：别把别人的也摘了
    rail.setAttribute(ATTR, "1");
    inner.setAttribute(ATTR_IN, "1");
    for (i = 0; i < layers.length; i++) if (layers[i] !== rail && layers[i] !== inner) layers[i].setAttribute(ATTR_G, "1");
    info.layers = layers.length;
    info.inner = label(inner);
    // 读的是改完之后浏览器认下来的数（读 scrollHeight 会强制 layout），__DSH_SIDE__ 里就能对账
    info.after = { railCH: rail.clientHeight, railSH: rail.scrollHeight, innerCH: inner.clientHeight,
                   innerSH: inner.scrollHeight, room: rail.scrollHeight - rail.clientHeight };
    info.applied = true;
  }

  var pending = 0;
  function schedule() {
    if (pending) return;
    pending = setTimeout(function () { pending = 0; try { run(); } catch (e) { info.error = String(e && e.message || e); } }, 180);
  }
  function boot() {
    run();
    if (!window.__DSH_SIDE_WATCHING) {
      window.__DSH_SIDE_WATCHING = 1;
      var mo = new MutationObserver(schedule);
      mo.observe(document.documentElement, { childList: true, subtree: true });
      window.addEventListener("resize", schedule);
      window.addEventListener("orientationchange", function () { setTimeout(schedule, 250); });
    }
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
