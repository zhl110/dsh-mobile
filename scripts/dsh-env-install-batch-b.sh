#!/usr/bin/env bash
# dsh-env-install-batch-b.sh —— 把《手机端情况.md》B 类里"能补的"那批一次补完（2026-10-21 晚）。
#
# 他这一轮的原话是「根据我那个手机端情况，这个文件里面的问题一个一个帮我解决掉，你给我最终结果就可以了」，
# 而那份文件自己末段就问的是「要不要我先把 B 类里最常用的那批装上
# （python3 pip git gcc make ffmpeg imagemagick poppler-utils unzip tmux 之类）」——
# 所以这一支装的就是那一串名字（python3 与 git 已在 14.29 那装卸好，本支跳过），
# 「之类」我按第 C 节的具体诉求展开：sqlite3（文档/数据类工具要读库）、zip file rsync wget（压缩包与传文件）。
#
# 明确**不装**的：docker / podman（文件自己写了装了也跑不起来，没 namespace）、
# rustc / go / java（B 类清单里在，但第 46 行那串"最常用"没有它们，体积也差一个量级）、
# libreoffice / pandoc / tesseract（同上；要不要装留给下一轮，我在这支末尾用 apt-get -s 给出体积与包数，不做决定）。
#
# 三条按死的口径（与 14.29 那支同形）：
#   ① flags 全程 -y --no-install-recommends，与探针 48 那四次模拟一字不差 ——
#      只有 flags 一致，"模拟计划的 newly installed"才允许等于"装完 dpkg 差集的数"。
#   ② 一批一对账，不是四批合一对：pip / 编译 / 媒体文档 / 杂项 各数自己的 ①②③，
#      任何一批 ①≠② 就停在那一批，后面的批次不再动（防止把差异糊在一起看不清）。
#   ③ 装之前留 dpkg 快照与磁盘读数，装完复点引擎 pid、:3080、:3081、hosts 钉表行数 ——
#      用来证明这发 apt 没把跑着的东西带倒、没碰解析。
set -u
export DEBIAN_FRONTEND=noninteractive
TS=$(date -u +%Y%m%d-%H%M%S)
BEFORE=/root/.dsh/dpkg-before-$TS.txt
AFTER=/root/.dsh/dpkg-after-$TS.txt
LOG=/root/.dsh/apt-install-batch-b-$TS.log

# 四批的名字与探针 48 第 3 节那四行【必须逐字一致】，否则计划的数对不上
BATCHES=(
  "pip|python3-pip|4"
  "编译|gcc g++ make cmake pkg-config|54"
  "媒体文档|ffmpeg imagemagick poppler-utils sqlite3|204"
  "杂项|unzip zip file rsync wget tmux|11"
)

echo "== 0. 时刻与身份"
echo "  UTC  $(date -u '+%F %T')   北京 $(TZ=Asia/Shanghai date '+%F %T' 2>/dev/null)（chroot 里这个钟是 UTC，文件名里的时间是 UTC）"
echo "  whoami=$(id -u) uid=$(id -un)  内核 $(uname -r)  PID1=$(cat /proc/1/comm 2>/dev/null)（没 systemd）"

echo "== 1. 装之前"
dpkg -l 2>/dev/null | awk '$1=="ii"{print $2}' | sort > "$BEFORE"
USED_BEFORE=$(df -k / | awk 'NR==2{print $3}')
FREE_BEFORE=$(df -k / | awk 'NR==2{print $4}')
USR_BEFORE=$(du -sk /usr 2>/dev/null | cut -f1)
ENGINE_PID_BEFORE=$(pgrep -f 'dsh web' | head -1)
echo "  dpkg 快照 = $(wc -l < "$BEFORE") 行；df -k / 已用 $USED_BEFORE KB / 可用 $FREE_BEFORE KB；du -sk /usr = $USR_BEFORE KB"
echo "  引擎 pid（装之前）= ${ENGINE_PID_BEFORE:-空}  含 'dsh web' 进程数 = $(pgrep -f 'dsh web' | wc -l)（要恰好 1）"
echo "  已经在位的（上一支装的）：$(command -v git >/dev/null && echo git 在) $(command -v python3 >/dev/null && echo python3 在)"
echo "  内存可用 = $(awk '/MemAvailable/{printf "%.1f G", $2/1048576}' /proc/meminfo)"

PREV=$BEFORE
STOP=0
for row in "${BATCHES[@]}"; do
  IFS='|' read -r LABEL PKGS PLAN <<< "$row"
  if [ "$STOP" = "1" ]; then echo "== 批【$LABEL】跳过（前一批对账没过，铁律 2：不糊数）"; continue; fi
  echo "== 2. 批【$LABEL】装：$PKGS"
  # 每批装之前现场再模拟一次：上一支那 22 个包进来后依赖闭包可能缩，探针 48 的数只是当时的
  SIM=$(apt-get -s install -y --no-install-recommends $PKGS 2>&1)
  SRC=$?
  SIMLINE=$(printf '%s\n' "$SIM" | grep -E '^[0-9]+ upgraded,' | tail -1)
  SIM_NEW=$(printf '%s' "$SIMLINE" | sed -E 's/^[0-9]+ upgraded, ([0-9]+) newly installed.*/\1/')
  SIM_UP=$(printf '%s' "$SIMLINE" | sed -E 's/^([0-9]+) upgraded.*/\1/')
  echo "  模拟 rc=$SRC：$SIMLINE"
  echo "  $(printf '%s\n' "$SIM" | grep -E 'Need to get|After this operation' | tr '\n' ' ')"
  echo "  计划数：本批现场模拟 new=$SIM_NEW upgraded=${SIM_UP:-?}（探针 48 当时读到 new=$PLAN）"
  if [ "$SRC" != "0" ] || [ -z "${SIM_NEW:-}" ]; then
    echo "  !! 模拟就没过（rc=$SRC），这一批不装，停在这里"; STOP=1; continue
  fi
  # 已经全在位的批（数出 0 新包）不浪费一发 install
  if [ "$SIM_NEW" = "0" ]; then echo "  [skip] 这一批都已在上（0 newly installed），不发 install"; continue; fi
  N0=$(wc -l < "$PREV")
  apt-get install -y --no-install-recommends $PKGS >>"$LOG" 2>&1; RC=$?
  echo "  装 rc=$RC"
  if [ "$RC" != "0" ]; then
    echo "  --- 日志里的失败行（E: / dpkg: / error）"
    grep -nE '^E: |^dpkg: |error:|^Errors were encountered' "$LOG" | tail -6 | sed 's/^/      /'
    echo "  !! 这一批 rc≠0，停在这里，后面的批次不装"; STOP=1; continue
  fi
  MID=/root/.dsh/dpkg-mid-$LABEL.txt
  dpkg -l 2>/dev/null | awk '$1=="ii"{print $2}' | sort > "$MID"
  NEW_CNT=$(comm -13 "$PREV" "$MID" | wc -l)
  UP_CNT=$(comm -23 "$PREV" "$MID" | wc -l)
  echo "  对账（口径=本批前后各数各的，不与别的批混）："
  echo "        ① 现场模拟 new=$SIM_NEW   ② 差集新增=$NEW_CNT（版本变=$UP_CNT）   ③ 包数 $N0 → $(wc -l < "$MID")（差 $(( $(wc -l < "$MID") - N0 ))）"
  if [ "$SIM_NEW" != "$NEW_CNT" ]; then
    echo "  !! ①≠②（$SIM_NEW vs $NEW_CNT）：报数不猜，后面批次停手（差额先核上面【版本变】那个数）"
    STOP=1
  else
    echo "  [ok] ①=② 这一批计划与实际一致"
  fi
  PREV=$MID
done

echo "== 3. 三个数总对账（四批合起来的最终口径）"
dpkg -l 2>/dev/null | awk '$1=="ii"{print $2}' | sort > "$AFTER"
TOTAL_NEW=$(comm -13 "$BEFORE" "$AFTER" | wc -l)
TOTAL_UP=$(comm -23 "$BEFORE" "$AFTER" | wc -l)
echo "  四批装完新增 = $TOTAL_NEW 个（另有版本变了 = $TOTAL_UP 个）"
echo "  装前 $(wc -l < "$BEFORE") → 装后 $(wc -l < "$AFTER") 个 ii 包"
echo "  --- 新增名单（这份就是以后要撤时 apt remove 的参，已存 $AFTER 旁边一份）"
comm -13 "$BEFORE" "$AFTER" > /root/.dsh/dpkg-newbatch-$TS.txt
echo "      名单文件 /root/.dsh/dpkg-newbatch-$TS.txt = $(wc -l < /root/.dsh/dpkg-newbatch-$TS.txt) 行"
comm -13 "$BEFORE" "$AFTER" | tr '\n' ' ' | fold -s -w 100 | sed 's/^/      /'
if [ "$TOTAL_UP" != "0" ]; then
  echo "  --- 版本变了的（预期只有 perl-base 一类）："; comm -23 "$BEFORE" "$AFTER" | sed 's/^/      /'
fi

echo "== 4. 命令逐个复点（B 类那串名字，看不看得见我说了不算）"
for c in git python3 pip pip3 gcc g++ make cmake pkg-config ffmpeg convert identify pdftoppm sqlite3 unzip zip file rsync wget tmux; do
  P=$(command -v $c 2>/dev/null || true)
  printf '    %-11s %s\n' "$c" "${P:-缺}"
done
echo "  --- 版本行"
for L in "git --version" "python3 -V" "python3 -m pip --version" "gcc --version | head -1" "make --version | head -1" "cmake --version | head -1" "ffmpeg -version | head -1" "convert --version | head -1" "pdftoppm -v 2>&1 | head -1" "sqlite3 --version" "unzip -v | head -2 | tail -1" "tmux -V" "wget --version | head -1"; do
  printf '    %-32s → %s\n' "$L" "$(eval "$L" 2>&1 | head -1)"
done
echo "  --- python 侧能不能干活（B 类那句"能生成 docx/xlsx 但没有 PIL"）"
echo "    python3 -c import: $(python3 -c 'import sqlite3,json,sys;print("sqlite3",sqlite3.sqlite_version)' 2>&1 | head -1)"
echo "    PIL 在不在 = $(python3 -c 'import PIL;print(PIL.__version__)' 2>&1 | head -1)（P 类属 pip install，本支只补 apt 名）"

echo "== 5. 还剩哪些 B 类没装，体积各是多少（只模拟，不装）"
for row in "文档办公|libreoffice-writer pandoc" "OCR|tesseract-ocr" "语言栈|rustc golang-go default-jdk" "容器|docker.io podman"; do
  IFS='|' read -r LB PK2 _ <<< "$row"
  S2=$(apt-get -s install -y --no-install-recommends $PK2 2>&1)
  echo "  [$LB] $(printf '%s\n' "$S2" | grep -E '^[0-9]+ upgraded,' | tail -1) · $(printf '%s\n' "$S2" | grep -E 'Need to get' | tail -1)"
done

echo "== 6. 装完复点磁盘与服务（这一发最关心的两件：占了多少、有没有带倒服务）"
USED_AFTER=$(df -k / | awk 'NR==2{print $3}')
USR_AFTER=$(du -sk /usr 2>/dev/null | cut -f1)
echo "  df -k / 已用 $USED_BEFORE → $USED_AFTER KB（多 $((USED_AFTER-USED_BEFORE)) KB ≈ $(( (USED_AFTER-USED_BEFORE)/1024 )) MiB）  可用 $(df -k / | awk 'NR==2{print $4}') KB"
echo "  du -sk /usr $USR_BEFORE → $USR_AFTER KB（多 $((USR_AFTER-USR_BEFORE)) KB ≈ $(( (USR_AFTER-USR_BEFORE)/1024 )) MiB）"
echo "  apt 下载缓存 /var/cache/apt/archives = $(du -sk /var/cache/apt/archives 2>/dev/null | cut -f1) KB，.deb 计数 = $(ls -1 /var/cache/apt/archives/*.deb 2>/dev/null | wc -l)（清不清他说了算：apt-get clean）"
ENGINE_PID_AFTER=$(pgrep -f 'dsh web' | head -1)
echo "  引擎 pid 装前=${ENGINE_PID_BEFORE:-空} 装后=${ENGINE_PID_AFTER:-空}（同一个数才叫没被带倒）  含 'dsh web' 进程数 = $(pgrep -f 'dsh web' | wc -l)"
echo "  入口 pid = $(pgrep -f dsh-entry.js | head -1)  监听命中数(3080/3081) = $(ss -ltn 2>/dev/null | awk 'NR>1 && $4 ~ /:(3080|3081)$/' | wc -l)"
printf '  :3080 GET / → %s\n' "$(curl -s -o /dev/null -m 8 -w '%{http_code} %{size_download}B' http://127.0.0.1:3080/ 2>&1)"
printf '  :3081 GET / → %s（未带 cookie 设计上就 404）\n' "$(curl -s -o /dev/null -m 8 -w '%{http_code} %{size_download}B' http://127.0.0.1:3081/ 2>&1)"
echo "  hosts 钉表生效行数 = $(grep -vc '^#\|^$' /etc/hosts)  备份件数 = $(ls -1 /root/.dsh/hosts.bak.* 2>/dev/null | wc -l)（本支不碰解析）"

echo "== 7. 我留了什么在机上"
ls -1 /root/.dsh/dpkg-before-$TS.txt /root/.dsh/dpkg-after-$TS.txt /root/.dsh/dpkg-newbatch-$TS.txt /root/.dsh/apt-install-batch-b-$TS.log /root/.dsh/dpkg-mid-*.txt 2>/dev/null | sed 's/^/  /'
echo "  日志 $(stat -c %s "$LOG" 2>/dev/null) B；chroot /root 里 .sh 数 = $(ls -1 /root/*.sh 2>/dev/null | wc -l)"
echo " 完（这一支只按他那份文件 B 类那串名字装了包，没动档位、没动 cordis、没重启引擎/入口、没碰 hosts、没 pip install 任何东西）"
