#!/bin/bash
# probe 133 —— 真触摸设备(/dev/input/event8)能不能写入（能写就说明可以造"硬件触摸"基线）。
set -u
python3 - <<'PY'
import os, struct
p='/dev/input/event8'
try:
    fd=os.open(p, os.O_WRONLY|os.O_NONBLOCK)
    print('OPEN ok fd=%d' % fd)
    try:
        n=os.write(fd, struct.pack('qqHHi',0,0,0,0,0))
        print('WRITE ok n=%d' % n)
    except Exception as e:
        print('WRITE fail %r' % (e,))
    os.close(fd)
except Exception as e:
    print('OPEN fail %r' % (e,))
PY
echo "== 完 =="
