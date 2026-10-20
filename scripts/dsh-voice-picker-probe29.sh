#!/bin/bash
# scripts/dsh-voice-picker-probe29.sh —— 接 p28 那条结论往下走一步：手机侧到底能不能自己把模型拉下来。
#
# p28 已经分清了哪层坏：UDP 53 对没钉 hosts 的域名一律 10 秒给空，而阿里 DoH 给真答案、
# 拿真答案直连 443 时境内站全通（aliyun 301 / modelscope 302 / gitee 200 / hf-mirror 200 /
# tuna 的 Range 206 真落了 1024 B / npmmirror 跟 302 后 200 且 tar 解得开），境外（npmjs 104.16.x、
# GitHub Pages 185.199.x）不通。⇒ 病在解析，不在下载。
# p28 第③段那三个"1046/360/1042 字节"不是模型，是 302 的重定向体 —— 我当时没跟转，所以那一段不能算证完。
# 这一发就是把它跟到底：
#   ① 对 hf-mirror 的模型 URL 用 -L 真取前 1 MB，报最终落到的主机名（插件用的是 node fetch，它自己会跟转，
#      所以"最终主机"就是手机上必须可达/必须钉住的那一个）；
#   ② 那台最终主机 DoH 一下看有没有真答案；
#   ③ GitHub 那侧：直连不通已确认，那就找国内代理镜像 —— 逐个 DoH→连→真取一个 raw 文件 1 KB。
#      注意 gh-proxy 这类在 p27 里报 000 是**没解析**，不是被墙，这次拿 DoH 的 IP 连才算公平。
# 出网计量：全程 KB 级（1 MB 那一发是唯一大的），完整读数在 downloads/p29.txt。
# 只读：不写 hosts、不装包、不动他的东西。口令不参与。
set -u
doh() {
  curl -sk -m 8 "https://223.5.5.5/resolve?name=$1&type=A" 2>/dev/null |
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);
      const a=(j.Answer||[]).filter(x=>x.type===1).map(x=>x.data).join(",");console.log(a||"无A记录");}
      catch(e){console.log("解析不出");}});'
}
HFI=$(doh hf-mirror.com | cut -d, -f1)
echo "== ⓪ hf-mirror 的 DoH 答案 = $HFI（hosts 里现在没有这条）"

echo
echo "== ① 跟转到底，真取模型前 1 MB（Range 0-1048575）"
P="csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/2365baeacb507f821a0c8120fcee3d484dba7a07/model.int8.onnx"
R=$(curl -sL -m 60 --resolve "hf-mirror.com:443:$HFI" -H 'Range: bytes=0-1048575' -o /tmp/p29-model.part \
      -w 'http=%{http_code} size=%{size_download} time=%{time_total}s 最终url=%{url_effective}' "https://hf-mirror.com/$P" 2>&1)
echo "  $R"
echo "  落盘：$(ls -l /tmp/p29-model.part 2>/dev/null | awk '{print $5" B"}')  sha256(前16)=$(sha256sum /tmp/p29-model.part 2>/dev/null | cut -c1-16)"
echo "  对照：整文件 sha 前 16 应是 c71f0ce00bec95b0（清单里那条）。前 1 MB 不等于整文件，所以这里只比头 16 字节，看落的是不是同一条流。"
printf '  头 16 字节：'; xxd -l 16 -p /tmp/p29-model.part 2>/dev/null
rm -f /tmp/p29-model.part

echo
echo "== ② 最终主机（①那行 url_effective 里的主机名）DoH 有没有真答案"
FIN=$(printf '%s' "$R" | sed -n 's/.*最终url=https:\/\/\([^/ :]*\).*/\1/p')
if [ -n "$FIN" ]; then printf '  %-32s DoH=%s  hosts命中=%s\n' "$FIN" "$(doh "$FIN")" "$(grep -cE "[[:space:]]$FIN\$" /etc/hosts)"; else echo "  没解析出最终主机"; fi

echo
echo "== ③ GitHub 国内代理镜像：DoH→直连→真取一个 raw 文件 1 KB"
RAWP="sherpa-onnx/sherpa-onnx/master/README.md"
for G in gh-proxy.com ghfast.top mirror.ghproxy.com ghproxy.net ghp.mgtm.fun github.moeyy.xyz; do
  IP=$(doh "$G" | cut -d, -f1)
  case "$IP" in *[0-9]*) ;; *) printf '  %-22s DoH 无答案\n' "$G"; continue ;; esac
  H=$(curl -s -o /dev/null -m 8 --resolve "$G:443:$IP" -w '%{http_code}' "https://$G/" 2>&1)
  B=$(curl -sL -m 20 --resolve "$G:443:$IP" -H 'Range: bytes=0-1023' -o /tmp/p29-g \
        -w 'size=%{size_download} 最终=%{url_effective}' "https://$G/https://raw.githubusercontent.com/$RAWP" 2>&1)
  printf '  %-22s 连 %s 首页http=%s  raw取回:%s\n' "$G" "$IP" "$H" "${B:-报错}"
  [ -s /tmp/p29-g ] && printf '      头 40 字节：%s\n' "$(head -c 40 /tmp/p29-g | tr -d '\n')"
  rm -f /tmp/p29-g
done

echo
echo "== ④ 对照：GitHub 直连（已钉 hosts 那条）再确认一次是不是真的连不上"
GH=$(grep -E "[[:space:]]github\.com\$" /etc/hosts | head -1 | awk '{print $1}')
printf '  github.com hosts 里钉的是 %s ⇒ ' "$GH"
curl -s -o /dev/null -m 8 --resolve "github.com:443:$GH" -w 'http=%{http_code} time=%{time_total}s\n' "https://github.com/" 2>&1
