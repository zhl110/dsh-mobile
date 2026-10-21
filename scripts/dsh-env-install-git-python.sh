#!/usr/bin/env bash
# dsh-env-install-git-python.sh —— 他点名的那两件：在 chroot 里装上 git 与 python3（2026-10-21 晚他一句
# 「它需要安装 Git、安装 Python 3，然后才能够有效地去运行一些比较复杂的命令，这个需要你去解决一下」）。
#
# 这一支是**写盘**的，与探针不同，所以把话说死在三处：
#   ① 只装他点名的两个名字，flags 与探针 47 那次模拟完全一致（-y --no-install-recommends），
#      这样"计划里 newly installed 的 22"与"装完 dpkg 差集的数"才允许相等；不等就停下报数，不猜。
#   ② B 类清单里其余 20 多个名字（gcc/make/cmake/ffmpeg/unzip/tmux/pip3…）一个都不动 —— 铁律 7：装包要他点头，他点头的是两件。
#   ③ 装之前留 dpkg 快照与磁盘读数，装之后复点同一组；服务那一侧（引擎 pid、:3080、:3081）也复点，
#      用来证明这发 apt 没把跑着的东西带倒。
set -u
export DEBIAN_FRONTEND=noninteractive
TS=$(date -u +%Y%m%d-%H%M%S)
BEFORE=/root/.dsh/dpkg-before-$TS.txt
AFTER=/root/.dsh/dpkg-after-$TS.txt
PLAN_NEW=22          # 读数口径：downloads/p47.txt 第 3 节「1 upgraded, 22 newly installed」，Inst 行 23
LOG=/root/.dsh/apt-install-$TS.log

echo "== 0. 时刻与身份"
echo "  UTC  $(date -u '+%F %T')   北京 $(TZ=Asia/Shanghai date '+%F %T' 2>/dev/null)"
echo "  whoami=$(id -u) uid=$(id -un)  内核 $(uname -r)  chroot 里没 systemd（PID1=$(cat /proc/1/comm 2>/dev/null)）"

echo "== 1. 装之前留快照"
dpkg -l 2>/dev/null | awk '$1=="ii"{print $2}' | sort > "$BEFORE"
USED_BEFORE=$(df -k / | awk 'NR==2{print $3}')
USR_BEFORE=$(du -sk /usr 2>/dev/null | cut -f1)
echo "  快照 $BEFORE = $(wc -l < "$BEFORE") 行 / $(stat -c %s "$BEFORE") B"
echo "  df -k / 已用 = $USED_BEFORE KB   可用 = $(df -k / | awk 'NR==2{print $4}') KB   du -sk /usr = $USR_BEFORE KB"
ENGINE_PID_BEFORE=$(pgrep -f 'dsh web' | head -1)
echo "  引擎 pid（装之前）= ${ENGINE_PID_BEFORE:-空}   命中含 'dsh web' 的进程数 = $(pgrep -f 'dsh web' | wc -l)（要恰好 1）"

echo "== 2. 装（只装他点名的这两个名字）"
apt-get install -y --no-install-recommends git python3 >"$LOG" 2>&1; RC=$?
echo "  rc=$RC  日志 $LOG = $(stat -c %s "$LOG" 2>/dev/null) B"
echo "  --- 日志里 apt 自己那几行合计（原文照抄，不是我数的）"
grep -E 'upgraded,|newly installed|Need to get|After this operation' "$LOG" | sed 's/^/      /'
echo "  --- 有没有 E: / dpkg: error / 依赖没过"
grep -nE '^E: |^dpkg: |error:' "$LOG" | head -8 | sed 's/^/      /'
if [ "$RC" != "0" ]; then
  echo "  !! rc 非 0 —— 先试一发 apt-get update（清掉可能过期的清单）再重试一次，只重试这一次"
  apt-get update >"$LOG.update" 2>&1; URC=$?
  echo "     apt-get update rc=$URC，尾 3 行："
  tail -3 "$LOG.update" | sed 's/^/       /'
  apt-get install -y --no-install-recommends git python3 >>"$LOG" 2>&1; RC2=$?
  echo "     重试 rc=$RC2"
  [ "$RC2" = "0" ] || { echo "  !! 仍然失败，停在这里：没继续动别的东西，把日志带回去看"; exit 1; }
fi

echo "== 3. 三个数对账（铁律 2：计划 / 差集 / 逐个相加，不等就停）"
dpkg -l 2>/dev/null | awk '$1=="ii"{print $2}' | sort > "$AFTER"
NEW_CNT=$(comm -13 "$BEFORE" "$AFTER" | wc -l)
UP_CNT=$(comm -23 "$BEFORE" "$AFTER" | wc -l)
echo "  ① 模拟计划 newly installed = $PLAN_NEW（读数 p47.txt）"
echo "  ② 装完 dpkg 差集新增       = $NEW_CNT"
echo "  ③ 快照前后总数            = before $(wc -l < "$BEFORE") → after $(wc -l < "$AFTER")（差 = $(( $(wc -l < "$AFTER") - $(wc -l < "$BEFORE") ))）"
echo "  ④ 差集里【不是新增而是版本变了】的行数 = $UP_CNT（预期 1：perl-base 5.38.2-3.2ubuntu0.4 → .0.6）"
[ "$NEW_CNT" = "$PLAN_NEW" ] && echo "  [ok] ①=② 计划与实际一致" || echo "  !! ①≠②（$PLAN_NEW vs $NEW_CNT）—— 报数不猜，后面读数照常打但这一格算没过"
echo "  --- 新增的包名全列（逐行，自己数一遍等于 $NEW_CNT）"
comm -13 "$BEFORE" "$AFTER" | sed 's/^/      /'

echo "== 4. 装完复点（命令真在不在、版本、占了多少）"
for c in git python3 python pip3 gcc make; do
  printf '    %-8s command -v = %s\n' "$c" "$(command -v $c 2>/dev/null || echo 缺（预期：gcc/make/pip3 本来就不在这两件里）)"
done
echo "    git --version  → $(git --version 2>&1)"
echo "    python3 -V     → $(python3 -V 2>&1)"
echo "    python3 -c 一句 → $(python3 -c 'import sys,sqlite3,json;print(sys.version.split()[0], sqlite3.sqlite_version)' 2>&1)"
USED_AFTER=$(df -k / | awk 'NR==2{print $3}')
USR_AFTER=$(du -sk /usr 2>/dev/null | cut -f1)
echo "  df -k / 已用 = $USED_AFTER KB（比装之前多 $((USED_AFTER - USED_BEFORE)) KB ≈ $(( (USED_AFTER - USED_BEFORE) / 1024 )) MiB）"
echo "  du -sk /usr = $USR_AFTER KB（比装之前多 $((USR_AFTER - USR_BEFORE)) KB ≈ $(( (USR_AFTER - USR_BEFORE) / 1024 )) MiB）"

echo "== 5. 服务有没有被这发 apt 带倒（复点，不做任何重启）"
ENGINE_PID_AFTER=$(pgrep -f 'dsh web' | head -1)
echo "  引擎 pid 装之前=${ENGINE_PID_BEFORE:-空} 装之后=${ENGINE_PID_AFTER:-空}（同一个数才叫没被带倒）"
echo "  含 'dsh web' 的进程数 = $(pgrep -f 'dsh web' | wc -l)（要恰好 1）"
echo "  入口 pid = $(pgrep -f dsh-entry.js | head -1)  监听命中数 = $(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:(3080|3081)$/' | wc -l)"
printf '  :3080 GET / → %s\n' "$(curl -s -o /dev/null -m 8 -w '%{http_code} %{size_download}B' http://127.0.0.1:3080/ 2>&1)"
printf '  :3081 GET / → %s（未带 cookie 设计上就 404）\n' "$(curl -s -o /dev/null -m 8 -w '%{http_code} %{size_download}B' http://127.0.0.1:3081/ 2>&1)"
echo "  /etc/hosts 有没有被动（钉表生效行数）= $(grep -vc '^#\|^$' /etc/hosts)  备份件数 = $(ls -1 /root/.dsh/hosts.bak.* 2>/dev/null | wc -l)"

echo "== 6. 我留了什么在机上（新文件逐个列，都带时间戳，好删）"
ls -1 /root/.dsh/dpkg-before-$TS.txt /root/.dsh/dpkg-after-$TS.txt /root/.dsh/apt-install-$TS.log 2>/dev/null | sed 's/^/  /'
echo "  chroot /root 里 .sh 数 = $(ls -1 /root/*.sh 2>/dev/null | wc -l)"
echo " 完（这一支只装了 git 与 python3 两个名字，没动档位、没动 cordis、没重启引擎、没碰 hosts）"
