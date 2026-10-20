#!/bin/bash
# scripts/dsh-voice-picker-probe22.sh —— 把"下模型"这件事闭环：让插件自己走一遍 prepare。
#
# 为什么这一步是安全的（读代码读出来的，不是我估的）：
#   lib/index.js:338  download() 的第一行就是 if (await matchesAsset(...)) return;
#   而 matchesAsset(:186-199) 判的是"字节数相等 + 整文件 sha256 相等"。
#   ⇒ 三份文件既然已经撞上清单，prepare 不会发起网络请求，也不会覆盖或删除任何东西。
#   它剩下的动作只有 verifyRuntime(:222-238) 与起 worker 载模型 —— 只读 + 吃内存。
#   机器还有 9.6 GB 可用（p21 读数），插件自报 expectedMemoryBytes = 1,000,000,000，够。
#
# 第一版栽在参数上（p22a.txt）：speech/prepare 的描述符要 providerId，我给的是空对象，
# 网关直接 arguments-invalid；接着我又拿 catalog 去轮询，读到的是**上一次失败留下的内存快照**
# （phase 还是 failed），差点把这当成"推过去的文件不算数"。所以这一版改成：
#   先从 catalog 读 providerId ⇒ 再发 prepare ⇒ 只在"发过 prepare 之后"才认 phase 变化。
# 口令只从 /root/.dsh/entry.key 读进变量、经 curl -K - 走 stdin，不进 argv、不打印。
set -u
B=http://127.0.0.1:3081
K=$(tr -d '\r\n' < /root/.dsh/entry.key)
call() { # $1=method $2=args-json $3=超时秒
  printf 'cookie = dsh-entry=%s\n' "$K" | curl -s -m "${3:-20}" -K - -X POST \
    -H 'content-type: application/json' -H "origin: $B" -H "referer: $B/" \
    -d "{\"type\":\"client-request\",\"rpcId\":\"p22\",\"method\":\"$1\",\"payload\":{\"args\":$2}}" \
    "$B/api/$1" 2>&1
}
cat_field() { # 从 catalog 原文里用 node 挑字段，防我肉眼看花；取值走环境变量，不在命令行里拼引号
  DSH_PICK="$1" node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
    try{const v=JSON.parse(s).result.value;const r=new Function("v",process.env.DSH_PICK)(v);
      console.log(typeof r==="string"?r:JSON.stringify(r));}
    catch(e){console.log("解析不出："+s.slice(0,160));}});'
}

echo "== 0. 先拿 providerId 与当前 phase（这一步不改任何东西）"
C0=$(call speech/catalog '{}' 20)
PIDv=$(printf '%s' "$C0" | cat_field 'return v.selection.providerId')
echo "  providerId = $PIDv"
echo "  发 prepare 之前的 phase = $(printf '%s' "$C0" | cat_field 'return v.providers[0].preparation.phase')"

echo
echo "== 1. 发 prepare（args = {providerId:$PIDv}）"
R=$(call speech/prepare "{\"providerId\":\"$PIDv\"}" 40)
echo "  回：$(printf '%s' "$R" | head -c 500)"

echo
echo "== 2. 之后每 5 秒读一次 catalog，最多 36 次（180 秒）：phase / 步骤 / 引擎 RSS"
PREV=""
for i in $(seq 1 36); do
  C=$(call speech/catalog '{}' 20)
  L=$(printf '%s' "$C" | cat_field 'const p=v.providers[0].preparation;return p.phase+" | "+(p.message||"")+" | "+p.steps.map(x=>x.kind+":"+x.status).join(",")')
  P=$(printf '%s' "$C" | cat_field 'return v.providers[0].preparation.phase')
  RP=$(pgrep -f "dsh web" 2>/dev/null | head -1)
  RSS_KB=$(ps -o rss= -p "${RP:-0}" 2>/dev/null | tr -d ' ')
  printf '  [%03ds] %-90s 引擎RSS=%s MB\n' "$((i*5))" "$L" "$(( ${RSS_KB:-0} / 1024 ))"
  case "$P" in ready|standby) echo "  ⇒ 落到 $P，收工"; break;; esac
  PREV=$P
  sleep 5
done

echo
echo "== 3. 最后整条 catalog 留档（前 1300 B）"
printf '%s' "$C" | head -c 1300
echo
