#!/bin/bash
# scripts/dsh-voice-picker-probe28.sh —— 分清楚这台机的网络到底是哪一层坏，并当场证明"手机能不能自己下东西"。
#
# p26/p27 摆出来的形状：凡是我提前钉进 /etc/hosts 的域名全通（tuna / npmmirror / deb.debian.org 都是 http=200），
# 凡是没钉的全 000；而 UDP 53 对境内域名 10 秒之后给空、对 huggingface.co 这种被墙域名给 Facebook 段的假答案。
# ⇒ 高度怀疑：**出站是通的，坏的只有解析**。但"高度怀疑"不能当他以后怎么办问题的答案，所以这一发分开测：
#   ① 用阿里 DoH（p27 丙证明它从手机侧 200 可用、且给的是真答案）拿一批域名的 A 记录；
#   ② 拿到的 IP 直接 --resolve 连一发 —— 通了 ⇒ 病在解析；还不通 ⇒ 病在出口，那才真要靠电脑；
#   ③ 顺手对 hf-mirror 那条模型 URL 真取 1 KB 字节回来（Range），因为"能 HEAD 通"和"能落字节"是两件事；
#   ④ npmmirror 的包体在 CDN 上（302），跟一发看跟不跟得动；
#   ⑤ apt 侧拿 tuna 的一个 Release 文件同样验字节。
# 出网计量：这一发全是 KB 级（DoH 每条几百 B、Range 各 1 KB），完整读数记在 downloads/p28.txt。
# 只读：不写 hosts、不改 resolv.conf、不装包。口令不参与。
set -u
doh() { # $1=域名 ⇒ 打出第一个 A 记录
  curl -sk -m 8 "https://223.5.5.5/resolve?name=$1&type=A" 2>/dev/null |
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);
      const a=(j.Answer||[]).filter(x=>x.type===1).map(x=>x.data).join(",");console.log(a||"无A记录");}
      catch(e){console.log("解析不出");}});'
}
for H in mirrors.aliyun.com modelscope.cn gitee.com cdn.npmmirror.com registry.npmmirror.com \
         mirrors.tuna.tsinghua.edu.cn deb.debian.org hf-mirror.com huggingface.co \
         github.com raw.githubusercontent.com objects.githubusercontent.com registry.npmjs.org; do
  PIN=$(grep -cE "[[:space:]]$H\$" /etc/hosts 2>/dev/null)
  IP=$(doh "$H")
  printf '  %-32s hosts=%s  DoH=%s\n' "$H" "$PIN" "$IP"
done

echo
echo "== ② 拿 DoH 的 IP 直连 443（通了＝病在解析；000＝病在出口）"
for H in mirrors.aliyun.com modelscope.cn gitee.com hf-mirror.com registry.npmjs.org raw.githubusercontent.com; do
  IP=$(doh "$H" | cut -d, -f1)
  case "$IP" in *[0-9]*) ;; *) printf '  %-28s 拿不到 IP，跳过\n' "$H"; continue ;; esac
  R=$(curl -s -o /dev/null -m 8 --resolve "$H:443:$IP" -w 'http=%{http_code} time=%{time_total}s' "https://$H/" 2>&1)
  printf '  %-28s 连 %s ⇒ %s\n' "$H" "$IP" "${R:-报错}"
done

echo
echo "== ③ 模型那三个文件：从 hf-mirror 真取前 1024 字节（URL 抄自 assets.json，revision 不动）"
IP=$(doh hf-mirror.com | cut -d, -f1)
for P in \
  "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/2365baeacb507f821a0c8120fcee3d484dba7a07/model.int8.onnx" \
  "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/2365baeacb507f821a0c8120fcee3d484dba7a07/tokens.txt" \
  "csukuangfj/vad/resolve/fba88cd2e921609e7675c3aaf51e0b9b295da4bc/silero_vad.onnx" ; do
  N=$(basename "$P")
  R=$(curl -s -m 20 --resolve "hf-mirror.com:443:$IP" -H 'Range: bytes=0-1023' -o "/tmp/p28-$N" \
      -w 'http=%{http_code} size=%{size_download} time=%{time_total}s' "https://hf-mirror.com/$P" 2>&1)
  S=$(sha256sum "/tmp/p28-$N" 2>/dev/null | cut -c1-16)
  printf '  %-22s %s  前1KB的sha=%s…\n' "$N" "${R:-报错}" "${S:-无}"
done
rm -f /tmp/p28-*.onnx /tmp/p28-tokens.txt

echo
echo "== ④ npm 包体在 CDN 上：跟 302 拉一个真包（is-odd，1 KB 级）"
curl -sL -m 20 -o /tmp/p28.tgz -w '  跟转后 http=%{http_code} size=%{size_download} time=%{time_total}s url=%{url_effective}\n' \
  "https://registry.npmmirror.com/is-odd/-/is-odd-3.0.1.tgz" 2>&1
tar -tzf /tmp/p28.tgz 2>&1 | head -3 | sed 's/^/    包内: /'
rm -f /tmp/p28.tgz

echo
echo "== ⑤ apt 侧：tuna 上 Ubuntu 24.04 的 Release 取前 1024 字节"
curl -s -m 20 -H 'Range: bytes=0-1023' -o /tmp/p28-rel -w '  http=%{http_code} size=%{size_download} time=%{time_total}s\n' \
  "https://mirrors.tuna.tsinghua.edu.cn/ubuntu/dists/noble/Release" 2>&1
head -c 80 /tmp/p28-rel 2>/dev/null | tr -d '\0' | sed 's/^/    开头: /'; rm -f /tmp/p28-rel
