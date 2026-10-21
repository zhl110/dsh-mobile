#!/bin/bash
# 探针 65（有写）—— 把探针 64 里三件没收尾的事收尾：
#   ① 上一条装的"GitHub 整段换成 gitee.com/mirrors/"是**错的**：gitee 的镜像仓不带 owner
#      （真地址是 gitee.com/mirrors/git.git，而这条规则拼出来是 gitee.com/mirrors/git/git.git），
#      五个仓全回 rc=128（读数 downloads/p64.txt 第 9–13 行）。先把候选路一条一条量出来，再决定留哪条。
#   ② /tmp 里能归到我头上的一次性件清掉，引擎在用的那几个（dsh-spill-* / dsh-subprocess-* /
#      node-compile-cache / pnpm-store-*）一个不动。
#   ③ 四批包的"下载量 / 装完占多少"上一发没量到 —— 因为 apt 把这两行打到 **stderr**，
#      我写了 2>/dev/null 把它丢了。这发收回来。
set -u
cd / || exit 1
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
echo "chroot 内时刻: $(date '+%F %T %Z')"

echo
echo "== ① 镜像候选路逐条量（HTTP 码 + 字节，不带 --resolve，走真解析）"
REF='info/refs?service=git-upload-pack'
probe_url() {
  local NAME=$1 URL=$2
  local R
  R=$(timeout 25 curl -s -o /tmp/p65-body -w '%{http_code} %{size_download} %{time_total}' "$URL" 2>/tmp/p65-err); local RC=$?
  local ER=$(head -1 /tmp/p65-err 2>/dev/null | cut -c1-58)
  printf '   %-26s rc=%-3s %s %s\n' "$NAME" "$RC" "${R:-无读数}" "${ER:+($ER)}"
}
probe_url "gitee 无 owner（真形）" "https://gitee.com/mirrors/git.git/$REF"
probe_url "gitee 带 owner（我那条规则拼的）" "https://gitee.com/mirrors/git/git.git/$REF"
probe_url "gh-proxy.com" "https://gh-proxy.com/https://github.com/git/git.git/$REF"
probe_url "gitclone.com" "https://gitclone.com/github.com/git/git.git/$REF"
probe_url "hub.gitmirror.com" "https://hub.gitmirror.com/https://github.com/git/git.git/$REF"
probe_url "github 本体（对照）" "https://github.com/git/git.git/$REF"
echo "   （hosts 里这几条钉没钉：$(grep -cE '(gitee\.com|gh-proxy\.com|gitclone\.com|gitmirror\.com|github\.com)$' /etc/hosts) 行）"
grep -E '(gitee\.com|gh-proxy\.com|gitclone\.com|gitmirror\.com|github\.com)$' /etc/hosts | sed 's/^/     /'

echo
echo "-- 现在这条 insteadOf 还在："
git config --global --get-regexp '^url\.' 2>/dev/null | sed 's/^/   /'
echo "-- 先撤掉那条错的"
git config --global --unset 'url.https://gitee.com/mirrors/.insteadOf'
echo "   撤完剩 $(git config --global --get-regexp '^url\.' 2>/dev/null | wc -l) 条 url.* 规则"
echo "-- 按上面哪条通了，就照那个形状装（下面这段自己判，不手改）"
OK=""
if [ "$(timeout 20 curl -s -o /dev/null -w '%{http_code}' "https://gitee.com/mirrors/git.git/$REF" 2>/dev/null)" = "200" ]; then
  echo "   gitee/mirrors 可达 ⇒ 只能按仓逐条映射（它不带 owner），先装我们真用得上的那几条"
  for MAP in "git:https://github.com/git/git.git|https://gitee.com/mirrors/git.git" \
             "go:https://github.com/golang/go|https://gitee.com/mirrors/go" \
             "rust:https://github.com/rust-lang/rust|https://gitee.com/mirrors/rust" \
             "node:https://github.com/nodejs/node|https://gitee.com/mirrors/node" \
             "numpy:https://github.com/numpy/numpy|https://gitee.com/mirrors/numpy" \
             "scrapy:https://github.com/scrapy/scrapy|https://gitee.com/mirrors/scrapy"; do
    FROM=$(echo "$MAP" | cut -d'|' -f2); TO=$(echo "$MAP" | cut -d'|' -f3)
    CODE=$(timeout 20 curl -s -o /dev/null -w '%{http_code}' "$TO/$REF" 2>/dev/null)
    if [ "$CODE" = "200" ]; then
      git config --global "url.$TO.insteadOf" "$FROM"
      printf '   装 %-46s → %s（探到 200）\n' "$FROM" "$TO"
      OK="$OK $FROM"
    else
      printf '   不装 %-44s（镜像回 %s，不硬编）\n' "$FROM" "${CODE:-无码}"
    fi
  done
  echo "   实装条数: $(git config --global --get-regexp '^url\.' 2>/dev/null | wc -l)"
fi
echo "-- 装完真跑一遍（不带 GIT_ASKPASS，让它照默认走；GIT_TERMINAL_PROMPT=0 防卡住）"
for R in https://github.com/git/git.git https://github.com/golang/go https://github.com/rust-lang/rust; do
  OUT=$(GIT_TERMINAL_PROMPT=0 timeout 30 git ls-remote "$R" HEAD 2>&1); RC=$?
  printf '   %-38s rc=%-3s %s\n' "$R" "$RC" "$(printf '%s\n' "$OUT" | head -1 | cut -c1-70)"
done

echo
echo "== ② /tmp 里归我的那批"
for X in dsh_page.html w xz.log apt-lite.log entry-selftest.out; do
  if [ -e "/tmp/$X" ]; then
    if [ -f "/tmp/$X" ]; then SZ=$(wc -c < "/tmp/$X"); rm -f "/tmp/$X"; echo "   删文件 /tmp/$X（$SZ B）"; else echo "   留 /tmp/$X：不是普通文件（$(stat -c %F "/tmp/$X" 2>/dev/null)），不动"; fi
  else echo "   /tmp/$X 已不在"; fi
done
N=$(ls -d /tmp/dsh-entry-selftest-* 2>/dev/null | wc -l)
for D in /tmp/dsh-entry-selftest-*; do [ -e "$D" ] || continue; rm -rf "$D"; echo "   删目录 $D（deploy 自测每次重建的那个临时目录）"; done
echo "   自测临时目录删了 $N 个"
echo "-- 剩下的 13→$(ls -A /tmp 2>/dev/null | wc -l) 个，逐个说明是谁的："
for E in $(ls -A /tmp 2>/dev/null); do printf '   %-42s %s\n' "$E" "$(stat -c '%F %s B' "/tmp/$E" 2>/dev/null)"; done
echo "   （dsh-spill-* / dsh-subprocess-* / dsh-purge-desktop.log = 引擎与插件写的；node-compile-cache / node-addon-* / pnpm-store-* = node 与 pnpm 的缓存目录 ⇒ 都不动）"

echo
echo "== ③ 四批包：把 stderr 收回来，量下载量与占盘"
for spec in "文档办公|libreoffice-writer pandoc" "OCR|tesseract-ocr" "语言栈|rustc golang-go default-jdk" "容器|docker.io podman"; do
  LBL=${spec%%|*}; PKGS=${spec#*|}
  for MODE in "" "--no-install-recommends"; do
    RAW=$(apt-get -s install $MODE $PKGS 2>&1)
    N=$(printf '%s\n' "$RAW" | grep -c '^Inst ')
    GET=$(printf '%s\n' "$RAW" | grep -m1 'Need to get' | sed 's/.*Need to get //;s/ of archives.*//')
    AFT=$(printf '%s\n' "$RAW" | grep -m1 'After this operation' | sed 's/.*operation, //;s/ of additional.*//')
    printf '   %-10s %-22s 包数=%-4s 下载 %-14s 装完多占 %-12s\n' "$LBL" "${MODE:-含 recommends}" "$N" "${GET:-无}" "${AFT:-无}"
  done
done
echo "-- 已装与未装：dpkg 现在 $(dpkg -l 2>/dev/null | grep -c '^ii') 个包；apt 缓存 $(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1) / $(ls /var/cache/apt/archives/*.deb 2>/dev/null | wc -l) 个 .deb"
echo "-- 磁盘：$(df -h / | awk 'NR==2{print $4" 可用 / 共 "$2}')"

echo
echo "== ④ 这发留没留东西"
rm -f /tmp/p65-body /tmp/p65-err
echo "   /root/*.sh: $(ls /root/*.sh 2>/dev/null | wc -l)   /tmp 顶层: $(ls -A /tmp 2>/dev/null | wc -l)   p65 残留: $(ls /tmp/p65-* 2>/dev/null | wc -l)"
