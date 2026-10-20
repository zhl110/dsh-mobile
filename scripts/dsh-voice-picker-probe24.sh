#!/bin/bash
# scripts/dsh-voice-picker-probe24.sh —— 真拿手机上的 SenseVoice 识别一句中文，把文字读回来。
#
# 键名不是猜的（第一版就是猜的，p24a.txt 里被网关判 wire field "request" failed boundary validation）：
#   dsh-experimental-api-speech-to-text/lib/typert.host.js:339 起的描述符写着
#   TranscriptionRequest = { audioBase64: string(必填), providerId?: string, language?: string }，
#   core 包里那个 request.audio 是**网关解完参数之后**内部传给 provider 的名字，不是线上的键。
#   worker.js:110 直接从第 44 字节起取 PCM ⇒ 要的是 44 字节头的 canonical WAV；
#   validateWave 用 maxAudioBytes/32e3 判时长 ⇒ 32,000 B/秒 = 16 kHz 单声道 16-bit。
#
# 第二发（p24.txt）键名对了、又被拦一道：Audio must be a canonical 16 kHz mono PCM16 WAV recording。
# 不是采样率没转（ffprobe 明写 16000 Hz / 1 channel / s16），是 **ffmpeg 默认在 fmt 块后面塞了一块
# LIST INFO 元数据** —— 头 44 字节 hexdump 出来第 37-40 字节是 4c49 5354（"LIST"）而不是 6461 7461（"data"），
# 于是 'data' 不在偏移 36、整头不是 44 字节，而 worker.js:110 是硬按第 44 字节起读 PCM 的。
# 加 -map_metadata -1 -fflags +bitexact -flags:a +bitexact 重转 ⇒ 头变成 RIFF…WAVEfmt(16)…data，
# 135,658 B = 44 + 135,614，135,614 / 32,000 = 4.2379 秒，正好撞上回包里的 audioSeconds=4.2379375。
# 这一发才过（p24b.txt）。
# ⇒ 两处都记进 tools/make-voice-wav.ps1 的注释，别下轮再猜一遍。
#
# 为什么要走到这一步：p22 只证明了插件自己承认 ready（phase=ready、五步全 complete），
# 那还是"状态位"。ready ≠ 认得出话。 sherpa-onnx 在 arm64 上到底能不能前向、
# 中文能不能出字，只有喂一段真有说话的音频才知道。
# 测试件不是我录的真人声，是 Windows 自带 SAPI（Microsoft Huihui Desktop，zh-CN）合成的一句
# 「今天天气怎么样，我想出门散步。」，再用 ffmpeg 转成 16 kHz / 单声道 / 16-bit PCM
# （tools/make-voice-wav.ps1 + 一条 ffmpeg，读数见 downloads/voice-test-*.txt）。
# 合成音不是真人声 ⇒ 认得准不准只能当参考；这一发要证的只有"手机侧那条识别路真的跑通了"。
#
# 音频从 /tmp 读，payload 用 node 写成文件再 --data-binary @ 发；口令只经 stdin 给 curl -K -。
# 结束后把 /tmp 里这两份自己清掉（不是他的文件，是我这轮送进去的测试件）。
set -u
B=http://127.0.0.1:3081
WAV=/tmp/voice-test-zh-16k.wav
K=$(tr -d '\r\n' < /root/.dsh/entry.key)
[ -f "$WAV" ] || { echo "!! 测试音频不在：$WAV（先 adb push 到 chroot 的 /tmp）"; exit 1; }
echo "== 测试件：$(wc -c < "$WAV") B，sha256 $(sha256sum "$WAV" | cut -c1-16)…"

node -e '
const fs=require("fs");
const audio=fs.readFileSync("/tmp/voice-test-zh-16k.wav").toString("base64");
fs.writeFileSync("/tmp/p24.json", JSON.stringify({
  type:"client-request",rpcId:"p24",method:"speech/transcribe",
  payload:{args:{request:{audioBase64:audio,providerId:"sensevoice-local",language:"zh"}}}
}));
console.log("  payload = "+fs.statSync("/tmp/p24.json").size+" B（音频 "+audio.length+" B base64）");' 2>&1

echo "== 发 speech/transcribe（同步等结果，上限 90 秒）"
T0=$(date +%s)
R=$(printf 'cookie = dsh-entry=%s\n' "$K" | curl -s -m 90 -K - -X POST \
  -H 'content-type: application/json' -H "origin: $B" -H "referer: $B/" \
  --data-binary @/tmp/p24.json "$B/api/speech/transcribe" 2>&1)
T1=$(date +%s)
echo "  用时 $((T1-T0)) 秒，回包 $(printf '%s' "$R" | wc -c) B"
echo "  原文（前 900 B）：$(printf '%s' "$R" | head -c 900)"
echo
echo "== 单独把识别出来的文字挑出来（node 解析，防我把结构看花）"
printf '%s' "$R" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{const r=JSON.parse(s);const v=r.result&&r.result.value;
    console.log("  ok        = "+JSON.stringify(r.result&&r.result.ok));
    console.log("  value 结构 = "+JSON.stringify(v).slice(0,400));
    console.log("  识别文字   = "+JSON.stringify(v&&(v.text!==undefined?v.text:v.transcript)));
    if(r.result&&r.result.error)console.log("  错误      = "+JSON.stringify(r.result.error));}
  catch(e){console.log("  解析不出："+s.slice(0,200));}});' 2>&1
rm -f /tmp/p24.json "$WAV"
echo "== 收尾：/tmp 里这两份已删（$(ls /tmp/voice-test-zh-16k.wav /tmp/p24.json 2>&1 | head -1)）"
