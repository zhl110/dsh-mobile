#!/system/bin/sh
# dsh-model-probe.sh — 只读：查清 dsh 的模型/密钥到底配在哪一层，不改任何文件
# 用法（root）：sh /data/local/sh/dsh-model-probe.sh
ROOTFS=/data/local/dsh-rootfs
ENV_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
R() { chroot "$ROOTFS" /usr/bin/env HOME=/root TMPDIR=/tmp PATH="$ENV_PATH" /bin/bash -lc "$1"; }

echo "=== 1. dsh --help（看有没有配模型/登录的子命令）:"
R "dsh --help 2>&1 | head -40"

echo
echo "=== 2. 默认配置总字节数（先试 --profile web 再试裸命令）:"
R "dsh --profile web --dump-default-config 2>&1 | wc -l -c"
R "dsh --dump-default-config 2>&1 | wc -l -c"

echo
echo "=== 3. 默认配置里凡含 key/token/api/model/base/provider 的行:"
R "dsh --profile web --dump-default-config 2>&1 | grep -inE 'key|token|api|model|base|provider|url' | head -70"

echo
echo "=== 4. web profile 目录结构（maxdepth 2）:"
R "find /root/.dsh/profiles/web -maxdepth 2 -not -path '*/node_modules/*' | head -30"

echo
echo "=== 5. profile 里有没有现成 patch/配置文件:"
R "ls -l /root/.dsh/profiles/web/ 2>&1 | head -20; echo '---'; cat /root/.dsh/profiles/web/cordis.patch.yml 2>&1 | head -40"

echo
echo "=== 6. home 级 patch 是否存在:"
R "ls -l /root/.dsh/cordis.patch.yml 2>&1; ls -l /root/.dsh-env 2>&1"
