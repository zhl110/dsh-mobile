#!/bin/bash
# dsh-setup-in-chroot.sh — v3：在手机那台 Ubuntu 24.04 chroot 里装出本轮实测环境的完整步骤
#
# v3 和 v2 的区别不是"润色"，是 v2 里四条猜测被真机推翻了，逐条记在这儿：
#   1) v2 改 /etc/apt/sources.list —— Ubuntu 24.04 早就不用它了，源在
#      /etc/apt/sources.list.d/ubuntu.sources（deb822 格式，URIs:/Suites:/Signed-By:）。
#   2) v2 一上来就用 https 装包 —— base 镜像里没有任何 CA，`apt-get update` 报的是证书校验失败，
#      而我当时只 tail -5，把它看成了"源被配置了两次"那句无关警告。真做法：先临时切 http 装
#      ca-certificates，装完再切回 https（apt 的包本身有 Release.gpg 签名，http 引导不等于无校验）。
#   3) v2 用 tar -xJf 解 Node —— base 里没有 xz，报的是 `xz: Cannot exec`，得先 apt 装 xz-utils。
#      另外我在 Windows 上手工重打过一份 node-usr.tar 想绕开 xz，结果 tar 把可执行位丢了，
#      chroot 里直接 `/usr/local/bin/node: Permission denied`；换成设备本机解原 .tar.xz 才通。
#      教训：这类二进制包必须在目标机上解，别在别的系统上中转解包再打回去。
#   4) v2 里 `apt-get install build-essential cmake` 是白装的 —— 实测本机 koffi 拿到的是预编译，
#      现在盘上 cmake/gcc/g++/make/git/python3 全是"未装"，dsh 照装照跑。工具链一个都不需要。
#
# 跑法（Android root shell 里进 chroot，或用总控脚本）：
#   sh /data/local/sh/dsh-chroot.sh --run 'bash /root/dsh-setup-in-chroot.sh'
# 前置条件（不在本脚本职责内，缺了它第一步就会红）：
#   /etc/hosts 里钉好 mirrors.tuna / registry.npmmirror / cdn.npmmirror —— 见 tools/pin-hosts.py，
#   本机 53 端口 UDP+TCP 出站都被拦，resolv.conf 单独摆不平。
set -uo pipefail

[ "$(id -u)" = "0" ] || { echo "!! 得在 chroot 里以 root 跑"; exit 1; }
export TMPDIR=/tmp            # 不显式给的话，adb 带进来的 /data/local/tmp 会让 postinst 挂在 mktemp 上
MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/
NODE_VER=v22.20.0
NODE_TARBALL=node-${NODE_VER}-linux-arm64.tar.xz
# 本地 downloads/ 那份的 sha256 与镜像的 SHASUMS256.txt 逐字符相同（2026-10-19 双向核过）
NODE_SHA=06907b9c088ce62305bc1530e5c1ae1510245114645768f7750c349c5b6fe667
DSH_PKG=@deepseek-ai/dsh@0.2.1-rc.2

step() { echo; echo "===== $* ====="; }

step "0. 身份与门检"
uname -m            # 期望 aarch64
. /etc/os-release   # 期望 Ubuntu 24.04
echo "  实到 $PRETTY_NAME / $(uname -m)"
[ "$(uname -m)" = "aarch64" ] || { echo "!! 不是 arm64，后面的源路径和二进制包都不对"; exit 1; }
grep -q mirrors.tuna /etc/hosts || { echo "!! /etc/hosts 里没有 mirrors.tuna 的钉，先跑 tools/pin-hosts.py"; exit 1; }

step "1. deb822 源（只留 ubuntu.sources，删掉老的 sources.list）"
rm -f /etc/apt/sources.list
cat > /etc/apt/sources.list.d/ubuntu.sources <<EOF
Types: deb
URIs: ${MIRROR}
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: ${MIRROR}
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

step "2. 没有 CA 时先走 http 引导（GPG 签名照验，只是不校验 TLS）"
sed -i "s|URIs: https://|URIs: http://|" /etc/apt/sources.list.d/ubuntu.sources
apt-get update -qq && apt-get install -y --no-install-recommends ca-certificates
sed -i "s|URIs: http://|URIs: https://|" /etc/apt/sources.list.d/ubuntu.sources
apt-get update -qq
echo "  CA bundle 字节=$(wc -c < /etc/ssl/certs/ca-certificates.crt)  /etc/ssl/certs 文件数=$(ls /etc/ssl/certs | wc -l)"

step "3. 只装这轮真用得到的四个包（工具链不装）"
apt-get install -y --no-install-recommends curl xz-utils iproute2
for p in ca-certificates curl xz-utils iproute2; do
  printf "  %-16s %s\n" "$p" "$(dpkg-query -W -f='${Version}' $p 2>/dev/null || echo 未装)"
done

step "4. 解 Node（必须在设备上本机解，别用别处打回去的 tar）"
[ -f /root/$NODE_TARBALL ] || { echo "!! /root/$NODE_TARBALL 不在，先把 downloads/ 那份推进来"; exit 1; }
echo "$NODE_SHA  /root/$NODE_TARBALL" | sha256sum -c - || { echo "!! 包不完整，别解"; exit 1; }
tar -xJf /root/$NODE_TARBALL -C /usr/local --strip-components=1
echo "  node -v = $(node -v)   npm -v = $(npm -v)"

step "5. 装 dsh（registry 走 npmmirror，--foreground-scripts 让 koffi 的 install 脚本看得见）"
printf 'registry=https://registry.npmmirror.com\n' > /root/.npmrc
npm i -g --foreground-scripts "$DSH_PKG"
echo "  dsh --version = $(dsh --version)"

step "6. 自检：平台敏感件 + 反向确认工具链确实没装"
RG=$(find /usr/local/lib/node_modules/@deepseek-ai/dsh -type f -name rg | head -1)
echo "  ripgrep: $("$RG" --version 2>/dev/null | head -1)"
node -e 'require("/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/koffi"); console.log("  koffi require OK")'
for t in cmake gcc g++ make git python3; do printf "  %-8s %s\n" "$t" "$(command -v $t || echo 未装（符合预期）)"; done

step "7. 密钥不在这里填"
echo "  dsh 自己在没 key 时打的话是（实测）："
echo "    MISSING_CREDENTIAL: llm-deepseek: no API key for provider route \"deepseek-official\";"
echo "    store DEEPSEEK_API_KEY through the credentials service (the web Models page writes it),"
echo "    or export DEEPSEEK_API_KEY in the launching environment"
echo "  所以两条路：Web 的 Models 页填，或在 Android 侧跑 sh /data/local/sh/dsh-set-key.sh。"
echo "  本脚本故意不生成 /root/.dsh-env —— 留个空占位反而更容易分不清是没填还是填错。"
echo
echo "全部步骤跑完。起服务回 Android 侧：sh /data/local/sh/dsh-chroot.sh --web"
