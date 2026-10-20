#!/bin/sh
# 图标：把 icon/icon-src.png 切成 res/mipmap-* 五档（只有这一处需要 JDK 自带的 ImageIO）
set -e
cd "$(dirname "$0")"
[ -f icon/icon-src.png ] || { echo "!! 缺 icon/icon-src.png"; exit 1; }
java tools/ResizeIcon.java icon/icon-src.png res
