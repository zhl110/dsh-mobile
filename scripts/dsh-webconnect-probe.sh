#!/system/bin/sh
# dsh-webconnect-probe.sh —— 只读探针：查「网页端工作区读不到手机 / 登录失败 / 配不了 key」三件事的实际成因
# 不写盘、不装东西、不打印任何密钥值（只看变量名与文件是否存在）
LOG=/data/local/dsh.log
ROOTFS=/data/local/dsh-rootfs

echo "===== 1. 服务进程现在活在哪 ====="
PID=$(netstat -tlnp 2>/dev/null | grep ':3080' | awk '{print $NF}' | cut -d/ -f1)
[ -n "$PID" ] || PID=$(grep -l . /proc/*/cmdline 2>/dev/null >/dev/null; for p in $(ls /proc | grep -E '^[0-9]+$'); do grep -qa 'dsh' /proc/$p/cmdline 2>/dev/null && echo $p; done | head -1)
echo "pid=$PID"
echo "cwd(宿主视角)=$(ls -l /proc/$PID/cwd 2>&1 | sed 's/.*-> //')"
echo "root(宿主视角)=$(ls -l /proc/$PID/root 2>&1 | sed 's/.*-> //')"
echo "--- 进程自己的 cwd 在 chroot 内是哪个目录 ---"
nsenter -t $PID -m -- /bin/readlink /proc/self/cwd 2>&1 || echo "nsenter 不可用"

echo
echo "===== 2. 手机存储有没有进了这个 chroot ====="
echo "--- 挂载表里跟存储有关的行（空=根本没挂）---"
grep -E 'sdcard|media|storage|fuse' /proc/mounts | grep dsh-rootfs || echo "(无：没有任何存储挂进 $ROOTFS)"
echo "--- chroot 内看 /sdcard /storage /data/media ---"
nsenter -t $PID -m -- /bin/sh -c 'for d in /sdcard /storage /data/media /mnt; do printf "%-14s " "$d"; ls -d $d 2>&1 | head -1; done' 2>&1 || \
  chroot $ROOTFS /bin/sh -c 'for d in /sdcard /storage /data/media /mnt; do printf "%-14s " "$d"; ls -d $d 2>&1 | head -1; done'
echo "--- chroot 内工作区根目录实际长什么样（这就是网页端看到的 workspace）---"
chroot $ROOTFS /bin/sh -c 'cd / && pwd && ls -a | head -30'
echo "--- 宿主上真正的用户存储在哪 ---"
ls -d /data/media/0 2>&1
ls /data/media/0 2>&1 | head -12

echo
echo "===== 3. 登录：日志里最近的 account / auth 行 ====="
echo "--- 日志总行数 ---"
wc -l < $LOG 2>&1
echo "--- 最后 30 条含 account/auth/sign/token 的行 ---"
grep -aiE 'account|auth|sign|login' $LOG 2>&1 | tail -30
echo "--- 有没有新的 no-response / 4xx / 5xx ---"
grep -aiE 'no-response|errorCode|status.?=[45]|HTTP/[0-9.]+ [45]' $LOG 2>&1 | tail -10

echo
echo "===== 4. key：配置文件里到底有没有凭据槽（只看键名） ====="
echo "--- chroot 内 ~/.dsh 相关 ---"
for f in /root/.dsh-env /root/.dsh/settings.json /root/.dsh/.credentials.yaml /root/.config/dsh; do
  printf "%-34s " "$f"
  if [ -e "$ROOTFS$f" ]; then echo "在 $(wc -c <"$ROOTFS$f" 2>/dev/null) B"; else echo "不在"; fi
done
echo "--- /root/.dsh-env 里的变量名（值一律不打印）---"
sed -E 's/=.*/=<隐藏>/' "$ROOTFS/root/.dsh-env" 2>&1
echo "--- 环境变量里有没有 DEEPSEEK_API_KEY（只报有/无）---"
tr '\0' '\n' < /proc/$PID/environ 2>&1 | grep -oE '^(DEEPSEEK_API_KEY|DSH_[A-Z_]+)=' | sed 's/=$/=<在环境里>/' | head -20
echo "--- 服务进程能否读到 api.deepseek.com（真发一次 HEAD，不出网则失败）---"
chroot $ROOTFS /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  sh -c 'curl -s -o /dev/null -w "api=%{http_code} " --max-time 8 https://api.deepseek.com/v1/models; curl -s -o /dev/null -w "platform=%{http_code}\n" --max-time 8 https://platform.deepseek.com/'
