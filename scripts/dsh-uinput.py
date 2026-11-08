#!/usr/bin/env python3
"""dsh-uinput —— 用 /dev/uinput 造虚拟触摸屏/键盘，从内核输入层注入。
与无障碍手势的区别：事件走 evdev → InputReader，deviceId 是真实正数、flags=0，
App 在 onTouchEvent 里分不出与真手指的差别（无障碍手势会带 deviceId=-1 / flags=0x800）。

两种用法：
  dsh-uinput.py --tap <px> <py> <w> <h>     造设备、点一下、销毁（自测用）
  dsh-uinput.py --serve                     常驻，监听抽象 socket @dsh-uinput

协议（换行 JSON，坐标是 0..1 归一化，换分辨率不用改）：
  {"op":"tap","nx":0.5,"ny":0.5,"ms":80}
  {"op":"swipe","nx1":..,"ny1":..,"nx2":..,"ny2":..,"ms":300}
  {"op":"ping"}
回复：{"ok":true} / {"ok":false,"error":"..."}
"""
import os, sys, struct, fcntl, time, random, json, socket

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT = 0
ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0x2f, 0x35, 0x36, 0x39
BTN_TOUCH = 0x14a
INPUT_PROP_DIRECT = 1

UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT, UI_SET_PROPBIT = 0x40045564, 0x40045565, 0x40045567, 0x4004556e
UI_DEV_SETUP, UI_ABS_SETUP = 0x405c5503, 0x401c5504
RES = 32767


def _ev(fd, t, c, v):
    os.write(fd, struct.pack('qqHHi', 0, 0, t, c, v))


class Touch:
    def __init__(self, name=b'touchpanel'):
        fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
        for ev in (EV_SYN, EV_KEY, EV_ABS):
            fcntl.ioctl(fd, UI_SET_EVBIT, ev)
        fcntl.ioctl(fd, UI_SET_KEYBIT, BTN_TOUCH)
        for ax in (ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID):
            fcntl.ioctl(fd, UI_SET_ABSBIT, ax)
        for ax in (ABS_MT_POSITION_X, ABS_MT_POSITION_Y):
            fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack('Hxxiiiiii', ax, 0, 0, RES, 0, 0, 0))
        fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack('Hxxiiiiii', ABS_MT_SLOT, 0, 0, 9, 0, 0, 0))
        fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack('Hxxiiiiii', ABS_MT_TRACKING_ID, 0, 0, 65535, 0, 0, 0))
        fcntl.ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_DIRECT)
        # 与这台机的真触摸设备同名同 id，尽量不新增"看着可疑"的设备
        fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack('HHHH80sI', 0x0000, 0x0000, 0x0001, 0x0001, name, 0))
        fcntl.ioctl(fd, UI_DEV_CREATE)
        self.fd = fd
        time.sleep(0.25)          # 等 InputReader 把这个设备收进来

    @staticmethod
    def _raw(n):
        return max(0, min(RES, int(round(n * RES))))

    def down(self, nx, ny):
        x = self._raw(nx) + random.randint(-25, 25)
        y = self._raw(ny) + random.randint(-25, 25)
        x, y = max(0, min(RES, x)), max(0, min(RES, y))
        _ev(self.fd, EV_ABS, ABS_MT_SLOT, 0)
        _ev(self.fd, EV_ABS, ABS_MT_TRACKING_ID, random.randint(100, 60000))
        _ev(self.fd, EV_ABS, ABS_MT_POSITION_X, x)
        _ev(self.fd, EV_ABS, ABS_MT_POSITION_Y, y)
        _ev(self.fd, EV_KEY, BTN_TOUCH, 1)
        _ev(self.fd, EV_SYN, SYN_REPORT, 0)
        return x, y

    def move(self, x, y):
        _ev(self.fd, EV_ABS, ABS_MT_POSITION_X, x)
        _ev(self.fd, EV_ABS, ABS_MT_POSITION_Y, y)
        _ev(self.fd, EV_SYN, SYN_REPORT, 0)

    def up(self):
        _ev(self.fd, EV_ABS, ABS_MT_TRACKING_ID, -1)
        _ev(self.fd, EV_KEY, BTN_TOUCH, 0)
        _ev(self.fd, EV_SYN, SYN_REPORT, 0)

    def tap(self, nx, ny, ms=None):
        if ms is None:
            ms = random.randint(55, 120)
        time.sleep(random.uniform(0.01, 0.06))   # 人抬手前不可能 0ms 落下
        self.down(nx, ny)
        time.sleep(ms / 1000.0)
        self.up()

    def swipe(self, nx1, ny1, nx2, ny2, ms=300):
        x1, y1 = self.down(nx1, ny1)
        x2, y2 = self._raw(nx2), self._raw(ny2)
        steps = max(4, int(ms / 9))
        for i in range(1, steps + 1):
            f = i / float(steps)
            e = f * f * (3 - 2 * f)             # ease-in-out，不是匀速直线
            x = int(x1 + (x2 - x1) * e) + random.randint(-18, 18)
            y = int(y1 + (y2 - y1) * e) + random.randint(-18, 18)
            self.move(max(0, min(RES, x)), max(0, min(RES, y)))
            time.sleep(ms / 1000.0 / steps)
        time.sleep(0.02)
        self.up()

    def close(self):
        try:
            fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        except Exception:
            pass
        try:
            os.close(self.fd)
        except Exception:
            pass


def _handle(req, touch):
    op = req.get('op')
    if op == 'tap':
        touch.tap(float(req['nx']), float(req['ny']), req.get('ms'))
        return {'ok': True}
    if op == 'swipe':
        touch.swipe(float(req['nx1']), float(req['ny1']),
                    float(req['nx2']), float(req['ny2']), int(req.get('ms', 300)))
        return {'ok': True}
    if op == 'ping':
        return {'ok': True, 'pid': os.getpid()}
    return {'ok': False, 'error': 'unknown op'}


def main():
    if len(sys.argv) >= 6 and sys.argv[1] == '--tap':
        px, py, w, h = (float(x) for x in sys.argv[2:6])
        t = Touch()
        t.tap(px / w, py / h, 90)
        time.sleep(0.3)
        t.close()
        return
    if len(sys.argv) >= 2 and sys.argv[1] == '--serve':
        touch = Touch()
        # 方向是"root 连 App 的 socket"：SELinux 只允许 root→app 的 connectto，
        # 反过来 app(untrusted_app)→su 的 socket 是 denied（11-08 实测 dmesg avc）。
        while True:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                s.connect('\0dsh-inject')
            except Exception:
                s.close()
                time.sleep(2)
                continue
            sys.stderr.write('[uinput] connected pid=%d\n' % os.getpid()); sys.stderr.flush()
            try:
                f = s.makefile('rwb')
                while True:
                    line = f.readline()
                    if not line:
                        break
                    try:
                        resp = _handle(json.loads(line.decode('utf-8')), touch)
                    except Exception as e:
                        resp = {'ok': False, 'error': str(e)}
                    f.write((json.dumps(resp) + '\n').encode('utf-8'))
                    f.flush()
            except Exception:
                pass
            finally:
                try: s.close()
                except Exception: pass
                time.sleep(1)
        return
    sys.stderr.write('usage: --tap <px> <py> <w> <h> | --serve\n')
    sys.exit(2)


if __name__ == '__main__':
    main()
