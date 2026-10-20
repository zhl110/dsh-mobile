#!/bin/bash
# dsh-dev-node-probe.sh — 一次性勘察：在 ns 里能不能把 /dev 换成"只给 API 节点"的新 tmpfs
#
# 为什么要探这件事（2026-10-20 读数）：现在的 runner 对 /dev 是"跳过不冻"，也就是把宿主 rbind
# 进来的那份 /dev 原样留给被围命令。后果不是 /dev/null 坏了，而是 **/dev/block/*、/dev/disk/*
# 这些裸设备节点也在** ——被围命令和被围的 dsh 同为 uid 0，那等于"围住了文件系统但能直接写分区"。
# bwrap 的 --dev 不会给这些：它挂一个全新 tmpfs，只放 null/zero/full/tty/ptmx/random/urandom
# 这一组 API 节点。这条判据就是"能不能把 bwrap 那一档仿出来"。
#
# 全程只在自己的 mount namespace 里动 /dev，进程退出 ns 就散，宿主 /dev 一根毛都不掉。
# 用法（root 宿主侧）：sh /data/local/tmp/dsh-dev-node-probe.sh
ROOTFS=/data/local/dsh-rootfs
EP=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
exec chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH="$EP" /bin/bash <<'EOS'
set -u
echo "--- 宿主(=chroot 原样)的 /dev 是什么 ---"
grep ' /dev ' /proc/mounts
echo "  /dev 顶层条目 $(ls /dev | wc -l) 个，其中 /dev/block 下 $(ls /dev/block 2>/dev/null | wc -l) 个"
stat -c '  %n: %F %a %U:%G' /dev/block/dm-74 2>/dev/null || echo "  /dev/block/dm-74 读不到"
echo "--- 进 ns 试换 /dev ---"
unshare -m bash -c '
set -u
mount --make-rprivate / || { echo "RPRIVATE-FAIL"; exit 1; }
mount -t tmpfs tmpfs /dev && echo TMPFS-DEV-OK || echo TMPFS-DEV-FAIL
for spec in "null c 1 3" "zero c 1 5" "full c 1 7" "random c 1 8" "urandom c 1 9" "tty c 5 0" "ptmx c 5 2"; do
  set -- $spec
  if mknod /dev/$1 $2 $3 $4 2>/dev/null; then chmod 666 /dev/$1 2>/dev/null; echo "MKNOD-OK  $1"; else echo "MKNOD-FAIL $1"; fi
done
chmod 755 /dev 2>/dev/null
echo "  围内 /dev 顶层条目 $(ls /dev | wc -l) 个；/dev/block 在不在：$(test -e /dev/block && echo 在 || echo 没了)"
echo x > /dev/null && echo NULL-OK || echo NULL-FAIL
echo x > /dev/full 2>/dev/null; echo "  /dev/full 写 rc=$? （该是 1）"
head -c 4 /dev/zero | wc -c | sed "s/^/ZERO-BYTES /"
mkdir -p /dev/pts && mount -t devpts -o gid=5,mode=620 devpts /dev/pts 2>/dev/null && echo PTS-OK || echo PTS-FAIL
mkdir -p /dev/shm && mount -t tmpfs tmpfs /dev/shm 2>/dev/null && echo SHM-OK || echo SHM-FAIL
ln -sfn /proc/self/fd /dev/fd 2>/dev/null && echo FD-LINK-OK || echo FD-LINK-FAIL
ls -l /dev/random | wc -l | sed "s/^/RANDOM-STAT-LINES /"
'
echo "  退出 ns 后宿主 /dev 顶层条目 $(ls /dev | wc -l) 个（应仍是原来那个数）"
EOS
