#!/usr/bin/env bash
# tools/fetch-history.sh — 只要**提交历史**，不要历史里的文件内容
#
# 和 clone-upstream.sh 的分工：那份按"深度"切（浅克隆 → 逐段 --deepen），
# 但深度切不动**体积** —— 本仓 depth-1 的一包就得搬整棵树（woaiys3 的包里有 11,694,592 B 的 esbuild.exe，
# DSHA 树 66 M），在 ~30 KB/s 且 4~6 分钟必掐的镜像通道上，这一包本身就装不进一个窗口 ⇒ 每次都白跑。
# 这份改成按**对象类型**切：--filter=blob:none 只搬 commit + tree，历史里的文件内容（blob）要看了才按需取。
# 于是"git log 全通、git log --name-status 通、git show 的正文按需拉几 KB"。
#
# 用法：sh tools/fetch-history.sh <owner/repo> <目录名>
#       MIRROR=https://ghproxy.net TRY=10 sh tools/fetch-history.sh DSH-APP/DSHA DSHA-hist
# 目标目录在 reference/gh-3p/ 下（已 .gitignore）。**不碰已有的 *-main 快照目录，也不碰 clone-upstream.sh 的目录名。**
# 判"成没成"一律用 git rev-parse HEAD + git log --oneline -1，不用 rev-parse --is-shallow-repository
# —— 后者在半截仓库上返回 "false"，我今天就是这么打出去一次假的"就绪"（RUNBOOK 14.13 坑①）。
set -u

UP="${1:?用法：sh tools/fetch-history.sh <owner/repo> <目录名>}"
NAME="${2:?要给目标目录名}"
MIRROR="${MIRROR:-https://ghproxy.net}"
TRY="${TRY:-12}"
URL="$MIRROR/https://github.com/$UP.git"

cd "$(dirname "$0")/../reference/gh-3p" || exit 1
export GIT_HTTP_LOW_SPEED_LIMIT=2000 GIT_HTTP_LOW_SPEED_TIME=75

echo "== $UP → $NAME（blobless，镜像 $MIRROR）"
echo "起点：$(date '+%H:%M:%S')"

i=1
while [ "$i" -le "$TRY" ]; do
  if git -C "$NAME" rev-parse HEAD >/dev/null 2>&1; then
    echo "已在本地：$(git -C "$NAME" log -1 --format='%h %ad %s' --date=short)（提交 $(git -C "$NAME" rev-list --count HEAD) 条）"
    break
  fi
  rm -rf "$NAME"
  echo "-- 第 $i/$TRY 次（--filter=blob:none --no-checkout --single-branch）"
  timeout 600 git clone --quiet --filter=blob:none --no-checkout --single-branch "$URL" "$NAME" 2>&1 | tail -2
  if git -C "$NAME" rev-parse HEAD >/dev/null 2>&1; then
    echo "   落地：$(git -C "$NAME" log -1 --format='%h %ad' --date=short)，提交 $(git -C "$NAME" rev-list --count HEAD) 条"
    break
  fi
  echo "   没成（残目录已删）"
  rm -rf "$NAME"
  i=$((i + 1))
done

git -C "$NAME" rev-parse HEAD >/dev/null 2>&1 || { echo "!! $TRY 次全失败：历史留到下次，快照树照读不误"; exit 1; }

# 标签同样按 blobless 拿；失败不影响已有历史
timeout 300 git -C "$NAME" fetch --quiet --tags origin 2>&1 | tail -1 || echo "   标签没拿全"

echo "终点：$(date '+%H:%M:%S')"
echo "== 读数"
git -C "$NAME" log -1 --format='HEAD   %H%n提交日 %ad%n标题   %s' --date=iso
echo "提交条数 $(git -C "$NAME" rev-list --count HEAD)"
echo "最早一条 $(git -C "$NAME" log --reverse --format='%h %ad' --date=short | head -1)"
echo "标签数   $(git -C "$NAME" tag | wc -l)"
echo "浅仓库？ $(git -C "$NAME" rev-parse --is-shallow-repository)（blobless 通常 false，看上面条数才算）"
echo "体积     $(du -sh "$NAME" 2>/dev/null | cut -f1)"
echo "工作区   未检出（--no-checkout）；文件一律读同目录的 *-main 快照"
