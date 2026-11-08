#!/bin/bash
# probe 101 —— 只读：量"把动作从无障碍手势换成 root 注入"这条路通不通。
# ① /dev/uinput 在不在、能不能开；② python3/node 有没有；③ 读屏的另一条路（screencap）；④ /dev/input 设备数。
set -u
echo "== ① /dev/uinput =="
ls -l /dev/uinput 2>&1
ls -lZ /dev/uinput 2>&1
echo "== ② 打开试一下（只 open/close，不建设备） =="
command -v python3 >/dev/null 2>&1 && python3 -V 2>&1 || echo "no python3"
python3 - <<'PY' 2>&1
import os
try:
    fd = os.open('/dev/uinput', os.O_RDWR | os.O_NONBLOCK)
    print('OPEN ok fd=%d' % fd)
    os.close(fd)
except Exception as e:
    print('OPEN fail %r' % e)
PY
echo "== ③ 有没有 fcntl（建 uinput 设备要 ioctl） =="
python3 - <<'PY' 2>&1
try:
    import fcntl
    print('fcntl ok', fcntl.ioctl)
except Exception as e:
    print('fcntl fail %r' % e)
PY
echo "== ④ 读屏的另一条路 =="
ls -l /proc/1/root/system/bin/screencap 2>&1
ls -l /proc/1/root/system/bin/uiautomator 2>&1
echo "== ⑤ /dev/input 里现在几个设备（名字只看有无，不读内容） =="
ls -1 /dev/input 2>&1 | head -20
ls -1 /dev/input 2>/dev/null | wc -l
echo "== ⑥ 本机 python 包（要不要现装） =="
python3 -c "import sys; print(sys.version)" 2>&1
echo "== 完 =="
