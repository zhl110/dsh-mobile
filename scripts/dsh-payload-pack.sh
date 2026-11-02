#!/bin/bash
# scripts/dsh-payload-pack.sh —— 在 chroot 里跑的那一半：算清单 + 普查 + 往 stdout 吐 tar 流
#
# 为什么清单与普查放在设备侧脚本里，而不是 PC 侧 make-payload.sh 的字符串里（2026-11-02 实测）：
#   1) 三层引号（Windows bash → adb shell → su -c → chroot → bash -c）里双引号会和外层撞、
#      单引号会被 su -c 那层截断。上一版把 `grep -rlIE -e "apiKey|api_key|..."` 塞进 CH()，
#      `{12,}` 被设备 shell 展成好几个词、`|` 被当管道，普查打出 770 行 /dev 报错 +
#      "/system/bin/sh: access_token: inaccessible or not found" —— 那种读数一条都不能信。
#   2) 路径里带空格与中文（真读到过 /root/.dsh/dpkg-mid-杂项.txt）。字符串拼 --exclude 会劈开，数组不会。
#   3) 单一真源：tar 的 --exclude、du 的 --exclude、find 的 -prune 必须同一批路径；
#      两处各抄一份就等于没有对账（铁律 2 的同源规矩）。
#
# 用法（前两种由 PC 侧 tools/make-payload.sh 调用，别手搓 adb）：
#   bash /root/dsh-payload-pack.sh --census  只读：清单、保留体积、留/剥了什么、敏感文件名、词形命中（参考）、
#                                            已知凭证串回归（闸门一）。值一律不打印，只报文件名与个数 —— 铁律 8
#   bash /root/dsh-payload-pack.sh --pack    把保留集以 tar 流写到 stdout，诊断一律走 stderr
#   bash /root/dsh-payload-pack.sh --meta    只给 payload-meta.txt 的那几个数
#   bash /root/dsh-payload-pack.sh --selftest  造一棵假树把闸门跑三遍（埋雷要抓到 / 撤雷要 0 / 凭证源空要报"取不到串"）。
#                                            不需要手机，Windows 的 git-bash 就能跑：2026-11-02 当场 合计 3 条 PASS 3 / FAIL 0
set -u

MODE=${1:---census}
# /root/.dsh 下**只留**这三个：语音模型（离线能用）、profile 层栈（dsh 本体配置）、purge 的备份目录。
DSH_KEEP='speech-to-text profiles dsh-purge'

DROP=(
  /phone
  /tmp /proc /sys /dev /run
  /root/.npm /root/.cache /root/.local /root/.ssh /root/.bash_history /root/.dsh-env /root/.config
  /var/cache/apt /var/lib/apt/lists
  /usr/local/lib/python3.12/dist-packages/frida
  /usr/local/lib/python3.12/dist-packages/frida_tools
  /usr/local/bin/frida /usr/local/bin/frida-server /usr/local/bin/frida-inject
  /root/dsh-payload-pack.sh
)
MOUNTPTS=(/proc /sys /dev /run /tmp)
NAMEPAT='\.key$|\.pem$|\.p12$|\.pfx$|id_rsa|credential|token|secret|\.dsh-env|bash_history'
CENPATS=(apiKey api_key access_token 'Bearer ' 'sk-' password secret refresh_token client_secret)
# 扫描面：保留清单里属于"这台机自己写过的东西"的那一层。/usr 那 1 GB 多是上游包，不在面内（写明没扫）。
DATAFACE=${DSH_T_DATAFACE:-'^/(etc|home|srv|opt|usr/local/etc|usr/local/share|root/|var/lib/dpkg|var/spool/cron)'}
LIST=${DSH_T_LIST:-/tmp/.packlist.$$}
DATA=${DSH_T_DATA:-/tmp/.packdata.$$}
# 凭证源与 /etc/shadow 都可被 DSH_T_* 覆盖 —— 为了 --selftest 能在本机（PC 的 git-bash 也行）
# 拿一棵假树真跑一遍闸门；手机端不传这些变量，取的就是下面这三个默认路径。
KEYF=${DSH_T_KEY:-/root/.dsh/entry.key}
ENVF=${DSH_T_ENV:-/root/.dsh-env}
PROVD=${DSH_T_PROVIDER:-/root/.dsh/llm-deepseek}
SHADOWF=${DSH_T_SHADOW:-/etc/shadow}

EXCL=(); DUEXC=(); PRUNE=()
add_drop() { EXCL+=( "--exclude=.$1" ); DUEXC+=( "--exclude=$1" ); PRUNE+=( -path "$1" -o ); }
for p in "${DROP[@]}"; do add_drop "$p"; done
# /root/.dsh：除 DSH_KEEP 外的一层条目当场展开逐个剔（不靠通配：通配会连模型目录一起匹配）
DSH_DROP=''
for f in /root/.dsh/* /root/.dsh/.[!.]*; do
  [ -e "$f" ] || continue
  b=${f##*/}; keep=0
  for k in $DSH_KEEP; do [ "$b" = "$k" ] && keep=1; done
  [ "$keep" = 1 ] && continue
  add_drop "$f"; DSH_DROP="$DSH_DROP$f
"
done
for n in '*session.v4.jsonl.zstd' '*entry.key' '*.pid'; do EXCL+=( "--exclude=./$n" ); done

tar_stream() { tar -C / -cf - "${EXCL[@]}" .; }
kept_du()    { du -sbx "${DUEXC[@]}" / 2>/dev/null | cut -f1; }
find_kept()  { find / \( "${PRUNE[@]}" -false \) -prune -o -type f -print 2>/dev/null; }

# 闸门本体（第 5 节词形 = 只打印；第 6 节已知凭证串回归 = 判据）。
# 抽成函数是为了 --selftest 能用一棵假树在**任何一台机器**上把它跑一遍 —— 手机端掉线这段时间里，
# 这是唯一还能推进这格交付的事：出包前至少证明"埋进去的 key 会被抓到"。
run_gate() {
  echo "== 5 词形普查（**只作参考，不作闸门**：上游 js 里字段名与随机 hash 全都会撞）"
  # 2026-11-02 在本机同一套 profile 树上量的：password 命中 43 个文件、sk- 26 个、Bearer  13 个，
  # 没有一条是真凭证。所以这一节只打印，闸门判据在下面第 6 节"已知凭证串回归"。
  PATARG=(); for p in "${CENPATS[@]}"; do PATARG+=( -e "$p" ); done
  grep -E "$DATAFACE" "$LIST" > "$DATA"
  echo "  扫描面（数据面文件）: $(wc -l < "$DATA" | tr -dc '0-9') 个，来自保留清单"
  echo "  撞上任一词形的文件 : $(xargs -d '\n' -a "$DATA" grep -lF "${PATARG[@]}" 2>/dev/null | wc -l | tr -dc '0-9') 个（命中 ≠ 泄露，逐条看过才算）"
  xargs -d '\n' -a "$DATA" grep -ohF "${PATARG[@]}" 2>/dev/null | sort | uniq -c | sort -rn | sed 's/^/    /'
  echo "  （/usr 那 1 GB 多上游 js 不在扫描面内 —— 这条要写清没做什么）"

  echo "== 6 已知凭证串回归（闸门一：这台机上真在用的那些串，一个字节都不许出现在保留集里）"
  # 判据为什么从"词形"换成"值"：词形必然误报（上面那节），而"值"是精确的 ——
  # 从**已知会被剥掉的凭证源**里把串取出来（只进内存，绝不打印、绝不落盘），
  # 再拿这批串去扫保留集：命中就是真泄露，不命中就是"我的 key 没跟着走"。
  # 凭证源：entry.key 整份、.dsh-env 每个 export 的值、provider 配置目录里所有长 token。
  TOK=()
  add_tok() {
    [ "${#1}" -ge 20 ] || return 0
    case "$1" in *[0-9]*) : ;; *) return 0 ;; esac      # 必须含数字：纯字母的长串多半是单词，不是 key
    TOK+=("$1")
  }
  if [ -f "$KEYF" ]; then
    while IFS= read -r l; do add_tok "${l%%[[:space:]]*}"; done < "$KEYF"
  fi
  if [ -f "$ENVF" ]; then
    while IFS= read -r l; do
      v=${l#*=}
      v=${v%\"}; v=${v#\"}; v=${v%\'}; v=${v#\'}
      add_tok "$v"
    done < <(grep -E '^[[:space:]]*(export[[:space:]]+)?[A-Za-z0-9_]+=' "$ENVF" 2>/dev/null)
  fi
  if [ -d "$PROVD" ]; then
    while IFS= read -r cf; do
      while IFS= read -r t; do add_tok "$t"; done < <(grep -oE '[A-Za-z0-9_-]{20,}' "$cf" 2>/dev/null | sort -u)
    done < <(find "$PROVD" -type f 2>/dev/null | head -40)
  fi
  TOK_N=${#TOK[@]}
  if [ "$TOK_N" = 0 ]; then
    echo "  !! 一个凭证串都没取到 ⇒ 这一节什么都没测。别把空读数读成通过。"
    echo "  已知凭证串命中 : 取不到串（不是 0）"
    return 0
  fi
  TARG=(); for t in "${TOK[@]}"; do TARG+=( -e "$t" ); done
  LEAKED=$(xargs -d '\n' -a "$DATA" grep -lF "${TARG[@]}" 2>/dev/null)
  LEAK=$(printf '%s' "$LEAKED" | grep -c .)
  echo "  取到的凭证串 : $TOK_N 个（值不打印；来源 = entry.key / .dsh-env / provider 目录）"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '  !! 保留集里出现凭证串 : %s（distinct %s 个）\n' "$f" "$(grep -ohF "${TARG[@]}" -- "$f" 2>/dev/null | sort -u | grep -c .)"
  done <<EOF
$LEAKED
EOF
  echo "  已知凭证串命中 : $LEAK"
}

# 自测：造一棵最小假树，把 key 埋进"保留集"里看闸门抓不抓得到；再撤掉埋的看会不会误报；
# 最后把凭证源清空，确认它走"取不到串"那一支而不是假装通过。合计 3 条断言。
selftest() {
  T=$(mktemp -d) || { echo "!! mktemp 失败"; exit 1; }
  mkdir -p "$T/root/.dsh/provider" "$T/etc" "$T/data"
  FAKEKEY="sk-SELFTEST0000000000000000000000ab"
  printf '%s\n' "$FAKEKEY" > "$T/root/.dsh/entry.key"
  printf 'export DSHM_DEMO="%s"\n' "$FAKEKEY" > "$T/root/.dsh-env"
  printf '{"apiKey":"%s","note":"password 这种词形也该被第 5 节打印出来"}\n' "$FAKEKEY" > "$T/root/.dsh/provider/cfg.json"
  printf 'ok\n' > "$T/etc/hosts"
  KEYF=$T/root/.dsh/entry.key; ENVF=$T/root/.dsh-env; PROVD=$T/root/.dsh/provider
  DATAFACE="^$T"; LIST=$T/list; DATA=$T/.gate-data
  PASS=0; FAIL=0
  # A) 埋一发在保留集里 ⇒ 必须命中 1
  printf '请把 %s 用上\n' "$FAKEKEY" > "$T/data/leak.txt"
  find "$T" -type f | grep -v 'entry.key' | grep -v 'dsh-env' | grep -v 'provider' | grep -v "$T/list$" > "$LIST"
  OUT=$(run_gate 2>&1)
  A=$(printf '%s\n' "$OUT" | sed -n 's/^  已知凭证串命中 : \([0-9]\{1,\}\).*/\1/p' | tail -1)
  if [ "$A" = "1" ]; then echo "  A 埋一发进保留集 ⇒ 命中 1 : PASS"; PASS=$((PASS+1)); else echo "  A !! 读到 ${A:-空}（期望 1）: FAIL"; FAIL=$((FAIL+1)); fi
  printf '%s\n' "$OUT" | grep '保留集里出现凭证串' | sed 's/^/     /'
  # B) 撤掉埋的 ⇒ 必须 0，且取到的串数 > 0（不然那个 0 是假 0）
  rm -f "$T/data/leak.txt"; printf 'nothing to see\n' > "$T/data/clean.txt"
  find "$T" -type f | grep -v 'entry.key' | grep -v 'dsh-env' | grep -v 'provider' | grep -v "$T/list$" | grep -v "$DATA$" > "$LIST"
  OUT=$(run_gate 2>&1)
  B=$(printf '%s\n' "$OUT" | sed -n 's/^  已知凭证串命中 : \([0-9]\{1,\}\).*/\1/p' | tail -1)
  TN=$(printf '%s\n' "$OUT" | sed -n 's/^  取到的凭证串 : \([0-9]\{1,\}\).*/\1/p')
  if [ "$B" = "0" ] && [ "${TN:-0}" -gt 0 ]; then echo "  B 撤掉埋的 ⇒ 命中 0（当场取到 $TN 个串）: PASS"; PASS=$((PASS+1)); else echo "  B !! 命中=${B:-空} 取到串=${TN:-空}（期望 0 与 >0）: FAIL"; FAIL=$((FAIL+1)); fi
  # C) 凭证源清空 ⇒ 必须明确报"取不到串"，不能打 0 蒙过去
  rm -f "$T/root/.dsh/entry.key" "$T/root/.dsh-env"; rm -rf "$T/root/.dsh/provider"
  OUT=$(run_gate 2>&1)
  if printf '%s\n' "$OUT" | grep -q '取不到串（不是 0）'; then echo "  C 凭证源为空 ⇒ 报"取不到串"而不是 0 : PASS"; PASS=$((PASS+1)); else echo "  C !! 没走空读数那一支: FAIL"; FAIL=$((FAIL+1)); fi
  echo "  合计 $((PASS+FAIL)) 条：PASS $PASS / FAIL $FAIL"
  rm -rf "$T"
  [ "$FAIL" = 0 ]
}

if [ "$MODE" = "--selftest" ]; then selftest; exit $?; fi

if [ "$MODE" = "--pack" ]; then
  echo "[pack] exclude ${#EXCL[@]} 条；条目数由 PC 侧从同一条流数，这里不另数" >&2
  tar_stream; rc=$?; echo "[pack] tar rc=$rc" >&2; exit $rc
fi

if [ "$MODE" = "--meta" ]; then
  # 只给 payload-meta.txt 用的几个数（快；不跑普查、不 tar —— 条目数由 PC 侧从同一条流数，这里再数一遍就是第二份真源）
  printf 'kept_du=%s\n' "$(kept_du)"
  printf 'dsh=%s\n' "$(node -e 'console.log(require("/usr/local/lib/node_modules/@deepseek-ai/dsh/package.json").version)' 2>/dev/null)"
  printf 'dpkg_ii=%s\n' "$(dpkg -l 2>/dev/null | grep -c ^ii)"
  printf 'cordis=%s\n' "$(wc -c < /root/.dsh/profiles/web/cordis.patch.yml 2>/dev/null | tr -dc '0-9')"
  printf 'hosts=%s\n' "$(awk '!/^#/ && NF>=2' /etc/hosts | wc -l | tr -dc '0-9')"
  exit 0
fi

echo "== 0 现场（UTC $(date -u '+%F %T')，$(tar --version | head -1)）"
echo "  整树（含 /tmp 与缓存，p89 口径）: $(du -sbx / 2>/dev/null | cut -f1) B"
echo "  保留体积（tar 用的同一批清单）  : $(kept_du) B"
echo "  --exclude 条数 ${#EXCL[@]} / -prune 条件 $(( ${#PRUNE[@]} / 3 ))"

echo "== 1 /root/.dsh 留了什么（只留：$DSH_KEEP）"
du -sb /root/.dsh/speech-to-text /root/.dsh/profiles /root/.dsh/dsh-purge 2>/dev/null | sed 's/^/  留 /'
printf '%s' "$DSH_DROP" | while IFS= read -r f; do
  [ -n "$f" ] || continue; printf '  剥 %s B  %s\n' "$(du -sb "$f" 2>/dev/null | cut -f1)" "$f"
done

echo "== 2 挂载点目录（包里没有也行：runner 自己 mkdir + mount --rbind；这里只报现状）"
for d in "${MOUNTPTS[@]}"; do
  printf '  %-6s 在=%s 条目 %s\n' "$d" "$([ -d $d ] && echo y || echo n)" "$(ls -A $d 2>/dev/null | wc -l | tr -d ' ')"
done

find_kept > "$LIST"
echo "== 3 敏感文件名普查（整棵保留集，只看名字）"
echo "  保留集文件数 : $(wc -l < "$LIST" | tr -dc '0-9')"
grep -iE "$NAMEPAT" "$LIST" | head -60 | sed 's/^/  文件名 /'
echo "  命中条数 : $(grep -icE "$NAMEPAT" "$LIST")"

echo "== 4 root 口令状态（只报形状，绝不打印哈希）"
awk -F: '$1=="root"{print "  root 字段 : " (substr($2,1,1)=="$" ? "有哈希 ⇒ /etc/shadow 要处理" : ($2 ~ /^[!*]/ ? "锁定/无哈希 ⇒ 可以随包走" : "其他"))}' "$SHADOWF" 2>/dev/null
echo "  shadow : $(wc -c < "$SHADOWF" 2>/dev/null | tr -dc '0-9') B，行数 $(wc -l < "$SHADOWF" 2>/dev/null | tr -dc '0-9')（文件 $SHADOWF）"

run_gate
rm -f "$LIST" "$DATA"
echo "[done] census rc=0"
