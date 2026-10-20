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
