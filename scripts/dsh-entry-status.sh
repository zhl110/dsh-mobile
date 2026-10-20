#!/usr/bin/env bash
# scripts/dsh-entry-status.sh —— 只读地问一句"入口现在还活着吗"，并把两种问法各问一遍。
#
# 为什么要有这个：2026-10-20 深夜我在 Android 侧裸跑 `curl http://127.0.0.1:3081/__entry_status`
# 拿到的是 `Not Found`，而入口自述页本来是该出文本的。这一发有两种解释，形状一模一样：
#   甲）入口按设计拒答 —— 它对外一律"404 而不是 403"，没带口令 cookie 的请求根本不该知道自己敲对了门；
#   乙）入口真挂了 / 那个路径没了。
# 分开它们的唯一办法是**同一条路上带口令再问一遍**：出文本 = 甲（我的读法），还是 Not Found = 乙。
# 所以这个脚本一次跑两遍，把两条读数并排打出来。
#
# 口令红线：值只从 /root/.dsh/entry.key 读进变量、经 stdin 交给 `curl -K -`，
# **不进 argv、不进输出、不进日志**（这也是为什么这里用 -K - 而不是 -H）。
set -u
KEY=$(cat /root/.dsh/entry.key 2>/dev/null)
if [ -z "$KEY" ]; then echo "读不到 /root/.dsh/entry.key，这一版脚本不猜，直接停"; exit 1; fi

echo "--- 甲：不带口令 ---"
curl -sS -m 4 -o - -w '\n[http=%{http_code} 字节=%{size_download} 耗时=%{time_total}s]\n' \
  http://127.0.0.1:3081/__entry_status 2>&1 | head -4

echo "--- 乙：带口令（值不打印）---"
printf 'cookie = dsh-entry=%s\n' "$KEY" | curl -sS -m 4 -K - -o - \
  -w '\n[http=%{http_code} 耗时=%{time_total}s]\n' \
  http://127.0.0.1:3081/__entry_status 2>&1 | head -14
unset KEY
