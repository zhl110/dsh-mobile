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
│                       make-voice-wav.ps1 / deploy-entry.sh / **deploy-env.sh（`/root/.dsh-env` 的部署器，带 --check/--revert）**
│                       pin-hosts.py / dsh-compat.js / install-apk.sh / install-phone-plugins.sh
├─ reference/           只读参照（三家 APK 解包、上游 index.js 等），不入库
└─ downloads/           每轮读数、日志、测试件（gitignore，但**改口与结论都要从这里读**）
```

设备侧固定路径：rootfs = `/data/local/dsh-rootfs`；chroot 的家目录在宿主上看是 `rootfs/root`；
runner = `/data/local/sh/dsh-chroot.sh`。**这两个路径不能混**（见铁律 1）。

**git 是两套（2026-10-21 晚他一句"提交到我的 GitHub 仓库里面去，权限是私密的"之后）**：
本目录现在有**自己的** `.git`，remote `origin` = GitHub 私密库 `zhl110/dsh-mobile`，历史是从工作区仓
`D:\mycode` 用 `git subtree split --prefix=dsh-mobile` 切出来的 5 发（做法与读数见 RUNBOOK 那一节）。
`D:\mycode` 那个仓**照旧跟踪这些文件**（与他另一项目 `agent-hub` 同性质：父仓跟踪 + 子目录自己有 `.git`），
所以**每轮两个仓都要提交**，否则父仓会一直挂着脏项、下次冷启动的人以为没做。

## 铁律（每条都真摔过，违反就等于把坑再挖一遍）

1. **设备路径分两套**：宿主 `su` 看到的是 `/data/local/dsh-rootfs/root/x.sh`，chroot 里是 `/root/x.sh`。
   `su -c '…'` 用单引号包命令时，里面的 `/root` 会被**宿主 shell** 先解释掉 ⇒ 一律走 `tools/run-probe.sh`
   （它把 `MSYS2_ARG_CONV_EXCL='*'`、CRLF 剥离、两套路径、跑完删副本并数残留全按死了）。
   10-21 傍晚又犯一次、症状不一样：我随手写 `--run 'ls -1 /phone | wc -l'` 没走包装，**引号塌了 ⇒ 命令被宿主 shell 求值**，
   于是回 `No such file or directory`，看着像"手机存储没挂进来"。实际挂载一直在。**这类"路径不存在"先怀疑自己在哪一侧求值，别去改他的挂载。**
   **`/tmp` 也是两套**（10-21 晚 14.28）：我在 PC 的 git-bash `/tmp` 里重定向存了一份流量基线，探针第 9 节去查**手机 chroot 的 `/tmp`** ⇒ 设备侧永远报"基线不在"。
   跨侧的文件要么落在项目里（`downloads/`），要么在探针里写死它到底是哪一侧，别指望两个 `/tmp` 是同一个。
2. **报数只认"能对上的数"**：三个计数必须相等（清单 N ⇒ 推 N ⇒ 机上校验 N）；合计要逐行相加。
   不许 `test -e` 判存在（EACCES 时它返回 false，造过假读数）、不许把计数器放进 `$( )`（子 shell 丢变量，犯过两次）、
   `wc -l` 数的是换行（`printf '%s'` 不带换行，会少报 1，犯过一次）。
   **同一支探针里"列表"与"计数"必须同源**：10-21 那发 p39 同时打出"两条监听"和"命中行数 = 0"，因为计数走 `grep ':(3080|3081)$'`
   数的是整行末尾，而 `ss -ltn` 行末还有 peer / 进程列 —— 措辞没用，只有让计数复用那同一个 `awk '$4 ~ …'` 才不再打脸。
   **列号与字段语义先查再印**（同一发探针里连错三处）：`ls -l --time-style=long-iso` 是 `$5` 大小 `$6` 日期 `$7` 时刻；
   `df -h` 的"剩"是 `$4`（`$6` 是挂载点，取错就打出"剩 /"）；`/proc/pid/stat` 第 22 字段是"**开机后第几秒出生**"不是年龄 ——
   出生 = `/proc/stat` 的 `btime` + 它，年龄 = `/proc/uptime` − 它，`/proc/<pid>` 目录 mtime 更不沾边（这三条各犯过一次）。
   **引一个数要带口径**：`/phone` 顶层 117 是 `ls -1`、135 是 `ls -1A`，同一挂载差 18 个隐藏条目；单写"135 个条目"下次就对不上号。
   **年龄要在打的那一刻现读**：`/proc/uptime` 在脚本开头取一次快照，之后拿它去算"新进程活了多久" ⇒ p44 打出**"活着 -3 秒"**（新引擎比快照晚出生）。
   出生时刻可以用开机后秒数反推（`btime + $22/HZ`），**年龄不行**。这是上面第 22 字段那条的同族第三种形状。
   **`lo` 的 rx 与 tx 是同一批字节**（两侧各计一次，所以两列永远相等）⇒ 全表 `rx+tx` 求"这轮走了多少网"会把回环**双计**，而且它根本不是出网。
   出网只数 `wlan*` 与 `rmnet*`，并写清窗口与"这个窗口里装的是哪几件事"。
   **两份清单拼起来数行数 = 造重叠计数**（14.29 又犯一种新形状）：`git add --dry-run` 对**已跟踪的修改件**也打一行 `add '…'`，
   我把它的 34 行当"新件数"再去加 `git ls-files` 的 109，得出"143 个文件"—— 那 34 真值是**新增 23 + 修改 11**，11 个本来就在 109 里。
   ⇒ 认新件只认 `git diff --cached --name-only --diff-filter=A`，认总数只认 `git ls-files | wc -l`，别拿两种口径的行数相加。
3. **"通"的判据只认落字节**：`Range` 拿到 206 且头里有真内容、跟完 302 落到包体并解得开、音频真出字。
   端口在听 / HTTP 200 / 退出码 0 都不算。
   **按需触发的链路，"没报错"不算通过**（14.28）：dshmarket 只在页面打开那一刻才取目录 ⇒ 换代后 `log.ndjson` 一字节没长，
   只证明"没人来过"，不证明"修好了"。这种格子要么自己造一次真触发，要么如实写"欠他一眼"。
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
   **"我只列键名"要靠代码兜住，不能靠我记得**（14.28 差点破戒）：`grep '^export' f | cut -d= -f2` 取的是**等号右边的值**，
   与注释里那句"只列键名"正好相反；列键名要写 `sed -n 's/^export \([A-Za-z0-9_]*\)=.*/\1/p'`，
   读 `/proc/<pid>/environ` 同理（`sed -n 's/^\(DSHM[A-Za-z0-9_]*\)=.*/\1=<有值>/p'`，别 `grep` 出来原样印）。
9. **git 两个动作都带 pathspec**：`git add -- .`、`git commit … -- .`。这个仓里同时躺着他别的项目的批量删除，
   不带 pathspec 会一起带走（首入库时差点中招）。不 amend，不 commit 除非他说。
   **嵌套仓里"当前目录"不再是项目根**：在 `D:\mycode` 里干活时 pathspec 要写 `dsh-mobile/<路径>`，
   进了 `dsh-mobile` 里就得写 `./<路径>`；同一句话在两个仓里含义不同，动手前 `git rev-parse --show-toplevel` 认一遍人在哪个仓。
   **10-21 晚我在这条上摔过一发（已还原，别学）**：我写 `git init -q --initialBranch=main .`，选项名少一个连字符
   ⇒ init **失败退出**，而后面用 `;` 串着的 `update-ref` / `symbolic-ref` / `reset --mixed` 照样跑了 —— 因为
   目录里没有 `.git` 时 git 会**往上找到父仓**，于是那三发全打在 `D:\mycode` 上：它的 `main` 被我挪到了 split 那一发、
   index 被 reset 成 split 的树。症状是 `git log` 只剩 5 发、`rev-list --count HEAD` 从 227 变 5。
   靠 `reflog` 找回 `175bcfbf` 还原了，**盘上一个字节没动**（`reset --mixed` 只改 index），代价只有"他暂存区里若有东西会被打回未暂存"。
   两条要留住的规矩：① **建仓这类"前一条不成功后一条就不该跑"的动作，用 `&&` 串并留 `[ok]` 回声，别用 `;`**；
   ② **挪分支之前先把 `rev-parse HEAD` 与 `rev-list --count HEAD` 打出来**，还原后就有一对可比的数（我那轮靠 reflog，但 reflog 会过期）。
10. **文档纪律**：改口**就地加箭头**、不删旧话；每个数字来自盘上读数；事实与推断分开标；
    汇报必须写"没做什么"；提交号回来填死。
11. **时钟**：chroot 本地时区是 **UTC**，文档里的"凌晨/深夜"按他电脑上的北京时间写，差 8 小时；
    `/etc/hosts` 备份文件名 `hosts.bak.<时间戳>` **按 UTC 读**。
12. **自家文档里的计数要能当场重跑**：`PASS N/N`、"合计 N 条"、清单条数这类数字一旦写进文档就会被下一个人（包括明天的我）当事实，
    而代码一改它就不作数。要引用就先重跑一次、只抄脚本打的"合计"行，过时的旧读数**就地加箭头**不删。
    （14.26 这轮自己撞上了：14.16 那节记的 59 条早于后续改动，当场重跑是 58。）
13. **改 `/root/.dsh-env` 必须重启引擎才吃得进，而"重启"有最小那一条**：入口 spawn 那条命令是
    `. /root/.dsh-env …; exec dsh web --port 3080`（`scripts/dsh-entry.js:70`），**这文件只在 spawn 那一刻 source 一次**；
    最小的重启 = **只 `SIGTERM` 引擎**，入口自己有监管（`dsh-entry.js:168-177`，2 s backoff 起、封顶 30 s，见 startup 行就复位），
    它自己认新一代启动行、重换 cookie ⇒ 他手机里那条入场链接与门禁**都不作废**，代价只剩"那几秒正在跑的会话断掉"（**重启本身要他在场**）。
    **杀之前先数身份**（#45 的探针侧形状）：`cmdline` 含 `dsh web` 的进程**恰好 = 1** 才杀，同时断言入口非空且与它不是同一 pid；
    只 `pgrep | head -1` 就动手是错的（PID 会复用，光看 pid 不看 cmdline 会杀错人）。
    部署这文件走 `tools/deploy-env.sh`（备份→逐字节撞 sha256 才写→落点 md5 复点→`--revert` 还原），**`--check` 能查出机上还是旧发** ——
    14.28 就是这么发现 `config/dsh-env` 的 10-20 改动从没推上去过（机上一直 1,687 B）。

## 常用命令（Windows 侧，git-bash）

| 目的 | 命令 |
|---|---|
| adb（不在 PATH 里） | `/d/mycode/.agent-tools/platform-tools/adb.exe` |
| 送一条只读探针并收尾 | `bash tools/run-probe.sh scripts/<探针>.sh downloads/<输出>.txt [参数…]` |
| 看服务/环境 | `adb shell "su -c \"/data/local/sh/dsh-chroot.sh --status\""` |
| 起引擎 / 起入口 / 停 | 同上 `--web` / `--entry` / `--stop` / `--entry-stop` |
| 在 chroot 里跑一条 | 同上 `--run 'bash /root/<脚本>'` |
| 手机侧 hosts 对账 / 补钉 / 还原 | 同上 `--run 'bash /root/doh-hosts.sh --check\|--sync\|--revert <备份>'` |
| **部署 `/root/.dsh-env`**（改档位、加 `DSHM_*` 这类引擎环境变量之后） | `bash tools/deploy-env.sh --check` 先看对不对等；`sh tools/deploy-env.sh` 写（备份→sha256→md5 复点）；`sh tools/deploy-env.sh --revert <备份>` 逐字节还原。**写完必须重启引擎才吃得进**（铁律 13） |
| 让引擎换代并复点新 env 吃没吃到 | `bash tools/run-probe.sh scripts/dsh-engine-restart-and-verify44.sh downloads/p44.txt`（**它会 SIGTERM 引擎** ⇒ 要他在场；里面那段"杀前数身份"就是为这条服务的） |
| 市场这一格动没动（**最便宜的一发，纯只读**） | `bash tools/run-probe.sh scripts/dsh-market-check-probe45.sh downloads/p45.txt`（三层现场 + `.dsh-market/` 两个文件的字节/行数/级别计数 + hosts 里那两个 host + `/proc/net/dev` 全表） |
| 市场一直转圈 / 目录取不到 的深查 | `bash tools/run-probe.sh scripts/dsh-market-catalog-probe42.sh downloads/p42.txt`（只读：`state.json` 的区、`log.ndjson` 全文、四个目录地址、hosts 名单、`:3080` 与 `:3081` 各回什么码）；修法量法见 `…probe43.sh` |
| 命令行问 dsh 一句 | `--run 'bash /root/dsh-ask.sh'`（问题写进 `/tmp/dsh-task`，不走 argv） |
| 重打 APK | `bash app/build.sh`（版本号在 `AndroidManifest.xml` 与 `build.sh` 两处） |
| 重跑入口自测（**不需要手机**，Windows 侧就能跑） | `node scripts/dsh-entry.js --selftest`（2026-10-21 当场：`合计 58 条：PASS 58 / FAIL 0`；铁律 12） |
| 换图标（切五档） | 先把满幅方图存成 `app/icon/icon-src.png`，再 `sh app/icon.sh`，最后重打 APK |
| 电脑侧取模型 / 推模型 | `bash tools/fetch-sensevoice.sh` / `bash tools/push-sensevoice.sh` |
| 电脑上官方 DSH 的 CLI（不在 PATH） | `powershell -NoProfile -Command "cd 'D:\program files\DeepSeek\resources\runtime\cli\bin'; .\dsh.cmd plugin --profile desktop list"` |
| 量手机侧现状（profile / pnpm / registry 出口，纯只读） | `bash tools/run-probe.sh scripts/dsh-plugins-probe32.sh downloads/p32.txt` |
| 复点"这台机什么干不了"这类断言（含模型自己的自述） | `bash tools/run-probe.sh scripts/dsh-envclaim-probe33.sh downloads/p33.txt` |
| 装之前置体检（本地清单 + 设备数 + chroot 有没有 pnpm） | `bash tools/install-phone-plugins.sh --check` |
| 把 tarball 装进手机 `web` profile | `bash tools/install-phone-plugins.sh`（三计数：清单 / 推上去 / sha256 撞上，不等就停） |
| 装 APK 但**不重打** | `bash tools/install-apk.sh`（只推现成那发；`--verify` 只比指纹、一个字节不写。**别用 `app/build.sh --install`**：它前六步无条件重打，sha 必变 ⇒ 报过的指纹作废） |
| 收尾量流量 / 我留了什么 / 引擎现场 | `bash tools/run-probe.sh scripts/dsh-traffic-and-cleanup-probe39.sh downloads/p40.txt`（`/proc/net/dev` 两拍差值、`lo` 上的连接数、两个 node 的出生与年龄、机上 `.sh` 残留分类） |
| **开工复点时顺手取一次 `/proc/net/dev` 全表** | 10-21 傍晚这轮就没取，"整轮走了多少网"当场答不出增量，只能退回"我点得出的字节"（14.27 八）。基线只有开工那一刻有。→ **同日再补**：别存进 PC 的 `/tmp`（那是**另一个** `/tmp`，探针在手机上查不到，见铁律 1），**直接 `> downloads/net-full-<北京时间>.txt`**，下一发的差集在 PC 上拿这两份文本算（`名字 rx tx` 三列；口径见铁律 2 的 `lo` 那条）。第一份在 `downloads/net-full-20261021-185612.txt` |
| 推到 GitHub 私密库 | 先 `git rev-parse --show-toplevel` 确认人在 `D:/mycode/dsh-mobile`，再 `git add -- .` / `git commit -m … -- .` / `git push origin main`（`origin` = `zhl110/dsh-mobile`，**私密**）。推完复点：`git rev-list --count HEAD` 与 `git rev-list --count origin/main` 要相等，`gh repo view --json visibility` 要回 `PRIVATE` |

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
- **图标要喂满幅方图**：启动器自己会裁形状，带白底的圆角导出（Figma/分享导出的那种）会把四个白角原样带上桌面。
  `app/tools/SquareIcon.java` 能给白角补色，但补出来有一圈很淡的圆角接缝，能用不等于好看。
- **验 APK 里的图标不能比文件 sha**：aapt2 会重压 PNG（152 KB 的包里 xxxhdpi 只有 56,997 B，源图 74,897 B），
  要比就解出来逐像素比（`downloads/icon-check/ComparePng.java` 是当时的临时件）。
- **PowerShell 5.1 读无 BOM 的 .ps1 会吞中文**；写 .ps1 一律带 UTF-8 BOM。
  同一套里 `System.Drawing` 不会自动加载 ⇒ 先 `Add-Type -AssemblyName System.Drawing`，否则报"找不到类型 Bitmap"。
- **推上手机的 `.sh` 必须零 CR**：`run-probe.sh` 会先拦（CR 会让设备 bash 把 `\r` 当命令的一部分）。
- **调官方桌面端那个 `dsh.cmd` 只能走 PowerShell**：它的路径含空格（`D:\program files\DeepSeek\...`），
  git-bash 里 `cmd //c "…"` 会把参数在空格处劈开，报 `'esources' 不是内部或外部命令`（2026-10-21 实测）；
  `powershell -NoProfile -Command "cd '…\cli\bin'; .\dsh.cmd …"` 才通。
- **给桌面 profile 装本地插件 = `dsh plugin --profile desktop add <tgz>`**，它只是把包转给 pnpm 装进
  `~/.dsh/profiles/desktop`；**真正改宿主要靠 App 里插件设置页那记「应用」**（这步按插件 README 不该由助手代点）。
  → 这句**只对"要改宿主"的那类插件成立**（dsh-purge 就是）；纯层栈类插件（dshmarket 那发）自带的 `cordis.patch.yml` 只插一行，**根本没有「应用」这一步**，别报"等他点应用才好使"这种错话。
  `file:` 依赖会把 profile 钉在你给的那个 tarball 路径上 ⇒ 别指 `downloads/`，放稳定路径（现装在 `D:\tools\dsh-plugins\`）。
- **往桌面 profile 装新 bundle 不用重启客户端**（我第一轮写成"要重启"，被读数推翻）：宿主 HMR 会为层栈里**新增**的 bundle 重组合 ——
  `add` 落盘 **2 秒**后 profile 根下自己长出 `.dsh-market/state.json`（78 B）+ `log.ndjson`（124 B，里面那行还是它自己跑完网络探域的结果）。
  ⇒ 判"装完起没起"**认它自己写的状态件与日志字节**，别看退出码、也别急着让他退出重开；**设置页里那条入口在不在仍要他自己看**，我替代不了。读数 RUNBOOK 14.24。
- **`dsh-purge` 打过补丁的机器上，判"宿主改没改"不能只看 `app.asar`**：它走的是解包目录优先加载
  （`resources\app` 在位 + `*.dshpurge.bak` 一堆 + `dsh.cmd` 被改写并留 `.bak`，**`app.asar` 可以一字未动**）。
  复测就测那三个：`resources\app` 存在性、`.dshpurge.bak` 份数、`app.asar` 的 sha 前缀。
- **社区插件这摊：仓名 / npm 包名 / 层栈 id 是三个名字**（`dsh-market/dsh-market` 仓、包叫 `dshmarket`、插进层栈的 id 是 `dsh-market`），
  而且同名仓很挤（搜 `dsh-market` 回 284 个仓、两家同名）⇒ **报版本必须带仓全名 + tag/包版本**，只说"dsh-market 最新版"迟早对错东西。
- **镜像上下来的包要三条口径同时对**才算"就是官方那发"：registry 的 `integrity`（sha512→base64）、`shasum`（sha1）、
  `unpackedSize`（解出来 `du -sb`）。npmmirror 的 `shasum` 抄的是 npm 原值，所以它能当交叉证。
- **电脑那套装插件的路径不能照抄到手机**，三处不对等（每次动之前先想起来）：profile 名 **手机 `web` / 电脑 `desktop`**；
  宿主形态 **手机是 npm 装的全局 dsh，电脑是 Electron 的 asar + 解包 `resources\app`** ⇒ purge 的「应用」在手机上改的是什么、改不改得动，**未验**；
  `dsh plugin` 只是把参数转给 **pnpm**，电脑上有（11.28.5），**手机 chroot 里有没有还没读到**（没有就要 `npm i -g pnpm` = 往他机上装包 ⇒ 得他点头）。
- **PowerShell 用 `-Command "…"`（双引号）时，bash 会把 `$_` / `$LASTEXITCODE` 吃掉**：前者被换成上一条命令的最后一个参数
  （报 `/d/mycode/dsh-mobile.ProcessName 无法识别为 cmdlet`），后者变空（报`必须在"+"运算符后面提供一个值表达式`）。
  写 `\$` 转义，或者干脆用通配避开它们。
- **"这台机做不到 X"这类断言要分成四种形状再下结论**，别一来就认（也别看模型自述像样就当事实）：
  ① **真做不到**（内核没编 `USER_NS`/Landlock、没有 X 服务）；② **没挂进来**（chroot 只 rbind `proc sys dev` + `/phone`，
  所以它报"`/system/bin` 整个不存在、一点 Android 接口都没有"——那是**我们的挂载选择**，不是限制，见 14.25 一·3）；
  ③ **建好了但没接线**（`dsh-unshare-run` 34 PASS 在位，profile 里没 `runnerCommand` ⇒ 它只能报"沙盒不可用、只能完全访问"，见 14.25 一·1）；
  ④ **在它视角外**（自启服务在宿主侧、常驻入口在 chroot 外，它按"PID 1 不是 systemd / 进程挂了没人拉"就判死，见 14.25 一·2）。
  复点工具是 `scripts/dsh-envclaim-probe33.sh`（走 `tools/run-probe.sh`）；**判网络那几条另按铁律 5**：先 `doh-hosts.sh --check`，
  形状按铁律 4 分超时与快速失败，`github.com` 不通而 `codeload.github.com` 通这种一半通的形状先想解析病，别顺着它那句"网络不通"往下写。
- **别人的对比报告要"反着读"**：`docs/` 那两篇 REA 报告（DSHA vs woaiys3、官方壳 vs 社区壳）做法清单很长（第一篇 §6 就 66 条、条条带 `文件:行`），
   顺着一通通勾会勾出一堆重复实现。正确的读法是**拿每条判据回我们自己的文件里找证据**：14.26 那轮的结果是
   **20 条我们早就做了**（哨兵 / 代次 / 句柄防重 spawn / 43 位整行判据 / 常数时间比较 / 回调里才 loadUrl / WebView 三开关 …），
   **真缺口 5 条**（prompt 通道无来源校验、503 后不自动重试、无崩溃处理器、pidfile 无出生身份、机上无常驻资产清单），
   另有整族**不适用**（proot 的 W^X / `--link2symlink` / bionic 那四类原生模块补丁 —— 我们是真 Ubuntu chroot，这些债我们本来就没有）。
   两篇都在结尾自述**没构建、没安装、没运行任何 APK、没连手机、PASS 数没复现** ⇒ 里面的 288 MB / 162 MB / "冷启动更快"全是项目自述或推断，**不许当我们这边的读数**。

- **桌面图标不刷新 ≠ 没装进去**（14.28）：启动器按 **包名 + versionCode** 缓存位图，同 `versionCode` 的 `pm install -r` 不会换位图。
  最便宜的一条是**他自己把桌面图标删了重放一次**；抬 `versionCode` 重打要付的代价是那发 APK 的 sha 作废（铁律：APK 不是逐字节可复现）⇒ **别为一张图重打**。
- **dshmarket 的目录源怎么长的**（读的是电脑上那发 `dshmarket 1.66.45`，行号在 `lib/regions.js`）：
  区**只在没定过时探一次并落盘**（`state.json` 里那个 `region`），此后**永不重探**；`catalogSourcesFor()`（`:136-144`）会在每张表末尾
  **追加一条"本区 registry 上的目录包 `dsh-plugin-catalog`"**；`routesFor()`（`:233-236`）用 `DSHM_NPM_MIRROR` 覆盖 `npmRegistry` ——
  所以**不改 `region`、不动他的 UI**，只加一行 env 就能把 global 区那条死掉的 `registry.npmjs.org` 备用源换成 npmmirror。
  两个区的成本差在那儿：global 第一源 `https://awesome-dsh-plugin.com/plugins.json` 是 **GitHub Pages 上无缓存的 4 MB，每次重取**；
  china 第一源是 npm 包（**2.58 MB，且用包版本当缓存校验**），但 china 那套还会把 GitHub 的 raw/git 改走 `gh-proxy`。
  **"钉了 awesome 通"不能外推到 `raw.githubusercontent.com`** —— `plugins.json` 是构建产物、从不提交进仓，那条 raw 路径按源码注释是 guaranteed 404。
- **入口 `:3081` 对不带门禁口令的请求一律回 `404 Not Found`**（`dsh-entry.js:484-485`，设计如此，故意不像"没这个路由"）。
  ⇒ 判"插件路由挂没挂"要**直接打引擎 `:3080`**：`401 got=156B` = 挂着且要登录，`404` = 真没挂上。别拿 `:3081` 的 404 说"插件没加载"。

- **工作区仓 `D:\mycode` 从来没有配过 remote**（2026-10-21 读数：`git remote -v` 回空，227 发提交全在本地）。
  ⇒ 别以为"提交"就等于"上传"；要上 GitHub 得走本目录这个嵌套仓。他账号 `zhl110` 下的库是**一项目一库**
  （`agent-hub`/`litellm`/`speaknow` 私密，其余公开），`gh` 用 fine-grained PAT、`agent-hub` 的 remote 走 **SSH** ——
  两条认证路径不是一个东西，别拿一条的成功推另一条的可行。
  **→ 本轮（10-21 晚）当场量掉了这半**：那把 fine-grained PAT **能建库**（`gh repo create dsh-mobile --private --source . --remote origin` 退出码 0，
  建出来 `private=true`），所以"新建私密库"不用他先去网页上手动建。`agent-hub` 那条 SSH 与 `litellm`/`speaknow` 仍各管各的，本轮没碰。
- **新建的仓没有 git 身份**：`user.name`/`user.email` 是**父仓 repo-local** 配的（`再来一杯海星酒 <1828980455@qq.com>`），全局没有 ⇒ 新仓里第一次 `git commit` 报
  **`Author identity unknown`**（错误行还会把中文用户名打成乱码，别以为那是编码坏了）。
  解法**不是**去 `git config`（他的规矩：不改 git 配置），是**单发传参**：
  `git -c user.name="$(git -C /d/mycode config user.name)" -c user.email="$(git -C /d/mycode config user.email)" commit …`
  ⇒ 提交出的 author/committer 与他原有那几发一致，仓里也不多出我没经同意写下的配置。
- **父仓与工作仓双轨跟踪同一批文件**（`agent-hub` 早就是这个形状）：`D:\mycode` 里那些 `dsh-mobile/…` 条目**不会**因为
  本目录有了 `.git` 就消失，`git add dsh-mobile/AGENTS.md` 在父仓里照样能更新 blob。所以**每轮两边各提交一次**，
  父仓那次的 pathspec 必须带 `dsh-mobile/` 前缀（铁律 9）。

## 不在这里写的东西

当前状态、待办、遗留问题**不要**往本文件加 —— 它们在 PROGRESS 里，只有一处真源。
本文件只在出现**新的、可复现的**踩坑时加一条，并带上"读数在哪"。
