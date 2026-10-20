#!/bin/bash
# tools/doh-hosts.sh —— 在**手机上**用 DoH 把域名解析成 IP 并钉进 chroot 的 /etc/hosts。
#
# 为什么需要它（2026-10-21 凌晨量出来的形状，读数在 downloads/p26–p31.txt）：
#   这台机的 UDP 53 基本是废的：对没钉过的域名问 10 秒给空（境内境外一视同仁），
#   对被墙的域名倒能给答案 —— 给的是 Facebook 段的假 IP（huggingface.co ⇒ 104.244.46.9 / 157.240.8.36）。
#   而 443 出站本身是通的：拿真 IP 直连，tuna 的 apt 源 Range 206 真落字节、npmmirror 跟 302 落 2774 B 且 tar 解得开、
#   github.com 与 codeload 各在 30 秒里传回 676,496 B / 790,533 B（约 22–26 KB/s，慢但活着）。
#   ⇒ 病在**解析**这一层。手机侧唯一干净的解析路是阿里的 DoH：https://223.5.5.5/resolve（实测 200 且给真答案）。
#   所以"以后是不是全得靠电脑"的正解不是每次 push，而是把解析这一层在手机上自己补上。
#
# 它干什么：--sync 把清单里缺的域名问一次 DoH、追加进 hosts；--check 只报不写（每条已钉的域名现在 DoH 给什么、
#           还撞不撞得上 hosts 里那个 IP —— IP 会漂，钉过的条会**悄悄地坏**，这条不查就永远不知道）。
# 它不干什么：不写 resolv.conf、不装包、不改系统侧任何配置、不删已有条目。
# 退回：--sync 之前先逐字节备份到 /root/.dsh/hosts.bak.<时间戳>，--revert <备份路径> 原样还原并复点 sha256。
set -u
HOSTS=/etc/hosts
# 分两摞，差别是有没有实测过"拿这个 IP 连得上"：
#   LIST_PIN —— p28/p31 从手机侧实测可达（tuna 的 Range 206 真落字节、npmmirror 跟转 200 且解得开、
#                aliyun 301 / modelscope 302 / gitee 200 / hf-mirror 200 / github 与 codeload 慢但传字节），
#                只有这些会被 --sync 钉进 hosts；
#   LIST_WATCH —— 钉了也连不上的（境外 CDN：raw 那台 185.199.108.133 在 0.118 秒内直接失败、
#                npmjs 的 104.16.x、Canonical 的 91.189.x 没实测过），--check 只报不写。
#                把连不通的 IP 钉进去不会让下载变通，只会让"失败"从"解析超时"变成"连接被拒"，
#                反而更难查，所以默认不钉。
LIST_PIN="
api.deepseek.com platform.deepseek.com
github.com codeload.github.com objects.githubusercontent.com
registry.npmmirror.com cdn.npmmirror.com
mirrors.tuna.tsinghua.edu.cn deb.debian.org
hf-mirror.com www.modelscope.cn modelscope.cn gitee.com mirrors.aliyun.com
"
LIST_WATCH="raw.githubusercontent.com registry.npmjs.org ports.ubuntu.com archive.ubuntu.com security.ubuntu.com cdn.jsdelivr.net"
LIST_DEFAULT="$LIST_PIN $LIST_WATCH"
DOH=https://223.5.5.5/resolve
MODE=${1:---check}

doh_a() { # 域名 ⇒ 逗号连接的 A 记录（无答案就回空）
  curl -sk -m 10 "$DOH?name=$1&type=A" 2>/dev/null |
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);
      console.log((j.Answer||[]).filter(x=>x.type===1).map(x=>x.data).join(","));}catch(e){console.log("");}});'
}

case "$MODE" in
  --check)
    echo "== 逐条对账：hosts 里钉的 IP vs DoH 现在给的答案（只读，不写）"
    printf '%-34s %-18s %s\n' 域名 hosts里的IP DoH现在的A记录
    # 只点带点的名字（hosts 里那两条 localhost 别名拿去问 DNS 只会出噪声）
    for H in $(awk '!/^[[:space:]]*#/ && NF>=2 {for(i=2;i<=NF;i++) if($i ~ /[.]/) print $i}' "$HOSTS" 2>/dev/null | sort -u); do
      PIN=$(awk -v d="$H" '!/^[[:space:]]*#/ && $2==d {print $1}' "$HOSTS" | head -1)
      printf '%-34s %-18s %s\n' "$H" "${PIN:-—}" "$(doh_a "$H")"
    done
    echo
    echo "== 清单里还没钉的（PIN 那摞下次要用就 --sync；WATCH 那摞钉了也连不通，只报给你看）"
    for H in $LIST_DEFAULT; do
      grep -qE "[[:space:]]$H\$" "$HOSTS" && continue
      case " $LIST_PIN " in *" $H "*) T=可钉 ;; *) T=只看不钉 ;; esac
      printf '  %-32s %-8s ⇒ %s\n' "$H" "$T" "$(doh_a "$H")"
    done
    ;;
  --sync)
    [ -f "$HOSTS" ] || { echo "!! $HOSTS 读不到"; exit 1; }
    SHA0=$(sha256sum "$HOSTS" | cut -d' ' -f1)
    BAK="/root/.dsh/hosts.bak.$(date +%Y%m%d-%H%M%S)"
    mkdir -p /root/.dsh && cp -p "$HOSTS" "$BAK"
    [ "$(sha256sum "$BAK" | cut -d' ' -f1)" = "$SHA0" ] || { echo "!! 备份没撞上原文件，停手不写"; exit 1; }
    echo "[ok] 先逐字节备份到 $BAK（sha256 与 $HOSTS 相同：$SHA0）"
    ADD=0; SKIP=0; NONE=0
    for H in $LIST_PIN; do
      if grep -qE "[[:space:]]$H\$" "$HOSTS"; then SKIP=$((SKIP+1)); continue; fi
      A=$(doh_a "$H"); FIRST=${A%%,*}
      if [ -z "$FIRST" ]; then echo "  [无答案] $H —— 跳过（DoH 也没给，写进去只会更坏）"; NONE=$((NONE+1)); continue; fi
      printf '%s\t%s\n' "$FIRST" "$H" >> "$HOSTS"
      # 候选条数用 echo 不是 printf：wc -l 数的是换行，printf '%s' 末尾不带换行 ⇒ 每条都少报 1
      #（2026-10-21 实测：hf-mirror 只有 1 个候选时它印「给了 0 条」，gitee 3 个印 2、aliyun 16 个印 15）
      printf '  [+钉] %-34s %s（DoH 给了 %s 条候选）\n' "$H" "$FIRST" "$(echo "$A" | tr ',' '\n' | wc -l)"
      ADD=$((ADD+1))
    done
    echo "== 结果：新增 $ADD 条、本来就在 $SKIP 条、问不到 $NONE 条"
    echo
    echo "== 钉完之后不再用 --resolve 直发一发（这一步才算「解析层修好了」，不然是自欺）"
    for H in hf-mirror.com gitee.com mirrors.aliyun.com www.modelscope.cn; do
      printf '  %-24s 不带 --resolve ⇒ %s\n' "$H" \
        "$(curl -s -o /dev/null -m 12 -w 'http=%{http_code} time=%{time_total}s' "https://$H/" 2>&1)"
    done
    echo "   退回：bash $0 --revert $BAK"
    ;;
  --revert)
    B=${2:?--revert 后面要给备份文件路径}
    [ -f "$B" ] || { echo "!! 备份不在：$B"; exit 1; }
    cp -p "$B" "$HOSTS"
    S1=$(sha256sum "$B" | cut -d' ' -f1); S2=$(sha256sum "$HOSTS" | cut -d' ' -f1)
    [ "$S1" = "$S2" ] && echo "[ok] $HOSTS 已还原成 $B（sha256 $S1）" || { echo "!! 还原后 sha 不撞：$S1 vs $S2"; exit 1; }
    ;;
  *) echo "用法：bash tools/doh-hosts.sh [--check|--sync|--revert <备份>]"; exit 2 ;;
esac
