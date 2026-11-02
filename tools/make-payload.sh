#!/usr/bin/env bash
# tools/make-payload.sh —— 把手机上那棵跑着的 rootfs 打成"别人能装的产物"（tar.gz + sha256 + 泄露闸门）
#
# 为什么不把这些大件提交进 git（依据是 downloads/p89.txt 第 1/2/3 节的读数，不是猜）：
#   git 没有存 uid/gid 的字段，也没有 setuid/setgid 位。这棵树里 root:root 119,474 个、1001:1001 6,194 个，
#   setuid/setgid 17 个（passwd / su / mount 那一族），/dev 之外还有 4 个设备节点。
#   别人 checkout 出来属主全变、那两位全丢、节点没有 ⇒ chroot 里起不来。不是配额问题，是格式装不下。
#   要保属性只能走 tar（tar 存 owner+mode），而 tar 必然是 GB 级 ⇒ 产物挂 Release，仓里只放脚本与文档。
#
# 分工：清单、普查、tar 流全在 scripts/dsh-payload-pack.sh（设备侧，GNU 那套 + 数组，见那份头注释）；
#       本脚本只做 PC 侧的事：推脚本、收字节、本机压缩、两道闸门、指纹与元数据、超档切卷。
#
# 两条硬规矩：
#   1) 凭证与这台机上的用户数据不进包。闸门一 = 出包前"已知凭证串回归"（从 entry.key / .dsh-env /
#      llm-deepseek 取真串，回扫保留集；命中就是真泄露，不命中才算过。词形普查只作参考，见设备侧第 5 节注释）；
#      闸门二 = 出包后对**成员名单**再扫一次敏感名（命中就停，不推）。
#   2) 报数只认同源：条目数从同一条流算两次（raw 与 gz 各数一遍，必须相等），不拿另一套 find 口径去凑。
#
# 用法（在 D:\mycode\dsh-mobile 下跑）：
#   bash tools/make-payload.sh --dry        只读普查：清单/保留体积/留剥什么/敏感名/凭证命中；不出包
#   bash tools/make-payload.sh              出包到 release-assets/（超过 MAX_MB 自动 split 成多卷）
#   bash tools/make-payload.sh --pack --keep-raw   出包并留 raw tar（默认算完 sha 就删）
set -u
export MSYS2_ARG_CONV_EXCL='*'

ADB="${DSH_ADB:-/d/mycode/.agent-tools/platform-tools/adb.exe}"
[ -x "$ADB" ] || ADB="C:/Users/周海龙/DeskBox/我的桌面/platform-tools/adb.exe"
[ -x "$ADB" ] || { echo "!! 找不到 adb（两条路径都试过）"; exit 1; }
command -v gzip >/dev/null && command -v sha256sum >/dev/null || { echo "!! 要 git-bash 的 gzip / sha256sum"; exit 1; }

ROOT=/data/local/dsh-rootfs
RUNNER=/data/local/sh/dsh-chroot.sh
SCRIPT=scripts/dsh-payload-pack.sh
DEVNAME=$(basename "$SCRIPT")
OUTDIR=release-assets
MAX_MB=1900
MODE=${1:---dry}
KEEPROW=$([ "${2:-}" = "--keep-raw" ] && echo 1 || echo 0)

# 引号形状照 tools/run-probe.sh:45：外层双引号给 adb、转义双引号给 su -c —— 这样命令串里可以出现单引号
S() { "$ADB" shell "su -c \"$1\"" </dev/null 2>&1 | tr -d '\r'; }
CHRUN() { "$ADB" shell "su -c \"$RUNNER --run 'bash /root/$DEVNAME $1'\"" </dev/null 2>&1 | tr -d '\r'; }

[ -f "$SCRIPT" ] || { echo "!! 缺设备侧那一半：$SCRIPT"; exit 1; }
bash -n "$SCRIPT" || { echo "!! $SCRIPT 语法不过"; exit 1; }
CR=$(tr -cd '\r' < "$SCRIPT" | wc -c); [ "$CR" = "0" ] || { echo "!! $SCRIPT 有 $CR 个 CR，先 dos2unix"; exit 1; }
if [ "$MODE" != "--dry" ]; then
  echo "== -1 先在本机把闸门自测一遍（同一份脚本，三种形状：埋雷要抓到 / 撤雷要 0 / 凭证源空要报"取不到串"）"
  bash "$SCRIPT" --selftest || { echo "!! 闸门自测不过 —— 闸门本身坏了，这时候的"0 命中"不作数，不出包"; exit 1; }
fi
"$ADB" get-state >/dev/null 2>&1 || { echo "!! 设备不在 device 状态"; exit 1; }

echo "== 0 送设备侧脚本并逐字节撞 md5"
"$ADB" push "$SCRIPT" "/data/local/tmp/$DEVNAME" </dev/null 2>&1 | tr -d '\r'
S "cp /data/local/tmp/$DEVNAME $ROOT/root/$DEVNAME; chmod 755 $ROOT/root/$DEVNAME; chown root:root $ROOT/root/$DEVNAME; rm -f /data/local/tmp/$DEVNAME"
LOC=$(md5sum "$SCRIPT" | cut -d' ' -f1)
DEV=$(S "md5sum $ROOT/root/$DEVNAME" | cut -d' ' -f1)
[ "$LOC" = "$DEV" ] && echo "  [ok] 机上那份与本地相同（md5 $LOC）" || { echo "!! md5 不撞：本地 $LOC 设备 $DEV"; exit 1; }

if [ "$MODE" = "--dry" ]; then
  OUT=downloads/payload-census-$(date -u +%Y%m%d-%H%M%SZ).txt
  CHRUN --census | tee "$OUT"
  echo "[ok] 普查读数写进 $OUT"
  S "rm -f $ROOT/root/$DEVNAME" >/dev/null
  echo "  设备侧脚本副本已删；剩余 .sh：$(S "ls -1 $ROOT/root/*.sh 2>/dev/null | wc -l" | tr -dc '0-9')（含本探针时才是真残留，这里已删完应为 0 或常驻那几份）"
  exit 0
fi

echo "== 1 出包前普查（闸门一：这台机真在用的凭证串若在保留集里出现，就停，不出包）"
# 判据是设备侧脚本第 6 节"已知凭证串命中"（从 entry.key / .dsh-env / llm-deepseek 取真值再回扫保留集）。
# 不再拿第 5 节的词形命中当闸门：2026-11-02 在本机同型 profile 树上量到 password 43 个文件、sk- 26、Bearer 13
# 全是上游 js 的字段名与 hash —— 用词形当闸门会永远出不了包（假阳性卡死），见那份脚本头注释。
CEN=$(CHRUN --census)
printf '%s\n' "$CEN" | sed -n '/^== 6/,$p' | sed 's/^/  /'
N=$(printf '%s\n' "$CEN" | sed -n 's/^  已知凭证串命中 : \([0-9]\{1,\}\).*/\1/p' | tail -1)
[ -n "${N:-}" ] || { echo "!! 没读到闸门计数（设备侧那一半跑坏了，或一个凭证串都没取到 ⇒ 那不算通过），不出包"; echo "$CEN" | tail -20; exit 1; }
[ "$N" = "0" ] || { echo "!! 保留集里命中 $N 个文件带真凭证串：把它们加进设备侧 DROP/DSH_KEEP 再重打，别继续。"; exit 1; }
echo "  [ok] 已知凭证串回归 0 命中"

mkdir -p "$OUTDIR"
RAW=$OUTDIR/.packing.tar
echo "== 2 流式取 raw tar（机上不落一个字节，PC 侧收原始字节）"
T0=$(date +%s)
"$ADB" exec-out "su -c \"$RUNNER --run 'bash /root/$DEVNAME --pack'\"" > "$RAW" 2> "$OUTDIR/.pack.stderr"
RC=$?
RAWSZ=$(wc -c <"$RAW" | tr -dc '0-9')
echo "  raw : $RAWSZ B  rc=$RC  耗时 $(( $(date +%s) - T0 )) 秒  诊断：$(tr '\n' ' ' < "$OUTDIR/.pack.stderr")"
rm -f "$OUTDIR/.pack.stderr"
[ "$RC" = 0 ] || { echo "!! 取流退出码 $RC"; exit 1; }
[ "${RAWSZ:-0}" -gt 100000000 ] || { echo "!! raw 小得不对（保留集是 GB 级）；先查管道"; exit 1; }
ENT_RAW=$(tar -tf "$RAW" 2>/dev/null | wc -l | tr -dc '0-9')
echo "  raw 条目数 : $ENT_RAW（后面所有对账的基准，同源）"

echo "== 3 本机 gzip -1 压缩"
TS=$(date -u +%Y%m%d-%H%M%SZ)
OUT=$OUTDIR/dsh-rootfs-$TS.tar.gz
T1=$(date +%s)
gzip -1 -c "$RAW" > "$OUT"
GZ=$(wc -c <"$OUT" | tr -dc '0-9')
echo "  产物 : $OUT  $GZ B  耗时 $(( $(date +%s) - T1 )) 秒"
gzip -t "$OUT" && echo "  [ok] gzip -t 过" || { echo "!! gz 坏了"; exit 1; }
ENT_GZ=$(tar -tzf "$OUT" 2>/dev/null | wc -l | tr -dc '0-9')
[ "$ENT_RAW" = "$ENT_GZ" ] && echo "  [ok] gz 与 raw 条目数相等：$ENT_GZ" || { echo "!! 条目不等 raw=$ENT_RAW gz=$ENT_GZ"; exit 1; }

echo "== 4 名单闸门（闸门二：敏感名命中就停）"
RE='entry\.key|session\.v4|/\.dsh-env|bash_history|/\.ssh/|^\./phone/|/\.npm/|apt/archives|/redteam/|/attachments/|/llm-deepseek/|frida|/\.dsh/logs/|/\.dsh/storages/|/\.dsh/cache/'
BAD=$(tar -tzf "$OUT" | grep -cE "$RE")
echo "  命中 : $BAD 条（要 0）"
[ "$BAD" = "0" ] || { tar -tzf "$OUT" | grep -E "$RE" | head -12 | sed 's/^/    /'; echo "!! 闸门不过：$OUT 别推，删掉重打"; exit 1; }
echo "  [ok] 名单干净；条目数 $ENT_GZ"

echo "== 5 指纹与元数据"
SHA=$(sha256sum "$OUT" | cut -d' ' -f1)
printf '%s  %s\n' "$SHA" "$(basename "$OUT")" > "$OUTDIR/SHA256SUMS"
# 元数据那几个数由设备侧 --meta 一次给（同一批清单、同一台机、当场读 —— 不在 PC 侧凭记忆抄）
META_RAW=$(CHRUN --meta)
mget() { v=$(printf '%s\n' "$META_RAW" | sed -n "s/^$1=//p" | head -1); printf '%s' "${v:-空读数}"; }
META=$OUTDIR/payload-meta.txt
{
  echo "生成 UTC      : $(date -u '+%F %T')"
  echo "产物          : $(basename "$OUT")  $GZ B"
  echo "sha256        : $SHA"
  echo "raw / gz      : $RAWSZ B → $GZ B（比 $(awk -v a="$RAWSZ" -v b="$GZ" 'BEGIN{printf "%.2f", a/b}')）"
  echo "条目数        : raw $ENT_RAW / gz $ENT_GZ（同一条流数两次，必须相等）"
  echo "机上保留体积  : $(mget kept_du) B（du 口径，与 tar 同一批 --exclude）"
  echo "dsh 版本      : $(mget dsh)"
  echo "dpkg ii 数    : $(mget dpkg_ii)"
  echo "cordis 字节   : $(mget cordis)"
  echo "hosts 钉的行  : $(mget hosts)"
  echo "闸门            : 本机自测 3/3 通过；出包前已知凭证串回归 $N 命中；出包后名单闸门 0 命中"
  echo "剥除清单      : 见 scripts/dsh-payload-pack.sh 的 DROP / DSH_KEEP（单一真源，本文件不抄第二份）"
  echo "保留 /root/.dsh: speech-to-text（离线模型）、profiles（层栈）、dsh-purge（备份目录）"
  echo "明确不含      : entry.key、/root/.dsh-env 与它的备份、任何 provider 的 API key、会话/附件/storages/日志、缓存、/tmp、/phone、frida"
} > "$META"
sed 's/^/  /' "$META"
[ "$KEEPROW" = "1" ] && echo "  [keep-raw] raw 留在 $RAW" || rm -f "$RAW"

MB=$(( GZ / 1024 / 1024 ))
echo "== 6 体积档位 : ${MB} MB（上限 ${MAX_MB} MB/卷）"
if [ "$MB" -gt "$MAX_MB" ]; then
  echo "  超了 → split 成多卷（装机脚本按 *-part-* 顺序 cat 回去，再校总 sha）"
  split -b "${MAX_MB}m" "$OUT" "$OUT-part-" && ls -1 "$OUT"-part-* | sed 's/^/    /'
  ( cd "$OUTDIR" && sha256sum "$(basename "$OUT")"-part-* >> SHA256SUMS )
fi
S "rm -f $ROOT/root/$DEVNAME" >/dev/null
echo "  设备侧脚本副本已删：$(S "ls -1 $ROOT/root/$DEVNAME 2>&1" | head -1)"
echo "[done] $OUT"
