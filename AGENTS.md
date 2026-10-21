# AGENTS.md — dsh-mobile 项目规则

> 上位规则：`D:\mycode\AGENTS.md` → 全局宪法 `~/.codex/AGENTS.md`。本文件只约束本项目。
> 目标与进度：[PROGRESS.md](PROGRESS.md)；逐轮读数与过程：[RUNBOOK.md](RUNBOOK.md)（14.x 按轮编号）。
> **本文件只写"下次别再犯"的规则与入口，读数不往这里抄** —— 抄一份就会有第二份真源，最后两边对不上。

## 这个项目在做什么

把 DeepSeek Harness（`@deepseek-ai/dsh` 0.2.1-rc.2）**完整跑在手机本机**：真 chroot 的 Ubuntu 24.04 arm64，
推理走联网调 API，用法要像桌面应用（点开就能用、能关掉、能挂后台）。交付物是**三层**：

```
壳 App com.zhl.dsh（桌面图标 · 自己的窗口 · 不走浏览器）
   ↓ http://127.0.0.1:3081/
常驻入口 scripts/dsh-entry.js（换 token 为 30 天 cookie · 兼容层出口内联 · 门禁）
   ↓ http://127.0.0.1:3080/
引擎 chroot 里的 dsh web（真页面与 RPC）
```

Termux 控制台（`/data/local/sh/dsh-console.sh` 菜单）与那个 16 MB 原生客户端是**对照与退路**，不是主路径。

## 开工顺序（冷启动照这个走）

1. **插上手机先复点**：上一轮收尾会关 adb、手机也可能被拔掉。先 `adb devices` + 端口/进程各读一次，
   **不要假设"上次还在跑"**（PROGRESS 顶部写着怎么复点）。
2. 读 [PROGRESS.md](PROGRESS.md) 顶部「接班先读这一段」→ `## 下一步` → `## 遗留问题`。
3. 要证据/要改口经过，再翻 RUNBOOK 的 14.x（14.21 = 语音模型那轮，14.22 = 网络那轮）。
4. 设备侧动手一律先写只读探针，走 `tools/run-probe.sh`；**不要**手搓 `adb shell "su -c …"`。

## 目录职责

```
dsh-mobile/
├─ app/                 Android 壳源码（MainActivity.java / AndroidManifest.xml / build.sh / out 已忽略）
├─ config/dsh-env       服务环境真源模板（bash source 它，必须 LF）
├─ scripts/             引擎侧：dsh-chroot.sh（chroot 总入口）/ dsh-entry.js（常驻入口）
│                       dsh-console.sh（Termux 菜单）/ dsh-ask.sh（命令行问一句）
│                       dsh-*-probe*.sh（历次只读探针，编号即轮次）
├─ tools/               Windows 侧工具：run-probe.sh / doh-hosts.sh / fetch|push-sensevoice.sh
│                       make-voice-wav.ps1 / deploy-entry.sh / pin-hosts.py / dsh-compat.js
├─ reference/           只读参照（三家 APK 解包、上游 index.js 等），不入库
└─ downloads/           每轮读数、日志、测试件（gitignore，但**改口与结论都要从这里读**）
```

设备侧固定路径：rootfs = `/data/local/dsh-rootfs`；chroot 的家目录在宿主上看是 `rootfs/root`；
runner = `/data/local/sh/dsh-chroot.sh`。**这两个路径不能混**（见铁律 1）。

## 铁律（每条都真摔过，违反就等于把坑再挖一遍）

1. **设备路径分两套**：宿主 `su` 看到的是 `/data/local/dsh-rootfs/root/x.sh`，chroot 里是 `/root/x.sh`。
   `su -c '…'` 用单引号包命令时，里面的 `/root` 会被**宿主 shell** 先解释掉 ⇒ 一律走 `tools/run-probe.sh`
   （它把 `MSYS2_ARG_CONV_EXCL='*'`、CRLF 剥离、两套路径、跑完删副本并数残留全按死了）。
2. **报数只认"能对上的数"**：三个计数必须相等（清单 N ⇒ 推 N ⇒ 机上校验 N）；合计要逐行相加。
   不许 `test -e` 判存在（EACCES 时它返回 false，造过假读数）、不许把计数器放进 `$( )`（子 shell 丢变量，犯过两次）、
   `wc -l` 数的是换行（`printf '%s'` 不带换行，会少报 1，犯过一次）。
3. **"通"的判据只认落字节**：`Range` 拿到 206 且头里有真内容、跟完 302 落到包体并解得开、音频真出字。
   端口在听 / HTTP 200 / 退出码 0 都不算。
4. **判"连不上"要分形状**，先给足窗口：到点超时（丢包样）vs 0.1 秒快速失败（不可达）不是一回事；
   6 秒窗曾把 GitHub 判死，30 秒窗同一 IP 传回 676,496 B。
5. **解析问题先查解析**：这台机 UDP 53 基本废、被墙域名还会给假答案（Facebook 段）。
   先手机上 `bash /root/doh-hosts.sh --check`，要补再 `--sync`（写前逐字节备份 + 比 sha256）；
   **验收不许带 `--resolve`**，带了就算 hosts 没修好也 200，是自欺。
6. **他的东西一律不碰**：`/data/local/tmp` 里他那批（`boot_b.img` / `init_boot_b.img` / `kpatch/` / `magiskboot` /
   `patch_boot*.sh` / `brevent*` / `sukisu_*.ko` …）、KernelSU/susfs 配置、锁屏。只删自己建的，删前逐个确认。
7. **不 reboot、不装包、不进锁屏、不动自启开关**：`apt install` 这类要他点头；自启现在是 `.off`，拨不拨他说了算。
8. **凭证不进任何可回看的地方**：API key、`/root/.dsh/entry.key` 不进口令行、不回显、不写日志、不写文档；
   curl 要给 header 就用 `-K -` 从 stdin 递。
9. **git 两个动作都带 pathspec**：`git add -- .`、`git commit … -- .`。这个仓里同时躺着他别的项目的批量删除，
   不带 pathspec 会一起带走（首入库时差点中招）。不 amend，不 commit 除非他说。
10. **文档纪律**：改口**就地加箭头**、不删旧话；每个数字来自盘上读数；事实与推断分开标；
    汇报必须写"没做什么"；提交号回来填死。
11. **时钟**：chroot 本地时区是 **UTC**，文档里的"凌晨/深夜"按他电脑上的北京时间写，差 8 小时；
    `/etc/hosts` 备份文件名 `hosts.bak.<时间戳>` **按 UTC 读**。

## 常用命令（Windows 侧，git-bash）

| 目的 | 命令 |
|---|---|
| adb（不在 PATH 里） | `/d/mycode/.agent-tools/platform-tools/adb.exe` |
| 送一条只读探针并收尾 | `bash tools/run-probe.sh scripts/<探针>.sh downloads/<输出>.txt [参数…]` |
| 看服务/环境 | `adb shell "su -c \"/data/local/sh/dsh-chroot.sh --status\""` |
| 起引擎 / 起入口 / 停 | 同上 `--web` / `--entry` / `--stop` / `--entry-stop` |
| 在 chroot 里跑一条 | 同上 `--run 'bash /root/<脚本>'` |
| 手机侧 hosts 对账 / 补钉 / 还原 | 同上 `--run 'bash /root/doh-hosts.sh --check\|--sync\|--revert <备份>'` |
| 命令行问 dsh 一句 | `--run 'bash /root/dsh-ask.sh'`（问题写进 `/tmp/dsh-task`，不走 argv） |
| 重打 APK | `bash app/build.sh`（版本号在 `AndroidManifest.xml` 与 `build.sh` 两处） |
| 电脑侧取模型 / 推模型 | `bash tools/fetch-sensevoice.sh` / `bash tools/push-sensevoice.sh` |

## 已知坑（都是一次性真相，别再花一轮去重新发现）

- **语音 RPC 的线上键是 `audioBase64`**，不是 core 内部那个 `request.audio`；调之前先读 descriptor。
- **canonical WAV** 只认 44 字节头、PCM 从第 44 字节起读；ffmpeg 默认塞 LIST 元数据块 ⇒ 必须
  `-map_metadata -1 -fflags +bitexact -flags:a +bitexact`。
- **模型目录形状**：`models/silero/` 与 `models/sensevoice-onnx/` 是**兄弟**，不是子目录。
- **`preparation` 是进程内状态**，不是盘上文件；`prepare` 前先从 `speech/catalog` 的 `selection.providerId` 取 providerId。
- **插件校验靠 size + 整文件 sha256**，撞上就不联网 ⇒ 模型可以"电脑下 + push"，不用改插件配置。
- **hf-mirror 的 302 落在 `cas-bridge.xethub.hf.co`**，手机侧 0 字节 ⇒ 模型这类仍走电脑代取；
  apt / npm / GitHub 手机自己能走（GitHub 约 22–26 KB/s，clone 前要 `apt install git`，得他点头）。
- **APK 打包不是逐字节可复现**：同源码重打 sha 会变 ⇒ 认 sha 记"哪一次打包"，版本号区分不了两发。
- **PowerShell 5.1 读无 BOM 的 .ps1 会吞中文**；写 .ps1 一律带 UTF-8 BOM。
- **推上手机的 `.sh` 必须零 CR**：`run-probe.sh` 会先拦（CR 会让设备 bash 把 `\r` 当命令的一部分）。

## 不在这里写的东西

当前状态、待办、遗留问题**不要**往本文件加 —— 它们在 PROGRESS 里，只有一处真源。
本文件只在出现**新的、可复现的**踩坑时加一条，并带上"读数在哪"。
