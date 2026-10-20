#!/system/bin/sh
# dsh-boot.sh — 开机自启：只做"等到有网，然后叫总控脚本去起服务"这一件事
#
# 为什么这么薄：起服务的全部规矩（TMPDIR=/tmp、pidfile、端口判活、SELinux 不动、
# 挂载、source /root/.dsh-env）都在 /data/local/sh/dsh-chroot.sh 里。开机脚本自己再抄一份，
# 迟早和总控对不上——2026-10-19 这轮就吃过这个亏：旧版这里写着 setenforce 0 和 pgrep 自查，
# 而实测是 Enforcing 下完全能跑、pgrep 那句永远假阳性。所以只留一个调用。
#
# 装法（root shell）：
#   mkdir -p /data/adb/service.d
#   cp /data/local/sh/dsh-boot.sh /data/adb/service.d/50-dsh.sh
#   chmod 0750 /data/adb/service.d/50-dsh.sh
# 不想自启了：rm /data/adb/service.d/50-dsh.sh（就这一个文件，删掉即完全撤销）
#
# 实测环境：一加 13(PJZ110) / Android 15 / KernelSU；KernelSU 会在开机后期以 root
# 跑 /data/adb/service.d/*.sh。本脚本没在手机真重启过一次——重启验证需要机主点头。
LOG=/data/local/dsh-boot.log
CTRL=/data/local/sh/dsh-chroot.sh

exec >>"$LOG" 2>&1
echo "===== $(date) boot ====="

[ -f "$CTRL" ] || { echo "!! 找不到 $CTRL，不自启"; exit 0; }

# 全部丢后台：service.d 是开机后期串行执行的，这里睡 90 秒就会把后面别的模块脚本堵住。
{
  # 等默认路由出现，最多 90 秒。/proc/net/route 里 00000000 那行就是默认路由，
  # 2026-10-19 在本机读到过，判据可靠。
  i=0
  while [ $i -lt 45 ]; do
    grep -q '00000000' /proc/net/route && break
    i=$((i + 1)); sleep 2
  done
  [ $i -ge 45 ] && echo "警告：没等到默认路由，仍然试着拉起来"

  # 端口已经在了就什么都不做（--entry 自己会 skip）。
  # 2026-10-20 晚上这里从 `--web` 改成 `--entry`：App 现在指的是入口 :3081，
  # 只把裸引擎拉起来的话，开机后点开图标会停在「连不上工作台」那一屏 —— 而这条只有真重启才暴露，
  # 恰好是没人会去点的那一下。入口脚本不在位（没部署过）才退回 --web，至少服务本身活着。
  if [ -f /data/local/dsh-rootfs/usr/local/bin/dsh-entry.js ]; then
    sh "$CTRL" --entry
  else
    echo "入口脚本不在位，退回裸引擎（App 那条 :3081 起不来，需要从 Windows 跑 sh tools/deploy-entry.sh --entry）"
    sh "$CTRL" --web
  fi
  echo "退出码=$?"
} &
echo "已丢到后台拉起，包装 pid=$!"
