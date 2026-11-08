#!/bin/bash
set -u
grep -B3 -A8 'Name="touchpanel"' /proc/bus/input/devices 2>&1
echo "== 完 =="
