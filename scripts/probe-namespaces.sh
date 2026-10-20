#!/bin/bash
export PATH=/usr/sbin:/usr/local/sbin:/usr/bin:/bin
echo "== kernel caps"
zcat /proc/config.gz 2>/dev/null | grep -E '^CONFIG_USER_NS|^CONFIG_NAMESPACES|# CONFIG_NAMESPACES' | head -3
echo "== unshare -m (no propagation flag)"
unshare -m /bin/true; echo "  exit=$?"
echo "== unshare -m --propagation private"
unshare -m --propagation private /bin/true; echo "  exit=$?"
echo "== mount ns + read-only bind enforcement"
mkdir -p /tmp/rotest && echo x > /tmp/rotest/f
unshare -m /bin/bash -c '
  mount --bind /tmp/rotest /tmp/rotest 2>&1 | sed "s/^/    bind: /"
  mount -o remount,bind,ro /tmp/rotest 2>&1 | sed "s/^/    ro:   /"
  if touch /tmp/rotest/w 2>/dev/null; then echo "    WRITE_OUTSIDE=NOT_ENFORCED"; else echo "    WRITE_OUTSIDE=BLOCKED(real ro)"; fi
' ; echo "  exit=$?"
echo "== does / support MS_REC private?"
findmnt -no FSTYPE,OPTIONS / 2>/dev/null
findmnt -no FSTYPE,OPTIONS /tmp 2>/dev/null
rm -rf /tmp/rotest
