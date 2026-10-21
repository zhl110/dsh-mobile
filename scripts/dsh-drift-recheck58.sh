#!/bin/bash
# dsh-drift-recheck58.sh —— 把探针 57 里两下"看着像坏"的读数按字节重测一遍，顺带清点 /tmp 里我留的东西。
#
# 为什么要再跑一发（不跑就是在猜）：
#   ① 57 第 2 节我自己写错了两处取数：`sed 's/.*"data":"\([0-9.]*\)".*/\1/p'` 里那个 `.*` 是**贪婪**的，
#      抓的是最后一个 A 记录而不是第一个；`pin_of()` 用 `$0 ~ d` 做子串匹配，问 github.com 时先撞上了
#      codeload.github.com 那行 ⇒ 于是报出"github.com 钉 .165 / DoH .166 漂了"。
#      同一次跑里的 `doh-hosts.sh --check`（node 精确取 Answer[0] + hosts 精确比 $2）给的是 **github.com 钉 .166、一致**。
#      ⇒ 两条互相打脸时以**精确那条**为准，但这句话得有读数支撑，所以 58 只干这一件：把可疑的两条按字节重测。
#   ② github.com 那发 code=000 bytes=0，但 connect=1.098 s 是真连上了的 ⇒ 我怀疑是 `-m 15 --max-filesize 200000`
#      把首页（远大于 200 KB）掐了，curl 在写统计前就中止，把 http_code 留成 000。**这条不许猜**，改用 robots.txt 与 Range 各测一遍。
#   ③ awesome-dsh-plugin.com 首页 200 bytes=0 —— 首页本来就是空壳，真件是 plugins.json，得打真路径才算"通"。
set -u
R() { # R <标签> <URL> <额外参数…>：只认字节
  local tag=$1 url=$2; shift 2
  printf '  %-34s %s\n' "$tag" \
    "$(curl -s -o /dev/null -m 25 -w 'code=%{http_code} bytes=%{size_download} connect=%{time_connect}s ttfb=%{time_starttransfer}s' "$@" "$url" 2>&1)"
}

echo "== 1 github.com：小文件 + Range，两条路各测"
R 'robots.txt 不带 --resolve'   https://github.com/robots.txt
R 'robots.txt 钉 .166'          https://github.com/robots.txt --resolve github.com:443:20.205.243.166
R '首页 Range 0-1023'           https://github.com/ -r 0-1023

echo "== 2 codeload / objects：真下载路的两跳"
R 'codeload 首页 Range 0-1023'  https://codeload.github.com/ -r 0-1023
R 'objects 404 页（能回字节即通）' https://objects.githubusercontent.com/nope

echo "== 3 awesome-dsh-plugin.com：打真件 plugins.json（只取前 1 KB）"
R 'plugins.json Range 0-1023'   https://awesome-dsh-plugin.com/plugins.json -r 0-1023
R '同上，钉 185.199.108.153'    https://awesome-dsh-plugin.com/plugins.json -r 0-1023 --resolve awesome-dsh-plugin.com:443:185.199.108.153

echo "== 4 57 里真漂的两条（钉的 IP 不在 DoH 集合里）：坏没坏只看字节"
for H in cdn.npmmirror.com mirrors.aliyun.com registry.npmmirror.com; do
  P=$(awk -v d="$H" '!/^[[:space:]]*#/ && $2==d {print $1}' /etc/hosts | head -1)
  R "$H（钉 $P）" "https://$H/"
done

echo
echo "== 5 /etc/hosts 逐条 vs DoH 首个答案，精确口径再数一遍（这次不贪婪）"
node -e '
const {execSync}=require("child_process");
const rows=execSync("awk \x27!/#/ && NF>=2 {for(i=2;i<=NF;i++) if($i ~ /[.]/) print $1, $i}\x27 /etc/hosts").toString().trim().split("\n");
let same=0, multi=0, gone=0, bad=[];
for(const r of rows){const [pin,h]=r.split(/\s+/);
  let j; try{j=JSON.parse(execSync(`curl -sk -m 10 "https://223.5.5.5/resolve?name=${h}&type=A"`).toString());}catch(e){bad.push(h+" 问不到");continue;}
  const A=(j.Answer||[]).filter(x=>x.type===1).map(x=>x.data);
  if(!A.length){gone++;bad.push(h+" DoH 无答案");}
  else if(A[0]===pin)same++;
  else if(A.includes(pin)){multi++;console.log("  在候选集合里但不是首选 : "+h+" 钉="+pin+" 首选="+A[0]);}
  else{bad.push(h+" 不在候选里 钉="+pin+" DoH="+A.slice(0,4).join(","));}
}
console.log("  合计 "+rows.length+" 条：首选一致 "+same+" / 在集合里 "+multi+" / DoH 空 "+gone+" / 对不上 "+bad.length);
bad.forEach(x=>console.log("  !! "+x));'

echo
echo "== 6 机上 /tmp 里我留下的东西（只列不删）"
echo "dsh-* 计数 : $(ls -d /tmp/dsh-* 2>/dev/null | wc -l)"
ls -la /tmp/dsh-* 2>/dev/null | head -40
echo "按名字去重后的前缀统计："
ls -d /tmp/dsh-* 2>/dev/null | sed 's|/tmp/||' | sed 's/[0-9]\{2,\}//g' | sort | uniq -c | sort -rn | head -12
echo "总占用 : $(du -sh /tmp 2>/dev/null | cut -f1)（/tmp  whole）"
