#!/bin/bash
# probe 137 —— 直接调 find_real_touch()，看它挑到哪；并试 open + EVIOCGABS。
set -u
python3 - <<'PY'
import importlib.util
spec=importlib.util.spec_from_file_location('u','/usr/local/bin/dsh-uinput.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print('picked=', m.find_real_touch())
try:
    import os, fcntl
    p=m.find_real_touch()
    if p:
        fd=os.open(p, os.O_WRONLY|os.O_NONBLOCK)
        print('open ok', fd)
        try:
            print('X', m._abs_range(fd, m.ABS_MT_POSITION_X))
            print('Y', m._abs_range(fd, m.ABS_MT_POSITION_Y))
        except Exception as e:
            print('abs fail', repr(e))
        os.close(fd)
except Exception as e:
    print('outer fail', repr(e))
PY
echo "== 完 =="
