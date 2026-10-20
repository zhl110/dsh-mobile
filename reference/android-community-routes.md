# 社区两条 Android/Termux 路线精读，以及对我们这套的账

> 同一批调研的第二份、形态不同：三家**装 APK 就能用**的方案（DSHA / Soodok / woaiys3）读在
> [`android-three-community-apps.md`](android-three-community-apps.md)。那份的主菜是"三家最终档位都落在
> `danger-full-access`，其中一家的 `sandboxMode` 是谎报的"；这份讲的是 Termux 命令行那一族。

读的东西（全部 `git clone --depth 1` 到本目录，逐文件读过，不是只看 README）：

| 仓库 | commit | 最后提交 | star | 体量 | 基线版本 |
| --- | --- | --- | --- | --- | --- |
| `Vengisk/deepseek-harness-termux` | `4e56ebf3440e1eaa4ac61c611bcab085b089776e` | 2026-08-26 | 71 | 268 K（源码） | dsh **0.1.0-rc.6** |
| `FunnelCakes/deepseek-harness-android` | `52b2ca07f1dc19d213ee141d4a7ffce385cd01ed` | 2026-08-18 | 46 | 283 K（源码） | 自陈"最高支持 **rc.7**" |

顺带从它们的 issue / README 里挖出来的：`mexiaosqwq/dsh-web-mobile`（152★，**2026-10-18 还在动**）、
`qiannianhuanxiang/DSHA`（安卓启动器 APK，内置上面那个插件）、`woaiys3/deepseek-harness-android-app`、
`cokelaoshi1/android-termux-dsh`、上游 Discussion **#136**（Android/Termux 部署）与 **#248**（Android 禁 hardlink）。
以及一个 **`awesome-dsh-plugin.com`** —— dsh 有第三方插件市场，这个我们之前完全不知道。

**先给一句总账**：这两个项目都是 **Termux 原生（Bionic）** 路线，我们是 **root + glibc chroot** 路线。
他们 8 成的补丁是在还 Bionic 的债，我们花 1.7 G rootfs 买断了这笔债 —— 这条对照 RUNBOOK §1 早就写了，
这次拿到了**具体到补丁编号的证据**。但他们有三件事我们确实没想到，其中一件能直接改掉现在卡住的沙箱决定。

---

## 一、他们各自怎么做的

### Vengisk/deepseek-harness-termux

`install.sh`（31,672 B，幂等）+ 8 个 `diff -u` 补丁 + 一套预编译产物。做法是**改 dsh 源码本身**：

1. 全局 `npm i @deepseek-ai/dsh` → 对各个 `@deepseek-ai/dsh-*` 子包逐个 `patch -p1`；
2. 在手机上**现编** `koffi` 与 `node-pty`（要 clang + cmake + `ndk-multilib` + `libandroid-spawn`，README 说 5–10 分钟）；
3. 再发一个"免编译"方案：`dsh-termux-full.tgz`（约 57 MB，整棵打好补丁的 node_modules）或
   `dsh-termux.tgz`（360 KB，postinstall 现拉）—— 由 `scripts/build-prebuilt.sh` 在 PC 上产出。

补丁清单（每条都对应一个 Bionic/sepolicy 的坑）：

| 补丁 | 目标包 | 修什么 |
| --- | --- | --- |
| 01 | `dsh-terminal-bash` | Android 没有 `/bin/bash`，shell 路径要按 Termux 解析 |
| 02 | `dsh-session-persistence-jsonl` | sepolicy 禁 `link(2)` → 回退原子 `rename(2)` |
| 03 | `dsh-subprocess-local` | 进程组检查 `kill(-pid,0)` 把 `android` 视同 `linux` |
| 04 ×2 | `dsh-host-apiproxy` | 打开文件/URL 改走 `termux-open`；原生路径检测 |
| 05 | `dsh-host-directory-picker-native` | 目录选择器走 Linux(zenity) 分支 |
| **07** | `dsh-sandbox-local` | **把 proot 加进沙箱 runner 链**（见第三节，最值钱的一条） |
| 08 | `dsh-tool-fs-search` | ripgrep 平台包在 android 上解析不到 |
| koffi-statx | `koffi` | Bionic 无 `statx()`，编译期剔掉、回退 `stat()`/`fstat()` |

### FunnelCakes/deepseek-harness-android

`setup.sh`（15,298 B）+ `apply-frontend.sh` + `apply-js-patches.sh` + `patches/patch-dsh-android-link.js`（11,428 B）
+ `start_dsh.sh` / `stop_dsh.sh` / `restart_dsh_now.sh`。同样是改源码路线，但**重心放在前端可用性**上：
`patches/mobile.css`（7,637 B）与 `patches/mobile.js`（13,211 B）直接注进 `dist/index.html`，
外加 `config/cordis.patch.yml` 覆盖配置层。作者测试环境是**华为 Mate 60 / HarmonyOS 4.2 / 无 root / Node v26**。

---

## 二、他们修的坑，哪些在我们这儿天然不存在（chroot 白捡的）

这张表是我这次读下来最实在的一块 —— 每一条我都在自己设备上验过或反证过：

| 他们的坑 | 我们 | 我这轮的读数 |
| --- | --- | --- |
| `process.platform === "android"` 导致上游 `=== "linux"` 分支全落空（补丁 01/03/04/05/08 全是这一条的衍生） | **不存在** | chroot 里 node 报 `linux`/`aarch64`，所以 01/03/04/05/08 四条**整类作废** |
| `koffi` 的 `statx()` 在 Bionic 编译不过 | **不存在** | 我们直接 require 官方预编译件成功（RUNBOOK §0 那行"盘上 cmake/gcc 一个都没装"就是这条的证据） |
| `@vscode/ripgrep` 去找不存在的 `@vscode/ripgrep-android-arm64` | **不存在** | 我们装到的是 `@vscode/ripgrep-linux-arm64`，rg 15.0.0 跑得动 |
| sepolicy 禁 `link(2)` → 会话存不下、`write` 工具新建文件报 `EACCES` | **不存在** | 我在 `/phone` 里实测 `ln a b` → `LINK_EXIT=0`、`ls -l` 显示 nlink=2。**我们 root + chroot 的 SELinux 域和 Termux 那个 `untrusted_app` 域不是一回事**，所以他们最大的那个 `patch-dsh-android-link.js` 对我们是多余的 |
| 要现编 node-pty / 装 NDK 工具链 | **不存在** | 我们不需要 PTY 补丁，Web 终端那条路是另一回事 |
| `sharp` 原生件加载失败 → 装 `@img/sharp-wasm32` 兜 | **待验** | 我们没测过图像那条链。chroot 里 glibc 预编译件本该能用，但**这条我没读数，别当已通** |
| HMR 要 `--expose-internals`（Node 22+ 禁 `node:internal/modules`） | **待验** | 我们 `node_modules` 里 `dsh-hmr`/`dsh-client-hmr` 都在，`dsh.log` 里 `expose-internals` 与 `internal/modules` 命中数 **0** —— 要么我们的启动方式已经带上了，要么 HMR 是静默关着的。**没查清，记着** |

**还有一条更硬的**：FunnelCakes issue #6 说 **0.2.x 起多了个硬依赖 `node-addon-require-builtin`，官方只发了
darwin/linux/win 的平台包、没有 `android-arm64`**，Termux 路线上 `dsh web` 直接致命退出
（`No usable native binding found …`，栈在 `dsh-app-boot/lib/index.js:4105`）。
我在我们设备上读到的是 `node-addon-require-builtin` **和 `node-addon-require-builtin-linux-arm64-gnu` 两个目录都在**。
那个 `-gnu` 后缀就是 glibc 的标记 —— 也就是说 **dsh 到 0.2.x 之后，Termux 原生路线已经跑不起来了，chroot 是目前唯一还能跟上主干的版本**。
这两家都停在 8 月不是偶然。

---

## 三、我们没考虑到、而且能马上改变决定的三件事

### ① proot 可以做沙箱后端 —— 我们那个"要么裸奔要么没 Bash"的二选一，可能是假的

Vengisk 的 `patches/07-sandbox-local-proot-runner.patch`（5,318 B）往 `dsh-sandbox-local` 里塞了一个新 runner：

```js
const PLATFORM_CHAINS = {
	linux:   ["bwrap", "landlock"],
	android: ["proot", "bwrap", "landlock"],   // ← 他们加的
	...
};
STATIC_ENFORCEMENT = { …, proot: "partial", … }
```

理由写得很清楚：**proot 是 ptrace 用户态 bind，不需要 `CLONE_NEWUSER`、不需要 mount namespace**，
所以正好落在 bwrap 死掉的那台内核上。我们这台 `# CONFIG_USER_NS is not set` 杀的是 bwrap，**杀不到 proot**。

我核过我们这版的可移植性：`dsh-sandbox-local/lib/index.js` 里 `PLATFORM_CHAINS` 还在（173 行），
`runnerArgv` / `probeRunner` / `RUNNER_FAILURE_RULES` 这几个锚点全在，形状和他们打补丁之前一模一样；
`grep -rlo proot` 整个模块**零命中** ⇒ 上游到 0.2.1-rc.2 仍然不认 proot，得自己动源码（约 40 行 JS，不是重编）。

**但这条我要先把丑话说完**：他们自己的注释承认 proot 的 `-b /:/` 是**读写**的，"read-only is not enforced"，
所以 `enforcement: "partial"` 的实底是 —— **工作区外只读这一条，proot 根本没拦住**，它只是让 dsh 不再拒绝跑命令。
拿它当安全边界是自欺。另外 proot 是 ptrace 逐 syscall 拦，**性能会明显掉**。

### ② 更实在的一条：这台设备上 mount namespace 其实是通的，只是 chroot 里面不通

这是我这轮自己试出来的，两个项目都没有（他们无 root，压根没这个选项）：

```
chroot 内：  unshare -m /bin/true   →  unshare: cannot change root filesystem propagation: Invalid argument   exit=1
chroot 外：  unshare -m …true       →  exit=0
组合：       unshare -m sh -c 'chroot /data/local/dsh-rootfs /bin/echo INSIDE_NS_OK'  →  INSIDE_NS_OK，且 ns 内 mount --bind rc=0
```

也就是说 **`unshare -m` 在这台手机上能用，失败只是"从 chroot 里面调它"这一种姿势**。
理论上可以做一个 root 侧的 runner：`unshare -m` 包一层、在里面 bind 出真的只读，再 chroot 进去跑命令 ——
**那才是真围堵，不是 proot 那种名义围堵**。
没做完的部分要说清：我只验到"ns 建得出来 + ns 内 bind 成功"，**没验到 ns 内 `remount,bind,ro` 真能挡住写**
（我在 ns 外试全局 remount-ro 时读到 `Device or resource busy`，那次测试无效）。这条是"值得试"，不是"可行"。

### ③ 档位不该靠 UI 那个胶囊一次一点 —— `cordis.patch.yml` 能钉死，我们已经在用它了

FunnelCakes 的 `config/cordis.patch.yml` 注释写得很直白：Android 上 bwrap/landlock 都不可用，
所以**必须**用 `danger-full-access`，并安装到 `~/.dsh/profiles/web/cordis.patch.yml`：

```yaml
- id: sandbox-policy
  config:
    mode: danger-full-access
```

我打开我们设备上那份 `profiles/web/cordis.patch.yml`（508 B）—— **同一个机制在我们 0.2.1-rc.2 上是活的**，
里面已经躺着两条覆盖（`ui-settings-general.welcomeNoticeVersion` 和 `agent-default-model`，后者就是我们看到的默认模型档位）。
`start_dsh.sh` 里还有一行 `export DSH_PERMISSION_MODE=danger-full-access` 当第二条路。

**这条直接解决我们那个"新开会话又退回 workspace-write、又撞同一堵墙"的缺口**：
档位可以写进配置文件持久生效，而不是每个会话在客户端点一次胶囊。
所以 §14.5 那个悬着的问题，实际有三个选项而不是两个：
① 保持现状但**把档位写进 cordis.patch.yml**（至少行为可预期、可复盘）；
② 试 proot runner（名义围堵 + 变慢）；
③ 试 `unshare -m` 真围堵 runner（最干净，但要自己写，且只验到一半）。

---

## 四、他们做对了、我们该照抄的几件小事

1. **移动端 UI 有现成插件，不用自己注 index.html。**
   `mexiaosqwq/dsh-web-mobile` v3.2.0 自陈"**兼容 0.2.1 及以后**"，装法是官方的
   `dsh plugin --profile web add dsh-web-mobile` —— 走插件层就不怕升级冲掉。
   我们的 `tools/dsh-compat.js` 是打进 `dist/` 的，升级即失效（RUNBOOK 10.11 已经认了这个账）。
   它顺带还做了：弹窗变底部 sheet、刘海安全区、大 JSON 自动 gzip/brotli、768–1023px 平板档限宽居中。
2. **`manifest display: fullscreen` 是错的，`standalone` 才对。**
   FunnelCakes 实测：fullscreen 沉浸模式下软键盘弹出不收缩视口、没有几何信号，输入框直接被盖住；
   改 standalone 恢复系统栏与正常键盘行为。我们那份 manifest 现在正是 `fullscreen`（RUNBOOK §0 那行写着），
   而我"添加到主屏幕"那条待办**根本没考虑到这一层**。
3. **viewport meta 要加 `viewport-fit=cover, interactive-widget=resizes-content`。**
   我读了我们注入后的 `reference/dsh-web-frontend-index.html`，viewport 还是出厂那句
   `width=device-width, initial-scale=1` —— 键盘跟随这一条我们完全没做。
4. **`crypto.randomUUID` 在局域网 HTTP 下没有**（非安全上下文），他们为此专门发了 PR（closed #2/#3）。
   我们的 `tools/dsh-compat.js` 只补了 `AbortSignal.any` / `timeout` 等四个，**没补 randomUUID**。
   哪天他从 PC 用 adb forward 或局域网打开这个页面，第一个撞的就是它。
5. **重进/切回卡顿与 4.7 MB bundle 重下。** 他们的 `02-runtime-incremental-resync.patch`（7,791 B）
   做"保留窗口静默补齐"，`01-apiproxy-history-slim.patch`（6,952 B）做历史窗口瘦身 + 大结果截断，
   `04/05` 给静态资源和插件 bundle 加 immutable 缓存头。我们一次都没量过"手机上重进一个长会话要等多久"。
6. **`termux-open` 那类"打开文件"的出口。** 我们 chroot 里没有对应物，Agent 说"帮你打开这个文件"时无路可走 ——
   原生客户端那个「工作区 → 文件」页现在就是唯一的浏览出口。
7. **装依赖前先测速再选镜像**（他们 `setup.sh` 自动测 npm / nodejs.org，慢就切 npmmirror，且只对本次会话生效）。
   我们是把 npmmirror 钉死的 —— 对他们不在国内的人不适用，对我们正好，但"会话级、不改全局"这个做法值得学。

---

## 五、反面教训（这几条比经验更值钱）

1. **改源码这条路会被上游冲死，而且他们自己知道。**
   Vengisk issue #2 标题就是"贡献上游及后续计划？"，原话：上游每发新版会带来**破坏性改动**，
   每次都要**重写补丁**，"至少对我这样已经折腾不动的人来说不是好事"。两家都停在 8 月，
   FunnelCakes 停在 rc.7 —— 然后 0.2.x 那个 `node-addon-require-builtin` 一来，Termux 路线直接死。
   ⇒ **我们自己那 77 KB WebView 壳 + chroot 里零源码改动的做法，反而是这几条路里最抗升级的。**
2. **插件能把整站打挂，装之前先在空闲端口试。** 两份现成的事故：
   - Vengisk README 的 WARNING：装 `dsh-web-search-pro@0.1.2` + `@anweat/dsh-browser` 之后，
     插件在 profile 里装的**第二份 `@deepseek-ai/dsh-tools` 遮蔽了宿主注册表**（Symbol 键查调度器拿到 undefined），
     **所有**工具调用一起报 `Cannot read properties of undefined (reading 'prepare')`。
   - dsh-web-mobile 自己的 v3.0.6 修复项 #165：与 `dsh-pocket` 同装时**locale 命名空间重名把整站启动打挂**。
   ⇒ 我们要是照第四条去装 `dsh-web-mobile` 或哪天装 `dsh-relay`，**必须按 Vengisk 那句在 `--port 3191` 上先起一个实例验**，
   别拿他正在用的那个 3080 当试验田。
3. **"已修好"的判定要看全，别只看调用点。** FunnelCakes issue #7 报的是个很典型的 bug：
   `patch-dsh-android-link.js` 判断是否修好时**只看调用点是不是 `rename(`，没检查 import 里有没有 `rename`**，
   于是把"改了调用、漏了导入"的坏状态打成 `[OK]`，运行时才 `ReferenceError: rename is not defined`。
   ⇒ 我们那个 polyfill 注入的幂等判断同样只看了"标记在不在"。以后写这类校验，**导入和调用要一起点**。
4. **低版本 Android 装不上，很多时候不是"不支持"，是脚本少装了几样。** Vengisk issue #4 给了补齐清单：
   `ndk-multilib` + `libandroid-spawn` + `CFLAGS=-I$PREFIX/include/` + `LDFLAGS=-landroid-spawn` + `android_ndk_path`。
   ⇒ 对我们不直接适用，但"把'不支持'降级成'少装了东西'"这个态度值得记。
5. **真机启动慢这件事没人解释得了。** Vengisk issue #5：v1.5.x 起 node 加载 DSH 内核要 **50–60 秒**
   （v1.4.0 同内核同 node 只要 ~10 秒，模拟器 4 秒），逐字节比对过 payload，排除了网络与存储模式，作者来求经验。
   ⇒ 我们**从没量过自己 `dsh web` 从按下到能用的墙钟时间**。这条便宜又重要，下次服务自然重启时顺手掐个表。
6. **让 Agent 自己修自己的环境，会出事。** FunnelCakes issue #8 是一份很特别的记录：
   一个"完全不懂编程"的人用手机上的 DSH agent 自己折腾 0.2.x，**AI 把自己的安装搞崩过一次**，
   最后是另一个跑在沙盒里的 AI 实例救回来的。作者反复声明"这不是项目、不保证正确性、换设备请默认结论不适用"。
   ⇒ 这条正好给 §14.5 那个"要不要给它完全访问"添了个真实案例做参照。

---

## 六、我建议的下一步（按性价比排，都不动他正在用的东西）

1. **先做 ③**：把档位这件事从"UI 点一次"变成"配置文件里写死 + 可复盘"。
   选哪个值等他点头（现在悬着的就是这个），但**机制**该换成 `cordis.patch.yml`，别再靠胶囊。
2. **再验 ②**：花一次会话时间把 `unshare -m` 里的 `remount,bind,ro` 到底挡不挡写测穿。
   挡住 ⇒ 我们有**真围堵**，`workspace-write` 名副其实，Bash 也能用，§14.5 那个二选一直接消失。
   挡不住 ⇒ 明确写"此路不通"，省得下次再试。
3. **①（proot）留作备胎**，并且**在文档里写死它是名义围堵**，不能当安全边界卖。
4. **如果他哪天嫌原生客户端不够用**，再考虑 `dsh-web-mobile` 插件 —— 但按第五条第 2 点，
   先在 `--port 3191` 起一个副本实例验，验过才碰 3080。
5. 顺手能补的三个小读数（都便宜）：`dsh web` 冷启动墙钟时间 / 长会话重进等待时间 / `sharp` 在 chroot 里加载不加载得动。
