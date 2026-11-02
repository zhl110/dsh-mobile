#!/bin/bash
# 探针 83（只读）：82 号数到"documentpreview 的 excel/pdf 那两份 client.js 里真有 createObjectURL + .download"，
# 但**数命中文件**不等于"它就是走 <a download> 那一条路"。这一发把原文窗口取出来看形状：
# 如果是 `a.href=URL.createObjectURL(b); a.download=名字; a.click()` ⇒ 0.10 那条 blob 路正好接住（且名字要靠页面属性）；
# 如果是别的（比如交给后端回一个 http URL）⇒ 接的是 http 那条。
set -u
PKGS=/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai
SAY() { printf '\n=== %s\n' "$1"; }
win() {   # 在某个文件里找一段原文，只印命中处前后各 60 字符（拆行之后才看得清，minified 一行 1 MB）
  # 注意：这里**不能用 grep -F** —— 加了 -F，那串 `.{0,60}` 就成了字面量（点、花括号都不再是量词），
  # 我第一发就是这么把五个文件的窗口全打成空的（已进 AGENTS.md 已知坑）。
  local f="$1" pat="$2"
  printf '  ┌ %s ｜ %s\n' "$(basename "$f")" "$pat"
  timeout 30 tr ';{}' '\n\n\n' < "$f" 2>/dev/null | timeout 20 grep -o -m3 -E ".{0,60}$pat.{0,60}" | sed 's/^/    │ /'
}

for f in "$PKGS/dsh-client-ui-sidebar-documentpreview/lib/client.excel.js" \
         "$PKGS/dsh-client-ui-sidebar-documentpreview/lib/client.pdf.js" \
         "$PKGS/dsh-client-ui-sidebar-documentpreview/lib/client.js" \
         "$PKGS/dsh-client-ui-conversation/lib/client.js" \
         "$PKGS/dsh-client-ui-settings-general/lib/client.js"; do
  SAY "文件：${f#$PKGS/}"
  [ -f "$f" ] || { echo '  !! 不在位'; continue; }
  ls -l "$f" | awk '{printf "  大小=%s B\n", $5}'
  win "$f" 'createObjectURL'
  win "$f" '\.download='
  win "$f" 'download='
  win "$f" '\.click\(\)'
done

SAY '收尾'
echo '本探针只读：没写、没改、没装；不建临时件。'
