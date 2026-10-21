#!/usr/bin/env bash
# dsh-pyjs-mirror-setup54.sh —— 把这轮刚装上的 pip 与 npm 接到这台机**走得通**的那两扇门上，并当场拿真字节证明走得通。
#
# 为什么要这一发：《手机端情况.md》A 类第 14 行写着 `registry.npmjs.org`、`pypi.org`、`files.pythonhosted.org`
# 全部解析/连接失败，而 B 类那句"能补"默认了装了 pip 就装得了包 —— 装得上但下不动，等于没补。
# 这台机上能落字节的只有清华/阿里镜像与 npmmirror（读数：tools/doh-hosts.sh 头部那段与 downloads/p28/p31/p43）。
# 所以这里做的不是"修外网"，是把**默认源**换成能通的那一个 —— 两行配置，全在 chroot 里，随时可删。
#
# 只写两个文件，都先备份、都带时间戳，删掉就恢复原样：
#   /root/.config/pip/pip.conf   （不存在 ⇒ 备份记「原本没有」，退回就是 rm）
#   npm 的全局 registry          （npm config delete registry 可退）
# 其余一律不动：不 pip install 任何包进系统、不 npm install 任何包、不改档位、不重启、不碰 hosts。
set -u
TS=$(date -u +%Y%m%d-%H%M%S)
PIP=/root/.config/pip/pip.conf
PIP_BAK_NOTE=""
MIRROR_PY=https://pypi.tuna.tsinghua.edu.cn/simple
MIRROR_JS=https://registry.npmmirror.com

echo "== 0. 时刻"
echo "  UTC  $(date -u '+%F %T')   北京 $(TZ=Asia/Shanghai date '+%F %T')（这台机 chroot 是 UTC）"

echo "== 1. 配之前的现场（先看清是不是真的没配，别把已有的当成我写的）"
echo "  pip 配置文件 = ${PIP}：$(test -e "$PIP" && echo "在，$(stat -c %s "$PIP") B" || echo 不存在)  —— 全局那份 $(test -e /etc/pip.conf && echo 在 || echo 不存在)"
echo "  pip 现用 index：$(pip config get global.index-url 2>&1 | head -1)"
echo "  npm 现用 registry：$(npm config get registry 2>&1 | head -1)（npm $(npm -v) / node $(node -v)）"
echo "  这两家在 hosts 里钉没钉（不带 --resolve，解析不通就是死）："
for h in pypi.tuna.tsinghua.edu.cn registry.npmmirror.com pypi.org files.pythonhosted.org registry.npmjs.org; do
  printf '    %-34s hosts 里=%s  getent=%s\n' "$h" \
    "$(grep -cE "[[:space:]]$h\$" /etc/hosts)" \
    "$(getent hosts "$h" 2>/dev/null | awk '{print $1" "$2}' | head -1 || echo 空)"
done

echo "== 2. 写 pip 的镜像配置（原本不存在 ⇒ 退回就是删这个文件）"
mkdir -p "$(dirname "$PIP")"
if test -e "$PIP"; then cp -p "$PIP" "$PIP.bak-$TS" && PIP_BAK_NOTE="$PIP.bak-$TS"; fi
cat > "$PIP" <<EOF
# 2026-10-21 由 dsh-mobile 项目写入（探针 54）。这台机上 pypi.org 与 files.pythonhosted.org
# 解析与连接都失败（《手机端情况.md》A 类），清华源与 apt 用的是同一台已钉好的主机，实测落字节。
# 退回：rm -f $PIP   （原本这文件不存在；备份 = ${PIP_BAK_NOTE:-无}）
[global]
index-url = $MIRROR_PY
trusted-host = pypi.tuna.tsinghua.edu.cn
EOF
echo "  写了 $(stat -c %s "$PIP") B，md5 $(md5sum "$PIP" | cut -d' ' -f1)"
echo "  pip config get global.index-url → $(pip config get global.index-url 2>&1 | head -1)"

echo "== 3. 写 npm 的镜像配置"
npm config set registry "$MIRROR_JS" >/dev/null 2>&1
echo "  npm config get registry → $(npm config get registry 2>&1 | head -1)（退回：npm config delete registry）"

echo "== 4. 真下东西（判「通」只认落字节，不认 200 —— 这是这项目的铁律 4）"
TMP=/root/.dsh/mirror-probe-$TS
mkdir -p "$TMP"
echo "  --- pip：download 一个纯 python 小包（只下载不安装，装不装他说了算）"
timeout 90 pip download --no-deps -d "$TMP" requests >"$TMP/pip.log" 2>&1; RC=$?
echo "      rc=$RC  下到的文件："
ls -1 "$TMP" 2>/dev/null | grep -v pip.log | sed 's/^/        /'
echo "      合计 $(du -sk "$TMP" 2>/dev/null | cut -f1) KB，日志尾 2 行："
tail -2 "$TMP/pip.log" | sed 's/^/        /'
echo "  --- pip 那条 PEP 668 的坎（Ubuntu 24.04 的系统 python 不让你直接 pip install）：原话照抄"
pip install --dry-run requests 2>&1 | head -12 | sed 's/^/        /'
echo "  --- npm：view 元数据 + pack 一个 tarball"
timeout 40 npm view zod version 2>&1 | head -2 | sed 's/^/      npm view zod version → /'
timeout 90 npm pack zod@3 --pack-destination "$TMP" >"$TMP/npm.log" 2>&1; RC2=$?
echo "      npm pack rc=$RC2  下到的文件：$(ls -1 "$TMP" 2>/dev/null | grep -E '^zod.*tgz$' | tr '\n' ' ')"
tail -2 "$TMP/npm.log" | sed 's/^/        /'

echo "== 5. 清掉下载件（配置留着，下载的东西不留）"
BEFORE=$(du -sk "$TMP" 2>/dev/null | cut -f1)
rm -rf "$TMP"
echo "  删了 $TMP（之前 $BEFORE KB），残留 = $(test -e "$TMP" && echo 还在 || echo 没了)"

echo "== 6. 服务复点（这发只写了两个配置文件，不该有任何换代）"
echo "  引擎 pid = $(pgrep -f 'dsh web' | head -1)（要仍是 21363）  含 'dsh web' 进程数 = $(pgrep -f 'dsh web' | wc -l)"
echo "  hosts 生效行数 = $(grep -vc '^#\|^$' /etc/hosts)（要仍是 28 —— 本支不动解析）"
echo "  dpkg ii 计数 = $(dpkg -l 2>/dev/null | awk '$1=="ii"' | wc -l)（要仍是 411，本支没装包）"
echo " 完（写了 pip.conf 与 npm registry 两行配置、下过两发真字节又删干净；没装包、没动 hosts、没重启、没 pip/npm install 进系统）"
