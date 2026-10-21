#!/bin/bash
# dsh-tmp-hygiene61.sh —— 清掉**我自己**在 chroot /tmp 里留的一次性件，并当场把"删了哪些、留下哪些、为什么留下"打出来。
#
# 为什么这一发不是只读：前面几发探针（p56 第 6 节、p58 第 6 节）量出 /tmp 里挂着 33 个 dsh-* 东西，
# 逐个核过名字与来历，只有三类是我建的：`dsh-entry-selftest-<pid>/`（我跑 --selftest 时 TMPDIR 指的目录，每个里就一份 221 B 的 entry.log 副本）、
# `dsh-devnull-inner.sh`（沙箱探针的内层件）、`dsh-entry-check-page.html` / `-clean.html`（我抓真首页做字节对账的临时落盘，对账结果已在 downloads/）。
# **明确不碰**：`dsh-subprocess-*`、`dsh-spill-*` 是引擎/插件自己在跑的临时目录，`dsh-purge-desktop.log` 刚在 12:56 还被写过（14 KB，是插件写的日志不是我）。
# 判据用白名单，不用通配删除：只删 /tmp/dsh- 开头且**逐条 print 出来**的路径，路径不在 /tmp 一律跳过。
set -u
echo "== 1 删之前"
echo "  /tmp 下 dsh-* 计数 : $(ls -d /tmp/dsh-* 2>/dev/null | wc -l)   /tmp 总占用 : $(du -sh /tmp 2>/dev/null | cut -f1)"

echo "== 2 逐个删（白名单三族，删前打印每一个）"
N=0
for P in /tmp/dsh-entry-selftest-* /tmp/dsh-devnull-inner.sh /tmp/dsh-entry-check-page.html /tmp/dsh-entry-check-clean.html; do
  [ -e "$P" ] || continue
  case "$P" in
    /tmp/dsh-*) ;;
    *) echo "  !! 路径不对，跳过：$P"; continue ;;
  esac
  echo "  删 $(ls -ld "$P" | awk '{print $1, $5, $6, $7, $8}')  $(basename "$P")"
  rm -rf --one-file-system "$P" && N=$((N+1))
done
echo "  合计删掉 $N 项"

echo "== 3 删之后（留下的必须逐个说明归属）"
echo "  /tmp 下 dsh-* 计数 : $(ls -d /tmp/dsh-* 2>/dev/null | wc -l)   /tmp 总占用 : $(du -sh /tmp 2>/dev/null | cut -f1)"
for P in /tmp/dsh-*; do
  [ -e "$P" ] || continue
  printf '   留下 %-28s %8s B  %s\n' "$(basename "$P")" "$(du -sk "$P" 2>/dev/null | cut -f1)" "$(ls -ld "$P" | awk '{print $6,$7,$8}')"
done
echo "   —— 留下的一律不是我建的（引擎 subprocess / 插件 spill / 插件日志），要清得他点头。"

echo "== 4 顺带复点：更新后的 doh-hosts.sh 在机上认得新加的那条 WATCH（只读，不写 hosts）"
md5sum /root/doh-hosts.sh | awk '{print "  机上 md5 :", $1}'
bash /root/doh-hosts.sh --check 2>/dev/null | awk '/清单里还没钉的/,0' | grep -E 'gh-proxy|npmjs|jsdelivr' | sed 's/^/ /'
echo "  hosts 生效行数 : $(awk '!/^[[:space:]]*#/ && NF>=2' /etc/hosts | wc -l)"

echo "== 5 这发自己有没有留东西"
echo "  /root 下 .sh 计数（跑完 runner 会删掉本探针）: $(ls /root/*.sh 2>/dev/null | wc -l)"
