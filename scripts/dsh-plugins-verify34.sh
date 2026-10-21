#!/bin/bash
# scripts/dsh-plugins-verify34.sh —— 插件装完之后，只看盘，把 install 脚本里那两个「假读数」重取一遍。
#
# 为什么还要再来一发：tools/install-phone-plugins.sh 第 5 步我用了 `echo package.json=$(wc -c <package.json)`，
# 三层引号送到机上后那个 $() 是**被最外层 /system/bin/sh 求值**的（那儿没有 package.json），
# 于是打出 `package.json= B`（空）和 `非隐藏条目=0`（而它上面自己列出的 5 条就在旁边）。
# 这是 AGENTS 铁律 2「子 shell 丢计数器」在三层引号下的第三种形状。
# 本探针整份文件先推成 /root/<name>，再交给 chroot 里的 bash 跑，所有 $( ) 都在同一个 bash 里，计数才可信。
#
# 全程只读：不写盘、不装包、不重启引擎。唯一执行类动作是 `dsh plugin list`（只转发 pnpm list）。
# 跑法：bash tools/run-probe.sh scripts/dsh-plugins-verify34.sh downloads/p34.txt
set -u
export LANG=C
PROFILE=web
P=/root/.dsh/profiles/$PROFILE

echo "== 0. 时刻与身份（chroot 是 UTC，文档按北京时间，差 8 小时）"
date -u '+  UTC  %F %T'
echo "  whoami=$(id -un) uid=$(id -u)  uname=$(uname -m)"

echo "== 1. profile 目录本身（逐个文件给字节，不糊进同一个 subshell）"
for f in package.json pnpm-lock.yaml pnpm-workspace.yaml cordis.patch.yml cordis.yml; do
  printf '  %-22s ' "$f"
  stat -c '%s B  mtime=%F %TZ  mode=%a' "$P/$f" 2>&1
done
echo "  --- package.json 全文"
sed 's/^/    /' "$P/package.json" 2>&1
echo "  --- bundles 名单（数名字不数行数）"
sed -n '/"bundles"/,/]/p' "$P/package.json" | grep -oE '"[^"]+"' | grep -vx '"bundles"' | sed 's/^/      /'
echo "    bundles 计数 = $(sed -n '/"bundles"/,/]/p' "$P/package.json" | grep -oE '"[^"]+"' | grep -vx '"bundles"' | wc -l)"
echo "  --- dependencies 里两条 file: 指向"
grep -oE '"(dsh-purge|dshmarket)": *"file:[^"]*"' "$P/package.json" | sed 's/^/      /'
echo "    file: 引用计数 = $(grep -cE '"(dsh-purge|dshmarket)": *"file:' "$P/package.json")（要 2）"

echo "== 2. node_modules 真实条目数（这次在同一个 bash 里数）"
echo "  node_modules 在 = $([ -d "$P/node_modules" ] && echo yes || echo no)"
ALL=$(ls -1A "$P/node_modules" 2>/dev/null | wc -l)
VIS=$(ls -1 "$P/node_modules" 2>/dev/null | wc -l)
echo "  ls -1A（含隐藏）= $ALL / ls -1（可见）= $VIS"
ls -1 "$P/node_modules" 2>/dev/null | sed 's/^/      /'
echo "  .pnpm 虚拟仓条目 = $(ls -1 "$P/node_modules/.pnpm" 2>/dev/null | wc -l)"
ls -1 "$P/node_modules/.pnpm" 2>/dev/null | sed 's/^/      /'

echo "== 3. 两发插件的真身与它们自带的 bundle 元数据"
for b in dsh-purge dshmarket; do
  echo "  --- $b"
  echo "    解引用 = $(readlink -f "$P/node_modules/$b" 2>/dev/null || echo 读不到)"
  echo "    目录条目 = $(ls -1A "$P/node_modules/$b" 2>/dev/null | wc -l)  体积 = $(du -sh "$P/node_modules/$b" 2>/dev/null | cut -f1)"
  ls -1 "$P/node_modules/$b" 2>/dev/null | sed 's/^/      /'
  if [ -f "$P/node_modules/$b/package.json" ]; then
    node -e '
      const j=require(process.argv[1]); const d=j.dsh||{};
      console.log("name="+j.name+"  version="+j.version);
      console.log("dsh.bundle="+JSON.stringify(d.bundle||null));
      console.log("dsh.client="+JSON.stringify(d.client||null));
      console.log("main="+String(j.main)+"  bin="+JSON.stringify(j.bin||null));
    ' "$P/node_modules/$b/package.json" 2>&1
    echo "    （以上四行取自它自己的 package.json）"
  else
    echo "    !! 没有 package.json"
  fi
  echo "    它自带的 cordis.patch.yml = $(stat -c '%s B' "$P/node_modules/$b/cordis.patch.yml" 2>/dev/null || echo 无)"
done

echo "== 4. 装它俩依赖的那两份 tarball 还在不在（package.json 里是 file: 引用，删了下次重装就断）"
ls -1 /root/dsh-plugins 2>/dev/null | sed 's/^/    /'
echo "    条目数 = $(ls -1 /root/dsh-plugins 2>/dev/null | wc -l)（要 2）"
n=0
for f in /root/dsh-plugins/*.tgz; do
  [ -f "$f" ] || continue
  n=$((n+1))
  echo "    sha256 $(sha256sum "$f" | cut -c1-16)  $(stat -c %s "$f") B  $(basename "$f")"
done
echo "    逐条数过 = $n（要 2；本地记的是 7f43fb873782c7ed / 5267bdcdf66ab16d）"

echo "== 5. pnpm 内容寻址仓与体积（装之前 p32 记的：/root/.dsh 232M、profiles 45K）"
echo "  store = $(du -sh /root/.local/share/pnpm/store 2>/dev/null | cut -f1)"
echo "  profile = $(du -sh "$P" 2>/dev/null | cut -f1)"
echo "  /root/.dsh = $(du -sh /root/.dsh 2>/dev/null | cut -f1)"
echo "  /root/dsh-plugins = $(du -sh /root/dsh-plugins 2>/dev/null | cut -f1)"
df -h / | awk 'NR>1{print "  盘上可用 "$4"  已用 "$5}'

echo "== 6. dsh 自己认不认这两发（只 list，不 add/remove）"
cd "$P" 2>/dev/null || echo "  !! cd $P 失败"
echo "  --- dsh plugin --profile $PROFILE list（超时 120 s）"
timeout 120 dsh plugin --profile $PROFILE list 2>&1 | sed 's/^/      /'
echo "  list_rc=${PIPESTATUS[0]}（PIPESTATUS：sed 的 0 不算，要的是 dsh 那个）"

echo "== 7. 运行时目录（电脑上那台装了之后会生 .plugin-manager 与 .dsh-market；这台引擎还没重启过）"
for d in .plugin-manager .dsh-market; do
  printf '  %-16s ' "$d"
  if [ -d "$P/$d" ]; then
    echo "在，条目 $(ls -1A "$P/$d" | wc -l)"
    ls -1A "$P/$d" | sed 's/^/      /'
  else
    echo "还没有"
  fi
done

echo "== 8. 引擎是哪一秒生的、package.json 是哪一秒改的（要不要重启只看这个先后）"
NOW=$(date +%s)
HZ=$(getconf CLK_TCK)
for pid in $(pgrep -f 'node' 2>/dev/null); do
  args=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | cut -c1-70)
  case "$args" in *dsh*|*node*) ;; *) continue;; esac
  st=$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || echo 0)
  [ "$st" != 0 ] || continue
  up=$(awk '{print $1}' /proc/uptime | cut -d. -f1)
  born=$(( NOW - up + st / HZ ))
  printf '  pid %-6s 活 %6s s  出生 %s  %s\n' "$pid" "$(( NOW - born ))" "$(date -u -d "@$born" '+%F %T')Z" "$args"
done
PKG=$(stat -c %Y "$P/package.json")
echo "  package.json mtime = $(date -u -d "@$PKG" '+%F %T')Z"
echo "  引擎（17611）出生 = $(stat -c %Y /proc/17611 2>/dev/null | awk -v p="$PKG" '{if ($1<p) print "早于 package.json ⇒ 新 bundle 还没进层栈"; else print "晚于"}')"

echo "== 9. 日志里有没有它自己报加载了哪几层（只数命中行，不 cat 全文）"
LOGC=0
for l in $(find /root/.dsh /root /tmp -maxdepth 2 -name '*.log' -newermt '-72 hours' 2>/dev/null | head -6); do
  LOGC=$((LOGC+1))
  echo "  --- $l（$(stat -c %s "$l") B，mtime $(stat -c %y "$l" | cut -c1-19)）"
  echo "      dsh-purge 命中 $(grep -c 'dsh-purge' "$l" 2>/dev/null) 行 / dshmarket 命中 $(grep -c 'dshmarket' "$l" 2>/dev/null) 行"
done
echo "  找到的 log 数 = $LOGC"

echo "== 10. 与电脑上那台（desktop profile）对照（PC 侧 10-21 15:23 装完实测：可见 5、.pnpm 1、有 .plugin-manager 与 .dsh-market）"
echo "  本机可见条目 = $VIS / .pnpm = $(ls -1 "$P/node_modules/.pnpm" 2>/dev/null | wc -l)"
echo "  完（本探针没写任何盘）"
