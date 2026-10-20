#!/usr/bin/env bash
# tools/clone-upstream.sh — 把上游仓库的**真历史**弄到本地
#
# 为什么要有这个脚本（2026-10-20 实测）：这台机到 GitHub 只有 ~88 KB/s（直连 codeload 60 秒下 5,296,133 B），
# github.com 的 git 端口直连不通，能用的镜像是 ghproxy.net（gh-proxy.com 对 git 协议返回
# "expected flush after ref listing"，gitclone.com 的 ls-remote 直接超时，
# 走镜像的 codeload 路径 403）。镜像的 git 通道更慢（实测 ~30 KB/s）且**每次跑到 4~6 分钟必被掐**：
#   error: RPC failed; curl 18 transfer closed with outstanding read data remaining
#   fatal: early EOF / fatal: fetch-pack: invalid index-pack output
# 整仓克隆和一次性浅克隆都因此失败过（DSHA 6 分 21 秒、woaiys3 4 分 4 秒，各三次）。
# ⇒ 唯一能扛的做法：**每次只搬一小截**，浅克隆先落地，再逐段 --deepen，任何一步失败就重试那一步。
#
# 用法：sh tools/clone-upstream.sh <owner/repo> <目录名>
#       MIRROR=https://ghproxy.net TRY=6 sh tools/clone-upstream.sh DSH-APP/DSHA DSHA
# 目标目录落在 reference/gh-3p/（已在 .gitignore 里）。跑完不会动已有的 *-main 快照目录。
set -u

UP="${1:?用法：sh tools/clone-upstream.sh <owner/repo> <目录名>}"
NAME="${2:?要给目标目录名}"
MIRROR="${MIRROR:-https://ghproxy.net}"
TRY="${TRY:-8}"
URL="$MIRROR/https://github.com/$UP.git"

cd "$(dirname "$0")/../reference/gh-3p" || exit 1
# 卡住就断，别在那儿挂 6 分钟等代理掐我
export GIT_HTTP_LOW_SPEED_LIMIT=2000 GIT_HTTP_LOW_SPEED_TIME=90
git config --global --get user.name >/dev/null 2>&1 || true

echo "== $UP → $NAME（镜像 $MIRROR）"
echo "起点：$(date '+%H:%M:%S')"

# ── 第一段：浅克隆，重试到落地 ──────────────────────────────────────────
if ! git -C "$NAME" rev-parse HEAD >/dev/null 2>&1; then
  i=1
  while [ "$i" -le "$TRY" ]; do
    rm -rf "$NAME"
    echo "-- 浅克隆第 $i/$TRY 次"
    if timeout 900 git clone --quiet --depth 1 --single-branch "$URL" "$NAME" 2>&1 | tail -2; :; then :; fi
    if git -C "$NAME" rev-parse HEAD >/dev/null 2>&1; then
      echo "   落地：$(git -C "$NAME" log -1 --format='%h %ad' --date=short)"
      break
    fi
    echo "   这几次都没成（残目录已删）"
    rm -rf "$NAME"
    i=$((i + 1))
  done
fi
git -C "$NAME" rev-parse HEAD >/dev/null 2>&1 || { echo "!! 浅克隆 $TRY 次全失败，先停在这里（快照目录仍在，可读）"; exit 1; }

# ── 第二段：逐段加深，每段独立重试 ──────────────────────────────────────
for target in 100 500 2000 20000; do
  have=$(git -C "$NAME" rev-list --count HEAD 2>/dev/null || echo 0)
  [ "$have" -ge "$target" ] && { echo "-- 已有 $have 条提交，跳过 $target"; continue; }
  i=1
  while [ "$i" -le "$TRY" ]; do
    echo "-- 加深到 $target（当前 $have，第 $i/$TRY 次）"
    timeout 900 git -C "$NAME" fetch --quiet --deepen=$((target > have ? target - have : 1)) origin 2>&1 | tail -1
    git -C "$NAME" merge --ff-only FETCH_HEAD >/dev/null 2>&1 || git -C "$NAME" reset --quiet --hard FETCH_HEAD 2>/dev/null
    now=$(git -C "$NAME" rev-list --count HEAD 2>/dev/null || echo 0)
    if [ "$now" -gt "$have" ]; then have=$now; echo "   进到 $have 条"; break; fi
    i=$((i + 1))
  done
  [ "$i" -gt "$TRY" ] && echo "   !! $target 这一档 $TRY 次没推进，就此为止"
done

# ── 第三段：标签 + 试一次全量历史（能成就成，不成也不回头）──────────────
timeout 300 git -C "$NAME" fetch --quiet --tags origin 2>&1 | tail -1 || true
echo "-- 试 --unshallow（失败不影响已有深度）"
timeout 1800 git -C "$NAME" fetch --quiet --unshallow origin 2>&1 | tail -1 || echo "   没跑完，保留当前深度"

echo "终点：$(date '+%H:%M:%S')"
echo "== 读数"
git -C "$NAME" log -1 --format='HEAD   %H%n提交日 %ad%n标题   %s' --date=iso
echo "提交条数 $(git -C "$NAME" rev-list --count HEAD 2>/dev/null)"
echo "浅仓库？ $(git -C "$NAME" rev-parse --is-shallow-repository)"
echo "标签数   $(git -C "$NAME" tag | wc -l)"
echo "体积     $(du -sh "$NAME" 2>/dev/null | cut -f1)"
