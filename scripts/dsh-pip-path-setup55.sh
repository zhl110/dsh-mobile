#!/usr/bin/env bash
# dsh-pip-path-setup55.sh —— 把 pip 这条路真正打通：先钉域名，再拿真字节证明装得下来，顺带量清 PEP 668 那三条路各省多少包。
#
# 上一发（探针 54，读数 downloads/p54.txt）的形状是"工具装了、门没开"：
#   index-url 指到清华 pypi 之后 `pip download requests` 仍回 (from versions: none)，
#   同一条里 getent 对 pypi.tuna.tsinghua.edu.cn 给空、hosts 里计数 0 ⇒ 坏在解析，不坏在镜像。
# 这一发就补这一步：① 用本项目的 doh-hosts.sh --sync 把它钉上（自带逐字节备份与 --revert）；
# ② 不带 --resolve 再下一遍真字节 —— 只认 200 不算通，这是铁律 4；
# ③ PEP 668 那条 externally-managed 的坎（54 第 4 节原文抄到了）给三条走法各量一个数，让他一句话挑，我不替他选。
#
# 写盘的只有两处：/etc/hosts（--sync 自己备份，退回一条命令）与 /root/.dsh 下一个用完就删的临时目录。
# 不装任何包、不动档位、不重启、不动 npm 那侧（npm 已实测通：54 第 4 节 npm pack 落 604 KB）。
set -u
DOH=/root/doh-hosts.sh
KEY=/root/.dsh/entry.key

echo "== 0. 时刻"
echo "  UTC  $(date -u '+%F %T')   北京 $(TZ=Asia/Shanghai date '+%F %T')（chroot 是 UTC）"
echo "  doh-hosts.sh 在位 = $(test -e "$DOH" && echo "在，$(stat -c %s "$DOH") B，md5 $(md5sum "$DOH" | cut -d' ' -f1 | cut -c1-12)" || echo 不在！)"
echo "  清单里有没有 pypi.tuna 这一条 = $(grep -c 'pypi.tuna.tsinghua.edu.cn' "$DOH" 2>/dev/null)（要 1，没有说明设备上那份是旧的）"

echo "== 1. 钉之前：解析层读数"
printf '  %-34s hosts=%s getent=%s\n' pypi.tuna.tsinghua.edu.cn "$(grep -cE '[[:space:]]pypi\.tuna\.tsinghua\.edu\.cn\$' /etc/hosts)" "$(getent hosts pypi.tuna.tsinghua.edu.cn 2>/dev/null | awk '{print $1}' | head -1 | sed 's/^$/空/')"
printf '  %-34s hosts=%s getent=%s（对照：apt 用的那台，一直通）\n' mirrors.tuna.tsinghua.edu.cn "$(grep -cE '[[:space:]]mirrors\.tuna\.tsinghua\.edu\.cn\$' /etc/hosts)" "$(getent hosts mirrors.tuna.tsinghua.edu.cn 2>/dev/null | awk '{print $1}' | head -1)"
H0=$(sha256sum /etc/hosts | cut -d' ' -f1); L0=$(grep -vc '^#\|^$' /etc/hosts); echo "  /etc/hosts sha256 = ${H0:0:16}…，生效行数 = $L0"

echo "== 2. --sync（这一步写 /etc/hosts，它自己先逐字节备份）"
bash "$DOH" --sync 2>&1 | sed 's/^/  /'
echo "  --- 钉完之后：/etc/hosts 生效行数 = $(grep -vc '^#\|^$' /etc/hosts)（钉之前那一步读的是 $L0）  sha 变了没 = $(test "$(sha256sum /etc/hosts | cut -d' ' -f1)" = "$H0" && echo 没变（说明一条都没新钉） || echo 变了（预期）)"
printf '  复点解析：pypi.tuna ⇒ getent = %s\n' "$(getent hosts pypi.tuna.tsinghua.edu.cn 2>/dev/null | awk '{print $1}' | head -1)"

echo "== 3. 不带 --resolve 真下东西（这才算解析层修好了）"
TMP=/root/.dsh/pip-path-$RANDOM
mkdir -p "$TMP"
echo "  --- 元数据一发（HEAD 一个包，只看落不落得下字节）"
curl -s -o "$TMP/idx.html" -m 25 -w '      simple/requests/ ⇒ http=%{http_code} %{size_download}B %{time_total}s\n' https://pypi.tuna.tsinghua.edu.cn/simple/requests/
echo "  --- pip download（只下载不安装）"
timeout 120 pip download --no-deps -d "$TMP" requests >"$TMP/pip.log" 2>&1; RC=$?
echo "      rc=$RC  下到的文件："; ls -1 "$TMP" 2>/dev/null | grep -vE 'pip.log|idx.html' | sed 's/^/        /'
tail -2 "$TMP/pip.log" | sed 's/^/        /'
echo "  --- pip install --target 一个真装（不动系统 python，装完就删）"
timeout 150 pip install --target "$TMP/t" requests >"$TMP/pip2.log" 2>&1; RC2=$?
echo "      rc=$RC2  装进去的顶层包：$(ls -1 "$TMP/t" 2>/dev/null | tr '\n' ' ')"
echo "      装完能不能 import：$(PYTHONPATH="$TMP/t" python3 -c 'import requests,json;print(requests.__version__, requests.get("https://api.deepseek.com/models").status_code)' 2>&1 | head -1)"
tail -3 "$TMP/pip2.log" | sed 's/^/        /'
echo "  --- 清掉（这目录只是用来验路的）"
KB=$(du -sk "$TMP" 2>/dev/null | cut -f1); rm -rf "$TMP"; echo "      删了 $TMP（$KB KB），残留 = $(test -e "$TMP" && echo 还在 || echo 没了)"

echo "== 4. PEP 668 那三条路，各省多少包、代价各是什么（只模拟，一个不装）"
echo "  路 A 装 python3-venv（正式做法：给每个工程一个独立环境）"
apt-get -s install -y --no-install-recommends python3-venv python3-full 2>&1 | grep -E '^[0-9]+ upgraded,|Need to get' | sed 's/^/        /'
echo "  路 B 不装东西，pip 一律加 --break-system-packages（少一步，但 python 包能盖掉 apt 包的文件）"
echo "        pip 现在的行为：$(pip install --dry-run requests 2>&1 | head -1)"
echo "  路 C 不装东西，pip 一律加 --target 指到某个目录（上面第 3 节验的就是这条，已实测可用）"
printf '        副作用：得每次带 PYTHONPATH 或 --target，agent 容易忘\n'
echo "  --- venv 到底在不在（决定路 A 现在能不能走）"
python3 -c 'import venv; print("        venv 模块可导入，ensurepip =", __import__("importlib.util",fromlist=["x"]).find_spec("ensurepip") is not None)' 2>&1 | head -2 | sed 's/^/      /'

echo "== 5. 服务复点"
echo "  引擎 pid = $(pgrep -f 'dsh web' | head -1)（要仍是 21363）  含 'dsh web' = $(pgrep -f 'dsh web' | wc -l)  入口 pid = $(pgrep -f dsh-entry.js | head -1)"
echo "  dpkg ii 计数 = $(dpkg -l 2>/dev/null | awk '$1=="ii"' | wc -l)（要仍是 411 —— 本支一个包都没装）"
echo "  退回解析：bash $DOH --revert <上面列出的 hosts.bak.路径>（备份件数现在 = $(ls -1 /root/.dsh/hosts.bak.* 2>/dev/null | wc -l)）"
echo " 完（这一支写了 /etc/hosts 一条（自带备份）、下了两发真字节、装进临时目录又删干净；没 apt 装包、没重启、没动 npm/档位/兼容层）"
