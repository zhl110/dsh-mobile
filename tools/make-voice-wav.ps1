# tools/make-voice-wav.ps1 —— 造一段"有人说话"的测试音频，用来真跑一遍手机上的语音识别。
#
# 为什么不用静音当测试件：静音喂进去识别结果必然是空串，那只能证明"链路没报错"，
# 证明不了模型真的在手机上前向了一遍。这里用 Windows 自带的 SAPI 合成一句中文（zh-CN Huihui），
# 再交给 ffmpeg 转成 16 kHz / 单声道 / 16-bit PCM —— 这正是 SenseVoice 那侧要的格式。
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/make-voice-wav.ps1 -Out downloads/voice-test-zh.wav
# 只读系统、只往 -Out 指定的路径写一个文件，不动任何别的东西。
param(
  [string]$Text = "今天天气怎么样，我想出门散步。",
  [string]$Out  = "downloads/voice-test-zh.wav",
  [string]$Culture = "zh-CN"
)
Add-Type -AssemblyName System.Speech
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$want = $s.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture -like "$Culture*" } | Select-Object -First 1
if ($null -eq $want) {
  Write-Output "!! 没有 $Culture 的声音；这台机器上装的是："
  foreach ($v in $s.GetInstalledVoices()) { Write-Output ("   {0} | {1}" -f $v.VoiceInfo.Culture, $v.VoiceInfo.Name) }
  exit 3
}
$s.SelectVoice($want.VoiceInfo.Name)
$full = [System.IO.Path]::GetFullPath($Out)
New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
$s.SetOutputToWaveFile($full)
$s.Speak($Text)
$s.SetOutputToNull()
Write-Output ("[ok] 用 {0} 合成 → {1}（{2} B）" -f $want.VoiceInfo.Name, $Out, (Get-Item $full).Length)
Write-Output "     说的内容：$Text"
