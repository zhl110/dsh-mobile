#!/bin/bash
# probe 135 —— 让注入器自测模式跑一发，把 stderr 的"选了哪条路"打出来。
set -u
python3 /usr/local/bin/dsh-uinput.py --tap 1000 1250 1440 3168 2>&1
echo "== 完 =="
