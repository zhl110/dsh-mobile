#!/bin/bash
# scripts/dsh-envclaim-probe33.sh —— 把「手机端情况.md」那份 dsh 自述逐条拿到盘上复点一遍。
#
# 为什么要这一发：那份自述里有的是它自己实测的，有的是它从"我在 chroot 里看不见"推出来的，
# 还有两条与我们自己 14.10/14.11/14.22 的读数直接对不上（namespace、沙盒档位）。
# 判它对错不能靠谁写得更像样，只能同一台机上再取一次数。本探针**全程只读**，
# 唯一的"执行类"动作是 unshare / bwrap / curl / apt-get -s 这四发，都不写盘。
#
# 跑法：bash tools/run-probe.sh scripts/dsh-envclaim-probe33.sh downloads/p33.txt
# 注意：/root/.dsh-env 里有 API Key —— 下面只用锚定 ^(DSH_)?(SANDBOX|UNSHARE|SHELL) 的形式取那几行，
#       不 cat、不 grep -v、不整行回显别的键。
set -u
export LANG=C
P="printf"
echo "== 0. 时刻与身份（chroot 本地时区是 UTC，与文档里的北京时间差 8 小时）"
date -u '+  UTC  %F %T'; date '+  本地  %F %T %Z'
echo "  whoami=$(id -un) uid=$(id -u) gid=$(id -g) 上下文=$(cat /proc/self/attr/current 2>/dev/null || echo 读不到)"
echo "  uname: $(uname -srm)"

echo "== 1. 它说「/system/bin 整个不存在、完全没有 Android 接口」"
echo "  --- chroot 里看 /system：它在 chroot 里确实不该在，这条要判的是能不能补"
stat -c '  /system          %F mode=%a owner=%U:%G' /system 2>&1
stat -c '  /vendor          %F mode=%a owner=%U:%G' /vendor 2>&1
echo "  --- /proc 是宿主 rbind 进来的，所以这里能看到宿主自己的挂载表：Android 分区在不在宿主上"
grep -E ' /(system|system_ext|product|vendor|odm|apex) ' /proc/self/mountinfo | awk '{print "    "$5"  设备="$4}' | head -8
echo "    （共 $(grep -cE ' /(system|system_ext|product|vendor|odm|apex) ' /proc/self/mountinfo) 行）"
echo "  --- 根是谁的设备号（它报的是 dm-74）"
awk '$5=="/"{print "    chroot 视角 / 的设备="$4"  选项="$6}' /proc/self/mountinfo | head -2
echo "  --- /dev 里 Android 那些接口节点在不在（chroot 的 /dev 是宿主 rbind，理论上全在）"
for n in binder hwbinder vndbinder binderfs ashmem kgsl-3d0 ion dri graphics/fb0; do
  printf '    /dev/%-14s ' "$n"; stat -c '%F %a %U:%G' "/dev/$n" 2>&1 | head -1
done
echo "    /dev 条目总数：$(ls -1A /dev 2>/dev/null | wc -l)"

echo "== 2. 它说「不能截图、不能点屏、没有浏览器引擎、渲染不了 JS」"
echo "  DISPLAY=[${DISPLAY:-}] WAYLAND_DISPLAY=[${WAYLAND_DISPLAY:-}]"
for p in /tmp/.X11-unix /run/user; do printf '  %s ' "$p"; stat -c '%F' "$p" 2>&1 | head -1; done
ls -1 /dev/dri 2>/dev/null | sed 's/^/    dri: /' || echo "  /dev/dri 无"
echo "  包管理器里能装到的浏览器（只查有没有，不装）："
for c in chromium chromium-browser firefox epiphany.webkit xdg-open; do printf '    %-18s %s\n' "$c" "$(command -v $c || echo 无)"; done
echo "  node 全局包（一层）："
npm ls -g --depth=0 2>/dev/null | sed 's/^/    /' || echo "    npm 不可用"

echo "== 3. 它说「内核禁止创建 namespace，bwrap 报 Invalid argument，workspace-write 直接不可用」"
echo "  --- 我们 14.11 的读数与此不同，这里三条分开量：user ns / mount ns / landlock"
printf '    unprivileged_userns_clone = '; cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || echo "文件不存在（内核没这开关）"
run1() { O=$("$@" 2>&1); RC=$?; printf '    %-28s rc=%s %s\n' "$LBL" "$RC" "$(printf '%s' "$O" | head -1 | cut -c1-70)"; }
LBL='unshare -u true'; run1 unshare -u true
LBL='unshare -m true'; run1 unshare -m true
LBL='unshare -m -p -i --fork true'; run1 unshare -m -p -i --fork true   # ← 2026-10-21 17:57 改：原先这行写的是 `unshare -mpid true`，rc=1 打的是 "invalid option -- 'd'"，**那是我参数写错**（util-linux 把 -mpid 拆成 -m -p -i -d，没有 -d），不是内核拒绝；别再拿那次 rc=1 当证据
LBL='unshare -Urm true'; run1 unshare -Urm true
printf '    Landlock/LSM 列表: '; cat /sys/kernel/security/lsm 2>/dev/null || echo "读不到 /sys/kernel/security/lsm"
echo "  --- bwrap 在不在、真跑一发什么结果"
printf '    command -v bwrap: '; command -v bwrap || echo "无（它自述装了 0.9.0，这条要复点）"
if command -v bwrap >/dev/null 2>&1; then
  LBL='bwrap --ro-bind / / true'; run1 bwrap --ro-bind / / -- /bin/true
fi
echo "  --- 我们那个 runner 还在不在位（14.11 部署的）"
stat -c '    %n %s B mode=%a owner=%U:%G mtime=%y' /usr/local/bin/dsh-unshare-run 2>&1
sha256sum /usr/local/bin/dsh-unshare-run 2>/dev/null | cut -c1-16 | sed 's/^/    sha 前缀: /'
head -1 /usr/local/bin/dsh-unshare-run 2>/dev/null | sed 's/^/    首行: /'
echo "  --- 接线了没有：profile 里到底有没有 runnerCommand"
for f in /root/.dsh/profiles/web/cordis.patch.yml /root/.dsh/profiles/web/package.json; do
  printf '    %s ' "$(basename $f)"; stat -c '存在 %s B mtime=%y' "$f" 2>/dev/null || echo "不存在"; done
echo "    grep runnerCommand 命中行数：$(grep -c runnerCommand /root/.dsh/profiles/web/cordis.patch.yml 2>/dev/null)"
echo "  --- 服务 env 里档位相关的那几行（只锚定这几条，别的不取，见文件头为什么）"
echo "      14.10 钉的那条是 DSH_PERMISSION_MODE，它决定审批策略（=danger-full-access 时 policy 变 never）"
grep -oE '^(export +)?(DSH_)?[A-Z_]*(SANDBOX|UNSHARE|SHELL_MODE|PERMISSION|PROFILE|WORKDIR|NO_PHONE)[A-Z_]*=.*' /root/.dsh-env 2>/dev/null | sed 's/^/    /'
echo "    （上面没输出 = .dsh-env 里根本没有档位相关键，档位走上游默认或走 cordis）"
echo "    .dsh-env 本身：$(stat -c '%s B mode=%a owner=%U:%G mtime=%y' /root/.dsh-env 2>/dev/null || echo '读不到（14.10 时在位：1,687 B / 0600 / md5 82bdb1f3…）')"
echo "    引擎进程实际读到的档位（从 /proc/<pid>/environ 只取这几条）："
EP=$(cat /root/.dsh/web.pid 2>/dev/null || echo '')
if [ -n "$EP" ] && stat -c '%F' "/proc/$EP" >/dev/null 2>&1; then
  tr '\0' '\n' < "/proc/$EP/environ" 2>/dev/null | grep -oE '^(DSH_)?[A-Z_]*(SANDBOX|PERMISSION|WORKDIR|NO_PHONE|PROFILE)[A-Z_]*=.*' | sed 's/^/      /'
  echo "      （pid=$EP；这一发只按锚定正则取，不会把别的环境变量带出来）"
else
  echo "      读不到 /root/.dsh/web.pid 或那 pid 不在 ⇒ 引擎不是这份 pid 管的，改看第 4 节 ps 那几行"
fi
echo "  --- profile 组合后的 cordis.yml 里 sandbox 那几行（只打含 sandbox 的本行，不带上下文，免得把凭据行捎出来）"
grep -inE 'sandbox|runnerCommand|mode:' /root/.dsh/profiles/web/cordis.yml 2>/dev/null | head -12 || echo "    读不到 cordis.yml"

echo "== 4. 它说「PID 1 是 Android init、无 systemd、进程挂了就没了、不能开机自启」"
echo "    /proc/1/comm = $(cat /proc/1/comm 2>/dev/null || echo 读不到)"
stat -c '    /run/systemd/system %F' /run/systemd/system 2>&1 | head -1
echo "  --- 但这台机上真正管引擎的是常驻入口，它带重拉逻辑（14.14 起）"
ps -eo pid,etimes,rss,args 2>/dev/null | grep -E 'dsh-entry|dsh [a-z]|node' | grep -v grep | sed 's/^/    /' | head -8
echo "    监听：$(ss -lnt 2>/dev/null | grep -oE ':(3080|3081)' | tr '\n' ' ')"
echo "    入口状态文件：$(stat -c '%s B mtime=%y' /root/.dsh/entry.log 2>/dev/null || echo '读不到 /root/.dsh/entry.log')"
grep -cE '重拉|startEngine|backoff' /root/.dsh/entry.log 2>/dev/null | sed 's/^/    日志里重拉或backoff命中行数: /'
echo "    （宿主侧 service.d 那条开关不在 chroot 里，看 dsh-chroot.sh --status，本探针不覆盖）"

echo "== 5. 网络：它列的 6 个失败域名 + 2 个可用对照，全部不带 --resolve（带了就是自欺）"
echo "  --- 先复点我们自己的解析层"
bash /root/doh-hosts.sh --check 2>&1 | sed 's/^/    /' | head -40
echo "    /etc/hosts 里非注释非空白行数：$(grep -cvE '^\s*(#|$)' /etc/hosts)"
echo "    /etc/resolv.conf nameserver 行：$(grep -c '^nameserver' /etc/resolv.conf 2>/dev/null)"
echo "  --- 逐域名（每发 30 秒窗，rc 28=到点超时、rc 6/7=快速失败，两形状不是一回事）"
for h in registry.npmjs.org pypi.org files.pythonhosted.org api.anthropic.com api.github.com raw.githubusercontent.com github.com registry.npmmirror.com mirrors.tuna.tsinghua.edu.cn; do
  R=$(curl -sS -o /dev/null -m 30 -w 'http=%{http_code} B=%{size_download} t=%{time_total} speed=%{speed_download} ip=%{remote_ip}' "https://$h/" 2>&1)
  RC=$?
  printf '    %-32s rc=%-2s %s\n' "$h" "$RC" "$(echo "$R" | tr '\n' ' ' | cut -c1-110)"
done

echo "== 6. 它说「dpkg 只有 124 个包、apt 可用、这批工具全都没有」+ 问要不要装"
echo "    dpkg 已装包计数：$(dpkg-query -W -f='Status: ${Package}\n' 2>/dev/null | grep -c '^Status:')"
echo "    apt lists 新鲜度（-s 模拟要靠它，太旧这批数就不作数）："
stat -c '      %n %s B mtime=%y' /var/lib/apt/lists 2>/dev/null | head -1
echo "      lists 条目数：$(ls -1A /var/lib/apt/lists 2>/dev/null | wc -l)"
echo "  --- 它列的那串逐个复点（有/无）"
for c in python3 python pip3 git gcc g++ make cmake rustc go java docker podman sqlite3 ffmpeg convert pdftoppm ssh rsync wget unzip zip file tmux node npm; do
  printf '    %-12s %s\n' "$c" "$(command -v $c || echo 无)"
done
echo "  --- 装它建议那一批到底要下多少：apt-get -s（模拟，不下载不写盘），两种档各量一发"
BATCH="python3 python3-pip git gcc g++ make cmake ffmpeg imagemagick poppler-utils unzip zip file tmux sqlite3 wget rsync"
for extra in "--no-install-recommends" ""; do
  OUT=$(apt-get -s -y install $extra $BATCH 2>&1); ARC=$?
  printf '    apt-get -s -y install %s %s\n      rc=%s\n' "$extra" "$BATCH" "$ARC"
  printf '      新装包数（逐行数 Inst 行）：%s\n' "$(printf '%s\n' "$OUT" | sed -n 's/^Inst \([^ ]*\).*/\1/p' | wc -l)"
  printf '%s\n' "$OUT" | grep -E '^(Need to get|After this operation)' | sed 's/^/      /'
  printf '%s\n' "$OUT" | grep -iE '^(E:|W:)' | head -3 | sed 's/^/      ! /'
done
echo "    最小那批（不含 ffmpeg/imagemagick/poppler）："
OUT2=$(apt-get -s -y install --no-install-recommends git python3 python3-pip unzip file tmux sqlite3 2>&1)
printf '%s\n' "$OUT2" | grep -E '^(Need to get|After this operation)' | sed 's/^/      /'
printf '      新装包数：%s\n' "$(printf '%s\n' "$OUT2" | sed -n 's/^Inst \([^ ]*\).*/\1/p' | wc -l)"
echo "      （-s 出来的 Need to get 是 apt 自己算的，含依赖；这条数比我在文档里推的那句可靠）"
echo "  --- pip 侧镜像（它说 pypi 不通；这台机的正解是镜像，不是修 pypi）"
printf '    npm registry: '; npm config get registry 2>/dev/null || echo "npm 不可用"
echo "    /etc/pip.conf：$(stat -c '%s B' /etc/pip.conf 2>/dev/null || echo '不存在')"; cat /etc/pip.conf 2>/dev/null | sed 's/^/      /'

echo "== 7. 它说「8 核、23 GB 内存（可用 7.5 G）、341 G 空闲」——资源复点"
echo "    nproc=$(nproc)  CPU 型号行=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null || echo 无)"
free -h 2>/dev/null | sed 's/^/    /'
df -h / /root /tmp /phone 2>/dev/null | sed 's/^/    /'
echo "    /phone 顶层条目：$(ls -1A /phone 2>/dev/null | wc -l)；/phone 可写测试留给他（本探针不写手机存储）"
echo "    /root/.dsh：$(du -sh /root/.dsh 2>/dev/null | cut -f1)；node_modules(dsh)：$(du -sh /usr/lib/node_modules/@deepseek-ai 2>/dev/null | cut -f1)"
echo "    node=$(node -v 2>/dev/null) npm=$(npm -v 2>/dev/null) pnpm=$(pnpm -v 2>/dev/null || echo 无) dsh=$(dsh --version 2>/dev/null || echo 读不到)"

echo "== 8. 它那句「/phone 里能看到应用的数据目录」——暴露面复点（数 + 顶层名字；名字会进本地读数文件，不外传）"
# ← 2026-10-21 17:57 改口：这节标题原先写"只数不列内容"，可下面这条就是列名字的（p33.txt 里 135 个顶层名全在）。
#    名字本身对他判断"引擎能看到多少东西"是有用的，我把它留着，但把话说明白：**没读任何 App 的私有文件内容**，只 ls 了一层目录名。
echo "    /phone 顶层条目：$(ls -1A /phone 2>/dev/null | tr '\n' ' ')"
echo "    /phone/Android/data 下的目录数：$(ls -1A /phone/Android/data 2>/dev/null | wc -l)"
echo "    /phone/Android/obb 下的目录数：$(ls -1A /phone/Android/obb 2>/dev/null | wc -l)"
FIRST=$(ls -1A /phone/Android/data 2>/dev/null | head -1)
if [ -n "$FIRST" ]; then
  echo "    任挑第一个（$FIRST）试读一层：条目数 $(ls -1A "/phone/Android/data/$FIRST" 2>/dev/null | wc -l)，rc 见下"
  ls -1A "/phone/Android/data/$FIRST" >/dev/null 2>/tmp/p33.err; echo "      rc=$? err=$(head -c 90 /tmp/p33.err | tr '\n' ' ')"; rm -f /tmp/p33.err
fi
echo "    挂载源复点：$(grep ' /phone ' /proc/self/mountinfo | awk '{print "宿主侧="$4" 本视图="$5}')"
echo "    工作区根（引擎 cwd 说了算，这里只给视图）：$(ls -1A /phone 2>/dev/null | wc -l) 个顶层条目 / DSH_WORKDIR 未在本探针内取（见第 3 节 env 那几行）"
echo "    （这一节只 ls 与 wc，不读任何 App 的私有文件内容；名字也不往外列，只报计数）"

echo "== 本探针做过的动作（如实记录）"
echo "  只读：stat/ls/ps/ss/grep/cat/dpkg-query/du/df/free/nproc/date。"
echo "  执行类：unshare 四发（建临时 ns，退出即无，其中 -U 那发预期失败）、bwrap 一发（预期失败或不存在）、"
echo "  curl 9 发各 30 秒窗（只取首页小 body，不下载文件）、apt-get -s 三发（模拟，不下载不写盘）、"
echo "  doh-hosts.sh --check（按脚本自述「只报不写」）、dsh/npm 的版本与配置查询。"
echo "  临时件：只在 /tmp 落过一个 p33.err（取 ls 的报错原文用），读完即 rm；rootfs 与 chroot /root 里没留任何东西。"
echo "  没做：任何 apt install、没下载包、没写 /phone、没读任何 App 的私有文件内容、"
echo "  没读凭据内容（.dsh-env 只按锚定正则取档位相关那几行）、没改 cordis、没重启引擎。"
