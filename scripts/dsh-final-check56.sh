#!/bin/bash
# dsh-final-check56.sh —— 只读现场复点：这一轮交付完之后，机上到底是个什么形状。
# 为什么还要再跑一发：前面每一发探针各自证明各自那半（装的包 / pip 的字节 / 注入的段），
# 但"此刻这盘上是不是还都成立"没有一条汇总读数 —— 而他下次开机看到的就只是"现在"。
# 这一发不写任何文件、不装任何东西、不动 hosts、不重启任何进程。
# 口令：打 :3081 那一下要用 /root/.dsh/entry.key，走 `curl -K -` 从 stdin 递，
#       值绝不进 argv、绝不 echo、绝不落进本文件输出（只报"取到没有"）。
set -u
Q() { printf '\n== %s\n' "$1"; }

Q "0 设备与时间"
echo "uname -a  : $(uname -m -o 2>/dev/null)"
echo "chroot 钟 : $(date '+%F %T %Z')   （chroot 里是 UTC，换算北京时间 +8）"

Q "1 两层服务还在不在（引擎 :3080 / 入口 :3081）"
E=$(pgrep -f 'dsh web' | head -1); N=$(pgrep -f 'dsh-entry.js' | head -1)
echo "引擎 dsh web   pid=${E:-无}  进程数=$(pgrep -cf 'dsh web')"
echo "入口 dsh-entry pid=${N:-无}  进程数=$(pgrep -cf 'dsh-entry.js')"
echo "入口日志末 3 行（只挑与兼容层/读入相关的）："
tail -20 /root/.dsh/entry.log 2>/dev/null | grep -i 'compat\|兼容\|listen\|3081' | tail -3
echo "  （没有相关行不等于没生效 —— 注入层证据在第 5 节的产品字节里）"

Q "2 apt：包数 / 缓存 / 磁盘"
echo "dpkg 记账的包名数 : $(dpkg-query -f 'x\n' -W 2>/dev/null | wc -l)   （本轮装之前 119）"
echo "ii 状态包数       : $(dpkg -l 2>/dev/null | awk '$1=="ii"{n++}END{print n+0}')"
echo "apt 下载缓存      : $(du -sk /var/cache/apt/archives 2>/dev/null | cut -f1) KB / $(ls /var/cache/apt/archives/*.deb 2>/dev/null | wc -l) 个 .deb"
echo "/ 已用            : $(df -k / | awk 'NR==2{print $3}') KB"
echo "/usr 体量         : $(du -sk /usr 2>/dev/null | cut -f1) KB"

Q "3 这轮装进来的东西现在还能跑吗（逐个 command -v + 版本）"
for c in git python3 pip3 gcc g++ make cmake pkg-config ffmpeg convert pdftoppm sqlite3 tmux wget unzip zip file rsync; do
  P=$(command -v "$c" 2>/dev/null)
  if [ -z "$P" ]; then printf '  %-12s !! 不在 PATH\n' "$c"; continue; fi
  V=$("$c" --version 2>&1 | head -1 | cut -c1-40)
  printf '  %-12s %-26s %s\n' "$c" "${P##*/}" "$V"
done

Q "4 解析层：hosts 里那些钉出来的条还撞不撞得上 DoH"
echo "hosts 生效行数（带域名的）: $(awk '!/^[[:space:]]*#/ && NF>=2' /etc/hosts | wc -l)"
echo "pypi.tuna 那条           : $(awk '/pypi\.tuna/{print $1" <- "$2}' /etc/hosts)"
for H in pypi.tuna.tsinghua.edu.cn registry.npmmirror.com awesome-dsh-plugin.com github.com; do
  A=$(curl -sk -m 8 "https://223.5.5.5/resolve?name=$H&type=A" 2>/dev/null |
      sed -n 's/.*"data":"\([0-9.]*\)".*/\1/p' | head -1)
  PIN=$(awk -v d="$H" '!/^[[:space:]]*#/ && $0 ~ d {print $1}' /etc/hosts | head -1)
  if [ -z "$PIN" ]; then S="没钉"
  elif [ -z "$A" ]; then S="钉了 $PIN，DoH 这次没给（不判坏）"
  elif [ "$A" = "$PIN" ]; then S="一致"
  else S="漂了：hosts=$PIN DoH=$A"; fi
  printf '  %-30s %s\n' "$H" "$S"
done

Q "5 兼容层：机上那份 + 出口内联那段（不打印内容，只报字节与计数）"
CF=/root/.dsh/entry-compat.js
echo "机上 $CF : $(wc -c <"$CF" 2>/dev/null) B  md5 $(md5sum <"$CF" 2>/dev/null | cut -c1-32)"
K=/root/.dsh/entry.key
if [ -s "$K" ]; then
  HTML=$(printf 'cookie = dsh-entry=%s\nurl = "http://127.0.0.1:3081/"\n' "$(cat "$K")" |
         curl -sS -m 15 -K - 2>/dev/null)
else
  HTML=""; echo "  !! 口令文件不在（不创建、不猜）"
fi
printf '%s' "$HTML" > /tmp/p56-page.html 2>/dev/null
echo "首页字节           : $(printf '%s' "$HTML" | wc -c)"
echo "data-dsh-entry-compat 标签数 : $(printf '%s' "$HTML" | grep -c 'data-dsh-entry-compat')  （要 1）"
echo "本轮新增那段的两串命中 : $(printf '%s' "$HTML" | grep -c '__DSH_SIDE__') / $(printf '%s' "$HTML" | grep -c 'data-dsh-side-scroll')  （各要 ≥1）"
echo "内联段里裸 </script> 之后的正文是否仍以 <!DOCTYPE 开头 : $(printf '%s' "$HTML" | head -c 9)"
rm -f /tmp/p56-page.html

Q "6 这发探针有没有在机上留东西"
echo "chroot /root 下我的 .sh 份数 : $(ls /root/*.sh 2>/dev/null | wc -l)"
echo "  名字：$(ls /root/*.sh 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ')"
echo "/tmp 剩余探针与临时目录 : $(ls -d /tmp/dsh-* 2>/dev/null | wc -l)"
