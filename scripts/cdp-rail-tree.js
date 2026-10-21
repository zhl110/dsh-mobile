// cdp-rail-tree.js —— 把左侧那一列的子树逐层打出来（只读）
// 为什么：上一版探针只找了「自己可滚」的元素，在这台机上只找到聊天区那一个（wSkVaW_scrollBody），
// 侧栏一个没有 ⇒ 侧栏的内容是被 flex 压扁 + overflow:hidden 裁掉的，不是"没给滚动"。
// 要修就得看清每一层的 top/height/flex/overflow/minHeight，所以这里逐层打印。
(function () {
  function px(v) { return Math.round(v * 10) / 10; }
  function row(el, depth, path) {
    var r = el.getBoundingClientRect();
    var cs = window.getComputedStyle(el);
    return {
      p: path, d: depth,
      tag: el.tagName.toLowerCase(),
      cls: (typeof el.className === 'string' ? el.className : '').replace(/hHd-Xa_|pI_x6G_|bhn1Oq_/g, '').slice(0, 34),
      top: px(r.top), h: px(r.height), ch: el.clientHeight, sh: el.scrollHeight,
      ovY: cs.overflowY, shrink: cs.flexShrink, grow: cs.flexGrow, basis: cs.flexBasis,
      minH: cs.minHeight, maxH: cs.maxHeight, disp: cs.display, pos: cs.position,
      kids: el.children.length, txt: (el.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 26)
    };
  }
  var rail = document.querySelector('.pI_x6G_sidebarCol') || document.querySelector('.hHd-Xa_root');
  if (!rail) return 'NO-RAIL';
  var out = [], seen = 0;
  (function walk(el, depth, path) {
    if (depth > 10 || seen > 260) return;
    out.push(row(el, depth, path));
    seen++;
    for (var i = 0; i < el.children.length; i++) walk(el.children[i], depth + 1, path + '.' + i);
  })(rail, 0, '0');
  return JSON.stringify({ viewport: { iw: window.innerWidth, ih: window.innerHeight }, rows: out }, null, 0);
})()
