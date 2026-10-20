# 三家社区 App 方案精读 + 与我们这条 chroot 路线的对比

> 对象（都是 2026-08 中旬起号的仓库，到我看的时候都还在活跃推送）：
> · `DSH-APP/DSHA` · `Soodok/Deepseek-Harness-Local-Android` · `woaiys3/deepseek-harness-android-app`
> 与本文另两份精读的关系：`reference/android-community-routes.md` 讲的是 **Termux 命令行路线**那两家
> （Vengisk / FunnelCakes），这三家讲的是 **装个 APK 就能用** 的产品形态。同一道题的两种解法族。

## 口径（先说清我读了什么、按什么证据说话）

**样本**：三家 `main` 分支 tarball，2026-10-20 通过 `codeload.github.com` 取得（直连 github.com 在这台 Windows 上
`http=000`，走不通）。解包在 `reference/gh-3p/`，包与 API 原文在 `downloads/gh3/`，校验和 `downloads/gh3.sha256`：

| 仓库 | tarball 字节 | sha256 前 12 位 | 解包后占用 |
| --- | --- | --- | --- |
| DSH-APP/DSHA | 32,875,642 | `ed41227d13b2` | 66 M |
| Soodok/Deepseek-Harness-Local-Android | 11,666,166 | `22fce1696527` | 14 M |
| woaiys3/deepseek-harness-android-app | 8,204,504 | `814314f006ec` | 20 M |

**证据分三档，本文每条结论后都带标记**：

- **【码】** —— 我读到源码原文，能给出 `文件:行`，这条最硬。
- **【文】** —— 只在 README / docs / issue 里看到，代码里没找到对应实现；当作"他们这么说"，不当事实。
- **【疑】** —— 我没能验证，或读数自相矛盾。

**2026-10-20 补第四档【史】**：DSHA 与 woaiys3 两仓的上游真提交历史后来到了本地（`reference/gh-3p/DSHA-hist`
627 条 / `dsh-android-app-hist` 298 条，blobless），凡"他们什么时候把引擎追到哪一版""某个 release 资产被没被换过"
这类**只有时间线能回答**的问题，我现在能引 commit sha 而不是引 README。补读出来的五条在第六·补节，
其中两条把本文原话改了口。**Soodok 那仓仍只有解包件**（他这轮明确先不看）。

**最重要的一条口径**：**这三家我一个都没跑过** —— 没装 APK、没上机、没有真机读数。这份报告是纯代码 + 文档阅读。
所以下面凡是"能不能用、性能、稳定性"，我只能说**它的代码路径指向哪儿**，不能说**它在真机上什么表现**。
我们自己的路线有 34 PASS/0 FAIL 这类实测数字，对比时要认清：这一列上三家都是空的。

---

## 一、一屏结论

数字来自 `downloads/gh3/*.api.json`（GitHub API 原文，2026-10-20 抓取）。
star 数当天就在动：他给我那句说"1708 颗星"，API 抓到 1,720，而 DSHA 自己主干最新那条自动提交（`fe07a02` 2026-10-20）
标题写的是 1736 —— 三个数按时间排都对，**别把哪个当定值**。

| | DSH-APP/DSHA | Soodok/…-Local-Android | woaiys3/…-android-app | **我们（dsh-mobile）** |
| --- | --- | --- | --- | --- |
| ★ / fork | **1,720** / 101 | 296 / 20 | 519 / 37 | — |
| open issues | 75 | 10 | 30 | — |
| 主语言 | Java | **Kotlin** | Java | 无 App（脚本 + 一个 16 MB WebView 壳） |
| License | MIT | MIT | MIT | — |
| 创建 | 2026-08-14 | 2026-08-26（最晚） | 2026-08-16 | — |
| 最近推送 | 10-19 18:43Z | 10-19 03:43Z | 10-18 01:28Z | — |
| 仓库大小 | 63,655 KB | 11,892 KB | 13,643 KB | < 1 MB（不含 rootfs） |
| 官方站点 | 空 | 无 | `https://dshaa.xin` | — |
| 跑的 dsh | `0.2.0-rc.2`【码】`Constants.java:42` | `0.2.1-rc.2`【文】README:24 | `0.2.1-rc.2`（v1.20.1）**【史】**`26be089` 2026-10-18 提交消息，另【码】四档 overlay；轨迹 0.1.7-rc.1→0.2.0-rc.2→0.2.1-rc.2 | **0.2.1-rc.2**（实测在跑） |
| Linux 从哪来 | **APK 内置 Ubuntu 24.04 noble arm64 rootfs**【码】 | **不要 Linux**：bionic 上裸跑【码】 | **不要 Linux**：bionic 上裸跑【码】 | root + **真 chroot**（1.7 G Ubuntu 24.04） |
| 要不要 root | 不要 | 不要 | 不要（Shizuku/ADB 是可选通道） | **要**（KernelSU，全程 Enforcing） |
| 沙箱档位 | `danger-full-access`【码】 | `danger-full-access`【码】 | 名义上不是、实际是【码】 | `workspace-write` + 我们自己写的真围堵 runner（34/0【码】） |

**一句话概括三家**：DSHA 是"把一整台 Ubuntu 打进 APK"，花钱买省事；Soodok 是"一分钱一分货地硬啃 Bionic"，
把每一个原生模块逐个 stub 掉；woaiys3 是"把上游 JS 直接 tar 覆盖重打补丁"，最激进也最脏。
**三家的最终档位都落在 `danger-full-access`** —— 这不是巧合，是同一堵墙。下面第四节是这份报告的主菜。

---

## 二、根本分野：把 Linux 弄进手机的三种办法

这道题只有三个变量：**bash 谁提供 / 原生 .node 模块怎么加载 / 文件语义对不对得上 glibc**。三家各选一档：

### DSHA：APK 里装一整个 Ubuntu，用 bxroot/proot 跑

**【码】** rootfs 不是下载的，是从 APK 自己的 asset 里解出来的 ——
`ManagedRuntimeAssets.java:126` 直接 `apk.getEntry("assets/offline-rootfs.layout")`，配
`ColdBundleExtractor.java:62`（"split-runtime-v1" 布局判定）。README:119 说"Ubuntu 24.04 (noble) arm64 打进 APK，
无网也能完成环境部署"，README:261 老实标了代价：**APK 273.10 / 345.27 MiB**。
README:284 的架构图：`Ubuntu 24.04 arm64 · Node.js 24 · pnpm 10`。

引擎层 `ContainerRuntime.java` 是一个接口 + 三个实现：`Proot`（:50 起，Termux proot，APK 内置）、
`Bxroot`（**当前默认**【码】`EngineSpec.java:43` 那句 `return prepared(requested, new BxrootRuntime(context), "DEFAULT_BXROOT")`，
`ContainerRuntime.java:10` 注释也对得上："由冻结 EngineSpec 统一选择 bxroot 或 proot"）、以及 **`Proroot` 已被 `@Deprecated`，
:166 的注释写得很直白**：
"历史诊断名称保留；build172 不含可执行 proroot 实现" —— LD_PRELOAD 那条老路他们试过并正式放弃了。
这一点很有价值：**它把 `android-community-routes.md` 里我记的"proroot 是某家的替代引擎"升级成了"上游实践者已经放弃它"**。

补丁层：`assets/runtime-patches.json` 实测统计 **active 25 条 + specialized 5 条 + retired 3 条**（我按 JSON 结构数的，
不是 README 说的数），每条挂一个 asset 和一个目标 `module` 路径，部分带 `markers` 做幂等断言。
这是三家唯一有"补丁台账"这件事的仓库。

**它的界面为什么不缺东西 —— 一条对我们直接有用的读数**：DSHA 不重写前端，**它渲染的就是那个网页本身**
（`assets/web-integration/manifest.json`【码】是一份内容脚本清单，`matches` 写 `http://127.0.0.1/*`，
`startup-relay.js` 在 `document_start`、`page.js` + `content.js` 在 `document_end`；
这份清单还引用了一个 `gecko-compat.js`，**而仓库里找不到这个文件**【疑】，大概是构建期生成 —— 他们另有 Gecko 那档 flavor）。

真正值钱的是他们**打补丁的形状**。以 `assets/pdf-compat-patch.json` 为例【码】，一份补丁声明里同时写了：
目标上游模块（`@deepseek-ai/dsh-client-ui-sidebar-documentpreview/lib/client.pdf.js`）、
**定位用的原文锚**（`mainBefore` 是一整串上游源码原文，`resourceBefore` / `resourceAfter` 同理）、
要前置进去的资产（`asset: web-integration/es-compat.js`），以及最关键的一行 ——
**`dshVersion: "0.2.0-rc.2"`**。也就是说补丁不是"盖上去就完事"，是**钉着上游版本、靠原文锚定位**的：
上游一改，锚对不上就该响亮失败，而不是静默少打一层（**这一条正好是我们那个"polyfill 打在 `dist/index.html` 里、
一升级就被冲掉"的老遗留问题的解法形状**）。`runtime-patches.json` 里部分条目还带 `markers` 做幂等断言，同一思路。
另有四份补丁用 `prependAsset`【码】：`deepseek-messages-compat-patch.json`、`language-patch.json`、
`session-interaction-patch.json`、`sidebar-layout-recovery-patch.json`。

**每个资产的 sha256 都进了台账**：`runtime-descriptor.json` 里 `web-integration/es-compat.js` = `a17b4cce…`、
`compat.js` = `dc935b39…`，和 `es-compat.inputs.json` 那个总 `sha256` 对得上（我核过一致）。
而 `es-compat.js` 头部原文是 **"DSHA ES compatibility | core-js 3.50.0 | MIT"**，旁边躺着 `core-js.LICENSE` ——
**他们把"手机内核太老、跑不动上游新前端"做成了一个带校验和、可重放的兼容包**。

顺手捡到一条硬数据【码】：同一份 `pdf-compat-patch.json` 里那句内联修的注释原文是
"**WebView 116 把非特殊协议的主机放在 pathname**" —— 他们**针对 Chromium 116 档 WebView 的一处 URL 解析差异做内联修，
而这份补丁干的是"给上游模块前置兼容包 + 内联修"两件事**，也就是说 **116 档内核上他们仍然带着兼容层**。
这条直接影响我们晚上那个决定：**"内核新一点就可以把兼容层拆掉"这个念头别默认成立**。


顺带一条对上号的线索【疑】：`LICENSE` 里写的版权人是 **`qiannianhuanxiang`**，而仓库在 `DSH-APP` 组织下 —— ——
`android-community-routes.md:11` 我从 Termux 那两家的 issue 区挖到的正是 `qiannianhuanxiang/DSHA`
（当时记的是"安卓启动器 APK"）。所以这大概率是**同一个项目搬进了组织号**。我没核对两边 release 是否连续，
这条只当线索，不当结论。

### Soodok：不装 Linux，Bionic 上裸跑，靠 targetSdk 28 开门

**【码】** `app/build.gradle.kts:20-22` 注释原文："**关键决策：targetSdk 28 —— sideload 分发，豁免 Android 10+ 的
W^X 限制**"，:14 补了半句"compileSdk 仅决定编译期 API 可见性，不影响运行时行为（targetSdk=28 才是生效阈值）"。
这是整个仓库最关键的一把钥匙：**Android 10+ 对 targetSdk ≥ 29 的应用禁了 exec 掉进可写目录（W^X）**，
而 node 生态里到处是"写个 .so/.cjs 然后 require/exec"。把 targetSdk 钉回 28，这一整类失败当场消失 ——
代价是只能 sideload 分发，不能上 Play。**我们没有这个问题**：chroot 里 exec 的是 apt 装好的二进制，
`/phone` 上的写也不落到 exec 路径上。

runtime 从哪来：`scripts/collect-termux-runtime.sh:9-10,47-52` 把 Termux 的 `nodejs-lts` deb 解出来、
重定位进 APK assets。也就是说 **bionic 版 node 是 Termux 编的**，他们只搬运不编译。
原生 addon 一律假件（`--expose-internals` + `createRequire` 顶掉内置、koffi 换成 inert Proxy、
自带 `dsh_pty.c` 补 pty、rg 用 android 包、sharp 只走 wasm）。

**上限在哪**：`AgentContextSeed.kt:321` 明确禁止 glibc/native 包，`npm rebuild` 这条路在他们那儿是死的 ——
**任何需要现场编译原生模块的项目，在这个方案里做不了**。README:197 系统要求"Android 8.0+（WebView ≥ Chrome 85）"。

### woaiys3：同样 Bionic，但把上游被改过的那些文件按原路径摆成一档一档，装的时候整片盖上去

node 是 bionic v26，dsh 树解到应用私有目录，启动命令直接
`node --expose-internals bin.js web --host 127.0.0.1 --port 3080`【码】`MainActivity.java:3994-3996`
（端口跟我们一样是 3080，这个撞车挺有意思，说明大家都照抄上游默认）。targetSdk 同样钉 28
【码】`AndroidManifest.xml:8`：`minSdkVersion="24" targetSdkVersion="28"`（compat 变体 minSdk 26）。

补丁形态是三家里最"物理"的：`dsh-patches/apply.sh:24` 就一句
`( cd "$SRC" && tar cf - . ) | ( cd "$DST" && tar xf - )` —— **按原路径把文件盖到已安装的 JS 上**。
四个档位并存：`overlay/`（0.1.5-rc.2）、`overlay-017/`、`overlay-020/`、`overlay-021/`【码】目录实测。

**这里我先改一句自己写错的话**：我初稿写"每一档都是一整棵 `node_modules/@deepseek-ai/**` 的副本，
仓库体积绝大部分是上游代码的第二三四份拷贝" —— **数过文件之后这是错的**。实测每档只装**被改过的那几个文件**
（按上游路径摆好）：`overlay/` **103 个文件 / 1.5 M**、`overlay-017/` 12 个 / 720 K、`overlay-020/` 17 个 / 960 K、
`overlay-021/` 18 个 / 1.2 M，全仓总共 266 个文件。仓库 13,643 KB 的绝大部分其实是**那个 11,694,592 B 的 `legacy-patch/esbuild.exe`**。**这个形状比我初稿说的干净**：带的是差集不是全树。
好处是升级只需换档；坏处仍然是**每条 fix 要在最多四个地方各打一遍，没有任何机制保证四档一致**。

### 对照表

| | DSHA | Soodok | woaiys3 | 我们 |
| --- | --- | --- | --- | --- |
| bash 来自 | Ubuntu 的 bash（proot 里） | bionic 的 sh + dsh 自带 bash 插件（打桩后） | 同左 | **真 Ubuntu bash** |
| 原生 .node | rootfs 里 glibc，随便用 | 全部 stub | 全部 stub / 自建 | **glibc + arm64-gnu 在位** |
| W^X | 不需要绕（不 exec 可写目录） | **targetSdk 28** | **targetSdk 28** | 不需要绕 |
| 首次安装代价 | APK 273/345 MiB | 装完即用 | 装完即用 | **我们付 1.7 G rootfs，一次付清** |
| 需不需要 root | 否 | 否 | 否 | **是** |
| 上限 | 高（完整 apt） | **中**（native/rebuild 死路） | **中**（同左） | 最高（就是台 Linux） |

**结论**：`android-community-routes.md` 里我写过那句"他们 8 成补丁是在还 Bionic 的债，我们那 1.7 G rootfs 把这笔债买断了"，
这三家读完，那句话不但成立，而且更硬 —— **DSHA 为了买断这笔债，付了 273 MiB 打进 APK**；
两家不肯付的，就在代码里一条一条还。我们靠 root 买断，付的是"这台设备必须 root 且不能给别人"。

---

## 三、跑的是不是真 dsh、上游升级怎么活下来

三家都是**真引擎**（不是"照 dsh 的协议自己写一个"），这条我先给它们背书 —— 判据是我在每家里都读到了
上游包名/文件路径的实物：DSHA `assets/builtin-plugins/*/package.json` 依赖 `@deepseek-ai/dsh-*` `0.2.0-rc.2`【码】，
Soodok `EngineConfig.kt:481-508` 生成的 YAML 覆盖的是上游插件 `id: sandbox-policy / approval / permission`【码】，
woaiys3 overlay 里直接躺着 `@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-bash-local/lib/index.js`【码】。

**升级策略三档，差别很大**：

- **DSHA：钉版本 + 台账 + 审计。** `runtime-patches.json` 顶层写 `dshVersion: "0.2.0-rc.2"`【码】，
  README:73 说明源码在 tag `v0.2.0-rc2`，版本码 170、Ubuntu 基础环境编号 10 两条独立线（README:125"界面更新不重建环境，
  普通 dsh 更新不递增基础版本"）。还有 `docs/audits/build154/`、`build156`（187 条 issue 处置台账）和 E7E3 签名纪律。
  **代价是它停在 0.2.0-rc.2，比我们低一版。**
- **Soodok：跟主干跟得最紧，用覆盖层跟。** `EngineConfig.kt:481-508` 把 `mode: danger-full-access`、
  `approval policy: never`、`defaultPreset: danger-full-access` 写成 YAML 由 `--patch` 注入，:510 注释
  "Critical host services are repeated in this last overlay deliberately"——**同一 id 后到的整行替换前一行**，
  这是他们对抗 profile bundle 顺序的手法。跟得上版本的代价是这套覆盖层把安全语义整个压平了（见第四节）。
- **woaiys3：四档并存，靠 `FORCE_OVERWRITE_PREFIXES`（apply.sh:102-127）+ `UserPatches.java:23-45` 重放。**
  升级后把用户补丁再打一遍。这是最能在"上游又改了"之后活下来的写法，但也是最容易把 fix 打成不一致的写法。

**给我们的一条直接可用信息**：0.2.0 起 `peerDependencies` 校验会让不匹配的插件**静默失效**
（woaiys3 `CHANGES.md:795-797` 记的）。我们 `app/` 那个壳和 `config/dsh-env` 以后要挂任何 dsh 插件，
得把这条列进装插件的检查项：**插件没生效不会报错，只会消失**。

---

## 四、沙箱与权限档位（本报告主菜）

**三家最终都跑在"引擎完全不围"的状态，而且三家对这件事的表述质量差别极大。我们上一轮做的
`dsh-unshare-run` 正好是这条空白上的第一个实现。** 逐个看，都有源码。

### DSHA：明说"我没有强沙箱"，改用审批闸门

`ConfigStore.java:455` 默认值字面就是 `"danger-full-access"`（`text(Constants.KEY_PERMISSION_MODE, "danger-full-access")`，
:630/:703 读档时也拿它当 fallback），`PermissionMode.java:5` 同源。他们不硬撑：仓库里自陈
**"工具审批 ≠ 强沙箱"**，并在 `assets/destructive-policy/index.js:10-26` 自己写了一套 fail-closed 的危险命令 JS 闸门。
另有 AndroidKeyStore 静态加密 key（`KeyVault.java:26-41`，AES/GCM）。

**评级：诚实**。它没解决围堵，但它没有假装解决 —— 而且它把"审批"当成一门正经工程做（独立策略模块 + fail-closed），
这是我们目前完全没有的一层：我们靠 `DSH_PERMISSION_MODE=workspace-write` 钉档位 + runner 围文件系统，
**命令级审批闸门我们没有**。

### Soodok：撞上我们同一堵墙，然后写注释宣布绕过去

`EngineConfig.kt:406-414` 的注释是这一节最值钱的一段，我把关键原文抄下来：

> dsh 的沙箱后端是 Linux landlock / macOS seatbelt，**Android 上两者都不存在** → sandbox-policy 默认 `read-only`：
> read-only/workspace-write 下 bash 工具直接拒绝执行（模拟器实测原文：
> `sandbox mode "workspace-write" ... refusing to run the command unconfined; no sandbox backend usable on host`）
> → AI 一条命令都跑不了；本项目的安全边界是 App 自身的权限模式（Normal 沙箱 / Shizuku ADB 级 / Root）
> 与 su 闸门（applySuGate），而非引擎内部沙箱，故置 danger-full-access。

**那句 `no sandbox backend usable on host` 和我们设备上一字不差** —— 同一条上游拒绝文案。
区别只在：他们说"所以安全边界挪到 App 层"，我们把"所以引擎里那条围不住的路自己补上"。
:481-508 还把 sandbox-local 的原生 import 剥掉，`approval: policy: never` 一并写死。

**评级：合理但不彻底。**"挪到 App 层"这个选择本身讲得通（App 沙箱 + 三级权限 + su 闸门确实是真边界），
但它对 dsh 内部那套"读文件、写文件、跑命令"的工具集**一个字节都没围**：agent 一旦拿到 bash，
在它自己的 UID 下就是 `/data/data/<pkg>` 全可写全可读，包括它自己的会话与凭证目录。

### woaiys3：谎报 —— `sandboxMode` 返回 `workspace-write`，同时注释承认自己从不围

这是**整个调研里最严重的一条发现**，我读的是 `overlay/lib/.../dsh/node_modules/@deepseek-ai/dsh-bash-local/lib/index.js:70-86`：

```js
 * ⚠ v1.15 订正：本执行器只 inject subprocess，**从不调用 ctx.sandbox**，所以
 * sandbox 服务是否启用与 bash 无关。旧版本注释声称"真正需要 koffi 的 sandbox
 * 执行服务依旧保持禁用"——**该判断是错的，并且已经造成严重后果**：
 * 禁掉 sandbox 会让 ptc-runtime 永久 pending，进而使所有 agent preset 会话
 * create/resume 失败。sandbox 现已恢复启用。
 */
get sandboxMode() {
    return "workspace-write";
}
```

上一段注释（:70-78）还交代了为什么非要返回这个值：0.1.7 的 `dsh-permission-presets` **在构造时检查
`ctx.shell.sandboxMode`，undefined 就直接抛** "the mounted bash executor does not confine (no sandboxMode)"。
他们的解法是 —— **让它看起来 confine**。而且"恢复启用 sandbox"那句里的"启用"只是让那个 koffi 服务被 import 起来，
`ctx.sandbox` 依然没有任何调用点。

**为什么这条比 Soodok 危险**：上游那句检查说明 **dsh 生态把 `sandboxMode` 当作可信声明在用** —— 插件、
审批预设、UI 胶囊、会话台账都按它决定"要不要逐条问用户"。一个谎报 `workspace-write` 的执行器会让整条链
以为受限，于是**把审批也一起放松**。上游自己那个"配了 runnerCommand 就把 `enforcement` 直接记成 `full` 且不探测"
（`reference/dsh-sandbox-local-index.js:311-321`）是同一类问题的**轻度版本**；这里是重度版本。

三家合起来把这道题的三种答法都占了：**关掉（Soodok）/ 不碰（DSHA，明说）/ 谎报（woaiys3）**。
第四种 —— **真围住并且自己验一遍** —— 三家都没有。这条我们有：`scripts/verify-unshare-run.sh` 34 PASS / 0 FAIL
（读数在 `downloads/verify-runner-3.txt`，过程在 RUNBOOK §14.11）。

### 我们相对这条轴的位置（把话说全，不只说赢的部分）

- 我们的 runner 只围 **文件系统的可写面**（`/` 下顶层目录逐个 bind-remount 只读，工作区叠回可写）。
  **命令级审批一层我们没有**，DSHA 那套 destructive-policy 是这一层的正面样本。
- **围堵目前还没接线**：runner 做完了、验过了，但 `runnerCommand` 还没进 `profiles/web/cordis.patch.yml`
  （没接是因为一接就要重启服务、会换掉他手机里那条入场链接，这轮他让我先停在"结果 + 记录"）。
  所以"我们有真围堵"这句，严格讲是**能力已就位、生产路径上还是 `workspace-write` 名义档位 + 上游自动那套**。
- 我们有一条和 woaiys3 一模一样的坑，只是方向相反：`enforcement: "full"` 是**配置出来的，不是探测出来的**
  （:318），而 `:320` 那套已配置 runner 的失败规则**没有 exit-code 闸门**（对比 :239-242 的 windows-acl 规则有
  `allowedExitCodes:[127]`）—— 意味着 runner 自己打出的任何一条提示行，只要前缀撞了致命签名，
  就会被判成整个沙箱失败。我们上一轮就是这么翻车又爬出来的（`dsh-unshare-run-notice:` 前缀分裂，RUNBOOK §14.11 的四个隐藏 bug）。
- 还有一条**三家全都在、我们也有的共同前提**：这台内核 `CONFIG_USER_NS` / `CONFIG_PID_NS` / `CONFIG_SECURITY_LANDLOCK`
  全是 `not set`。见第九节。

---

## 五、能抄的东西（按"改动成本 / 收益"排，全部带出处）

| 借鉴点 | 出处 | 我们现在的情况 | 成本 |
| --- | --- | --- | --- |
| **Android 文件系统容忍三补丁**：`link` 失败退 `rename`；`open("wx")` 保留 EEXIST；目录 fsync 吞 EINVAL/ENOTSUP | woaiys3 `dsh-bash-local/lib/index.js:3264-3272`、`:2055-2066` | **没做过**。我们工作区 `/phone` 是 `/data/media/0` 的 bind，**同一类 FUSE 语义**，只是还没撞上 | 低（三处小补丁） |
| **一次性 token 不能被健康探测吃掉**：从 stdout 解析、只用一次 | DSHA `DshAuthUrl.java:22-30`；woaiys3 `MainActivity.java:6098`（注释叫"坑⑦写死的纪律"） | 我们踩过同款（token 每重启轮换，接线一次就要换一条入口 URL）——**但没写成纪律**，只写在 RUNBOOK | 极低（把纪律写进脚本断言） |
| **pidfile 先写再 `exec`** + stop sentinel 区分"用户主动停"和"崩了" | DSHA 同轴；woaiys3 `MainActivity.java:4100` `engineStoppedByUser` + `lastRespawnAt` 20 s 防风车 | 我们有 pidfile，**没有 stop sentinel，也没有 watchdog** | 中 |
| **`--port 0` 让内核选端口**，避免端口撞车 | DSHA | 我们写死 3080（woaiys3 也写死 3080 —— 我们和他家在同一台机上会打架） | 低 |
| **凭证静态加密**（AndroidKeyStore AES/GCM，密钥不出硬件） | DSHA `KeyVault.java:26-41` | 我们是明文放 chroot 内文件；**这是"手机丢了怎么办"这条问题的现有答案** | 中 |
| **把高密度环境事实预写进 `$DSH_HOME/AGENTS.md`**，让 agent 不用自己试 | Soodok `AgentContextSeed.kt:159-332` | 我们**完全没做**，agent 每次自己踩 chroot/PATH/工作区这些坑 | 极低，收益最高 |
| **插件台账 + 补丁 markers 幂等断言** | DSHA `runtime-patches.json`（active/specialized/retired 三态 + `markers`） | 我们补丁是散在 `config/` 与 `scripts/` 里的，无台账 | 中 |
| **`peerDependencies` 校验让插件静默失效** | woaiys3 `CHANGES.md:795-797` | 装插件检查项里没有这条 | 极低 |
| **AbortSignal.any 之类 polyfill 在老 WebView 上必需**（Chromium 91 白屏） | woaiys3 `legacy-patch/polyfill.js:44-55` + issue #38；**DSHA 侧另有硬数据**：`pdf-compat-patch.json` 那句注释写着"WebView 116 把非特殊协议的主机放在 pathname"【码】⇒ **116 档仍然要挂兼容包** | 我们**独立踩过同一个坑并自己修好了** —— 现在有了两家独立证据 | 0（已解决），但别据此以为"内核新一点就可以拆掉兼容层" |
| **补丁要"钉版本 + 原文锚定位 + 校验和台账"**，别静默少打一层 | DSHA `pdf-compat-patch.json`（`dshVersion` + `mainBefore` 原文锚 + `asset`）、`runtime-descriptor.json` 逐资产 sha256 | 我们的 polyfill 直接改在 `dist/index.html` 里，**上游一升级就静默消失** | 中（把注入改成声明式） |
| **ELF `e_machine` 双重断言**（推上去的二进制先验架构，别跑起来才发现不对） | DSHA 工具链侧 | 我们靠人肉记忆 | 低 |
| **备份做成独立 runtime**（v5 快照 + recovery runtime，坏了另一套起） | DSHA `backup/ConfigurationSnapshots.java` 等 | 我们是文件级备份（逐字节副本） | 高（先不做） |

---

## 六、工程成熟度与仓库卫生

**DSHA（最像产品）**：CI 完整、343 个单测（`app/src/test/**`，如 `PermissionModeTest.java`、`WebLaunchCommandTest.java`
证我在盘上找到）、`docs/audits/build154` 与 `build156`（187 条处置）、`docs/adr`、README:69 公开证书指纹
`e7e3a3…a53f5` 和"同签名覆盖安装"的验装方法。四档并存的东西也有：`standard` / `low` 两个 flavor（Gecko 143 那条）。
**唯一一处我读不到的宣传**：README 里"零额外 token 多模型协作"这类话，我在代码里没找到对应实现 ——【文】，按宣传处理。

**Soodok（工程密度高，仓库卫生差）**：
- 单测 0。
- **仓库里躺着他真机的 uiautomator dump（`_u*.xml`）和根目录 `_settings_head.xml`** ——【码】文件在包里，
  这类 dump 通常含包名、活动名、用户内容片段。这是不小心把调试现场提交了。
- README:35 的"APK 约 144 MB"**只对 v1.3.0 成立**；v1.4.0 实测 235,652,373 B（约 224.7 MiB）——【疑→码】
  README 数字没跟着版本走，我按 release 元数据核对过。
- **同一版本号重复发布 3 次**（release 列表），装过的人分不清自己手上是哪一份。
- `WAKE_LOCK` 声明了但代码里没用；**`AndroidManifest.xml` 里没有 `BOOT_COMPLETED`** —— 我 grep 无命中，
  也就是说他不做开机自启，**这条上我们比它完整**（我们有 `/data/adb/service.d`，虽然还没验过重启）。

**woaiys3（迭代最快，纪律最松）**：
- **同一个 Activity 有两份、各一万一千行**【码】：`android-app/src/com/deepseek/harness/MainActivity.java` **11,374 行**、
  `android-app/compat/MainActivity.java` **11,142 行**（**本文引的行号除特别说明都是 compat 那份**，
  他两个变体各一份，同一处逻辑要在两处各改一遍）。一个文件里塞了控制台 UI、引擎 spawn、watchdog、token 解析、存储路由、主题。
  这不是 WebView 壳，是原生控制台，功能确实多，但没人维护得住。
- CI 没有；测试只有一个、且引用了仓库里不存在的目录；**11,694,592 B 的 `esbuild.exe` 直接进了库**
  （它出现在 main 分支的压缩包 `legacy-patch/` 里，按 codeload 的口径即"这就是提交的内容"）。
  **我初稿在这里还多写了一句"而它自己写在 `.gitignore` 里"—— 数过了，全仓只有一份 `.gitignore`，
  里面既没有 `exe` 也没有 `esbuild`，那条是错的，划掉。**
- **同一个包里补丁只打了一半**【码】：`dsh-session-persistence-jsonl/lib/index.js:2974` 有那段
  "Android 适配：/data 分区不支持 hardlink（link() 直接报 EPERM/EXDEV）"的 link→rename 补丁（该文件里 `rename` 出现 5 次），
  而**同目录那个 11,654 行的 `worker.cjs:11502` 还是裸的 `await internals.fs.link(staged, currentPath)`** ——
  并且这个 `worker.cjs`（0.4 MB）**就躺在 overlay 里带上了**，不是没带，是带上来没改。
- **`DSH_PERMISSION_MODE` 在整个仓库里搜不到** —— 他家的档位不是钉住的，是补丁出来的。

---

## 第六·补 上游真历史到手之后：新增五条，其中两条改本文的口（2026-10-20）

取得方式与链路账在 RUNBOOK 14.13（一句话：`--filter=blob:none --no-checkout`，9 秒落地；按深度切的那条路
被 20 MB 不可压缩的 asset 堵死了）。两仓 HEAD 逐字等于两份快照出处提交里记的上游 sha
（`fe07a028673a4c92cc2f7a773a36883ac11d61ff` / `98162a23b39eeeb75b8d4608b3e773bbb13be43d`）
⇒ **我读的那两棵树确实是上游主干尖端**，不是某个旧镜像的缓存。

**① woaiys3 的引擎版本 `0.2.1-rc.2` 从【文】升到【史】，且追版轨迹拿到了**【史】。原先只按 README:46 记了一句
"他们自己说跟到 0.2.1-rc.2"；现在提交消息直接写着轨迹：
`0.1.7-rc.1`（v1.15.2）→ `8c153e7` 2026-10-01 v1.17.1"内核升级 DSH 0.2.0-rc.2 + 0.2.0 RPC 适配 + 插件 peerDeps 闸门修复"
→ `26be089` 2026-10-18 v1.20.1"同步源码（**内核 0.2.1-rc.2** + 会话 v4 兼容 + 五插件改进）"，
三条都是当月真实提交而不是一句宣传话 ⇒ 它那四档 overlay 的补丁对象**确实就是我们设备上这一版**
（第五节"抄它的 FUSE 语义容忍"那几行，原先补丁内容本身是【码】、但"对我们这一版有效"只能靠 README 的版本宣称撑着，
现在这半也有提交做凭了）。
同一句里"会话 v4 兼容"和我们自己取证时数出来的 `session.v4.jsonl.zstd` 是同一件事（见 PROGRESS 遗留问题那条 zstd 多帧坑）——
原先只在文档里看到的说法，现在有提交做凭。

**② 一条"我们没踩"的确认，来自他们的热修**【史】：`984ba3d`（2026-10-17）修的是他们 `payload/bin/bash` shim
把 argv 拼成字符串（`args="$args $a"`）再 `exec /system/bin/sh $args` —— 未加引号的展开**又做了一次 word-split**，
于是 `bash -c 'touch probe1'` 变成 `sh -c touch probe1`（`-c` 只拿到 `touch`，`probe1` 落到 `$0`）。
他们写的表现是"命令在第一个空格处被截断、引号救不了、`${IFS}` 反而能绕过 ⇒ 这会让 AI 完全没法执行命令"。
**这正是我们 runner 的同型风险**（上游是按**数组**把命令交进来的，`dsh-sandbox-local-index.js:311-321`）。查过我们自己的：
`scripts/dsh-unshare-run.sh:53-60` 全程数组 + `shift`、`:125` 是单引号字面量 `exec "$@"`、
`:142` `exec unshare "${UA[@]}" bash -c "$SCRIPT" dsh-unshare-run "$@"` ⇒ **argv 边界不丢，这条不用抄**。
他那份判据形状值得抄：5 条离线用例（带参数 touch 真建文件 / 引号内连续空格 / date 带空格格式串 / 多段命令 / 剥长参数），
且**跑的是 APK 包里那份 shim**，旧 shim 同组 0/5 —— "拿产物本身跑判据"这个动作比我们只跑仓库脚本更硬，
应并进 `scripts/verify-unshare-run.sh`。

**③ DSHA 那 627 条提交里有 42 条标题就是 `chore(star-history):`**（凡带 "Star History" / "刷新曲线" / "星标曲线"
字样的并集 48 条）**——自动提交占 627 条的 6.7%**【史】，真源码是整片推的：
`810fb03 chore: 同步 build173 源码并刷新 Star History [skip ci]`、`9120b87 chore: 上传 build157 已验证源码`。
⇒ **提交条数不能当"迭代勤"的证据**，本文第六节给 DSHA 的"最像产品"评价不靠这个数，靠 CI/343 单测/审计台账。
同一节 woaiys3 那侧也有个对照读数：重复标题最多的是 **37 条一模一样的"v1.15.2：同步源码…"**、
**24 条一样的 v1.17.1** —— 它是"每次同步都重提一遍"的用法，纪律比我初稿写的还松。

**④ release 资产可以在不 bump 版本号的情况下被换掉**【史】：`984ba3d` 自己写"版本：不改版号（仍 1.19.1），
versionCode 54 → 56，保证老用户可覆盖升级；**资产已就地替换到同一 Release（未新建 Release）**"。
⇒ **tag 名与版本号都不是内容指纹**。这条正好接上本文第十节那条"我下的是 main 源码、不是 release 里的 APK"：
不只是"我没拿到包"，是**就算拿到同一个 tag 的包也不保证和历史上那个包一致**，要认内容只能比 sha256。

**⑤ DSHA 的 tag 名不能当"打包了哪版 dsh"的台账**【史】：按日期排 `v0.2.1-build150` 是 2026-10-01，
`v0.2.0-rc2` 反而在 **2026-10-09**（更晚），`v1.2.0-rc1.4` 在 2026-09-08。三套命名（`v1.x` App 线、
`v0.x.x-rcN` 引擎线、`v0.2.1-buildNNN` build 线）混在一个 tag 空间里。
⇒ 本文第三节引的 `runtime-patches.json` 顶层 `dshVersion` 和 `Constants.java:42` 才是能信的版本来源。

---

## 七、风险与红线（要抄之前先看清这四条）

1. **Soodok 的无障碍服务：能力和文案不符**【码】。`res/xml/<a11y>.xml` 声明了
   `canRetrieveWindowContent="true"` + `canTakeScreenshot="true"` + `canPerformGestures="true"`，
   注释自己写着"读取屏幕内容"；而给用户看的中文说明 `values-zh-rCN/strings.xml:38` 是
   "本服务**仅声明手势注入能力，不读取屏幕内容**"。**且没有逐次动作确认。**
   开这种服务等于把整块屏幕内容交给这个进程。我们那个 16 MB 壳没走这条路，**别照抄**。
2. **woaiys3 把引擎 stdout 原样镜像到外部存储**【码】`MainActivity.java:3934-3966`：
   `getExternalStorageDirectory()/DeepSeekHarness*/dsh-web.log`，注释 v1.7.1 明写"**无需 root/adb 可读**"。
   而登录 token URL 就打在 stdout 里（:6067 注释"通道：dsh-web.log 最后一行的启动令牌 → GET /?token="）。
   ⇒ **bearer token 明文躺在共享存储上**，任何拿到这台机外部存储读取权限的应用/adb 都能读到入口。
   我们所有日志现在都在 chroot 私有路径（`/data/local/dsh.log`），**这条是我们做对了的，写死别改**。
3. **Soodok 扩展中心只校验 SHA-256，没有签名、没有 allowlist，且允许任意 npm**【码/半码】。
   Termux deb 闭包 + 任意 npm = 这条链子上的任何一方都能往这台机推代码。DSHA 的 `client-peer-attestations.json`
   / `client-seed-proof.json` 那套证章机制是对着这个洞写的。
4. 顺带一条：**特权命令默认不逐条确认**（woaiys3 `plugins/README.md:29`），配合上面第 2 条，
   是"token 谁都能读 + 拿到就能跑且不问"两条叠在一起。

---

## 八、四档结论

**A. 能直接搬、成本低于收益的（我建议下轮就做这三条）**
① 把环境事实预写进 `$DSH_HOME/AGENTS.md`（Soodok `AgentContextSeed.kt:159-332` 的形状）；
② 把"一次性 token 不许被健康探测消费"写成脚本断言（DSHA/woaiys3 两家独立踩过）；
③ `link→rename` / `wx` 保 EEXIST / 目录 fsync 吞 EINVAL 三处 FUSE 容忍补丁
（我们现在 `/phone` 是 bind 过去的 FUSE，**这是迟早要撞的**，现在零报错只是因为还没撞）。

**B. 它替我们踩过、我们记下来当预期的**：Chromium 91 白屏与 `AbortSignal.any`、`/sdcard` 上读两万+小文件导致启动慢到
超时（woaiys3 `MainActivity.java:2108` 的根因结论）、插件 `peerDependencies` 静默失效、proot 下 `/proc/net/tcp` 被 hidepid
挡住 ⇒ **只能用 pidfile 不能用端口反查进程**（DSHA 的 AGENTS.md 里写了这条，和我们独立得到的结论一样 —— 两家都到齐了）。

**C. 我们已经解决、他们还没有的**
① **真围堵**（三家全空白，见第四节）；② **开机自启**（Soodok 干脆没有）；③ **真 chroot 的完整 apt/原生模块能力**
（两家 Bionic 路线的天花板，DSHA 用 273 MiB APK 换到了同等能力）；④ **凭证不落共享存储**；
⑤ **端到端实测数字**（34 PASS/0 FAIL），三家一个真机读数都没公开过。

**D. 明确是坑，别学**：第七节那四条，加上 woaiys3 的"tar 覆盖上游 JS × 4 档手工同步"
（短期最省事，长期是债），和 Soodok 把 uiautomator dump 提交进仓库。

---

## 九、三家共同没解的那道题 —— 也是我们那条路的真实边界

三家的文档合起来，把这条边界描述得很完整，但**没有一家给出解**：

> 这台内核 `# CONFIG_USER_NS is not set`、`# CONFIG_PID_NS is not set`、`# CONFIG_SECURITY_LANDLOCK is not set`。

⇒ 非 root 拿不到 mount namespace，**Landlock 这条上游正统路在 Android 上根本不存在**（Soodok 注释就是这句），
`--unshare-pid` 也起不来（我们的 runner 因此必须有"没有 PID_NS 就响亮失败/按显式许可降级"这两档，
`DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=1`）。

我们的解法是：**用 root 拿 mount namespace**（实测 root 下 `unshare -m` 通，见 `android-community-routes.md` §三②），
把工作区之外的顶层目录逐个 `--bind` + `remount,bind,ro` 冻住，再叠回可写工作区。
**它的适用前提写死了三条**，也正是这套方案不能给他们任何一家的原因：

1. **必须 root**（DSHA/Soodok/woaiys3 的卖点恰恰是"零 root"，这是产品定位级分歧，不是技术分歧）；
2. **rootfs 必须自己成挂载点，且用 `--rbind`**（非递归 `--bind` 会让新 chroot 的 `/proc` 是空的 —— 我们实测踩过）；
3. 它只围**可写面**，不围 `/dev` 下的裸设备节点（Android `/dev` 是 348 个条目的 tmpfs，含 253 个
   `/dev/block/*` 节点；同 UID 的被围进程能碰到它们）。**这条窟窿我们还没堵**（任务 #18，
   修法在 `scripts/dsh-devnull-inner.sh`，写好了没跑成 —— 上一轮 chroot EPERM 后 adb 掉了）。

**所以这份对比的正确读法是**：三家证明了"在 Android 上把 dsh 跑起来"至少有两条通途（打进 APK / 硬啃 bionic），
而"把 dsh 的工具围起来"这条，**三家一致选择放弃，只有一致程度的差别**（不碰 / 绕开 / 谎报）。
这条空白不是因为他们笨，是因为**它要求 root**，而 root 会毁掉"装个 APK 就能用"这个卖点。
我们这台设备已经 root 了，所以我们是这三家之外唯一有资格做这件事的位置 —— 这也是任务 #19 值得接完的理由。

---

## 十、我没做、没验、以及读数存疑的

- **三家一家都没跑过**：没装 APK、没上机、没看运行时行为。这份全是静态阅读。
- 我读的是 **`main` 分支源码**，不是他们 release 里的 APK。DSHA 的 rootfs 在 APK 里、**不在 git 里**，
  所以那 273 MiB 的实际内容我无法核对 —— 只核对了"代码确实从 APK asset 解 rootfs"这个动作【码】。
  → 历史到手之后这条**更硬而不是更松**（第六·补④）：woaiys3 `984ba3d` 自陈"资产已就地替换到同一 Release（未新建 Release）"，
  不改版号只把 versionCode 54→56 ⇒ **同一个 tag 名在两个时刻指向的两个包可以内容不同**，要认内容只能比 sha256。
- Soodok 的 `0.2.1-rc.2` 是 README 宣称【文】；我在包里没找到钉死这个版本号的单点常量。
- woaiys3 的四档 overlay **是否互相一致，我没做集合比对**（实测各档只装被改过的那几个文件：
  `overlay/` 103 个、`-017/` 12 个、`-020/` 17 个、`-021/` 18 个，逐档 diff 是另一件活儿，
  我没有据此下结论，只在第六节说了"没有机制保证一致"）。
- DSHA"零额外 token 多模型协作"**在代码里没有找到实现**【文/疑】。
- 三家 issue 区我只读了标题级别，没有逐条读（第二轮我打算只挑"和我们撞同一堵墙"的那几条）。
- 本文所有 `文件:行` 都对 `reference/gh-3p/` 下的解包成立；**注意 woaiys3 的行号是 overlay 里那份副本的行号**，
  和上游 npm 包的原文件行号不一致（他们改过文件，行有增减）。
