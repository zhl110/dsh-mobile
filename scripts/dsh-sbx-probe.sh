#!/bin/sh
# dsh-sbx-probe.sh — 被 dsh-unshare-run 围住之后跑的"探针"，每项打一行 KEY=VALUE
#
# 为什么单独成文件（本轮实测教训）：判据要经过 宿主 mksh → chroot → bash -lc "..." → runner → bash -c '...'
# 四层引号，第 57 行那句 mount | grep " /tmp " 就是这么把 bash 打成
#   /bin/bash: -c: line 1: unexpected EOF while looking for matching `''
# 的。把判断逻辑放进这个文件，外层只剩"拼参数 + grep KEY="，引号塌回一层。
#
# 部署位置：chroot:/root/dsh-sbx-probe.sh（0755）。它要在围住之前写进去——围住后 /root 是只读的，
# 但只读≠读不到，ns 里的命令照样能读它。
#
# 红线：这里 rm 的对象只允许是 dsh-sbx-probe-* 这种我们自己造的文件。/dev/null 那条走 wonly，
# 绝不能 rm——/dev 是从宿主 rbind 进来的同一个文件系统，在 ns 里删掉的就是真 /dev/null。
set -u

# 造靶子→试写→报读数→自己擦掉（只擦自己造的普通文件）
# 那层 { …; } 2>&1 是必须的，不是风格：dash 把"重定向失败"这句话打在**shell 自己的 stderr**上，
# 不塞进 $()。第一版没包组，实测读数是 ETC=BLOCK:（原因为空），围堵判据退化成"整发输出里 grep 得到
# read-only 就行"——那已经不再逐条验证 dialect 了。包上组才能把原文取回来。
wt() {
  if err=$( { echo x > "$1"; } 2>&1 ); then
    printf 'OPEN'
  else
    printf 'BLOCK:%s' "$(printf '%s' "$err" | head -1)"
  fi
  rm -f "$1" 2>/dev/null
}
# 只试写、绝不擦（/dev/null 这类设备节点专用）
wonly() {
  if err=$( { echo x > "$1"; } 2>&1 ); then
    printf 'OPEN'
  else
    printf 'BLOCK:%s' "$(printf '%s' "$err" | head -1)"
  fi
}

case "${1:-}" in
  ro)   # 只读围堵：这些必须全是 BLOCK
    echo "ETC=$(wt /etc/dsh-sbx-probe-b)"
    echo "USR=$(wt /usr/dsh-sbx-probe-b)"
    echo "ROOT=$(wt /root/dsh-sbx-probe-b)"
    echo "ROOTDIR=$(wt /dsh-sbx-probe-b)"      # / 根上直接建文件（第三步冻 / 那一发）
    ;;
  ctl)  # 对照组：不围的时候同样的靶子必须全是 OPEN（不然"挡住了"不作数）
    echo "ETC=$(wt /etc/dsh-sbx-probe-a)"
    echo "USR=$(wt /usr/dsh-sbx-probe-a)"
    echo "ROOT=$(wt /root/dsh-sbx-probe-a)"
    echo "ROOTDIR=$(wt /dsh-sbx-probe-a)"
    ;;
  ws)   # 工作区必须还能写——挡过头等于档位废掉
    if mkdir -p /phone/dsh-sbx-probe-dir 2>/dev/null \
       && echo hi > /phone/dsh-sbx-probe-dir/w4 2>/dev/null; then
      echo "WS=$(cat /phone/dsh-sbx-probe-dir/w4 2>/dev/null)"
    else
      echo "WS=NO"
    fi
    ;;
  dev)  # 老毛病：v3 那次把 / 整体影子掉，/dev/null 开不开
    echo "DEVNULL=$(wonly /dev/null)"
    if wc -c < /proc/self/stat > /dev/null 2>&1; then echo PROC=OPEN; else echo PROC=DEAD; fi
    ;;
  tmp)
    echo "TMP=$(wt /tmp/dsh-sbx-probe-c)"
    # /proc/mounts 的字段是「设备 挂载点 类型 …」，新 tmpfs 的这里必须是 tmpfs
    awk '$2 == "/tmp" { print "TMPFS=" $1; f = 1 } END { if (!f) print "TMPFS=NONE" }' /proc/mounts
    ;;
  read) # 只读≠读不到
    echo "LS=$(ls /usr/bin 2>/dev/null | wc -l)"
    ;;
  pid)
    echo "SELF=$(readlink /proc/self 2>/dev/null)"
    ;;
  *)
    echo "BADMODE"
    exit 9
    ;;
esac
