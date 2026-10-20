#!/system/bin/sh
# dsh-dump-config.sh — 只读：把 dsh web profile 组合后的配置树打到 stdout
# 用法（root）：sh /data/local/sh/dsh-dump-config.sh            # 含用户 patch 层
#              DSH_DUMP_DEFAULT=1 sh /data/local/sh/dsh-dump-config.sh   # 只看出厂默认
#
# 两条实测边界（2026-10-20）：
#   1. `--dump-config` 打的是**求值前**的组合树，`!!js …` 就是那行字面文本。别把它读成"服务算出来的值"，
#      要算出来的值走 /data/local/sh/dsh-verify-perm-mode.sh（它带 env 到没到手的判别位）。
#   2. 这里特意 source 一次 /root/.dsh-env，和 dsh-chroot.sh --web 拉起服务时那层环境保持一致；
#      不 source 的话 dump 出来的树可能和服务实际吃的不是同一份。
ROOTFS=/data/local/dsh-rootfs
ENV_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if [ "${DSH_DUMP_DEFAULT:-0}" = "1" ]; then FLAG=--dump-default-config; else FLAG=--dump-config; fi
exec chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH="$ENV_PATH" \
  /bin/bash -lc ". /root/.dsh-env >/dev/null 2>&1; dsh --profile web $FLAG 2>&1"
