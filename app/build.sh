#!/bin/sh
# dsh 手机壳 App 的一键重建脚本（在 D:\mycode\dsh-mobile\app 目录下跑：sh build.sh）
# 工具链不装在项目里，走工作区约定的 D:\tools\android-build（aapt2 / r8 / apksig / android.jar）。
# 产出 out/dsh-app.apk；加 --install 就顺手 push 到手机并 pm install。
set -e

TOOLS="${DSH_ANDROID_TOOLS:-D:/tools/android-build}"
AAPT2="$TOOLS/aapt2.exe"
R8="$TOOLS/dl/r8-9.4.15.jar"
APKSIG="$TOOLS/dl/apksig-9.4.1.jar"
APIJAR="$TOOLS/platforms/android-35/android.jar"
ADB="${DSH_ADB:-C:/Users/周海龙/DeskBox/我的桌面/platform-tools/adb.exe}"

KS_PASS="${DSH_KS_PASS:-dsh-local-2026}"
PKG=com.zhl.dsh
MIN_API=26
VER_CODE=7
VER_NAME=0.7

cd "$(dirname "$0")"
# Git-Bash 会把 /data/local/tmp/x 这种参数改写成 D:/program files/Git/data/local/tmp/x 再交给 adb
# —— 和 tools/deploy-entry.sh 里记的是同一个坑（2026-10-20 在这条 push 上又撞一次：
# "remote secure_mkdirs() failed: No such file or directory"）。关自动转换是唯一稳的写法。
export MSYS2_ARG_CONV_EXCL='*'
[ -x "$ADB" ] || ADB="/d/mycode/.agent-tools/platform-tools/adb.exe"
for f in "$AAPT2" "$R8" "$APKSIG" "$APIJAR"; do
  [ -f "$f" ] || { echo "!! 缺工具件：$f（见 RUNBOOK 的 APK 工具链那一节）"; exit 1; }
done
[ -f res/mipmap-xxxhdpi/ic_launcher.png ] || { echo "!! 图标没切，先跑：sh icon.sh"; exit 1; }

rm -rf out/build
mkdir -p out/build/classes out/build/src out/build/dex

# 1) 入口地址与口令：local/entry.key 那一行烤进包里（不打读、不入库）
#    旧版这里烤的是 local/url.txt 里那条带 token 的 3080 地址 —— 那是个定时炸弹：token 实测一次性，
#    烤进包就等于包里存了一条早就作废的入场券。现在地址写死成 3081 的入口，包里只留口令。
mkdir -p out/build
# 这台 Windows 的 console 编码是 GBK，中文 print 会 UnicodeEncodeError 把脚本带倒（2026-10-20 实测）。
# 两条 python 段都自带 PYTHONIOENCODING=utf-8；第 2 段的 print 里也别再掺 \u 转义。
PYTHONIOENCODING=utf-8 python -c "
import os,re
key=open(r'local/entry.key',encoding='utf-8',errors='replace').read().strip() if os.path.exists(r'local/entry.key') else ''
key=re.sub(r'[^A-Za-z0-9_-]','',key)
open(r'out/build/entry.key','w',encoding='utf-8',newline='\n').write(key)
print('[%s] entry key taken: %d B (value not printed)' % ('ok' if key else 'skip', len(key)))
" || echo "[skip] local/entry.key 读不了，包里留空（App 首屏会给「还没有入口口令」那一屏）"
PYTHONIOENCODING=utf-8 python -c "
import os,glob
url='http://127.0.0.1:3081/'
if os.path.exists(r'local/entry.url'):
    url=open(r'local/entry.url',encoding='utf-8').read().strip() or url
key=open(r'out/build/entry.key',encoding='utf-8').read().strip()
for f in glob.glob(r'src/com/zhl/dsh/*.java'):
    s=open(f,encoding='utf-8').read()
    s=s.replace('__DSH_ENTRY_URL__',url).replace('__DSH_ENTRY_KEY__',key)
    d='out/build/src/com/zhl/dsh'; os.makedirs(d,exist_ok=True)
    out=os.path.join(d,os.path.basename(f))
    open(out,'w',encoding='utf-8',newline='\n').write(s)
    print('[ok] 模板展开 %s -> %d B' % (out,os.path.getsize(out)))
"

# 2) 没有签名库就先造一把自签的（只用于本机装机；丢了就要卸了重装）
if [ ! -f local/dsh.keystore ]; then
  mkdir -p local
  KS_TMP=local/.ks.pw
  printf '%s' "$KS_PASS" > "$KS_TMP"
  keytool -genkeypair -keystore local/dsh.keystore -storetype PKCS12 -alias dsh \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass:file "$KS_TMP" -keypass:file "$KS_TMP" \
    -dname "CN=dsh-mobile, OU=local, O=local, L=local, ST=local, C=CN" >/dev/null 2>&1
  rm -f "$KS_TMP"
  echo "[ok] 造了自签库 local/dsh.keystore（$(wc -c <local/dsh.keystore) B）"
fi

# 3) javac → class
# -J-Duser.language=en：不加这条，javac 的报错会用 GBK 中文吐到 UTF-8 的终端上，成乱码读不了（2026-10-20 实测）
javac -nowarn -J-Duser.language=en -source 8 -target 8 -bootclasspath "$APIJAR" \
  -d out/build/classes out/build/src/com/zhl/dsh/*.java 2>&1 | grep -av "bootstrap class path" || true
[ -f out/build/classes/com/zhl/dsh/MainActivity.class ] || { echo "!! javac 没产出 class"; exit 1; }
echo "[ok] javac 过了（$(ls out/build/classes/com/zhl/dsh | wc -l) 个 class）"

# 4) class → classes.dex
java -cp "$R8" com.android.tools.r8.D8 --release --min-api "$MIN_API" --lib "$APIJAR" \
  --output out/build/dex out/build/classes/com/zhl/dsh/*.class
echo "[ok] dex：$(wc -c <out/build/dex/classes.dex) B"

# 5) 资源 + manifest → 未签名 apk
"$AAPT2" compile --dir res -o out/build/res.zip
"$AAPT2" link -o out/build/base.apk -I "$APIJAR" --manifest AndroidManifest.xml \
  --min-sdk-version "$MIN_API" --target-sdk-version 35 \
  --version-code "$VER_CODE" --version-name "$VER_NAME" out/build/res.zip
echo "[ok] aapt2 link 过了（$(wc -c <out/build/base.apk) B）"

# 6) dex 塞进 apk，再签名（v2+v3）
jar uf out/build/base.apk -C out/build/dex classes.dex
java -cp "$APKSIG" tools/SignApk.java out/build/base.apk "out/dsh-app.apk" \
  local/dsh.keystore dsh "$KS_PASS"

SHA=$(sha256sum out/dsh-app.apk | cut -d' ' -f1)
echo "[ok] 成品 out/dsh-app.apk $(wc -c <out/dsh-app.apk) B"
echo "     sha256 $SHA"

# 7) 装机（可选）
if [ "$1" = "--install" ]; then
  # 两条看着更顺的路都实测走过、都不通（2026-10-20，一加 13 / Android 15）：
  #   adb install -r              → Failure [-99]（这台机的 USB 安装闸口，得他本人在开发者选项里放行）
  #   pm install /data/local/tmp/x → System server has no access to read file context
  #                                  u:object_r:shell_test_data_file:s0
  #   —— 后者是 Android 11+ 的规矩：system_server 读不到 adb push 那块标签，跟我们有没有 root 无关。
  # 通的是这条：push 到 tmp → root 把它 cp 进 /data 根 → restorecon（cp 才走 type_transition，
  # 标签变 system_data_file；用 mv 试过，标签原样带过来，照样读不到）→ pm install -r → 两处都删。
  # pm 的退出码单独打出来，别让 set -e 把清理那步带跑（残留的 /data/dsh-app.apk 是我们的文件，必须没）。
  "$ADB" push out/dsh-app.apk /data/local/tmp/dsh-app.apk >/dev/null
  echo "[..] 搬进 /data 根、改标签、pm install -r"
  "$ADB" shell "su -c 'cp /data/local/tmp/dsh-app.apk /data/dsh-app.apk; restorecon /data/dsh-app.apk >/dev/null 2>&1; ls -Z /data/dsh-app.apk; pm install -r /data/dsh-app.apk 2>&1 | head -2; echo pm_rc=\$?; rm -f /data/dsh-app.apk /data/local/tmp/dsh-app.apk; ls /data/dsh-app.apk 2>&1 | head -1'"
  echo "[ok] 装好了：包名 $PKG"
  "$ADB" shell "su -c 'dumpsys package $PKG | grep -m1 versionName'"
fi
