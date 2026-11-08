#!/usr/bin/env python3
"""dsh-uinput —— 从内核输入层注入触摸。

优先写**真触摸设备**（/dev/input/eventN，手指走的就是它）：deviceId 是真实正数、设备表里不会多出一个
touchpanel；这条在这台机上是实测通的（probe 134：写 event8 → 系统收到 deviceId=4）。
找不到/写不进时才退回自建 uinput 虚拟触摸屏（会多出一个同名设备，但功能等价）。

方向是"注入器连壳"：SELinux 只放行 root→app 的 connectto，Shell 起 @dsh-inject 服务端。
协议（换行 JSON，坐标 0..1 归一化，按自然方向）：
  {"op":"tap","nx":0.5,"ny":0.5,"ms":80}
  {"op":"swipe","nx1":..,"ny1":..,"nx2":..,"ny2":..,"ms":300}
  {"op":"ping"}
回复：{"ok":true} / {"ok":false,"error":"..."}
自测：dsh-uinput.py --tap <px> <py> <w> <h>
"""
import os, sys, struct, fcntl, time, random, json, socket

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT = 0
ABS_MT_SLOT, ABS_MT_TOUCH_MAJOR, ABS_MT_POSITION_X, ABS_MT_POSITION_Y = 0x2f, 0x30, 0x35, 0x36
ABS_MT_TRACKING_ID, ABS_MT_PRESSURE = 0x39, 0x3a
BTN_TOUCH = 0x14a
INPUT_PROP_DIRECT = 1

UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT, UI_SET_PROPBIT = 0x40045564, 0x40045565, 0x40045567, 0x4004556e
UI_DEV_SETUP, UI_ABS_SETUP = 0x405c5503, 0x401c5504
RES = 32767


def _ev(fd, t, c, v):
    os.write(fd, struct.pack('qqHHi', 0, 0, t, c, v))


def _abs_range(fd, code):
    req = 0x80000000 | (24 << 16) | (ord('E') << 8) | (0x40 + code)   # EVIOCGABS
    info = struct.unpack('iiiiii', fcntl.ioctl(fd, req, bytes(24)))
    return info[1], info[2]


def find_real_touch():
    """从 /proc/bus/input/devices 里挑真触摸设备：PROP 含 DIRECT 且有 Phys（虚拟设备的 Phys 是空的）。"""
    try:
        text = open('/proc/bus/input/devices').read()
    except Exception:
        return None
    best = None
    for block in text.strip().split('\n\n'):
        lines = block.splitlines()
        prop = phys = handlers = name = None
        for l in lines:
            if l.startswith('B: PROP='):
                prop = l.split('=', 1)[1]
            elif l.startswith('P: Phys='):
                phys = l.split('=', 1)[1].strip()
            elif l.startswith('H: Handlers='):
                handlers = l.split('=', 1)[1].strip()
            elif l.startswith('N: Name='):
                name = l.split('=', 1)[1].strip().strip('"')
        if not prop or not phys or not handlers:
            continue
        try:
            if not (int(prop, 16) & (1 << INPUT_PROP_DIRECT)):
                continue
        except ValueError:
            continue
        evs = [h for h in handlers.split() if h.startswith('event')]
        if not evs:
            continue
        score = 2 if (name and 'touch' in name.lower()) else 1
        if best is None or score > best[0]:
            best = (score, '/dev/input/' + evs[0], name)
    return best[1] if best else None


class Injector:
    """一套 tap/swipe，底下两种源：真触摸设备 或 自建 uinput 虚拟屏。"""

    def __init__(self):
        self.fd = None
        self.real = False
        path = find_real_touch()
        if path:
            try:
                fd = os.open(path, os.O_WRONLY | os.O_NONBLOCK)
                self.xmin, self.xmax = _abs_range(fd, ABS_MT_POSITION_X)
                self.ymin, self.ymax = _abs_range(fd, ABS_MT_POSITION_Y)
                if self.xmax > self.xmin and self.ymax > self.ymin:
                    self.fd = fd
                    self.real = True
                    sys.stderr.write('[uinput] real touch %s x=%d..%d y=%d..%d\n'
                                     % (path, self.xmin, self.xmax, self.ymin, self.ymax))
                    sys.stderr.flush()
                    return
                os.close(fd)
            except Exception as e:
                sys.stderr.write('[uinput] real touch %s 失败 %r，改走 uinput\n' % (path, e))
                sys.stderr.flush()
        self._create_uinput()

    def _create_uinput(self):
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
        fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack('HHHH80sI', 0x0000, 0x0000, 0x0001, 0x0001, b'touchpanel', 0))
        fcntl.ioctl(fd, UI_DEV_CREATE)
        self.fd = fd
        self.real = False
        self.xmin, self.xmax, self.ymin, self.ymax = 0, RES, 0, RES
        time.sleep(0.25)
        sys.stderr.write('[uinput] fallback uinput touchscreen\n')
        sys.stderr.flush()

    def _raw(self, nx, ny):
        x = int(round(self.xmin + nx * (self.xmax - self.xmin)))
        y = int(round(self.ymin + ny * (self.ymax - self.ymin)))
        j = 16 if self.real else 25
        x += random.randint(-j, j)
        y += random.randint(-j, j)
        return max(self.xmin, min(self.xmax, x)), max(self.ymin, min(self.ymax, y))

    def down(self, nx, ny):
        x, y = self._raw(nx, ny)
        _ev(self.fd, EV_ABS, ABS_MT_SLOT, 0)
        _ev(self.fd, EV_ABS, ABS_MT_TRACKING_ID, random.randint(100, 60000))
        _ev(self.fd, EV_ABS, ABS_MT_POSITION_X, x)
        _ev(self.fd, EV_ABS, ABS_MT_POSITION_Y, y)
        if self.real:
            _ev(self.fd, EV_ABS, ABS_MT_TOUCH_MAJOR, 10)
            _ev(self.fd, EV_ABS, ABS_MT_PRESSURE, 50)
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
        time.sleep(random.uniform(0.01, 0.06))
        self.down(nx, ny)
        time.sleep(ms / 1000.0)
        self.up()

    def swipe(self, nx1, ny1, nx2, ny2, ms=300):
        x1, y1 = self.down(nx1, ny1)
        x2, y2 = self._raw(nx2, ny2)
        steps = max(4, int(ms / 9))
        for i in range(1, steps + 1):
            f = i / float(steps)
            e = f * f * (3 - 2 * f)             # ease-in-out，不是匀速直线
            x = int(x1 + (x2 - x1) * e) + random.randint(-18, 18)
            y = int(y1 + (y2 - y1) * e) + random.randint(-18, 18)
            self.move(max(self.xmin, min(self.xmax, x)), max(self.ymin, min(self.ymax, y)))
            time.sleep(ms / 1000.0 / steps)
        time.sleep(0.02)
        self.up()

    def close(self):
        try:
            if self.real:
                os.close(self.fd)
            else:
                fcntl.ioctl(self.fd, UI_DEV_DESTROY)
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
        return {'ok': True, 'pid': os.getpid(), 'real': touch.real}
    return {'ok': False, 'error': 'unknown op'}


def main():
    if len(sys.argv) >= 6 and sys.argv[1] == '--tap':
        px, py, w, h = (float(x) for x in sys.argv[2:6])
        t = Injector()
        t.tap(px / w, py / h, 90)
        time.sleep(0.3)
        t.close()
        return
    if len(sys.argv) >= 2 and sys.argv[1] == '--serve':
        touch = Injector()
        while True:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                s.connect('\0dsh-inject')
            except Exception:
                s.close()
                time.sleep(2)
                continue
            sys.stderr.write('[uinput] connected pid=%d real=%s\n' % (os.getpid(), touch.real))
            sys.stderr.flush()
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
