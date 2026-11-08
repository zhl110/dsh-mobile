#!/bin/bash
# probe 136 —— 看 chroot 里的 /proc/bus/input/devices（注入器挑真设备用的就是它）。
set -u
ls -l /proc/bus/input/devices 2>&1
echo "---"
cat /proc/bus/input/devices 2>&1 | head -40
echo "== 完 =="
