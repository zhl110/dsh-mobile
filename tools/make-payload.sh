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
#   2) 报数只认同源：产物先在**设备上**打成 tar.gz，机上数一遍条目数与 sha256，PC 拉回后再数一遍 —— 两边必须相等；
#      不拿另一套 find 口径去凑（2026-11-03：这台机 adbd 不能带二进制流，见第 2 步那段注释）。
#
# 用法（在 D:\mycode\dsh-mobile 下跑）：
#   bash tools/make-payload.sh --dry        只读普查：清单/保留体积/留剥什么/敏感名/凭证命中；不出包
#   bash tools/make-payload.sh              出包到 release-assets/（超过 MAX_MB 自动 split 成多卷）
#   bash tools/make-payload.sh --keep-raw   出包并**保留机上那份 tar.gz**（默认拉回后当场删掉）
#   bash tools/make-payload.sh --publish      出完直接挂 Release（tag = payload-<UTC>，读回资产才算成）
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
KEEPROW=0; case " $* " in *" --keep-raw "*) KEEPROW=1;; esac
PUB=0; case " $* " in *" --publish "*) PUB=1;; esac

# 引号形状照 tools/run-probe.sh:45：外层双引号给 adb、转义双引号给 su -c —— 这样命令串里可以出现单引号
S() { "$ADB" shell "su -c \"$1\"" </dev/null 2>&1 | tr -d '\r'; }
# $* 而不是 $1：--pack 要带产物路径（11-03 第一次实跑就栽在这儿 —— CHRUN 只转 $1，
# 设备侧读到 OUT_ARG 为空 ⇒ 自己拒绝打包并回 rc=2，PC 侧那道"没读到 tar rc=0 就不发布"的闸门把它拦住了）
CHRUN() { "$ADB" shell "su -c \"$RUNNER --run 'bash /root/$DEVNAME $*'\"" </dev/null 2>&1 | tr -d '\r'; }

[ -f "$SCRIPT" ] || { echo "!! 缺设备侧那一半：$SCRIPT"; exit 1; }
bash -n "$SCRIPT" || { echo "!! $SCRIPT 语法不过"; exit 1; }
CR=$(tr -cd '\r' < "$SCRIPT" | wc -c); [ "$CR" = "0" ] || { echo "!! $SCRIPT 有 $CR 个 CR，先 dos2unix"; exit 1; }
if [ "$MODE" != "--dry" ]; then
  echo "== -1 先在本机把闸门自测一遍（同一份脚本，五种形状：埋雷要抓到 / 撤雷要 0 且当场取到过串 / 凭证源空要报"取不到串" / shadow 替代件要锁掉 root 且不残留原哈希 / 原件读不到要报错而不是产空件）"
  ST_OUT=$(bash "$SCRIPT" --selftest 2>&1)
  [ "$?" = 0 ] || { printf '%s\n' "$ST_OUT" | sed 's/^/  /'; echo "!! 闸门自测不过 —— 闸门本身坏了，这时候的"0 命中"不作数，不出包"; exit 1; }
  ST_SUM=$(printf '%s\n' "$ST_OUT" | grep '合计' | tail -1)
  echo "  ${ST_SUM:-没读到自测合计行}"
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
echo "== 2 机上打成 tar.gz（落 chroot /tmp —— tar 的字节流不能过 adb，见下面注释）"
# 2026-11-03 实测（读数在 RUNBOOK 14.40）：这台机的 adbd 两个口都不能带二进制 ——
#   exec-out ：tar 直接报 "Refusing to write archive contents to terminal"（su 的 fd1 是 /dev/pts/0），
#             于是 PC 收到的"raw tar"其实只有 427 B 的诊断文本，rc 还是 0。
#   shell    ：fd1 是 socket，64 KiB 全换行的流测过（md5 与机上逐字节撞上）**不是转译**；
#             但 120 MB 那一发收到 120,974,137 B（tar 应为 120,359,424，多 614,713），解出的成员长度对、md5 不撞。
#   ⇒ 大流不可信，只能走文件 + adb pull（pull 是 file-sync，且拉回来必撞 sha256 才算数）。
#   /tmp 在设备侧 DROP 里（scripts/dsh-payload-pack.sh 第 27 行那批），所以产物不会被自己打进包。
DEV_GZ=/tmp/dsh-rootfs-payload.tar.gz          # chroot 里的路径
HOST_GZ=$ROOT/tmp/dsh-rootfs-payload.tar.gz    # 宿主上看到同一个文件
T0=$(date +%s)
PACK_OUT=$(CHRUN --pack "$DEV_GZ")
printf '%s\n' "$PACK_OUT" | grep '^\[pack\]' | sed 's/^/  /'
DEV_SHA=$(printf '%s\n' "$PACK_OUT" | sed -n 's/^\[pack\] gz .*sha256 \([0-9a-f]\{64\}\).*/\1/p' | tail -1)
DEV_BYTES=$(printf '%s\n' "$PACK_OUT" | sed -n 's/^\[pack\] gz \([0-9]\{1,\}\) B.*/\1/p' | tail -1)
DEV_ENT=$(printf '%s\n' "$PACK_OUT" | sed -n 's/^\[pack\] gz .*条目 \([0-9]\{1,\}\).*/\1/p' | tail -1)
printf '%s\n' "$PACK_OUT" | grep -q '\[pack\] tar rc=0' || { echo "!! 没读到 [pack] tar rc=0 ⇒ 机上那一发没成，不拉不回、不发布"; exit 1; }
[ -n "$DEV_SHA" ] || { echo "!! 没读到机上产物的 sha256 ⇒ 无法验拉回来的字节，停"; exit 1; }
echo "  机上产物 : ${DEV_BYTES:-?} B / 条目 ${DEV_ENT:-?} / sha256 ${DEV_SHA:0:12}…  耗时 $(( $(date +%s) - T0 )) 秒"

echo "== 3 拉回 PC 并逐字节撞机上那发 sha256"
TS=$(date -u +%Y%m%d-%H%M%SZ)
OUT=$OUTDIR/dsh-rootfs-$TS.tar.gz
T1=$(date +%s)
PULL_OUT=$("$ADB" pull "$HOST_GZ" "$OUT" 2>&1 </dev/null); RC=$?
printf '%s\n' "$PULL_OUT" | tr -d '\r' | sed 's/^/  /'
[ "$RC" = 0 ] || { echo "!! adb pull 退出码 $RC"; exit 1; }
GZ=$(wc -c <"$OUT" | tr -dc '0-9')
SHA=$(sha256sum "$OUT" | cut -d' ' -f1)
echo "  产物 : $OUT  $GZ B  耗时 $(( $(date +%s) - T1 )) 秒"
[ "$GZ" = "${DEV_BYTES:-0}" ] || { echo "!! 字节数不撞（机上 $DEV_BYTES / PC $GZ）"; exit 1; }
[ "$SHA" = "$DEV_SHA" ] && echo "  [ok] sha256 与机上逐字节撞上：${SHA:0:12}…" || { echo "!! sha256 不撞（机上 $DEV_SHA / PC $SHA）⇒ 这条链路不可信，停"; exit 1; }
gzip -t "$OUT" && echo "  [ok] gzip -t 过" || { echo "!! gz 坏了"; exit 1; }
ENT_GZ=$(tar -tzf "$OUT" 2>/dev/null | wc -l | tr -dc '0-9')
[ "$ENT_GZ" = "${DEV_ENT:-x}" ] && echo "  [ok] 条目数机上与 PC 各数一遍相等：$ENT_GZ" || { echo "!! 条目不等 机上=$DEV_ENT gz=$ENT_GZ"; exit 1; }
if [ "$KEEPROW" = "1" ]; then echo "  （--keep-raw：机上那份留在 $HOST_GZ，不删）"; else S "rm -f $HOST_GZ" >/dev/null; echo "  机上那份已删：$(S "ls $HOST_GZ 2>&1 | head -1" | tr -d '\r')"; fi

echo "== 4 名单闸门（闸门二：敏感名命中就停）"
# ^\./etc/shadow$ 是 11-03 加的：原件带 root 口令哈希，一律不进包（包里改发一份 root 锁掉的替代件，
# 落在 ./root/payload-stage/etc/shadow —— 那条名字**不该**被这条 pattern 抓到，所以必须锚死整行）。
# /redteam/ 从"拦"降到"打印"（11-03 真产物读数）：46 条全在 node_modules/dsh-purge/ 底下
#   （lib/redteam/*.js 与 skills/redteam/*.md —— 那是他装的插件自带的代码与说明书，不是这台机写出来的数据）。
#   判据按"名字属于谁"分：**这台机写过的东西**（口令/会话/用户数据）命中就拦；上游包目录里的同名词只报数。
#   这与今天早些那条"词形当闸门必误报"是同一族，只是这次的边界是"路径属于谁"而不是"词长得像不像"。
#   剩下 frida 仍在拦的那边 —— 那一发闸门抓到的是 9 条 pip 元数据残件，是真该排掉的（已在 DROP 改成 frida*）。
RE='entry\.key|session\.v4|/\.dsh-env|bash_history|/\.ssh/|^\./phone/|/\.npm/|apt/archives|/attachments/|/llm-deepseek/|frida|/\.dsh/logs/|/\.dsh/storages/|/\.dsh/cache/|^\./etc/shadow$'
RE_REF='/redteam/'
tar -tzf "$OUT" > /tmp/payload-members.txt 2>/dev/null
BAD=$(grep -cE "$RE" /tmp/payload-members.txt)
REF=$(grep -cE "$RE_REF" /tmp/payload-members.txt)
echo "  拦的那批命中 : $BAD 条（要 0）；参考（上游插件内的同名词）: $REF 条"
[ "$BAD" = "0" ] || { grep -E "$RE" /tmp/payload-members.txt | head -12 | sed 's/^/    /'; echo "!! 闸门不过：$OUT 别推，删掉重打"; exit 1; }
[ "$REF" = 0 ] || { grep -E "$RE_REF" /tmp/payload-members.txt | sed -n '1,2p;$p' | sed 's/^/    /'; echo "    （这 $REF 条随插件源码一起走，是他装的那个插件的内容，不是这台机的数据）"; }
ALT=$(grep -c '^./root/payload-stage/etc/shadow$' /tmp/payload-members.txt)
echo "  [ok] 名单干净；条目数 $ENT_GZ；shadow 替代件在位 = $ALT（要 1；0 ⇒ 装机那步会缺 /etc/shadow，见 install-from-scratch 3b）"

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
  echo "打包方式      : tar -czf 在设备上完成（GZIP=-1），adb pull 拉回后逐字节撞机上那发 sha256；raw 不曾到过 PC —— 这台机的 adb 两个口都带不了二进制流"
  echo "条目数        : 机上 $DEV_ENT / PC 拉回后 $ENT_GZ（同一件产物各数一遍，必须相等）"
  echo "机上保留体积  : $(mget kept_du) B（du 口径，与 tar 同一批 --exclude）"
  echo "dsh 版本      : $(mget dsh)"
  echo "dpkg ii 数    : $(mget dpkg_ii)"
  echo "cordis 字节   : $(mget cordis)"
  echo "hosts 钉的行  : $(mget hosts)"
  echo "闸门            : 本机自测 ${ST_SUM:-没读到}；出包前已知凭证串回归 $N 命中；出包后名单闸门拦下的那批 $BAD 命中（另有 $REF 条是上游插件目录里的同名词，只报数不拦）"
  echo "剥除清单      : 见 scripts/dsh-payload-pack.sh 的 DROP / DSH_KEEP（单一真源，本文件不抄第二份）"
  echo "保留 /root/.dsh: speech-to-text（离线模型）、profiles（层栈）、dsh-purge（备份目录）"
  echo "明确不含      : entry.key、/root/.dsh-env 与它的备份、任何 provider 的 API key、会话/附件/storages/日志、缓存、/tmp、/phone、frida、/etc/shadow 原件（不管 root 那栏是不是哈希都不发；包里发的是 root 锁掉的替代件，装机脚本 3b 放回）"
  echo "装机验证状态  : tools/install-from-scratch.sh（含 3b）**未在干净机上实机跑过** —— 本包只验到两道闸门与本机自测，'装完能用'目前只有设计证据、没有实测读数"
} > "$META"
sed 's/^/  /' "$META"

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

# --publish = 出包完直接挂 Release（他 11-03 那句"先不验证，直接提交"）。
# 传哪几件：超档切卷时**只传卷**（原件不重复传一遍 GB），加 SHA256SUMS 与 payload-meta.txt。
if [ "$PUB" = 1 ]; then
  command -v gh >/dev/null || { echo "!! 要 gh（本机路径：C:\\Users\\周海龙\\AppData\\Local\\Microsoft\\WinGet\\Links\\gh.exe）"; exit 1; }
  TAG=payload-$TS
  ASSETS=("$OUTDIR/SHA256SUMS" "$META")
  if ls "$OUT"-part-* >/dev/null 2>&1; then
    while IFS= read -r f; do ASSETS+=("$f"); done < <(ls -1 "$OUT"-part-*)
  else
    ASSETS=("$OUT" "${ASSETS[@]}")
  fi
  echo "== 7 挂 Release : tag $TAG，资产 ${#ASSETS[@]} 件"
  printf '    %s\n' "${ASSETS[@]}"
  NOTES="Ubuntu 24.04 arm64 chroot + Node + dsh 0.2.1-rc.2 的整棵运行时，供 tools/install-from-scratch.sh 一键装。"
  NOTES="${NOTES}仓里没有这些大件是格式问题不是配额问题（git 存不了属主与 setuid 位）。"
  NOTES="${NOTES}包内不含：入口口令、provider 的 API key、会话与日志、缓存、/tmp、/phone、frida、/etc/shadow 原件。"
  NOTES="${NOTES}装完第一件事是在网页里填你自己的 key。读数与清单见随包的 payload-meta.txt，做法见 docs/INSTALL-from-scratch.md。"
  NOTES="${NOTES}如实说：install-from-scratch.sh 这条安装流程未在干净机上实机跑过（作者手上只有那台现役机），'装完能用'目前只有设计证据、没有实测读数；包里两道泄露闸门有本机自测兜住。"
  CRE_OUT=$(MSYS2_ARG_CONV_EXCL='*' gh release create "$TAG" --repo zhl110/dsh-mobile \
    --title "dsh-mobile rootfs payload $TS" --notes "$NOTES" "${ASSETS[@]}" 2>&1); RCP=$?
  printf '%s\n' "$CRE_OUT" | tr -d '\r' | sed 's/^/  /'
  echo "  create 退出码 : $RCP"
  VIEW_OUT=$(MSYS2_ARG_CONV_EXCL='*' gh release view "$TAG" --repo zhl110/dsh-mobile --json tagName,assets \
    -q '"tag=" + .tagName + " 资产 " + (.assets|length|tostring) + " 件：" + ([.assets[]|(.name + "=" + (.size|tostring) + "B " + (.digest // "无摘要"))]|join(", "))' 2>&1); VIEWRC=$?
  echo "  复点（只认读回来的资产，不认退出码）:"
  printf '%s\n' "$VIEW_OUT" | tr -d '\r' | sed 's/^/    /'
  [ "$RCP" = 0 ] && [ "$VIEWRC" = 0 ] || { echo "!! 上面两发有一发没成 ⇒ 别当成已发布（退出码：create=$RCP view=$VIEWRC）"; exit 1; }
  echo "  [ok] Release 已挂上：https://github.com/zhl110/dsh-mobile/releases/tag/$TAG"
fi
