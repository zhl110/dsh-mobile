#!/bin/bash
# probe 109 —— 量 uinput 的坐标映射：raw (8192,8192) / (16384,16384) / (24576,24576)，看落到屏幕哪里。
set -u
python3 - <<'PY'
import os, struct, fcntl, time
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN = 0
SLOT, PX, PY, TID = 0x2f, 0x35, 0x36, 0x39
BTN_TOUCH = 0x14a
UI_DEV_CREATE = 0x5501; UI_DEV_DESTROY = 0x5502
UI_SET_EVBIT = 0x40045564; UI_SET_KEYBIT = 0x40045565; UI_SET_ABSBIT = 0x40045567; UI_SET_PROPBIT = 0x4004556e
UI_DEV_SETUP = 0x405c5503; UI_ABS_SETUP = 0x401c5504
RES = 32767
def ev(fd,t,c,v): os.write(fd, struct.pack('qqHHi',0,0,t,c,v))
def tap(fd,x,y):
    ev(fd,EV_ABS,SLOT,0); ev(fd,EV_ABS,TID,777)
    ev(fd,EV_ABS,PX,x); ev(fd,EV_ABS,PY,y)
    ev(fd,EV_KEY,BTN_TOUCH,1); ev(fd,EV_SYN,SYN,0)
    time.sleep(0.08)
    ev(fd,EV_ABS,TID,-1); ev(fd,EV_KEY,BTN_TOUCH,0); ev(fd,EV_SYN,SYN,0)
    time.sleep(1.2)
try:
    fd = os.open('/dev/uinput', os.O_WRONLY|os.O_NONBLOCK)
    for e in (EV_SYN,EV_KEY,EV_ABS): fcntl.ioctl(fd, UI_SET_EVBIT, e)
    fcntl.ioctl(fd, UI_SET_KEYBIT, BTN_TOUCH)
    for ax in (SLOT,PX,PY,TID): fcntl.ioctl(fd, UI_SET_ABSBIT, ax)
    for ax in (PX,PY): fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack('Hxxiiiiii',ax,0,0,RES,0,0,0))
    fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack('Hxxiiiiii',SLOT,0,0,9,0,0,0))
    fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack('Hxxiiiiii',TID,0,0,65535,0,0,0))
    fcntl.ioctl(fd, UI_SET_PROPBIT, 1)
    fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack('HHHH80sI',0,0,1,1,b'touchpanel',0))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(0.4)
    for v in (8192, 16384, 24576):
        tap(fd, v, v); print('sent raw %d,%d' % (v, v))
    print('kept 10s')
    time.sleep(10)
    fcntl.ioctl(fd, UI_DEV_DESTROY); os.close(fd)
    print('closed')
except Exception as e:
    print('fail %r' % (e,))
PY
echo "== 完 =="
