#!/bin/bash
# tools/kbd-check.sh —— 量「软键盘弹出时页面窗口到底有没有被压小」（只读 + 聚焦/失焦）
# 用法：bash tools/kbd-check.sh
# 判据：before / after 两份读数里 innerHeight 与 visualViewport.height 的差，
#       配 android 侧 mInputShown 与窗口 mFrame 的高度一起看。
set -u
cd "$(dirname "$0")/.." || exit 1
ADB=${DSH_ADB:-/d/mycode/.agent-tools/platform-tools/adb.exe}
export MSYS2_ARG_CONV_EXCL='*'
OUT=downloads/kbd-$(date +%H%M%S); mkdir -p "$OUT"
JS=$(cat scripts/cdp-kbd-probe.js)

w() { "$ADB" shell "su -c '$1'" </dev/null 2>&1 | tr -d '\r'; }

echo "== 0 屏幕方向与基线"; w 'dumpsys input_method | grep -E "mInputShown|mImeVisible|mCurSession"' | tee "$OUT/ime-0.txt"

echo "== 1 键盘起来前"
node scripts/dsh-cdp.js --eval "$JS" > "$OUT/before.txt" 2>&1; tail -1 "$OUT/before.txt" | cut -c1-400

echo "== 2 对输入框中心发一次真触摸（会真的弹键盘，量完立刻收回）"
# 这里不用 focus()：focus 不算用户操作，软键盘不出来，量到的"窗口没变"是假读数（见 dsh-cdp.js 注释）
node scripts/dsh-cdp.js --tapsel "${SEL:-.uV2eYG_input}" 2>&1 | tail -1
sleep 1.8

echo "== 3 键盘起来后：安卓侧"
w 'dumpsys input_method | grep -E "mInputShown|mImeVisible"' | tee "$OUT/ime-1.txt"
w 'dumpsys window windows | grep -A55 "com.zhl.dsh/com.zhl.dsh.MainActivity" | grep -E "mFrame|mAppFrame|mVisibleFrame|mContentFrame|softInput|Smallest|isInFullScreen|mLastVisibleAlpha"' | tee "$OUT/win-1.txt"
w 'dumpsys window | grep -E "mCurrentFocus|mFocusedApp"' | tee "$OUT/focus-1.txt"

echo "== 4 键盘起来后：页面侧"
node scripts/dsh-cdp.js --eval "window.__DSH_KBD_PHASE__='after'; $JS" > "$OUT/after.txt" 2>&1; tail -1 "$OUT/after.txt" | cut -c1-400

echo "== 5 收回键盘"
node scripts/dsh-cdp.js --eval "window.__DSH_KBD_PHASE__='before'; if(document.activeElement&&document.activeElement.blur){document.activeElement.blur();} 'blurred'" 2>&1 | tail -1
w 'dumpsys input_method | grep -E "mInputShown"' | tee "$OUT/ime-2.txt"
if grep -q 'mInputShown=true' "$OUT/ime-2.txt"; then
  echo "   blur 没收回，补一发 KEYCODE_ESCAPE（不用 BACK：那会撞到壳里「返回先收侧栏」那条逻辑）"
  w 'input keyevent 111'
  sleep 1.0
  w 'dumpsys input_method | grep -E "mInputShown"' > "$OUT/ime-3.txt"
  grep -q 'mInputShown=true' "$OUT/ime-3.txt" && echo "   !! ESCAPE 也没收回，键盘可能还开着" || echo "   已收回"
fi
sleep 1.2
echo "== 6 收回后页面侧（应与第 1 步一致）"
node scripts/dsh-cdp.js --eval "$JS" > "$OUT/restored.txt" 2>&1; tail -1 "$OUT/restored.txt" | cut -c1-260
echo "== 读数目录：$OUT"
