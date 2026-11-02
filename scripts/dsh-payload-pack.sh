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
# 用法（都由 PC 侧 tools/make-payload.sh 调用，别手搓 adb）：
#   bash /root/dsh-payload-pack.sh --census  只读：清单、保留体积、留/剥了什么、敏感文件名、凭证形状命中
#                                            （只报文件名与命中的那个词，绝不打印行内容 —— 铁律 8）
#   bash /root/dsh-payload-pack.sh --pack    把保留集以 tar 流写到 stdout，诊断一律走 stderr
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

echo "== 3 敏感文件名普查（整棵保留集，只看名字）"
find_kept > /tmp/.packlist.$$
echo "  保留集文件数 : $(wc -l < /tmp/.packlist.$$ | tr -dc '0-9')"
grep -iE "$NAMEPAT" /tmp/.packlist.$$ | head -60 | sed 's/^/  文件名 /'
echo "  命中条数 : $(grep -icE "$NAMEPAT" /tmp/.packlist.$$)"
rm -f /tmp/.packlist.$$

echo "== 4 root 口令状态（只报形状，绝不打印哈希）"
awk -F: '$1=="root"{print "  root 字段 : " (substr($2,1,1)=="$" ? "有哈希 ⇒ /etc/shadow 要处理" : ($2 ~ /^[!*]/ ? "锁定/无哈希 ⇒ 可以随包走" : "其他"))}' /etc/shadow 2>/dev/null
echo "  /etc/shadow : $(wc -c < /etc/shadow 2>/dev/null | tr -dc '0-9') B，行数 $(wc -l < /etc/shadow 2>/dev/null | tr -dc '0-9')"

echo "== 5 凭证形状内容普查（只扫数据面，不扫 /usr 上游包；只报文件名与命中的词）"
HITS=0
PATARG=(); for p in "${CENPATS[@]}"; do PATARG+=( -e "$p" ); done
scan() {
  while IFS= read -r -d '' f; do
    W=$(grep -ohF "${PATARG[@]}" -- "$f" 2>/dev/null | sort -u | tr '\n' ',')
    if [ -n "$W" ]; then HITS=$((HITS+1)); printf '  %-4s %9s B  %s  «%s»\n' 命中 "$(wc -c <"$f" | tr -dc '0-9')" "$f" "$W"; fi
  done < <(find "$@" -print0 2>/dev/null)
}
# 数据面 = 保留下来的 /root/.dsh 两块 + /root 一层 + /etc + /usr/local/etc + /home + /srv
scan /root/.dsh/profiles /root/.dsh/dsh-purge -type f -not -path '*/node_modules/*'
scan /root -maxdepth 1 -type f
scan /etc /usr/local/etc /home /srv -type f
echo "  合计命中文件 : $HITS"
echo "  （命中 != 泄露：字段名、样例、注释都会撞；逐条看过再决定剥不剥。/usr 那 1 GB 多上游 js 本轮没扫 —— 写清楚没做什么）"
echo "[done] census rc=0"
