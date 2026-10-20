#!/system/bin/sh
# dsh-verify-perm-mode.sh — 只读：验「档位钉在 /root/.dsh-env 里」这条链真能通到 dsh
#
# 为什么要有这个脚本（2026-10-20 的两条实测教训）：
#   1) 三层引号（本地 bash → adb shell → su -c → chroot bash -lc）会把命令啃得不成人形：
#      同一轮里 $P 变量展开成空、cd 静默失败退回 / 根目录、printf %%s 打成字面 %s、
#      node -e 的双引号套嵌打出一句 NaN。全部是"读数看起来过了其实没跑对"的假通过。
#      规矩：凡是要往 chroot 里塞带引号的判断，一律写成脚本推上去跑。
#   2) 上游那句是 `process.env.DSH_PERMISSION_MODE ?? 'workspace-write'`——env 没设和
#      env 设成 workspace-write 算出来一模一样。所以只看最终值必然是假通过，
#      必须额外打一个「env 到没到手」的判别位（本脚本 T3 的 SET/UNSET）。
#
# 用法（root）：sh /data/local/sh/dsh-verify-perm-mode.sh
# 全程不碰在跑的 dsh 服务：只在 chroot 里另起一次性 bash/node 读数。
ROOTFS=/data/local/dsh-rootfs
ENV_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENVF=$ROOTFS/root/.dsh-env

say() { echo "$*"; }

[ -f "$ENVF" ] || say "!! $ENVF 不存在：这条链的第一步就断了"
say "--- 文件读数 ---"
ls -l "$ENVF" 2>&1
say "字节数=$(wc -c < "$ENVF" 2>/dev/null)  md5=$(md5sum "$ENVF" 2>/dev/null | cut -d' ' -f1)"
# CRLF 会让导出的值尾带 \r，插件加载时按非法档位报错、服务直接起不来
CR="$(printf '\r')"
if [ -n "$CR" ] && LC_ALL=C grep -q "$CR" "$ENVF" 2>/dev/null; then say "!! 文件里有 CR（Windows 换行），值会被污染"; else say "CR 检查：0（干净）"; fi
say "里面生效的 export 行：$(grep -cE '^export ' "$ENVF" 2>/dev/null) 条"
grep -E '^export ' "$ENVF" 2>/dev/null | sed 's/^/    /'

IN() { chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH="$ENV_PATH" /bin/bash -lc "$1"; }

say "--- T1 对照：不 source 这个文件（= 今天 07:00 之前活着的 10150 的状态） ---"
say "    env 里 DSH_PERMISSION_MODE 命中条数 = $(IN 'env | grep -c DSH_PERMISSION_MODE')"

say "--- T2 source 之后：值原样露出来（cat -A 会把 CR 打成 ^M、行尾打成 \$） ---"
IN '. /root/.dsh-env; env | grep DSH_PERMISSION_MODE | cat -A' | sed 's/^/    /'
say "    source 返回码=$(IN '. /root/.dsh-env; echo rc=$?')"

say "--- T3 判别位：env 到底到手没（缺这一段就等于假通过） ---"
IN 'A=$(env | grep -c ^DSH_PERMISSION_MODE=); . /root/.dsh-env; B=$(env | grep -c ^DSH_PERMISSION_MODE=); echo "source 前=$A source 后=$B"' | sed 's/^/    /'

say "--- T4 子进程继承：exec dsh web 吃的就是这一层 ---"
IN '. /root/.dsh-env; exec env | grep DSH_PERMISSION_MODE' | sed 's/^/    /'

say "--- T5 上游那句表达式在两棵树下的算法结果（SET/UNSET 必须分得开） ---"
say "    不 source（应判 UNSET）："
IN 'node -e "console.log(process.env.DSH_PERMISSION_MODE ? String(process.env.DSH_PERMISSION_MODE) : String(undefined))"' | sed 's/^/      /'
say "    source 之后（应判出钉的值）："
IN '. /root/.dsh-env; node -e "console.log(process.env.DSH_PERMISSION_MODE ? String(process.env.DSH_PERMISSION_MODE) : String(undefined))"' | sed 's/^/      /'

say "--- T6 顺带把上游真源那两行再读一遍（证明机制不是我编的） ---"
BP=$ROOTFS/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-base/cordis.patch.yml
grep -n "DSH_PERMISSION_MODE" "$BP" 2>/dev/null | sed 's/^/    /' || say "    !! 读不到 $BP"

say "--- T7 现在这个服务（不重启就还是老 env，钉的值要等下次拉起才生效） ---"
P=$(cat "$ROOTFS/root/dsh.pid" 2>/dev/null)
if [ -n "$P" ] && [ -d "/proc/$P" ]; then
  say "    pid=$P 活着；它的 exec 时 env 里 DSH_PERMISSION_MODE 命中条数=$(tr '\0' '\n' < "/proc/$P/environ" | grep -c DSH_PERMISSION_MODE)"
  say "    （0 是预期的：这个 pid 在本文件创建之前就已经 exec 了）"
else
  say "    !! pidfile 里没有活进程"
fi
say "    :3080 还在听吗：$(ss -lnt 2>/dev/null | grep -c ':3080')"
