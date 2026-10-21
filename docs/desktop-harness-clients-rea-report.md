# 两个 DeepSeek Harness 桌面端：REA 逆向对比报告

> 取证时间：2026-10-21（北京时间）
> 工具：REA 6.4.0（`@morluto/rea`）
> 对象：DeepSeek 官方桌面端 `@deepseek-ai/dsh-desktop 0.2.1-rc.2`；社区桌面端 `dsh-plugin-desktop 2.0.18`（仓库 `anywhere-labs/deepseek-harness-desktop`）
> 用途：给他自己编译桌面端 DSH 时当"架构选型 + 细节清单"用
>
> 标注约定：**事实**＝盘上文件/REA 读数可直接复核；**推断**＝根据代码语义判断，未做运行时验证。

> **→ 2026-10-21 改口：本报告的对象判错了。** 他说的是 `reference/gh-3p` 里的 DSHA 与 `woaiys3/deepseek-harness-android-app`，不是官方桌面端与 anywhere-labs。新报告见 [dsha-vs-woaiys3-rea-report.md](dsha-vs-woaiys3-rea-report.md)。本文保留原文不删，只作"官方桌面端 vs 社区桌面端"的旧参照。

---

## 0. 先给结论

1. **两者不是两个产品，而是同一个上游 `@deepseek-ai/dsh 0.2.1-rc.2` 的两种桌面壳。** 官方是"封闭式整机"，社区是"插件式桌面宿主"。共同点比差异多，差异集中在**进程模型、恢复能力、可扩展性**三件事上。
2. **官方赢在边界与一致性**：自有 `dsh-app://` 协议、自有 runtime、83 个 IPC 通道全部做 sender 校验、WebSocket 只给主窗口注 Cookie、浏览器访客按工作区分区。它把一个"带凭证的本地 Web 应用"关进了很窄的笼子。
3. **社区赢在可恢复性与可运维性**：Host 放进 `utilityProcess`（宿主崩了窗口还在）、安全模式、独立恢复助手、Profile 检查点、插件禁用/卸载/回滚、数据目录迁移、诊断包、系统终端、LAN HTTPS。它假设"环境一定会被玩坏"，并为此写了整套逃生通道。
4. **如果只给自己做一台日常用的桌面 harness**，推荐"社区进程模型 + 官方安全/更新纪律"的混合体：Electron 主进程只做窗口与生命周期，Host 放 utilityProcess，壳页面走自定义协议，先有恢复助手和诊断包，再谈多 Profile、LAN、插件市场。
5. **最值得先抄的 8 个细节**：Host 进程隔离、自定义 secure scheme、sender 三重校验、任务检查后再安装更新、启动前恢复面（安全模式/禁用插件）、诊断包 worker、崩溃报告先落盘再弹窗、WebContentsView 恢复时 `invalidate()`。

---

## 1. 对象、来源与可复现性

### 1.1 两份产物

| 项 | 官方 | 社区 |
|---|---|---|
| 产品名 | DeepSeek（`@deepseek-ai/dsh-desktop`） | DSH Desktop（`dsh-plugin-desktop`） |
| 版本 | 0.2.1-rc.2 | 2.0.18 |
| 安装形态 | 已安装：`D:\program files\DeepSeek\` | 安装包：`downloads\dsh-desktop-dl\DSH-Desktop-2.0.18-x64-Setup.exe` |
| 主产物 | `resources\app.asar` **182,794,869 B** | NSIS 安装包 **330,099,798 B**，解包后 `resources\app` **808,634,535 B / 27,930 文件** |
| SHA-256 | `47874618bf5b3011fcaac10cd4c85f69da333e70d4f99b921207c78d0999512a` | `d1edf6ef53156542e06836e2a478dc3508599a3290c5402eb32f771e7bb09f39` |
| 上游 dsh | `dsh/` 内 `@deepseek-ai/dsh` **0.2.1-rc.2** | 依赖表 `@deepseek-ai/dsh` **0.2.1-rc.2** |
| 壳代码体量 | `lib/` 13 文件 / 966,301 B；`main.js` 516,716 B | `lib/` 178 文件 / 6,103,515 B；`main.js` 216,856 B；`client.js` 690,972 B |
| 自带 runtime | `dsh/` 抽取后 17,262 文件 / 425,299,340 B（≈ `app.asar` 182 MB + `app.asar.unpacked` 255 MB；安装目录另有 `resources/runtime` 约 270 MB） | 打包依赖（`resources/app` 内），未单独拆 runtime 目录 |
| 发布渠道 | 安装包内 `app-update.yml`：generic → `download.deepseek.com/dsh-desk/feeds/win-x64/`，channel `nightly` | 安装包内 `app-update.yml`：GitHub `anywhere-labs/deepseek-harness-desktop` |

> **事实**：两个 sha256 都对上了各自来源（官方安装目录、GitHub Release 资产 digest）。
> **推断**：社区包是从 GitHub Release 下载的 `DSH-Desktop-2.0.18-x64-Setup.exe`；未核验代码签名证书与发布者主体，只核验了哈希。

### 1.2 识别说明

他说的"那两个桌面端 DeepSeek Harness"，盘上能对上的就是这两个：一个是本机已安装的官方 DeepSeek 客户端，一个是 `anywhere-labs` 的社区 DSH Desktop。两者都把上游 `dsh` 的 Web UI 装进 Electron，只是壳的做法完全不同。**如果他还指过第三个客户端，这份报告没有覆盖。**

### 1.3 REA 取证流程（可复现）

```bash
# 官方：先 inspect 出 asar 清单，再只抽壳层，避免对 425 MB（含 unpacked）runtime 做全量 AST
rea inspect-artifact "D:/program files/DeepSeek/resources/app.asar" --json > official-inspect.json

# 壳层目录（lib/、renderer/、根 node_modules/、package.json）单独分析
rea analyze-javascript-application "D:/mycode/dsh-mobile/downloads/rea-desktop/official-shell" --json > official-shell-evidence.json

# 投影成摘要视图
jq -c '{source:{kind:"inline",evidence:.},view:{kind:"summary"}}' official-shell-evidence.json > official-view.json
rea inspect-analysis-view official-view.json

# 社区：NSIS 解包得到 app/resources/app，同样只分析壳层
rea analyze-javascript-application "D:/mycode/dsh-mobile/downloads/rea-desktop/community-shell" --json > community-shell-evidence.json
```

证据文件都在 `downloads/rea-desktop/`（`downloads/` 已 gitignore，不会入库）：

| 文件 | 大小 | 内容 |
|---|---:|---|
| `official-inspect.json` | 23,514,983 B | 官方 asar 完整 inventory（18,309 文件） |
| `official-shell-evidence.json` | 77,989,188 B | 官方壳层完整 Evidence |
| `official-summary.json` | 1,692,763 B | 官方 summary 视图 |
| `official-graph.txt` | 36,980 B | 节点/边投影（窗口、IPC、bridge） |
| `community-shell-evidence.json` | 53,565,787 B | 社区壳层完整 Evidence |
| `community-graph.txt` | 5,471 B | 社区节点/边投影 |
| `official-shell/` | 7,921,531 B / 1,047 文件 | 官方壳层抽取结果 |
| `community-shell/` | 10,328,488 B / 190 文件 | 社区壳层抽取结果 |

---

## 2. REA 看到了什么：它和"直接读源码"到底差在哪

### 2.1 同口径统计

| 指标 | 官方壳层 | 社区壳层 |
|---|---:|---:|
| 相关文件 | 1,001 | 170 |
| 读入文本 | 7,562,604 B | 5,843,195 B |
| 成功解析的 JS 文件 | 947 | 89 |
| 访问 AST 节点 | 1,063,943 | 326,977 |
| 发现（findings） | 2,982 | 825 |
| BrowserWindow | **4** | **2** |
| 显式 webPreferences | 20 | 9 |
| contextBridge API | **11** | **6** |
| 暴露成员 | 16 | 9 |
| IPC 操作 | **83** | **9** |
| 其中字面量通道 / 动态表达式 | 0 / 83 | 1 / 8 |
| 主进程 handler | **35** | 0 |
| sender 校验观察 | 22 | 7 |
| utilityProcess | 0 | **1** |

> **事实**：以上来自两份 Evidence 的 `normalized_result.summary`。
> **推断**：社区的 `main_handlers = 0` 不代表它不用 IPC，而是它的主进程与 Host 之间主要走 `utilityProcess` 的 RPC 和本地 HTTP；REA 数到的 9 个 IPC 集中在兼容层 chrome。官方大量使用 `ipcMain.handle` + 常量通道名，所以 83 个全部是动态表达式。

### 2.2 REA 的"额外反馈"

他的判断是对的：**REA 给的是结构坐标，源码给的是语义。** 具体差别：

1. **先看到形状，再决定读哪里。** REA 一遍就给出"4 个窗口 / 11 个 bridge / 83 个 IPC / 35 个 handler / 0 个 utilityProcess"对"2 个窗口 / 6 个 bridge / 9 个 IPC / 1 个 utilityProcess"。这个对比直接指向了真正的架构差异（官方是单进程壳 + 子进程 Host；社区是 utilityProcess Host + WebContentsView 组合），而不是靠翻文件猜。
2. **可量化、可对比。** 两份 Evidence 用同一套指标，能放在一张表里；纯读源码很难保证"两边都数全了"。
3. **暴露盲区。** 官方的 83 个通道名全是动态表达式，REA 标不出来具体字符串，必须回源码读常量表；官方的语义图还是 `partial/truncated`（节点上限 100,000）。这些限制本身是有用的信息：它告诉你"别把摘要当全貌"。
4. **可追溯。** 每个结论都能落到 Evidence 的节点/位置；产物有 sha256、inventory id、coverage 限制，适合以后复核。

**结论**：REA 适合做"侦察与对比"，不适合替代"读业务语义"。这次的最优组合就是：REA 定坐标 → 源码读关键路径 → 用盘上读数复核。

---

## 3. 两套架构

### 3.1 官方：封闭式整机

```
Electron 主进程 (lib/main.js, 516 KB)
├─ BrowserWindow ×4
│   ├─ main      → dsh-app://app/...      （真 UI，webviewTag=true）
│   ├─ welcome   → dsh-app://shell/welcome.html
│   ├─ update-dialog
│   └─ mandatory-update（Windows 上嵌进主窗口）
├─ 自定义协议 dsh-app:
│   ├─ host=shell → renderer/ 静态壳页面
│   ├─ host=app   → dsh/node_modules/@deepseek-ai/dsh-web-frontend/dist
│   └─ 其余路径   → forwardWebRequest(hostUrl, hostCookie)
├─ 子进程 Host（spawn，stdio 带 ipc）
│   └─ @deepseek-ai/dsh-desktop-host
│       └─ dsh Web 服务（回环 HTTP + WebSocket）
├─ electron-updater（nightly，强制更新策略）
└─ 托盘 / 崩溃报告 / 退出确认 / 浏览器访客
```

启动链路（源码顺序）：

1. 单实例锁 → 读 Desktop 设置 → 登录 shell 环境。
2. `protocol.registerSchemesAsPrivileged(dsh-app, {standard, secure, supportFetchAPI, corsEnabled, stream, codeCache})`（`lib/main.js:11880`）。
3. `protocol.handle(dsh-app, ...)`：壳页面直接发文件；`app` 的 `/`、`/index.html`、`/assets/*`、`/favicon.svg`、`/manifest.webmanifest` 发前端静态文件；Host 未就绪时返回 **503**，其余路径带 Cookie 转发（`12406–12414`）。
4. `spawn(process.execPath, ["--expose-internals", ..., entry, runtimeDir, projectDir, primaryRuntime, pnpm, nodeBin], {stdio:["ignore","pipe","pipe","ipc"]})`（`3794–3811`）。
5. Host 回 `ready` 后开主窗口；窗口加载 `dsh-app://app/`。
6. WebSocket 请求在 `onBeforeSendHeaders` 里注入 Cookie，只对 `ws://127.0.0.1/*`、`wss://127.0.0.1/*` 生效，且只对主窗口（`12447–12469`）。
7. 退出/更新前先向 Host 发 `quit-inspection` 或 `update-tasks`，超时 2 s / 10 s。

### 3.2 社区：插件式桌面宿主

```
Electron 主进程 (lib/main.js, 216 KB)
├─ BrowserWindow（主窗口）
│   └─ WebContentsView 组合
│       ├─ contentView → 上游 dsh Web UI（partition persist:dsh-desktop-renderer）
│       └─ chromeView  → 兼容层标题栏/菜单（独立 partition + 独立 preload）
├─ utilityProcess.fork(host-process-entry.js, serviceName "DSH Host")
│   ├─ Profile Manager / Settings Bridge / 插件包 / 市场
│   ├─ dsh Host（Cordis root，兼容模式）
│   ├─ 回环 WebServer（强制 127.0.0.1）
│   └─ LAN HTTPS edge（可选，绑 LAN，CA 指纹）
├─ 本地 HTML 窗口：setup-wizard / profile-selector / profile-create /
│                  desktop-dialog / recovery / compatibility-chrome
├─ 恢复体系：safe-mode / recovery assistant / profile checkpoint /
│            session_projcache 隔离 / factory reset
└─ 系统终端 / 诊断包 / 通知 / 更新检查
```

启动链路：

1. 单实例锁 → 日志 sink（10 MB/文件、200 MB/目录、7 天）→ 崩溃证据 `active-run.json`。
2. 判断 `--dsh-desktop-recovery` / `--dsh-desktop-safe-mode`；安全模式用一次性 home。
3. `utilityProcess.fork(host-process-entry.js, {serviceName:"DSH Host", stdio:"pipe"})`（`lib/main.js:139`）。
4. Host 内 `HostRpc`（超时 120 s）接管 `boot` / `stop` / `certificate` / `quit`，`boot` 里挂 Cordis、LAN、代理、WebServer（`host-process-entry.js:229–304`）。
5. 主进程 `WebContentsView` 先加载 content，再叠 chrome；窗口尺寸变化时分别 `setBounds`。
6. 启动失败 → `RendererStartupFailure` / 超时 120 s → 打开恢复助手或安全模式。
7. 退出时 Host 3 s 内收尾，失败则记录并继续。

### 3.3 一张表看完差异

| 维度 | 官方 | 社区 |
|---|---|---|
| 定位 | 第一方、封闭、开箱即用 | 第三方、插件式、可改造 |
| 与上游关系 | 自带完整 runtime，版本锁死 | 作为 Cordis 插件插进上游，兼容模式 |
| Host 进程 | `spawn` 子进程 + IPC | `utilityProcess.fork` + RPC |
| 主 UI | 单 BrowserWindow 加载 `dsh-app://app` | BrowserWindow + WebContentsView（chrome/content 分离） |
| 本地页面协议 | 自定义 `dsh-app://` | 本地 HTTP + `dsh-desktop-dialog:` / `dsh-recovery:` |
| IPC 面 | 83 通道 / 35 handler / 11 bridge | 9 通道 / 6 bridge / 1 utility process |
| 多 Profile | 无（单环境） | 有（创建/切换/检查点/渠道隔离） |
| 恢复 | 致命错误对话框 + 崩溃报告 + 禁用第三方插件 | 安全模式 + 恢复助手 + 检查点回滚 + 工厂重置 + 缓存隔离 |
| 诊断 | 崩溃报告文件（含 renderer console 尾部） | 诊断 ZIP（worker 导出）+ 开发者日志 + 生命周期证据 |
| 终端 | 无 | 系统终端 + shell/DSH/pnpm/node shim |
| LAN | 仅回环 | 可选 LAN HTTPS + CA 下载 |
| 更新 | electron-updater + 强制更新策略 + 更新日志/注意力提醒 | GitHub Releases + 自研检查/下载 + SHA-256 校验 |
| 插件生态 | 官方内置/官方插件 | 社区市场 + pnpm + 插件管理 |
| 体积 | `app.asar` 182 MB + unpacked 255 MB（dsh 抽取后 425 MB） | 安装包 330 MB，解包 808 MB |

---

## 4. 共同点（这些是可以直接照抄的"底线"）

1. **都是"Electron 壳 + 本地 dsh Web UI"**，不是把 UI 重写成原生。
2. **渲染进程一律 `contextIsolation: true`、`nodeIntegration: false`、`sandbox: true`、`webSecurity: true`**；UI 只能通过 preload 暴露的窄接口做事。
3. **都有独立的本地页面**（欢迎/引导/更新/恢复/对话框），不把系统级 UI 混进业务页面。
4. **Host/WebServer 只绑回环**；对外暴露是后加的能力，不是默认。
5. **更新都不自动装**：先检查、再让用户确认、安装前处理运行中的任务、最后重启。
6. **都处理"Host 没起来"和"Host 崩了"**：官方是 503 + 致命对话框；社区是恢复助手 + 安全模式。
7. **都做窗口生命周期**：单实例、第二次启动聚焦、托盘/隐藏、退出确认、主题/标题栏同步。
8. **都避免把凭证写进可回看的地方**：官方 Cookie 只在内存/请求头里；社区登录 session 不落盘，日志做脱敏。
9. **都对第三方内容设边界**：官方浏览器访客独立 partition、禁下载/权限；社区弹窗一律 deny、导航白名单。
10. **都有一份"壳"与"上游"的版本对应关系**，出问题能定位是壳还是 dsh。

---

## 5. 官方：优点与细节优化

### 5.1 安全边界（最值得学）

- **自定义 scheme 一次给全权限**：`standard + secure + supportFetchAPI + corsEnabled + stream + codeCache`（`lib/main.js:11880`）。这样页面是"真 origin"，能正常用 fetch/CORS/Service Worker，同时又不是 `file://`。
- **Host 未就绪返回 503**（`12411`）：请求不会打到不存在的 Host，前端可据此重试或提示。
- **WebSocket 头注入只开一条缝**：
  - 只匹配 `ws://127.0.0.1/*`、`wss://127.0.0.1/*`；
  - 只对主窗口的 `webContentsId`；
  - 目标 host/protocol 必须与 `hostUrl` 一致；
  - 请求头 `origin` 必须是 `dsh-app://app`，否则直接 cancel；
  - 通过后把 `origin` 改成目标 origin，塞 `cookie`，补 `sec-fetch-site: same-origin`（`12447–12469`）。
- **sender 三重校验**：`event.sender === mainWindow.webContents`、`event.senderFrame === mainFrame`、`frame.url` 必须是 `dsh-app://app/`。`assertDesktopSender` 还单独校验协议与 hostname（`7015–7019`）。
- **Platform 命令只认主应用帧**：`assertMainApplication` 检查 sender、mainFrame、URL 前缀（`12470–12474`）；`page` 只允许 `usage`/`top-up` 两个值（`12484`）。
- **目录选择器防重入**：同一窗口的 pending Promise 复用，窗口最小化先 restore，再 show/focus（`7030–7043`）。
- **麦克风权限只给主应用帧**：校验 `contents === primary()`、`isMainFrame`、origin 是 `dsh-app://app`、`mediaType === "audio"`，macOS 还要系统授权（`7062–7069`）。
- **浏览器访客（webview）的笼子**（`10481–10664`）：
  - 每个 workspace 一个进程生命周期 partition（`dsh-sidebar-browser-<uuid>`）；
  - lease 绑定 owner 窗口，`about:blank#<lease>` 握手，`will-attach-webview` 里先删掉页面给的所有 prefs，再强制写安全值；
  - `nodeIntegration*` 全 false、`contextIsolation/sandbox/webSecurity` 全 true、`webviewTag: false`、`plugins: false`、`disableDialogs: true`；
  - 禁止 URL 里带 username/password；只允许 `http/https`（导航）与 `about/data/blob`（请求）；
  - 禁止下载、禁止 HTTP auth、禁止再嵌 webview；
  - 新窗口请求转成 IPC 让主应用决定，不在访客里开；
  - 主框架导航、`render-process-gone`、窗口销毁时统一释放 lease。

> 这些细节说明：官方不是"Electron 默认配置 + 关掉 nodeIntegration"，而是把每个入口都当成不可信输入重新校验了一遍。

### 5.2 启动与协议

- Host 子进程启动参数带 `--expose-internals`，开发模式可开 `--inspect=127.0.0.1:<port>`；stderr 只留最后 64 KB（`3794–3816`）。
- Host 消息白名单：`ready` / `platform-session` / `shutdown-complete` / `fatal` / 控制响应；非法消息直接 `SIGTERM`（`3818–3837`）。
- `updateTasks("inspect"|"lock"|"unlock")`：安装前先 drain 已准入请求，再查任务；drain 超时不授权安装（`3857+`）。
- 退出检查 2 s（`QUIT_INSPECTION_DEADLINE_MS = 2e3`，`3663`），超时就按"有任务"处理，不无限等。
- 窗口参数：1280×820、最小 520×600；Windows 只在主窗口用 `titleBarStyle: "hidden"` + `titleBarOverlay`（高 40，颜色随深浅色），macOS 用 `hiddenInset` + `trafficLightPosition {16,18}` + vibrancy（`11935–11960`）。
- 引导阶段动态调最小宽度：onboarding 激活时从 520 提到 960，窗口不够宽就拉宽（`12529–12537`）。这是一个很小的细节，但能避免引导页在窄窗口里挤成一团。

### 5.3 更新、退出与任务

- `autoDownload = false`、`autoInstallOnAppQuit = false`；检查/下载/安装是三件事，不混在一起。
- 安装前 `beforeRestart()`：任务授权 → 准入锁 → 关闭自有进程；然后 `quitAndInstall(true, true)`。
- 更新确认区分"有活动任务 / 有定时任务 / 两者都有 / 未知"，未知也会警告（`DesktopQuitConfirmation`）。
- `DesktopUpdateAttention`：下载完成后，如果窗口没聚焦，Windows `flashFrame(true)`、macOS dock bounce、再发一条静音通知；每个版本只提醒一次；点击通知回到确认界面（`9670–9760`）。
- `DesktopUpdateJournal`：只在 `DSH_DESKTOP_UPDATE_JOURNAL_DIR` 设置时启用；每行只记 phase、目标版本、整数进度、失败操作和**固定错误码白名单**，不记原始错误文本/URL（`9019–9102`）。
- 更新轮询：默认 10 分钟，抖动 0.2，最大退避 1 小时；聚焦/唤醒/手动检查会触发（`9121–9136`）。
- 强制更新策略：`dshMandatoryUpdatePolicy` 指向 `harness.deepseek.com`，页面 origin 白名单；Windows 上强制更新 UI **嵌在主窗口**里，不开子窗口（`9762+`）。
- 强制更新确认带 `confirmationRevision`，防止旧页面拿旧确认去安装；`later` 只在确实提供任务延期时可用（`9800–9823`）。

### 5.4 崩溃与恢复

- **崩溃报告先写盘，再弹窗**：最多等 1 s；报告包含错误、可枚举属性、cause 链、进程事实、renderer 最近 64 KB 的 error 级 console（`8301–8456`）。
- 对话框 detail 预算 1200 字符，只取错误最后 8 行；报告路径单独一行；`EADDRINUSE` 有专门文案（`8352–8358`）。
- **只处理第一次致命错误**：后续报告直接 resolve，不会叠一堆对话框（`8344–8346`）。
- 恢复按钮：退出 / 重启 / **禁用第三方插件**；恢复操作本身失败时，把 message 换成"恢复失败"并显示新错误，继续循环（`8367–8385`）。
- 崩溃报告文件名带 ISO 时间和来源（`host` / `web-boot` / `renderer` / `main`），清理只删匹配这个格式的文件（`8416`）。

### 5.5 内嵌浏览器

- （见 5.1 最后一段）访客分区按 workspace，lease 按窗口，释放时等 `destroyed` 再删；主框架导航会释放该窗口全部 lease，避免旧页面留下后台进程（`10612–10621`）。

### 5.6 窗口、托盘、引导

- 托盘常驻；点击打开；菜单有 Open / Quit；隐藏到托盘第一次会弹确认，确认结果持久化到 `userData/background-close-confirmed`。
- 关闭窗口默认隐藏而不是退出；退出确认会区分活动/定时任务。
- 欢迎/引导有独立窗口和 `preload-welcome`；授权 URL 自动打开；失败/过期会聚焦；凭证写入后自动进工作区。
- 分析默认关闭，需要显式 opt-in；locale/theme 双向同步；Windows 应用菜单/编辑菜单/标题栏颜色都从 renderer 回传。
- DevTools 入口在菜单里隐藏，F12 只在非 Windows 保留。

### 5.7 官方的不足

- **单体壳**：`main.js` 516 KB，4 个窗口、83 个通道、35 个 handler，读和改都重。
- **单 Profile**：环境坏了主要靠"禁用第三方插件 + 重启"，没有检查点/回滚/多环境。
- **没有内置终端、诊断包、LAN**：排查手段偏"崩溃报告"。
- **产品策略强**：nightly + 强制更新 + 遥测入口，个人改造空间小。
- **体积大**：asar 182 MB + unpacked 255 MB，dsh 抽取后约 425 MB。
- **权限处理有取舍**：主 session 只特判麦克风，其他权限走 Electron 默认；真正严格的是浏览器访客 session。自己抄的时候别把这段当成"全部 deny"。

---

## 6. 社区：优点与细节优化

### 6.1 进程隔离与渲染组合

- **Host 在 utilityProcess 里**：`utilityProcess.fork(host-process-entry.js, {serviceName:"DSH Host", stdio:"pipe"})`（`lib/main.js:139`）。主进程只做窗口/生命周期；Host 崩了，窗口和恢复 UI 还在。
- Host 入口明确声明"不 import BrowserWindow/Electron main API"（`host-process-entry.js:230`），把 Host 变成可测试的纯服务。
- stderr 尾部只留 16 KB（`main.js:158`），RPC 超时 120 s（`160–168`），停止时 3 s abort（`194–199`）。
- **WebContentsView 组合**：
  - content view 用 `persist:dsh-desktop-renderer`，chrome view 用独立 partition（`electron-runtime…js:672, 807–824`）；
  - chrome 的 IPC 校验 exact sender + mainFrame + **文件 URL 完全相等**（`839–842`），比只查 origin 更严；
  - chrome 禁止导航/重定向/webview/新窗口（`835–838`）；
  - 窗口恢复时先 `resize()` 再对两个 view `invalidate()`；注释解释了为什么不能用 `backgroundThrottling:false`（会让整个窗口在最小化时继续绘制，renderer 也无法回收内存）（`919–940`）。
- **三种窗口形态**：compatibility / advanced / extended；macOS 支持透明 + vibrancy，Windows 用 `titleBarOverlay` + 圆角/阴影/厚边框，Linux 回退原生。
- **本地对话框协议** `dsh-desktop-dialog:`：1–4 个按钮、default/cancel 索引、`preferred-size-changed`、250 ms reveal 兜底、模态一次性、关闭即取消、文档/绘制/布局就绪前不 reveal。
- **登录 session 不落盘**：Platform 登录用内存 session，cookie 不写磁盘；权限一律 deny；登录弹窗按 URL 分类（`1512–1540`）。

### 6.2 可恢复性（社区最强的一块）

**安全模式**（`lib/main.js:3494–3601`）：

- 一次性目录 `userData/safe-mode/{dsh-home,desktop-state}`；写 `environment.json` 标记（版本 + createdAt），目录/标记都必须是真目录/真文件，拒绝符号链接。
- 固定默认：市场关闭、通知全关、`networkExposure: loopback`、`openBrowser: false`、无 Setup。
- 启动时如果 `DSH_HOME` 指向安全模式 home，先删掉，避免继承；退出时清理一次性目录；托盘提供"退出安全模式"。
- 准备失败会整体清理，不留半套环境。

**恢复助手**（`1052–1541`）：

- 独立于 Host 的 Electron 窗口；页面走 `dsh-recovery:`，**只接受固定 action 白名单**（卸载/禁用/启用/检查点/打开目录/导出诊断/进安全模式/换数据目录/工厂重置/切 Profile/重启/退出）（`1496–1520`）。
- 参数严格校验：`id` 长度 8–160；检查点只接受 `slot-1..3`；`switch-profile` 的 name 不能有 `/`、`\`、NUL、CR/LF，UTF-8 ≤ 255 B；`apply-data-directory` 的 path ≤ 32 KB。
- **预览令牌**：卸载/恢复/禁用/启用都先 `preview*` 拿一个 5 分钟 TTL 的 token，最多 256 个，执行时校验 token + profile + generation，且同一时间只允许一个操作（`1055–1063, 1129–1181`）。
- **generation 校验**：所有操作前后都确认当前 Profile/generation 没变，避免在恢复过程中被外部切换（`1393–1403`）。
- 错误脱敏：`maskSecrets` + 24,000 字符上限，只把脱敏后的 detail 给 UI（`1430–1434`）。
- 可恢复对象：插件卸载、插件禁用/启用、Profile 检查点回滚、打开检查点目录、修改/恢复数据目录、工厂重置（`shell.trashItem`，并拒绝文件系统根、拒绝包含 home/appData/安装目录/当前目录的目标）。

**启动兜底**：

- 生命周期记录器分阶段（`electron-ready` → `shell-environment` → `runtime-bootstrap` → `profile-selection` → `profile-composition` → …），失败时知道停在哪。
- `active-run.json` 检测上次是否干净退出；unreadable 也单独记一条。
- Renderer 启动失败分 `renderer-failed` / `renderer-timeout`；超时 120 s（`RENDERER_BOOT_TIMEOUT_MS`）。
- 可选 UI 插件启动失败会被跳过并通知，不让一个插件拖死整个启动（`notifySkippedOptionalEntries`）。
- `session_projcache.json` 超过 128 MB 就改名为 `*.oversized-<UTC 时间戳>.json` 隔离，让上游从历史重建（`3603–3658`）。
- Windows 卷诊断：安装目录/用户数据/DSH home 落在不支持的文件系统时，UI 就绪后弹一次通知，stderr 写精确路径（`3835–3853`）。

### 6.3 多 Profile 与渠道隔离

- 每个 release channel 有自己的 home 目录名；不会把稳定版/beta 的 `~/.dsh` 混用。
- 注释点明了真实问题：共享 home 也共享 `profiles/node_modules`，每个 core generation 启动都会重写模块索引；两个版本交错时，Profile 扫描可能读到"半愈合"的索引，把已装插件报成缺失（`3660–3672`）。
- 已有安装不会被隐式搬走：只有本渠道 home 不存在、共享 home 可用时，才继续用共享 home，并提示重叠（`3696–3707`）。
- Profile 兼容性准入：检查该 Profile 是否被另一个渠道/更新版本写过；不允许时给"切换 Profile / 仍然使用 / 退出"三个选择（`4389–4417`）。
- Profile 检查点、依赖物化（`materializeProfile`）、模块回退修复（`healDesktopProfileModuleFallback`）构成"升级前可回滚"的闭环。

### 6.4 终端（系统终端 + shim，不是内嵌 pty）

- 托盘命令打开**系统终端**：macOS `open -a Terminal`；Windows 优先 Windows Terminal，其次 PowerShell 7 / Windows PowerShell / cmd（`desktop-terminal…js:394–413, 470–510`）。
- 为当前 Profile 生成私有 shim 目录：`dsh` / `pnpm` / `node` 三个命令；`ELECTRON_RUN_AS_NODE=1` 只作用于子进程（`101–119`）。
- 生成文件用临时文件 + `renameSync` 原子替换，拒绝符号链接目标，权限 0600/0700（`76–99`）。
- 所有值做 NUL/CR/LF 校验；PowerShell/cmd 欢迎脚本分别转义；`shell:false`，argv 数组启动，避免拼接注入（`55–66, 414–444`）。
- Linux 打包版直接禁用（`cordis.patch.yml` 里 `disabled: !!js process.platform === 'linux'`）。

> **修正**：我最初以为它是内嵌 `node-pty`，读源码后确认不是。它是"系统终端 + 生成 shim"，优点是零原生依赖、跟用户自己的终端体验一致；缺点是不能在应用内嵌一个终端面板。

### 6.5 诊断与可观测性

- **诊断 ZIP 在 worker 里导出**：`new Worker(..., {resourceLimits:{maxOldGenerationSizeMb:256}})`，证据上限 50 MB；包含 logs、host logs、Crashpad、`active-run.json`、生命周期证据（`diagnostic-export…js`）。
- 开发者日志：进程内 runId + sequence + pid + level；`sanitize()` 后再写；`developerLogging` 关闭时只保留 error 级（`developer-logging…js`）。
- renderer 日志：console 限速 100 条/秒、单条 8192 字符；只保留 error 级（开发者日志关闭时）；识别 `[desktop-ui-error]`、`slot entry crashed` 等标记（`electron-runtime…js:313`）。
- renderer boot health：UI 主动上报 `{status, error, plugins}`；主进程 120 s 未收到就判 `renderer-timeout`（`2824, 3428, 3599`）。
- UI 里有"重新加载界面"入口；恢复助手也能打开终端/导出诊断/看配置路径。

### 6.6 Windows 沙箱与跨平台细节

- **PowerShell 路径固定**：优先 `%ProgramFiles%\PowerShell\7\pwsh.exe`，再 `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`；避免 PATH 里的便携版 pwsh 进沙箱（`windows-pwsh-sandbox.js:11–16`）。
- `pwshPath` 用 getter 引用，而不是构造时快照；用户后续改配置能生效（`32–48`）。
- **ELECTRON_RUN_AS_NODE trampoline**：上游 ACL runner 本来用 `execPath` 启动，Electron 不是 Node；这里在 argv 层替换成 `execPath + trampoline + upstreamRunner`，并清掉大小写不同的 `ELECTRON_RUN_AS_NODE` 再设 `1`（`56–77`）。
- **先分配 console 再套受限 token**：否则受限子进程没有 console；用 koffi 调 `user32.ShowWindow` 控制窗口（`windows-acl-runner.js:1–140`）。
- **Windows 卷诊断**：不支持的文件系统（如某些网络盘/压缩盘）会在沙箱/pnpm 阶段变成难懂的错，所以启动时先诊断并提示。
- **AppImage 重启**：不用 `app.relaunch()`（会指向已卸载的 `/tmp/.mount_*`，或 setuid fusermount 在 `no_new_privs` 下失败），而是 detached bash：先关掉 >2 的 fd，等旧 pid + 解包 runtime 退出，再从环境变量里剥掉本次 mount 的 PATH/LD_LIBRARY_PATH/XDG_DATA_DIRS/GSETTINGS_SCHEMA_DIR，最后 exec AppImage（`3349–3476`）。
- **代理探测**：直接问 Chromium `resolveProxy`（它已经读了注册表/系统设置/PAC/WPAD），3 次尝试、200 ms 退避；结果只通过返回值进入日志，避免同一诊断打印两遍或与实际决策不一致（`3734–3792`）。

### 6.7 LAN HTTPS

- 基础 WebServer 强制 `host === "127.0.0.1"`（`webserver.js`）；LAN 是后加的 HTTPS edge，不是直接把 HTTP 绑到 0.0.0.0。
- 证书/CA 指纹是显式配置；CA 通过 `/.well-known/dsh-desktop-ca.crt` 提供；私钥用 `safeStorage` 保护，Linux 上拒绝 `basic_text`/`unknown` backend（`main.js:3793–3805`）。
- edge 只在拿到上游实际回环端口后 attach 一次，拒绝重复 attach（`lan-https-runtime…js:323–341`）。

### 6.8 更新

- 自研检查：固定版本端点 + 渠道 semver 解析；安装 ID 是持久化 UUID v4，放在私有目录（0700/0600），文件锁 + 原子写，损坏/符号链接会显式报错，不会每次静默换新 ID（`update-checker…js:1–110`）。
- 下载：只允许最终落在 HTTPS、无用户名/密码、端口为空或 443；支持 expected SHA-256，用 `timingSafeEqual` 比较；写盘有进度检查（0 字节写入算失败）（`update-download…js:291–355`）。
- 更新 UI 与 Profile/任务状态联动；安装前停 Host，失败可回退。

### 6.9 社区的不足

- **状态空间大**：三种窗口形态 × 多 Profile × 渠道 × 安全模式 × 恢复模式，组合多，测试成本高。
- **自研面广**：Profile、检查点、恢复、更新、LAN、终端、诊断都是自己维护，升级上游时容易踩兼容。
- **信任链弱于官方**：GitHub Release + 自签/无签名，用户要自己判断发布者。
- **体积更大**：解包 808 MB。
- **兼容层是两层 UI**：chrome 是本地 HTML，content 是上游 UI，接缝处需要额外同步主题/尺寸/交互。
- **终端不是内嵌的**：想要 IDE 式体验还得自己加 pty。

---

## 7. 给他自己的桌面 harness：借鉴清单

### 7.1 推荐架构（个人日常用）

```
Electron main（只做窗口/托盘/更新/恢复 UI）
├─ utilityProcess Host
│   ├─ dsh / Cordis / WebServer（127.0.0.1）
│   └─ 配置、插件、Profile、诊断
├─ BrowserWindow + WebContentsView
│   ├─ content = 上游 UI
│   └─ chrome  = 自己的标题栏/菜单（可选）
├─ 自定义 scheme（secure/standard/stream）
└─ 恢复助手（本地 HTML，不依赖 Host）
```

**一句话**：抄社区的进程隔离与恢复，抄官方的协议/校验/更新纪律；不要抄官方的 4 窗口单体和强制更新。

### 7.2 优先级清单

| 优先级 | 事项 | 具体做法 | 参考 |
|---|---|---|---|
| P0 | Host 进程隔离 | `utilityProcess.fork`，主进程不 require dsh/Cordis；RPC 带超时；stderr 留尾部 | 社区 `main.js:139` |
| P0 | 自定义 secure scheme | `standard/secure/supportFetchAPI/corsEnabled/stream/codeCache`；Host 未就绪返回 503 | 官方 `11880, 12406` |
| P0 | 渲染安全 | `contextIsolation/sandbox/webSecurity=true`、`nodeIntegration=false`；preload 只暴露白名单方法 | 两边 |
| P0 | sender 校验 | `sender + mainFrame + URL origin` 三重校验；每个 IPC handler 都做 | 官方 `7015, 12470` |
| P0 | 恢复面 | 启动失败时打开本地 HTML：重试/安全模式/禁用插件/打开日志/换数据目录 | 社区 `1052–1541` |
| P0 | 崩溃报告 | 先落盘再弹窗；含错误链、进程事实、renderer console 尾部；1 s 超时 | 官方 `8301–8456` |
| P1 | 更新纪律 | check/download/install 分离；安装前查任务并停 Host；不自动装 | 官方 `7748+, 12329` |
| P1 | 诊断包 | worker 导出 ZIP，限制内存与证据字节；含日志/Crashpad/active-run | 社区 `diagnostic-export…js` |
| P1 | 日志轮转 | 单文件 10 MB、目录 200 MB、保留 7 天；启动时 enforce | 社区 `main.js:3937` |
| P1 | 终端 | 系统终端 + 生成 `dsh/pnpm/node` shim；零原生依赖 | 社区 `desktop-terminal…js` |
| P1 | renderer 健康 | UI 主动上报 boot health；120 s 超时；错误标记 + 重新加载 | 社区 `electron-runtime…js:2824, 3599` |
| P2 | Profile/检查点 | 至少升级前快照 `package.json` + settings；插件多再做多 Profile | 社区 `1052–1445` |
| P2 | 缓存隔离 | 超大 `session_projcache` 改名隔离，交给上游重建 | 社区 `3603–3658` |
| P2 | LAN HTTPS | 默认回环；需要时再加 HTTPS edge + CA 指纹 + safeStorage | 社区 `lan-https-runtime…js` |
| P2 | 浏览器访客 | 独立 partition、lease、禁下载/权限、URL 无凭证 | 官方 `10481–10664` |

### 7.3 不要照抄的地方

- **4 个 BrowserWindow + 83 个 IPC 通道**：个人项目没必要拆这么细；能合并的窗口合并，通道按域分组。
- **强制更新策略 + 遥测**：个人用不上，反而添乱。
- **兼容层双 UI**：如果直接改上游 UI，就不要再加一层 chrome；WebContentsView 适合"壳与内容分离"的明确需求。
- **自带大 runtime**：dsh 抽取后约 425 MB（asar 182 MB + unpacked 255 MB）。如果本机已有可控的 dsh 运行时，优先复用；要分发再考虑打包。
- **把权限默认放开**：官方主 session 只特判麦克风，这是产品取舍；自己写就默认 deny，按需开。

### 7.4 最小可用启动清单

1. `app.requestSingleInstanceLock()`；第二次启动聚焦已有窗口。
2. 日志 sink + `active-run.json`。
3. 解析 `--safe-mode` / `--recovery`。
4. `utilityProcess.fork(host)`，等 `ready`。
5. 注册 `dsh-app://`，Host 未就绪返回 503。
6. 开窗口，加载壳页面 → 上游 UI。
7. preload 暴露 `boot/deviceInfo/updates/picker` 等少量方法，每个 handler 做 sender 校验。
8. 托盘 + 关闭到托盘（首次提示）+ 退出确认（有任务时）。
9. 更新检查（只检查，不自动下载/安装）。
10. 启动失败 → 恢复助手；崩溃 → 报告 + 重启/禁用插件。

---

## 8. 证据索引

| 结论 | 证据位置 |
|---|---|
| 官方 4 窗口 / 83 IPC / 11 bridge / 35 handler | `downloads/rea-desktop/official-summary.json` → `normalized_result.summary` |
| 社区 2 窗口 / 9 IPC / 6 bridge / 1 utility process | `downloads/rea-desktop/community-shell-evidence.json` → `normalized_result.summary` |
| 官方协议与转发 | `official-shell/lib/main.js:11880, 12406–12414` |
| 官方 WS 注入 | `official-shell/lib/main.js:12447–12469` |
| 官方 sender 校验 | `official-shell/lib/main.js:7015–7019, 12470–12474` |
| 官方 Host 启动 | `official-shell/lib/main.js:3794–3816` |
| 官方崩溃/恢复 | `official-shell/lib/main.js:8301–8456` |
| 官方更新日志/调度 | `official-shell/lib/main.js:9019–9136` |
| 官方更新注意力/强制更新 | `official-shell/lib/main.js:9670–9823` |
| 官方浏览器访客 | `official-shell/lib/main.js:10481–10664` |
| 官方托盘/退出确认 | `official-shell/lib/main.js:11618–11799` |
| 官方启动主流程 | `official-shell/lib/main.js:12000–13120` |
| 社区 Host utilityProcess | `community-shell/lib/main.js:139–199` |
| 社区 Host 入口 | `community-shell/lib/host-process-entry.js:229–304` |
| 社区 WebContentsView | `community-shell/lib/electron-runtime-Be7e-XQ5.js:672, 780–1002` |
| 社区安全模式 | `community-shell/lib/main.js:3494–3601` |
| 社区恢复助手/令牌 | `community-shell/lib/main.js:1052–1541` |
| 社区缓存隔离 | `community-shell/lib/main.js:3603–3658` |
| 社区终端 | `community-shell/lib/desktop-terminal-CSXxo5CR.js` |
| 社区 Windows 沙箱 | `community-shell/lib/windows-pwsh-sandbox.js`, `windows-acl-runner.js` |
| 社区诊断 | `community-shell/lib/diagnostic-export-CHpLmCFd.js`, `diagnostic-export-worker.js` |
| 社区 LAN HTTPS | `community-shell/lib/lan-https-runtime-6lVFk32q.js` |
| 社区更新校验 | `community-shell/lib/update-checker-CND31yfF.js`, `update-download-DHyLShyy.js` |

---

## 9. 没做什么 / 未验证

1. **没有启动这两个客户端做运行时验证**：没抓 UI、没点菜单、没测真实更新/登录/LAN 握手/终端启动。所有行为结论来自静态代码。
2. **没有对官方 `dsh/` 运行时做全量 AST**：182 MB asar 全量分析约 70 分钟，只分析了壳层（1,001 文件）；`dsh/` 只核对了版本、体积和入口。社区同样只分析壳层。
3. **没有验证动态 IPC 通道名**：官方 83 个通道在 REA 里全是动态表达式；具体字符串是回源码读常量表得到的，未做运行时抓包。
4. **没有核验代码签名/发布者证书**：只核验了 SHA-256 与 Release digest。社区包的签名链、官方安装包的 Authenticode 都没查。
5. **没有比较许可证**：官方 package.json 写 MIT；社区仓库许可证未查。
6. **没有改任何源码、没有提交 git、没有动设备侧**：所有产物都在 `downloads/rea-desktop/` 与本文档。
7. **`downloads/` 已 gitignore**：证据文件不会被提交；如果以后要复核，按第 1.3 节命令重跑。
8. **社区"0 个 main handler"是 REA 的统计口径**：不代表它没有主进程 IPC；它的 Host 通信主要走 utilityProcess RPC 和 HTTP。
