#!/bin/bash
# probe 104 —— 用 /dev/uinput 造虚拟触摸屏点一下（1000,1250），设备保持 10 秒，便于宿主侧 dumpsys input 看这一发。
set -u
python3 - <<'PY'
import os, struct, fcntl, time, random
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN = 0
ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0x2f, 0x35, 0x36, 0x39
BTN_TOUCH = 0x14a
UI_DEV_CREATE = 0x5501; UI_DEV_DESTROY = 0x5502
UI_SET_EVBIT = 0x40045564; UI_SET_KEYBIT = 0x40045565; UI_SET_ABSBIT = 0x40045567; UI_SET_PROPBIT = 0x4004556e
UI_DEV_SETUP = 0x405c5503; UI_ABS_SETUP = 0x401c5504
RES = 32767
def ev(fd,t,c,v): os.write(fd, struct.pack('qqHHi',0,0,t,c,v))
try:
    fd = os.open('/dev/uinput', os.O_WRONLY|os.O_NONBLOCK)
    for e in (EV_SYN,EV_KEY,EV_ABS): fcntl.ioctl(fd, UI_SET_EVBIT, e)
    fcntl.ioctl(fd, UI_SET_KEYBIT, BTN_TOUCH)
    for ax in (ABS_MT_SLOT,ABS_MT_POSITION_X,ABS_MT_POSITION_Y,ABS_MT_TRACKING_ID): fcntl.ioctl(fd, UI_SET_ABSBIT, ax)
    for ax in (ABS_MT_POSITION_X,ABS_MT_POSITION_Y): fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack('Hxxiiiiii',ax,0,0,RES,0,0,0))
    fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack('Hxxiiiiii',ABS_MT_SLOT,0,0,9,0,0,0))
    fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack('Hxxiiiiii',ABS_MT_TRACKING_ID,0,0,65535,0,0,0))
    fcntl.ioctl(fd, UI_SET_PROPBIT, 1)
    fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack('HHHH80sI',0,0,1,1,b'touchpanel',0))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(0.3)
    x = int(round(1000/1440.0*RES)); y = int(round(1250/3168.0*RES))
    ev(fd,EV_ABS,ABS_MT_SLOT,0); ev(fd,EV_ABS,ABS_MT_TRACKING_ID,4321)
    ev(fd,EV_ABS,ABS_MT_POSITION_X,x); ev(fd,EV_ABS,ABS_MT_POSITION_Y,y)
    ev(fd,EV_KEY,BTN_TOUCH,1); ev(fd,EV_SYN,SYN,0)
    time.sleep(0.09)
    ev(fd,EV_ABS,ABS_MT_TRACKING_ID,-1); ev(fd,EV_KEY,BTN_TOUCH,0); ev(fd,EV_SYN,SYN,0)
    print('UINPUT tap sent device kept 10s')
    time.sleep(10)
    fcntl.ioctl(fd, UI_DEV_DESTROY); os.close(fd)
    print('UINPUT closed')
except Exception as e:
    print('UINPUT fail %r' % (e,))
PY
echo "== 完 =="
