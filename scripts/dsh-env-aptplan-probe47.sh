#!/usr/bin/env bash
# dsh-env-aptplan-probe47.sh —— 只读：装之前把"到底会动哪些包"量死（含 sources 用的哪个 host、有没有包会被升级）
#
# 为什么要单独这一发：探针 46 里 `apt-get -s install git` 打的是「1 upgraded, 26 newly installed」——
# 那 **1 个 upgraded 是盘上已有的包要被换版本**，不是新装。他不点头我们不动盘，但动了就得说清楚动的是谁。
# 这一发同时把安装用的 flags 钉成与下一步真装完全一致（`-y --no-install-recommends`），
# 这样"计划的数"与"装完新增的数"才允许相等（铁律 2：只认能当场重跑的数）。
set -u

echo "== 0. 时刻"
echo "  UTC  $(date -u '+%F %T')   北京 $(TZ=Asia/Shanghai date '+%F %T' 2>/dev/null)"

echo "== 1. apt 真源（Noble 用 deb822 那份，sources.list 是空的）"
echo "  /etc/apt/sources.list 生效行数 = $(grep -vc '^#\|^$' /etc/apt/sources.list 2>/dev/null)"
ls -1 /etc/apt/sources.list.d/ 2>/dev/null | sed 's/^/    sources.list.d\/|/'
awk 'NF && $1!~/^#/ {printf "    %s\n", $0}' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null | head -14
for h in mirrors.tuna.tsinghua.edu.cn ports.ubuntu.com archive.ubuntu.com security.ubuntu.com; do
  printf '    host %-30s hosts 命中 %s 行  getent = %s\n' "$h" "$(awk -v H=$h '$2==H' /etc/hosts | wc -l)" "$(getent hosts $h 2>/dev/null | head -1 | awk '{print $1}')"
done

echo "== 2. 清单新旧"
echo "  /var/lib/apt/lists 文件数 = $(ls -1 /var/lib/apt/lists 2>/dev/null | grep -vc '^partial$')，最旧一份改于 $(ls -1tr /var/lib/apt/lists 2>/dev/null | grep -v '^partial$' | head -1 | xargs -I{} stat -c %y /var/lib/apt/lists/{} 2>/dev/null | cut -d' ' -f2 | cut -d. -f1)，最新一份改于 $(ls -1t /var/lib/apt/lists 2>/dev/null | grep -v '^partial$' | head -1 | xargs -I{} stat -c %y /var/lib/apt/lists/{} 2>/dev/null | cut -d' ' -f2 | cut -d. -f1)"

echo "== 3. 合起来模拟一把（与真装同一组 flags，一个字节不写）"
apt-get -s install -y --no-install-recommends git python3 >/tmp/.p47plan 2>&1; RC=$?
echo "  rc=$RC"
grep -E 'upgraded,|newly installed|Need to get|After this operation' /tmp/.p47plan | sed 's/^/    /'
echo "  Inst 总行数 = $(grep -c '^Inst' /tmp/.p47plan)"
echo "  --- 其中【会被升级】的那些（apt 的形状是 Inst 名字 [旧版本]，新装的没有这一段）"
echo "      计数 = $(grep -cE '^Inst [^ ]+ \[' /tmp/.p47plan)"
grep -E '^Inst [^ ]+ \[' /tmp/.p47plan | sed 's/^/      /'
echo "  --- 全部 Inst 行原文（版本与来源都在，别只看名字）"
grep '^Inst' /tmp/.p47plan | sed 's/^/      /'
echo "  --- 下载体积（Need to get 那一行的原文就是口径）"
grep -E 'Need to get' /tmp/.p47plan | sed 's/^/      /'
cp /tmp/.p47plan /root/.dsh/aptplan-p47.txt 2>/dev/null && echo "  已把这份计划留到 /root/.dsh/aptplan-p47.txt（好让真装完能逐行比对）"
rm -f /tmp/.p47plan

echo "== 4. 装之前留一份「已装包名」快照（装完用它数新增）"
dpkg -l 2>/dev/null | awk '$1=="ii"{print $2}' | sort > /root/.dsh/dpkg-before-p47.txt
echo "  快照 = $(wc -l < /root/.dsh/dpkg-before-p47.txt) 行 / $(stat -c %s /root/.dsh/dpkg-before-p47.txt) B（改于 $(date -u '+%F %T') UTC）"
echo "  对比口径：装完把同一条 dpkg 再跑一遍存成 after，用 comm -13 数差集，与上面 newly installed 那个数比"

echo "== 5. 空间与内存（装完要复点同一组）"
df -k / | awk 'NR==2 {printf "  / 已用 %s KB 可用 %s KB\n", $3, $4}'
free -m | awk 'NR==2 {printf "  Mem total %s MiB used %s MiB available %s MiB\n", $2, $3, $7}'
echo " 完（探针 47 全只读：没 apt install、没写 /etc/hosts、没动服务）"
