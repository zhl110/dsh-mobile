# DSHA vs woaiys3：两条把桌面 DeepSeek Harness 搬进 Android 的路线

> 取证时间：2026-10-21（北京时间）
> 工具：REA 6.4.0（`@morluto/rea`）
> 对象：`DSH-APP/DSHA` 与 `woaiys3/deepseek-harness-android-app`
> 证据根：`D:\mycode\dsh-mobile\reference\gh-3p\`；REA 原始输出：`downloads/rea-gh3p\`
> 标注约定：**事实**＝盘上文件或 REA 读数可直接复核；**推断**＝从代码语义或文档判断，未做运行时验证；**评价**＝我的取舍判断，不是项目自述。
> 旧报告：`docs/desktop-harness-clients-rea-report.md` 分析的是"官方桌面端 vs anywhere-labs 社区桌面端"，对象判错，已就地加箭头指向本文；原文保留不删。

---

## 0. 接班摘要

1. **这两个不是 Electron 桌面壳，而是"把桌面 DSH 原样搬进手机"的两条路线。** DSHA 把整个 Ubuntu 24.04 用 bxroot/proot 塞进 App 私有目录，在 glibc 环境里跑 Node 24 + dsh 0.2.0-rc.2；woaiys3 不建容器，直接用 bionic Node v26.4.0 跑 dsh 0.2.1-rc.2，并给 dsh 打 4 类 Android 补丁。
2. **一句话选型：要环境保真、能跑原生模块和 apt/pnpm，看 DSHA；要体积小、启动轻、设备工具多，看 woaiys3。** 代价分别是"重"（98 MB 仓库、288 MB APK、545 个 Java 文件）和"脆"（targetSdk 28、四处补丁、dsh 升级要重打）。
3. **两边真正的差距不在功能列表，而在"失败之后怎么办"。** DSHA 有 PID 出生身份、停止哨兵、受管运行时事务、独立应急运行时、宿主备份；woaiys3 有内核清单自检、会话自愈、用户补丁层、四端口令牌鉴权、`healthOk` 读真实内容。前者像"带回滚的发行版"，后者像"带急救包的改装车"。
4. **最值得直接抄的 10 个细节**：PID 身份+哨兵、43 位 token 严格解析、Cookie 异步落盘后再导航、WebMessage 同源/顶层帧/代次三重校验、`healthOk` 读内容不认状态码、防重复 spawn、四端口统一 `X-DSH-Token`、内核清单 size→sha256、会话修复先备份+临时文件 rename、用户补丁基线+白名单+回放不阻塞引擎。
5. **REA 的反馈和直接读源码确实不一样**：REA 几分钟给出"这里有什么、多大、JS 里有哪些端点和桥"；但它不认 Java，`android-app` 目录只解析了 3 个 `.mjs`，21 个 Java 文件、32,999 行完全没进图。**REA 适合第一小时画地图，架构判断和坑位必须回到源码、AGENTS 和真机日志。**

---

## 1. 目标、证据与可复现性

### 1.1 为什么是这两个

你指到 `D:\mycode\dsh-mobile\reference\gh-3p` 后，按"有完整 git 历史、且是把桌面 DSH 搬上 Android 的两个完整实现"筛，落在这两个：

| 项 | DSHA | woaiys3 |
|---|---|---|
| GitHub | `DSH-APP/DSHA` | `woaiys3/deepseek-harness-android-app` |
| 快照目录 | `DSHA-main` | `deepseek-harness-android-app-main` |
| 快照提交 | `a92928f192481f15603cedead6873839807630e8`（2026-10-20，snapshot @ `fe07a02`） | `72f553e704ad207371ad9712c1f149feb4127f45`（2026-10-20，snapshot @ `98162a2`） |
| 历史克隆 | `DSHA-hist` @ `fe07a028673a4c92cc2f7a773a36883ac11d61ff` | `dsh-android-app-hist` @ `98162a23b39eeeb75b8d4608b3e773bbb13be43d` |
| 上游最新提交语义 | `chore(star-history): 刷新曲线（1736 stars）` | `v1.20.1：附五插件 AI 评审与全量回归结果` |
| 本次是否纳入 | 是 | 是 |

第三个目录 `Deepseek-Harness-Local-Android-main`（Soodok）没有自己的 remote，是一次普通快照，不是"有历史的项目"，因此不在这对里。**事实**：`git remote -v` 为空；**评价**：拿它做三方对照可以，但不能和这两个放在同一张"工程演进"表里。

### 1.2 先纠正一个前提

你口中的"桌面端"在这两个项目里指的是 **DeepSeek Harness 的桌面版 Web UI + 本地运行时**，不是 Electron 桌面壳。两边最终都是：

```
Android App（WebView 壳）
  → http://127.0.0.1:3080/（dsh web）
  → 一个被塞进手机的"桌面运行时"
```

所以下面的"桌面端"一律指这套东西；真正要比的是**运行时怎么搬、壳怎么包、失败怎么救**。

### 1.3 REA 怎么跑、读到了什么

REA 的 `analyze` 对目录会自动选 provider；这两个仓库里能被它认的只有 JavaScript/TypeScript。实际用的是：

```bash
rea analyze-javascript-application <目录> --artifact-format directory --format json
```

逐包跑完，原始 JSON 在 `downloads/rea-gh3p/`。**事实**（REA 6.4.0 读数，已剔除重复的 `woa-browser.json`，它与 `woa-dsh-tool-browser.json` 字节相同）：

| 组 | 包数 | relevant files | parsed | text bytes | visited AST nodes | findings |
|---|---:|---:|---:|---:|---:|---:|
| DSHA 七个工具插件 | 7 | 18 | 11 | 122,274 | 17,344 | 63 |
| DSHA `dsh-web-mobile` | 1 | 202 | 133 | 2,373,337 | 80,432 | 652 |
| **DSHA 合计** | **8** | **220** | **144** | **2,495,611** | **97,776** | **715** |
| woaiys3 五个插件 | 5 | 12 | 6 | 216,213 | 27,002 | 89 |
| woaiys3 `android-app`（只认到 3 个 `.mjs`） | 1 | 3 | 3 | 34,286 | 5,413 | 41 |

两点必须说清楚：

- **findings 不是漏洞数**，是 REA 的静态候选观察；它自己的 limitations 写的是"保守的静态候选，不证明运行时执行或因果流"。
- **AST nodes 不是行数**。`dsh-web-mobile` 一个包占掉 80,432 个节点、652 条 findings、2.37 MB 文本，是 DSHA 里 JS 体量最大的部分；它不是"工具插件"，是移动端 UI 适配层（TypeScript 源 123 个 `.ts`，构建后 `lib/client.js` 约 812 KB）。

### 1.4 代码量口径

**事实**（本次 `find` + 逐文件换行计数；末尾无换行的文件会少计 1 行）：

| 项 | DSHA | woaiys3 |
|---|---:|---:|
| 仓库文件 / 体积 | 2,890 / 98 MB | 295 / 28 MB |
| 主源码 Java 文件 / 行 | 545 / 101,204 | 21 / 32,999（`src` 20 个 / 21,857 + `compat/MainActivity.java` 11,142） |
| 测试 Java 文件 / 行 | 343 / 41,005 | 0（仓库内未见同口径 JUnit） |
| 最大单文件 | `HttpShellService.java` 2,415 行 | `MainActivity.java` 11,374 行 / 614,490 B |
| 第二个大文件 | `WebPreviewActivity.java` 1,485 行 | `BrowserHost.java`（浏览器宿主） |

这不是"谁代码写得多谁更好"，而是两种组织方式：DSHA 把 545 个类按 `ui/core/runtime/data/bridge/util` 分层，纯逻辑强制配 JUnit；woaiys3 把绝大多数壳逻辑堆进一个 11k 行的 `MainActivity`，换来"改一处就能重打"的低摩擦。**但 compat flavor 又复制了一份 `compat/MainActivity.java`（11,142 行）**，同一个修复要打两遍——这是"单体+多 flavor"的真实维护成本，不是免费。

---

## 2. 两张画像

### 2.1 DSHA：把发行版搬进来

**事实**：

- 包名 `com.dsh.client`，Java 包 `com.deepseekharness.app`；`minSdk 30`（`low` flavor 23）、`targetSdk 37`、`versionCode 173`、`versionName 0.2.24-20261014.1308-dsh0.2.0-rc.2`（`DSHA-main/app/build.gradle:19-45`）。
- 运行时：bxroot / proot 把 `Ubuntu 24.04 (noble) arm64` 放进 App 私有目录；里面是 `Node.js 24` + `pnpm 10` + `@deepseek-ai/dsh 0.2.0-rc.2`（`DSHA-main/AGENTS.md:30`、`README.md:119,284`）。
- 只用 `arm64-v8a`；标准版用系统 WebView，兼容版额外带 Gecko 143（`AGENTS.md:117`）。
- 8 个内置插件目录：7 个工具/服务插件 + `dsh-web-mobile`（移动 UI）。显式工具 **19 个**：`dsh-computer-use-android` 6 个、`dsh-tool-vscreen` 13 个（`builtin-plugins/*/lib/server.cjs`）。
- 标准包在 build173 回执里是 **288,084,856 B**（`AGENTS.md` 顶部 build173 段）；这是项目自述，不是本次复称。

**评价**：DSHA 的核心信念是"**不动 dsh 的原生依赖，给它一个它认识的世界**"——它也有补丁，但补丁只落在网页兼容层 / 配置兼容层 / 移动客户端（`tools/web-compat/`、`persona-compat-patch.json`、`client-combo-patch.json`、`apply-mobile-client-patches.mjs`，`AGENTS.md:46,85,97-98`），不在 node-pty/sharp 这类原生模块上动刀。因此 apt、pnpm、node-pty、sharp 这些在 bionic 上会碎的东西，在 glibc 里原样能用；代价是 APK、启动、内存、维护全线变重。

### 2.2 woaiys3：把 dsh 改成能在手机上跑

**事实**：

- 包名 `com.deepseek.harness`，`versionCode 57`，Manifest 写 `versionName 1.20.0`，README/最新提交写 `v1.20.1`（`android-app/AndroidManifest.xml:5-8`；以 Manifest 为准的话是 1.20.0）。
- `minSdk 24`、`targetSdk 28`。**targetSdk 必须保持 28**：README 明说"≥29 会导致 node 二进制 EACCES 起不来"（`README.md:244`）。
- 运行时：不建容器，直接执行 `filesDir/payload/runtime/bin/node --expose-internals ... web --host 127.0.0.1 --port 3080`（`MainActivity.java:3974-3996`）；Node v26.4.0（`android-app/build.sh:340`），dsh `0.2.1-rc.2`（`README.md:11,46`）。
- 内核树约 25,287 个文件（`docs/开发指南.md:42`）；普通包约 162 MB、兼容版约 250 MB（`CHANGES.md:41`、`README.md:157`）。
- 5 个自研插件、**41 个工具**：accessibility 11、android 7、browser 10、shizuku 5、vscreen 8；6 个 JS 文件、4,622 行、213,506 B（本次统计）。
- compat flavor 有一份独立的 `android-app/compat/MainActivity.java`（11,142 行），与主 flavor 的 11,374 行近似复制；改主界面时要同步两边。
- 四类 dsh 补丁：`node-pty → child_process`、`sharp → 纯 JS` + `link → rename`、`bash-local` 的 `sandboxMode` getter、`session-persistence-jsonl` 的 `link → rename`（`dsh-patches/README.md:43-46`）。

**评价**：woaiys3 的核心信念是"**不改环境，改代码**"。它把 dsh 当成一棵可打补丁的树，用 targetSdk 28、bionic Node、四个补丁换掉容器；换来小体积和直接启动，代价是每次 dsh 升级都要重新对齐补丁和原生模块替代。

### 2.3 对照表

| 维度 | DSHA | woaiys3 |
|---|---|---|
| 运行时基底 | Ubuntu 24.04 arm64 + bxroot/proot（glibc） | 无容器，Android bionic 直接跑 |
| Node | 24 | v26.4.0 |
| dsh | 0.2.0-rc.2 | 0.2.1-rc.2 |
| APK 量级 | 标准包 288 MB（build173 自述） | 普通包约 162 MB / 兼容版约 250 MB（项目文档） |
| Android API | min 30 / target 37（low 23） | min 24 / target **28** |
| 代码组织 | 545 个主类 + 343 个测试类，分层 | 20 个主类 + compat 副本，`MainActivity` 11,374 行 |
| 原生模块 | 原样跑（node-pty/sharp 可用） | 打补丁/纯 JS 替代 |
| 设备工具 | 19 个显式工具 + 移动 UI 插件 | 41 个工具 |
| 进程模型 | 引擎 + 3090 原生桥 + 前台服务 | 引擎 + 4 个 loopback 服务 + `:browser` 独立进程 |
| 安全边界 | WebView 收紧、Cookie HttpOnly、桥令牌常数时间比较 | 四端口统一令牌，但 WebView `allowFileAccess=true` |
| 失败恢复 | 受管事务 + 回滚 + 独立应急运行时 + 备份 | 清单自检 + 会话自愈 + 用户补丁层 |
| 升级策略 | 受管运行时多根切换，保留健康前代 | 重解压 payload + 补丁重放 + 清单校验 |
| 文档风格 | 规范/契约/回执，句子长、边界细 | README/CHANGES/评审记录，句子短、坑位多 |

---

## 3. 架构总览

### 3.1 DSHA

```
┌──────────────────────────────────────────────────────────────┐
│ MainActivity / WebPreviewActivity（Java 17 + Material3）      │
│   WebView: fileAccess=false, mixed=never, 多窗口=false        │
│   Cookie: <43位token>; Path=/; HttpOnly; SameSite=Strict      │
└───────────────┬──────────────────────────────────────────────┘
                │ http://127.0.0.1:3080/
┌───────────────▼──────────────────────────────────────────────┐
│ WebLifecycleController（唯一 Web 编排）                       │
│   端口策略 → 读 KeyVault → 生成代次 → 启动 → 60s 慢启动提示   │
│   WebProcessManager：.dsha-web.pid / .identity / .dsha-stopped│
└───────────────┬──────────────────────────────────────────────┘
                │ bxroot / proot
┌───────────────▼──────────────────────────────────────────────┐
│ Ubuntu 24.04 arm64 rootfs（/data/local/dsh-rootfs 之类）      │
│   Node 24 + pnpm 10 + dsh 0.2.0-rc.2                          │
│   /root/.dsh（DSH_HOME）                                      │
└───────────────┬──────────────────────────────────────────────┘
                │ 127.0.0.1:3090 + X-Token
┌───────────────▼──────────────────────────────────────────────┐
│ HttpShellService（原生桥）                                    │
│   /app/ui/* /app/device/* /app/vscreen/* /root/dsh-bin/adb-shell│
│   ← dsh-computer-use-android / dsh-tool-vscreen 等插件调用     │
└──────────────────────────────────────────────────────────────┘
       另：ManagedRuntimeTransaction / RecoveryRuntime / NativeBackupJobs
```

### 3.2 woaiys3

```
┌──────────────────────────────────────────────────────────────┐
│ MainActivity（WebView + 原生控制台 + 主题）                   │
│   allowFileAccess=true, addJavascriptInterface("dshshell")    │
│   主框架错误重试 120 次 × 2.5s                                │
└───────────────┬──────────────────────────────────────────────┘
                │ http://127.0.0.1:3080/?token=...
┌───────────────▼──────────────────────────────────────────────┐
│ bionic Node v26.4.0 + dsh 0.2.1-rc.2（patched dshroot）       │
│   EngineService：前台服务，START_STICKY                       │
└───┬───────────────┬───────────────────┬──────────────────────┘
    │ 3081 通知     │ 3181 无障碍       │ 8999 虚拟屏桥 → 8998 特权核心
    ▼               ▼                   ▼
  LocalAuth（四处统一 X-DSH-Token，fail-closed）
    │
    │ Messenger IPC
    ▼
 BrowserService（android:process=":browser"）
   BrowserHost：快照/点击/输入/多标签，generation/navGen/mut
```

---

## 4. 共同点：两个项目都踩过的 Android 坑

1. **都用 WebView 当壳，引擎都是 `127.0.0.1:3080` 的 `dsh web`。** 不是把 dsh 编译成原生 UI，而是保留桌面 Web UI，再在壳里做移动适配。
2. **都必须给 loopback 加鉴权。** Android 的 loopback 对设备上所有 App 开放，端口又可枚举；DSHA 用 3090 的 `X-Token`，woaiys3 用四个端口的 `X-DSH-Token`。
3. **都用前台服务保活。** DSHA `HarnessService`（`specialUse|connectedDevice`）；woaiys3 `EngineService`（`dataSync`、`START_STICKY`，`EngineService.java:31,39`）。
4. **都得防"重复拉起引擎"。** DSHA 用代次 + 端口策略 + 慢启动不重启；woaiys3 用 `healthOk` + 端口监听 + `nodeProcess` 句柄；它记录了"EADDRINUSE 72 次 vs 成功启动 38 次"的真机数据（`MainActivity.java:8340`）。
5. **都做设备控制工具。** DSHA 19 个、woaiys3 41 个；都覆盖截图、点击、滑动、输入、按键、应用启动、虚拟屏/无障碍。
6. **都依赖无障碍 / Shizuku / root 三条特权通道。** 两家都把"免 root 操作手机"当卖点，也都要求用户显式授权。
7. **都要处理 dsh 的一次性 token。** token 在启动行里只出现一次，必须从 stdout 抓；抓早了会截断，抓晚了可能已被消费。
8. **都要做移动端 UI 适配。** DSHA 内置 `dsh-web-mobile` 3.1.0（TypeScript，2.7 MB）；woaiys3 用 `mobile-patch/` 幂等注入 CSS/JS + viewport 锁定。
9. **都固定运行时版本、随包携带离线资产。** 两家都不是"装个 npm 包就完事"，而是把 node、dsh、依赖一起打包。
10. **都有一份很长的"已知坑"文档。** DSHA 是 AGENTS 契约，woaiys3 是 README/CHANGES/评审记录；这类文档的价值不低于代码。

---

## 5. 根本差异：环境保真 vs 宿主适配

### 5.1 运行时：glibc 容器 vs bionic 直跑

**DSHA 的事实**：

- 启动参数包含 `--kill-on-exit`、`-0`（root 映射）、`--rootfs=...`、`--cwd=/root`；只有文件系统不支持硬链接时才加 `--link2symlink`（`ContainerRuntime.java:98-111`）。
- proot 二进制从 `nativeLibraryDir/libproot.so` 执行，靠 `PROOT_LOADER` / `LD_LIBRARY_PATH` 引导（`ContainerRuntime.java:146-149`；`AGENTS.md:188`）。
- `PROOT_L2S_DIR` 在 rootfs 内的 `.l2s` 必须绑定到**相同的宿主绝对路径**，否则 dpkg 对硬链接做 chown/stat 会报文件不存在（`AGENTS.md:171`）。
- 明确不 bind `/linkerconfig`：proot 每次启动都会打 `can't sanitize binding "/linkerconfig": Permission denied`，而且 bind 失败等于从没绑上（`ContainerRuntime.java:216-217`）。
- `NARB_DISABLE_NATIVE_CACHE=1` 让原生扩展直接从随包目录加载，避免 link+unlink 缓存第一次悬空（`AGENTS.md:125`）。

**woaiys3 的事实**：

- 直接 `new ProcessBuilder(node, "--expose-internals", binjs, "web", ...)`，没有 proot/bxroot（`MainActivity.java:3994-3996`）。
- `targetSdk 28` 是为了让 `filesDir` 里的 node 还能执行；README 明说 ≥29 会 EACCES（`README.md:244`）。
- `LD_LIBRARY_PATH` 指向 payload 的 `runtime/lib`；`OPENSSL_CONF` 指向随包 `openssl.cnf`，绕开 Termux 编译时写死的 `OPENSSLDIR`（`MainActivity.java:3998-4004`）。
- Git 要补 `GIT_EXEC_PATH`、`GIT_TEMPLATE_DIR`、`GIT_PAGER=cat`、`GIT_CONFIG_GLOBAL`、`GIT_CONFIG_NOSYSTEM`、`GIT_ATTR_NOSYSTEM`、`GIT_TERMINAL_PROMPT=0`；CA 要同时喂 `SSL_CERT_FILE` / `CURL_CA_BUNDLE` / `GIT_SSL_CAINFO`（`MainActivity.java:4005-4033`）。
- 用 `LINKS.txt` 把 soname 链接"物化"成真实文件，绕开 Android 对符号链接/硬链接的限制（`android-app/build.sh:84-117`）。

**评价**：DSHA 走的是"把 Linux 的假设原样满足"；woaiys3 走的是"把 Linux 的假设逐个拆掉"。前者升级 dsh 更省心，后者省掉整个容器的体积和启动开销。

### 5.2 补丁策略：不动原生依赖 vs 四类外科手术

DSHA 也改 dsh，但改在网页/配置兼容层（`tools/web-compat/`、`persona-compat-patch.json`、`client-combo-patch.json`、`apply-mobile-client-patches.mjs`，`AGENTS.md:46,85,97-98`），不在 `node-pty`/`sharp` 这类原生模块上动刀。woaiys3 的 `dsh-patches/README.md:43-46` 把四类补丁写得非常直白：

| 补丁对象 | 原因 | 做法 |
|---|---|---|
| `dsh-subprocess-local` | node-pty 原生模块在 Android 编不出来 | 用 `child_process` 模拟 |
| `dsh-attachment-local` | sharp 原生模块 + Android 禁硬链接 | 纯 JS 头解析 + `link→rename` |
| `dsh-bash-local` | 原生沙箱禁用后要兼容 | 补 `sandboxMode` getter |
| `dsh-session-persistence-jsonl` | Android SELinux 禁硬链接 | `link→rename` |

另外 `config/cordis.patch.yml` 禁用了 `bash-sandbox`、`pwsh-sandbox`、`session-log-download`、`session-telemetry-otel`，但**明确保留 `sandbox`**：0.1.7 起 `ptc-runtime` 注入了 sandbox 服务，禁掉会让 `workflow-ptc` 永久 pending（`cordis.patch.yml:5-14,25-38`）。默认 preset 是 `danger-full-access`（`cordis.patch.yml:58`）。

**评价**：woaiys3 的补丁是"知道自己在拆什么"的补丁；但每一条都绑定 dsh 内部实现，dsh 一升级就要重新验证。DSHA 的"少补"不是免费，它把成本转移到了 288 MB 的 rootfs 和 proot 的兼容性上。

### 5.3 代码组织：分层+测试 vs 单体+迭代

- DSHA 的 `util/` 明确要求"不得 import Android API"，`ShellQuote`、`Query`、`BackupScope`、`WebProcSel` 四类纯逻辑必须配 JUnit（`AGENTS.md:160-173`）；测试 343 个文件、41,005 行。
- woaiys3 没有同口径的 JUnit；它的验证主要是 `verify-v1193.sh` 和真机评审记录。README 自述"三套包各 109 PASS / 0 FAIL；official 全量回归 31 步 OK / 772 PASS / 0 FAIL"（`README.md:20`）——**这是项目自述，本次没有复跑**。
- woaiys3 的 `docs/reviews-v1.20.1/` 反而很有价值：它记录了失败，比如虚拟屏 `android_vscreen_launch` 把"首帧纯白"误报成"画面已刷新"、无障碍树里的启动遮罩幽灵节点。这比只写 PASS 的测试报告更能指导后来人。

### 5.4 更新与恢复：事务回滚 vs 清单自检

**DSHA**：

- `ManagedRuntimeTransaction` 用 `verified / switching / rolling-back / rolled-back / finalized` 标记 + `plan.json` 哈希；提交前做健康检查，用户目录不在切换清单里（`ManagedRuntimeTransaction.java:243-279,294,370-375`）。
- `RecoveryRuntime` 是独立应急环境：从锁定资产构建，预留 128 MB，overlay 文件单独列（`RecoveryRuntime.java:38,46-49,297-306`），不经过正式环境的迁移和数据绑定。
- 备份密码只在 worker 内存里，结束即 `Arrays.fill(password, '\0')`；产物放在 rootfs 外（`NativeBackupJobs.java:425-444,515-522`）。

**woaiys3**：

- `KernelSelfCheck` 以随包 `kernel-manifest.tsv`（相对路径/大小/sha256）为唯一判据；先比大小，再算 sha256；区分 `extraKernel`（内核命名空间，可自动修）与 `extraUser`（用户数据/第三方插件，只报不改）；每次自检写 JSON 账本（`KernelSelfCheck.java:8,36,44-49,145,246-251,303-312`）。
- `SessionHeal` 只修选中的一条会话；写盘前备份 `.corrupt-<ts>`，临时文件 + rename 原子替换，默认 dry-run；因为 Java 没有 zstd，实际修复交给随包 `session-heal.mjs`（`SessionHeal.java:27-36,43-46,240`）。
- `UserPatches` 是"我的补丁"层：以出厂基线 `.baseline.tsv` 判断哪些是用户改的；只允许源码/配置/图片扩展名，**拒绝 `.so/.dex/.apk/.jar/.sh/.bin`**，单文件 ≤8 MB；所有官方同步之后回放，失败绝不让引擎起不来；只碰 `dshroot/`，不碰用户数据（`UserPatches.java:42-46,63,67,118,259,282,339-341,434-443`）。

**评价**：DSHA 的恢复是"整机回滚"，适合"我可能把整个运行时玩坏"；woaiys3 的恢复是"定点修复"，适合"我知道哪个文件坏了"。前者成本高但兜底强，后者成本低但要求清单准确。

### 5.5 安全边界：收紧 vs 够用

| 项 | DSHA | woaiys3 |
|---|---|---|
| WebView 文件访问 | `setAllowFileAccess(false)`，只开 `allowContentAccess` 给 FileProvider（`WebPreviewActivity.java:674-676`） | `setAllowFileAccess(true)`（`MainActivity.java:298`） |
| 混合内容 | `MIXED_CONTENT_NEVER_ALLOW`（`:677`） | 未见到同等收紧 |
| 多窗口 | `setSupportMultipleWindows(false)`（`:678`） | 未见到 |
| Cookie | `HttpOnly; SameSite=Strict`，第三方 Cookie 关闭，异步回调后才导航（`:689-706`） | 未见到同等级 Cookie 策略 |
| Web 消息桥 | `DshaLanguage`/`DshaTheme` 只对 base origin 注册，校验当前页、顶层帧、来源 URL、代次（`:776-808`） | `addJavascriptInterface(..., "dshshell")`，用于背景色；面较小但仍是 JS 接口 |
| 本地桥 | 3090 绑 127.0.0.1，`X-Token`，`LanAuth.constantTimeEquals`（`HttpShellService.java:50,493,666-668,702`） | 四端口统一 `X-DSH-Token`，token <16 一律拒绝，header 优先、query 兜底（`LocalAuth.java:9-15,20-23,33,88-102`） |
| 明文流量 | 未在 Manifest 开 `usesCleartextTraffic` | `usesCleartextTraffic=true`（Manifest） |
| targetSdk | 37 | 28（为可执行性） |

**评价**：DSHA 在 WebView 和 Cookie 上明显更严；woaiys3 在"四端口统一鉴权"上更系统。两者的共同短板是：本地桥一旦被同机恶意 App 拿到 token，就能读屏、注入手势、读剪贴板；DSHA 甚至在注释里承认"导出 `.bridge_token` 后，同机任意应用即可完全接管本桥"（`HttpShellService.java:1972`）。

### 5.6 设备控制与 UI：广度 vs 深度

- **工具数量**：woaiys3 41 个，DSHA 19 个。woaiys3 多出来的主要是 accessibility 的连续手势/按住/触摸状态、browser 的 10 个工具、shizuku 的剪贴板/通知/设置。
- **虚拟屏**：DSHA 13 个 vscreen 工具，用 `generation` + `frameSeq` 做"画面代次"门控；woaiys3 8 个 vscreen 工具，走 8999 桥 → 8998 特权核心。
- **浏览器**：woaiys3 把浏览器放进 `:browser` 独立进程（Manifest `android:process=":browser"`），用 Messenger IPC，崩溃不拖死主壳；DSHA 的浏览器能力更多在 WebView/预览层。
- **UI**：DSHA 是原生 Material3 多 Activity（欢迎、主界面、预览、恢复、备份、插件安装、文档提供者、PiP）；woaiys3 是"原生控制台 + 一个大 WebView"，控制台管解压/权限/插件/日志，主题可切。
- **移动适配**：DSHA 用 `dsh-web-mobile` 3.1.0；woaiys3 用 `mobile.css`/`mobile.js` 注入 + viewport `maximum-scale=1.0, user-scalable=no`，并给老 WebView 补 `Iterator.prototype.join`（`mobile-patch/mobile.js:2-9,37-43`）。

---

## 6. 细节优化清单（这节是给"自己写"用的）

> 每条都标了文件和行；"为什么"是我从代码/文档读出来的，不是项目自述。**推断**处已注明。

### 6.1 启动与进程身份

| # | 做法 | 证据 | 为什么值得抄 |
|---|---|---|---|
| 1 | `exec` 前写 PID，`exec` 不换 PID | `WebLaunchCommand.java:36-42`；`AGENTS.md:169-170,187` | 停止时按 PID 文件杀，不靠端口反查；`/proc/net/tcp` 非 root 读不到，`/proc` 可能 hidepid |
| 2 | 同时写"出生身份"（`.dsha-web.identity`），杀前二次核验 | `WebProcessManager.java:175-194,463-469` | 防 PID 复用；只对身份匹配的进程发信号，绝不误杀 proot/launcher |
| 3 | 先写停止哨兵 `.dsha-stopped`，再杀 | `WebProcessManager.java:149-156,269-274`；`WebLaunchCommand.java:41` | 防看门狗/重启脚本"秒复活" |
| 4 | 每次启动带 `DSHA_WEB_GENERATION`，旧代次启动直接退出 | `WebLaunchCommand.java:33-42` | 异步回调/旧页面不能批准新代次 |
| 5 | 慢启动只提示、不重启；60 秒只是提示 | `WebLifecycleController`（AGENTS `:107`） | 把"慢"当"死"会触发重复拉起，反而更慢 |
| 6 | 端口冲突先保留用户配置，再试备用端口，最后 `--port 0` | `AGENTS.md:107`；`WebLifecycleController` | 不因端口占用改用户配置，也不按端口猜 PID |
| 7 | 启动前检查 `.offline-extracted` 与环境身份；维护页不能伪造就绪 | `AGENTS.md:185-188` | 避免"界面绿了、引擎没起" |
| 8 | 前台服务 + `START_STICKY`，每次重建都刷新通知 | `EngineService.java:31,39` | 系统杀进程后还能回来 |
| 9 | `healthOk` 读真实响应内容，不认"任意 HTTP 200-499" | `MainActivity.java:2448-2479,4162` | 占位服务/端口复用会骗过状态码 |
| 10 | 防重复 spawn：先看 `nodeProcess` 句柄，再看端口是否 listening | `MainActivity.java:8313-8359,8340` | 真机 EADDRINUSE 72 次 vs 成功 38 次，重复拉起是最高频浪费 |

**推断**：第 9、10 条是 woaiys3 从真机日志里磨出来的，不是设计出来的；这类"失败驱动"的细节比架构图更难抄，但收益最大。

### 6.2 鉴权与 WebView

| # | 做法 | 证据 | 为什么值得抄 |
|---|---|---|---|
| 11 | 只接受 `http://127.0.0.1:<port>/?token=<43位base64url>`，容忍日志前缀但要求完整 token | `DshAuthUrl.java:21-30` | 抓早了会截断 token；抓宽了会把日志里的假 URL 当鉴权入口 |
| 12 | token 永不写盘、不写日志；落盘前统一打码 | `DshAuthUrl.java:34,105-108` | 凭证不进任何可回看的地方 |
| 13 | Cookie 的 `setCookie` 是异步的，回调成功后才继续首次导航 | `WebPreviewActivity.java:689-706` | 不等回调就 load，首次进入会偶发未认证 |
| 14 | Cookie 带 `HttpOnly; SameSite=Strict`，第三方 Cookie 关闭 | 同上 `:691,696` | 降低 XSS/CSRF 面 |
| 15 | WebMessageListener 只注册 base origin，并校验当前页/顶层帧/来源 URL/代次 | `WebPreviewActivity.java:776-808` | 网页里任意 iframe 不能冒充主页面调原生 |
| 16 | WebView 关文件访问、关混合内容、关多窗口 | `WebPreviewActivity.java:674-678` | 三个开关是 WebView 最便宜的加固 |
| 17 | 本地桥 token 常数时间比较；`X-Token` 头，不把 token 放 query | `HttpShellService.java:666-668,702` | 防时序侧信道；query 会进日志/历史 |
| 18 | 四端口统一 `X-DSH-Token`，token 缺失或 <16 一律拒绝 | `LocalAuth.java:20-23,88-102` | 只要有一个 loopback 服务漏鉴权，整机都能读屏/注入 |
| 19 | 给 curl 留 `.bridge_headers`，用 `-K -` 从 stdin 递 header | `HttpShellService.java:43`；项目规则 | 凭证不进 argv，`ps` 看不到 |

**评价**：DSHA 的 11-16 是"把 WebView 当不可信浏览器"；woaiys3 的 18 是"把 loopback 当公网"。两边合起来才是完整答案。

### 6.3 运行时与构建

| # | 做法 | 证据 | 为什么值得抄 |
|---|---|---|---|
| 20 | `--link2symlink` 只在文件系统不支持硬链接时加，不无脑加 | `ContainerRuntime.java:98-101` | 它会破坏 dsh 的 write 工具；能不加就不加 |
| 21 | `PROOT_L2S_DIR` 的 `.l2s` 绑定到相同宿主绝对路径 | `AGENTS.md:171` | 否则 dpkg 对硬链接 chown/stat 会报文件不存在 |
| 22 | proot 二进制放 `nativeLibraryDir`，不放 `filesDir` | `AGENTS.md:188` | Android 10+ W^X；`filesDir` 不可执行 |
| 23 | 不 bind `/linkerconfig` | `ContainerRuntime.java:216-217` | 每次启动都报 Permission denied，纯噪音 |
| 24 | `NARB_DISABLE_NATIVE_CACHE=1` | `AGENTS.md:125` | 默认 link+unlink 缓存会在 `--link2symlink` 下首次悬空 |
| 25 | 构建前扫 payload 里的 JSON/YAML BOM，命中就失败 | `android-app/build.sh:28-37` | Node 的 `JSON.parse` 遇 BOM 直接 SyntaxError，表现是"引擎起不来" |
| 26 | 随包 `openssl.cnf` + `OPENSSL_CONF` | `MainActivity.java:3999-4004`；`build.sh:47` | Termux 编译的 node 把 OPENSSLDIR 写死，装了 Termux 就 EACCES |
| 27 | Git 七件套环境变量 + 合并 CA bundle | `MainActivity.java:4005-4033` | 内置 git 的 remote helper、模板、分页器、证书都会指错 |
| 28 | `LINKS.txt` 物化 soname 链接 | `build.sh:84-117` | Android 对符号链接/硬链接的限制会让 `lib*.so` 找不到 |
| 29 | 用 `targetSdk 28` 保可执行性 | `README.md:244` | 只适合自用/侧载；上架或高安全场景应改用 `nativeLibraryDir`/proot，别学这个 |
| 30 | 移动补丁幂等注入，不覆盖 `index.html` | `mobile-patch/inject.sh:2-4,25-38` | 保留上游 hash/引用；重复构建不会插两份 |
| 31 | viewport 补 `maximum-scale=1.0, user-scalable=no` | `inject.sh:43-50` | WebView 的 `setSupportZoom(false)` 不够，viewport 才是权威 |
| 32 | 老 WebView 补 `Iterator.prototype.join` | `mobile-patch/mobile.js:2-9,37-43` | ES2025 在 WebView <122 不存在，不补就白屏 |

### 6.4 数据与自愈

| # | 做法 | 证据 | 为什么值得抄 |
|---|---|---|---|
| 33 | 受管运行时事务：`verified→switching→finalized`，失败 `rolling-back→rolled-back`，每步绑 `plan.json` 哈希 | `ManagedRuntimeTransaction.java:243-279,370-375` | 更新不是"覆盖文件"，是可证明的提交/回滚 |
| 34 | 用户目录不在切换清单；提交前健康检查 | 同上 `:294`；`AGENTS.md:89` | 系统可换，对话/附件/项目不能丢 |
| 35 | 独立应急运行时，128 MB 预留，锁定资产 | `RecoveryRuntime.java:38,46-49,297-306` | 正式环境坏了还能进去修 |
| 36 | 备份密码只在 worker 内存，结束清零；产物放 rootfs 外 | `NativeBackupJobs.java:425-444,515-522` | 密码不落盘、不跨进程；环境坏了备份还在 |
| 37 | 内核清单先比大小再算 sha256，区分内核/用户 extra | `KernelSelfCheck.java:8,36,145,246-251,303-312` | 全量 sha256 很慢；先比大小能秒级排除大多数 |
| 38 | 自检只读，修复写账本 | `KernelSelfCheck.java:44-49,79-80` | "修过什么、依据什么"可查 |
| 39 | 会话修复只碰选中一条；`.corrupt-<ts>` 备份；临时文件+rename；默认 dry-run | `SessionHeal.java:27-36,240` | 不自作主张批量修，不半写 |
| 40 | 用户补丁层：基线判断、扩展名白名单、8 MB 上限、同步后回放、失败不阻塞 | `UserPatches.java:42-46,63,67,118,259,339-341` | 让用户改内核文件还能在升级后保留，但不让补丁把引擎搞死 |
| 41 | 补丁只碰 `dshroot/`，不碰 `dshhome/**` | `UserPatches.java:46,434-443` | 用户数据与内核树分开 |

### 6.5 设备控制、浏览器与虚拟屏

| # | 做法 | 证据 | 为什么值得抄 |
|---|---|---|---|
| 42 | 浏览器放 `:browser` 独立进程，用 Messenger IPC，死了可重连 | Manifest `:81-83`；`BrowserService`/`BrowserIpc` | WebView/浏览器崩溃不拖死主壳 |
| 43 | 快照用稳定引用，不用位置索引；真增量；操作后二次验证 | `BrowserHost.java:58-66,572,933-946` | 页面一变动，位置索引就错；"点了"不等于"生效" |
| 44 | `generation` 与 `navGen` 分开；DOM 变更不算导航 | `BrowserHost.java:94-98,937-938` | 否则每次 DOM 变动都误报 stale |
| 45 | 限制 400 节点 / 120 字符名 / 8,000 字符文本 / 1080×1920 | `BrowserHost.java:58-66` | 防一次快照把内存/上下文打爆 |
| 46 | 拒绝 loopback 导航 | `BrowserHost`（项目文档/代码） | 防 AI 浏览器回到本机管理面 |
| 47 | 虚拟屏用 `generation` + `frameSeq` 门控，未知结果不重放 | `dsh-tool-vscreen/lib/server.cjs:6-15`；`AGENTS.md:14` | 屏幕操作不是幂等的，重放会点两次 |
| 48 | 截图最大 16 MB，校验 PNG/base64，响应限长 | `dsh-computer-use-android/lib/server.cjs:32-36` | 防大图/坏图把桥拖死 |
| 49 | 虚拟屏工具支持 nodeId 语义操作、editor get/edit/submit | `dsh-tool-vscreen/lib/server.cjs:12-14` | 像素点击不稳时，语义树更可靠 |
| 50 | 无 root 的 Shizuku 通道 + 有 root 的 su 通道，发送前选路，未知不重放 | `AGENTS.md:118,122`；woaiys3 Shizuku 插件 | 特权通道不能"失败了换一条再试"，会重复执行 |

### 6.6 移动 UI 与交互

| # | 做法 | 证据 | 为什么值得抄 |
|---|---|---|---|
| 51 | 原生控制台先起，不必等引擎；解压/权限/插件/日志四页 | `README.md:35` | 冷启动时用户有地方可看、可操作 |
| 52 | 主框架加载失败重试 120 次 × 2.5 s | `MainActivity.java:312-320` | 引擎慢启动时 WebView 不会永远白屏 |
| 53 | 页面加载后 0/700/2000/5000 ms 采样背景色 + MutationObserver | `MainActivity.java`（onPageFinished） | 让原生状态栏/背景跟网页主题走 |
| 54 | 崩溃处理器 + 启动诊断 | `MainActivity.java:1008`；woaiys3 `startup-diag.txt` | 用户说"打不开"时，有东西可查 |
| 55 | 主题包 / 多套配色 | woaiys3 控制台 | 单人项目里这是低成本高感知的体验 |
| 56 | PiP、DocumentsProvider、FileProvider 临时授权 | DSHA Manifest `:130,146`；`WebPreviewActivity` | 让"手机上的桌面应用"更像桌面应用 |
| 57 | 系统语言在进程最早时刻锁存，早于任何 `Locale.setDefault` | `AGENTS.md:101` | 否则"跟随系统"切一次就自我锁死 |
| 58 | 中英文文案由 `messages.json` 构建生成，不硬编码在布局 | `AGENTS.md:101` | 文案与布局解耦，短屏/大字体好适配 |
| 59 | 双 flavor：标准版系统 WebView，兼容版 Gecko 143 | `AGENTS.md:117` | 老设备/旧 WebView 有退路 |
| 60 | Lite/Compat 独立包名 + 独立端口（3082/3084） | `README.md:156-157`；`MainActivity.java:2528-2535` | 三套包可同时装，不抢 3080 |

### 6.7 测试与工程

| # | 做法 | 证据 | 为什么值得抄 |
|---|---|---|---|
| 61 | 纯逻辑抽到 `util/`，禁止 import Android，强制 JUnit | `AGENTS.md:160-173` | 进程/路径/引号/备份范围这些最容易错，且最好测 |
| 62 | `ShellQuote` 防恶意值逃逸；`Query` 逐参数名匹配 | `AGENTS.md:165-167` | `indexOf(key+"=")` 会被后缀劫持；空值≠不存在 |
| 63 | `BackupScope`：部分备份绝不叫 `DSHA-backup-*` | `AGENTS.md:168` | 否则老版本会当全量恢复，清掉配置/插件 |
| 64 | `WebProcSel` 认得出 dsh，绝不把 proot/launcher 当 dsh | `AGENTS.md:165` | 杀错容器启动器 = 环境连 App 一起带走 |
| 65 | 真机评审记录保留失败案例 | `docs/reviews-v1.20.1/*` | 比只写 PASS 的报告更能防回归 |
| 66 | 构建即校验：BOM、API key、摘要、签名 | `build.sh:28-37`；DSHA `AGENTS.md:61-62` | 把"人会忘"的东西变成构建失败 |

---

## 7. 各自优点与代价

### 7.1 DSHA 的优点

1. **环境保真度最高**：apt、pnpm、node-pty、sharp、Python 都能按 Linux 的方式跑；dsh 升级时不用追着原生模块补丁跑。
2. **失败恢复最完整**：受管事务、回滚、独立应急运行时、宿主备份，四层都有。
3. **进程安全最细**：PID 出生身份、停止哨兵、代次、慢启动不重启、按 PID 不按端口。
4. **WebView 最克制**：文件访问关、混合内容禁、多窗口关、Cookie HttpOnly、WebMessage 同源+顶层帧+代次。
5. **测试最扎实**：343 个测试文件、41,005 行；纯逻辑与 Android 依赖隔离。
6. **设备面最像"桌面应用"**：PiP、DocumentsProvider、终端、文件预览、插件安装、双 flavor。

### 7.2 DSHA 的代价

1. **重**：98 MB 仓库、288 MB APK、545 个主类；构建需要 `offline-rootfs.bin` / `dsh-runtime.bin` 这类不提交的大资产（`AGENTS.md:61-62`）。
2. **proot 开销**：启动、I/O、内存都比直跑高；只支持 arm64（标准版）。
3. **暴露面大**：`PluginInstallActivity` 导出（`dsha://install`、`https://dsha.cc/install`）、DocumentsProvider、无障碍、Shizuku、大量权限（Manifest `:5-37,100,130,146,176,184,191`）。
4. **签名历史包袱**：AGENTS 明说线上 APK 历史上用 debug keystore，增量更新清单另用 release keystore，"绝不混用"（`AGENTS.md` 签名段）。这套不要照抄。
5. **文档密度高**：AGENTS 很长，接班成本不低；好处是边界写死了。

### 7.3 woaiys3 的优点

1. **轻**：28 MB 仓库、20 个主类（另有一份 compat 副本）、无容器；普通包约 162 MB，比 DSHA 小一个量级。
2. **启动路径短**：直接 bionic Node，没有 proot 翻译层；**推断**冷启动更快（未实测）。
3. **设备工具最全**：41 个工具，覆盖无障碍、浏览器、Shizuku、虚拟屏、系统设置。
4. **失败驱动细节极多**：BOM 闸门、OpenSSL/Git/CA、`healthOk` 读内容、防重复 spawn、会话自愈、用户补丁层、清单自检——每一条都有真机日志背景。
5. **浏览器进程隔离**：`:browser` 独立进程 + Messenger IPC，崩溃不拖死主壳。
6. **对用户改动的尊重**：用户补丁层让"我改过的内核文件"在重启/重装后不丢，且有白名单/大小/失败兜底。
7. **多版本共存**：正式/Lite/Compat 三套包名与端口，能同时装。

### 7.4 woaiys3 的代价

1. **targetSdk 28 是硬伤**：为了 node 可执行而停在旧 target；上架、安全基线、新系统行为都受限（`README.md:244`）。
2. **补丁与 dsh 强耦合**：仓库保留 4 类补丁，README 又自述 0.2.1 升级时"16 个补丁全部合并"；每次升级都要重验，`sharp → 纯 JS` 还可能损失性能/格式覆盖。
3. **单体难维护**：`MainActivity.java` 11,374 行，`compat/MainActivity.java` 又复制了 11,142 行；改一处容易碰另一处，且要同步两份。
4. **WebView 边界较松**：`allowFileAccess=true`、`addJavascriptInterface`、`usesCleartextTraffic=true`；对自用可接受，对分发偏危险。
5. **四端口增加面**：虽然统一了 token，但 3081/3181/8999/8998 都是本机可枚举的入口；任何一个漏鉴权都致命。
6. **测试不可复跑**：109 PASS/772 PASS 是项目自述，仓库内没有同口径的自动化入口。

### 7.5 谁适合谁

| 你的目标 | 更像谁 | 理由 |
|---|---|---|
| 自己用、要 apt/pnpm/原生模块/终端 | DSHA | glibc 环境省掉大量"为什么这个包编不过" |
| 要小体积、快启动、设备工具多 | woaiys3 | 无容器 + 41 工具 + 独立浏览器进程 |
| 要分发给非 root 用户 | woaiys3（但要改 targetSdk/WebView） | DSHA 的 proot 和 288 MB 对普通用户太重 |
| 要长期跟 dsh 升级 | DSHA | 不碰原生模块，升级主要是换运行时（网页/配置兼容层仍需跟验） |
| 要用户敢改内核文件 | woaiys3 | 用户补丁层是现成的 |
| 要把"失败后怎么救"做扎实 | DSHA | 事务/回滚/应急运行时/备份四层 |

---

## 8. 如果你要回来写自己的：建议路线

### 8.1 选型建议

你现在 `dsh-mobile` 已经是"真 chroot + 三层壳"的路线，和 DSHA 同源，不要因为 woaiys3 轻就推翻重来。**建议：保留 chroot 的保真度，补上两边的"纪律层"。**

- **运行时**：继续 chroot/rootfs；如果以后要做非 root 分发，再考虑 woaiys3 的 bionic + 补丁路线，但那时 targetSdk 28 不能带。
- **启动**：抄 DSHA 的 PID 身份 + 哨兵 + 代次；抄 woaiys3 的 `healthOk` 读内容 + 防重复 spawn。
- **鉴权**：抄 DSHA 的严格 token 解析 + Cookie 异步；抄 woaiys3 的"所有 loopback 端口统一令牌"。
- **WebView**：抄 DSHA 的 fileAccess=false / mixed=never / 多窗口=false / WebMessage 同源+顶层帧+代次。
- **数据**：抄 DSHA 的事务/回滚/应急运行时；抄 woaiys3 的清单自检 + 会话自愈 + 用户补丁层。两者不冲突：一个是"整机回滚"，一个是"定点修复"。
- **设备**：先做 3-5 个高频工具（截图、点击、输入、返回、启动应用），再扩虚拟屏；不要一上来追 41 个。
- **UI**：先做原生控制台（解压/权限/日志/启停），再做主题；移动适配优先 viewport + 键盘 + 安全区。

### 8.2 P0/P1/P2 清单

| 优先级 | 事项 | 验收判据 |
|---|---|---|
| P0 | 引擎单实例 + PID 身份 + 停止哨兵 | 连续点 10 次启动只出现 1 个 node；停止后 5 秒内不复活；杀错进程 0 次 |
| P0 | token 严格解析 + Cookie 异步 + WebView 三开关 | 首次进入不出现未认证页；token 不出现在日志/argv；iframe 不能调原生桥 |
| P0 | 所有 loopback 端口统一鉴权 | 不带 token 的 curl 全部 401/拒绝；token <16 位一律拒绝 |
| P0 | `healthOk` 读真实内容 + 防重复 spawn | 占位 200 不误判；EADDRINUSE 为 0；启动按钮不提前亮 |
| P1 | 内核清单自检（size→sha256）+ 账本 | 缺文件/内容不符能定位到路径；用户数据只报不改 |
| P1 | 会话/配置修复：备份 + 临时文件 rename + dry-run | 修复中断不产生半文件；默认不落盘 |
| P1 | 用户补丁层：基线 + 白名单 + 8 MB + 同步后回放 | 重启/重装后用户改动还在；补丁坏了引擎仍能起 |
| P1 | 备份/恢复：密码只在内存，产物在 rootfs 外 | 进程结束密码清零；环境坏了备份可读 |
| P2 | 受管运行时事务/回滚 | 更新失败能回到上一代；用户目录字节不变 |
| P2 | 独立应急运行时 | 正式环境起不来时能进应急页 |
| P2 | 浏览器/虚拟屏独立进程 + 代次门控 | 浏览器崩溃不拖死主壳；未知结果不重放 |
| P2 | 移动适配 + 主题 + 多 flavor | 窄屏/横屏/键盘/大字体不破；Lite 可共存 |

### 8.3 不要照抄的 6 件事

1. **不要抄 `targetSdk 28`**。它是 woaiys3 为了 bionic node 可执行做的妥协；你做 chroot/proot 或把二进制放 `nativeLibraryDir`，不需要这个。
2. **不要抄 `setAllowFileAccess(true)` + `addJavascriptInterface`**。除非你能证明那个 JS 接口只做背景色且不可被页面伪造；优先 WebMessageListener + 同源校验。
3. **不要抄 DSHA 的双签名历史**。线上包用 debug keystore 是历史包袱，不是设计；用一把 release key，更新清单另算。
4. **不要抄 11k 行单体 `MainActivity`，更不要复制一份 compat 副本**。woaiys3 是单人高频迭代的产物；你要长期维护，至少把生命周期/鉴权/自检/桥拆开，compat 用共享基类/构建变体而不是复制。
5. **不要默认 `danger-full-access` 且关掉沙箱**。woaiys3 保留 `sandbox` 是有原因的；先明确"工具审批不是强沙箱"。
6. **不要无脑 `--link2symlink`**。它只在文件系统不支持硬链接时需要，且会破坏 dsh 的 write 工具；能不加就不加。

---

## 9. REA 逆向 vs 直接读源码：这次的真实差别

### 9.1 一张表

| 维度 | REA 6.4.0 | 直接读源码 |
|---|---|---|
| 覆盖面 | 目录级、可枚举、可计数；8 个 DSHA 包 + 5 个 woaiys3 插件几分钟跑完 | 要自己找入口，容易漏；545 + 21 个 Java 文件不可能全读 |
| 结构 | AST 节点、findings、模块、endpoint/IPC 候选 | 能看懂状态机、时序、失败路径、注释里的血泪 |
| 跨语言 | 只认 JS/TS；Java/Manifest/Gradle 基本看不见 | 能读 Java、Manifest、Gradle、AGENTS、真机日志 |
| 语义 | 保守静态候选；不证明运行时执行/因果 | 能结合注释和文档判断"为什么这样写" |
| 产出 | "这里有什么、多大、哪些字符串像端点" | "为什么这样做、哪里会炸、该怎么抄" |
| 适合 | 第一小时画地图、找大文件/桥接/端点 | 第二小时做架构判断、抄细节、写验收 |

### 9.2 三个具体例子

1. **`android-app` 目录**：REA 只解析了 3 个 `tools/*.mjs`（`manifest-gen.mjs`、`session-admin.mjs`、`session-heal.mjs`），41 条 findings；21 个 Java 文件、32,999 行（含 compat 副本）完全没进图。**如果只看 REA，会以为这个 App 几乎没逻辑。**
2. **DSHA 的 3090 桥**：REA 在七个工具插件里抽到的 endpoint 是 `GIT_CONFIG_COUNT`、`GIT_CONFIG_PARAMETERS`、`GIT_DIR`、`GIT_WORK_TREE`、`HOME`、`PWD`——这些是环境变量，不是 HTTP 端点。真正的 3090 桥在 `HttpShellService.java`，REA 看不见。**如果只看 REA，会完全错过 DSHA 最大的原生能力面。**
3. **woaiys3 的四个 loopback 服务**：REA 在插件里抽到 `/shell`、`/notify`、`/clipboard`、`/setting`、`/browser` 等 endpoint，顺着这些字符串回到 `LocalAuth.java`，才发现"四个服务统一令牌"的设计。**这是 REA 的正向价值：它给的是路标，不是结论。**

### 9.3 结论

- **REA 不是"自动逆向"，是"自动盘点 + 静态候选"**。它最擅长回答"这个目录里有多少 JS、哪些文件最大、有哪些像端点/IPC 的字符串、AST 规模多大"。
- **架构判断必须回到源码**。proot 还是 bionic、PID 身份、Cookie 异步、事务回滚、用户补丁层——这些都不在 AST 里。
- **最好的用法是两段式**：REA 先画地图（10 分钟），人再沿地图读关键文件（1-2 小时），最后用真机/测试验证。只做前者会漏，只做后者会慢。

---

## 10. 没做什么 / 未验证

- **没有构建、安装或运行任何 APK**；没有连手机/模拟器；没有复跑 `verify-v1193.sh`、109 PASS/772 PASS、JUnit、Lint。文中所有"项目自述"的数字都标了出处，不等于本次复现。
- **没有下载或分析 APK 本体**。仓库里没有 APK；REA 的 `inspect-android-package` / `inspect-android-class` / `inspect-android-method` 需要 APK，本次没用上。`offline-rootfs.bin` / `dsh-runtime.bin` / `dshroot` 分块包也不在仓库里，所以"APK 内真实资产"未核。
- **没有逐行读完 545 + 21 个 Java 文件**。读的是启动、鉴权、WebView、桥、备份/恢复、自检/自愈、补丁、浏览器/虚拟屏这些关键路径；其余按目录结构和类名判断。
- **没有验证 dsh 0.2.1-rc.2 的行为差异**，也没有验证 woaiys3 的四类补丁在新版本上是否仍成立；只读了补丁说明和调用点。
- **没有验证 Node v26.4.0 二进制的来源/签名**；只读了构建脚本和 `spawnNode`。
- **没有验证 DSHA 的 288 MB APK、woaiys3 的 162/250 MB 体积**；这些是项目文档/回执的自述。
- **没有改任何项目代码**；只新增本文，并在旧报告顶部加了一条失效箭头。
- **没有 git commit**（按项目规则，未得到你的明确指示不提交）。
- **没有触碰设备、凭证、`/data/local/tmp`、KernelSU/susfs、锁屏、自启**；没有 `adb` 操作。

---

## 11. 附：REA 命令与读数

### 11.1 复现命令

```bash
# 单包
rea analyze-javascript-application \
  "reference/gh-3p/DSHA-main/app/src/main/assets/builtin-plugins/dsh-tool-vscreen" \
  --artifact-format directory --format json \
  > downloads/rea-gh3p/dsha-dsh-tool-vscreen.json \
  2> downloads/rea-gh3p/dsha-dsh-tool-vscreen.err

# 整目录（会被自动路由到 JS provider；Java 不会进图）
rea analyze-javascript-application \
  "reference/gh-3p/deepseek-harness-android-app-main/android-app" \
  --artifact-format directory --format json \
  > downloads/rea-gh3p/woa-app-analyze.json \
  2> downloads/rea-gh3p/woa-app-analyze.err
```

### 11.2 读数表（已剔除重复 `woa-browser.json`）

| 包 | relevant | parsed | bytes | AST | findings |
|---|---:|---:|---:|---:|---:|
| `dsha-dsh-auto-review` | 2 | 1 | 674 | 11 | 2 |
| `dsha-dsh-computer-use-android` | 3 | 2 | 8,932 | 1,566 | 12 |
| `dsha-dsh-destructive-guard` | 4 | 3 | 62,884 | 9,436 | 18 |
| `dsha-dsh-device-shell-guide` | 2 | 1 | 9,358 | 529 | 7 |
| `dsha-dsh-status-overlay` | 2 | 1 | 17,334 | 1,673 | 6 |
| `dsha-dsh-task-notifier` | 2 | 1 | 11,520 | 1,975 | 9 |
| `dsha-dsh-tool-vscreen` | 3 | 2 | 11,572 | 2,154 | 9 |
| `dsha-dsh-web-mobile` | 202 | 133 | 2,373,337 | 80,432 | 652 |
| `woa-dsh-tool-accessibility` | 2 | 1 | 57,645 | 7,570 | 11 |
| `woa-dsh-tool-android` | 2 | 1 | 35,837 | 4,343 | 14 |
| `woa-dsh-tool-browser` | 2 | 1 | 30,331 | 3,908 | 8 |
| `woa-dsh-tool-shizuku` | 2 | 1 | 31,048 | 3,487 | 19 |
| `woa-dsh-tool-vscreen` | 4 | 2 | 61,352 | 7,694 | 37 |
| `woa-app-analyze`（3 个 `.mjs`） | 3 | 3 | 34,286 | 5,413 | 41 |

### 11.3 关键文件索引

| 主题 | DSHA | woaiys3 |
|---|---|---|
| 版本/API | `app/build.gradle:19-45` | `android-app/AndroidManifest.xml:5-8` |
| 启动契约 | `util/WebLaunchCommand.java:16-42` | `MainActivity.java:3974-4090` |
| 进程身份 | `runtime/WebProcessManager.java:175-194,463-469` | `MainActivity.java:8313-8359` |
| token 解析 | `util/DshAuthUrl.java:21-30` | `MainActivity.java:4139` 附近 |
| Cookie/WebView | `ui/WebPreviewActivity.java:674-706,776-808` | `MainActivity.java:296-358` |
| 本地桥 | `HttpShellService.java:50,493,666-668,702` | `LocalAuth.java:9-102` |
| 事务/恢复 | `backup/ManagedRuntimeTransaction.java:243-279`；`recovery/RecoveryRuntime.java:38-49` | `KernelSelfCheck.java:8-49,145`；`SessionHeal.java:27-36` |
| 用户改动 | — | `UserPatches.java:42-46,63-67,339-341` |
| dsh 补丁 | 受管运行时/网页兼容（`AGENTS.md:62,89,109`） | `dsh-patches/README.md:43-46`；`config/cordis.patch.yml:5-61` |
| 移动适配 | `assets/builtin-plugins/dsh-web-mobile/` | `mobile-patch/inject.sh`；`mobile.js:2-43` |
| 设备工具 | `dsh-computer-use-android` 6 + `dsh-tool-vscreen` 13 | accessibility 11 + android 7 + browser 10 + shizuku 5 + vscreen 8 |

---

**最后一句**：这两个项目最值得学的不是"哪个功能多"，而是它们各自把一类失败变成了工程机制——DSHA 把"环境会坏"变成事务/回滚/应急运行时；woaiys3 把"升级会碎"变成清单/自愈/补丁层。你回来编译自己的桌面 harness 时，先决定"我最怕哪类失败"，再选对应的那套机制，不要两套都全量搬。
