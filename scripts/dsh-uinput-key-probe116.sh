#!/bin/bash
# probe 116 —— 造一个虚拟键盘按 HOME（KEYCODE 3），看能不能回桌面。
set -u
python3 - <<'PY'
import os, struct, fcntl, time
EV_SYN, EV_KEY = 0, 1
SYN = 0
UI_DEV_CREATE = 0x5501; UI_DEV_DESTROY = 0x5502
UI_SET_EVBIT = 0x40045564; UI_SET_KEYBIT = 0x40045565
UI_DEV_SETUP = 0x405c5503
def ev(fd,t,c,v): os.write(fd, struct.pack('qqHHi',0,0,t,c,v))
try:
    fd = os.open('/dev/uinput', os.O_WRONLY|os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_SYN)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    for c in (3,4,187,26,25,115,116): fcntl.ioctl(fd, UI_SET_KEYBIT, c)
    fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack('HHHH80sI',0,0,0,1,b'uinput_nav',0))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(0.4)
    ev(fd,EV_KEY,3,1); ev(fd,EV_SYN,SYN,0); time.sleep(0.08)
    ev(fd,EV_KEY,3,0); ev(fd,EV_SYN,SYN,0)
    print('sent HOME')
    time.sleep(2)
    fcntl.ioctl(fd, UI_DEV_DESTROY); os.close(fd)
    print('closed')
except Exception as e:
    print('fail %r' % (e,))
PY
echo "== 完 =="
