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
   **→ 10-21 深夜起再加一句**：现场可能被**手机侧那个 dsh 自己**动过（改 cordis / 换代 / 装包），"上次还在跑"之外还要撞**cordis 字节数、`dpkg -l` 数、引擎代际**三个数 —— 见铁律 18。
2. 读 [PROGRESS.md](PROGRESS.md) 顶部「接班先读这一段」→ `## 下一步` → `## 遗留问题`。
3. 要证据/要改口经过，再翻 RUNBOOK 的 14.x（14.21 = 语音模型那轮，14.22 = 网络那轮，**14.32/14.33 = 围堵与"手机侧自己动盘"那两轮**）。
4. 设备侧动手一律先写只读探针，走 `tools/run-probe.sh`；**不要**手搓 `adb shell "su -c …"`。

## 目录职责

```
dsh-mobile/
├─ PROGRESS.md / RUNBOOK.md                 **现役两份**：进度与做法，冷启动只读这两份就够
├─ PROGRESS-archived.md / RUNBOOK-archived.md  搬出去的封闭历史（原文一字未改），要翻旧账才来
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

**文档是「现役两份 + 归档两份」（2026-10-21 晚他一句"progress 还有 runbook 这些文件太长了…你要不要先给它整理一下"）**：
搬的是行不是话 —— `RUNBOOK.md` 原第 49–2039 行整段进 `RUNBOOK-archived.md`，`PROGRESS.md` 原第 463–799 行（状态 12/13 到状态 25）整段进 `PROGRESS-archived.md`，
**没有删、没有改写、没有用小节代替原文**（铁律 10）。四条规矩：
① **新格子只写现役件**（RUNBOOK 从 14.24 起、PROGRESS 从状态 26 起）；
② 要改归档里的旧读数 → **去归档件就地加箭头**，别在现役件重抄一遍（抄了就成两份事实，下一个人不知道信谁）；
③ 引用"RUNBOOK 14.15"这类落点**照旧写** —— `RUNBOOK.md` 顶部那张索引表会把小节号指到归档件，`grep -n "^### 14.15" RUNBOOK-archived.md` 一步到行；
④ **冷启动的顺序**：`PROGRESS.md` 顶部接班段 → `RUNBOOK.md` 第 0 节 → `## 下一步` / `## 遗留问题`；这四步读完就能答"手机上现在什么状态 / 最新一格 / 下一步 / 有哪些坑"，读不到归档不算失败。
搬完的字节对账写在 `RUNBOOK.md` 那张索引表下面（那一行是读数，不是估的）。
**→ 10-21 深夜补一句（状态 33 之后）**：拆完那两份**还是很大**（现役 `RUNBOOK.md` 134,265 B / 1,015 行、`PROGRESS.md` 162,985 B / 1,141 行，
因为每轮都在长）⇒ **别整读**，按上面四步的区间读（第 0 节 = `RUNBOOK.md` 第 6–71 行，到"## 归档"那行之前；最新一格 = `grep -n "状态 33" PROGRESS.md` 往下到 `## 下一步`）；
真要瘦身就再搬一轮，但**搬的口径必须是"现役件里只留最近 5 格"**，且先跟他对一句"你要留多近的史"再动 —— 这是他来定的取舍，不是我该自决的。

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
   **git 默认会把 CJK 路径包上引号**（`core.quotePath` 没关）⇒ `"dsh-mobile/手机端情况.md"` 这种行**以引号开头**，
   任何 `grep '^dsh-mobile/'` 前缀过滤都会把它漏掉、`grep -vc` 会把它当成"范围外的东西"虚报一次越界。
   要按路径过滤就加 `-z`（NUL 分隔、不转义不引号）或 `-c core.quotePath=false`。10-21 那发父仓提交后我先被"1 条不是 dsh-mobile"吓了一跳，用 `-z` 复点才是 **0**。
   **取 DoH 的 A 记录不许用贪婪 `sed`**（10-21 深夜 p56/p57 连错两发）：`sed 's/.*"data":"\([0-9.]*\)".*/\1/p'` 里那个 `.*` 会一路吃到**最后一个** `"data":"`，
   打出来的是**末位**答案；CDN 每次轮转顺序，于是把"钉的就是首选"读成"漂了"。⇒ 认解析层只认 `doh-hosts.sh --check`（node 精确取 `Answer[0]`），别在探针里自造取数管道。
   **在 `/etc/hosts` 里查一个域名要用字段相等**（同一晚同一种错犯在两份脚本上）：`awk '$0 ~ d'` 问 `github.com` 会先匹配到 `codeload.github.com` 那行、拿回隔壁那个 IP，
   于是打出"钉 .165 / DoH .166 ⇒ 漂了"这种自己跟自己对账的假条。要 `awk -v d=$H '$2==d{print $1}'`。
   **删掉自己正站着的目录 = 后面每一条都白跑**（p62 第一次整发作废）：`cd /tmp/x && … && rm -rf /tmp/x` 之后 cwd 是个空洞，
   此后每条 `git` 都回 `fatal: Unable to read current working directory`、`rc=128`、`refs=0` —— **看着像"五个远端全拉不到"，其实一个字节都没发出去**。
   ⇒ 删目录后面紧跟一句 `cd /`；凡是"整批发红"的读数，先怀疑自己的 cwd / 环境，再下网络结论。
   **`GIT_ASKPASS=/bin/false` 不是"关掉认证"，是"把失败改成怪样子"**：真遇到私有库它回 `unable to read askpass response from '/bin/false'`，
   与"仓库不存在"两种成因同为 `rc=128` ⇒ 判远端只认 **refs 计数 > 0**，不认 rc。
   **探针会把自己算进"残留计数"**（p64/p65/p66 连报的"`/root/*.sh` = 3"其实是 **2 份常驻 + 当发探针**）：
   `run-probe.sh` 跑完把机上两份副本都删，所以**脚本内任何时刻**的计数必然含它自己 ⇒ 报"还剩 N 个"要当场写明"含本探针"，
   否则下一轮会把 3 读成"有 3 个残留"（14.31 那句"仍 9 份"就是这么虚高的，真值 8）。
   **不许写没读过的数 —— 这是第四类错，与上面那三条计数器坑不同源**（14.32：我在 `RUNBOOK.md` §0 写壳 0.7 的 sha256 `c9edd7ee…`，
   那个字符串**我从未在任何地方读到过**，盘上真值是 `be025bb3…`，而且是本机件与机上 `base.apk` **逐字节撞上**的那个）。
   前三类是"取数管道挑错行"，这一类是"**根本没取就写**" ⇒ 落笔时凡是 sha / 字节数 / pid / 版本号，要么当场 `sha256sum`、要么引用某份 `downloads/pNN.txt` 的第几节，
   否则就写"未取"。**APK 尤其危险**：同源码重打 sha 会变（见"已知坑"那条），凭记忆抄 sha 迟早对错发。
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
    **往列表里"追加一条"不等于用 Edit 替换邻居**（11-03 第 2 次犯，读数在 RUNBOOK 14.39 八）：`old_string` 只写**锚点那一行**，
    把上一条的正文一起圈进去再"换成新条目"会**静默删掉它**（上次删了 `grep -F` 那条，这次删了剪贴板那条）。
    抓法两步：`git diff --stat` 看删除行数对不对，再 `grep -c` 复点那条还在不在（**0 就是删了**）。
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
14. **profile 配置放错 `id` 会被静默丢掉，而 `--dump-config` 不重启就能判死**（14.32，探针 67/68）：
    `/root/.dsh/profiles/web/cordis.patch.yml` 是顶层 YAML 数组 `- {id, name, config}`；`- id: sandbox` = `@deepseek-ai/dsh-sandbox-local`（吃 `runnerCommand`/`runnerFailureSignatures`），
    `- id: sandbox-policy` = `@deepseek-ai/dsh-sandbox-policy`（**只吃 `mode`/`workspaceRoot`**）。**两个包的 zod Config 都没有 `.strict()`**（`strict(` 命中 0）
    ⇒ 键塞在错的 id 底下**不报错、不告警、直接丢**，于是"接了线其实没接"。所以**任何配置类改动，先 `dsh --profile web --dump-config` 在组合树里数命中**
    （它打印完就退出、**不 mount、不起服务** ⇒ 不用重启、不用他在场）；命中 0 就别去重启引擎。
    本仓 `RUNBOOK-archived.md:878`（14.11）那段示例就写错在 `sandbox-policy` 底下，**照抄它等于白接**，已就地加箭头。
    （`--dump-config-schema` 在 0.2.1-rc.2 这版回 **rc=1**，用不了，别拿它当判据。）
15. **声称"有围堵 / 被拦住了 / 会弹窗"之前，先查这棵树上有没有 `[dsh-purge]`**（14.32 是本轮最大的一条）：
    这台机的 web profile 装着 purge，它把上游 **42 个文件**换成了直通实现 —— `dsh-sandbox-local` 的 `confine()` **永不包装 argv**（还回 `enforcement:"full"`，
    光看这个字段会误判成"全围住了"）、`dsh-fs-sandbox` 的 `checkedTarget()` 不做越界检查、`dsh-user-approval` **在任何弹窗之前先回 `"allowed-once"`**。
    ⇒ **判据顺序**：`ls /*.dshpurge.bak* | wc -l` + `grep -rl '\[dsh-purge\]' <包根> | wc -l`（两条口径，备份件 ≠ 真被改的文件）→ 再读那个函数**现在的正文**，
    而不是读上游文档或它自己的注释。**别拿"服务 env 里有 `DSH_PERMISSION_MODE=workspace-write`"当"命令会被拒"的证据** —— 那要 `confine()` 真会去选 runner 才成立。
    purge 是他装的（点「应用」），**我不自己撤**；要撤先跟他说清代价（撤了就回到"Bash 全灭、原生 read/glob/edit 能用"那个旧形状）。
16. **探针脚本先本地 `bash -n` 再过 `tools/run-probe.sh`**（14.32 我在这条上连摔三次，全是同一形状）：
    把 `awk 'NR==2{print $4" … "$2}'` 或带单引号的串**嵌在 `$(…)` 里再塞进 `"…"`**，`bash` 会把 `;`/引号解析成别的东西 —— 症状是 `syntax error near unexpected token`，
    而且**是发上机之后才报**，白花一轮 adb。写法：**先把要算的东西赋给变量，再 `echo "$VAR"`**，别在 echo 里现套现。
    本地一步就挡住：`bash -n scripts/dsh-xxx.sh`。
17. **purge 在位时同一份代码盘上有两份，判行为只读真在加载的那一份，并写明读的哪份**（14.33，手机侧那个 dsh 就是栽在这儿）：
    真加载的是 `/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-sandbox-local/lib/index.js`（22,231 B、md5 `b976570f…`＝仓库 `downloads/sbx-dev-index.js`），
    purge 动手前的原件在 `/root/.dsh/dsh-purge/host-backups/9dac90ce22cf7f551f319a5e.bak`（**同目录同文件名，内容是不带 `[dsh-purge]` 标记的那版**）。
    它读 `.bak` 里的 `:311` 那条分支，就得出"填了 `runnerCommand` 就会包装 argv"——而真那份是直通的，接线是**死配置**。
    ⇒ 判法两步：① `md5sum` 那个在加载的路径，与仓库孪生件撞（撞上了函数体可在本地读，不用上机 `sed`）；② 要证行为就**直接调那一次**（`node -e` 按它写的 cfg 调 `confine()`，看 `ARGV_HAS_RUNNER`），
    别信"文件里有那个分支"。引用出处时写全 `lib/index.js` 还是 `*.bak`。
18. **手机那台 dsh 现在是第二个写手**（14.33 起）：它会自己改 cordis、自己 `kill -TERM` 换代、自己 `apt-get install`。
    ⇒ 每轮接班"现场没变"这句要撞三个数才说得出：**cordis 508 B（我撤干净）/ 1,627 B（它接回的死配置）**、**dpkg 411 / 415**、**引擎代际与 pid**（现在是第 6 代 28833）。
    并且：**它写的东西我不来回改**（撤/留等他一句，两个写手改同一个文件＝打转）；它的会话记录是取证入口 —— `session.v4.jsonl.zstd` 用机上 Node 的 `zlib.zstdDecompressSync` 解，
    `tool/call` 的命令串在 **`data.arguments` 这个 JSON *字符串*里**（不是对象，见"已知坑"）。

19. **这台机"直跑、不弹窗、root 权限"就是他要的效果 —— 别把没围栏当事故报给他**（10-21 深夜他两句：「不撤，插件你先不用管」＋「那是我让他装的，没关系，我要的就是这种效果」）：
    purge 把沙箱包装 / 文件围栏 / 审批弹窗三层一起短路，**这是他要的交付形态**，不是待修的缺陷。⇒ 汇报时**只陈述读数**（"命令真执行、没被拒、没弹窗"），不要再来一轮"风险提示 + 要不要补围栏"；
    也不许顺手去接围栏、撤 purge、改档位（改这些是他点头才动）。**归因要小心**：手机侧那次 `apt-get install ripgrep jq` 是**他授意**的，我第一版写成"它自己就装了、不会问他"⇒ 那是替他担心错了对象。
    **他实测"能用/能装"就是结案证据，别拿自己复点到的一发失败去翻案**（10-23 00:2x 形状：我在日志里撞到一发 `装插件 → 500`、把它列进"没闭环的账"，他一句"能装，我已经测试过了，装了几个插件了，能用，没问题"）⇒ 判据次序是**真实使用 > 日志里一发红**；留痕照写进 RUNBOOK，但**不再追、不再当缺陷报**（与他划走的子问题同族，与上一条"别把没围栏当事故报"同一族）。
    唯一还可以提的是**具体后果**（不是意见）：它现在能碰整个 `/phone`（顶层 117 项）与经 `/proc/1/root` 摸宿主，包括他 `/data/local/tmp` 那批刷机件；要收窄就把工作区挪进单独子目录（#41），**这条他自己决定，我不催**。

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
| 命令行问 dsh 一句 | `--run 'bash /root/dsh-ask.sh'`（问题写进 `/tmp/dsh-task`，不走 argv）**→ 10-21 晚 22:1x 起机上没这份了**（他让清残留，探针 64 删的 6 份里就有它，仓库孪生件 `scripts/dsh-ask.sh` 732 B 在）⇒ 现在要先 `bash tools/run-probe.sh scripts/dsh-ask.sh downloads/x.txt` 推上去再跑 |
| 量"某批 apt 包要下多少 / 占多少盘"（一个不装） | `bash tools/run-probe.sh scripts/dsh-size-probe66.sh downloads/p66.txt`（两口径 + 每批最大 10 件 + recommends 差集；并集在 `…precheck-probe67.sh` 第 ① 节。**别拿 `apt-get -s` 找那两行**，它不打，见"已知坑"） |
| 沙箱 runner 接线：接 → 验组合 → 重启 → 端到端 → 撤 | `scripts/dsh-wire-precheck-probe67.sh`（只读，先量接线位）→ `scripts/dsh-wire-probe68.sh`（写 cordis + `--dump-config` 判命中，**不重启**）→ `scripts/dsh-wire-restart-probe69.sh`（**SIGTERM 引擎**，含端到端 `confine()` 自测）→ `scripts/dsh-purge-trace-probe70.sh`（只读：purge 足迹 + 三个数的健康复点 + 逐字节还原）。读数为 `downloads/p67…p70.txt`，形状与"为什么现在是死配置"见 `config/cordis-sandbox-wiring.snippet.yml` 与铁律 14/15 |
| **对账手机侧那个 dsh 自己写了什么**（状态 35 那一轮的五发，纯只读） | `scripts/dsh-agent-write-audit-probe71.sh` → `downloads/p71.txt`（cordis 现状/两份备份/`--dump-config`/手工调 runner/我的三层 md5。⚠ 它 ② ⑥ 两节路径写错 ⇒ 空读数，**空读数不能读成结论**）；`scripts/dsh-confine-recheck-probe72.sh` → `p72.txt`（**修正版**：模块真实路径、`confine()` 直调、围内/围外 `/proc/1/root` 对照、dpkg、hosts 对账、会话清单）；`73`/`74`/`75` → 同一份会话记录三次提取（73 抓错字段、74 抓到工具名但命令为空、**75 才把 44 条命令串全提出来**） |
| 在机上读一份会话记录（`session.v4.jsonl.zstd`） | 见 `scripts/dsh-session-calls-probe75.sh` 第 ① 节那段的形状：`zlib.zstdDecompressSync` 解帧 → 按行 JSON → 取 `type==="tool/call"` → **`JSON.parse(data.arguments)` 才是命令**（`data.arguments` 本身是字符串）。FRAMES/LINES/DECOMP_FAILS 三个数要互相对得上 |
| 重打 APK | `bash app/build.sh`（版本号在 `AndroidManifest.xml` 与 `build.sh` 两处） |
| **打 rootfs 产物并挂 Release**（GB 级，不入库） | 一条命令到底：`bash tools/make-payload.sh --publish`（本机自测 → 设备普查 → **机上 `tar -czf` 落文件** → `adb pull` → **机上/PC 三方复点** → 两道闸门 → 指纹/元数据 → 超档切卷 → `gh release create payload-<UTC>` → **读回资产**判成没成）。闸门自测**不需要手机**：`bash scripts/dsh-payload-pack.sh --selftest`（11-03 本机 合计 5 条 PASS 5）。不发布就去掉 `--publish`，只看不出包加 `--dry`。剥除清单的**单一真源是 `scripts/dsh-payload-pack.sh`** 的 `DROP`/`DSH_KEEP`。**现役那一发的 tag 写在 `payload-meta.txt` 与 Release 上**，体积/sha256/条目数**本文件不抄第二份**（抄了就会有两边对不上的一天）。产物落 `release-assets/`（已 gitignore）。**`/etc/shadow` 原件永不进包**，包里是 root 栏 `!` 的生成替代件，靠装机脚本 3b 放回 |
| **在别人机上装成即装即用** | `bash tools/install-from-scratch.sh`（取包→撞 sha→设备上以 root 解压→3b 放回 `/etc/shadow`→推四件→起入口→烤口令→装 APK）。**从未实机跑过**（现役那台机别跑，见脚本头部警告；真验证要第二台机）。给别人看的说明在 `README.md` 与 `docs/INSTALL-from-scratch.md` |
| **提交之前的隐私闸门**（库已 PUBLIC ⇒ 这步不是可选） | `bash tools/check-private.sh`（扫跟踪区）；`--staged` 扫暂存区、`--selftest` 自证（11-03 本机 `合计 7 条：PASS 7 / FAIL 0`）。真值名单在**不入库**的 `tools/private-values.txt`（已 gitignore），脚本只报形状名与处数、不打印命中内容 |
| 重跑入口自测（**不需要手机**，Windows 侧就能跑） | `node scripts/dsh-entry.js --selftest`（2026-10-21 当场：`合计 58 条：PASS 58 / FAIL 0`；铁律 12） |
| 换图标（切五档） | 先把满幅方图存成 `app/icon/icon-src.png`，再 `sh app/icon.sh`，最后重打 APK |
| 电脑侧取模型 / 推模型 | `bash tools/fetch-sensevoice.sh` / `bash tools/push-sensevoice.sh` |
| 电脑上官方 DSH 的 CLI（不在 PATH） | `powershell -NoProfile -Command "cd 'D:\program files\DeepSeek\resources\runtime\cli\bin'; .\dsh.cmd plugin --profile desktop list"` |
| 量手机侧现状（profile / pnpm / registry 出口，纯只读） | `bash tools/run-probe.sh scripts/dsh-plugins-probe32.sh downloads/p32.txt` |
| 复点"这台机什么干不了"这类断言（含模型自己的自述） | `bash tools/run-probe.sh scripts/dsh-envclaim-probe33.sh downloads/p33.txt` |
| **交付之后一整轮复点**（两层进程 / dpkg 数 / 命令逐个版本 / hosts 对账 / 兼容层 md5 / 出口内联计数） | `bash tools/run-probe.sh scripts/dsh-final-check56.sh downloads/p56.txt`（纯只读，读数形状就是本文件铁律 2 那套） |
| 判"某条域名到底坏没坏"（别拿 IP 撞不撞当判据） | `bash tools/run-probe.sh scripts/dsh-hosts-drift-probe57.sh downloads/p57.txt` → 精确对账再补一发 `scripts/dsh-drift-recheck58.sh`（58 第 5 节那段 node 是唯一可信的"漂没漂"口径） |
| 判 GitHub / gitee / 镜像这几跳今晚通不通 | `bash tools/run-probe.sh scripts/dsh-github-route-probe59.sh downloads/p59.txt`，替代路与落字节见 `…probe60.sh` / `…probe62.sh`（**git 能不能干活只认 `clone` 真落多少 KB**） |
| 清我自己留在 chroot `/tmp` 的东西（白名单，逐个打印再删） | `bash tools/run-probe.sh scripts/dsh-tmp-hygiene61.sh downloads/p61.txt` |
| 装之前置体检（本地清单 + 设备数 + chroot 有没有 pnpm） | `bash tools/install-phone-plugins.sh --check` |
| 把 tarball 装进手机 `web` profile | `bash tools/install-phone-plugins.sh`（三计数：清单 / 推上去 / sha256 撞上，不等就停） |
| 装 APK 但**不重打** | `bash tools/install-apk.sh`（只推现成那发；`--verify` 只比指纹、一个字节不写。**别用 `app/build.sh --install`**：它前六步无条件重打，sha 必变 ⇒ 报过的指纹作废） |
| 收尾量流量 / 我留了什么 / 引擎现场 | `bash tools/run-probe.sh scripts/dsh-traffic-and-cleanup-probe39.sh downloads/p40.txt`（`/proc/net/dev` 两拍差值、`lo` 上的连接数、两个 node 的出生与年龄、机上 `.sh` 残留分类） |
| **开工复点时顺手取一次 `/proc/net/dev` 全表** | 10-21 傍晚这轮就没取，"整轮走了多少网"当场答不出增量，只能退回"我点得出的字节"（14.27 八）。基线只有开工那一刻有。→ **同日再补**：别存进 PC 的 `/tmp`（那是**另一个** `/tmp`，探针在手机上查不到，见铁律 1），**直接 `> downloads/net-full-<北京时间>.txt`**，下一发的差集在 PC 上拿这两份文本算（`名字 rx tx` 三列；口径见铁律 2 的 `lo` 那条）。第一份在 `downloads/net-full-20261021-185612.txt` |
| 推到 GitHub 私密库 | 先 `git rev-parse --show-toplevel` 确认人在 `D:/mycode/dsh-mobile`，再 `git add -- .` / `git commit -m … -- .` / `git push origin main`（`origin` = `zhl110/dsh-mobile`，**私密**）。推完复点：`git rev-list --count HEAD` 与 `git rev-list --count origin/main` 要相等，`gh repo view --json visibility` 要回 `PRIVATE` **→ 11-03 状态 42 两处改口（旧话不删）**：① 库已 **PUBLIC**（他一句"把仓库改成公开"），复点要回的是 `PUBLIC`；② `git push origin main` 这条**在这台机上走不通**（HTTPS 撞 `CRYPT_E_NO_REVOCATION_CHECK`），实际用的是**一次性 SSH URL** `git push git@github.com:zhl110/dsh-mobile.git main`（不动 `remote.origin.url`），更新计数用 `git fetch <同一 URL> main:refs/remotes/origin/main` |

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
  → **2026-10-21 晚两条"未验/还没读到"都被读数结掉了（就地加箭头，旧话不删）**：① purge 在手机上**真改得动** —— 改的就是 npm 全局那棵树本身
  （`/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/**`，**42 个文件带 `[dsh-purge]` 标记 + 56 份 `.dshpurge.bak`**，mtime 2026-10-21 10:35:16–17Z），
  生效内容见铁律 15（`confine()` 直通、`checkedTarget()` 不检查、审批先回 `allowed-once`）；**别再按桌面那套"解包目录优先加载"去手机上找 `resources\app`**，这边没有对应物；
  ② **机上有 pnpm 12.14.0**（14.27 量的），装插件不用往他机上补包。
- **PowerShell 用 `-Command "…"`（双引号）时，bash 会把 `$_` / `$LASTEXITCODE` 吃掉**：前者被换成上一条命令的最后一个参数
  （报 `/d/mycode/dsh-mobile.ProcessName 无法识别为 cmdlet`），后者变空（报`必须在"+"运算符后面提供一个值表达式`）。
  写 `\$` 转义，或者干脆用通配避开它们。
- **"这台机做不到 X"这类断言要分成四种形状再下结论**，别一来就认（也别看模型自述像样就当事实）：
  ① **真做不到**（内核没编 `USER_NS`/Landlock、没有 X 服务）；② **没挂进来**（chroot 只 rbind `proc sys dev` + `/phone`，
  所以它报"`/system/bin` 整个不存在、一点 Android 接口都没有"——那是**我们的挂载选择**，不是限制，见 14.25 一·3）；
  ③ **建好了但没接线**（`dsh-unshare-run` 34 PASS 在位，profile 里没 `runnerCommand` ⇒ 它只能报"沙盒不可用、只能完全访问"，见 14.25 一·1）；
  ④ **在它视角外**（自启服务在宿主侧、常驻入口在 chroot 外，它按"PID 1 不是 systemd / 进程挂了没人拉"就判死，见 14.25 一·2）。
  **→ 14.32 又出现第五种形状，比这四种都隐蔽**：⑤ **接线位接好了、上游函数却被插件换成了直通** ——
  `runnerCommand` 已挂到 `- id: sandbox` 底下、`--dump-config` 命中 1、引擎也换成了吃到新配置的那代，**但 `confine()` 被 purge 换成"永不包装 argv"**
  ⇒ 前面四条形状至少还能从配置/env 里推出来，这一种**任何配置读数都是绿的**，只有把上游函数**现在的正文**拉下来看才暴露（判法见铁律 15）。
  顺带把 ③ 那句改口：**"只差接线"已经不成立了**，接线做过、撤过、撤法逐字节复点过（`config/cordis-sandbox-wiring.snippet.yml` 是待用的那两行）。
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
  → **14.32 把这条补全成三个数，省得再当成故障**：`:3080` **裸打 = 401 / 68 B**（引擎活着、要券）；`:3081/` **不带口令 = 404 / 10 B**（按设计）；
  `:3081/` **带口令 = 200 / 53,687 B**（这才是 App 点开那一发，注入层属性在里面复点得到）。口令从 stdin 递（`curl -K -`，铁律 8）。
  p69 那发我就是因为只打了前两种，打出"看着像坏了"的两个读数，白花一发 p70 才问干净。
- **`apt-get -s`（simulate）**从来**不打** `Need to get …` 与 `After this operation …` 那两行（apt 2.8.3/arm64 实测：rc=0、428 行、只有 `106:0 upgraded, 161 newly installed`）。
  ⇒ 要"下多少 / 占多少盘"只能自己算：下载量 = `apt-get install --print-uris -qq` 每行**第 3 字段**（字节，URI 带单引号但文件名不带，别按空格切）；
  占盘 = `apt-cache show <pkg>` 的 **`Installed-Size`**（单位 **KiB**，且**一个候选版本一条记录**，要去重）。
  还有一条口径陷阱：**多批的包数不能相加当总量**（四批各量 348 / 182，真并集是 **281 / 159** —— `systemd`、`libpython3.12t64` 这类被几批同时拖进来）。
- **`dsh` 没有"一次性跑一句"的 CLI 入口**（`--help` 只有 `--profile / --patch / --dump-config / --dump-default-config / --from-default-profile` 这类，**没有** `--command`/`--exec`）。
  ⇒ 想端到端验上游函数（如 `confine()`）只有两条路：起真服务走 App，或者 `node --input-type=module -e "import(…)"` 自己 import 那个 `lib/index.js`
  （14.32 用的是后者，探针 69 第 ③ 节；构造要真 ctx 时可以先不构造，直接拿 `prototype.<方法>.call(手搭的 this)` 只验那一个方法）。
- **WebView 里键盘高度只能从原生拿，`adjustResize` 在沉浸式全屏下是废的**（壳 0.7，14.32 一）：`goFullscreen` 那句
  `hide(systemBars()) + BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE` 让窗口不再为输入法让高度 ⇒ 键盘**盖**在 WebView 上，页面 `innerHeight` 一字不改（实测 360 不动）。
  做法是 `root.setOnApplyWindowInsetsListener` 把 `in.getInsets(WindowInsets.Type.ime()).bottom` 压成 root 的下内边距（**只挂 API 30+**，`Type.ime()` 是 30 才有的）。
  **量键盘只认真触摸**：`scripts/dsh-cdp.js --tapsel` 点输入框中心，然后 `dumpsys input_method | grep mInputShown` 确认 `true`；
  用 `focus()` 唤出来的键盘**根本不出来**（`mInputShown=false`），那次的"页面没动"是**前提没成立**不是结论（我 14.32 第一版就栽在这，`downloads/kbd-212522/`）。

- **工作区仓 `D:\mycode` 从来没有配过 remote**（2026-10-21 读数：`git remote -v` 回空，227 发提交全在本地）。
  ⇒ 别以为"提交"就等于"上传"；要上 GitHub 得走本目录这个嵌套仓。他账号 `zhl110` 下的库是**一项目一库**
  （`agent-hub`/`litellm`/`speaknow` 私密，其余公开），`gh` 用 fine-grained PAT、`agent-hub` 的 remote 走 **SSH** ——
  两条认证路径不是一个东西，别拿一条的成功推另一条的可行。
  **→ 本轮（10-21 晚）当场量掉了这半**：那把 fine-grained PAT **能建库**（`gh repo create dsh-mobile --private --source . --remote origin` 退出码 0，
  建出来 `private=true`），所以"新建私密库"不用他先去网页上手动建。`agent-hub` 那条 SSH 与 `litellm`/`speaknow` 仍各管各的，本轮没碰。
- **新建的仓没有 git 身份**：`user.name`/`user.email` 是**父仓 repo-local** 配的（`再来一杯海星酒 〈提交邮箱·已遮〉`），全局没有 ⇒ 新仓里第一次 `git commit` 报
  **`Author identity unknown`**（错误行还会把中文用户名打成乱码，别以为那是编码坏了）。
  解法**不是**去 `git config`（他的规矩：不改 git 配置），是**单发传参**：
  `git -c user.name="$(git -C /d/mycode config user.name)" -c user.email="$(git -C /d/mycode config user.email)" commit …`
  ⇒ 提交出的 author/committer 与他原有那几发一致，仓里也不多出我没经同意写下的配置。
- **父仓与工作仓双轨跟踪同一批文件**（`agent-hub` 早就是这个形状）：`D:\mycode` 里那些 `dsh-mobile/…` 条目**不会**因为
  本目录有了 `.git` 就消失，`git add dsh-mobile/AGENTS.md` 在父仓里照样能更新 blob。所以**每轮两边各提交一次**，
  父仓那次的 pathspec 必须带 `dsh-mobile/` 前缀（铁律 9）。
- **往文档或提交正文里写"提交号 / 还差几发"之前，先当场 `git log` 与 `git rev-list --count origin/main..HEAD` 复点**（10-21 深夜连犯两次）：
  ① 把上一发的改动内容凭印象安到了本发头上（真号是 `6338ab9` 的改动我写进了 `c02e4ab` 的正文）；② 把工作仓上一条的号写成"641…"这种**没查就编的前缀**（真号 `a1bf414`）。
  另外"现在差 N 发没推"这类数**会自愈**：写这句话的那一发本身就让计数 +1 ⇒ 文档里只写"23:19 当场量到 N"，不写恒等值。两处都**不 amend、不改历史**，只在下一条里更正并留痕。
- **`findmnt --target` 在这台 chroot 里判不了"只读"**（14.33 五，探针 72）：对 `/etc` 它回的是**底下那层 f2fs 的挂载选项**（看着像 rw 其实上层已冻），
  对 `/phone` 一次回**两行**（`/dev/block/dm-74[/media/0] /phone`）。要判"写不写得进"只有真写一发再删（本轮没做，所以 14.33 那条只写"没用它下结论"）。
- **会话记录里 `tool/call` 的 `data.arguments` 是一个 JSON *字符串*，不是对象**（14.33 二）：`jq '.data.arguments.command'` 回空、`node` 里 `obj.data.arguments.command` 也空，
  必须先 `JSON.parse(data.arguments)`。这是"无关内容挤进我要数的字段"那一族的**第五种形状**（前四种：抓 schema 的 `description`、抓 `tool/result`、字段名撞车、数组当对象）。
- **入口那条路只有一个位置**：部署件在 **`/usr/local/bin/dsh-entry.js`**（70,487 B、md5 `4af378c9…`＝仓库 `scripts/dsh-entry.js`），**不在 `/root/`**。
  探针 71 第 ⑥ 节按 `/root/dsh-entry.js` 查 ⇒ 回"不在"。同理 `dsh-sandbox-local` 在 **`dsh/node_modules/@deepseek-ai/…` 底下那层**，不在包根同级；
  **路径不存在造成的空读数不能读成"没有标记/没被改"**（71 因此有整节作废，72 才修好）。
- **嵌套目录分组计数要先看深度**（14.33，探针 72 第 ⑦ 节）：会话是 `sessions/<组>/<session-id>/session.v4.jsonl.zstd` **多一层**，
  我在组目录里 `ls */*.zstd` 数 ⇒ 三个组全回"会话数 0"，而同一发的逐文件列表读到了 21 份。**"逐分组计数"与"逐个文件列表"两个口径并存时以列表为准**。
- **purge 的 shim 在每次引擎启动都跑一遍**（14.33，探针 74 第 ② 节）：`/tmp/dsh-purge-desktop.log` 尾部是 `[boot] enabled=true surface=web …`→`[home] home=/root/.dsh`→`[guard.wrap] …`，
  当天 14:00 之后 201 行。判"purge 今天有没有被再应用一次"**别看这份日志的行数**，看**被改模块的 mtime**（仍 10:35:16）与 `.dshpurge.bak` 计数（仍 56）——两个都没动 ⇒ 没重应用。
- **WebView 壳"点了没反应"的第一嫌疑人是没接的 `WebChromeClient` 回调**（14.34）：`onShowFileChooser` 不实现 ⇒ 默认实现**直接 `return false`**，Chromium **静默丢掉**这一次文件选择 —— console 干净、网络 0 请求、屏幕上什么都没有，
  看着像前端坏了，实际是壳没接线。同一族：`onPermissionRequest` 默认全拒（0.6 之前的语音）、`onShowCustomView` 默认不放（HTML5 全屏，至今没接）。接了之后**三条出口都要结掉回调**（选中 / 取消 / `createIntent()` 抛错），
  漏一条那个 input 就永远停在"正在选"，下次连 `click` 都不发 ⇒ **自家把同一个症状原样再造一遍**。
  → **10-22 夜这族一次接完了（壳 0.10，14.35）**：`onShowCustomView`/`onHideCustomView` 实现了（真用户＝文档预览里那个 `<video>`，p86 量到），
  **`setDownloadListener` 也补上了**（0.9 及之前根本没设过 ⇒ 默认行为是"什么都不做"，真用户＝pdf 预览那颗"下载"按钮，p85 量到 `a.download = filename`）。
  这两格从"没实现"变成"接了并有实测读数"；`onGeolocationPermissionsShowPrompt` 仍没接 —— 但 p82 量到**全摊 184 个文件里 `navigator.geolocation` 0 命中**，那格按"没人用"挂着。
- **附件通道不看 `setAllowFileAccess(false)` / `setAllowContentAccess(false)` 的脸色**（14.34 实测）：`content://com.android.providers.downloads.documents/…` 92 B 在两个开关都关着时照样被 WebView 读回页面。
  ⇒ 别为了"修上传"去翻这两个开关（翻了只是把"页面能自己加载 content URL"这扇门打开）。要保 accept 列表（页面插件那条是 `.zip,.tgz,.tar.gz,.tar,.skill`）就**必须用 `params.createIntent()`**，手搓 GET_CONTENT 会把它丢了。
- **设备上的 shell 也会做 glob 展开**：`am start -a GET_CONTENT -t */*` 里那个 `*/*` 不加引号会被设备上（不是 git-bash）展开成文件名，`query-activities` 于是读出**假 0**；我因此差点判"这台机没有可用的选择器"。加引号重跑 = **20** 项。
  同一条链上还有第二个坑：**`grep -c` 没命中时退出码是 1**，用 `&&` 串起来会把后半条整条带走，也读成 0 ⇒ 这类对账用 `;` 串，别用 `&&`。
- **CDP `DOM.setFileInputFiles` 两条读数坑**（14.34，工具已做成 `scripts/dsh-cdp.js --setfile`）：① 它是**异步 IPC**，调用 resolve 时 FileList 还没落到 DOM；② 这页的 React 在 `change` 之后**把 `input.value` 清空** ⇒ 之后再 `querySelector` 读 `files.length` 必是 **0**，那是假证。
  正确写法：**在 `change` 回调里当场把 `[...el.files]` 抓进 `window`**，再读那份引用。同理，`--tapsel` 量到**负数 y**（那次 `y=−6725`）＝元素在滚动区外，触摸发出去了但落不到，**不能记成页面缺陷**。
- **DocumentsUI（这台 OOS 15）网格里"点缩略图"＝预览，不是选中**（14.34）：点 `preview_icon` 会弹"打开方式"resolver（MT管理器/WPS/文本编辑器那一屏），URI 永远回不到壳；
  要点**同一张卡片非缩略图那块**（`item_root` 去掉 `preview_icon` 的区域）才把 content:// 交回调用方。`uiautomator dump` 里两个节点的 bounds 挨着，光看 `text=` 会点错。
- **网页发起的下载要"真手势"才算数**（14.35）：`evaluateJavascript(userGesture:true)` 里造一个 `<a download>` 再 `a.click()` ⇒ `onDownloadStart` **一次都不进**（我第一轮就是这么自测的，读成"没反应"）；
  换成 CDP `Input.dispatchTouchEvent`（`scripts/dsh-cdp.js --tapsel`）就进。⇒ 测下载**只能用 --tapsel**，别用 --eval / `--click`。
- **WebView 的 `onDownloadStart` 把页面起的文件名丢了**（14.35 实测）：`contentDisposition` 交过来是 **空串**（桌面 Chrome 会带），`<a download="会话-22.md">` 那个名字**传不到壳** ⇒ 只能从 URL 尾巴猜（blob 就猜成一个 UUID）。
  补法：页面侧挂一个捕获阶段 click 监听，把 `a.download`（反射属性，赋值也看得见）用现成的 `prompt('dsh:dlname', 名字)` 通道记回来，6 秒内有效、只当文件名、过 `sanitizeName` 才落盘。
- **`blob:` 的 URL 里没有字节**（14.35）：字节只活在渲染进程内存上，DownloadManager（另一个进程）取它必失败 ⇒ blob 这条路只有页面自己 `fetch` 自己那个 blob → FileReader 转 base64 → 分段捞回 Java 侧落盘（壳里上限 8 MiB）。
  http(s) 那条相反：**必须把 WebView 的 cookie 抄成请求头**（`addRequestHeader("Cookie", …)`，注意 API 名不是 `addHeader`），否则下载进程请求本机 `:3081` 直接吃 401/404。
- **判"这套页面用不用某个网页 API"不能只扫前端 dist**（14.35，p79→p82 那次改口）：真页面是 **`dsh-web-frontend/dist` 64 个文件 + 57 个 `dsh-client-ui-*` 包**拼起来的（合计 184 个 js / 29.4 MB）。
  我只扫了 dist ⇒ 读出"`createObjectURL` 0 命中、`requestFullscreen` 0 命中"，并据此把下载与全屏判成"将来才用得上"——**错的**：pdf 预览在 `a.download = filename`、文档预览里有 `<video>`。
  ⇒ 这类"有没有真实用户"的判断，扫描面要先数清楚（`find … -path '*client-ui*' -name '*.js'`），或干脆看**壳的运行时日志有没有进过那一发**。
- **安全闸门不能用"词形"当判据，且它的扫描面必须与产物同源**（11-02 夜，`scripts/dsh-payload-pack.sh` 那两处）：我第一版闸门是"文件内容里出现 `password|secret|sk-|Bearer ` 就停"，
   在本机同型 profile 树上量到 `password` 43 个文件、`sk-` 26、`Bearer ` 13 —— **全是上游 js 的字段名与校验代码**，一条真凭证没有 ⇒ 这种闸门只会把交付永久卡死在假阳性上。
   猜"值形状"也不成（`sk-[0-9a-f]{32}` 在整棵 `~/.dsh` **0 命中**，`AKIA[0-9A-Z]{16}` 反倒在 PIL 与 pnpm 里误报）。**能当闸门的是"这台机上真在用的那批串"**：
   从会被剥掉的凭证源取真值（只进内存、绝不打印），回扫产物。另一条同族：**别拿 `find 活盘` 当扫描面** —— 那会把 ① 探针脚本自己（里面写着那些词）② 已经在剥除清单里的文件算成命中，
   而这两样根本不会进包；清单要出自与 `tar --exclude` 同一批条件的那份列表。
   附带一条：闸门这类"只跑一次看不出对不对"的逻辑，做成一个**不需要外设就能跑的 `--selftest`**（埋雷要抓到 / 撤雷要 0 且当场取到过串 / 源为空要明说"取不到"），
   否则手机上掉线这段时间里你连"闸门是不是坏的"都无法判断。
   **→ 11-03 真跑第一发，这条判据长出两半（旧话不删）**：① **名单闸门也要看"这路径归谁"** —— 它打出 55 命中，其中 **9 条是真阳性**
   （`frida-17.24.3.dist-info/*`：`DROP` 只写了 `frida` / `frida_tools` 两个**目录名**，没盖住 dist-info ⇒ 宽成 `frida*`，条目 112,181→112,172），
   另 **46 条是上游插件目录里的同名词**（他装的 `dsh-purge/lib,presets/redteam/*`，那是插件源码不是这台机的数据）。⇒ 现在分两批：**拦（本机写过的路径）/ 参考（只报数不拦）**，两条计数都印出来。
   判据与"词形"那条同族：**名字不是所有权**。② `--selftest` 从 3 条长到 5 条后**真机第一次跑就全绿**，但它绿的是逻辑，**替代件是否真进包**要靠出包后那一条 `shadow 替代件在位 = 1（要 1）` 的复点。
- **这台机的 adb 两个口都带不了大二进制流，产物必须"机上落文件 + `adb pull` + 两边各算一遍 sha"**（11-03 那三发白花在这一条上，读数 RUNBOOK 14.40 二）：
  `adb exec-out` 在这台机上返回的 fd 是 **`/dev/pts/0`** ⇒ `tar -cf -` 报"输出是终端"，PC 侧收到 **427 B 而退出码 0**；`adb shell` 那条 socket 是**小样过大样翻车**
  （64 KiB 全 `\n` 逐字节撞上 ⇒ 我据此误判"能过"；换成 120 MB 真流，PC 侧**多 614,713 B 且 md5 不对**）。
  ⇒ 凡是 GB 级产物：**在设备上写成文件**（`tar -czf`）**再 `adb pull`**，并且**机上自报的字节数/sha256/条目数**要与 PC 拉回后重算的那三份逐字节撞上（`make-payload.sh` 第 3 步就是这么写的）；
  撞不上就停，别把"退出码 0 + 字节数对"当链路可信。**附带一条**：`du -sbx /` 里的 `-x` **拦不住 bind 进来的 `/phone`**（与 rootfs 同一个 `st_dev`）⇒ "整树"能读出 375 GB 那种假数，口径要写 `--exclude=/phone`。
- **改库可见性要 Administration 那项权限，而"外人下得动下不动"只认匿名 Range**（11-03 状态 42，读数 RUNBOOK 14.41 二/四）：那把 fine-grained PAT 原本只有 Contents + 建库 ⇒ `gh repo edit --visibility public` 回 **HTTP 403**（重试还是 403）。**摊开"缺哪一项 + 那一项还附带什么能力"让他一次决定**，他选的是加权限（Administration 同时管删库、改默认分支、改分支保护）。**编辑权限不换令牌值**（只有 Regenerate 才换）⇒ gh 与 GCM 不用重登，也别去动任何配置。翻完之后判"公开可用"用的是 `curl --ssl-no-revoke -L -r 0-1023` 打 Release 资产 ⇒ 要 **206 + 真收到 1024 B + 头四字节 `1f 8b`**；repo 页 200 与 `gh` 退出码 0 都不算（铁律 3）。
- **要把仓公开之前，扫全历史而不是只看 HEAD**（同轮）：`git log --all -p` 整坨扫凭证形状，顺手数最大跟踪文件与 `.git` 体积（公开后历史里的 blob 删不掉，改历史不算收回去）。**每一发命中都要追进原文再判** —— 那两发 `sk-…` 一发是我自己闸门自测埋的假串、一发是归档 RUNBOOK 里那行 `sk-dummy-invalid-do-not-use`（故意无效的哑 key）。**个人标识先查先例**：那个提交邮箱在他另外两个**公开**库里早就是公开的 ⇒ 不多露一次；设备序列号/机型/root 方案这类**会露但不可逆**的，按事实摆一次，他不改口就执行。
- **库公开之后，现役文件里不写本机可识别项**（11-03 状态 43，读数 RUNBOOK 14.42）：用户名、带用户名的家目录路径、设备序列号、提交邮箱、写死的口令默认值 —— 这类**不全是凭证，但进了跟踪文件就永久可回看**（改历史不算收回）。⇒ **提交前跑 `bash tools/check-private.sh`**（真值名单在**不入库**的 `tools/private-values.txt`，脚本只报形状名与处数、不打印命中内容；自测 `--selftest` = 埋雷要抓到 / 撤雷要回 0，11-03 当场 `合计 7 条：PASS 7 / FAIL 0`）。同轮两处**行为改了**，别按老写法找：① 五支脚本原来把 adb 默认路径写死成"作者本机带用户名的那发"⇒ 现在一律 `DSH_ADB` → PATH 里的 `adb` → `/d/mycode/.agent-tools/platform-tools/adb.exe`，都没有就停下来让人指；② `app/build.sh` 里签名口令的**默认值撤了**⇒ 库在位而取不到口令直接停。他本机那把 `app/local/dsh.keystore`（2,706 B，10-20 造的）用的就是撤掉的那个老默认值，**已写进 `app/local/ks-pass`（0600，该目录 gitignore）**，`keytool -list` 当场开库成功 ⇒ 重打 APK 不用再传 `DSH_KS_PASS`；换机器/丢文件时才需要 `export DSH_KS_PASS=…`，新造库会现造随机口令并存进这个文件。
- **内置浏览器没有他的登录态；驱动他的 Edge 只能坐标点，他手在动就立刻停手**（同轮）：`browser-use` 打开 GitHub 设置页直接跳 `/login` ⇒ 替不了他点。可用形状：`msedge.exe "<URL>"` 在现有实例里开新标签（进程数复点 18→20）+ `user32!SetCursorPos`/`mouse_event`（`tools/win-click.ps1`）+ `CopyFromScreen` 截图回看（`tools/win-shot.ps1`）—— **这两支已入库**：`downloads/` 是忽略区，文档引用它等于引用一个别人拉不到的文件。**每发点击后把 `GetCursorPos` 与请求值比**：一致才继续（`617,437→461,282`、`600,30→636,35` 那两发就是他在动鼠标）⇒ 在**令牌与权限类页面**盲点会把权限勾错，改成"一步一句话说给他点"。
- **`grep -F` 和 `.{0,60}` 不能同时用**（p83 那发）：加了 `-F`，`.` 与 `{0,60}` 全成字面量 ⇒ 五个文件的"原文窗口"齐刷刷空，看着像"页面里没有这段代码"。空窗口先怀疑自己的正则，别下结论。
- **往 chroot 里塞"一条命令"有两种静默失败，11-02 这一轮各撞一次**（都是白花一轮 adb 的那种）：
  ① **PATH**：`chroot $ROOT /bin/sh -c "tar …"` 继承的是 **Android 那套 PATH**，里面没有 `/usr/bin` ⇒ 报 `tar: not found`、`head: not found`，
  看着像"chroot 里没装 GNU tar"。必须 `/usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`（`scripts/dsh-chroot.sh:161` 一直是这么写的）。
  ② **引号层数**：Windows bash → `adb shell "…"` → `su -c "…"` → `chroot … bash -c "…"`，双引号会与外层撞、单引号会被 `su -c '…'` 截断。
  上一版把 `grep -rlIE -e "apiKey|api_key|sk-[A-Za-z0-9]{12,}"` 塞进这种串，`{12,}` 被设备 shell **展开成好几个词**、`|` 被当管道，
  于是一发普查打出 770 行 `/dev` 报错加 `/system/bin/sh: access_token: inaccessible or not found` —— 那种输出**一条都不能信**，
  最坏的是它"看着像跑完了"。⇒ **凡清单里有中文/空格路径、或模式里有 `|` 与 `{}`，就写成设备侧脚本文件走 `--run 'bash /root/x.sh'`**
  （数组拼 `--exclude`、`find -print0`，引号只有一层）；`tools/run-probe.sh:45` 那对 `S()`/`CHRUN()` 的引号形状是可用的，
  但它在 PC 侧字符串里仍然不允许出现双引号 —— `scripts/dsh-payload-pack.sh` 的头注释记的就是这条演进。
- **探针输出文件名要先查同名再写**（14.35 的事故）：我把新探针的读数写进 `downloads/p75.txt`，**覆盖了 14.33 引用过的那份**（差 1 字节，已按原脚本重跑生成，见 14.35 六）。
  `tools/run-probe.sh` 不挡覆盖 ⇒ 落盘前 `ls downloads/p<NN>*.txt`。
- **`navigator.clipboard.writeText` 在这台机的 WebView 里是通的，`readText` 不通**（14.35 各实测一次）：写 → 原生 `input keyevent 279`（KEYCODE_PASTE）粘得回来，同一个串；读 → **`NotAllowedError`**。
  网页里那两处"从剪贴板粘贴"（p82：excel 与 terminal 两个包在用 `clipboard.readText`）因此点了没结果 —— 这条**没有壳侧回调可接**（WebView 不暴露 clipboard-read），能做的是拿 `prompt` 通道 + 原生 `ClipboardManager` 给它垫一个桥（未做，等他点头）。
- **`gh` 这两发坑都是"退出码 0 但活儿没干成"**（11-03 夜，`tools/make-payload.sh` 的 `--publish` 段，读数在 RUNBOOK 14.39 四）：
  ① **`-q` 的 jq 表达式开头的 `|` 会让整条过滤失效** —— 我写 `gh release view … -q '(|.assets|length|tostring)'`，`gh` 报
  `failed to parse jq expression … unexpected token "|"`，**而 shell 看到的退出码是 0**（管道尾巴是 `tr` 的码），看着像读回了空资产。
  正确写法 `(.assets|length|tostring)`。⇒ 这类复点**用 canary 资产验**（建一发 9 B 的、读回名字/字节/digest、当场删），别拿"没报错"当通过（铁律 3）。
  ② **`--notes "…\` + 换行` 的续行会把反斜杠留在值里**（同一条老坑的第 3 次出现，前两次在普查条目里冒出 `[状态 ] \`）⇒ 多行说明一律写成 `NOTES="${NOTES}…"` 分段拼。
  同族第 ③ 条：`gh … | sed` 之后取 `$?` 拿到的是**管道尾码**，不是 `gh` 的 ⇒ 一律 `X=$(…); RC=$?` 再打印。

## 不在这里写的东西

当前状态、待办、遗留问题**不要**往本文件加 —— 它们在 PROGRESS 里，只有一处真源。
本文件只在出现**新的、可复现的**踩坑时加一条，并带上"读数在哪"。
