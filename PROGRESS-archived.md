# dsh-mobile PROGRESS 归档（状态 12–25 的每一格，原文照搬）

> 这一份是 `PROGRESS.md` 的 `## 文件变更` 节里那十几格旧状态，2026-10-21 晚搬出来，**内容一字未改**。
> 现役那半从**状态 26** 起，最新是**状态 31**；`## 当前状态` / `## 下一步` / `## 遗留问题` 三节仍在 `PROGRESS.md` 里没动。

**2026-10-20 这一轮（状态 12/13，改②与改①）新增/改动**：
项目内新建 `config/dsh-env`（改②的真源）、`scripts/dsh-verify-perm-mode.sh`、`scripts/dsh-unshare-run.sh`、
`scripts/verify-unshare-run.sh`、`scripts/dsh-sbx-probe.sh`、`scripts/dsh-dev-node-probe.sh`、
`scripts/dsh-devnull-inner.sh`、`reference/dsh-sandbox-local-index.js`（从设备逐字节拉回的 556 行，14.11 所有
`:254/:311-321/:216/:320/:239-242` 引的都在这份里）、`downloads/verify-runner-3.txt`；
改动 `scripts/dsh-chroot.sh`（`mount_fs` 头部加了 rootfs 自 **rbind** —— 非递归的 `--bind` 会把新 chroot 的
`/proc` 影子成空的，这个我自己造自己查的坑记在它注释里）、`scripts/dsh-dump-config.sh`（改成先 source 服务那份 env，
并写明 `--dump-config` 打的是**没求值的 `!!js` 原文**，别拿它当"配置生效了"的证据）；
RUNBOOK 新增 14.10 / 14.11，14.4、14.5、14.9 三处旧话就地加了箭头改口。
设备侧：`chroot:/root/.dsh-env`（0600，1,687 B）、`chroot:/usr/local/bin/dsh-unshare-run`（0755，9,530 B）、
`/data/local/tmp/{dsh-sbx-probe.sh,verify-unshare-run.sh,dsh-dev-node-probe.sh,dsh-devnull-inner.sh}`，
`/data/local/sh/` 里另有两份同名的旧副本（那份目录这台机上 root 写入是间歇性 EACCES，见状态 14，没强删）。
**没动过的**：他的会话/凭据/档位（`danger-full-access` 原样留着）、`profiles/web/cordis.patch.yml`（没接线）、
`/data/local/tmp` 里他自己的那些件、KernelSU 配置、自启（还是 `.off`）。

**2026-10-20 追加这一轮（状态 15，三家对比调研）新增/改动**：**设备侧零操作**（这轮全程在 Windows 上读代码，
一次 adb 都没发）。项目内新建 `reference/android-three-community-apps.md`（报告本体）、
`downloads/gh3/`（三家 main tarball + GitHub API 原文，约 52 M）、`downloads/gh3.sha256`（三条校验和）、
`reference/gh-3p/`（解包件 ~100 M：DSHA 66 M / Soodok 14 M / woaiys3 20 M，全部只读参照）；
`.gitignore` 加一行 `reference/gh-3p/`（`downloads/` 本来就在忽略里）——**为什么忽略了还留在盘上：
报告里每一条 `文件:行` 都指向这些解包件，删了下次要重下；它们没进 git，`git status` 干净。
改动：`RUNBOOK.md`（新增 14.12 + 文件索引那三行）、`reference/android-community-routes.md`（顶部加一句指向本文的箭头，
两份是同一批调研的两种形态，不新开一扇门）、本文件（状态 15 + 这段 + 下一步第 9 条 + 遗留问题两条）。

**2026-10-20 追加（他点名的两仓落到本地，任务 #21）**：**设备侧零操作**，一次 adb 都没发。
`reference/gh-3p/DSHA-main` 与 `reference/gh-3p/deepseek-harness-android-app-main` 从"解包件"变成**真 git 仓库**
（各自一条出处提交 `a92928f` / `72f553e`，消息里记死上游 commit、tarball 字节数与 sha256、`pushed_at`；
`origin` 指向上游、`git status --porcelain` 空、`core.autocrlf`/`safecrlf` 置 `false`）；
新建 `tools/clone-upstream.sh`（按深度切：浅克隆 → 逐段 `--deepen` → `--tags` → 试 `--unshallow`；
**实测在这条链路上不可行，判死过程与算术见 14.13**，留作"连历史 blob 也要"的退路）与
`tools/fetch-history.sh`（按对象类型切：`--filter=blob:none --no-checkout`，**实际成的是这份**），
产出 `reference/gh-3p/DSHA-hist`（627 条提交 / 28 标签 / 1.6 M）与 `reference/gh-3p/dsh-android-app-hist`
（298 条 / 28 标签 / 481 K），读数在 `downloads/fetch-history.log`；`downloads/clone-upstream.log` 是失败那趟的原文，留着。
两仓各多出 `.git` **32 M / 7.4 M** + 历史 **1.6 M / 481 K**，仍全在 .gitignore 内。
（这两份 hist 的体积按写这条时的 `du -sk` 读数 1,588 / 481 KiB —— 脚本报的是刚落地那一刻的数，`--tags` 之后还在长，
**别把哪个当定值**；提交条数与标签数才是定值。）
`RUNBOOK.md` 加 14.13（链路实测读数、三个自己的坑、以及他那句"三种形态"的纠正），文件索引补 `tools/fetch-history.sh`
与 `reference/gh-3p/` 那一行的下半句；本文件加状态 16 + 这段 + 下一步第 9 条的 ④ + 遗留问题三条（其中一条写完就改口了）。
`reference/android-three-community-apps.md` 加**第六·补**节（历史到手新增五条、两条改本文的口），
口径那节补第四档【史】，一屏结论表里 woaiys3 那格版本证据由【文】升【史】，star 数加了"当天就在动"的注。
**没做**：Soodok 那仓本轮他明确先不看 ⇒ 只停在解包件，没做成仓库、没取历史；两份 hist 里**没有历史 blob**，
要看某次提交改了哪几行得按需经镜像拉。

**2026-10-20 晚上这一轮（状态 17，手机入口换成常驻入口 + WebView 壳，任务 20）新增/改动**：
项目内新建三份 —— `scripts/dsh-entry.js`（**47,151 B**，常驻入口：起引擎、认 token 启动行、内存里换 cookie、
出口注入兼容层、只绑 127.0.0.1:3081、`--selftest` 46 条判据）、`scripts/dsh-entry-check.sh`（**5,742 B**，
机上只读体检：三种门禁探针 + 真首页字节顺序 + 入口自述 + 上游文件被动过没动过）、
`tools/deploy-entry.sh`（**8,014 B**，一条命令管推送/校字节/收日志权限/自测/起入口/看状态/跑体检/拉口令）。
重写三份 —— `app/src/com/zhl/dsh/MainActivity.java`（现 **28,884 B**；旧版尺寸没记，这一版新增的是：地址写死入口、种 cookie 后再 loadUrl、
`prompt()` 面板与原生通信、`android.util.Log` 六类事件、`setWebContentsDebuggingEnabled(true)`、retry 前 `clearCache`）、
`app/build.sh`（**6,789 B**：第 7 步换成这台机上唯一装得进去那条路 push→root cp→restorecon→`pm install -r`→删两份，
两条失败路留在注释里）、`app/AndroidManifest.xml`（**1,274 B**，versionCode 2 / versionName 0.2 ——
**manifest 这两个属性压过 aapt2 的 `--version-name`**，第一版就是这么装出来还是 0.1 的）。
改动三份 —— `scripts/dsh-chroot.sh`（**20,229 B**，加 `--entry` / `--entry-stop` / `--entry-status`）、
`scripts/dsh-console.sh`（**4,492 B**，菜单第 2 项直接起入口、第 3 项直接 `am start` 开 App，旧的"裸引擎 + 粘 token"
保留在 `w)` 当对照）、`scripts/dsh-boot.sh`（**1,861 → 2,477 B**：自启从 `--web` 改成"入口在位就 `--entry`"，
否则真重启一次就把 App 打在「连不上工作台」那一屏 —— 见下一步第 5 条）。删除两份 —— `app/local/url.txt`（里面是**活的一次性 token**，`.gitignore` 挡不住它躺在盘上）、
`scripts/dsh-probe-page.sh`（被 `dsh-entry-check.sh` 取代，机上那份副本一并 `rm`）。
**设备上被写的每一处**（全是我自己建的件）：`chroot:/usr/local/bin/dsh-entry.js` 47,151 B / 0755
（sha256 前缀 `296d82a382a0` 与本地逐字节相同）、`chroot:/root/.dsh/entry.key` 44 B / **0600**（口令值全程不上屏、
不进命令行、不进日志）、`chroot:/root/.dsh/entry-compat.js` 3,123 B、`chroot:/root/.dsh/entry.log`、
`chroot:/root/dsh-entry-check.sh` 5,742 B、`/data/local/sh/{dsh-chroot.sh,dsh-console.sh}`（各 20,229 / 4,492 B）、
`/data/local/dsh.log` 从 **0644 收到 0600**、新装 `com.zhl.dsh` 0.2（base.apk 82,537 B，
sha256 `65c49666…161e8b3` = 本地产物）、`/data/adb/service.d/50-dsh.sh.off`（**1,861 → 2,477 B**，
逐字节等于仓库那份 `4207c1bbf779…`，mode 0750 不变、**后缀 `.off` 不变 ⇒ 自启依然是关的**，只是把"开机只起裸引擎"
那个会把 App 打死的分支改掉）、装机用的临时件（推件暂存 `/data/local/tmp/.dshdeploy.<pid>`、装机暂存 `/data/local/tmp/dsh-app.apk`、
自启那份 `/data/local/tmp/.dshboot.new`）**已删净并复点为空**（装机那趟本来就在同一条命令里 `rm -f` 两处落点并复查
`/data/dsh-app.apk` 不存在；漏的是推件那条分支，见下一句）。
**这句是补做出来的，不是本来就成立的**：`push2` 剥 CR 那条分支 mv 走的是 `.lf` 那一份、**原件没人删**，
所以盘上实际堆了 4 份 19:22 的 `.dshdeploy.<pid>` + 一份已被 `dsh-entry-check.sh` 取代的旧 `probe-page.sh` ——
我第一版 changelog 写"搬完即删并复点"是**假读数**，按 `ls -a` 读回来才改成：脚本两条分支各补 `rm -f`，
机上那 5 份手动删掉，复点 `(无)`（`/data/local/tmp` 他自己的 71 件照旧，一个字节没碰）。
**没动过的**：他的会话/凭据/档位（`danger-full-access` 原样）、`dist/index.html`（876 B，
`grep -c data-dsh-entry-compat` = 0 行 ⇒ 兼容层只在出口内联，不再打进上游文件）、
`dist/assets/dsh-compat.js`（早轮打进去那份**原地留着没删** —— 与出口内联那份逐字节相同，双份是幂等的，
删它要动 vendor 目录，不值一次写入）、他的 `/data/local/tmp` 那堆 boot/kpatch/magiskboot、KernelSU 与 susfs 配置、
自启的**开关**（还是 `.off` —— 内容我改了，见上；状态没改，开机什么都不拉起）、16 MB 那个原生客户端（他点的"留着当对照"）。

新增 `RUNBOOK.md`（v2，全实测读数）、`PROGRESS.md`（本文件）、`tools/pin-hosts.py`、
`scripts/` 下 17 个脚本（总控 / 安装 / 自启 / 填 key / 控制台 / 验收 / 一组只读取证）、
`reference/` 下 4 份（3 份从设备逐字节拉回的资料 + Termux `~/.bashrc` 追加段）。
设备上：`/data/local/dsh-rootfs`（rootfs + node + dsh）、`/data/local/sh/*.sh`、
`/data/adb/service.d/50-dsh.sh.off`（自启现为关）、`/etc/hosts` 钉 IP 段（885 → 954 B，加了 `platform.deepseek.com`）、
新装 `com.termux` 0.118.3，其 home 里落了四个文件（全是我建的，owner u0_a343）：
`dsh-console.sh`(3,773 B) + `.dsh-hook.sh`(1,007 B) + `.bashrc`/`.bash_profile`(各 236 B，同一行 source)。
设备上 `/data/local/sh/` 另加 `dsh-console.sh`、`dsh-ask.sh`、`get-termux.sh` 三份，rootfs `/root/dsh-ask.sh` 一份。

**2026-10-20 这一轮**（三句话的账，全部读数在 RUNBOOK §13）：
新增 5 份 —— `scripts/dsh-webconnect-probe.sh`、`scripts/dsh-fetch-probe.js`、`scripts/dsh-add-workspace.js`、
`scripts/dsh-clear-key.sh`、`tools/dsh-compat.js`，加 `reference/` 下 `dsh-web-frontend-index.orig.html`(825 B)
与打过补丁的 `dsh-web-frontend-index.html`(876 B) 两份对照。
改动 1 份 —— `scripts/dsh-chroot.sh`（9,882 → 12,581 B，md5 `9e48227861d4476407289a6afdfad68c` 设备侧逐字节一致）：
`mount_fs` 挂 `/phone`、`--web` 前 `cd /phone`、`--status` 多打工作区一行、`--umount` 带上 phone。
设备侧被改的三处盘上文件：`dist/index.html`（插一行 polyfill）、`dist/assets/dsh-compat.js`（新增）、
`/root/.dsh/storages/workspace.json`（加了 `/phone` 一条，原文件在 `/root/.dsh/workspace.json.bak`）。
凭据库动过两次：假 key 写入 → 用 `dsh-clear-key.sh` 删掉，那份中间态备份留在
`/root/credentials.yaml.cleared-20261020-004131`。当前服务 pid 23377，`:3080` 在听，页面 200。
误触说明：在他手机上盲点菜单时点开过一次信息流广告（拉起京东 App），已 `am force-stop` 关掉，该 App 之前不在运行。

删除：PC 侧 `downloads/node-usr.tar`（198,184,960 B，我在 Windows 上重打的中间件，实测丢了可执行位、已无用）；
设备上我自己推的 5 个临时件（ubuntu-base / node 包两份 / hosts.pinned / cookie jar）。
他原有的 `boot_b.img`、`init_boot_b.img`、`kpatch/`、`magiskboot`、`patch_boot*.sh`、`brevent*`、
`sukisu_*.ko`、`stock_boot.img`、`new-boot.img` 抽查全部在位未碰。

**2026-10-20 凌晨这一轮**（「网页太麻烦了，想办法整个桌面端」，全部读数在 RUNBOOK §14）：
PC 侧新增 `D:\tools\android-build\`（约 90 MB 免 Android Studio 的 APK 工具链：aapt2 / r8 / apksig / platform-35 的 android.jar，
每样都核过 sha1 或 sha256，整目录可删）；项目内新增 `app/`（WebView 壳源码 + `build.sh`，
产物 `app/out/dsh-app.apk` **78,441 B**，sha256 `b1c7e602…b2435c96`，`aapt2 dump badging` 认得出 —— **没装到手机上，是退路**）、
`tools/decomp-session.js` 与 `tools/dump-record.js`（只读解开 `session.v4.jsonl.zstd`，14.4/14.5 的读数出自它们）、
`downloads/dshm-1..17.png` 屏证与那份 16 MB APK；`.gitignore` 从 1 行加到 3 行（补 `app/local/`、`app/out/`，
因为 `app/local/url.txt` 里是**活 token**）。
设备上：新装 `com.labteto.dshmobile`（他要的这一层）；chroot 内 `apt install bubblewrap 0.9.0-1ubuntu0.3`（126 KB，为取证装的，
`apt -y remove` 即撤）；服务从"死过一次"的状态用 `--web` 重起，现 pid **10150**、`:3080` 在听、一条 ESTABLISHED 就是那个 App。
本轮我自己推的取证临时件（`/data/local/tmp/{decomp.js,dump.js,s.cur.zst}` 与 rootfs `/tmp/{decomp.js,dump.js,s.zst}`）
**已全部删掉并复点**，`/data/local/tmp` 剩下的仍是他自己那些件。
误触说明：一次 `input tap` 落空把屏幕甩到了桌面搜索页（`com.heytap.quicksearchbox`），没拉起任何第三方 App、没点任何授权。

**2026-10-20 同一晚的追读**（他让我精读社区那两个仓库）：纯调研，**设备侧零写入**（只跑只读探针，
临时探针脚本 `/data/local/tmp/pns.sh` 与 rootfs `/tmp/pns.sh` 跑完当场 `rm`，`/phone/.dshlinktest` 测试目录已 `rmdir` 并复点为不存在）。
PC 侧新增 `reference/android-community-routes.md`（逐条对照与反面教训）、`reference/gh-deepseek-harness-{termux,android}/`
两份 `--depth 1` clone（各约 270 KB，只读参照，随时可删）、`scripts/probe-namespaces.sh`（命名空间能力探针，只读），
`downloads/` 下多几份 issue/readme 抓取件；`RUNBOOK.md` 加 14.9 与 §11 三行指针，本文件加状态 11 与下一步第 8 条。

**2026-10-20 深夜这一轮（状态 18，他验收那四个症状）**新增/改动：
新增一份 `scripts/dsh-cdp.js`（约 150 行，只读驱动手机上那个 WebView：`--list/--eval/--watch/--click/--url`；
网络记录`reqLine()`故意把 query 丢掉，因为 query 里可能带一次性 token；`mWakefulness` 不是 Awake 就直接拒绝跑 ——
实测 Dozing 时 renderer 冻着、attach 超时，那种状态下量出来的读数不可信）。
改动五份 —— `scripts/dsh-entry.js` 47,151 → **64,791 B**（`escapeForInline()` 修代码墙、`proxyRequest` 与
`attachUpgrade` 两处 Origin/Referer 改写、`S.seen`/`S.bad` 两个环进自述页且非 2xx 那环多带一列 Origin、
自测从 46 条加到 **59 条**：新增 4c+ 生产那双 / 4d 转义 / 4e 环 / 4f Origin 栅栏与隧道两条断言）、
`scripts/dsh-entry-check.sh` 5,742 → **13,579 B**（同源栅栏差分 / 内联元素关得对不对 / 静态资源耗时 /
"摘掉 script 之后正文还剩多少可见文字"）、`scripts/dsh-chroot.sh` 20,229 → **20,763 B**（`--entry-stop`
那条假警报：改成最多轮询 10 秒并把等待秒数打出来）、`app/src/com/zhl/dsh/MainActivity.java`（模板展开
**34,678 B**：`setSupportMultipleWindows` + `onCreateWindow` + `OVER_SCROLL_NEVER` + 落盘的 `shell.log`
日志通道，400 KB 自截断、口令与 token 只报长度）、`app/AndroidManifest.xml`（versionCode 3 / versionName 0.3 +
`enableOnBackInvokedCallback="false"`，注释里把"事实：targetSdk=35 那条读数"与"推断：所以返回键不生效"分开写，
并写明这个读数还欠着）、`app/res/values/styles.xml`（**新建**，深色 windowBackground 治冷启动白闪）、
`app/build.sh`（VER_CODE=3 / VER_NAME=0.3）。
文档三份就地改口并加读数 —— `RUNBOOK.md` 加 **14.15** 整节、13.4 表里那条`cp /data/local/sh/index.html.orig-dshmobile`
标成"指向一个不存在的文件，别照着跑"、第 0 节"页面能跑起来的前提"那行补两次改口、文件清单里删掉不存在的
`--entry-status` 并把 `46 条判据` 改成 59；本文件加状态 18 与这段。`reference/dsh-web-frontend-index.orig.html`
与 `.html` 两行的说明也按"机上新备份落在哪、谁才是还原真源"重写过。
设备上被写的每一处（全是我自己建的件）：`chroot:/usr/local/bin/dsh-entry.js` 64,791 B / 0755、
`chroot:/root/dsh-entry-check.sh` 13,579 B、`/data/local/sh/{dsh-chroot.sh,dsh-console.sh}` 20,763 / 4,492 B、
`chroot:/root/.dsh/index.html.patched-876.bak`（新建备份）、
`chroot:…/dsh-web-frontend/dist/index.html` **876 → 825 B**（还原上游原样，md5 `5a1bf51057dbb270bcba7d997498db6e`
与仓库那份逐字节相同）、同目录 `assets/dsh-compat.js` **删除**（3,123 B，与出口内联那份字节全等）、
新装 `com.zhl.dsh` **0.3**（86,632 B，sha256 `84ce80fafe1747d9…`，机上 base.apk 与本地产物逐字节相同）、
推件与装机暂存件当场 `rm` 并复点。`/data/local/tmp` 下他自己那堆（boot_b.img / kpatch / magiskboot /
sukisu_*.ko / brevent* / stock_boot.img / new-boot.img / app-debug.apk）一个字节没碰。
**零出网**（全程只打 127.0.0.1），**没做过**：动他的会话/凭据/档位（`danger-full-access` 原样）、动 KernelSU 或
susfs 配置、绕锁、开自启开关（还是 `.off`）、拆 16 MB 那个对照客户端、git commit。
误触与失手两处，都按读数当场改口：① 我第一版把装机 sha 写成 `2511557f…`（那是没按盘上 `sha256sum` 抄的），
现在 `84ce80fafe1747d9…`；② 差分脚本我第一版直接对**整页**抓资源名，把 polyfill 注释里那句示例标签当成一条真
资源去请求，量出个 404 看着像"资源挂了"⇒ 改成先摘内联再抓（干净页 39,512 B / 整页 42,690 B）。

**2026-10-20 深夜再下一轮（状态 19，他真机用了一趟）**新增/改动：
新增 `downloads/dsh-shot-2040.png`（363,580 B，第一张真渲染截图）。
改动一份代码 —— `scripts/dsh-entry.js` **64,791 → 69,556 B**（`attachUpgrade` 重写：`handedOver` + 首字节到就
`up.setTimeout(0)`、`close/error` 处理器移出 `net.connect` 回调、新增 `CFG.wsHandshakeMs`（默认 8000，
`DSH_ENTRY_WS_HANDSHAKE_MS` 可调）；自测 **59 → 62 条**，新块 6b 三条 + 假上游加了 `/ws-stall`）。
→ **那两个条数是加出来的不是读出来的**：状态 20 那轮按脚本打的"合计"行实测 **Windows 与机上都是 58**（含新加的
一条），倒推本轮之前是 57。6b 三条本身逐条 PASS 是真的，错的只有汇总数。口径见 RUNBOOK 14.16 原地的改口。
`scripts/dsh-entry-check.sh`（13,579 B）、`dsh-chroot.sh`、壳那四份 Java/manifest/资源本轮**一个字节没动** ——
这一轮的输入是他那趟真用产生的流量，不是我改出来的。
文档两份 —— `RUNBOOK.md` 加 **14.16** 整节（119,468 B），14.15 里那句"选择器那条路已通还没有读数"就地加箭头改口；
本文件加状态 19 与这段、下一步第 12 条把"点一次选目录"划掉（已量到）。
设备上被写的每一处（全是我自己建的件）：`chroot:/usr/local/bin/dsh-entry.js` 69,556 B / 0755，
入口重启一次（`:3080` 关→起，引擎新 pid 18741），`/data/local/tmp` 下他自己那堆一个字节没碰。
**零出网**（全程只打 127.0.0.1），**没做过**：动他的会话/凭据/档位、动 KernelSU 或 susfs 配置、绕锁、
开自启、拆对照客户端、git commit。

**2026-10-20 深夜最后一格（状态 20，那簇 40 秒的请求）**新增/改动：
新增 `scripts/dsh-slow-probe.sh`（**1,381 B**，只读耗时探针：口令只从 `/root/.dsh/entry.key` 读进变量、
只走 `curl -K -` 的 stdin，不进 argv 不打出来；跑法是推进 chroot 后 `dsh-chroot.sh --run 'bash /root/…'`，
**用完当场删机上副本并复点**）。
改动一份代码 —— `scripts/dsh-entry.js` **69,556 → 70,487 B**（`proxyRequest` 里加 `req.on('end')` 记
"请求体收完"的时刻，流水每行尾部多一列 `体Nms`/`体未收完`；判据加一条 ⇒ 脚本自己打的合计是
**58 条 PASS 58 / FAIL 0**，Windows 与机上交付物各跑一遍都是 58）。
文档两份 —— `RUNBOOK.md` 加 **14.17** 整节，并就地改口三处（14.16 那句"62/62"、文件清单里 `dsh-entry.js`
那行原先写的"59 条判据"、清单里新增 `dsh-slow-probe.sh` 一行），按盘上读数是 **126,270 B**；
本文件加状态 20、状态 19 里那两个条数加箭头、文件变更加这段、下一步第 12 条补"下一次读 体 那一列"。
设备上被写的只有一处（我自己建的件）：`chroot:/usr/local/bin/dsh-entry.js` 70,487 B / 0755、
md5 `4af378c95d0bab8a9bf0681e50095cc1`（与 `/data/local/tmp` 暂存件逐字节相同）；入口停/起一轮
（新 pid 17611、引擎 17637）。临时件三份（`/data/local/tmp/dsh-slow-probe.sh`、`/data/local/tmp/dsh-entry.js`、
`chroot:/root/dsh-slow-probe.sh`）跑完当场删并复点为不存在。他自己那堆 `/data/local/tmp` 文件一个字节没碰。
**零出网**（探针只打 127.0.0.1:3081），**没做过**：动凭据/会话/档位、动 KernelSU 或 susfs、绕锁、开自启、
拆对照客户端、git commit。**本轮没修任何东西**（只加了区分甲乙的那一列）。

**2026-10-20 深夜收尾（状态 21，他提的三件手感事 → 壳 0.4）**新增/改动：
改动四份（全在 `app/`，壳这一层）—— `app/src/com/zhl/dsh/MainActivity.java` **34,647 → 42,773 B**
（新增 `goFullscreen()` 用 `WindowInsetsController` 收状态栏+导航栏、`handleBack()` 三层返回语义并由
`onKeyDown` 与 `onBackPressed` 共用、`askExit()` 那张"退出工作台？"确认屏、`startLoad()` + 5 秒看门狗自动重试、
`onCreate/onPause/onResume/onDestroy` 四条生命周期日志、**删掉 `web.pauseTimers()`**）、
`app/AndroidManifest.xml`（versionCode **4** / versionName **0.4**，那段"事实与推断分开"的注释按他的新读数重写）、
`app/build.sh`（VER_CODE=4 / VER_NAME=0.4）、`app/res/values/styles.xml` **没动**（全屏走运行时，不走那条旧旗标）。
新增两张屏证：`downloads/dsh-shot-now.png`（322,635 B，0.3 时他那一屏，状态栏还在）、
`downloads/dsh-shot-04-fullscreen.png`（304,540 B，0.4 全屏后）。
文档两份 —— `RUNBOOK.md` 加 **14.18** 整节 + 14.15 那两串 0.3 指纹加箭头指向 0.4（"认版本只认 sha 不认字节数"），
本文件加状态 21 与这段、下一步第 12 条把"返回键"改成"0.4 上要他按两下"。
设备上被写的只有装机这一处：`com.zhl.dsh` 0.3 → **0.4**（`adb install -r`，同一把自签 key，不卸载所以他的
cookie 与首选项都还在），成品 `app/out/dsh-app.apk` **86,632 B**、sha256 `b20c6ddfa38d53b4baa9bbcd4a01fa286707358224a9764f168ce467e632945c`
与机上 `base.apk` 逐字节相同。我建的暂存截屏件（`/data/local/tmp/cap*.png`）当场删并复点。
**零出网**（CDP 走 adb forward、探针只打 127.0.0.1），**没做过**：动凭据/会话/档位、动 KernelSU 或 susfs、
绕锁（他手机睡了我就停手，没替他解锁）、开自启、拆那个 16 MB 对照客户端、git commit。

**2026-10-20 深夜再收一格（状态 22，他把返回键那两件事退回给我 → 壳 0.5）**新增/改动：
改动三份（还是全在 `app/`）—— `app/src/com/zhl/dsh/MainActivity.java` **42,773 → 52,266 B**（模板，展开进包 52,297 B；
本轮末尾又补了两条注释，模板现 52,423 B）：`handleBack()` 重排成四层并把"页面里有没有盖着的层"这一层放到最前、
新增 `closeOverlayOrHint()`（`evaluateJavascript` 异步 + 800ms 兜底）与 `OVERLAY_JS` 那段判据、
新增 `showExitHint()/hideHint()/makeHint()/fadeHintOut/dp()` 与 `root/hint/hintUntil/ui` 四个字段、
`setContentView(web)` 改成先套一层 `FrameLayout`、**整段删掉 `askExit()` 并去掉 `AlertDialog` 的 import**；
`app/AndroidManifest.xml`（versionCode **5** / versionName **0.5**）、`app/build.sh`（VER_CODE=5 / VER_NAME=0.5）。
`app/res/values/styles.xml` 与 `scripts/dsh-entry.js`（仍 70,487 B）**都没动**，入口与引擎这轮**没重启**。
新增一条只读探针 `scripts/dsh-entry-status.sh`（1,560 B，同一条路带/不带口令各问一遍，用来把"入口按设计拒答"
和"入口真挂了"分开——这轮就靠它把一条 `Not Found` 判成甲；口令只经 stdin 给 `curl -K -`，不进 argv 不进输出）。
新增四张屏证：`dsh-shot-05-sidebar-expanded.png`（258,080 B，侧边栏 280 px 摊开那一屏，他描述的同一件事）、
`dsh-shot-05-hint.png`（96dp 那版，压在输入框上）、`dsh-shot-05-hint2.png`（40dp 那版）、
`dsh-shot-05-hint-faded.png`（等 3 秒后，与上一张逐像素只差浮层那块 1004×178 的区域 ⇒ 自己消散）。
文档两份 —— `RUNBOOK.md` 加 **14.19** 整节 + 14.18 那条"第 1 层灵不灵取决于前端有没有 push history"加箭头
（读数：`history.length` 恒为 1，那层不是有时不灵，是永远不灵），本文件加状态 22 与这段、
下一步第 12 条从"要他按两下"改成"0.5 上按三下"。
设备上被写的只有装机这一处：`com.zhl.dsh` 0.4 → **0.5**（`adb install -r` 两发同版本号，
`d5432fa67c826301…` 与 `251282084c113dcc…`，机上现在这发是后者；`dumpsys` 只读到 `versionName=0.5`，
**区分不了这两发，只有 sha 能**）。成品 `app/out/dsh-app.apk` **90,729 B**。
**这轮手机上没落任何暂存件**（截屏全用 `exec-out` 直接拉回 Windows，`/data/local/tmp` 一个字节没碰），
**零出网**，**没做过**：动凭据/会话/档位、动 KernelSU 或 susfs、绕锁（每次发输入事件前都先读到 `mWakefulness=Awake`）、
开自启、拆那个 16 MB 对照客户端、git commit。

**2026-10-20 深夜再收一格（状态 23，他一句"先去看那两个已克隆的项目怎么适配手机，看完再做" → 壳 0.6 + 选择器补入口 + 语音查到底）**
先按他说的读了先例，再动手，三处都照先例落：`reference/gh-3p/DSHA-main` 的
`MicrophonePolicy.java:9-36`（判来源与"要的是不是只有麦克风"）、`WebViewMicrophone.java:1-70`（发系统权限申请再把结果交回 request）、
`AndroidManifest.xml:6-9`（三条麦克风声明）、`RuntimeExecution.java:102-108`（往 rootfs 的 `/root` 建「手机存储」软链、失败只记一条不阻断）；
`Deepseek-Harness-Local-Android-main` 那条走的是另一路（native `AudioRecord` + 自己的识别 + `evaluateJavascript` 灌文字），**我没选它**，
理由是引擎那套插件本来就按"浏览器给音频流"设计（`…-api-speech-to-text` 自述原话），选它要改两边。

改动三份代码：`app/src/com/zhl/dsh/MainActivity.java` **52,423 → 62,414 B**（模板，展开进包 62,445 B）——
`onPermissionRequest` → `requestMic()` 五道闸（有 pending / 无 origin / 要的不止麦克风 / 来源不在放行范围 / 这一发已过期）
+ `finishMic()` 单次闩后只 `grant(RESOURCE_AUDIO_CAPTURE)`，grant 抛 `RuntimeException` 就退成 deny；
`app/AndroidManifest.xml`（3,991 B，versionCode **6** / versionName **0.6**）加 `RECORD_AUDIO`、`MODIFY_AUDIO_SETTINGS`、
`uses-feature(microphone, required=false)`；`app/build.sh` VER_CODE=6 / VER_NAME=0.6。
第四份是引擎侧：`scripts/dsh-chroot.sh` **20,763 → 23,047 B**，新增 `home_entry_ensure()`（`:135-147`）
并挂进 `--web`(`:244`)/`--entry`(`:281`)/`--run`(`:373`) 三条路径的 `mount_fs` 之后，**已部署**（机上复点同字节），
跑 `--entry` 时它建完链就走到 `[skip] :3081 已在听` ⇒ 入口 pid 17611、引擎 pid 17637 前后同一对，**没重启**。
`scripts/dsh-entry.js`（70,487 B）与 `app/res/values/styles.xml` 这轮**都没动**。

读数与证据（详见 `RUNBOOK.md` **14.20**）：麦克风链在他机上真按通了（`shell.log` 六行 23:07:18→23:09:00，
含一行"要的不只是麦克风 ⇒ 拒"的实弹、一行系统弹窗、`dumpsys` `RECORD_AUDIO: granted=true flags=[USER_SET|…]` ⇒ 是他点的允许）；
选择器不带 path 那一发从 `entries` 只有 `.dsh`/`.npm` 两条 hidden 变成**多出 `手机存储`(hidden:false)**，
顺着软链 `path=/root/手机存储` 与 `…/Download` 都列得出来；语音查到源码层 —— 平台白名单含 `linux-arm64`、
`sherpa-onnx-linux-arm64` 已装（**手机跑得起**），默认 int8 模型 239,233,841 B + tokens 315,894 B + VAD 1,807,522 B ≈ **241 MB**，
盘上那四层目录**零文件**（`du` 那 14 KB 是目录 inode，不是权重），两个默认源在这台机全死
（`huggingface.co` 拿到的是脸书段 IPv6 且 `ip -6 route` 为空、强制 -4 超时；`hf-mirror.com` 解析都拿不到），
而他电脑上 `hf-mirror.com` HEAD 是 **200** ⇒ 可行的路是电脑下 + 校 sha256 + `adb push`，**这 241 MB 我没动，等他点头**。
改口两处并写进 14.20：① 上一轮"探针副本已删"是 `test -e` 在 EACCES 下返回 false 造成的假读数，
本轮真数出 9 份（`p.sh p2…p6` + `p13…p15`）逐条删、删后复点为 0；② "53 端口出站被拦"那句测的是 **TCP** 53，
`getent` 这轮拿到过答案 ⇒ **UDP 53 通但答案被污染**，以后"解析不了"与"解析错"分开报。
上一轮挂着的 root 那件事（uid 0 但域还是 shell）这轮复测自己好了（`su -c id` → `context=u:r:su:s0`），**成因仍未定位**（推断，无证据）。

出网：chroot 内 3 发 HEAD + Windows 侧 2 发 HEAD，body 全 0 字节，无 clone、无安装、无模型字节。
新增三份只读探针 `scripts/dsh-voice-picker-probe13/14/15.sh`（3,001 / 3,055 / 3,557 B，全 `bash -n` 过、零 CR、机上跑完即删），
读数留在 `downloads/p13.txt` / `p14.txt` / `p15.txt`。文档：`RUNBOOK.md` 加 14.20 整节（1,599 → **1,746 行**，159,865 B），
本文件加状态 23 与这段、下一步补第 14、15 两条。
**这轮没做过**：点 App 上那行「手机存储」（要他人工闭环）、触发模型下载、单独验 `MODIFY_AUDIO_SETTINGS` 缺了会怎样、
量竖屏下的布局、动 KernelSU/susfs、绕锁、git commit。

**2026-10-21 凌晨那一格（状态 24，他一句"提交，然后下模型"→ 241 MB 进来、插件自己认了、并且真出字）**
先提交：`2c4b0fa2` 是本项目的**首次入库**（87 份）。**差点出事**：`git add` 不带 pathspec 时，工作区里他那批与本项目无关的
`D ../aihot-promo/…`、`D ../apple-site-tour/…` 删除会被一起暂存走 —— 现在 `add` 与 `commit` **都带 `-- dsh-mobile`**，
并补了 `.gitignore`（`downloads/`、`reference/gh-3p/` 这类只读参照件不入库）与 `.gitattributes`（`.sh` 强制 LF，防止我推上去的探针被 Windows 换成 CRLF）。

再取模型（读数全在 RUNBOOK **14.21**）：电脑侧按包里 `runtime/assets.json` 那几个固定 URL 从 hf-mirror 取三份 ——
`model.int8.onnx` **239,233,841 B**、`tokens.txt` **315,894 B**、`silero_vad.onnx` **1,807,522 B**，合计 **241,357,257 B**，
逐个本地算 sha256 与清单对上再 `adb push`。**目录形状是猜错一次才知道的**：清单里 VAD 的落点是
`models/silero/`，与 `models/sensevoice-onnx/` 是**兄弟**、不是它的子目录（`lib/index.js:216` 那句 `join(dataRoot,"models","silero",name)`），
第一版按 `sensevoice-onnx/silero/` 推过去插件不认。**又改口一次**：push 脚本第一版报"零失败"是假的 ——
`adb` 在 `while read` 循环里把循环的 stdin 吃了，实际只推了一份；判据改成**三个计数必须相等**（清单 3 ⇒ 推 3 ⇒ 机上校验通过 3，`push2.log` 读数 `3/3`），
`push.log` 那份错日志留着不删，它是这条错长什么样的证据。

插件那一侧的闭环**不是我算的**：`speech/prepare`（args 从 `speech/catalog` 的 `selection.providerId` = `sensevoice-local` 拿）
之后轮询，`[05s] checking` ⇒ **`[10s] ready`、五步全 complete、全程零下载字节**。原因是代码里 `download()` 第一行
`if (await matchesAsset(...)) return;`（:338），而 `matchesAsset()` 判 size + 整文件 sha256 ⇒ **撞上清单连 DNS 都不查**。
顺带把那份"过期快照"摘掉：第一次读 catalog 拿到的还是 `failed` + 他那次点下载失败的旧消息，那不是新判断，
是进程内对象（`/root/.dsh` 下语音这块没有任何状态文件）。内存增量实测：引擎 234 → 247 MB，识别 worker 单进程 RSS **440 MB**
（插件自己给 UI 的预估是 1 GB，那是预估不是读数），机器 `MemAvailable` 9,420 MB 量级 ⇒ 富余。

**最硬的一发**：Windows 自带 SAPI 合成「今天天气怎么样，我想出门散步。」→ ffmpeg 转 16k/单声道/PCM16 → base64 喂 `speech/transcribe`，
机上回 `text:"今天天气怎么样？我想出门散步。"`、`audioSeconds:4.2379375`、`inferenceSeconds:0.1039142189999984`
⇒ **4.24 秒音频在手机上推理 0.10 秒**。中间被拒两次，**两次都是我的错**：线上键名是 `audioBase64`（我照 core 内部那个 `request.audio` 猜的），
以及 ffmpeg 默认在头里塞了一块 LIST INFO 元数据（`worker.js:110` 硬按第 44 字节起读 PCM，偏移 36 那四个字节必须是 `data`），
要 `-map_metadata -1 -fflags +bitexact -flags:a +bitexact`。逗号出来成问号不算识别错：模型开着 `useInverseTextNormalization: 1`，断句是它自己判的。
**但测试件是合成音，只证明链路通，不证明真人准确率** —— 那半条得他自己录。

出网：**电脑 241,357,257 B（本项目第一次真下载东西），手机零出网**。设备上只写了那三份模型（644 root:root，`du -sb` 与逐份相加一致）
加 `/tmp` 里两个测试件（跑完自删、复点 No such file）；`/root` 里本轮新推的探针副本逐个 `head -2` 确认是我这轮编号才删，
删后复点 `.sh` = **7**（那 7 份是往轮部署的正式工具，一份没动）。新增三份常驻工具：`tools/run-probe.sh`（送探针自带收尾：强制 `MSYS2_ARG_CONV_EXCL`、
统一去 CRLF、跑完删两份副本并当场数残留）、`tools/fetch-sensevoice.sh`、`tools/push-sensevoice.sh`，另加 `tools/make-voice-wav.ps1`（UTF-8 带 BOM，PowerShell 5.1 才不吞中文）。
文档：RUNBOOK 加 14.21 整节（1,746 → 1,862 行），本文件加状态 24 与这段、下一步第 14 条结掉。
**这轮没做**：App 里那两步（插件关再开、真人录一句）、`inspect()` 重启后是否真进 `standby`（只到读代码得推断）、fp32 那档 937,617,178 B、
真人声准确率、`MODIFY_AUDIO_SETTINGS` 缺失会怎样、竖屏窄栏布局；没动 KernelSU/susfs、没绕锁、没 reboot、没 npm install。

**2026-10-21 凌晨再收一格（状态 25，他那句"以后难道全得通过电脑下载吗"→ 量出病在解析，并在手机上把解析补好了）**
四层分开测（读数 `downloads/p26.txt`–`p33-sync.txt`，全节在 RUNBOOK **14.22**）：配置层 = resolv.conf 三条 nameserver + `timeout:2 attempts:2`、
无 proxy 变量、**IPv6 默认路由 0 条**；解析层 = **UDP 53 这台机基本废**，没钉过的域名六条全在 `10,011–10,015 ms` 给空且退出码仍是 0，
被墙那类倒给得出**假答案**（`huggingface.co` ⇒ `104.244.46.9` 与带 `face:b00c` 的 v6，DoH 回 `157.240.8.36`）；
建连层 = 拿真 IP 直连 443，境内 `301/302/200` 全有响应，境外两种 `000` 形状不同（npmjs 8 秒窗到顶 vs raw **0.118 秒**就失败）；
真字节层 = apt 侧 tuna 的 noble Release **Range `206` 落 1,024 B**、npm 侧跟 302 到 cdn 落 **2,774 B 且 tar 解出 3 个成员**。
⇒ **病在解析不在出口**，所以答案不是"以后全得靠电脑"。

手机侧唯一干净的解析路是**阿里的 DoH**（`https://223.5.5.5/resolve`；`1.1.1.1` / `8.8.8.8` 那两条 6 秒全空），
这条路是拿错的参数撞出来的 —— `p26` 我打 Cloudflare 式 `/dns-query`，回 `no 'dns' query parameter found`，
**那句失败恰好证明 TLS 通了、对端回话了**。做成了常驻工具 `tools/doh-hosts.sh`（6,293 B，`--check` / `--sync` / `--revert`；
清单分"实测连得上的才钉"与"钉了也连不通的只报不写"两摞；写之前逐字节备份并比 sha256 才动笔；
钉完那一步的验收**故意不带 `--resolve`**，不然自欺）。跑一遍的读数（`p33-sync.txt`）：备份
`/root/.dsh/hosts.bak.20261020-161513`（sha `cbdb3af9…`）、**新增 5 / 本来就在 9 / 问不到 0**、
不带 `--resolve` 复测 hf-mirror `200` / gitee `200` / aliyun `301` / www.modelscope `302`；hosts 从 22 行非注释变 27（机上复点 26 条数字开头 + 1 条 `::1`）。

分来源裁决：**apt 能**（源本就配 tuna ubuntu-ports）、**npm 能**（钉 npmmirror 后包体落盘解得开）、
**GitHub 能但慢**（`github.com` `676,496 B/30s`、`codeload` `790,533 B/30s` ⇒ 约 22–26 KB/s；chroot **没有 `git`**，装要走 apt = 等他点头）、
**HF 那类模型仍不行、且原因不在解析**（hf-mirror 解析与连接都通，但它 302 落点 `cas-bridge.xethub.hf.co` 在手机上
`302 / size=0 / 10.57s`；ModelScope 三个猜测仓库名全 `404` = **我没验到**，不是"国内没有"）。

改口四处，都写在原地：① `p27` 丁那句"npm 拿不到包"读的是**没跟转的 302 正文 80 B**；② `p26` §3 那发 `github.com 000`
是**窗口设了 6 秒**，30 秒窗同一 IP 拿到 676,496 B；③ `p31` 末尾"出网合计 0 B"是 `tot` 计数器在子 shell 里丢的假读数，
逐行相加是 **1,726,377 B**；④ 我自己工具里那行"（DoH 给了 N 条候选）"**每条少报 1**（`printf '%s'` 不带换行而 `wc -l` 数换行），
已改 `echo` 并推回机上（本地/机上 md5 同 `568c093f…`），**但那一行没能复现**（14 条全在清单里，`--sync` 不再进那行）⇒ 这半条只到读代码。
另有一条观察值得留着：`cdn.npmmirror.com` 钉的 `223.109.3.139` 已不在 DoH 当时给的 16 条里，可那次跟着 302 仍 `200 / 2,774 B`
⇒ **"不在当前答案集合"只说明钉旧了，不说明连不通**；判据要按在不在集合里，不能按是不是第一条。

出网：手机侧 1,726,377 B（全是我故意压带宽的三发）+ KB 级取样；**电脑侧这轮零下载**。
设备写入只有 `/etc/hosts`（追加 5 行，有逐字节备份与 `--revert`）与 `/root/doh-hosts.sh`（6,293 B）两处，
chroot `/root` 的 `.sh` 从 7 份变 8 份（新增这份是正式工具，与那 7 份同性质）；探针副本跑完即删。
文档：RUNBOOK 加 14.22 整节，本文件加状态 25 与这段、下一步新增第 16、17 条（要不要在机上装 `git`、要不要把 `--check` 挂周期），
并给第 6 条那个"连不上就先跑电脑上的 pin-hosts"补了一个不依赖电脑的前置。
**这轮没做**：`apt install git`、手机上真 clone 一个仓、把 `--check` 做成周期跑（IP 会漂，钉过的条会悄悄地坏）、
替他点 App 那两步、动 KernelSU/susfs、绕锁、reboot。
