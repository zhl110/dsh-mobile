#!/usr/bin/env bash
# dsh-env-install-probe46.sh —— 只读：把《手机端情况.md》B 类那一条清单当场重跑一遍（缺什么、apt 能不能补、补了占多少），
# 顺带取 14.28 之后市场这一格的新现场（--status 里掉出来 502，那几发请求是谁发的、上游回什么）。
#
# 为什么这一发不写盘：他点头的是 git 与 python3 两件（2026-10-21 晚"它需要安装 Git、安装 Python 3，这个需要你去解决一下"），
# 但 B 类那张表里有 23 个名字。装之前要先量三件事：① 现在到底缺哪几个（他那份表是模型自述，铁律：模型自述要复点）；
# ② apt 的源在不在钉表里、清单过没过时；③ `apt-get -s` 这两发会牵出多少新包、占多少字节（铁律 2：只认脚本打的合计行）。
set -u

echo "== 0. 时刻（chroot 是 UTC；北京 = UTC+8）"
echo "  UTC  $(date -u '+%F %T')"
echo "  北京 $(TZ=Asia/Shanghai date '+%F %T' 2>/dev/null || date '+%F %T')"

echo "== 1. 三层现场"
BOOT=$(awk '/^btime/ {print $2}' /proc/stat)
UP=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
HZ=$(getconf CLK_TCK 2>/dev/null); [ -n "$HZ" ] || HZ=100
for P in $(pgrep -f 'dsh web|dsh-entry.js'); do
  CMD=$(tr '\0' ' ' < "/proc/$P/cmdline" 2>/dev/null | cut -c1-52)
  ST=$(awk '{print $22}' "/proc/$P/stat" 2>/dev/null)
  case "$CMD" in *'dsh web'*) TAG=引擎;; *dsh-entry.js*) TAG=入口;; *) TAG=别的;; esac
  [ -n "$ST" ] && printf '  %s pid %-7s 出生 %s UTC 活着 %7s 秒  %s\n' "$TAG" "$P" "$(date -u -d "@$((BOOT + ST / HZ))" '+%F %T')" "$((UP - ST / HZ))" "$CMD"
done
echo "  监听命中数 = $(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:(3080|3081)$/' | wc -l)"
ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:(3080|3081)$/ {printf "    %s\n", $4}'
printf '  :3080 GET / → %s\n' "$(curl -s -o /dev/null -m 8 -w '%{http_code} %{size_download}B' http://127.0.0.1:3080/ 2>&1)"
printf '  :3081 GET / → %s（未带 cookie 设计上就 404）\n' "$(curl -s -o /dev/null -m 8 -w '%{http_code} %{size_download}B' http://127.0.0.1:3081/ 2>&1)"

echo "== 2. B 类那张清单当场重跑（逐个 command -v，命中就顺手取版本）"
B="python3 python pip3 git gcc g++ make cmake rustc go java docker podman sqlite3 ffmpeg convert pdftoppm libreoffice soffice pandoc tesseract ssh rsync wget curl unzip zip file tar grep sed awk node npm dpkg apt apt-get xz-utils pkg-config"
MISS=0; HIT=0
for c in $B; do
  if command -v "$c" >/dev/null 2>&1; then
    HIT=$((HIT+1)); printf '    [有] %-12s %s\n' "$c" "$(command -v $c)"
  else
    MISS=$((MISS+1)); printf '    [缺] %-12s\n' "$c"
  fi
done
echo "    合计：点名 $(printf '%s\n' "$B" | wc -w) 个，命中 $HIT，缺 $MISS（HIT+MISS 要等于点名数，不等说明循环被截了）"
echo "  --- 他这次点名的两件，看看到底是不是真的没有"
for c in git python3; do
  printf '    %-8s command -v = %s；dpkg -l 里那行 = %s\n' "$c" "$(command -v $c 2>/dev/null || echo 空)" \
    "$(dpkg -l 2>/dev/null | awk -v n=$c '$2==n {print $1" "$3}' | head -1)"
done
echo "  --- dpkg 总包数（他那句「只有 124 个包」要复点）= $(dpkg -l 2>/dev/null | grep -c '^ii')"
echo "  --- node/npm：$(node -v 2>&1) / $(npm -v 2>&1)"

echo "== 3. apt 侧（只读 + 模拟，一个字节不写）"
echo "  sources："; awk 'NF && $1!="#" {printf "    %s\n", $0}' /etc/apt/sources.list 2>/dev/null | head -6
ls -1 /etc/apt/sources.list.d/ 2>/dev/null | sed 's/^/    sources.list.d\/|/'
echo "  清单目录 /var/lib/apt/lists 文件数 = $(ls -1 /var/lib/apt/lists 2>/dev/null | grep -v '^partial$' | wc -l)，最新一份改于 $(ls -1t /var/lib/apt/lists 2>/dev/null | grep -v partial | head -1 | xargs -I{} stat -c '%y' /var/lib/apt/lists/{} 2>/dev/null | cut -d. -f1)"
echo "  源主机在不在 /etc/hosts 钉表里："; for h in mirrors.tuna.tsinghua.edu.cn ports.tuna.tsinghua.edu.cn registry.npmmirror.com deb.debian.org; do
  printf '    %-34s hosts 命中 %s 行\n' "$h" "$(awk -v H=$h '$2==H' /etc/hosts | wc -l)"
done
for p in git python3; do
  echo "  --- apt-get -s install $p（模拟，一个包都不落地）"
  apt-get -s install -y "$p" >/tmp/.p46sim.$p 2>&1; RC=$?
  echo "    rc=$RC"
  grep -E 'upgraded,|newly installed|Need to get|After this operation' /tmp/.p46sim.$p 2>/dev/null | sed 's/^/      /'
  echo "    Inst 行数 = $(grep -c '^Inst' /tmp/.p46sim.$p)（这行要与上面 'newly installed' 那个数对得上，对不上以 apt 那行为准）"
  grep '^Inst' /tmp/.p46sim.$p 2>/dev/null | head -40 | awk '{printf "      %s\n", $2}'
  grep -iE '^E:' /tmp/.p46sim.$p 2>/dev/null | head -4 | sed 's/^/      报错: /'
  rm -f /tmp/.p46sim.$p
done

echo "== 4. 空间（装之前先看还剩多少）"
df -h / /tmp 2>/dev/null | sed 's/^/  /'
echo "  /root 占用 = $(du -sh /root 2>/dev/null | cut -f1)；/root/.dsh = $(du -sh /root/.dsh 2>/dev/null | cut -f1)"
free -m 2>/dev/null | head -3 | sed 's/^/  /'

echo "== 5. 市场这一格的新现场（--status 里掉出来的那几发 502）"
echo "  --- 入口自述（只读一发 GET /__entry_status，走它自己的口令，不打印凭据）"
HOME=/root TMPDIR=/tmp DSH_ENTRY_KEY_FILE=/root/.dsh/entry.key DSH_ENTRY_PORT=3081 DSH_UP_PORT=3080 \
  node /usr/local/bin/dsh-entry.js --status 2>&1 | sed 's/^/    /'
echo "  --- 上面这份里 market/purge 相关行就是证据本体（App / 探针 两类 UA 分得开），不在此重复计数"
echo "    entry.log = $(stat -c %s /root/.dsh/entry.log 2>/dev/null) B，改于 $(stat -c %y /root/.dsh/entry.log 2>/dev/null | cut -d. -f1)"
echo "    entry.log 里 dsh-market 行数 = $(grep -c 'dsh-market' /root/.dsh/entry.log 2>/dev/null)（0 不奇怪：流水在内存里，不在日志）"
echo "  --- 插件侧 state.json / log.ndjson"
M=/root/.dsh/profiles/web/.dsh-market
echo "    state.json：$(cat $M/state.json 2>/dev/null)"
echo "    log.ndjson = $(stat -c %s $M/log.ndjson 2>/dev/null) B，改于 $(stat -c %y $M/log.ndjson 2>/dev/null | cut -d. -f1)，行数 = $(wc -l < $M/log.ndjson 2>/dev/null)"
tail -2 $M/log.ndjson 2>/dev/null | cut -c1-260 | sed 's/^/      /'
echo "  --- 目录这四个地址，不带 --resolve 各回什么（验收口径：带了 --resolve 就是自欺）"
for u in "https://awesome-dsh-plugin.com/index.json" "https://awesome-dsh-plugin.com/plugins.json" "https://registry.npmmirror.com/dsh-plugin-catalog" "https://raw.githubusercontent.com/zhl110/awesome-dsh-plugin/main/README.md"; do
  printf '    %-58s %s\n' "$u" "$(curl -s -o /dev/null -m 12 -w '%{http_code} %{size_download}B %{time_total}s' "$u" 2>&1)"
done
echo "  --- getent 解析（同上面同一批发请求之前先查解析层）"
for h in awesome-dsh-plugin.com registry.npmmirror.com api.deepseek.com platform.deepseek.com; do
  printf '    %-30s getent = %s\n' "$h" "$(getent hosts $h 2>/dev/null | head -1)"
done

echo "== 6. 流量全表现值（口径：/proc/net/dev，rx=\$2 tx=\$10；抄回去当基线）"
awk 'NR>2 {n=$1; sub(/:/,"",n); printf "  %s %s %s\n", n, $2, $10}' /proc/net/dev

echo "== 7. 我在这台机上留过什么（自查，只列不删）"
ls -1 /root/*.sh 2>/dev/null | sed 's/^/  /'
echo "    /root/*.sh 计数 = $(ls -1 /root/*.sh 2>/dev/null | wc -l)；/tmp 条目 = $(ls -1A /tmp 2>/dev/null | wc -l)"
echo " 完（探针 46 全只读：没 apt install、没写 /etc/hosts、没点「应用」、没重启引擎）"
