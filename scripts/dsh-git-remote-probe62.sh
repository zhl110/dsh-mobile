#!/bin/bash
# dsh-git-remote-probe62.sh —— "git 装好了"不等于"git 在这台机上能用"；这一发把 git 分两层跑一遍。
#
# 触发：p60 第 4 节 gitee 那发 `git ls-remote` 回 rc=128 `could not read Username`（我挑的仓库路径压根不存在），
#       github 那发 rc=124 超时 ⇒ **git 的远端能力这轮没被证明**，只证明了"HTTP 层到 gitee 通"（404 / 7,187 B）。
#       他装 git 是为了让 DSH 跑复杂命令，所以这条要分两层各给读数：**本地工具链**与**网络远端**。
# 本地那层必做（不依赖外部）；远端那层拿候选公开仓库逐个问，第一个出 refs 的立刻 clone、复点、当场删。
# 不写 hosts、不改 git 全局配置（只在 /tmp 里建一个临时 HOME 级的 repo）、不装包。认证一律关掉。
set -u
export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false
echo "== 0 git 自己是谁 / 有没有脏的全局配置"
git --version
echo "  ~/.gitconfig 存在吗 : $(test -f /root/.gitconfig && echo 在 || echo 不在)   全局行数 : $(git config --global --list 2>/dev/null | wc -l)"
echo "  引擎与入口的 PATH 里有没有 git : $(grep -ao '/usr/bin/git' /proc/$(pgrep -f 'dsh web' | head -1)/environ 2>/dev/null | wc -l) 处（0 也可能是 environ 取不到，不作为结论）"

echo "== 1 本地工具链真跑一遍（建在 /tmp/p62-local，跑完删）"
rm -rf /tmp/p62-local; mkdir -p /tmp/p62-local && cd /tmp/p62-local || exit 1
git init -q -b main . 2>&1 | sed 's/^/    /'
printf 'hello\n' > a.txt && git add a.txt
git -c user.email=t@example.com -c user.name=probe commit -q -m 'first' && echo "    commit 1 ok"
printf 'world\n' >> a.txt && git -c user.email=t@example.com -c user.name=probe commit -qam 'second' && echo "    commit 2 ok"
git branch -q feature 2>/dev/null
printf '  HEAD        : %s\n' "$(git rev-parse --short HEAD)"
printf '  log --oneline: %s 条\n' "$(git log --oneline | wc -l)"
printf '  branches     : %s\n' "$(git branch --format='%(refname:short)' | tr '\n' ' ')"
printf '  diff HEAD~1  : %s 字节 / %s 行\n' "$(git diff HEAD~1 | wc -c)" "$(git diff HEAD~1 | wc -l)"
printf '  status       : %s 行（干净应为 0）\n' "$(git status --porcelain=v1 | wc -l)"
printf '  git ls-files : %s 个\n' "$(git ls-files | wc -l)"
printf '  gc + fsck    : %s\n' "$(git gc -q 2>&1; git fsck --no-progress 2>&1 | tail -1 | cut -c1-60)"
rm -rf /tmp/p62-local
echo "    /tmp/p62-local 还在吗 : $(test -e /tmp/p62-local && echo 在 || echo 不在)"
# ↓ 这一行是跑完第一次（读数 downloads/p62.txt）才补的：**删掉自己正站在的那个目录，cwd 就成了空洞**，
#   后面每一条 git 都回 `fatal: Unable to read current working directory`、rc=128、refs=0 ——
#   看着像"gitee 那五个仓库都拉不到"，其实一次网络都没发出去。取数错成这样必须重跑，不能拿 62 的 2、3 节当结论。
cd / || exit 1

echo "== 2 远端候选逐个问 refs（25 秒窗；仓库在不在另说，先拿到 rc 与错误文本）"
OKURL=""
for U in https://gitee.com/mirrors/git.git https://gitee.com/oschina/git-osc.git \
         https://gitee.com/mirrors/nginx.git https://gitee.com/mirrors/redis.git \
         https://gitee.com/paytm/paytm.git; do
  RAW=$(timeout 25 git ls-remote --heads "$U" 2>&1); RC=$?
  N=$(printf '%s\n' "$RAW" | grep -c 'refs/heads/')
  printf '  %-42s rc=%-3s refs=%-3s %s\n' "$U" "$RC" "$N" "$(printf '%s' "$RAW" | head -1 | cut -c1-56)"
  [ -z "$OKURL" ] && [ "$N" -gt 0 ] && OKURL=$U
done
# 挑 clone 对象时按体量排除：内核那种仓库 clone 一次几百 MB，这台机慢（20 几 KB/s）会把盘和时间都吃掉。
for X in linux gcc llvm; do case "$OKURL" in *"/$X.git") echo "  ⇒ clone 候选太大（$OKURL），只做 ls-remote，不 clone"; OKURL="";; esac; done
echo "  ⇒ 第一个真出 refs 的：${OKURL:-（一个都没有 —— 那这条判不了「能 clone」，只能判「问了没答」）}"

if [ -n "$OKURL" ]; then
  FREE=$(df -k / | awk 'NR==2{print $4}')
  echo "== 3 拿它做一次真 clone（--depth 1 → /tmp/p62-clone，复点后当场删）  / 可用 ${FREE} KB"
  [ "${FREE:-0}" -gt 2000000 ] || { echo "  !! 可用不足 2 GB，跳过 clone（不赌盘）"; OKURL=""; }
fi
if [ -n "$OKURL" ]; then
  rm -rf /tmp/p62-clone
  RAW=$(timeout 150 git clone --depth 1 "$OKURL" /tmp/p62-clone 2>&1); RC=$?
  printf '  clone rc=%s\n' "$RC"
  printf '%s\n' "$RAW" | tail -3 | sed 's/^/    /'
  if [ -d /tmp/p62-clone/.git ]; then
    echo "  复点（这一层才算「git 在这台机上能用」）："
    printf '    体量     : %s KB\n' "$(du -sk /tmp/p62-clone | cut -f1)"
    printf '    HEAD     : %s\n' "$(git -C /tmp/p62-clone rev-parse --short HEAD 2>&1)"
    printf '    log -1   : %s\n' "$(git -C /tmp/p62-clone log -1 --pretty='%h %ad %s' --date=iso 2>&1 | cut -c1-88)"
    printf '    ls-files : %s 个 / status %s 行改动\n' "$(git -C /tmp/p62-clone ls-files | wc -l)" "$(git -C /tmp/p62-clone status --porcelain=v1 | wc -l)"
    printf '    复杂命令链 : git log --oneline | wc -l = %s；grep -rIl 一个词命中 %s 个文件\n' \
      "$(git -C /tmp/p62-clone log --oneline | wc -l)" "$(grep -rIl 'license' /tmp/p62-clone 2>/dev/null | wc -l)"
  fi
  rm -rf /tmp/p62-clone
  echo "  清干净 : /tmp/p62-clone $(test -e /tmp/p62-clone && echo 还在!! || echo 不在)"
fi

echo "== 4 机上残留（本发只应留 runner 那份，跑完即删）"
echo "  /tmp 下 p62-* : $(ls -d /tmp/p62-* 2>/dev/null | wc -l)（应 0）   /tmp 下 dsh-* : $(ls -d /tmp/dsh-* 2>/dev/null | wc -l)"
