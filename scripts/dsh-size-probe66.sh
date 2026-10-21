#!/bin/bash
# 探针 66（只读）—— 把四批工具包的「下载量 / 装完占盘 / 里面到底是什么」量出来。
# 为什么要这一发：上一发（探针 65 ③）两个数都印成「无」。我原来的做法是 grep
#   'Need to get' / 'After this operation' 这两行 —— 这台机上 apt 在 -s（模拟）下
#   根本不印它们（①节把原文行号交出来，不猜）。改成两条自己算的路：
#     下载量 = apt-get install --print-uris -qq 的第 3 字段（字节，包索引里的真尺寸）逐个相加；
#     占盘量 = 计划里每个包的 Installed-Size（单位 KiB）相加。
#   计数一律用进程替换 < <(...) 喂循环：管道会让 while 进子 shell，累加就丢了
#   （AGENTS.md 第 2 条里那条坑，这次别再现一次）。
# 全程不装、不写盘：只用 apt-get -s / --print-uris / apt-cache show。
set -u
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
echo "chroot 内时刻: $(date '+%F %T %Z')"
echo "apt 版本: $(apt-get --version | head -1)"
MB=1048576

echo
echo "== ① 先证那两行到底有没有（文档办公，含 recommends，带行号）"
RAW=$(apt-get -s install libreoffice-writer pandoc 2>&1); RC=$?
echo "   rc=$RC  总行数=$(printf '%s\n' "$RAW" | wc -l)"
printf '%s\n' "$RAW" | grep -nE 'Need to get|additional disk|newly installed|upgrade' | sed 's/^/   /'
echo "   -- 末 4 行："
printf '%s\n' "$RAW" | tail -4 | sed 's/^/   | /'

names() {   # $1=模式 $2=包名串 ⇒ 计划里要新装的包名（去掉 :arch 尾巴），保序去重
  apt-get -s install $1 $2 2>/dev/null \
    | awk '/^Inst /{n=$2; sub(/:.*/,"",n); if(!(n in seen)){seen[n]=1; print n}}'
}
uris() {    # $1=模式 $2=包名串 ⇒ "需下载总字节 其中已在缓存的字节 行数"
  local T=0 C=0 N=0 F SZ B
  while read -r U F SZ REST; do
    [ -n "${SZ:-}" ] || continue
    N=$((N+1)); T=$((T+SZ))
    B=${F##*/}
    if [ -f "/var/cache/apt/archives/$B" ] || [ -f "$F" ]; then C=$((C+SZ)); fi
  done < <(apt-get install --print-uris -qq $1 $2 2>/dev/null)
  echo "$T $C $N"
}
kbmap() {   # $1=包名串 ⇒ 每个包一行 "KiB 包名"（Installed-Size 单位是 KiB，取每包第一条）
  apt-cache show $1 2>/dev/null | awk '
    /^Package: /{p=$2; next}
    /^Installed-Size: /{ if(!(p in s)){s[p]=$2+0} }
    END{for(q in s) printf "%d %s\n", s[q], q}'
}

echo
echo "== ② 四批 × 两口径：包数 / 要下多少 / 缓存里已有 / 装完占多少"
printf '   %-9s %-24s %5s %11s %11s %11s\n' 批次 口径 包数 需下载 已在缓存 装完占盘
for B in "文档办公:libreoffice-writer pandoc" "OCR:tesseract-ocr" "语言栈:rustc golang-go default-jdk" "容器:docker.io podman"; do
  L=${B%%:*}; K=${B#*:}
  for MODE in "" "--no-install-recommends"; do
    NM=$(names "$MODE" "$K"); N=$(printf '%s\n' "$NM" | grep -c .)
    read -r T C UN <<<"$(uris "$MODE" "$K")"
    KB=$(kbmap "$NM"); TOT=$(printf '%s\n' "$KB" | awk '{s+=$1} END{print s+0}')
    printf '   %-9s %-24s %5s %9.1fM %9.1fM %9.1fM   （下载行=%s 元数据包=%s）\n' \
      "$L" "${MODE:-含 recommends}" "$N" \
      "$(awk -v x="$T" -v m=$MB 'BEGIN{print x/m}')" \
      "$(awk -v x="${C:-0}" -v m=$MB 'BEGIN{print x/m}')" \
      "$(awk -v x="$TOT" 'BEGIN{print x/1024}')" "$UN" "$(printf '%s\n' "$KB" | grep -c .)"
  done
done

echo
echo "== ③ 每批里占盘最大的 10 件（含 recommends）——「这批到底装了些什么」的答案"
for B in "文档办公:libreoffice-writer pandoc" "OCR:tesseract-ocr" "语言栈:rustc golang-go default-jdk" "容器:docker.io podman"; do
  L=${B%%:*}; K=${B#*:}
  echo "-- $L（$K）"
  kbmap "$(names '' "$K")" | awk '{printf "%9.1f MB  %s\n", $1/1024, $2}' | sort -rn | head -10 | sed 's/^/     /'
done

echo
echo "== ④ recommends 多带进来的那部分（含 - 不含 的差集）"
for B in "文档办公:libreoffice-writer pandoc" "OCR:tesseract-ocr" "语言栈:rustc golang-go default-jdk" "容器:docker.io podman"; do
  L=${B%%:*}; K=${B#*:}
  D=$(comm -23 <(names '' "$K" | sort) <(names '--no-install-recommends' "$K" | sort))
  ND=$(printf '%s\n' "$D" | grep -c .)
  DS=$(kbmap "$D" | awk '{s+=$1} END{printf "%.1f MB", s/1024}')
  echo "-- $L：差集 $ND 个，合计 ${DS:-0}"
  kbmap "$D" | awk '{printf "%9.1f MB  %s\n", $1/1024, $2}' | sort -rn | head -6 | sed 's/^/     /'
done

echo
echo "== ⑤ 现状对照（不动盘）"
echo "   dpkg 已装: $(dpkg -l 2>/dev/null | grep -c '^ii') 个包"
echo "   apt 缓存: $(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1) / $(ls /var/cache/apt/archives/*.deb 2>/dev/null | wc -l) 个 .deb"
echo "   四批里已在位的命令: $(for c in soffice pandoc tesseract rustc go java docker podman git python3; do command -v $c >/dev/null 2>&1 && printf '%s ' $c; done)"
echo "   磁盘: $(df -h / | awk 'NR==2{print $4" 可用 / 共 "$2}')"
echo
echo "== ⑥ 这发留没留东西"
echo "   /root/*.sh: $(ls /root/*.sh 2>/dev/null | wc -l)   /tmp 顶层: $(ls -A /tmp 2>/dev/null | wc -l)"
