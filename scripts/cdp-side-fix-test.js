// cdp-side-fix-test.js —— 现场验一版「整栏可滑」的 CSS（可逆：跑完把加的属性和样式撤掉）
// 为什么：横屏时左侧那一列里，会话记录那层可视高只有 16 px、内容 402 px ——
// 上游不是没给滚动，是给滚动的那层被 flex 压扁了（读数 downloads/cdp-rail-tree-2.txt）。
// 所以修法不是"再加一次 overflow"，而是把中间那几层 flex-grow 松掉，让整列自己变成滚动的人。
// 选择逻辑一律按文案锚点 + 几何量，不写 hash class（hHd-Xa_ 这类换个版本就变）。
(function () {
  function px(v) { return Math.round(v * 10) / 10; }
  function leafs(t) {
    var out = [], w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT), n;
    while ((n = w.nextNode())) { if (((n.nodeValue || '')).trim() === t) out.push(n.parentElement); }
    return out;
  }
  function chainOf(el) { var a = []; while (el && el.nodeType === 1) { a.push(el); el = el.parentElement; } return a; }
  function m(el) {
    if (!el) return null;
    var cs = window.getComputedStyle(el), r = el.getBoundingClientRect();
    return { cls: (typeof el.className === 'string' ? el.className : '').slice(0, 30), ch: el.clientHeight, sh: el.scrollHeight, h: px(r.height), ovY: cs.overflowY, grow: cs.flexGrow, shrink: cs.flexShrink };
  }
  var A_TOP = ['新会话', '插件', '插件市场', '自动化任务'];
  var navSets = [], i;
  for (i = 0; i < A_TOP.length; i++) { var s = leafs(A_TOP[i]); if (!s.length) return JSON.stringify({ err: '锚点没找到: ' + A_TOP[i] }); navSets.push(s); }
  var navAnc = chainOf(navSets[0][0]), rail = null;
  for (i = 0; i < navAnc.length; i++) {
    var el = navAnc[i];
    var ok = true;
    for (var j = 1; j < navSets.length; j++) {
      var has = false;
      for (var k = 0; k < navSets[j].length; k++) if (el.contains(navSets[j][k])) { has = true; break; }
      if (!has) { ok = false; break; }
    }
    if (ok && el.parentElement && el.parentElement.tagName.toLowerCase() !== 'body') {
      // 还要能装下「工作区」那一段，否则选到的是导航组自己
      var ws = leafs('工作区');
      var hasWs = false;
      for (var q = 0; q < ws.length; q++) if (el.contains(ws[q])) { hasWs = true; break; }
      if (hasWs) { rail = el; break; }
    }
  }
  if (!rail) return JSON.stringify({ err: '没找到同时装着四个入口和「工作区」的那一列' });
  // 列里"被压扁的那层"：内容比可视高出一截、且自己带 overflow 的最深元素
  var inner = null, bestGain = 0, all = rail.querySelectorAll('*');
  for (i = 0; i < all.length; i++) {
    var e = all[i], cs2 = window.getComputedStyle(e);
    var oy = cs2.overflowY;
    if (e.clientHeight < 8) continue;
    if (oy !== 'auto' && oy !== 'scroll' && oy !== 'hidden' && oy !== 'clip') continue;
    var gain = e.scrollHeight - e.clientHeight;
    if (gain > bestGain) { bestGain = gain; inner = e; }
  }
  var before = { rail: m(rail), inner: m(inner) };
  if (!inner) return JSON.stringify({ err: '列里没有被压扁的一层', before: before });
  var growEls = chainOf(inner);
  for (i = 0; i < growEls.length; i++) if (growEls[i] === rail) { growEls = growEls.slice(0, i); break; }
  var STYLE_ID = 'dsh-side-fix-test-style';
  var st = document.createElement('style'); st.id = STYLE_ID;
  st.textContent = '[data-dsh-side-t]{overflow-y:auto !important;-webkit-overflow-scrolling:touch;overscroll-behavior:contain;touch-action:pan-y;}' +
    '[data-dsh-side-t-grow],[data-dsh-side-t-inner]{flex:0 0 auto !important;height:auto !important;min-height:0 !important;max-height:none !important;overflow:visible !important;}';
  document.head.appendChild(st);
  rail.setAttribute('data-dsh-side-t', '1');
  inner.setAttribute('data-dsh-side-t-inner', '1');
  for (i = 0; i < growEls.length; i++) growEls[i].setAttribute('data-dsh-side-t-grow', '1');
  var after = { rail: m(rail), inner: m(inner), growLayers: growEls.length };
  // 真能滚吗：把它往下推 160 px 看吃不吃
  rail.scrollTop = 160;
  var scrolled = { asked: 160, got: px(rail.scrollTop), maxScroll: px(rail.scrollHeight - rail.clientHeight) };
  rail.scrollTop = 0;
  var res = { before: before, after: after, scrolled: scrolled };
  // 撤干净，恢复他原来的画面
  rail.removeAttribute('data-dsh-side-t');
  inner.removeAttribute('data-dsh-side-t-inner');
  for (i = 0; i < growEls.length; i++) growEls[i].removeAttribute('data-dsh-side-t-grow');
  var s2 = document.getElementById(STYLE_ID); if (s2) s2.remove();
  res.reverted = { rail: m(document.querySelector('[data-dsh-side-scroll]') || rail) };
  return JSON.stringify(res, null, 1);
})()
