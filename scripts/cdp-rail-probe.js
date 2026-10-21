// cdp-rail-probe.js —— 给 scripts/dsh-cdp.js --eval 用的探针（只读，不改页面）
// 为什么要有这个文件：侧栏与键盘那两件事的判据全在页面几何里，光看代码是猜。
// 这个探针一次取三样：① 视口与 visualViewport 读数；② 左侧那一列从最内层到最外层的祖先链
// （每层的 class / position / overflow / 内容高 vs 可视高）；③ 聊天输入框在哪、它的祖先链。
// 写法约束（被 bash 双引号包住送进 node）：串只用单引号，不出现反引号、$、反斜杠。
(function () {
  function px(v) { return Math.round(v * 10) / 10; }
  function textLeaves(t) {
    var out = [];
    var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    var n;
    while ((n = w.nextNode())) {
      if (((n.nodeValue || '')).trim() === t) out.push(n.parentElement);
    }
    return out;
  }
  function info(el, depth) {
    var r = el.getBoundingClientRect();
    var cs = window.getComputedStyle(el);
    return {
      d: depth,
      tag: el.tagName.toLowerCase(),
      cls: (typeof el.className === 'string' ? el.className : '').slice(0, 48),
      pos: cs.position,
      ovY: cs.overflowY,
      h: px(r.height), top: px(r.top), left: px(r.left), w: px(r.width),
      ch: el.clientHeight, sh: el.scrollHeight,
      canScroll: el.scrollHeight > el.clientHeight + 2,
      flexDir: cs.flexDirection,
      insetB: cs.insetBottom, bottom: cs.bottom,
      maxH: cs.maxHeight
    };
  }
  function chain(el, maxDepth) {
    var a = [], d = 0;
    while (el && d < maxDepth) { a.push(info(el, d)); el = el.parentElement; d++; }
    return a;
  }
  var res = { url: location.href.slice(0, 60), title: document.title };
  res.viewport = {
    iw: window.innerWidth, ih: window.innerHeight, dpr: window.devicePixelRatio,
    vvW: window.visualViewport ? px(window.visualViewport.width) : null,
    vvH: window.visualViewport ? px(window.visualViewport.height) : null,
    vvOT: window.visualViewport ? px(window.visualViewport.offsetTop) : null,
    vvScale: window.visualViewport ? px(window.visualViewport.scale) : null,
    docCH: document.documentElement.clientHeight,
    docSH: document.documentElement.scrollHeight,
    bodyH: px(document.body.getBoundingClientRect().height),
    side: window.__DSH_SIDE__ ? JSON.parse(JSON.stringify(window.__DSH_SIDE__)) : null
  };
  var anchors = ['新会话', '插件', '插件市场', '自动化任务', '工作区'];
  var found = {};
  anchors.forEach(function (t, i) {
    var l = textLeaves(t);
    found['a' + i] = { text: t, leaves: l.length };
    if (l.length) found['a' + i].firstChainTop = info(l[0], 0);
  });
  res.anchors = found;
  // 祖先链：从「新会话」那个叶子往上 14 层
  var navLeaf = textLeaves('新会话')[0] || null;
  res.navChain = navLeaf ? chain(navLeaf, 14) : 'no-nav-leaf';
  // 「工作区」往上 14 层（会话记录那一块）
  var wsLeaf = textLeaves('工作区')[0] || null;
  res.wsChain = wsLeaf ? chain(wsLeaf, 14) : 'no-ws-leaf';
  // 整页里所有「自己可滚」的元素（这就是现在能划的那几个）
  var scrollers = [];
  var all = document.querySelectorAll('body *');
  for (var i = 0; i < all.length; i++) {
    var el = all[i];
    if (el.scrollHeight > el.clientHeight + 8 && el.clientHeight > 40) {
      var cs = window.getComputedStyle(el);
      if (cs.overflowY === 'auto' || cs.overflowY === 'scroll') {
        var r = el.getBoundingClientRect();
        scrollers.push({
          tag: el.tagName.toLowerCase(), cls: (typeof el.className === 'string' ? el.className : '').slice(0, 40),
          w: px(r.width), h: el.clientHeight, sh: el.scrollHeight, left: px(r.left), top: px(r.top),
          kids: el.children.length
        });
      }
    }
  }
  res.scrollers = scrollers;
  // 输入框
  var inputs = [];
  var cand = document.querySelectorAll('textarea, input[type=text], [contenteditable=true], [contenteditable]');
  for (var j = 0; j < cand.length; j++) {
    var e = cand[j];
    var rr = e.getBoundingClientRect();
    inputs.push({
      tag: e.tagName.toLowerCase(), ce: e.getAttribute('contenteditable'), ph: (e.getAttribute('placeholder') || '').slice(0, 24),
      cls: (typeof e.className === 'string' ? e.className : '').slice(0, 40),
      w: px(rr.width), h: px(rr.height), top: px(rr.top), bottom: px(rr.bottom), vis: rr.width > 0 && rr.height > 0
    });
  }
  res.inputs = inputs;
  var main = inputs.filter(function (x) { return x.vis; })[0];
  if (main) {
    var sel = main.tag === 'textarea' ? 'textarea' : (main.ce ? '[contenteditable]' : 'input[type=text]');
    var node = document.querySelector(sel);
    res.composerChain = node ? chain(node, 12) : 'not-found';
  }
  return JSON.stringify(res, null, 1);
})()
