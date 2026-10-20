#!/system/bin/sh
# v4：只问一件事 —— 「整盘只读 + 指定目录可写」这个形状在这台上做不做得出来。
# 三种做法各测一次，每种都先跑对照（不加只读时必须写得进）。
ROOTFS=/data/local/dsh-rootfs
S="$ROOTFS/root/.sbxprobe"
rm -rf "$S"; mkdir -p "$S/w"
mount --bind "$ROOTFS" "$ROOTFS" || { echo "[FATAL] rootfs bind 失败"; exit 1; }

cat > "$S/t.sh" <<'EOS'
#!/bin/sh
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
T=/usr/bin/.sbxprobe_write_test
probe () {
  DESC="$1"; shift
  rm -f "$T" 2>/dev/null
  echo "--- $DESC"
  echo "  前置: $(mount 2>/dev/null | grep -c . ) 条挂载可读"
  "$@"
  if touch "$T" 2>/dev/null; then echo "  >>> 写得进（这一档没围住）"; else echo "  >>> 写不进（围住了）"; fi
  rm -f "$T" 2>/dev/null
}
# 对照：什么都不加
rm -f "$T" 2>/dev/null; touch "$T" 2>/dev/null && echo "--- 对照：默认写得进 OK" || echo "!!! 对照就坏了，下面全部作废"
rm -f "$T"

echo "=== A) ns 内 mount --bind / / 然后 remount,bind,ro /"
unshare -m /bin/sh -c '
  echo "  make-rprivate: $(mount --make-rprivate / 2>&1 || echo 失败)"
  echo "  bind /:        $(mount --bind / / 2>&1 || echo 失败)"
  echo "  remount ro:    $(mount -o remount,bind,ro / 2>&1 || echo 失败)"
  touch /usr/bin/.sbxprobe_write_test 2>/dev/null && echo "  >>> A 写得进（没围住）" || echo "  >>> A 写不进（围住了）"
'
rm -f /usr/bin/.sbxprobe_write_test

echo "=== B) ns 内直接 remount,ro /（不走 bind）"
unshare -m /bin/sh -c '
  echo "  make-rprivate: $(mount --make-rprivate / 2>&1 || echo 失败)"
  echo "  remount ro:    $(mount -o remount,ro / 2>&1 || echo 失败)"
  touch /usr/bin/.sbxprobe_write_test 2>/dev/null && echo "  >>> B 写得进（没围住）" || echo "  >>> B 写不进（围住了）"
'
rm -f /usr/bin/.sbxprobe_write_test

echo "=== C) 只把 /usr 与 /etc 各自 bind 只读（别的都不动）"
unshare -m /bin/sh -c '
  mount --make-rprivate / 2>/dev/null
  mount --bind /usr /usr && mount -o remount,bind,ro /usr && echo "  /usr 加固 ok"
  touch /usr/bin/.sbxprobe_write_test 2>/dev/null && echo "  >>> /usr 写得进（没围住）" || echo "  >>> /usr 写不进（围住了）"
  mount --bind /root/.sbxprobe/w /root/.sbxprobe/w && mount -o remount,bind,rw /root/.sbxprobe/w
  touch /root/.sbxprobe/w/OK && echo "  >>> 指定可写目录照样写得进"
'
rm -f /usr/bin/.sbxprobe_write_test
EOS
chmod +x "$S/t.sh"
chroot "$ROOTFS" /bin/sh /root/.sbxprobe/t.sh
echo "--- 收尾核查：这些探针文件都该不存在"
ls -1 "$ROOTFS/usr/bin/.sbxprobe_write_test" 2>&1 | tr -d '\r'
umount "$S/w" 2>/dev/null
umount "$ROOTFS" && echo "[ok] rootfs bind 已撤" || echo "[WARN] 需手工 umount $ROOTFS"
rm -rf "$S"; echo "探针目录: $([ -e "$S" ] && echo 还在 || echo 已删)"
echo "mountinfo 行数: $(wc -l < /proc/self/mountinfo)（起点 446）"
