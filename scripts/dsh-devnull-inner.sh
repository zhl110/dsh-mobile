#!/bin/bash
# dsh-devnull-inner.sh — 就在 ns 里跑（外层只负责 chroot + unshare -m，一点引号都不套）
#
# 要回答一个问题：能不能在被围的 namespace 里把 /dev 换成"只放 API 节点"的新 tmpfs，
# 让被围命令碰不到 /dev/block 下那 253 个裸分区节点。上一轮实测 mknod null 单独失败，
# 而且失败之后 `echo x > /dev/null` 居然还"成功"（那是在 tmpfs 上建了个叫 null 的普通文件，假通过）。
set -u
# 自己把自己塞进一个新的 mount namespace 再往下跑（外层命令就只剩一个文件路径，零引号，
# 上一轮那条 "unshare: exec bash: No such file or directory" 就是三层引号套丢的代价）。
if [ -z "${IN_SBX_NS:-}" ]; then
  IN_SBX_NS=1 exec unshare -m bash "$0" "$@"
fi
mount --make-rprivate / || { echo "make-rprivate 失败，后面读数全不作数"; exit 1; }
echo "--- 覆盖前先留一份原 /dev 的把手 ---"
mkdir -p /tmp/devkeep
mount --bind /dev /tmp/devkeep && echo "  bind 把手 rc=0（$(ls /tmp/devkeep | wc -l) 个条目）" || echo "  把手失败 rc=$?"
echo "  把手里的 null：$(ls -l /tmp/devkeep/null 2>&1)"
echo "--- 换上干净 tmpfs /dev ---"
mount -t tmpfs tmpfs /dev && echo "  tmpfs rc=0" || echo "  tmpfs rc=$?"
echo "  换上之后 /dev 条目数 = $(ls /dev | wc -l)"
echo "--- 逐个 mknod，把真实报错原文留下 ---"
for spec in "null c 1 3" "zero c 1 5" "full c 1 7" "random c 1 8" "urandom c 1 9" "tty c 5 0" "ptmx c 5 2"; do
  set -- $spec
  msg=$(mknod "/dev/$1" "$2" "$3" "$4" 2>&1); rc=$?
  printf '  mknod %-8s rc=%s %s\n' "$1" "$rc" "$msg"
done
echo "--- null 到底在不在、是什么 ---"
ls -l /dev/null 2>&1 | sed 's/^/  /'
test -c /dev/null && echo "  /dev/null 是字符设备" || echo "  /dev/null 不是字符设备（若这句成立，写它=往 tmpfs 里堆数据，等于假通过）"
echo "--- 退路：用之前那份把手把宿主 /dev/null bind 回来 ---"
if [ ! -e /dev/null ]; then
  : > /dev/null 2>/dev/null; echo "  先建占位文件 rc=$?"
fi
msg=$(mount --bind /tmp/devkeep/null /dev/null 2>&1); echo "  bind 回 null rc=$? $msg"
ls -l /dev/null 2>&1 | sed 's/^/  /'
echo x > /dev/null && echo "  写 /dev/null rc=0" || echo "  写 /dev/null rc=$?"
test -c /dev/null && echo "  复验：/dev/null 现在是字符设备" || echo "  复验：仍然不是字符设备 ⇒ 这条路不通"
echo "--- 顺手看 block 节点有没有被遮住 ---"
echo "  /dev/block 在不在：$(test -e /dev/block && echo 在 || echo 没了)"
echo "  /dev 条目清单：$(ls /dev | tr '\n' ' ')"
echo "INNER-DONE"
