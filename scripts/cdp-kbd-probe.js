// cdp-kbd-probe.js —— 键盘弹出前后各取一次几何读数（只读 + 聚焦/失焦，不动数据）
// 为什么要有这个文件：他说「输入法跳上来，Harness 的输入框不跟着顶上去」。
// 判据只有一条：键盘起来后 window.innerHeight / visualViewport.height 有没有变小。
//   变小 ⇒ 窗口真的被 adjustResize 压了，是前端自己的固定高度不跟 → 页面侧能修；
//   没变 ⇒ 键盘是盖在窗口上面的（全屏/沉浸模式会让 adjustResize 失效）→ 页面侧看不见键盘，只能改壳。
// 用法：node scripts/dsh-cdp.js --eval "$(cat scripts/cdp-kbd-probe.js)" [--focus 1]
// 返回里 phase 标明这是按下前还是按下后。
(function () {
  function px(v) { return Math.round(v * 10) / 10; }
  function snap(el) {
    if (!el) return null;
    var r = el.getBoundingClientRect();
    var cs = window.getComputedStyle(el);
    return {
      tag: el.tagName.toLowerCase(), cls: (typeof el.className === 'string' ? el.className : '').slice(0, 40),
      top: px(r.top), bottom: px(r.bottom), h: px(r.height), pos: cs.position,
      ovY: cs.overflowY, transform: cs.transform === 'none' ? 'none' : cs.transform.slice(0, 40),
      insetB: cs.insetBottom
    };
  }
  var phase = window.__DSH_KBD_PHASE__ || 'before';
  var composer = document.querySelector('.uV2eYG_input') || document.querySelector('[contenteditable=true]');
  var res = {
    phase: phase,
    innerH: window.innerHeight, innerW: window.innerWidth,
    vvH: window.visualViewport ? px(window.visualViewport.height) : null,
    vvW: window.visualViewport ? px(window.visualViewport.width) : null,
    vvOT: window.visualViewport ? px(window.visualViewport.offsetTop) : null,
    vvOB: window.visualViewport ? px(window.visualViewport.offsetTop) : null,
    docCH: document.documentElement.clientHeight,
    scrollY: px(window.scrollY),
    active: document.activeElement ? (document.activeElement.tagName.toLowerCase() + '.' + String(document.activeElement.className).slice(0, 30)) : null,
    composer: snap(composer),
    // 输入框外层那圈（真正定位的容器）往上 4 层
    composerChain: (function () {
      var a = [], el = composer, d = 0;
      while (el && d < 5) { a.push(snap(el)); el = el.parentElement; d++; }
      return a;
    })(),
    // 底部那一排是什么（键盘会盖住它）
    footerCandidates: (function () {
      var out = [], all = document.querySelectorAll('body *');
      for (var i = 0; i < all.length; i++) {
        var e = all[i], r = e.getBoundingClientRect();
        if (r.height > 8 && Math.abs(r.bottom - window.innerHeight) < 3 && r.width > 200) {
          var cs = window.getComputedStyle(e);
          out.push({ tag: e.tagName.toLowerCase(), cls: (typeof e.className === 'string' ? e.className : '').slice(0, 40), pos: cs.position, h: px(r.height), top: px(r.top) });
          if (out.length > 8) break;
        }
      }
      return out;
    })()
  };
  if (phase === 'after') {
    // 键盘起来后再量一次"被盖住多少"
    res.coveredByKeyboard = px(window.innerHeight - (res.vvH || window.innerHeight));
  }
  return JSON.stringify(res);
})()
