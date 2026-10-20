#!/bin/sh
# 只读探针（状态 19 那批 40 s 的归因第一步）：
# 从 chroot 里用 curl 打几个引擎端点，**穿过入口 :3081**，量三次看耗时稳不稳。
# 口令只从文件读进变量、只走 curl 的 -K -（stdin 配置），不进 argv、不打出来。
# 本脚本不写任何东西、不改任何配置；跑完可以当场删掉。
KEY=$(tr -d '\r\n' < /root/.dsh/entry.key 2>/dev/null)
[ -n "$KEY" ] || { echo "!! /root/.dsh/entry.key 读不到，这一段没量到（别把没量到读成没问题）"; exit 1; }
E=http://127.0.0.1:3081

probe() {
  path=$1; body=$2; reps=$3
  i=1
  while [ "$i" -le "$reps" ]; do
    printf 'cookie = dsh-entry=%s\n' "$KEY" | curl -sS -K - -o /dev/null --max-time 75 -X POST \
      -H 'content-type: application/json' -H "origin: $E" \
      -d "$body" \
      -w "  ${path}  第${i}次  http=%{http_code}  总 %{time_total}s  连上 %{time_connect}s  首字节 %{time_starttransfer}s\n" \
      "${E}${path}"
    i=$((i + 1))
  done
}

echo "--- 穿过入口的引擎端点耗时（本机 curl，不经 WebView）---"
probe /api/credentials/describe '{}' 3
probe /api/commands/list '{}' 3
probe /api/session/modelCatalog '{}' 2
probe /api/account/getBalance '{}' 2
echo "--- 对照：同一批里最可能出网的两条已经打过，若全是个位数毫秒，那 40 s 就不在引擎/网络这一侧 ---"
