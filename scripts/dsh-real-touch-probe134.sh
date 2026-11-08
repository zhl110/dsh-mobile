#!/bin/bash
# probe 134 —— 往真触摸设备 /dev/input/event8 写一发完整触摸（不 grab），看系统收不收、flags 是什么。
set -u
python3 - <<'PY'
import os, struct, time
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN=0
SLOT, TOUCH_MAJOR, PX, PY, TID, PRESSURE = 0x2f, 0x30, 0x35, 0x36, 0x39, 0x3a
BTN_TOUCH=0x14a
def ev(fd,t,c,v): os.write(fd, struct.pack('qqHHi',0,0,t,c,v))
try:
    fd=os.open('/dev/input/event8', os.O_WRONLY|os.O_NONBLOCK)
    ev(fd,EV_ABS,SLOT,0); ev(fd,EV_ABS,TID,555)
    ev(fd,EV_ABS,PX,16000); ev(fd,EV_ABS,PY,20000)
    ev(fd,EV_ABS,TOUCH_MAJOR,10); ev(fd,EV_ABS,PRESSURE,50)
    ev(fd,EV_KEY,BTN_TOUCH,1); ev(fd,EV_SYN,SYN,0)
    time.sleep(0.09)
    ev(fd,EV_ABS,TID,-1); ev(fd,EV_KEY,BTN_TOUCH,0); ev(fd,EV_SYN,SYN,0)
    print('sent via real device (no grab)')
    time.sleep(1.5)
    os.close(fd)
except Exception as e:
    print('fail %r' % (e,))
PY
echo "== 完 =="
