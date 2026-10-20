#!/system/bin/sh
# 在手机侧直接下 Termux 的 APK 并核对指纹（Android 有 /system/bin/curl，且手机走 netd 的 DNS 是通的；
# PC 侧走 gh-proxy 这一路本轮实测只有 ~3.5 KB/s，35 MB 要下两个多小时，所以改在手机上取）。
# 跑法：adb shell "su -c 'sh /data/local/sh/get-termux.sh'"
BASE=https://github.com/termux/termux-app/releases/download/v0.118.3
OUT=/data/local/tmp/termux.apk
SUM=/data/local/tmp/termux.sha256sums

echo "=== 先拿官方 sha256 清单 ==="
curl -fL --retry 3 --max-time 60 -o "$SUM" "$BASE/termux-app_v0.118.3%2Bgithub-debug_sha256sums" || { echo "清单下不下来"; exit 1; }
grep arm64 "$SUM"

echo "=== 再下 arm64-v8a 的 APK ==="
curl -fL --retry 3 -o "$OUT" "$BASE/termux-app_v0.118.3%2Bgithub-debug_arm64-v8a.apk"
echo "curl 退出码=$?"
ls -l "$OUT"
echo "盘上字节=$(wc -c < "$OUT")  期望=35106607"
toybox sha256sum "$OUT"
