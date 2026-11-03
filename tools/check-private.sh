#!/usr/bin/env bash
# check-private.sh —— 提交前的「本机可识别项 / 凭证形状」闸门。
#
# 为什么要有这一发：这仓 2026-11-03 转成 PUBLIC 了。写进跟踪文件的用户名、家目录路径、
# 设备序列号、邮箱、口令默认值**对任何人可见，而且改历史不算收回去**（要收回只能删库重建）。
# 这类东西不全算凭证，但一样坏事，所以单独立一道，别指望人记住。
#
# 用法：
#   bash tools/check-private.sh            扫跟踪区（现役）—— 提交前跑这个
#   bash tools/check-private.sh --staged   扫暂存区（要挂 pre-commit 就用这个）
#   bash tools/check-private.sh --selftest 埋一颗雷（临时件进暂存区）⇒ 要抓到，撤掉 ⇒ 要回 0
#                                          闸门这类"只跑一次看不出对不对"的逻辑就得能自证。
#
# 只报**形状名 / 文件名 / 处数**，一律不打印匹配到的内容（命中可能就是真值）。
# 真值名单在 tools/private-values.txt（一行一个，这文件本身在 .gitignore 里 ⇒ 名单不会把值带进仓）。
# 名单不在位或是空的 ⇒ 记一次命中（不静默通过）—— 与 scripts/dsh-payload-pack.sh 那道闸门同一个规矩。
# shortcut: 形状表是手写的一小撮，新形状（换了口令前缀之类）就在这里加一行；--selftest 不覆盖"名单不在位"那一格。
set -u
cd "$(dirname "$0")/.."

LIST=tools/private-values.txt
# 排除自己：闸门里就写着那些形状的字面量，不排就会把自己数成命中（本机第一跑就是这么报的）。
SCOPE="-- . :(exclude)tools/check-private.sh"
[ "${1:-}" = "--staged" ] && SCOPE="--cached -- . :(exclude)tools/check-private.sh"

if [ "${1:-}" = "--selftest" ]; then
  T=tmp-check-private-selftest.txt
  { [ -f "$LIST" ] && grep -vE '^[[:space:]]*(#|$)' "$LIST" | head -1; printf 'C:\\Users\\ExampleUser\\x\nsk-ABCDEFGHIJKLMNOPQRSTUVWXaa\nadb -s 0123abcd shell getprop\n'; } > "$T"
  git add -- "$T" >/dev/null 2>&1
  L1=$(bash "$0" --staged 2>&1); R1=$?          # 计数别塞进 $( ) 里再串管道，这里只取退出码与整份输出
  git rm --cached -- "$T" >/dev/null 2>&1; rm -f "$T"
  L2=$(bash "$0" --staged 2>&1); R2=$?
  num() { printf '%s\n' "$L1" | grep -F "$1" | head -1 | sed -n 's/.*命中 *\([0-9]\{1,\}\).*/\1/p'; }
  P=0; F=0
  chk() { if [ "$2" = "$3" ]; then P=$((P+1)); printf 'PASS %s\n' "$1"; else F=$((F+1)); printf 'FAIL %s（%s）\n' "$1" "$4"; fi; }
  chk "A 埋雷被拦住（rc=1）"        "$R1" "1"                 "实际 rc=$R1"
  chk "B 凭证-sk 形状抓到"           "$(num 凭证-sk)"          "1"  "计数不对"
  chk "C Windows 家目录抓到"         "$(num 'Windows 家目录')" "1"  "计数不对"
  chk "D 设备序列号那一位抓到"       "$(num 设备序列号那一位)"  "1"  "计数不对"
  chk "E 本机名单抓到值"             "$(printf '%s\n' "$L1" | grep -A1 '本机名单' | grep -c '命中')" "1" "名单那格没报命中"
  chk "F 撤雷之后回 0"               "$R2" "0"                 "实际 rc=$R2"
  chk "G 临时件已清干净"             "$(ls "$T" 2>/dev/null | wc -l)" "0" "$T 还在"
  printf '合计 %s 条：PASS %s / FAIL %s\n' "$((P+F))" "$P" "$F"
  [ "$F" = "0" ] || exit 1
  echo "[ok] 闸门自测通过（它既能抓到雷，也不会抓到就报）"
  exit 0
fi

# 假串不算命中：自测埋的雷、归档里那个哑 key、以及本仓的遮位写法。
FAKE='SELFTEST|dummy-invalid|〈[^〉]*·已遮〉|<你的|<本机'

# 形状名:ERE（值按第一个冒号拆，所以正则里别出现名字用的冒号）
SHAPES="凭证-sk 形状:sk-[A-Za-z0-9]{20,}
凭证-ghp 形状:ghp_[A-Za-z0-9]{36}
凭证-PAT 形状:github_pat_[A-Za-z0-9_]{20,}
私钥块:BEGIN [A-Z ]*PRIVATE KEY
Windows 家目录:C:\\\\Users\\\\[^\\\\]+
macOS 家目录:/Users/[^/ ]+/
设备序列号那一位:adb -s [0-9a-f]{8}
写死的默认口令:KS_PASS. :-[a-zA-Z0-9_-]{4,}"

TOTAL=0
printf '== 通用形状（范围：%s） ==\n' "$([ "${1:-}" = "--staged" ] && echo 暂存区 || echo 跟踪区)"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  name="${line%%:*}"; pat="${line#*:}"
  # 内容只走管道用来数与取文件名，一律不上屏（命中的可能就是真值）。
  out=$(git grep -I -n -E -e "$pat" $SCOPE 2>/dev/null | grep -vE "$FAKE")
  if [ -z "$out" ]; then printf '  %-22s 0\n' "$name"; continue; fi
  n=$(printf '%s\n' "$out" | wc -l); files=$(printf '%s\n' "$out" | cut -d: -f1 | sort -u | tr '\n' ' ')
  printf '  %-22s 命中 %-3s 处  文件：%s\n' "$name" "$n" "$files"
  TOTAL=$((TOTAL+n))
done <<< "$SHAPES"

printf '== 本机名单（tools/private-values.txt，值与内容都不打印） ==\n'
if [ ! -f "$LIST" ] || [ "$(grep -cvE '^[[:space:]]*(#|$)' -- "$LIST" 2>/dev/null)" = "0" ]; then
  echo "  !! 名单不在位或是空的 ⇒ 这一格没判（不算通过）：把本机可识别项一行一个写进 $LIST"
  TOTAL=$((TOTAL+1))
else
  n=$(git grep -I -c -F -f "$LIST" $SCOPE 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}')
  if [ "$n" -gt 0 ]; then
    where=$(git grep -I -c -F -f "$LIST" $SCOPE 2>/dev/null | tr '\n' ' ')
    printf '  命中 %-3s 处  按文件：%s\n' "$n" "$where"
    TOTAL=$((TOTAL+n))
  else
    echo "  0（名单 $(grep -cvE '^[[:space:]]*(#|$)' -- "$LIST") 条，一条没在跟踪区出现）"
  fi
fi

printf '合计命中 = %s\n' "$TOTAL"
[ "$TOTAL" = "0" ] || { echo "!! 有本机可识别项或凭证形状要进仓 ⇒ 停下来遮掉再提交"; exit 1; }
echo "[ok] 干净"
