#!/bin/bash
set -u
python3 - <<'PY'
text=open('/proc/bus/input/devices').read()
print('len', len(text), 'blocks', len(text.strip().split('\n\n')))
for b in text.strip().split('\n\n'):
    if 'touchpanel' in b and 'Phys=synaptics' in b:
        for l in b.splitlines():
            print(repr(l))
PY
echo "== 完 =="
