# 在手机里跑 DeepSeek Harness —— root + Ubuntu chroot 路线（v2，全部换成真机读数）

跑通日期：2026-10-19。这一版把 v1（我还没有你手机时写的猜测版）里被真机推翻的说法逐条改掉了，
改在哪、凭什么改，都在文中标了「实测」。v1 的说法没有留在正文里误导下一个人。

## 0. 先给结论：现在手机上是什么状态，还差什么

已经成的（每一项都是这轮在设备上取到的数，不是推断）：

| 事项 | 读数 |
| --- | --- |
| Agent 本体 | `@deepseek-ai/dsh` **0.2.1-rc.2** 装在 chroot 里，`node /usr/local/bin/dsh web` 是活进程 |
| 运行时 | Ubuntu 24.04.5 LTS / aarch64 / node **v22.20.0** / npm **10.9.3** |
| 服务 | `127.0.0.1:3080` **LISTEN**，页面实测 **HTTP=200 / 37,512 B** |
| 编译件 | koffi 直接 require 成功；ripgrep **15.0.0**（`@vscode/ripgrep-linux-arm64`）。盘上 cmake/gcc/g++/make/git/python3 **一个都没装** —— 整套装完不需要编译器 |
| SELinux | 全程 **Enforcing**，没关过 |
| 磁盘 | rootfs 合计 **1.7 G**（清掉装它用的中间包之后；装完当时读到 1.9 G）；chroot 内 `df -h /` 读到空闲 **339 G** |
| 开机自启 | **已关**：`/data/adb/service.d/50-dsh.sh` → 改名 `50-dsh.sh.off`（1,861 B 原样在位）。2026-10-19 深夜按他一句「难道它一直在我后面跑着，我连看都看不到」关的，开关做成控制台菜单第 8 项，一条命令可复原 |
| 网络出口 | `api.deepseek.com https=401`（通，只是没带 key）、`registry.npmmirror.com https=200` |
| 登录不了的根因 | 账号登录走 `platform.deepseek.com`（`dsh-deepseek-account-platform/lib/types/protocol.js:98` 拼 `${origin}/auth-api/v0/dsh/${method}`，`index.d.ts:6` 注明这个 origin 就是 "Platform origin serving auth-api"），而它**没被钉进 `/etc/hosts`** → chroot 里 `getent` 为空、`curl exit=6`，日志里那句 `sign-in failed errorCode:'no-response'` 就是它。补钉后同一发请求读到 `HTTP=429`（解析与 TLS 都通了，剩下的是它自己的限流/参数）。2026-10-20 再核：那三条报错的时间戳(23:31)早于补钉(23:41)，是旧账；node 亲测 `auth_init` 现在 405/422 正常应答，PC Chrome 上点登录能进到「等待登录」→ 服务端这步已过，剩的是手机浏览器那一跳（13.2） |
| 工作区 | **= 手机内部存储**。`/data/media/0` bind 进 chroot 的 `/phone`，服务从那里起步（`workspaceRoot` 就是 `process.cwd()`），登记表里那条显示名叫「手机存储」，实测顶层 116 个条目、`@` 联想能列出 DCIM/Download。细节与代价见 13.1 |
| 页面能跑起来的前提 | 手机预装的 HeyTap 浏览器内核低于 Chromium 116，没有 `AbortSignal.any`，页面会永远卡在"正在加载工作区…"。已给它补了 polyfill（`tools/dsh-compat.js` 注入 `dist/`），**升级 dsh 会冲掉**，见 10.11 与 13.4 → **2026-10-20 晚改口**：兼容层现在由常驻入口在**出口内联**，盘上 `dist/index.html` 一个字节没改 ⇒ "升级会冲掉"这条对 App 那条路已经不成立；机上 WebView 是 `130.0.6723.58`，**按 Chromium 版本它本来就不缺 `AbortSignal.any`，但"拆掉兼容层还能不能跑完一个真回合"没有实测**（curl 看不见 JS 异常），所以内联照旧挂着，判据写在 PROGRESS 下一步第 11 条。仍然要在意这一行的只有"用手机浏览器打开 `:3080` 看页面"那条备用路，见 14.14 → **同一晚再改口两次，都以盘上读数为准**：① 上面那句"盘上 `dist/index.html` 一个字节没改"当时**不成立**（那文件还带着更早一轮打进去的 51 B，825 → 876 B），14.15 这一轮才真还原成 825 B、md5 `5a1bf510…` 逐字节等于上游，`assets/dsh-compat.js` 一并删掉；② 内联那段里有个注释原样写着 `<script src=…>`，会把 HTML 解析器提前闭合、把 2.6 KB 源码漏成屏幕上一片代码（他 14.15 报的第一个症状就是这个），现在内联前过一次转义 |
| 看得见的那个「软件」 | Termux **0.118.3**（uid u0_a343）+ `/data/local/sh/dsh-console.sh` 菜单，开图标即进控制台；菜单第 1/5 项已在设备上跑通：状态打出 `:3080 LISTEN / pid / http=200 37,512 B`，第 5 项在 chroot 里读到 `aarch64 / v22.20.0 / 0.2.1-rc.2` |
| 桌面上那个「客户端」 | **`com.labteto.dshmobile` v0.16.0**（16,013,796 B APK，sha256 对上官方清单），本机模式直连 `127.0.0.1:3080`，token 粘一次。已登进去并**真跑过回合**：统计条 `2 回合 · 5 步 · 首字 844ms · 250 tok/s · 缓存 58%`，`工作区 /phone` 能翻他内部存储真实目录；`force-stop`→`am start` 复点验过不用重新粘 token。第 14 节 |
| key | **他自己填好了**（`/root/.dsh/.credentials.yaml` 478 B，0600 明文）。日志侧证：`model listing from https://api.deepseek.com/models loaded 2 model(s)`，且真回话了 |
| 沙箱 | 这台内核 `# CONFIG_USER_NS is not set` + `# CONFIG_SECURITY_LANDLOCK is not set` ⇒ **`workspace-write` 下 Bash 全灭**（原生 read/glob/edit 不受影响，实测 `glob` 返回 17,056 B）。bwrap 0.9.0 照装照验，装不上不怪它。第 14.4 节 |

还差的**只有一件**：~~把你自己的 `DEEPSEEK_API_KEY` 填进去~~ —— **他 2026-10-20 凌晨自己填完了**，
模型列表 2 条、真回合 250 tok/s，第 4 条验收（"key 对了能回话"）到此才算真过。
第 5 节那条 `/root/.dsh-env` 的路留着当兜底，想清掉用 `scripts/dsh-clear-key.sh`。

另一件我做不了也不该替你做的：**重启手机验证开机自启**。脚本在位但现在是关着的（上面那行），
「真重启一次服务自己起来」这条我没验（第 6 节）。

## 1. 为什么走 chroot 而不是 Termux 里直接装

v1 的判断依据（PC 侧扫 npm 元数据）留着，现在补上设备侧的实证：

| 组件 | 来自 | glibc/arm64 实测结果 |
| --- | --- | --- |
| `@vscode/ripgrep` | `dsh-tool-fs-search` | 走可选包 `@vscode/ripgrep-linux-arm64`，装完 `rg --version` = **ripgrep 15.0.0** |
| `koffi` | `dsh-fs-local` | install 脚本 `cnoke --prebuild` **拿到了预编译**，`node -e 'require(koffi)'` OK；因此不需要 cmake |

装完在设备上数：`/usr/local/lib/node_modules` **888 M**，其中 dsh 包 **868 M**，
`@deepseek-ai/*` 目录 **305 个**。（v1 里我写「78 个子包」，那是当时在 PC 上扫发布 packument 的口径，
只数了声明的直接依赖，跟装完的传递闭包不是一回事，两个数都留下，别混用。）

v1 顺带纠的那条仍然成立：Termux 讨论里出现的 `node-pty` / `sharp`，在 0.2.1-rc.2 的发布树里根本没出现。

## 2. 这轮实际用的机器与目录

```
一加 13（ro.product.model=PJZ110）/ Android 15 / KernelSU / 已 root
/system/bin/chroot -> toybox        # 系统自带，不需要 Termux 也不需要 busybox 退路
/system/bin/setsid ss curl tar      # 也都在
rootfs    /data/local/dsh-rootfs    # 1.9 G
脚本      /data/local/sh/
日志      /data/local/dsh.log（服务）/ /data/local/dsh-boot.log（开机自启）
pidfile   /data/local/dsh-rootfs/root/dsh.pid
```

**Termux 这轮完全没用上。** v1 第 1 步让你去 F-Droid 装 Termux + busybox，是给「机型可能不带 chroot」
留的退路；本机 `/system/bin/chroot` 就是 toybox 链的，`mount --rbind`、`chroot`、执行 `/data` 里的
node 全通，退路没启用过。换机型时再回来看这条退路。

rootfs 用的是 Canonical 官方 `ubuntu-base-24.04.5-base-arm64.tar.gz`，**29,936,675 B**，
sha256 `a91d5a93010193712d346d761372b7c9db6dfcf093893161c64ca107f05914f2`
—— 该值与同时抓下来的官方 `SHA256SUMS` 逐字符相同（`downloads/SHA256SUMS`）。

## 3. 装的过程（按真机实际顺序，四个坑都写死了）

脚本在 `scripts/`，命令都在 Android 的 root shell 里跑（`adb shell` 后 `su`，或手机上任何 root 终端）。

1. **建目录 + 解 rootfs**：`mkdir -p /data/local/sh /data/local/dsh-rootfs`，
   把 base 包推上去 `tar -xzf` 解开（Android 的 toybox tar 支持 `-z`，**不支持 `-J`**，见第 3 步）。
2. **钉 IP**：`python tools/pin-hosts.py`（第 8 节讲为什么必须钉）。
3. **进 chroot 装环境**：`sh /data/local/sh/dsh-chroot.sh --run 'bash /root/dsh-setup-in-chroot.sh'`。
   `dsh-setup-in-chroot.sh` 现在这版（v3）就是这轮真实过程的回写，里面有四条 v2 猜测被推翻的记录：
   deb822 的 `ubuntu.sources`（不是 `sources.list`）／ 无 CA 时 apt 必须先临时走 http 引导装
   `ca-certificates` 再切回 https ／ 解 Node 前先 `apt-get install xz-utils` ／ 工具链一律不装。
4. **Node 包**：`node-v22.20.0-linux-arm64.tar.xz` **29,921,788 B**，sha256
   `06907b9c088ce62305bc1530e5c1ae1510245114645768f7750c349c5b6fe667`，
   与镜像 `SHASUMS256.txt` 里那一行逐字符相同（本地 `certutil` 与镜像双向核过）。
   这轮我在 Windows 上手工重打过一份 `node-usr.tar` 想绕开 xz，结果 tar 丢了可执行位，
   chroot 里 `/usr/local/bin/node: Permission denied` —— 二进制包必须在目标机本机解。
5. **装 dsh**：`npm i -g --foreground-scripts @deepseek-ai/dsh@0.2.1-rc.2`（registry 指向 npmmirror）。

装完 apt 层只多了四个包（`dpkg-query` 逐个读到的版本）：

```
ca-certificates 20260601~24.04.1     curl      8.5.0-2ubuntu10.16
xz-utils        5.6.1+really5.4.5-1ubuntu0.3    iproute2 6.1.0-1ubuntu6.4
gnupg / build-essential / cmake / git = 未装
```

## 4. 日常怎么用（这一节才是你要的「像桌面应用一样」）

```sh
sh /data/local/sh/dsh-chroot.sh --web      # 起服务（已在听就 skip）
sh /data/local/sh/dsh-chroot.sh --status    # 挂载/SELinux/端口/pid/HTTP 五样读数
sh /data/local/sh/dsh-chroot.sh --url       # 打日志里那条带 token 的入场 URL
sh /data/local/sh/dsh-chroot.sh --run 'ls' # 在 chroot 里跑一条命令就出来
sh /data/local/sh/dsh-chroot.sh             # 交互式进 chroot
sh /data/local/sh/dsh-chroot.sh --stop      # 关掉省电
```

**打开页面必须用带 token 的 URL，这点和 v1 写的不一样。** 实测：

```
裸 http://127.0.0.1:3080/          → 401  body="dsh web authentication required; reopen the URL printed by dsh web."
http://127.0.0.1:3080/?token=…     → 303（Set-Cookie: dsh-auth-…）→ 跟随后 200，37,512 B 真页面
```

`--web` 起来时会把那条 URL 直接打在终端上（`--url` 随时可以再取一次）。

「点开就能用」到底成不成立，我按最严的口径测了两件事：

- **同一次运行内**，那条 token URL 可以反复用（连打两次都是 303）。
- **服务重启之后**：token **换新的**（旧 URL 立刻 401），但**上一次会话浏览器拿到的 cookie 仍然 200**。
  签名密钥在 `/root/.dsh/.credentials.yaml`（161 B，重启前后 mtime 不变），cookie 里的 `expiresAt`
  比 `issuedAt` 晚 **2,592,000 秒 = 30 天**。

所以正确的用法是：**用手机浏览器打开一次带 token 的 URL**（拿到 cookie），然后 **Chrome 菜单 → 添加到主屏幕**。
之后点图标就是裸地址 + cookie，能直接进；服务重启、手机重启都不影响，30 天内不用再管 token。

这条路线能做「真 App 感」也是实测的，v1 说「大概率没有 PWA 清单」是错的（我当时看的是 npm 发布包里
那个 30 KB 的加载器，静态资源不在那儿）：

```
GET /manifest.webmanifest → 200, 255 B
  name="DeepSeek Harness"  short_name="DSH"  display="fullscreen"  icons=[favicon.svg]
```

`display: fullscreen` 意味着加到主屏幕后是独立全屏窗口，不是带地址栏的书签页。
注意 manifest 的 `start_url` 是 `./`（裸地址），所以**必须先登录一次再加桌面图标**，顺序反了会一开就 401。

## 5. 填 key（唯一剩的一步，两条路）

机制不是我猜的，是包里的默认配置和 dsh 自己的报错原文：

```
dump-default-config 第 366-372 行：web-search-deepseek / web-deepseek-api → apiKeyEnv: DEEPSEEK_API_KEY
dsh-llm-deepseek-api-key/lib/index.js:9 → apiKeyEnv 默认 "DEEPSEEK_API_KEY"
默认模型（第 52-55 行）→ provider: deepseek-official, model: deepseek-flash
端点（从包内 *.js 扫出）→ https://api.deepseek.com
```

**路 A（最省事，推荐）：** 手机浏览器进 Web UI → Settings/Models 页里填 key。dsh 没 key 时打的话是：

```
MISSING_CREDENTIAL: llm-deepseek: no API key for provider route "deepseek-official";
store DEEPSEEK_API_KEY through the credentials service (the web Models page writes it),
or export DEEPSEEK_API_KEY in the launching environment
```

**路 B（文件）：** 在 root shell 里跑 `sh /data/local/sh/dsh-set-key.sh`，它提示你亲手粘贴、**屏幕不回显**、
只从 stdin 收（不进命令行参数、不进 history、不落日志），写完落 `/root/.dsh-env` 权限 `0600`，
然后 `--stop` 再 `--web` 让服务带上它。

链路我已经用哑 key 端到端验过了 —— 这一步不是为了"试 key"，是为了证明请求真的离开了手机：

```
DEEPSEEK_API_KEY=sk-dummy-invalid-do-not-use dsh --profile headless 'reply with exactly one word: pong'
→ dsh: AUTH: Authentication Fails, Your api key: ****-use is invalid (request_id: a1f55d64-7c5d-4bc4-a196-6ec863853323)
→ 本次移动网络 rx 增量 27,347 B
```

对面回的是 DeepSeek 网关的鉴权失败（还带 request_id），说明「env → dsh → TLS → api.deepseek.com → 应答被读回来」
整条都在走。同一句 prompt 在 key 缺失时是 `MISSING_CREDENTIAL`，**rx 增量 0**（它压根没出网）——
两种失败长得不一样，将来按这个就能一眼分清是网络问题还是 key 问题。

验完我把哑 key 那份 `/root/.dsh-env` 删了（现在文件不存在），所以你的真 key 落进的是一个干净位置。
填完之后跑 `sh /data/local/sh/dsh-smoke.sh`，它走的就是服务用的那条路
（source `/root/.dsh-env` → headless 打一句 pong），第 1 段还会从 `/proc/<pid>/environ` 里确认
服务进程确实拿到了 key（只报有无与长度，不打印值）。

## 6. 开机自启

已装：`/data/adb/service.d/50-dsh.sh`（**1,861 B / 0750 / root:root**，KernelSU 开机后期以 root 串行执行）。
这版是**薄壳**：等默认路由（最多 90 秒）→ 调 `dsh-chroot.sh --web` → 记日志，全部逻辑只有一份。
v1 那份自己抄了一遍 `setenforce 0` 和 `pgrep` 自查，两个都是错的，所以砍掉重写。

另外把执行整体丢进了 `{ … } &`：`service.d` 是串行的，这里睡 90 秒会把后面别的模块脚本堵住。

本轮验到哪：手动跑 `sh /data/adb/service.d/50-dsh.sh`，`/data/local/dsh-boot.log` 出
`===== Mon Oct 19 23:12:53 CST 2026 boot =====` + `[skip] :3080 已在听，pid=32127` + `退出码=0`，
**pid 没变、没重复拉**。
本轮**没验**的：真重启一次。不想自启了 `rm /data/adb/service.d/50-dsh.sh` 就完全撤销。

## 7. SELinux：不用关（v1 那一整段"要认的账"作废）

v1 写了三条路（先试 / 接受 Permissive / 写 sepolicy.rule），因为当时没数据。实测结论是一句话：

```
getenforce = Enforcing，全程没 setenforce 过
KernelSU 的 su 域 u:r:su:s0 下：mount --rbind 通、chroot 通、执行 /data 里的 node 通、服务正常出页面
```

`dsh-chroot.sh` 和 `dsh-boot.sh` 都不动 SELinux；真要 Permissive 只剩显式开关
`DSH_SETENFORCE0=1`（换机型撞 avc 时才用）。

## 8. 网络：53 端口被拦，靠 `/etc/hosts` 钉 IP 活着

这是整个方案里最容易坏的一环，必须知道底细：

```
本机实测：UDP/53 与 TCP/53 出站都被拦（root 也一样）→ /etc/resolv.conf 单独摆不平
443 通 → 所以在 PC 上用 DoH（https://dns.alidns.com/resolve，备用 dns.google）问答案，把 IP 写进 chroot 的 /etc/hosts
```

`tools/pin-hosts.py` 就是干这个的，一条命令刷新，只替换自己那段
`# >>> dsh-mobile pin-hosts >>>` 到 `# <<< … <<<` 之间的内容，段外一行不动，写完当场验
`getent hosts localhost` 与 `curl https://api.deepseek.com/`（期望 401）。
默认钉四个域名：`api.deepseek.com`、`registry.npmmirror.com`、`cdn.npmmirror.com`、
`mirrors.tuna.tsinghua.edu.cn`。

**为什么必须能重复跑**：这轮同一次会话里 `registry.npmmirror.com` 的答案在一分钟内从
`111.62.184.148` 变成 `120.220.81.136`，`cdn.npmmirror.com` 的 8 个 IP 整批换过。IP 会漂是常态，
漂了就是「apt/npm 突然连不上」，届时先跑 `python tools/pin-hosts.py` 再说。

现在盘上 `/etc/hosts`：**885 B**，非注释行 22。里面除钉的四个域名外还留着上一轮手工加的
`deb.debian.org` / `github.com` / `objects.githubusercontent.com` / `codeload.github.com`
（那是 dsh 装完不需要、但当初引导时用到的，段外原样保留）。

**故意没钉** `dsh-otel-collector.deepseeksvc.com`：解析不到就发不出去，遥测自然静默
（实测那一段 rx 增量为 0）。想留档的话，配置树里 `desktop-product-telemetry` 本身就带
`disabled: profile != desktop` 的条件，web profile 不走它。

流量口径记两笔，将来判断"是不是手机在偷跑"时可比：整轮装完 `rmnet_data4` 的 rx 从
`4,786,914,973` 涨到 `4,990,513,224`（约 **194 MB**，大头应是手机上那次 `npm i -g`，装完 888 M；
但我没做按进程/uid 的归属，手机里别的 App 也计在同一计数里）；而我单独夹出来的两次验证跑，
增量分别是 **27,347 B**（哑 key 打到对岸拿到 request_id）和 **0 B**（key 缺失，压根没出网）。

## 9. 验收清单（将来重装或换机型，照这九条读数走）

```sh
uname -m                                        # aarch64
getenforce                                      # Enforcing（不用关）
node -v; npm -v; dsh --version                   # v22.20.0 / 10.9.3 / 0.2.1-rc.2
sh dsh-chroot.sh --status                        # :3080 LISTEN + pid + 「带token走完: http=200」
curl 裸 /                                        # 401（这是对的，别当故障）
curl -L 带 token                                 # 200 且有 bytes（本轮 37,512）
curl /manifest.webmanifest                       # 200，display=fullscreen
dsh --profile headless 'reply …pong'             # pong（key 填对才算整条通）
/data/local/dsh-boot.log                         # 重启后要有新的 boot 段 + [ok]/[skip]
```

读数一台机器一份，别抄我这轮的数。判活口径记住两条：**端口在听 ≠ 页面能用**（要 200），
**pgrep 匹配 dsh 的 cmdline 永远假阳性**（包住它的那层 `bash -c` 自己就带着那个字符串）。

## 10. 这轮没做、以及没验到的

没做：没改动你电脑上任何配置（只在 `D:\mycode\dsh-mobile\` 里写文件）；没删你手机上任何不是我建的文件
（`/data/local/tmp` 里你原有的 `boot_b.img`、`init_boot_b.img`、`kpatch/`、`magiskboot`、`patch_boot*.sh`、
`brevent`/`brevent.sh`、`sukisu_v413_android15-6.6_kernelsu.ko`、`stock_boot.img`、`new-boot.img` 逐个 `-e` 抽查，
全部在位；清理后该目录条目数 64）。我删的只有我自己这轮推上去的五个临时件
（`ubuntu-base.tar.gz` 29,936,675 B、两份 node 包 29,921,788 B × 2、`node-usr.tar` 198,184,960 B、
`hosts.pinned` 412 B、`dsh_cj` 401 B）—— 原始包在 PC 的 `downloads/` 里都还留着，两个都还能对上官方 sha256。

没验 / 留口子的：

1. **真重启验证开机自启**——见第 6 节，这一步要你点头。
2. **`dsh-setup-in-chroot.sh` v3 没在干净 rootfs 上整跑一遍**。它是按这轮真实过程回写的，
   顺序和包名都对得上盘上读数，但"从空 chroot 一条命令装到底"这件事本身还没被证明过。
3. **Web UI 里那一轮真实对话还是没跑**：真 key 不在我手上。但入口这一侧已经验过了 ——
   「开始使用 → 添加 API Key」那个框能填能存（我用一条假 key 试过，存进去后模型选择器立刻出模型），
   详见 13.3。
4. **`/root/.dsh-env` 与 Web 内填 key 谁赢，没做过对撞实验**。盘上事实是：UI 存的是
   `/root/.dsh/.credentials.yaml` 里的 `refs.DEEPSEEK_API_KEY`，而 `/root/.dsh-env` 这个文件**至今不存在**；
   包的 README 说接了 credentials 服务时按它的优先级解析、只有没接时才直读启动环境 ——
   照这句话 UI 那份优先，但这是读文档读出来的，不是跑出来的。
5. **Wi-Fi 下和移动数据下的表现没分别测**：这轮手机是 USB 连着 PC、走移动数据出口（`rmnet_data4`），
   换 Wi-Fi 后 53 端口是不是同样被拦我没换过环境验证。
6. **CDN IP 漂移的实际影响面没量化**：钉完之后多久会坏、坏了先撞哪个域名，只有下一次才知道。
7. `0.2.1-rc.2` 是 rc 版，正式版号与配置键可能变；升级后 `/etc/hosts` 与 `--run` 那套不变，
   但 `apiKeyEnv` 这类默认值要重新 `--dump-default-config` 核一次（`scripts/dsh-dump-config.sh`）。
8. **Termux 拿 root 这件事已经验过了**（2026-10-20 00:11，全过程与两个坑见第 12.1 / 12.2 节）：
   第一版静默失效（app 读不到 `/data/local/sh`、susfs4ksu 对未授权应用藏 `su`），改完 + 他在
   SukiSU Ultra 里勾上 Terminal 之后，冷启图标 → 菜单自己出来 → 选 1 打出
   `:3080 LISTEN / 32127 活着 / http=200 bytes=37512`，选 5 在 chroot 里读出 `aarch64 / v22.20.0 / 0.2.1-rc.2`。
   这轮之前拍不到屏只是因为手机锁着（`screencap` 拉回的是「指纹解锁」那一屏），我没有密码也不去试。
9. **装的 Termux 是 GitHub 官方 release 的 `github-debug` 构建**（v0.118.3 arm64-v8a，
   35,106,607 B，sha256 `72fdb596045116bf5ba1b5bdf5b26fddb9acc0bd074ad9f2da9eb0ae85e83a4e`，
   与 release 自带的 `…_sha256sums` 逐字符对上）。选它是因为 f-droid.org 在这台 PC 上被 DNS 污染
   （alidns 给的是 157.240.17.14，Facebook 的段），dns.google 直连超时，只有 gh-proxy 这一路通。
   debug 签名意味着任何能连 adb 的人都能 `run-as` 它 —— key 不在 Termux 里（在 rootfs 的
   `/root/.dsh-env`，0600），但这条你应该知道。想换 F-Droid 签名版：卸载重装即可，脚本与菜单不用动。
10. **手机上「登录」的最后一公里我没替他点完**：服务端这步已经过了（`auth_init` 从"解析不到"变成正常应答，
    PC Chrome 上点登录能进到「等待登录」且日志零失败行，见 13.2），但 HeyTap 浏览器打开授权页、
    再回跳 `127.0.0.1:3080/oauth/callback` 这一段要他自己点一次才算数 —— 他那台机器上只有
    HeyTap 40.10.23.1 和 Quark 10.18.5.1160 两个浏览器，没有 Chrome，我在盲点菜单时误触过信息流广告。
    点不动就退到填 key 那条路（13.3），那条不依赖账号登录。
11. **`dsh-compat.js` 是打进 vendor 包里的补丁**（`dsh-web-frontend/dist/`），`npm i -g @deepseek-ai/dsh`
    升级会把它连同那行 `<script>` 一起冲掉，症状还是"工作区永远在加载"。
    要么升级后重跑一遍注入（`tools/dsh-compat.js` + `reference/dsh-web-frontend-index.html` 两份都在仓库里），
    要么给手机装个 Chrome/Edge 116+ 就彻底不需要它了。
    → **这一条从 2026-10-20 晚起只适用于"用手机浏览器看页面"那条备用路**：App 那条现在吃的是入口的
    **出口内联**（`scripts/dsh-entry.js`，盘上 `dist/index.html` 876 B 未被我们改过，`grep -c data-dsh-entry-compat` = 0 行），
    没有可被升级冲掉的落点；早轮真打进 `dist/assets/dsh-compat.js` 那份原地留着没删（与内联那份逐字节相同、幂等）。
    全部读数与三个坑见 **14.14**。
12. 上面第 3 条那句"真 key 不在我手上"**到 2026-10-20 凌晨作废**：他自己填了 key，
    真对话跑过了（原生客户端里 `2 回合 · 5 步 · 250 tok/s`，盘上 `loaded 2 model(s)`），
    第 4 条验收才算真过。当时的哑 key 对岸实验仍然是那条路的证据，两件事不冲突。
13. **服务死过一次，原因没查到**：本轮接手时 `:3080` 零监听、`/data/local/dsh-rootfs/root/dsh.pid` 不存在，
    而设备**没重启过**（`uptime` 289,844 s）、`MemAvailable` 还有 8 G 所以不是 OOM，
    `/data/local/dsh.log` 尾部也没有 panic/退出行 —— 就是进程没了，我拿不到它是谁杀的。
    用 `--web` 重起后 pid **10150**、`HTTP=200`。这条只能记成"下次再死之前先 `logcat -b crash` 与
    `dmesg` 抓一遍"，别当成已经稳定。
14. **token 每次重启服务都会换**（`dsh.log` 里能数出四条不同的 `?token=`），原生客户端只在**服务不重启**时免粘
    （14.3 那次冷启验的是 App 冷启，不是服务冷启）。服务重启之后要重新粘一次 —— 这是这套"点开就能用"
    目前唯一还需要人动手的地方。它文档里那个中继模式能绕开，但要在 web profile 里加 `dsh-relay` 插件，
    这轮没装、没验。

## 11. 目录里都有什么

```
RUNBOOK.md                        本文
scripts/dsh-chroot.sh             总控：挂载/起停/状态/--url/--run/--umount/--entry/--entry-stop（**没有 --entry-status**：入口自述走 --status；脚本里的 case 分支实测就八个 —— --web/--entry/--entry-stop/--stop/--status/--url/--run/--umount，我 14.15 之前记错过一次）
scripts/dsh-entry.js              **常驻入口（手机上现在这一层）**：起引擎 + 认那条一次性 token 的启动行 + 内存里换 30 天 cookie + 出口内联 polyfill（内联前过一次转义）+ **转发时把 Origin/Referer 一起换成上游 authority** + **upgrade 隧道只按握手计时** + 流水里把"总耗时/请求体收完"分成两列，只绑 127.0.0.1:3081；`--selftest` **合计 58 条：PASS 58 / FAIL 0**（Windows 与机上交付物各跑一遍，两边都是 58；这里只许抄脚本打的"合计"行，见 14.17 那条口径与改口）
scripts/dsh-entry-check.sh        机上只读体检：三种门禁探针 / **同源栅栏差分** / 真首页字节顺序与**内联元素关得对不对** / **静态资源耗时** / 入口自述 / 上游文件被动过没动过（5,742 → 13,579 B，见 14.15）
scripts/dsh-cdp.js                电脑侧驱动手机上那个 WebView 的只读探针（adb forward + DevTools）：--list/--eval/--watch/--click/--url，网络记录只留路径不留 query；**手机 Dozing 时拒绝跑**（实测那状态 attach 超时），见 14.15
scripts/dsh-slow-probe.sh         chroot 内跑的只读耗时探针（1,381 B）：curl 用 `-K -` 从 stdin 拿入口口令（**不进 argv、不打出来**），串行重打那几个页面加载时必发的引擎端点各三次，量"总/连上/首字节"——用来把"App 里很慢"和"引擎里很慢"分开，见 14.17。跑法是 `dsh-chroot.sh --run 'bash /root/dsh-slow-probe.sh'`，用完当场删机上副本
scripts/dsh-setup-in-chroot.sh    chroot 内一次性装环境（v3，含 v2 被推翻的四条）
scripts/dsh-boot.sh               开机自启薄壳 → 装到 /data/adb/service.d/50-dsh.sh（现在是 .off，见第 0 节；**2026-10-20 晚改成"入口在位就起 --entry"**，见 14.14 ④）
scripts/dsh-console.sh            手机控制台菜单：状态/启动/打开/日志/终端/停止/收尾/自启/跑一句
scripts/dsh-ask.sh                控制台第 9 项的壳，装到 rootfs 的 /root/，问题从 /tmp/dsh-task 读
scripts/get-termux.sh             在手机侧下 Termux APK 并核 sha256（PC 侧走 gh-proxy 只有 ~3.5 KB/s）
scripts/dsh-auth-host-probe.sh    只读：登录为什么不通的取证（hosts 名单 / getent / auth_init 实打一发）
scripts/dsh-terminal-probe.sh     只读：dsh 到底有没有终端形态（profile 名单 / xterm / headless 补丁原文）
scripts/dsh-set-key.sh            从 stdin 收 key，写 /root/.dsh-env(0600)，不回显
scripts/dsh-smoke.sh              一次性验收：服务 env + 真打一句给模型
scripts/dsh-restart-check.sh      重启服务，验旧 token/旧 cookie 谁能活下来（第 4 节那两条结论就出自它）
scripts/dsh-probe.sh              环境读数（版本/平台敏感件/apt 包/磁盘），只读
scripts/dsh-dump-config.sh        把 dsh 组合后的配置树打到 stdout，只读
scripts/dsh-model-probe.sh        只读：查 key 到底配在哪一层（这轮的取证脚本）
scripts/dsh-key-probe.sh          只读：包内 apiKeyEnv/端点/hosts 取证
scripts/dsh-token-probe.sh        只读：token 能否复用 + DSH_ 可调变量名单
scripts/dsh-keychain-test.sh      哑 key 端到端取证 + env 有无 + 流量增量
tools/pin-hosts.py                PC 侧 DoH 解析 → 刷 chroot 的 /etc/hosts 钉 IP 段
scripts/dsh-webconnect-probe.sh   只读：三件事一次取齐（服务 cwd / 手机存储进没进 chroot / 凭据库有没有 key 槽）
scripts/dsh-fetch-probe.js        只读：用 node 自己打 auth_init，把"网络不通"和"服务端报错"分开（13.2 的读数出自它）
scripts/dsh-add-workspace.js      往 dsh 的工作区登记表里直接加一条（绕开手机浏览器坏掉的选目录弹窗）
scripts/dsh-clear-key.sh          清掉凭据库里那条 API Key（UI 里清空保存是删不掉的，见 13.3）
tools/dsh-compat.js               给老内核浏览器补 AbortSignal.any 等四个 API。**注入方式 2026-10-20 晚换了**：由入口在出口按 mtime 热读内联（14.14），不再是打进 `dist/`（那条见 13.1，只剩历史遗留那份就地副本）
tools/deploy-entry.sh             一条命令管入口这一层：推五件 + 逐字节校 + 收日志权限 + 用真首页跑自测 + `--entry` / `--status` / `--check` / `--pull-key`
reference/dsh-web-frontend-index.orig.html  改之前的 dist/index.html 原样（md5 5a1bf510…）。**机上那份副本 `/data/local/sh/index.html.orig-dshmobile` 已经不在了**（2026-10-20 晚还原时按读数复点：`md5sum` 报 No such file），现在唯一的还原真源就是仓库这份
reference/dsh-web-frontend-index.html       打过 polyfill 那行的版本（md5 50c5ee3f…）。**它不再是"要打进上游的那一份"**：盘上首页已还原成原样，兼容层只在出口内联（14.15），这一份现在只当"打过补丁那版长什么样"的对照与推回去的退路
reference/                        dsh 的 README/package.json/默认配置树（从设备逐字节拉回）
reference/android-community-routes.md  社区两条 Termux 路线（Vengisk / FunnelCakes）精读 + 与我们这套的逐条对照，见 14.9
reference/android-three-community-apps.md  三家 APK 形态方案（DSHA / Soodok / woaiys3）精读对比报告，见 14.12。**纯静态阅读，一家都没跑**
reference/gh-3p/                    那三家的 main 解包件（DSHA 66 M / Soodok 14 M / woaiys3 20 M，只读参照，已 .gitignore）
                                    其中 DSHA-main 与 deepseek-harness-android-app-main 已是**真 git 仓库**（各自一条出处提交 a92928f / 72f553e，
                                    消息里记死上游 commit 与 tarball sha256；只有快照、没有上游历史），见 14.13
                                    DSHA-hist 与 dsh-android-app-hist 是**上游真历史**（blobless，只 commit+tree、不检出工作区，见 14.13）
downloads/gh3/                      三家的 tarball + GitHub API 原文 + sha256（约 52 M，.gitignore 掉）
tools/clone-upstream.sh             按深度切的历史抓取器（浅克隆→逐段 --deepen→--tags→--unshallow）；**在这条链路上已被实测否掉**，留作"连历史 blob 也要"的退路，见 14.13
tools/fetch-history.sh              按对象类型切的历史抓取器（--filter=blob:none --no-checkout）；实际用的就是这份，读数在 downloads/fetch-history.log
scripts/dsh-unshare-run.sh        改①：说 bwrap 方言的 unshare -m runner（装到 chroot:/usr/local/bin/dsh-unshare-run），见 14.11
scripts/verify-unshare-run.sh     改①的验收：34 条正反判据，含"没围住"和"围过头"两个方向（宿主侧跑）
scripts/dsh-sbx-probe.sh          上面那个验收的探针（被围之后跑，打 KEY=VALUE）
scripts/dsh-dev-node-probe.sh     勘察：ns 里能不能把 /dev 换成"只放 API 节点"的新 tmpfs（14.11 第四节未结的那条）
scripts/dsh-devnull-inner.sh      上一条的续集：null mknod 失败之后的退路（待验，被 ADB 断线打断）
downloads/verify-runner-3.txt     34 PASS / 0 FAIL 那一跑的原文
reference/gh-deepseek-harness-termux/  那两个仓库的 clone（各 ~270 KB 源码，只读参照，随时可删）
reference/gh-deepseek-harness-android/
downloads/                        rootfs 与 Node 原始包（.gitignore 掉，不入库）
tools/decomp-session.js           只读：把 session.v4.jsonl.zstd 逐帧解开、列出每条记录类型与里面的工具名（14.4/14.5 的读数出自它）
tools/dump-record.js              只读：按行号把某几条会话记录原样打出来（看 approval/decided 这种关键行）
app/                              我自己那个 77 KB WebView 壳：AndroidManifest + MainActivity + res + build.sh，见 14.6，**没装到手机上**
app/local/                        含活 token 的 url.txt 与自签 keystore —— 整目录不入库
downloads/dshm-*.png              原生客户端这一路的屏证（登录态、工作区目录页、权限片读数）
```

`scripts/dsh-model-probe.sh`、`dsh-key-probe.sh`、`dsh-token-probe.sh`、`dsh-keychain-test.sh`
是这轮的取证脚本，留着是因为将来升级版本或换机型时，那几个结论（key 配在哪、token 能不能复用）
要重新取一次数才能信。

## 12. 为什么最后长成「一个终端 App + 一个网页」这个样

他原话是要「桌面的应用，想开就开想关就关，我看得见进程、能关得掉，像一个真正的终端、真正的软件」。
先把话说死：**dsh 0.2.1-rc.2 没有终端界面**，这条是设备上取回来的，不是我印象：

```
$ dsh --profile tui --help
Error: dsh: profile "tui" does not exist; create it with 'dsh plugin --profile tui add <package>'
```

随包只有 base / web-app / headless / sdk-app / sdk-minimal / acp-app 这几套 bundle，
`desktop` 是留给 Electron 的。`headless` 也不是 REPL —— 它自己的 `cordis.patch.yml` 第一行写着
"one-shot task mode"，且 `credentials` 与 `authorization` 都 `disabled: true`，即一次性任务、
只认启动时的 env。所以「对话」这一面在 0.2.x 只有 Web 一个壳，绕不开。

那「看得见、能开关」这件事就落在壳外面，落成两层，各管一半：

| 你要的 | 落在哪 | 凭什么 |
| --- | --- | --- |
| 桌面上有个图标，点开是个真窗口 | Termux 0.118.3（`com.termux`，launcher 里就叫 Terminal） | 打开即被 `~/.bashrc` 那段拉进控制台菜单 |
| 起 / 停 / 看状态 / 杀进程 | 控制台菜单 1/2/6/7 项，全走已实测的 `dsh-chroot.sh` | 菜单第 1 项实测打出 `:3080 LISTEN`、`pid 32127 活着`、`http=200 bytes=37512` |
| 一个真终端 | 菜单第 5 项：`chroot` 进 Ubuntu 的 `bash -l` | 实测读到 `aarch64 / v22.20.0 / 0.2.1-rc.2` |
| 看它到底在干什么 | 菜单第 4 项 `tail -f /data/local/dsh.log`，Ctrl-C 回菜单 | 日志里那句 `sign-in failed` 就是这么读出来的 |
| 不想让它自己在后台活着 | 菜单第 8 项开关自启；这轮已把它拨到 **关** | `/data/adb/service.d/50-dsh.sh` → `50-dsh.sh.off` |
| 对话界面本身 | 菜单第 3 项用浏览器打开带 token 的 URL；要图标就在 Chrome 菜单点「添加到主屏幕」 | `/manifest.webmanifest` 实测 200 / 255 B，`display: fullscreen`、`short_name: DSH` |

顺带一条他大概没发现的：Web 那套包里带着 `dsh-client-ui-sidebar-terminal`、`dsh-terminal-bash`、
`@xterm/headless`、`@xterm/addon-serialize` —— **网页里本身有一块真终端面板**（侧边栏 Terminal），
不是只有聊天气泡。他说「不是一个真正的终端」时，可能没往侧边栏点。

### 12.1 装完第一版之后，真机上又撞了两堵墙（这节是踩坑记录，别省）

第一版把钩子写在 `~/.bashrc` 里、判断 `[ -f /data/local/sh/dsh-console.sh ]`。他解锁点开图标，
屏幕上只有 `~ $`，菜单根本没出来。两条都是实测出来的原因：

1. **app 读不到 `/data/local/sh`**。这条不是权限位问题，是 SELinux：
   `runcon u:r:untrusted_app:s0:c67,c257,c512,c768 ls /data/local/sh` → `Permission denied`
   （Termux 实际上下文是 `untrusted_app_27`，它 targetSdk 28）。所以那个 `[ -f ]` 永远是假，
   整个 if 静默跳过 —— 连报错都不给，这就是"菜单没出来"的全部原因。
   改法：脚本本体挪进 Termux 自己的 home（`~/dsh-console.sh` + `~/.dsh-hook.sh`），root 侧按绝对路径读它。
2. **`su` 对未授权的应用是藏起来的**。在 Termux 里敲 `su` 读到的是
   `No su program found on this device. Termux does not supply tools for rooting`，
   而 root 侧 `command -v su` 明明有 `/system/bin/su`。他这台挂了 `susfs4ksu`，
   `/data/adb/susfs4ksu/config.sh` 里 `sus_su_active=2` —— su 路径按白名单可见。
   解法只有一条正路：**他在 SukiSU Ultra(v3.1.7 / LKM) 里把 Terminal 加进超级用户**，
   我没去手改 `/data/adb/ksu/.allowlist`（那是个二进制序列化文件，不是行文本，手改容易把他的 root 配置搞坏）。
   他点完之后 `grep -ac com.termux /data/adb/ksu/.allowlist` 读到 **1**，`su` 立刻就有了。

补一句 bash 侧的坑：Termux 起的 shell 是 login shell，只写 `~/.bashrc` 不一定被读，
所以 `~/.bashrc` 与 `~/.bash_profile` 两边都放同一行 `. "$HOME/.dsh-hook.sh"`，
钩子里用 `DSH_CONSOLE_DONE` 兜住不跑第二遍。

### 12.2 这条链路的验收读数（截图拍下来的，不是推的）

冷启 Termux（`am force-stop` 后重开）→ 菜单**自己**出现在屏幕上，十项齐全 → 选 `1)` 打出：

```
--- SELinux --- Enforcing      --- 监听 --- :3080 LISTEN
--- pidfile --- 32127 活着
--- HTTP --- 裸 /(预期401)= 401   带token走完= http=200 bytes=37512
--- dsh --- /usr/local/bin/dsh 0.2.1-rc.2
```

选 `5)` 在那个终端里读到 `Linux ... aarch64` / `v22.20.0` / `0.2.1-rc.2`。
到这一步，「桌面上有个图标 → 点开看得见 → 起停杀得掉」这三件事是齐的。

要退掉这层也不难，逐条可撤：`pm uninstall com.termux` 卸终端 App；`~/.bashrc` 里 `# >>> dsh-console >>>`
到 `# <<< dsh-console <<<` 那一段删掉即恢复 Termux 默认（追加前 Termux 的 home 里除了 `.termux/` 什么都没有，
没有覆盖你任何文件）；`rm /data/local/sh/dsh-console.sh /data/local/sh/dsh-ask.sh` 删脚本；
`mv /data/adb/service.d/50-dsh.sh.off 50-dsh.sh` 把自启拨回开。

## 13. 「网页端读不到手机 / 登录不了 / 配不了 key」——三条各有各的真因（2026-10-20）

他这三句都不是错觉，但**三条的成因不是同一个**，而且其中两条根本不在 dsh 身上。逐条给读数。

### 13.1 工作区读不到手机：一半是 chroot 里根本没有手机存储，一半是他那个浏览器跑不动页面

**第一半（服务端）**：改之前 `grep dsh-rootfs /proc/mounts` 只有 proc / sys / dev / dev/shm / run 五类，
`/sdcard`、`/storage`、`/data/media` 在 chroot 里**一个都不存在** —— 工作区当然读不到手机。
而 dsh 的工作区取的是进程当前目录，配置里写死：

```
reference/dsh-web-default-config.txt:137    workspaceRoot: !!js process.cwd()
```

改法（`scripts/dsh-chroot.sh` 已改，实测读数在下面）：`mount_fs` 把 **`/data/media/0`** bind 到
`$ROOTFS/phone`，`--web` 拉起前先 `cd /phone`。用 `/data/media/0` 而不是 `/sdcard` 是因为后者是给 App 的
FUSE 视图，chroot 里拿不到；前者是裸路径，root 直接可读。落地后：

```
--- 工作区 ---
  chroot 内 /phone，顶层条目 116 个；服务实际 cwd=(宿主视角)/data/local/dsh-rootfs/phone -> (chroot 视角)/phone
```

写权限也验过：chroot 里 `touch /phone/.dsh-write-test` 成功，落盘 `root 1023` 带 ACL，
SELinux 域 `u:r:su:s0`，**Enforcing 全程没动**，测完那个文件已删。

**第二半（浏览器，这条才是他看到的现象）**：手机预装的 HeyTap 浏览器（`com.heytap.browser` 40.10.23.1）
内核低于 Chromium 116，没有 `AbortSignal.any`，而 dsh 的**浏览器侧**模块用了它
（`dsh-api-session-controller/lib/client.js` 等 79 个文件里出现这个 API；服务端 node v22.20 本身有，坏的是页面）。
后果是点「选择工作区」永远停在"正在加载工作区…"，点「添加工作区」弹窗里直接红字：

```
AbortSignal.any is not a function
```

修法是给页面补一个 polyfill：`tools/dsh-compat.js`（3,123 B）放进
`dsh-web-frontend/dist/assets/`，并在 `dist/index.html` 的 module script **之前**插一行
`<script src="./assets/dsh-compat.js"></script>`。能这么干是因为实测响应头里**没有 CSP**。
补完当场在他手机上重开页面：工作区那一格直接变成「**手机存储**」，输入框、`/` 指令菜单、
`@` 文件联想全部出来了，`@` 后面列的就是他存储里的真目录（APK安装工具 / Alarms / Android / DCIM /
Documents / Download / Movies …）。

还有一步绕不过去：登记表原本是空的（`storages/workspace.json` 里 `workspaceIds: []`），
而往表里加东西的正规入口就是那个坏掉的选目录弹窗。所以写了 `scripts/dsh-add-workspace.js`
直接按 `dsh-workspace/lib/types/spec.js:workspaceRecord` 的形状登记 `/phone`（改之前把原文件挪到
`/root/.dsh/workspace.json.bak`）。**换 Chrome/Edge 116+ 之后这个脚本和 polyfill 都不再需要。**

代价要说在前面：`/phone` 是**整个**内部存储，工作区权限现在是 `workspace-write`，
也就是 Agent 真能改他照片和下载目录。收窄只要一行：`DSH_WORKDIR=/phone/Download`（或 `DSH_NO_PHONE=1` 干脆不挂）。

### 13.2 登录：那三条报错是钉 IP 之前的旧账，现在服务端这步已经过了

日志里 `sign-in failed { errorCode: 'no-response' }` 最后一条写在 **23:31:23**，
而 `/etc/hosts` 里补上 `platform.deepseek.com` 是 **23:41:49** —— 时间顺序反的，那是旧账。
用 node 自己（跟 dsh 同一个运行时）从 chroot 里打登录接口：

```
dns.lookup platform.deepseek.com -> [{"address":"60.204.2.4"},{"address":"60.204.2.5"}]
OK   error/POST https://platform.deepseek.com/auth-api/v0/dsh/auth_init status=422 ... 55ms
OK   error/GET  https://platform.deepseek.com/auth-api/v0/users/current status=200 body="{\"code\":40002,\"msg\":\"Missing Token\"}"
```

`422`/`40002` 都是**服务端正常应答**（缺参数、缺 token），不是连不上。
再在 PC Chrome 上点一次「登录」：页面进到「**等待登录**」弹窗（"没有自动打开新页面？复制登录链接…"），
而 `/data/local/dsh.log` 零新增失败行 —— 这个包只在失败时打日志，所以这就是 auth_init 成功。

**没验到的一步**：他手机上 HeyTap 打开授权页、再回跳 `127.0.0.1:3080/oauth/callback` 这整段我没替他点完。
盲点菜单时误触了浏览器信息流里的广告，把京东 App 拉起来了（已 `am force-stop com.jingdong.app.mall` 关掉，
它之前不在运行）。所以登录这条只到"服务端已通、页面已能发起"，**授权页能不能在他手机浏览器里走完，要他自己点一次才算数**。

### 13.3 配 key：UI 里一直有这个框，是浏览器让它打不开；填法与删法都验过了

`开始使用 → 添加 API Key` 是一个真输入框（`设置 → 模型 → 编辑` 里也有同一个）。
我用一条格式合法的**假 key**（`sk-` + 32 个 0）实测：保存后弹窗消失、模型选择器立刻出现
`DeepSeek-V4.1-Flash / High`，盘上 `/root/.dsh/.credentials.yaml` 多出 `refs: DEEPSEEK_API_KEY:` 一条
（0600，**明文**）。也就是说他遇到的"配不了"跟 13.1 第二半是同一堵墙，不是没有入口。

两个坑记下来：

1. 想删掉已存的 key，**不能靠在那个框里清空再保存** —— 它的 placeholder 明写"留空使用已保存凭据"，
   清空保存等于不改。删只能走 `scripts/dsh-clear-key.sh`（先停服务，否则它退出时把内存里的旧凭据写回去）。
2. `/root/.dsh-env` 那个文件到现在也不存在，而且**不需要**：UI 走的是凭据库。
   env 那条路仍当兜底（`dsh-llm-deepseek-api-key` 的 `apiKeyEnv` 默认 `DEEPSEEK_API_KEY`，只在没接 credentials 服务时才直读环境）。

假 key 已清掉，备份留在 chroot 内 `/root/credentials.yaml.cleared-20261020-004131`。
服务重启后他手机上停在「开始使用」那一屏，等他填真 key。

### 13.4 这一节里所有改动的还原路径

| 改了什么 | 还原 |
| --- | --- |
| `dist/index.html` 插了一行 polyfill（825 → 876 B） | **这条已经做完了**（2026-10-20 晚，14.15）：机上 `dist/index.html` 现在逐字节等于上游原样，md5 读到 `5a1bf51057dbb270bcba7d997498db6e`，`dist/assets/dsh-compat.js` 也 `rm` 了。打过补丁那版留在机上 `/root/.dsh/index.html.patched-876.bak`（876 B，md5 `50c5ee3f6e147bf1535d328f7ad7e613`）与仓库 `reference/dsh-web-frontend-index.html`，两边都有，想推回去随时能推。原先那句"`cp /data/local/sh/index.html.orig-dshmobile`"这条还原路**现在指向一个不存在的文件**（`md5sum` 读到 No such file），别再照着跑 |
| 工作区登记表加了 `/phone` | 停服务 → `cp /root/.dsh/workspace.json.bak /root/.dsh/storages/workspace.json` → 起服务 |
| `/phone` 这块 bind 挂载 | `sh /data/local/sh/dsh-chroot.sh --umount`（已把 phone 加进卸载列表），或临时 `DSH_NO_PHONE=1` |
| 凭据库里那条假 key | 已删；那份备份在 chroot 内 `/root/credentials.yaml.cleared-20261020-004131` |
| PC↔手机的调试端口转发 | `adb forward --remove tcp:3080`，本轮结束前已撤（`adb forward --list` 读回空） |

---

## 14. 「桌面端」这一层：16 MB 原生客户端接本机 dsh（2026-10-20 凌晨）

起因是他一句「网页太麻烦了，想办法整个桌面端」。这一节记的是最后长成的样子、凭什么、以及怎么退回去。

### 14.1 先说清楚"桌面端"在这件事里指什么

指**手机桌面上一个能点开的 App**：有图标、有自己的窗口、能被最近任务划走、能被 `force-stop` 杀掉，
不用先开浏览器、不用先找到那串带 token 的网址。不是 PC 上的客户端 —— dsh 跑在他手机里，PC 端接过去就把"不依赖电脑"这条破了。

### 14.2 装的是哪一个（都是读数，不是猜的）

`sorsama/deepseek-harness-mobile`（项目自称 DSH Mobile），Kotlin/Compose，MIT，v0.16.0（2026-10-12 发布）。
包名 `com.labteto.dshmobile`，APK **16,013,796 B**，sha256 `8baa02db3197987420ccc0f1ea7a7be4a4e20982da05f8ace9aa7608b8df7584`
（下载后本地重算对上官方清单才装的）。要求 Android 8.0+，这台是 Android 15 / API 35。

它自带三种连接模式：**本机 / 局域网 / 中继**。本机模式自己探 `127.0.0.1:3080`，
token 要手粘一次（它文档明写「每次 harness 重启，它都会改变」）；中继模式才需要
`dsh plugin --profile web add dsh-relay`，本机模式不需要装任何插件。

**为什么不是别的三条**：① 它仓库里没有安卓端自己的推理/沙箱，只是个客户端，所以不冲突；
② 我本来准备自己写的 WebView 壳（14.6）已经做出来了但**没装**，留作退路；
③ 162–362 MB 那种自带 node 的整包路线会把 rootfs 那 1.7 G 再撑大一倍，且和 chroot 里这份 dsh 变成两份真相。

### 14.3 接上之后的真机读数

登录成功，界面直接列出了他手机上那个历史会话（标题「问候」），顶栏模型片 `Dee… / Low`，
统计条 `2 回合 · 5 步 · 首字 844ms · 250 tok/s · 缓存 58%` —— 这一行就是**推理真跑过**的证据，不是页面渲染出来了事。
盘上对应 `[llm-deepseek-account] model listing from https://api.deepseek.com/models loaded 2 model(s)`，
服务 pid **10150** 在听 `127.0.0.1:3080`，`netstat` 里一条 `ESTABLISHED` 就是这个 App 的长连接。

工作区页（`工作区 /phone`，三个页签 文件/预览/终端）能逐层翻他内部存储的真实目录：
`backups / baidu / BaiduNetdisk / Browser / ByteDownload / cache / ColorOS / DCIM / Documents …`
—— 这条同时补上了 13.1 那个"页面读不到手机"的验收：现在**原生客户端也读到了**。

冷启验了一次：`am force-stop com.labteto.dshmobile` → `am start -n com.labteto.dshmobile/.MainActivity`
→ 6 秒后 `mCurrentFocus` 回到 `com.labteto.dshmobile/…MainActivity`，落在已连上的界面上，
**没有再要 token**。也就是"点开就能用"这一条在**服务不重启**的前提下成立。

### 14.4 沙箱：这台内核上 `workspace-write` 跑不了 Bash，真因已取到

会话默认档位是 `workspace-write`（会话记录第 1、2 条：`permission/preset` 与 `sandbox/mode` 都是 `workspace-write`）。
在这个档位下发一句"列出工作区顶层 5 个文件夹"，Bash 那一发直接回（第 37 条，原文照抄）：

> `Error: sandbox mode "workspace-write" is requested but no sandbox backend is usable on this host; refusing to run the command unconfined. Install bubblewrap or run a Landlock-enforcing kernel (Linux), ensure sandbox-exec is usable (macOS), or ensure the ACL restricted-token runner can start (Windows) — otherwise switch the consumer to danger-full-access.`

它给的三条 Linux 出路，在这台内核上**两条半是死的**，读数：

```
zcat /proc/config.gz | grep -E 'CONFIG_USER_NS|CONFIG_SECURITY_LANDLOCK'
# CONFIG_USER_NS is not set
# CONFIG_SECURITY_LANDLOCK is not set
```

没有 user namespace ⇒ bwrap 建不出命名空间（实测报 `bwrap: Creating new namespace failed…` /
`Failed to make / slave: Invalid argument`）；没有 Landlock ⇒ 第二条也走不通。
我**照样 apt 装了 `bubblewrap 0.9.0-1ubuntu0.3`（Installed-Size 126 KB）验了一遍**，装不上不怪它，怪内核。
想撤：`chroot /data/local/dsh-rootfs apt -y remove bubblewrap`，留着也不影响任何行为。

**但同一档位下 dsh 自己的原生文件工具是好的** —— 同一次回合里第 42 条 `tool/call glob {"pattern":"*"}`
→ 第 43 条 `tool/result` **17,056 B** 正常返回。所以准确说法不是"这套跑不动"，是：
**`workspace-write` 下能用 read/glob/grep/edit/write 这些原生工具，唯独 Bash 这一类需要沙箱后端的工具全灭。**

**2026-10-20 追加：这台机器其实有第三条出路，而且已经验到可复现。** 上游只列了 bwrap 和 landlock，
但命名空间本身是开的（`CONFIG_NAMESPACES=y`），只有 `unshare -m` 的 mount namespace 这一条我们没试过。
实测结论（`scripts/probe-ns-sandbox.sh` 跑两遍读数一致）：

```
chroot 内 unshare -m 直接失败：cannot change root filesystem propagation: Invalid argument
        ↑ 这不是能力问题，是因为 $ROOTFS 自己不是一个挂载点；
          先 `mount --bind $ROOTFS $ROOTFS` 之后，同一句 unshare -m 返回 exit=0
ns 内 mount --bind / / + mount -o remount,bind,ro /   → 写入被挡（真只读，围住了）
ns 内直接 mount -o remount,ro /                       → mount: /: mount point is busy（没围住）
ns 内只把 /usr /etc 各自 bind 成只读 + 指定目录留可写  → 只读的写不进、可写的照样写得进
```

所以"这台内核跑不了 `workspace-write`"这句要收窄成：**跑不了的是上游那两条后端；
mount namespace 这条路能力在、只是上游 0.2.1-rc.2 没写 android 这一档。**
代价也量出来了：全盘 bind 只读会连 `/dev/null` 一起冻住（`cannot create /dev/null: Read-only file system`），
真做成 runner 必须把 `/dev` `/proc` `/tmp` `/run` `/phone` `/root/.dsh` 逐个再 bind 回可写。

### 14.5 权限档位这笔账：现在这台在 `danger-full-access`，而且我要写清我说不清是谁点的

那次 Bash 失败之后，模型自己发了一发带 `sandbox_permissions: "danger-full-access"` 的升级请求（第 48 条），
`justification` 就是把 14.4 那句错误复述了一遍。客户端弹出「授予完全访问权限？……我了解其中的风险」那个框。

**我的处置**：我先用 `keyevent 4`（返回）把它退掉了 —— 这种"我了解风险"的勾选不该由我替他认。
但 3 秒后（第 50 条 `approval/decided` `outcome: "allowed-once"`）它被批了，Bash 就跑起来了（第 53 条 `tool/result` 1,200 B）。
再往后（第 60–65 条）出现一条 **`command/run` `name: permission` `args: " danger-full-access"` `source.kind: user`**，
于是这个会话的档位被**整体**改成 `danger-full-access`，`approval/policy` 变成 **`never`**（=以后不再问）。
界面底栏那个盾牌片现在读作 `Full access`。

这条 user 命令**我不能确定是谁发的**：那 63 秒里我在用 `input tap/input text` 盲操作他的屏幕，
我的坐标完全可能正好落在那个框的确认键上。所以按"可能是我碰的"来记账，不要按"他自己点的"来记账。

**现在这台机器的实际暴露面**：`danger-full-access` + `approval/policy=never` + 工作区 = 整个内部存储（`/phone`），
意味着 Agent 发的任何 shell 命令都不再问一声就能动他的照片和下载目录。

要拨回去（**这个动作该他自己做，或者他一句话让我做**）：在客户端底栏点那个盾牌片 → 选回 `Workspace Write`，
会话里会留下对应的 `permission/preset` 记录。代价是 14.4 那条 Bash 又全灭。
想同时要 Bash 又要它每次问一声：把档位停在 `danger-full-access` 但别停在 `never` —— 这一档怎么单独调我这轮没验，
别照我这句话当准。

档位**只写在这个会话的 transcript 里**（`/root/.dsh/sessions/--phone--/session-f780cb74-…/session.v4.jsonl.zstd`），
`profiles/` 下 grep 不到 `sandbox`/`preset` ⇒ **新开会话会回到 `workspace-write` 默认**，又撞同一堵墙。

> ↑ 这段里"新会话回到 workspace-write"的**结论对，成因写错了**（2026-10-20 验穿，见 14.10）：
> 不是"没地方钉所以只能默认"，是上游本来就把部署默认钉在 `dsh-base/cordis.patch.yml:246` 的一句
> `process.env.DSH_PERMISSION_MODE ?? 'workspace-write'` 上，而 `profiles/` 下 grep 不到是因为
> 我 grep 的是 profile 目录、那句话在 `node_modules` 里的上游包内。同一个变量还顺带决定审批策略（:262）。

### 14.6 备选那条我也做完了：不装 Android Studio 的 APK 工具链 + 77 KB WebView 壳

这条路是他改主意之前的产物，**做完了但没安装**，留着当退路（原生客户端哪天不维护了、或者他嫌它 16 MB 里有什么不想要的东西）。

工具链全在 `D:\tools\android-build\`（整目录可删）：`aapt2.exe`（Google Maven 的 `-windows.jar` 里解出来，sha1 对过）、
`dl/r8-9.4.15.jar`、`dl/apksig-9.4.1.jar`、`platforms/android-35/android.jar`（`platform-35_r02.zip`，sha256 记在同目录 `.sha256.txt`），
JDK 用 `D:\tools\jdk-21`。链路是 `javac -source/-target 8 -bootclasspath android.jar` → D8（`--release --min-api 26 --lib android.jar`）
→ `aapt2 compile --dir res` + `aapt2 link -I android.jar --min-sdk-version 26 --target-sdk-version 35` → `jar uf base.apk -C dex classes.dex`
→ apksig v2+v3。两个坑：`apksig-9.4.1.jar` 里**没有 Main**，要自己写一个 20 行的 `SignApk.java` 驱动，
且 `SignerConfig` 只能用 `new ApkSigner.SignerConfig.Builder(name,key,certList).build()`；
`javac` 那行 bootstrap class path 警告是二进制噪声，`grep` 要带 `-a`。

壳在 `app/`（`AndroidManifest.xml` + `MainActivity.java` + `res/` + `build.sh`），一个全屏 WebView 指 `127.0.0.1:3080`，
带 `dsh-app://retry` / `set` / `clear` 三个错误页出口，token URL 在打包时从 `app/local/url.txt` 模板展开（**这个文件含活 token，别入库**）。
产物 `app/out/dsh-app.apk` **78,441 B**，sha256 `b1c7e6025013132246d0dcdf5e4c21e76795c676ed41221f38ef1f95b2435c96`，
`aapt2 dump badging` 认得出包名 `com.zhl.dsh` / label「DSH 工作台」/ launcher 图标。一条命令重打并装机：`sh app/build.sh --install`。

### 14.7 这一节的还原路径

| 改了什么 | 还原 |
| --- | --- |
| 装了 `com.labteto.dshmobile`（16 MB 原生客户端） | 手机上卸，或 `adb shell pm uninstall com.labteto.dshmobile`；它不在 `/data/local/tmp` 留东西，会话数据在 App 私有目录，卸了就没了 |
| 会话档位改成 `danger-full-access` + `approval/policy=never` | 客户端底栏盾牌片改回 `Workspace Write`（见 14.5，**要他点头**）；这只影响那一个会话 |
| chroot 里 `apt install bubblewrap`（0.9.0，126 KB） | `chroot /data/local/dsh-rootfs apt -y remove bubblewrap`；留着也不生效，这台内核建不出命名空间 |
| PC 侧新增 `D:\tools\android-build\`（约 90 MB）与 `dsh-mobile/app/` | 整目录删即可，设备上没装过我的 APK，**盘上零痕迹** |
| 取证用的临时件（`decomp.js`/`dump.js`/会话快照 `.zst`） | 已删；`/data/local/tmp` 与 rootfs `/tmp` 复点过，他原有的 `boot_b.img`、`kpatch/`、`magiskboot`、`patch_boot*.sh`、`brevent*`、`sukisu_*.ko`、`app-debug.apk` 全部在位未碰 |

### 14.8 我在这一步又碰过的一次误触

盲点坐标那次（`input tap 720 2615` 后面接 `input text`）本意是把提示词打进输入框，
结果截图读回来是**桌面搜索页**（`com.heytap.quicksearchbox`），那句话根本没进 App。
顺带把这台机器 `input text` 的转义规矩钉死：**空格是 `%s`，`%20` 会被当字面量打进去**；
清空一个框用 `keyevent 123`（移到最后）+ 连发 `keyevent 67`（退格）。
这个 App 的 `uiautomator dump` 是**好用的**（不像 HeyTap 那边给空树），坐标该从 dump 里读 `bounds=` 拿，别盲打。

### 14.9 社区还有两条 Termux 路线，读完之后我们多了第三个选项

2026-10-20 他让我去精读 `Vengisk/deepseek-harness-termux` 与 `FunnelCakes/deepseek-harness-android`。
逐文件读过（两份 clone 在 `reference/gh-*`），完整对照表与反面教训写在
**[`reference/android-community-routes.md`](android-community-routes.md)**，这里只留改变决定的三条：

1. **他们 8 成的补丁是在还 Bionic 的债，我们花 1.7 G rootfs 买断了**：`process.platform==="android"` 引发的
   五处分支失效、koffi 的 `statx`、`@vscode/ripgrep-android-arm64` 不存在、sepolicy 禁 `link(2)` ——
   最后一条我特意在 `/phone` 里实测 `ln a b` 得到 `LINK_EXIT=0` / nlink=2，**他们最大的那个补丁对我们是多余的**。
   更硬的一条：FunnelCakes issue #6 说 **0.2.x 起多了硬依赖 `node-addon-require-builtin`，官方没有 android 平台包，
   Termux 路线 `dsh web` 直接致命退出**；我们设备上 `node-addon-require-builtin-linux-arm64-gnu` 在位。
   ⇒ **dsh 到 0.2.x 之后 chroot 是唯一还跟得上主干的路**，这两家停在 8 月不是偶然。
2. **`proot` 能做沙箱后端**（Vengisk 补丁 07 往 `PLATFORM_CHAINS` 里加了 `android: ["proot", …]`，
   理由是 proot 走 ptrace 用户态 bind、**不需要 user namespace**）。我核过我们这版 `dsh-sandbox-local`
   的 `PLATFORM_CHAINS`/`runnerArgv`/`probeRunner` 锚点全在、`proot` 零命中 ⇒ 补丁结构上可移植，但**要改源码**，
   而且它自己注释承认 proot 的 bind 是读写的、"read-only is not enforced" ⇒ **那是名义围堵，不能当安全边界卖**。
3. **这台设备上 mount namespace 其实是通的，只是"从 chroot 里面"调不通**（两个项目都没有这个选项，他们无 root）：

   ```
   chroot 内  unshare -m /bin/true                      → cannot change root filesystem propagation  exit=1
   chroot 外  unshare -m …                             → exit=0
   组合       unshare -m sh -c 'chroot … /bin/echo ok'  → ok，且 ns 内 mount --bind rc=0
   ```

   ⇒ 理论上能做一个 root 侧 `unshare -m` + 真只读 bind 的 runner，**那才是真围堵**。
   **我没验完**：只验到"ns 建得出来 + ns 内 bind 成功"，没验到 ns 内 `remount,bind,ro` 真挡得住写
   （ns 外那次全局 remount 读到 `Device or resource busy`，测试无效）。是"值得试"，不是"可行"。

   > ↑ 这句"没验完"已经被验完了（2026-10-20 同日下一轮，读数在 14.4 的追加段）。
   > 卡住的那两次都不是能力问题，是我自己的测试写错了：全局 remount 那句 `busy` 属于形状 B（不该拿来判生死），
   > 而 chroot 内 `unshare -m` 失败的真因是 `$ROOTFS` 不是挂载点 —— bind 自己一次就 exit=0。

另外两条纯赚的：档位可以写进 `profiles/web/cordis.patch.yml`（`- id: sandbox-policy / config: mode: …`）持久生效，
**不必每个会话在客户端点胶囊** —— 这解决 14.5 末尾"新开会话回默认又撞墙"那个缺口，而且我们那份文件已经在用这个机制了；
`manifest display` 应该是 `standalone` 而不是我们现在的 `fullscreen`（FunnelCakes 实测 fullscreen 沉浸模式下软键盘不收缩视口、输入框被盖住）。

> ↑ 第一条"纯赚"其实**半个缺口都不存在**，而且钉的位置我换了：上游部署层本来就在钉，
> 而且用的是一个环境变量同时管住沙箱档位和审批策略。细节与读数见 14.10，别照这句动手。

### 14.10 档位到底钉在哪：一句话——钉在 `/root/.dsh-env` 的一个环境变量上（2026-10-20）

**上游真源（在本机 `node_modules` 里读到，不是我推的）**：

```
@deepseek-ai/dsh-base/cordis.patch.yml:246
    mode: !!js process.env.DSH_PERMISSION_MODE ?? 'workspace-write'
@deepseek-ai/dsh-base/cordis.patch.yml:262
    policy: !!js "(process.env.DSH_PERMISSION_MODE ?? 'workspace-write') === 'danger-full-access' ? 'never' : 'ask'"
```

三件事一次说清：

1. **"新会话回到 workspace-write"不是缺陷，是上游设计**（那行上面的英文注释原话就是 `fresh sessions pin workspace-write + ask`）。
   我 14.5 里把它记成"没法持久"是记错了。会话内切档会写进 transcript 的 `sandbox/mode` 事件、
   靠重放活过重启，所以**旧会话记住自己的档、新会话从部署默认起**，两套并存，优先级是
   `显式批准 > 会话事件 fold > 部署默认`。
2. **`DSH_PERMISSION_MODE` 是官方留的部署级开关，而且它同时决定审批策略**：设成 `danger-full-access`
   就顺手把 `approval/policy` 变成 `never`（以后不问）。**所以我原来打算往 `cordis.patch.yml` 里钉
   `sandbox-policy.mode` 那一版是错的**——只钉 mode 不管 policy，两处会漂移；而且
   `id: sandbox-policy` 虽然确实是有效短名（`--dump-config` 里读到了），但它上游已经被上面那两行占位，
   再叠一层只是多一个互相遮蔽的地方。机制本身（`cordis.patch.yml` 用户层）照样留着，只是这件事不该用它。
3. **`!!js` 表达式在 `--dump-config` 里是不求值的**：dump 出来就是那行字面表达式文本。
   想验"算出来是什么"必须另走一条路（见下面 T5）。

**落地的改动（就一个文件）**：新建 `chroot:/root/.dsh-env`（宿主路径 `/data/local/dsh-rootfs/root/.dsh-env`），
0600、root:root、1,687 B、md5 `82bdb1f3af4fcdda531a3d998d037c23`，内容见
[`config/dsh-env`](config/dsh-env)（在项目里入版）。生效行只有一条：

```sh
export DSH_PERMISSION_MODE=workspace-write
```

**钉的是 `workspace-write`，不是 `danger-full-access`** —— 后者是扩大暴露面，那一改等他点头（14.5 那笔账还挂着）。
这一版**不改变今天任何行为**（它和上游默认算出来是同一个值），它换来两样：
以后要翻档位只改这一行、不用碰客户端胶囊；上游哪天动默认值也带不跑我们这台。

**顺手抓到的一条自家隐患**：`dsh-chroot.sh:164` 早就写着 `. /root/.dsh-env >/dev/null 2>&1`，
而这个文件**从来没存在过**（实测 `ls` 直接 `No such file or directory`）——`2>/dev/null` 把它吞成静默 no-op。
也就是说"密钥/环境有地方钉"这件事一直是纸面上的。现在文件在位了，这条 source 才第一次真起作用。

**验收怎么做的**（`scripts/dsh-verify-perm-mode.sh`，全程只读、不重启服务；T1–T7 全绿，读数是）：

```
文件 0600 root:root 1687 B；CR 检查 0（且检测器本身过了正负对照：造一份 CRLF 副本能判出"有 CR"）
T1 对照（不 source）  env 里命中条数 = 0
T3 判别位            source 前=0 source 后=1
T4 子进程继承        exec env 里读到 DSH_PERMISSION_MODE=workspace-write   ← dsh 吃的就是这层
T5 表达式求解        不 source → undefined ；source 后 → workspace-write
T7 活服务未受影响    pid=10150 仍活着、exec 时 env 命中 0（预期：它在本文件创建前就 exec 了）、:3080 仍在听
```

**四条本轮踩出来的假通过，都写进脚本注释了**：

- `??` 兜底的歧义：env 没设和 env 设成 `workspace-write`，**最终值一模一样**，只比最终值必然假通过 ⇒
  必须单列一个"env 到没到手"的判别位（T3/T5）。
- **`/proc/<pid>/environ` 是 exec 时刻的快照**，之后再 `export` 看不见。我第一版探针拿
  `tr '\0' '\n' < /proc/self/environ | grep` 验 source 后的结果，读到 0 条，差点报"改动没生效"。
  正确探针是 `env | grep`（看当前进程）和 `exec env | grep`（看传给子进程的那份）。
- 三层引号（本地 bash → adb shell → su -c → chroot bash -lc）会把命令啃变形：同一轮里 `$P` 展开成空、
  `cd` 静默失败退回 `/` 根目录、`printf %%s` 打成字面 `%s`、`node -e` 的双引号套嵌打出一句 `NaN`。
  ⇒ **凡是要往 chroot 里塞带引号的判断，一律写成脚本推上去跑**，别再在命令行上套。
- **不要并行发两条 `adb shell su -c`**：本轮两条并行 su 里的那条 `cat` 报了 `Permission denied`，
  同一条命令单独重发立刻成功（uid 一直是 0）。这是并发 su 的假失败，不是文件权限问题，
  别拿它当"读不到他的配置"下结论。

### 14.11 把 `workspace-write` 做成真围堵：一个说 bwrap 方言的 unshare runner（2026-10-20）

他上一句是「先改两个最重要的，每做完一个都要检测一遍，有没有隐藏 bug」，并追加一句
**「完全访问的档位肯定是要留的」**。②（档位钉住）见 14.10，已收工。这一节是①：给 `workspace-write`
做一个**真的**围堵后端。因为 14.4 那条判据只判到"上游那两条后端在这台内核上都没有"，
不代表"这台内核围不住" —— mount namespace 是 `=y`，root 直接 `unshare -m` 实测 exit=0。

**接线位是官方留的，一行源码都不用改**（`reference/dsh-sandbox-local-index.js`，逐字对过）：

- `:254` `Config = { runnerCommand: string[], runnerFailureSignatures: string[], probeTimeoutMs }`
- `:311-321` 只要 `runnerCommand` 非空，`confine()` 直接返回
  `[...runnerCommand, ...bwrapProfileArgs(policy), "--", ...argv]`，`enforcement: "full"`，**不探测、不验证**
- ⇒ **这句是整件事的风险核心**：runner 偷偷没围住，dsh 那边看不出来，日志照样写"已围堵"。
  所以围没围只能自己对天验，不能拿 dsh 的读数当证据。
- `:216` `DENIAL_SIGNATURES.runnerCommand = ["read-only file system", "permission denied"]`
  —— 挡下来时**报错文案必须落在这两条里**，否则 dsh 把"权限拒绝"当成"命令失败"，模型会去改命令而不是改路径。

#### 一、runner 是什么

`scripts/dsh-unshare-run.sh`（142 行 bash，部署在 `chroot:/usr/local/bin/dsh-unshare-run`，0755，9,530 B）。
吃 bwrap 的那套参数（`--ro-bind/--bind/--tmpfs/--dev/--proc/--unshare-pid/--die-with-parent/--`），
不认识的参数 **127 拒绝**（宁可报错也不静默少围一层）。ns 里三步，顺序是硬的：

1. `/` 下顶层目录**逐个**冻只读（跳过 `dev|proc|sys|run|tmp` 这五个名字；`/phone` 这种"也是挂载点"的照冻）
2. 把调用方点名要可写的叠在只读层**之上**（`--bind` → rw bind、`--tmpfs` → 新 tmpfs）
3. 最后 `mount -o remount,bind,ro /` 把 / 根自己冻住（只能试不改视图的 remount：`remount,ro /` 实测报 busy）

第二步必须在第三步之前 —— 反面实测过：先叠工作区、最后 `mount --bind / /` 影子一遍，先前叠的挂载全被盖掉，
`/phone` 变成"只读的空目录"，档位直接废。第一版还有个 `grep mountinfo && continue`（"是挂载点就跳过"），
实测后果是 read-only 档下 /phone 漏出去，所以改成"先全冻、后点名"。

#### 二、验收：34 PASS / 0 FAIL

`scripts/verify-unshare-run.sh`（151 行 POSIX，宿主侧跑 `sh /data/local/tmp/verify-unshare-run.sh`）
+ 探针 `scripts/dsh-sbx-probe.sh`。读数原文留在 `downloads/verify-runner-3.txt`（含这一跑之后仍开着的口子）。八节，关键是这几条都拿到了：

```
对照组（不围）    /etc /usr /root //根 四发全 OPEN，/phone 也能写   ← 靶有效，否则下面"挡住"不作数
围住之后          ETC/USR/ROOT/ROOTDIR = BLOCK:…Read-only file system   ← 逐条命中 dialect，不是整发 grep
工作区            WS=hi（可写可读）
/dev /proc /tmp   DEVNULL=OPEN  PROC=OPEN  TMP=OPEN  TMPFS=tmpfs  ns 内的 /tmp 写没漏到外面
只读≠读不到       /usr/bin 还能列 336 项
pid namespace     没授权降级 → unshare: Invalid argument, RC=1（响亮拒绝，不静默少围）
退出码/stdout     rc=42 原样传回；runner 自己一个字都不往 stdout 吐
参数表            --frobnicate → 127；--ro-bind 缺参 → 127；-- 后空命令 → 127
没把外面带崩      宿主 mountinfo 473 → 473；ns 外 /etc 照样可写；/dev/null 设备节点还在
```

#### 三、这一轮抓到的四个隐藏 bug（都已改掉，都在脚本注释里）

1. **报错词表自己咬自己**（不改就全盘皆废的那条）：dsh 给自定义 runner 装的是
   `{ fatalSignatures: [...] }`（`:320`），**没有 `allowedExitCodes` 闸门** —— 而内置 windows-acl 是
   `{ allowedExitCodes:[127], fatalSignatures:["windows-acl-run: "] }`（`:239-242`），上游注释明说退出码
   闸门就是为了"别把只是**打印**了这句话的命令判成 runner 挂了"。我们第一版的降级提示用的是
   `dsh-unshare-run: 注意 …`，和致命错误同一个前缀 ⇒ 一旦按常规把签名配成 `"dsh-unshare-run: "`，
   **每一次围堵都会被判成沙盒启动失败**（这条提示每发都打）。现在词表分两家：
   `dsh-unshare-run:` 只给致命（同时 exit 127），`dsh-unshare-run-notice:` 只给降级提示。
   验收第 6 节专门有正反两条：成功围堵的输出里**不含**签名、真出错时**必带**签名。
   接线时 `runnerFailureSignatures` 就填 `["dsh-unshare-run: "]`（`:279` 还硬要求：给了 runnerCommand
   就必须至少给一条签名，否则构造期直接 throw）。
2. **探针的假通过**：`err=$(echo x > /path 2>&1)` 在 dash 里取不到东西 —— 重定向失败那句话是打在
   **shell 自己的 stderr** 上的。第一版读数因此是 `ETC=BLOCK:`（原因为空），逐条 dialect 判据退化成
   "整发输出里 grep 得到 read-only"。包成 `err=$( { echo x > "$1"; } 2>&1 )` 才把原文取回来。
3. **`--ro-bind` 收下来但不重放 = 死代码**：改成自检 —— 上游现在只发一条 `--ro-bind / /`，
   逐目录冻是照这个形状写的；哪天方言变了（多条、或 `--ro-bind /usr /新路径`），本实现不再等价，
   就 127 拒绝，不静默按对不上号的形状去"围"。
4. **`for d in //*/` 写成双斜杠**（我上一轮为了绕一个自己没查清的东西加的），改成 `/*/` 后整组重跑，
   八节读数一模一样 —— 那条不是前提，是噪声，留着只会让下一个人当"有讲究"不敢动。

另外记一条环境事实（不是 runner 的问题，但会影响下次验收）：**这台机的 su 域往某些目录写是
间歇性 `Permission denied`** —— 同一条 `cp` 成功、紧跟的 `chmod` 就失败，下一条 su 会话连 create 都不行
（`/data/local/sh` 中招；`/data/local/tmp` 和 chroot 里 chmod 全 rc=0）。没追那条 sepolicy 的来源，
只把测试件挪到读数稳定的一侧（`/data/local/tmp`），免得把自己的验收做成随机 FAIL。

#### 四、还没做、也不能说成做了的三件事

1. **`/dev` 这条窟窿比 pid namespace 大**（这是本轮最后正在查的，被拔线打断）：runner 对 /dev 是
   "原样不动"，而 `ls /dev` 348 个条目、`/dev/block` 下 **253 个裸分区节点**，被围命令和 dsh 同为 uid 0
   （`stat -c` 读到 `/dev/block/dm-74: block special file 600 root:root`）⇒ 现在的说法只能是
   **"围住了文件系统"，不能说"围住了这台机"**：绕过文件系统直接写 /data 分区这条路还开着。
   bwrap 的 `--dev` 是给一个全新 tmpfs、只放七个 API 节点。能不能仿出来，实测到一半：
   `scripts/dsh-dev-node-probe.sh` 在 ns 里 `mount -t tmpfs tmpfs /dev` **OK**，`mknod` 六个成功
   （zero/full/random/urandom/tty/ptmx），**唯独 null 失败**，而且失败之后 `echo x > /dev/null` 还报"成功"
   —— 那是在 tmpfs 上建了个**名叫 null 的普通文件**，又一条假通过（这条判据得改成 `test -c /dev/null`）。
   退路已经写好在 `scripts/dsh-devnull-inner.sh`：覆盖前先 `mount --bind /dev /tmp/devkeep` 留把手，
   换上 tmpfs 之后再 `mount --bind /tmp/devkeep/null /dev/null` 把宿主那个真节点叠回来。**这条没跑完**
   （跑到那一步 ADB 断了：`: no devices/emulators found`），所以 /dev 这块现在是
   "已知缺口 + 有一条待验的修法"，不是"已解决"。
2. **没接线**：`profiles/web/cordis.patch.yml` 里还**没有** `runnerCommand`。接线上要重启服务，
   而重启会换 token（`dsh.log` 里数得出四条不同 token），他手机里那条入场链接会失效 —— 这代价得他挑时间，
   我不自己按。接线要配的两行形状（配错了会在构造期 throw，不是静默降级）：
   ```yaml
   - id: sandbox-policy
     config:
       mode: workspace-write            # 或靠 14.10 那个环境变量，别两处都钉
       runnerCommand: ["/usr/local/bin/dsh-unshare-run"]
       runnerFailureSignatures: ["dsh-unshare-run: "]
   ```
   还有 `DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=1` 该钉在哪：runner 是被 dsh spawn 的，继承服务 env，
   所以进 `/root/.dsh-env` 一行就够。**这条等于替机主认下"被围命令可以 kill dsh 自己"**（本机无 PID_NS，
   没有第二个选项），默认不给这个变量时 runner 是 127 拒绝执行 —— 那是"安全但整档不可用"。
3. **dsh 那一层的端到端没验过**：以上全是"我直接在 chroot 里调 runner"的读数。runner 交给 dsh 去 spawn
   之后，工作区路径由 `policy.workspaceRoot`（`canonicalPath(process.cwd())` = `/phone`）填进来，
   这条链路一个字都还没跑过。要跑就得重启，回到上一条。

#### 五、这一节对 14.4 那句判据的修正

14.4 写的是"这台内核上 `workspace-write` 跑不了 Bash"。这句话现在要收窄成：
**跑不了的是上游那两条后端（bwrap 要 USER_NS、Landlock 没编）；mount namespace 这条路能力在、
也已经真围住了文件系统的写，只是上游 0.2.1-rc.2 没为 android 写这一档，得由运维用官方 `runnerCommand` 口子补，
且补完还剩 `/dev` 裸设备这一条明确缺口。**

### 14.12 三家 APK 形态方案读完：同一堵墙，三种答法，第四种没人做（2026-10-20）

他给的三个链接：`DSH-APP/DSHA`（1,720★）、`woaiys3/deepseek-harness-android-app`（519★）、
`Soodok/Deepseek-Harness-Local-Android`（296★）。逐文件读过，完整报告在
**[`reference/android-three-community-apps.md`](android-three-community-apps.md)**（含每家的 `文件:行`、
一屏对照表、可借鉴清单、风险四条）。**声明在先：三家我一个都没跑过，纯静态阅读，运行时行为一律没有读数。**

路线上是三种办法，只有一档和我们有共同前提：**DSHA 把 Ubuntu 24.04 rootfs 整个打进 APK**
（`ManagedRuntimeAssets.java:126` 从 `assets/offline-rootfs.layout` 解，README 自己标了 273.10 / 345.27 MiB 的代价），
引擎 bxroot 默认、`Proroot` 已 `@Deprecated`（`ContainerRuntime.java:166`"build172 不含可执行 proroot 实现"）；
另两家走 bionic 裸跑，钥匙都是 **`targetSdk = 28` 豁免 Android 10+ 的 W^X**
（Soodok `build.gradle.kts:20-22`、woaiys3 `AndroidManifest.xml:8`）。

**本节只留一条改变决定的读数 —— 沙箱这一项，三家最终全落在 `danger-full-access`，但表述质量差三档**：

1. **DSHA 明说没围**：`ConfigStore.java:455` 默认值字面 `"danger-full-access"`，仓库自陈"工具审批 ≠ 强沙箱"，
   另写了一套 fail-closed 的危险命令 JS 闸门（`assets/destructive-policy/index.js:10-26`）。诚实。
2. **Soodok 撞上我们同一句报错然后绕开**：`EngineConfig.kt:406-414` 引的模拟器原文
   `refusing to run the command unconfined; no sandbox backend usable on host` **和我们设备上一字不差**，
   它的处置是把安全边界整体挪到 App 层（三级权限 + su 闸门），`:481-508` 用 `--patch` 硬钉 never/approval。合理但不彻底。
3. **woaiys3 是谎报**：`dsh-bash-local/lib/index.js` 里 `get sandboxMode() { return "workspace-write"; }`，
   而紧邻的注释（v1.15 订正那段）自己承认"本执行器只 inject subprocess，**从不调用 ctx.sandbox**"。
   动机写在 :70-78 —— 0.1.7 的 `dsh-permission-presets` 构造时检查这个 getter，`undefined` 就抛
   "does not confine (no sandboxMode)"，于是**让它看起来 confine**。
   **这条和 14.11 第一节那两个 bug 是同族问题**：dsh 把 `sandboxMode` / `enforcement` 当可信声明在用
   （`dsh-sandbox-local-index.js:318` 一配 `runnerCommand` 就记 `"full"` 且不探测），所以"报得比做的宽松"
   会让审批链跟着放松。**我们的 runner 之所以要 34 条正反判据自己对外验，理由在这里被第三方样本补全了。**

顺带三件能马上用的（进 14.11 第五节那份清单，不新开任务）：**`/phone` 是 bind 过去的 FUSE，
link/`wx`/目录 fsync 三处语义容忍补丁早晚要**（woaiys3 已把失败形状贴全）；**一次性 token 不能被健康探测消费**
两家独立踩过；**0.2.0 起 `peerDependencies` 不匹配会让插件静默消失不报错**（`CHANGES.md:795-797`）。

两条明确不抄：**Soodok 无障碍服务声明 `canRetrieveWindowContent` + `canTakeScreenshot`，
而给用户看的中文说明是"仅声明手势注入能力，不读取屏幕内容"**（`strings.xml:38` 对 `res/xml/*.xml`）；
**woaiys3 把引擎 stdout 原样镜像到 `/sdcard/DeepSeekHarness*/dsh-web.log`**（`MainActivity.java:3934-3966`，
注释明写"无需 root/adb 可读"）而 token URL 就在 stdout 里 ⇒ **bearer token 明文落共享存储**。
我们日志现在全在 chroot 私有路径，这条是**我们做对了、要写死别改**的。

### 14.13 他点名的两仓已经在本地盘上，但"克隆"这个词被链路改成了两段活（2026-10-20）

他这句的意思是只要两仓在本地（`DSH-APP/DSHA` 与 `woaiys3/deepseek-harness-android-app`），
`Soodok/Deepseek-Harness-Local-Android` 本轮他明确"先不用看它"。现在盘上：

| 目录 | 文件数 | 树 / `.git` | 本地提交 | 提交消息里记死的上游 |
| --- | --- | --- | --- | --- |
| `reference/gh-3p/DSHA-main` | 2,861 | 66 M / 32 M | `a92928f` | `main @ fe07a028673a4c92cc2f7a773a36883ac11d61ff`，包 32,875,642 B，sha256 `ed41227d…`，`pushed_at=2026-10-19T18:43:16Z` |
| `reference/gh-3p/deepseek-harness-android-app-main` | 266 | 20 M / 7.4 M | `72f553e` | `main @ 98162a23b39eeeb75b8d4608b3e773bbb13be43d`，包 8,204,504 B，sha256 `814314f0…`，`pushed_at=2026-10-18T01:28:44Z` |

两个都是**真 git 仓库**：`git remote -v` 指向上游、`git status --porcelain` 空、`core.autocrlf=false`。
每个只有一条出处提交 —— 将来怀疑"我读的到底是哪一版"，看提交消息就够，不用回头翻 `downloads/gh3.sha256`。

**为什么不是 `git clone` 就完事**（今天逐条实测，全部是读数不是猜）：
`github.com:443` 直连不通；能用的镜像只有 `ghproxy.net`（`info/refs` 返回 200 / 10,789 B，
但 git 通道 ~30 KB/s 且**每次跑到 4~6 分钟必被掐**）；`gh-proxy.com` 对 git 协议返回
`expected flush after ref listing`、对它走 codeload 是 403；`gitclone.com` 的 `ls-remote` 直接超时。
直连 `codeload.github.com` 是唯一通的：60 秒下 5,296,133 B = **88,265 B/s**。
在这个带宽上整仓克隆失败四次（DSHA 6 分 21 秒、woaiys3 4 分 4 秒），报错三件套
`RPC failed; curl 18 transfer closed with outstanding read data remaining` / `early EOF` / `fetch-pack: invalid index-pack output`。
⇒ **文件树先落地（走 tarball，它只要 60 秒级），历史单独啃**：`tools/clone-upstream.sh` 把一次大转移拆成
浅克隆 → 逐段 `--deepen`（100/500/2000/20000，每段独立重试）→ `--tags` → 试一次 `--unshallow`，
任何一步断了只重试那一步，`GIT_HTTP_LOW_SPEED_LIMIT=2000`/`TIME=90` 保证卡住就断不空等。

**但那份按"深度"切，切错了轴，跑了 4 分钟就看出来，改成了 `tools/fetch-history.sh` 按"对象类型"切**（读数）：
浅克隆那一包**必须装下当前整棵树**，而这两仓的树里全是大二进制 —— woaiys3 一个 `legacy-patch/esbuild.exe`
就 11,694,592 B；DSHA 光三个 asset（`adb-wheels.tar.gz` 9,951,074 + `glibc-python.tar.gz` 6,565,414 +
`pnpm-runtime.bin` 3,837,861）= **20.4 MB 不可压缩字节**，按实测 19~28 KB/s 折 13~18 分钟一趟，
而镜像**每 4~6 分钟必掐** ⇒ DSHA 这一档在深度轴上基本不可能落地。第一趟实测速率是从 `.git/objects/pack/tmp_pack_*`
的涨速算的（13:21 的 1.7 M → 13:24:55 的 5.9 M），所以这条不是推测。
`--filter=blob:none --no-checkout` 只搬 commit + tree，历史里的文件内容按需取 ⇒
**`git log` 全通、`git log --name-status` 通、`git show` 正文按文件拉几 KB**，而工作区一律还是读同目录那两份 `*-main`
快照（内容已按 tarball sha256 对上，不缺东西）。两份脚本都留着：深度那份是"连历史 blob 也要"时的退路，
object 这份是当前能成的那条。**换轴之后的实测：woaiys3 298 条提交 / 28 标签 9 秒落地，DSHA 627 条 / 28 标签 27 秒落地**
（`downloads/fetch-history.log`）—— 同一个镜像、同一个 `GIT_HTTP_LOW_SPEED_*`，前面四趟整仓克隆全死。
两份 hist 的 HEAD 各自逐字等于上面表里那条出处提交记的上游 sha ⇒ **"我读的是哪一版"这件事现在有硬答案**。
**一处将来会咬人的地方先写在这**：那两份 `*-hist` 的 `remote.origin.url` 是 `https://ghproxy.net/https://github.com/...`，
不是 github 直连（blobless 仓库按需取 blob 走的就是这个 URL）—— 别按快照仓库那样理解成"origin 指上游"，
也别把它当可信第三方；哪天镜像换了直接 `git -C reference/gh-3p/DSHA-hist remote set-url origin <新镜像>/https://github.com/DSH-APP/DSHA.git`。
两份 `*-main` 快照的 origin 才是 `https://github.com/...` 原样（它们从不 fetch，只是个带出处的本地仓库）。
历史读出来的五条（含"release 资产能在不改版号下被就地替换"这条）在报告**第六·补**节，本文不复述。

**这一轮我自己踩的三个坑，都记死**：
① 判"克隆好了没"第一次用的是 `rev-parse --is-shallow-repository` —— 半截仓库上它返回 `false`，
于是我打出过一次**假的"就绪"**，紧接着后台重试的 `rm -rf` 把目录删了。判据换成 `rev-parse HEAD` + `README.md` 存在。
② 提快照时 `core.autocrlf=true` 刷出满屏 CRLF 警告（这些仓库是 LF），改成 `core.autocrlf`/`safecrlf` 都 `false`，
索引和工作区按解包原样保持 LF。
③ **停一个后台链路不能只杀最外层 bash**：我杀了外层那两个之后，脚本里的循环还活着并**立刻推进到下一仓**，
盘上同时跑起两趟克隆（互相分掉本就只有一根细管子的带宽）。要停得先杀 `git-remote-https.exe`/`git.exe` 这些叶子，
再杀 `sh.exe`（跑脚本那个），最后复查一遍 `Get-CimInstance`；复查时**别拿"命令行里含 ghproxy"当判据**，
我自己那条查询 shell 也含这个词，会把自己列进去顺手杀掉。杀掉的两份半截克隆目录（`DSHA` / `deepseek-harness-android-app`）
已 `rm -rf` 清掉，两份 `*-main` 快照复查过没受影响（`a92928f` 2,861 文件 / `72f553e` 266 文件，dirty 都是 0）。

**顺带纠正他那句"这个项目有三种形态，有免 root 可以用的，还有 root 形态可以用的"** ——
DSHA 那三种是**手机设备命令的三个通道**，不是引擎的三种跑法：README:164「Shizuku / Root 通道 —— 备用设备命令通道，
与 ADB 同受命令白名单约束」、README:230「设备命令：白名单始终开启，Root / Shizuku / ADB 三通道同一套策略」，
`util/DeviceShellPolicy.java:11` 那句"设备命令默认拒绝：只接受可完整识别的单条 argv，不执行用户提供的 shell 程序"，
:15 的 `enum Kind { READ, FILE, STOP, SENSITIVE_READ, VIRTUAL_SCREEN, DENY }`。
**引擎本身永远跑在 App 自己那套 rootfs 里**（`ContainerRuntime.java:10` 由冻结的 `EngineSpec` 统一选 bxroot 或 proot，
代码里大量 `root` 其实是 `proot.getRootfsDir()` 这类路径调用），所以"免 root 能用"指的是**跑 dsh 不需要 root**，
"root 形态"多出来的只是**能替你操作这台手机**（读屏、点按、装应用、虚拟屏）那一层能力。
它自己的 dsh 权限默认值仍然是 `danger-full-access`（`ConfigStore.java:455`）—— 也就是说
**root 通道给它的是对手机的权力，不是给模型更少的安全边界**，这两件事在他那句里被合成一件了，值得拆开。

### 14.14 手机入口换成「常驻入口 + WebView 壳」：点开就是完整前端（2026-10-20）

他先问的那句是 **"他们写的那些桌面端软件都没办法做到打开就用的吗？"** —— 答案是**能，而且三家都做到了**，
只是"打开就用"这四个字背后省掉的东西各不相同：DSHA 的 `DshAuthUrl.java:25-26` + `WebPreviewActivity.java:692-706`
是 App 自己起引擎、自己在内存里把一次性 token 换成 `dsh-auth-*` cookie；Soodok 的 `dsh-lan-proxy.js:60-78` 是
一个常驻小工具代它换；woaiys3 `MainActivity.java:4139` 同形状。**没有一家是"把 token 存下来反复用"** ——
那条路被上游的鉴权设计堵死了（token 一次性、能久用的是 30 天的 cookie）。DSHA 也仍然要点一下「启动」
（`LaunchFragment.java:313-316`），所以"点开就用"这件事我们这条不比它差。

我们的形状差别只有一处：**引擎在 root 的 chroot 里，一个无权限的 APK 起不了它、也读不到它的 stdout**。
所以"起引擎 + 认那行启动日志 + 换 cookie"这半挪进了机上的常驻小工具 `scripts/dsh-entry.js`（Soodok 那个代理的形状），
App 退回成一个纯 WebView：地址永远写死 `http://127.0.0.1:3081/`，重启多少次都不用改、不用粘、不用看日志。

**这一轮交付的三件**（都在项目内，机上落点写在括号里）：
`scripts/dsh-entry.js`（chroot `/usr/local/bin/dsh-entry.js`，47,151 B，只绑 127.0.0.1）·
`app/src/com/zhl/dsh/MainActivity.java`（`com.zhl.dsh` 0.2 / versionCode 2，82,537 B，
sha256 `65c496660419d906b8b5a66b4daf61cd17371a18ca624d9de58394e87161e8b3`）·
`tools/deploy-entry.sh` 一条命令管部署与观测（`--entry` / `--status` / `--check` / `--pull-key`），
`--check` 跑的是 `scripts/dsh-entry-check.sh`（机上 `/root/dsh-entry-check.sh`）。
控制台的第 2 项现在直接起入口、第 3 项直接 `am start` 开 App，`w)` 保留旧的"裸引擎 + 粘 token"那条对照路。
**装到机上的那份与本地产物是同一串字节**：`sha256sum /data/app/…/com.zhl.dsh-…/base.apk` =
`65c49666…161e8b3`，与 `app/out/dsh-app.apk` 逐字相同 —— 这条不是顺手一验，是**就地改口**：本节第一版写的
`b59834b0…` 是 19:53 那次重打（加 `clearCache` 与日志那两笔）**之前**的旧构建，我拿盘上读数对了一遍才发现自己抄了旧数。
以后凡是写 APK 的 sha，判据固定为"本地产物与机上 base.apk 两个读数同时贴"，只贴一个迟早再错一次。

**真机读数（一次跑齐，零出网）**：入口 pid 27993，引擎 pid 28023，`upstream http://127.0.0.1:3080/`，`gen 1`，
`auth cookie 有`、`token 待用 无`（用过即清）。门禁四种：无 cookie **404**、错 cookie **404**、错 Host **404**、
裸 3080 **401**（404 是故意的 —— 不告诉扫描者这端口存在）。App 侧四行日志走完：
`open-entry`（口令 43 字符，值不打印）→ `cookie setCookie(...) accepted=true` → `page-start` →
**`page-finish ｜标题=DeepSeek Harness｜进度=100`**，`ws=18`（SSE/WebSocket 走的是那条注入 cookie 的原始隧道）。

**首页字节的顺序，这一轮才真正对上**：页面 42,740 B，摘掉我们的 tag 是 39,571 B（差 3,169 B）；
内联落在 `at=41`（`<head>` 开标签之后），上游第一段脚本在 `at=254` —— 那一段是**服务在出口现插的引导**
（`<script>(()=>{const pendingQueue=[]window.__ModuleLoader__={`），盘上那份 876 B 的
`dist/index.html` 里根本没有它；第一段 `type="module"` 在 `at=38534`。`order=ok`。
盘上那份首页 `mode 644`、`grep -c data-dsh-entry-compat` = **0 行** ⇒ **我们没改上游文件**，
兼容层只在出口注入，这一条现在由读数而不是由我的一句话担保。

**这一轮我自己踩的三个坑，全按读数改口，都写死**：
① **锚点顺序判据是恒真的假 PASS**。`injectHtml` 原来先试 `</head>`、找不到才试 module script，而 dsh 的首页
把 `<script type="module">` 放在 `<head>` **里面**（本地 `reference/dsh-web-frontend-index.html`：module 456 /
`</head>` 764；真页面：38534 / 41615）⇒ 先试 `</head>` 永远赢，polyfill 恒排在引擎脚本后面。
更难看的是自测：合成页面把 module 放在 `<body>` 里，于是那条判据在旧代码下也绿。现在三个候选位一起算取最早，
偏移直接打进 `/__entry_status` 的 `内联位置` 那行，合成页面改成照真页面的形状，并新增"拿真文件当用例"
（`DSH_ENTRY_TEST_PAGE`，机上指的就是那份 `dist/index.html`）。
② **注入对 App 静默失效，两个计数都不动**。WebView 默认带 `Accept-Encoding: gzip`，上游一 gzip，
`isHtml` 就判假（我们只认 identity），于是原样透传、`injected` 和 `injectMiss` 一个都不加 —— 从状态页上完全看不出来。
发现它是靠新加的"最近请求"那行：App 打开之后入口只收到 `/assets/*.css|js`，**一条 HTML 都没有**。
修法是对"可能要改字节"的那类请求（GET 且路径无扩展名或 `.html`）剥掉 `accept-encoding`，静态资源继续吃上游的 gzip。
③ **客户端会缓存我们改过的字节**。入口重启后 App 一条 HTML 请求都不发 —— 它吃的是 WebView 里那份缓存的旧首页，
里面是上一版 polyfill，于是"改兼容脚本不用重启入口"这句话在出口成立、在客户端不成立。
现在凡是真注入过的 HTML 一律回 `cache-control: no-store` 并撤掉 `expires` / `last-modified`，
面板上那个「重载」另外加了一句 `clearCache(true)` 兜住已经躺在缓存里的那份。
判据：不 `pm clear`、只 force-stop 再开，`injected` 从 1 走到 2。
④ **"搬完立刻删干净"这句我自己没做到，而且是写进 changelog 之后才发现没做到**。`tools/deploy-entry.sh` 的
`push2` 有两条分支：不剥 CR 的那条 `mv $stage $dst`，原件跟着目标名一起走了；**剥 CR 的那条 mv 走的是
`$stage.lf`，原件 `$stage` 没人删** ⇒ 每推一份 `.sh` 就在 `/data/local/tmp` 留一个 `.dshdeploy.<pid>`。
`ls -a` 读到 4 份（都是 19:22 那批，20,229 / 4,492 B 两份对上 `dsh-chroot.sh` 与 `dsh-console.sh` 的尺寸），
外加一份已被本节 `dsh-entry-check.sh` 取代的旧 `probe-page.sh`。两条分支现在各补 `rm -f $STAGE/$name`，
机上那 5 份手删，复点 `(无)`，他的 71 件照旧。教训口径：**"清理过"这句话的判据只能是删完再 `ls` 一遍的读数，
不能是脚本里有一句 mv**。

**顺手补的三条读数与一个口子**（2026-10-20 20:0x，都是只读或逐字节可验的小改）：
① **壳的内核到底多新** —— `dumpsys webviewupdate`：`Current` 与 `Preferred` 同一份
**`com.google.android.webview 130.0.6723.58`**（versionCode 672305833，beta/dev/canary/debug 与 `com.android.webview`
都不在位）。这条给的是"能不能拆兼容层"的**前提**，不是结论：拆的判据是"拔掉 polyfill 在 App 里走得完一个真回合"，
而 curl 看不见 JS 异常 ⇒ 要他在场点图标才算验（做法写在 PROGRESS 下一步第 11 条）。
② **装机那份 APK 与本地产物逐字节相同**：`sha256sum /data/app/…/base.apk` = 本地 `app/out/dsh-app.apk` =
`65c49666…161e8b3`。本节第一版写的是 `b59834b0…`，那是 19:53 重打之前的旧构建 —— 按盘上读数改口，
以后 APK 的 sha 一律"本地 + 机上 base.apk"两个读数同时贴。
③ **入口交付物与仓库那份逐字节相同**：`sha256sum chroot:/usr/local/bin/dsh-entry.js` = 本地
= `296d82a382a0…`，47,151 B / 0755；`/root/.dsh/entry.key` 44 B / **0600**（值不打印、不进 argv、不进日志）。
④ **一个只在真重启那天才会咬人的口子，今晚先堵了**：`scripts/dsh-boot.sh` 自启拉起的是 `--web`（裸引擎），
而 App 指的是入口 `:3081` ⇒ 哪天他把自启拨回来并重启，点开图标会停在「连不上工作台」那一屏，
且症状长得像"入口坏了"。改成**入口脚本在位就 `--entry`、不在位才退回 `--web`**（1,861 → 2,477 B，
`sh -n` 过），机上那份 `50-dsh.sh.off` 同步为逐字节相同（`4207c1bbf779…`，mode 0750 不变）。
**仍然没开自启**（后缀 `.off` 原样），所以这条改的是"哪天开的时候别踩"，不是"现在多了一个服务"。

**装机这条路为什么不是 `adb install`**（两条看着更顺的都实测不通）：
`adb install -r` → **Failure [-99]**（这台一加 13 的 USB 安装闸口，要他本人在开发者选项里放行）；
`pm install /data/local/tmp/x.apk` → **System server has no access to read file context
`u:object_r:shell_test_data_file:s0`**（Android 11+ 的规矩，跟我们有没有 root 无关）。
通的是：push 到 tmp → root `cp` 进 `/data` 根 → `restorecon`（**必须 cp，mv 会把旧标签原样带过去**，试过）→
`pm install -r` → 两处落点都删。整段已经写进 `app/build.sh --install`，实测 `Success` / `pm_rc=0` /
`versionName=0.2`，装完复查 `/data/dsh-app.apk` 不存在。
顺带记一条 aapt2 的规矩：**清单里写了 `android:versionName` 就以清单为准**，`--version-name` 那对参数只是缺省值 ——
第一次装出来是 0.1，因为清单没跟着改。

**安全口径没让步的地方**：只绑 127.0.0.1（**不学 DSHA `LanProxyService.java:308` 那样 bind 0.0.0.0**）；
Host 白名单挡 DNS rebinding；口令 `dsh-entry=<43>` 由壳在首次加载前用 `CookieManager` 种下，
`HttpOnly` ⇒ 页面 JS 读不到；token 全程不落盘、不进日志、不进 argv；`/data/local/dsh.log` 收成 **0600**
（原来是 0644 且里面有 token 行 —— 我上一版说过"日志全在 chroot 私有路径"，那句是错的，现在按读数改口）；
自测里那条"拿不到口令 ⇒ `--start` 直接 exit 2，而不是起来一个空口令的入口"是产物级断言（真 spawn 一次，
并检查它的 argv 里没有口令）。**代价也说清楚**：口令打进 APK，APK 在设备上可读，所以这道门是"抬高门槛"
不是"密不透风"；`WebView.setWebContentsDebuggingEnabled(true)` 开着（电脑 chrome://inspect 能直接挂进这个页面），
任何能 adb 到这台机的人都能驱动它 —— 这台机常年 adb + root，所以开，不想开删那一行重装。

**四处还没验 / 还没收口的**：
① **画面本身**。手机现在 `mWakefulness=Dozing`、`isKeyguardShowing=true`、`locksettings get-disabled=false`，
截屏只能拿到全黑，而我不绕他的锁。所以"完整前端在屏幕上真的渲染出来了"这条只有间接证据
（标题、进度 100、ws=18、资源 200），**要他解锁点一下图标才算验完**。
② **页面里还引用着一份历史遗留的就地补丁** `./assets/dsh-compat.js`（3,123 B）。它和我们现在内联的那份
**字节全等**（两边 sha256 都是 `c43d6606b263b2b8d49029768ec787e2f58110637cd2ab2848a8bc553a3b9cc1`），
所以是同一份代码跑两遍，幂等、不冲突。摘它需要上游那份未改的 `index.html` 做逐字节还原，收益低，先留着并记在这。
**退回路径**：`sh /data/local/sh/dsh-chroot.sh --entry-stop` 之后一切回到 14.13 之前那个形状
（裸引擎 + 日志里那条 token URL + 浏览器打开），那条路 `w)` 还在控制台里；壳 App 卸载即可，它不写任何别人的文件。
③ **`--status` 里那行"带token走完: http=401 bytes=68"是对的读数，别读成坏了**。token 已经被入口用掉了（一次性），
裸引擎那条探针再拿日志里的旧 token 去换必然 401 —— 这正是"一次性 token 不许被健康探测消费"那条老坑的形状，
现在它变成了一条**只有入口在位时才会出现的固定 401**。判活看的是同一屏的 `:3081 LISTEN` + `http=200` +
`engine running`，不是这一行。欠的那半：`dsh-chroot.sh --status` 现在把这条 401 打在"预期 401"旁边没有区分说明，
应该照"入口在位 ⇒ 这行恒 401 且属正常"补一句注解（PROGRESS 下一步第 9 条 ③ 的同一家族）。
④ **入口的"停 → 再起"循环在真机上一次都没走过**。今晚两次读数都落在同一个进程上（`gen 1`、`运行 441 秒`、
pid 27993），所以"restart 之后 App 点开还能进"这件事只有间接证据：`--selftest` 里那条哨兵断言
（`--stop` 写哨兵 ⇒ 自动重拉逻辑不再起第二个）与 46/46 的产物级自测。真做一次会换掉引擎那条入场链接，
所以排在"他哪天愿意重启一次"那一趟里一起做，不单独动他的服务。


---

### 14.15 他验收时报的四个症状：两个查到根因并有差分读数，两个只有嫌疑（2026-10-20 晚）

他那句原话拆成四件事：**「上面一大堆全都是代码」**、**「整个体验迟钝、不丝滑、容易卡住」**、
**「点了插件没反应，不跳到添加插件那页，要我自己返回」**、**「选工作区目录时显示 …PICK…LIST… HTTP 403，
是不是没连接 API 导致的？是不是需要我连上 API 给你实测一下？」**。

**先答他最后那一句：不需要。** 403 不是"没连 DeepSeek 的 API"，也不是"没登录" —— 推理链路那一层这轮一个字节
都没碰（key 早就他自己填好了，14.4/状态 4 那条真回合读数照旧成立）。这个 403 发生在**更前面一层**：
我们自己那个入口把请求转给裸引擎时，被引擎的**同源栅栏**挡在门外，跟外网、跟模型都无关。下面是读数。

**① 屏幕上那一大片代码 —— 根因取到了，是 HTML 解析规则，不是我们注入了两段**

`<script>` 的内容在解析器眼里是"script data"态：**看到第一个 `</script` 就闭合，不看 JS 语法、不看它在不在注释里**。
`tools/dsh-compat.js:8` 那行注释里原样写着 `<script src="./assets/dsh-compat.js"></script>`，内联进首页之后
解析器就在字节 533 处把这段 `<script>` 关掉了 —— 剩下 2.6 KB 源码于是成了页面上的**可见文字**，
正好是他说的"上面一大堆全都是代码"。（同一条规则还管 `<!--`：它会切进 "script data escaped" 态。）

修法：入口内联前过一次 `escapeForInline()`（`scripts/dsh-entry.js:305`）—— `<\/script` 与 `<\!--`。
这两个字面量在我们那份 polyfill 里**只出现在注释和字符串里**，加一个反斜杠不改语义；这个前提写在函数注释里，
将来谁往 polyfill 里加了真·正则字面量就该来看这行。

判据（`scripts/dsh-entry-check.sh`，机上跑，全程只读）：
`我们这段之后紧跟 "<base href=…"` ⇒ 闭合之后落回标签而不是裸文本；
`摘掉所有 script/style 之后正文里还有 polyfill 源码吗 → 没有`；`正文可见文本 16 字符`（上游模板本来那点字）；
`元素完整性=ok at=2805 完整`（入口自述里那一行，字节偏移自己算出来的）。
这一节是**这一轮新加的**，因为原来那条"顺序 ok"判据管不了这件事：polyfill 排在引擎脚本之前、
照样能被同一个坑打成一片裸代码，两个判据不重叠。

顺手抓到我自己一个 off-by-one：算闭合位置时 `wantCloseAt` 少算了开头那个 `\n`，自测报
`首个 </script 在 170，应在 169` —— 是判据算错不是产物错，改成 `+2`，并把那对标签抽成
`COMPAT_OPEN_TAG` 常量（同一串字面量原本抄在四个地方，必出错）。

**② 那句 HTTP 403 —— 根因是引擎的 Origin 栅栏，穿过入口的差分前后各量了一遍**

引擎里 `@deepseek-ai/dsh-client-connection/lib/index.js` 的 `isTrustedApiRequest()` 要求
**Origin 头的 `host:port` 逐字等于 Host 头**（`isSameAuthorityOrigin(origin, host)`），不等就 `{rejection: 403}`。
我们的入口把 Host 改写成 `127.0.0.1:3080` 交给裸引擎，而 WebView 发出来的 Origin 是 `http://127.0.0.1:3081`
⇒ **凡是带 Origin 的请求全被这条栅栏打死**；导航请求不带 Origin，所以页面能开、一点按钮就 403 ——
和他看到的"页面在、选目录报错"完全对得上。

裸引擎上的差分（2026-10-20，同一分钟量）：`Origin=:3081 ⇒ 403`、`Origin=:3080 ⇒ 401`、`不带 Origin ⇒ 401`。
后两条是"过了栅栏、停在鉴权那一层"，只有第一条被拦在门外 —— 这一发把"403 来自栅栏"和"403 来自没登录"分开了。

修：入口转发时连 Origin 一起换（`scripts/dsh-entry.js:352` 的 `proxyRequest` 里，改 Host 那两行紧跟其后），
Referer 同源一起换但只换 authority、路径与 query 原样（`swapAuthority()`，`:245`）；
WebSocket/SSE 那条 upgrade 隧道同样两行（`:483`）—— 上游 `dsh-api-gateway/lib/types/stream-server.js`
里有个 `rejectRemoteStreamUpgrade(..., 403)`，同一族问题在隧道上是另一个入口，只修 HTTP 会留一条更隐蔽的 403。
判据：自测 4f 那组（假上游开 `/__origin-echo` 回读 `{origin,host,referer}`）三条 ——
Origin 被换成上游 authority、Referer 路径保住、客户端没发 Origin 时**不无中生有**；
隧道那组另加 `X-WS-Origin` / `X-WS-Referer` 两条断言。

穿过入口的 A/B（修之前 / 修之后，同一个探针）：`带 Origin ⇒ 403 → 404`，`不带 Origin ⇒ 404 → 404`。
这里的 404 是**放行之后**的结果，不是"还坏着"：我拿的那条路径（`/api/session/list`）在这个 dsh 版本里本就不存在。

**读数之外要说清的**：他那句里的是**选择器**，而我没找到选择器真正走的那条 HTTP 路径。盘上抓到的形状是
RPC 方法名而不是 URL —— `directoryPicker/createDirectory` ×18、`directoryPicker/list` ×9、`directoryPicker/pick` ×6，
出处 `ce-controller/src/directory-picker.ts` 与 `api/workspace-controller/src/directory-picker.ts`；
我照着猜的 `POST /api/rpc` 两条都 404（带不带 Origin 都一样），所以**"他真点一次的那条路径"仍然没量到**。
它现在有了去处：入口的自述页把**非 2xx 环**（方法 + 路径 + 状态码 + UA + **Origin**）留 12 条，
他在 App 里点一次，哪条路径红、红成什么码、Origin 是什么，就落在里面 —— 不用再猜。
（Origin 这一列是这一轮加的，理由写在代码注释里：探针也会造 4xx，不分这一列就分不清"他手机上真红的那条"
和"我自己打出来的那条"。）

**③ "迟钝、不丝滑" —— 能排除的那半排除了，剩下一半我还没有判据**

入口的请求流水里，他 App 一次冷加载的四条静态资源全是 **157–163 ms**，而 77 KB 的 css 和 940 KB 的 js
用的时间一样 —— 跟体积无关的固定值。同一批资源我用 curl 串行重打一遍（`dsh-entry-check.sh` 新增那节
「静态资源耗时」）：`index-BxpfOGf3.css 77,343 B → 0.0025 s`、`index-CN7NIWNw.js 939,867 B → 0.0044 s`、
`vendor-DV2921Zo.css 27,312 B → 0.0021 s`、`vendor-DcuzkuQH.js 741,114 B → 0.0046 s`，再打一条热的没快。
⇒ **入口 + 引擎这一层是 2–5 ms 量级，那 160 ms 不在我们这两跳里**，最可能是 WebView 侧的并发排队
（四条一起发，每条都摊到一个固定等待）或者引擎在每个请求上的固定开销被并发放大 —— 两种治法不一样，
我还没分开，**这一条不许读成"迟钝已经解决"**。
还有一条嫌疑我明确没做：**SSE/WS 隧道没做背压**（上游推得快、`res.write()` 返回 false 时不 `pause()`），
真机慢网络下可能表现为"卡住"，这是嫌疑不是读数。

**④ "点了插件没反应、要我自己返回" —— 动了 App，但没验**

`setSupportMultipleWindows` 默认是 **false**，那种情况下 Chromium 会**静默丢掉** `target=_blank` 与
`window.open`：不报错、不发请求、不跳转。这和他"点了没反应"的形状对得上，所以我按这条改了壳
（APK **0.3**：`MainActivity.java` 开多窗口 + 实现 `onCreateWindow`，同域 URL 用当前 WebView 直接 `loadUrl`，
异域走 `openExternal`），另外补了两处手感的：`setOverScrollMode(OVER_SCROLL_NEVER)`（WebView 默认把页面当
可弹跳列表，滑动到边界整体回弹 —— 移动端 Web 壳"不丝滑"最常见的一条），以及新建 `res/values/styles.xml`
把 `windowBackground` 涂成和首页同色的深色（冷启动那一下的白闪）。
manifest 另加 `enableOnBackInvokedCallback="false"`。**这一条要老实标注**：targetSdk=35 在 Android 15 上
默认开预测式返回，而我们的返回逻辑写在 `onKeyDown(KEYCODE_BACK)` 里 —— `dumpsys package com.zhl.dsh` 现在
读到 `versionCode=3 minSdk=26 targetSdk=35`，这半是**事实**；"所以返回键不生效"是**推断**，
**要他真按一次返回键才知道**。还有一条更早的：上一版页面里那份历史遗留的阻塞式 `<script src="./assets/dsh-compat.js">`
（就在 `<head>` 最前面）也顺手没了 —— 它是同步脚本，会实打实拖慢首屏，这条属于"可能改好了但没量"。

**装机两件产物的指纹（这次两边都读了，逐字节相同）**

- 壳 APK：本地 `app/out/dsh-app.apk` 与机上 `base.apk` 都 **86,632 B**、sha256 都是
  `84ce80fafe1747d970adad3bac765e53211e6ffe76b3fb8073622846b234c1cc`；`versionName=0.3`、`lastUpdateTime=2026-10-20 20:39:24`。
  **改口**：我这轮先前记的装机 sha 是 `2511557f…`，那是**没按盘上读数写下来的**，现在按 `sha256sum` 改掉。
  → **这两串已经被 0.4 取代**（2026-10-20 深夜，见 14.18）：`versionCode=4 / versionName=0.4`、
  86,632 B、sha256 `b20c6ddfa38d53b4baa9bbcd4a01fa286707358224a9764f168ce467e632945c`（机上 base.apk 同串）。
  体积撞巧一样、内容不同 —— 所以**认版本只认 sha 和 `dumpsys` 的 versionName，别拿字节数当版本**。
- 入口：`chroot:/usr/local/bin/dsh-entry.js` **64,791 B**（本地逐字节相同），机上跑交付物自身
  `--selftest` **59 条判据 PASS 59 / FAIL 0**，Windows 侧同一份也 59/59。

**这轮真做过一次的"停 → 再起"循环，顺带抓到自家一条假警报**

`--entry-stop` → `[ok] :3081 已关闭` / `[ok] :3080 已关闭（等了 1s）` → `--entry` → 新引擎 pid=30921、
`gen 1`、`auth cookie 有`、页面 200/42,690 B。这一下补掉了 14.14 遗留问题 ④（"入口的停→再起在真机上一次都没走过"）。
为什么以前那两回打的是 `!! :3080 还在听（那不是入口起的？）`：**引擎是入口的子进程，入口死了它还要一两秒才退**，
而脚本发完 SIGTERM 立刻查端口 —— 读数是**真**的，但**结论**是假的。改成最多轮询 10 秒并把等待秒数打出来
（`scripts/dsh-chroot.sh:289-305`）。同一条链路上另一坑：`pgrep -f dsh-entry.js` 会**匹配到自己那条 `su -c` 包装命令**，
停完之后照样报出两个 pid（19669/19671 就是幻影）⇒ 这台机上判活只认端口（`ss`），不认 pgrep -f。

**上游目录这轮被还原成"我们从来没动过"**（这条同时改掉 14.14 里我那句不准确的话）

14.14 我写"盘上 `dist/index.html` 876 B、`grep -c data-dsh-entry-compat` = 0 行 ⇒ 上游文件没被我们改过"。
**那半句是错的**：0 行只证明**我这一版**没往里写，那个文件当时还带着**更早一轮**打进去的那行 polyfill。
现在真还原了：`dist/index.html` **825 B**，md5 读到 `5a1bf51057dbb270bcba7d997498db6e`，与仓库
`reference/dsh-web-frontend-index.orig.html` **逐字节相同**（这就是"还原"这件事的证明方式，不靠我自己数）；
`dist/assets/dsh-compat.js`（3,123 B，与出口内联那份字节全等）**已删**；打过补丁那版备份在
`/root/.dsh/index.html.patched-876.bak`（876 B，md5 `50c5ee3f6e147bf1535d328f7ad7e613`）。
**代价说清楚**：以后升级 dsh 不会再冲掉兼容层（只在出口内联），但**盘上少了一份"补丁版首页"的现成件**，
要推回去得从 Windows 侧 `reference/` 那一份推 —— 13.4 表里那条 `cp /data/local/sh/index.html.orig-dshmobile`
指向的文件已经不在了，我在原处标了，别照着跑。

**这轮新增的判据与工具（都只读）**

`scripts/dsh-entry-check.sh` 5,742 → **13,579 B**，加四节：内联元素**关得对不对**（不只是排在前面）、
**摘掉所有 script/style 之后正文还剩多少可见文字**、**静态资源耗时**、**同源栅栏差分**。
其中"抓资源名字"这节我先踩了自己一个坑：整页里 grep `assets/…` 会把 polyfill **注释里那句示例标签**
（`tools/dsh-compat.js:8`）当成一条真资源去请求，量出一个 404，看着像"资源挂了"⇒ 现在先 `awk` 摘掉我们那段
再抓（干净页 39,512 B / 整页 42,690 B，差值就是我们那段内联）。
新增 `scripts/dsh-cdp.js`（用 adb forward + Node 全局 WebSocket 直接跟 WebView 的 DevTools 说话：
`--list/--eval/--watch/--click/--url`，网络记录**只留路径不留 query**，因为 query 里可能带一次性 token；
**手机在 Dozing 时它拒绝跑** —— 实测那状态下 renderer 冻着，attach 直接超时，读数会假）。
它的用处就是把 ③④ 这两条现在只能猜的事变成读数：点一下"插件"，到底发没发请求、报没报 JS 异常。

**这轮在他手机上写的东西**（清单，全是我自己建的件）：`chroot:/usr/local/bin/dsh-entry.js`（64,374 → 64,791 B）、
`chroot:/root/dsh-entry-check.sh`（5,742 → 13,579 B）、`/data/local/sh/{dsh-chroot.sh,dsh-console.sh}`（20,763 / 4,492 B）、
`chroot:/root/.dsh/index.html.patched-876.bak`（新建备份）、`chroot:/usr/local/lib/node_modules/…/dist/index.html`
（876 → 825 B，还原成上游原样）、同目录 `assets/dsh-compat.js`（删）、装机暂存件（推过去当场 `rm` 并复点）。
**没动过**：他的会话 / 凭据 / 档位（`danger-full-access` 原样）、`/root/.dsh/entry.key`（值全程不上屏）、
KernelSU 与 susfs 配置、`/data/local/tmp` 下他自己那堆 boot/kpatch/magiskboot、自启的**开关**（还是 `.off`）、
16 MB 那个原生客户端（他点的"留着当对照"）。出网：**零发**（全程 127.0.0.1）。

**还欠的读数（只有他能给：解锁手机，停在「DSH 工作台」那一屏，然后按三下）**
① 拍一张屏 —— 证明上面那片代码真没了（我这轮只有字节级证据，屏幕上没看过）；
② 点一次**插件**，再看返回键能不能退回来 —— 这两下分别打的是 ③④ 那两条嫌疑；
③ 点一次**选工作区目录**，之后我读 `--status` 里的「非 2xx」环，那条真路径就出来了。
手机锁着（`mWakefulness=Dozing`）的时候截屏只有全黑、CDP 也连不上，**我不绕他的锁**，所以这三下等他人。

---

### 14.16 他真机用了一遍之后，从入口的请求流水里掉出来两条：一条是好消息，一条是我自己埋的坑（2026-10-20 晚）

他回来说"这版用着挺好，我就发了条消息测一下"。这句话本身不算读数，所以我去读了**入口的请求流水**——
他那一趟操作全在里面（`req=122`，App 侧一条 4xx 都没有，非 2xx 环里只有我自己 curl 探针那四条）：

```
POST /api/session/prompt        → 200 34ms App      ← 他发的那条消息
POST /api/schedule/list         → 200 12ms App
POST /api/agentPresets/list     → 200  8ms App
POST /api/skills/list           → 200 24ms App
POST /api/commands/list         → 200 12ms App
POST /api/session/create        → 200 66ms App
POST /api/directoryPicker/list  → 200  6ms App      ← 14.15 里我说"还没量到真路径"的那一条
```

**好消息是 14.15 那条欠账平了**：选择器真正走的是 **`POST /api/directoryPicker/list`**，穿过入口 **200 / 6 ms**。
14.15 我说"他真点的那条路径仍然没量到"，现在量到了；我猜的 `POST /api/rpc` 那条 404 是探针造的噪音，不是故障。
另外同一屏还读到 `engine running pid=…`、`auth cookie 有`、`ws=5`、`up401=0`、`reauth=0`。
**屏幕本身也第一次有图了**（他解锁在场时截的，`downloads/dsh-shot-2040.png`，363,580 B）：
深色完整前端，顶部是 logo + 新会话/插件/自动化任务/搜索会话名称/root/手机存储/未分组，会话菜单（置顶/重命名/
分叉/归档/复制 Session ID）正常浮出 —— **14.15 那个"上面一大片代码"在屏幕上确认没了**，不再只有字节级证据。

**坏消息是同一屏那行 `最后错误  ws upgrade 连不上上游`。查下来这条报错是假的，真相是我自己埋的两个坑。**

坑一：**隧道计时器管的是"空闲"而不是"握手"**。原来那行是
`up.setTimeout(8000, () => up.destroy(new Error('upgrade 连不上上游')))`，而且**从不解除** ——
`net.Socket` 的 timeout 是**每收到一个字节就重新计**的空闲计时器，所以任何一条安静满 8 秒的长连接
都会被我们自己掐掉，报错文案还指着"连不上上游"（他那一分钟根本没在动手机）。
前端形状就是"过一会儿不动它就像卡住，点一下才活"——**这条很可能就是他说的"容易卡住"里真的一部分**。
改法：只在"上游一个字节都没回"那段窗口里计时，首字节（那条 101）一到就 `up.setTimeout(0)` 摘掉，
窗口长度做成 `DSH_ENTRY_WS_HANDSHAKE_MS`（默认 8000），报错文案改成"握手 …ms 没等到上游首字节"。

坑二（更重，是**崩溃**不是手感）：`up.on('error')` 原来挂在 `net.connect` 的**回调里面**。
TCP 连接被拒时 `'error'` 在 connect 回调之前就发出 ⇒ 那一刻没有任何监听者 ⇒ **unhandled 'error' 把整个入口进程带走**。
这条我没有只写在注释里当推断，单独复刻了形状量一遍：同样的 connect 到没人听的端口，旧形状
`node:events:487 throw er; // Unhandled 'error' event / ECONNREFUSED 127.0.0.1:1`、**exit=1**；
把 handler 挪到外层之后同一发是 `外层接住了：ECONNREFUSED`、进程活着。
对上症状就是：**引擎重启的那一两秒里，只要 App 有一个 ws 在重连，入口跟着一起死**，屏幕上变成"连不上工作台"。

**判据（自测新增 6b 三组，59 → 62 条，Windows 与机上交付物自身都 62/62）**：
→ **这句里的三个数是推出来的，不是读出来的，14.17 按"合计"那行的实测改口**：本轮交付物在 Windows 与机上
**都是 58 条 PASS 58 / FAIL 0**（含 14.17 新加的那条"体Nms"），倒推 6b 加进去之前是 57。
"62"是我拿上一轮的 59 加三条新判据算的，"61/1"是同一个算法的产物 —— 而 6b 三条确实都在输出里逐条 PASS
（上面 ①②③ 那三行的读数是真是的），**错的只是那个汇总数**。立新口径：**判据条数只许抄脚本自己打的
"合计 N 条"那一行，不许把新增条数加在上一轮的 tally 上**；`R()` 的调用点数（65）也不等于跑出来的条数，
所以连"数代码"都替代不了读数。
① 握手成功之后**空闲 4 倍窗口（1 秒）隧道还活着**、字节照样回显 —— 这条是有判别力的：
把 `up.setTimeout(0)` 那行去掉跑退化版，机上/Windows 立刻 **61/1**，红的就是这条；
② 假上游开一条 `/ws-stall` 永不回 101 ⇒ 确实在握手窗口内掐掉，且 `lastErr` 里出现的是"握手"两个字；
③ 把上游指向没人听的端口 ⇒ 只掐这一条隧道，**随后一发 HTTP 仍然 200**（入口进程还在）。
③ 的判别力由上面那个独立形状复现撑着（退化版里 handler 位置没动，所以它不会红，红的是真进程）。

**产物与落位**：`chroot:/usr/local/bin/dsh-entry.js` 64,791 → **69,556 B**（逐字节校过），
`--entry-stop` → `[ok] :3080 已关闭（等了 1s）` → `--entry` → 新引擎 pid=18741、`auth cookie 有，已用 1 秒`、
`req=6 ws=0 lastErr=(无)`。**他的页面要重进一次**才吃到这一版（旧连接是旧的）。
零出网、没动他的凭据/会话/档位/自启开关。

**还欠的只剩两条**（都在 App 那一侧，要他在场点）：① 点一次**插件**看跳不跳（`onCreateWindow` 那处改动还没在屏幕上验过）；
② 按一次**返回键**看退不退得回去（`targetSdk=35` 是 `dumpsys` 读到的事实，"所以预测式返回吞掉 KEYCODE_BACK"仍是推断）。
另外 14.15 记的那条**SSE/WS 隧道没做背压**仍然没做 —— 坑一修的是"我们自己把安静连接掐了"，
跟"上游推太快、写不动时不 pause"是两件事，别混成一条。

---

### 14.17 那批 40 秒的请求：先分清是哪一侧慢，再谈修（2026-10-20 深夜）

14.16 记下他真机用过之后的读数是 `req=122`、全是 200。我把入口自述又读了一遍（`--status` 的入口那节），
**流水里掉出一簇很扎眼的耗时**：

```
POST /api/session/modelCatalog        → 200 40407ms App
POST /api/account/getUnnotifiedBonuses→ 200 40164ms App
POST /api/account/getProfile          → 200 40160ms App
POST /api/account/getBalance          → 200 40160ms App
POST /api/credentials/describe        → 200 40079ms App
POST /api/commands/list               → 200 40698ms App
```

同一条 `credentials/describe` 在同一个环里还出现过 **4ms / 5ms / 12ms / 17ms**。所以这不是"那个接口天生慢"，
是**有一批请求被整体按住了一下**。这六条在环里是**连着**的（环按完成时刻排，`S.seen.unshift`），彼此耗时只差
0.6 秒 ⇒ 推断：它们的**起止两头都落在同一段窗口里**，形状是"某个东西松了、整批一起走"，不是"六个接口各自随机慢"。
**注意这是推断不是读数** —— 环里只有耗时没有绝对时间戳，要把"一起完成"证死得给流水加开始时刻，本轮没做。

**为什么这条值得单独记**：他 14.16 那句"体验非常好、不迟钝"与我这行"有 40 秒"必须能同时成立，否则我们俩有
一个人在读错的东西。能同时成立的故事只有两种，而**这两种的修法完全相反**：

- **甲·卡在引擎那一侧**（冷启/等出网）：入口把请求转出去，引擎 40 秒才回头。修法在引擎或它的出网链路上。
- **乙·卡在他那一侧**（WebView 被后台冻结或锁屏节流）：请求体的最后几个字节或者响应被读走的时间被 Android 推后了。
  修法是把壳改成前台服务/保活，或者干脆不用管（他人不在屏幕前时慢不影响手感）。

**先把甲按下去一半（有读数）**：新写一份只读探针 `scripts/dsh-slow-probe.sh`（1,381 B，口令只走 `curl -K -`
的 stdin，不进 argv、不打出来），在 chroot 里用 curl **绕过 WebView、照样穿过入口 :3081** 串行重打那六个端点里
最可能被怀疑的四条，各 2–3 次：

```
/api/credentials/describe  200 总 0.0034s / 0.0037s / 0.0063s   连上 0.0002s  首字节 ≈ 总
/api/commands/list         200 总 0.0031s / 0.0032s / 0.0033s
/api/session/modelCatalog  200 总 0.0034s / 0.0035s
/api/account/getBalance    200 总 0.0033s / 0.0040s
```

**全是 3–6 毫秒，一次 40 秒都没有**。这一条量到的东西要说准：**它证明的是"引擎在这些接口上不慢"**，
它**没有**证明"引擎任何时刻都不慢"——我打完这一轮时引擎已经热了，而那一簇 40 秒发生在刚重启的窗口里。
所以甲只是"没有复现"，不是"排除"。另一条相关读数：`entry.log` 里在重启后各出现过一次
`存活探测失败：probe timeout`（那是入口自己 4 秒的 `/health` 探针超时，`scripts/dsh-entry.js:227`），
说明**引擎在刚起来的那一段确实有过不应答的窗口** ⇒ 甲还有嫌疑，而且现在有了一条独立证据。

**再把两种情况做成能分开的**（这是本轮真正的改动）：流水那行的耗时是在**上游回头**那一刻结算的
（`proxyRequest` 里 `startedAt` → `S.seen.unshift`），所以甲和乙在旧格式下长得一模一样。加一列
**"体Nms"= 入口把请求体收完的时刻**（`req.on('end')`，只加监听、不碰数据流；没收到就显示"未收完"，不假装量到）：

- 下次再看到 40 秒，**`体40000ms` ⇒ 乙**（他那侧送得慢）；**`体1ms` 而总 40 秒 ⇒ 甲**（引擎想得慢）。
- 本轮部署后实测：`POST /api/account/getBalance → 200 3ms 探针 体1ms`（两列都打出来了，格式是对的）。
- 判据加一条（4e 块里）：**"流水里带 体Nms"**，跑出来 **合计 58 条：PASS 58 / FAIL 0**，Windows 与机上
  交付物自身两边都是 58（上一轮那个"62"的来历与口径见 14.16 原地的改口）。

**产物与落位**：`scripts/dsh-entry.js` 69,556 → **70,487 B**，机上 `chroot:/usr/local/bin/dsh-entry.js`
md5 `4af378c95d0bab8a9bf0681e50095cc1`（与 `/data/local/tmp` 暂存件相同 ⇒ 推上去没走样）；
`--entry-stop` → `[ok] :3081 已关闭` + `[ok] :3080 已关闭（等了 1s）` → `--entry` → 入口 pid=17611、
引擎 pid=17637、`auth cookie 有，已用 7 秒`、`req=15 ws=0 最后错误（无）`。**他的页面这次也要重进一次**
才吃到这一版。**清理**：`/data/local/tmp/{dsh-slow-probe.sh,dsh-entry.js}` 与 chroot 里那份探针脚本跑完当场删，
复点时前两条 `No such file or directory`（chroot 那条从外面 `ls` 会被 SELinux 拦成 Permission denied，
所以是进 chroot 里 `ls` 复点的：`cannot access '/root/dsh-slow-probe.sh': No such file or directory`）。
他自己那堆 `/data/local/tmp` 文件一个字节没碰。**零出网**（探针只打 127.0.0.1:3081），没动凭据/会话/档位/自启开关。

**还欠着的**：14.16 那两条（点一次**插件**、按一次**返回键**）照旧；那 160ms/4ms 的静态资源差照旧；
**SSE/WS 背压**照旧没做。本轮没修任何东西，做的是**把"修哪个"变成下次一读就能定的事**——
甲乙两种故事对应的修法相反，在没分开之前动手就是猜。

---

### 14.18 他提的三件手感事：全屏、返回键要问一句、重进之后那 37 秒黑屏（2026-10-20 深夜，壳 0.4）

他那一段话里其实有四个东西，我按"有没有读数"分开记：

**① 先答他那句"旁边那一列按钮是不是 DeepSeek Harness 里面的"** —— 是，而且这次不是我看着截图猜的：
用 `scripts/dsh-cdp.js --eval` 直接问页面 DOM，把最左边 160 px 里所有可点元素的 `aria-label` 读回来：
`打开侧边栏 / 新建会话 / 全局面板 / 插件 / 自动化任务 / 添加工作区 / 搜索会话 / 账号菜单`，
外加输入框那一排的 `添加文件或调用指令`、`访问模式，当前：工作区内修改`、`1 轮 1 步 · 264 tok/s`。
**这些全是页面自己的按钮**（DeepSeek Harness 前端），我这个壳在屏幕上没有任何自己的东西 ——
壳只画了两样：窗口底色和那屏"连不上工作台"的说明页。所以他要改按钮的位置/含义，得改前端或者做遮罩，
不是在我这层能改的。（顺带读出他此刻的档位是**工作区内修改**，不是 `danger-full-access`。）

**② "打开之后顶部状态栏还显示着，我要它隐藏"** —— 做了，并且**拍屏验过**：
`downloads/dsh-shot-04-fullscreen.png`（304,540 B）里状态栏（时间/5G/电量）整条不见了，页面从屏幕最顶上开始画，
底部那条手势横条也收了（滑一下会临时露出、一两秒自己收回去 —— 选的是 `BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE`，
不是永久藏死，因为他还得看电量和时间）。
实现走运行时 `WindowInsetsController.hide(systemBars())`（API 30+），**没用** manifest 里那条
`windowFullscreen`：它管不到导航栏，而且在 targetSdk 35 上那套旧窗口旗标不保证生效。
`onResume` 里再调一次，从通知栏或别的 App 回来时状态栏不会赖着不走。
日志里对应 `21:46:15.615 fullscreen :: 已请求隐藏状态栏+导航栏（API 30+ 控制器，边缘滑出临时显示）`。

**③ "返回键应该先退回聊天界面，在聊天界面上再按要弹一个确认，第三次才真的回桌面"** —— 代码按这三层写了
（`MainActivity.handleBack()`），但**这一条我今天没有读数**，原因见 ⑤。
0.3 里只有第 1 层（`canGoBack` 就在 WebView 里退），所以他从首页侧滑一下就直接掉回桌面 —— 他那条反馈本身就是
0.3 的行为读数，也顺手把 14.15 挂着的那条推断解开了：**返回这一发确实到得了 Activity**（不是被预测式返回吞掉），
只是我们那时候没有"问一下"这一层。
两个入口（`onKeyDown(KEYCODE_BACK)` 与 `onBackPressed()`）都接到同一个 `handleBack()`，哪条真被走到由
`shell.log` 里那行 `back ::` 说话；确认屏还开着的时候再按返回 = 他要的"再按一次才退"，点「退出」也退，点「留下」只收屏。
**还有一条要盯的**：第 1 层灵不灵，取决于那个前端在子页面里有没有真的往 history 里 push；
它如果全用 `replaceState`，那"退一层"就会变成"弹确认"。这一条只能他在场点出来，日志会告诉我们走的哪一支。
**→ 这一条 0.5 量出来了，而且比我担心的更彻底：`history.length` 恒为 1，前端根本不往历史里推**，
所以第 1 层不是"有时候不灵"，是**永远不灵**（`location.hash` 也一直是空）。读数与改法见 14.19 ①。
上面那三层的排法他 0.4 装完当场判错（侧边栏摊开盖住主界面时也弹了确认），
那张要点「留下/退出」的确认屏他整体不要了 —— 见 14.19 ②③，0.5 已按他说的重排并换掉。

**④ 那 37 秒黑屏：这一次不是"感觉"，壳的日志把它量出来了**
他说"退出重进之后先黑屏大概 10 秒"。`/sdcard/Android/data/com.zhl.dsh/files/shell.log` 里他那一趟是这样的：

```
21:32:39.217 open-entry   21:32:39.226 cookie accepted=true      ← 这里已经 loadUrl 了
21:33:02.325 open-entry   21:33:02.335 cookie accepted=true      ← 他等得又点了一次图标（onNewIntent）
21:33:16.853 page-start   21:33:18.256 page-finish
```

**从 loadUrl 到 page-start 中间 37.6 秒**（他估的 10 秒是"黑屏到看见东西"，日志这一段比他还长）。
关键是这 37 秒里**服务端应该一条请求都没收到**：`onPageStarted` 就是主框架开始发请求的那一刻（这是它的定义），
而它 21:33:16 才来；入口这边 `GET /` 只要 2ms（同一批资源本轮实测 2–3ms）。**这一步是推理接出来的，
不是我直接量到的** —— 我 21:34 读环的时候里面只有他页面加载之后的那批 API，没有当时的时间戳可对。
但两条加起来指向同一个结论：卡的不是我的入口、不是引擎、不是网络，是 **WebView 内部"按下到真的开始导航"那一段**。
同一段路 21:40:22 我干净冷启再量一次：`cookie 22.079 → page-start 22.119（40ms）→ page-finish 22.670（639ms）`，
0.4 装完 21:46:15 又量一次：`83ms / 657ms`。**两次快、一次 37 秒 ⇒ 这是偶发，不是每次都慢**，
所以我没有"修好它"的资格，只有"下次它再犯我能看出来"的资格。0.4 为此做了三件事：
① `onCreate/onPause/onResume/onDestroy` 全打进日志（0.3 只有 6 个事件，看不出Activity 换实例的顺序）；
② 一个**看门狗**：`loadUrl` 之后 5 秒还没等到 `onPageStarted` 就自己重试一次（最多两次，重试前清一次缓存），
每一次都记 `stall ::` 那一行 —— 把"黑着不动"变成"最多黑 5 秒然后自己再来"；
③ 把 0.3 里那句 `web.pauseTimers()` 删了。它是**整个进程**级的"把所有 WebView 的 JS 定时器冻住"，
而退出重进这条路上 Activity 会换实例，旧实例的 `onPause` 完全可能排到新实例 `onResume` 之后 —— 那一冻就没人解冻了。
**这条是嫌疑不是结论**：删掉它的代价只是后台省电少一点，收益是少一个能冻住整页的开关。
（顺便：`ACCESS_NETWORK_STATE` 那条权限我没加。网上有"WebView 首次导航等网络句柄"的说法，
但我这两次干净冷启 40–83ms 就说明不缺它，为一个没复现的猜测加权限不做。）

**⑤ 我自己这次测试失手，记下来当判据**：0.4 装完我发 `input keyevent 4` 想验返回键，
日志只打到 `21:46:51 onPause`，我差点读成"返回键把 App 退了、我写的三层没生效"。
截屏拉回来一看是**锁屏 AOD**（星期二 9:46、75%、那个螺旋）——手机在 21:47:02 前后 `DOZE → OFF` 睡了，
那一发 KEYCODE_BACK 打在锁屏上，根本没进我们的 Activity。**结论：给手机发输入事件之前必须先读 `mWakefulness`**，
`dsh-cdp.js` 早就这么要求自己（不是 Awake 直接拒绝跑），我这次用裸 adb 命令把这条规矩绕过去了。
所以 ③ 那条**仍然欠他一次真按**，而"返回键到得了 Activity"这条读数来自他自己的描述，不是我的实验。

**产物与落位**：`app/src/com/zhl/dsh/MainActivity.java` 34,647 → **42,773 B**（模板，展开进包 42,804 B），
`app/AndroidManifest.xml` versionCode **4** / versionName **0.4**（那段"事实与推断分开"的注释按他新读数重写了），
`app/build.sh` VER_CODE=4 VER_NAME=0.4。成品 `app/out/dsh-app.apk` **86,632 B**、
sha256 `b20c6ddfa38d53b4baa9bbcd4a01fa286707358224a9764f168ce467e632945c`，
机上 `/data/app/…/com.zhl.dsh-…/base.apk` 逐字节同一串，`dumpsys package` 读到 `versionCode=4 targetSdk=35`。
装机是 `-r` 覆盖装（同一把自签 key，不用卸载），**他原来那个 16 MB 对照客户端没动**。
截图两张：`downloads/dsh-shot-now.png`（0.3 时他那一屏，状态栏还在）、
`downloads/dsh-shot-04-fullscreen.png`（0.4，状态栏与导航栏都收掉了）。
**零出网**（CDP 走 adb forward、探针只打 127.0.0.1），没动他的凭据/会话/档位/自启开关，
`/data/local/tmp` 下他自己那堆一个字节没碰；我这次建的暂存截屏文件当场删并复点。

---

### 14.19 返回键那两层他要我换个顺序，那张确认屏他不要了（2026-10-20 深夜，壳 0.5）

他 0.4 装完试了一下，回了两句话，两句都是"你理解错了"：

> "我现在点开那个插件这个页面，然后它左边的那个侧边栏不就覆盖到整个的主界面了吗？那这个时候我点返回的话，
> 它会弹出那个是否要退出工作台的确认。……我要的是这个时候，比如说左边的侧边栏占据全屏的时候，我点一下返回，
> 它会先返回到我的聊天界面。"
>
> "你现在做的这个退出工作台的弹窗啊，太丑了，而且字体整小一点。……或者你不要搞这种，它弹出来之后需要我点
> 留下、退出的这样的。就是像那种其他的软件一样，我点一下返回，它会有一个隐性的弹窗出来，比如说再点一下返回退出，
> 然后过个 1 秒它就隐下去……不用我去点。"

**① 为什么 0.4 会在侧边栏摊开时也弹确认 —— 一条读数就把这件事说完了**

`node scripts/dsh-cdp.js --eval "history.length"` → **1**（URL `http://127.0.0.1:3081/`、`location.hash` 空）。
这一版前端是单页应用，切视图、摊侧边栏**都不往浏览器历史里推条目**，所以 0.4 那句
`if (web.canGoBack())` 在他的页面上永远走不进去，返回键直接从"页面能退一层"跳到"弹确认"。
0.4 那节的注释里我写的是"① 页面里还能后退就先在页面里退一层"，把这条当成了活的第一层 ——
**它是条死层**，这是我的设计错，不是他按错了。

**② "侧边栏摊开"这件事，壳在 Java 这边看不见，只有页面知道**

壳能拿到的读数只有 WebView 的 URL 和 `canGoBack()`，两样都不动。所以只能问页面。
量法：`--click 'button[aria-label=打开侧边栏]'` 前后各读一次列宽和可见按钮（屏宽 360 CSS px）：

| 状态 | `div[class*=sidebarCol]` 宽 | 看得见的 `aria-label`（全页面只有这些） |
| --- | --- | --- |
| 收起 | 56 px | `打开侧边栏` |
| 摊开 | **280 px（占屏宽 78%）** | `收起侧边栏`（在 x=240 y=22，28×28） |

摊开那一屏我截了 `downloads/dsh-shot-05-sidebar-expanded.png`（258,080 B）——聊天被挤到右边一条，
跟他描述的"覆盖到整个主界面"是同一件事。
**关键坑：这两颗按钮在 DOM 里两种状态下都存在**（收起时"收起侧边栏"那个节点也在，只是不可见），
只按 `aria-label` 找会在根本没摊开时也"关"一把。所以判据是**看得见的那颗**：
`getBoundingClientRect()` 宽高都 > 2 且 `visibility!=='hidden' && display!=='none'`。
壳里那段 `OVERLAY_JS` 就干这一件事：按 `退出全屏 → 收起右侧边栏 → 收起侧边栏` 的次序找看得见的第一颗，
点它、把它的名字回给 Java；都没有就回 `none`。
**这条判据当场正反各验一次**：收起时跑 → 回 `none`、什么都不点；摊开时跑 → 回 `收起侧边栏`、列宽 280 → 56。

**③ 那枚浮层（`askExit()` 整段删了，AlertDialog 不再 import）**

`TextView` + `GradientDrawable`（圆角 21dp、底色 `#E620262F` 九成不透明、描边 1dp `#2EFFFFFF`、
内边距 20×11dp、15sp 白字"再按一次返回，退出工作台"），淡入 120 ms、停 1500 ms、淡出 300 ms，
"算第二下"的窗口取 1800 ms（比淡出结束稍长一点：淡出到一半再按也算退，那时候人早看清那行字了）。
`setContentView(web)` 改成外面套一层 `FrameLayout`，浮层加在这层上、不加进页面 DOM（页面一重绘就没了，
而且那是前端的地盘）。
**字号那格是选择不是读数**：14sp/20sp 那两档是平台 AlertDialog 的默认值，我按主题说的，
没在这台机上量过他嫌小的到底是哪一行。
**位置改过一次**：第一版离底 96dp，装上截图（`downloads/dsh-shot-05-hint.png`）正好压在输入框那半截上，
改成 40dp 落到框下面（`dsh-shot-05-hint2.png`）。这两次都是**眼睛看截图定的**，没有几何读数支撑。

**④ 机上真按的读数（这一轮每次都先读 `mWakefulness=Awake` 再发 `input keyevent`，照 14.18 立的规矩）**

| 时刻 | 按法 | 壳日志 / 屏幕上看到的 |
| --- | --- | --- |
| 22:15:01.888 | 侧边栏收起，按一下 | `没有盖着的层、历史也退不动 ⇒ 飘退出提示`，`mCurrentFocus` 还是 `com.zhl.dsh` |
| 22:15:35.524 / 36.133 | 隔 609 ms 按两下 | 第二下 → `提示还飘着又按了一次返回 ⇒ 退出`，`onPause` 36.153、`onDestroy` 36.953，焦点交回 `com.android.launcher` |
| 22:19:41.976 | 侧边栏摊开（280 px），按一下 | `「收起侧边栏」这一层开着 ⇒ 已在页面里替关掉`，列宽 280 → **56**，焦点没走、**没有飘提示** |
| 22:18:38 / 22:18:44 | 提示飘出后等 3 秒 | 两张截屏逐像素差只有一块 1004×178 的区（就是那枚浮层）⇒ **它自己消散了**，不用我点 |

**⑤ 有一件他要的事我这次没做，因为页面不给路（不是我省了）**

他说"最终退回是退回到聊天界面"。但**点开 `插件` 之后侧边栏并不摊开**（实测列宽仍是 56，主视图换成
`插件 / 内置插件配置 / 实验性插件`，输入框那颗 `描述你想要构建的内容…` 从可见集合里消失），
而从这个页面回到聊天，页面上只有两条路：`新建会话`（**会真建一个会话**）或摊开侧边栏点某一条会话
（**会换掉他当前开着的那条**）。再按一次 `插件` 不会切回去（实测），发 `Escape` 也不会（实测）。
所以 0.5 只做到"摊开的那一层先收掉"，**没有**做"从插件页返回到聊天"。
要做就得接受那两条副作用之一，这条等他点头再动。

**⑥ 没验到的几处，写清楚**

`退出全屏` 与 `收起右侧边栏` 这两颗我只在 DOM 里见过它们存在，**没造出过它们可见的状态**，
所以那两条分支是照左边侧边栏同一个形状写的、无读数；
`evaluateJavascript` 800 ms 不回音那条兜底**这轮一次都没触发过**（回调实测都在 1 ms 内回来）；
浮层"不吃点击"是按 Android 的触摸分发规则写的（没给 `TextView` 设 clickable，事件会落到下面那个子 View），
**我没有真在提示飘着的那 1.8 秒里往输入框上点一下验**；最坏情况也就是这 1.8 秒点不动，不会留下什么。

**⑦ 收尾时顺手多出来的一条读数**（本来差点被我读成"入口挂了"）

装完机我 `su -c curl http://127.0.0.1:3081/__entry_status` 拿到 **`Not Found`**，这形状跟"入口死了"一模一样。
两种解释分不开：甲=入口按设计对不带口令的请求一律 404（不是 403，它不让人知道自己敲对了门）；乙=真挂了。
于是新写了一条只读探针 `scripts/dsh-entry-status.sh`（**同一条路各问一遍**，口令只从
`/root/.dsh/entry.key` 读进变量、经 stdin 交给 `curl -K -`，不进 argv、不进输出），跑出来：
**甲 404 字节=10 耗时=1.2ms / 乙 出完整自述**（`engine running pid=17637`、`auth cookie 有，已用 3649 秒`、
`内联位置 order=ok`）⇒ 是甲，**入口与引擎这一整轮没重启过也没坏**（`ss -ltnp` 也读到 3080/3081 两行 LISTEN、
pid 与 22:0x 那轮同一对）。
乙那屏还白捡一条：流水里 `POST /api/account/getBalance → 200 300ms App 体0ms`、`getProfile → 200 236ms 体0ms`
—— **`体` 那一列开始干活了**，这两条的 300/236 ms 全在引擎那侧（客户端 0 ms 就把手发完了），
不是 14.17 担心的"WebView 冻结"那一种。
探针在手机上留的两份副本（`/data/local/tmp/` 与 chroot `/root/`）跑完当场 `rm` 并复点为不存在。

**产物与落位**：`app/src/com/zhl/dsh/MainActivity.java` 42,773 → **52,266 B**（模板，展开进包 52,297 B；
本轮末尾又加了位置改注与注释，模板现 52,423 B），`app/AndroidManifest.xml` versionCode **5** /
versionName **0.5**，`app/build.sh` VER_CODE=5 VER_NAME=0.5。
成品 `app/out/dsh-app.apk` **90,729 B**，**装了两发同版本号**：
先 `sha256 d5432fa67c826301836ae2447dbe578dc186a1ebf1b717926bcde355884aa953`（浮层离底 96dp 那发，
就是上表 22:15 三条读数的对象），后 `sha256 251282084c113dcc7888cb2093eb407bd7623e6df1edb9e0dc3d1158fa3d5ce5`
（改成 40dp 那发，**他手机上现在装的是这一发**，上表 22:18/22:19 三条读数的对象）。
两发 `dumpsys package` 都只读到 `versionName=0.5` ⇒ **版本号区分不了这两发，只有 sha 能**，
所以以后别拿 versionName 当"装的是哪一发"的证据。
**这条当场又长了一截**：为了核"装的这发跟盘上源码是不是同一版"，我拿**没再改过一个字的同一份源码**重打了第三遍，
出来 **90,729 B 一模一样、sha 却是 `09920b6af77f7c3ab035478c22e73897783d4add861c26728139e4e1469532ca`**
（模板 52,423 B → 展开 52,454 B，与装机那发同一份代码）⇒ **这套打包不是逐字节可复现的**（签名或 zip 时间戳里
带了会变的东西），所以 **sha 认的是"哪一次打包"，不是"哪一版代码"**：sha 相同可以证明代码没变，
sha 不同**不能**证明代码变了。盘上 `app/out/dsh-app.apk` 现在是第三遍那发，**他手机上装的是 `25128208…` 那一发**，
代码相同、字节不同。装机走 `-r` 覆盖装，入口(:3081)与引擎(:3080)没重启过，
他那个 16 MB 对照客户端没动，`/data/local/tmp` 下他自己那堆一个字节没碰（截屏全用 `exec-out` 直接拉回 Windows，
手机上没落临时件），**零出网**。

### 14.20 他让我先去看那两个已克隆的项目怎么做手机适配，看完再动手（2026-10-20 深夜，壳 0.6 + 选择器补入口 + 语音那条查到底）

**① 先例读完的形状（这一节的东西全是照这两条先例来的，出处都给到行）**

两份先例给的是**两条不同的语音路**，不是一条：

- 甲：native 侧自己 `AudioRecord` 录音 + 自己的识别 + `evaluateJavascript` 把文字塞回页面 —— `Deepseek-Harness-Local-Android-main` 那套 Kotlin 壳走这条；
- 乙：**放行页面自己发的 `getUserMedia`** —— DSHA 走这条：`WebChromeClient.onPermissionRequest` 里把 `RESOURCE_AUDIO_CAPTURE` grant 回页面，
  放行条件收在三处（`MicrophonePolicy.java:9-36` 判来源与"要的是不是只有麦克风"、`WebViewMicrophone.java:1-70` 发系统权限申请并把结果交回 request、
  `AndroidManifest.xml:6-9` 声明 `RECORD_AUDIO` / `MODIFY_AUDIO_SETTINGS` / `uses-feature microphone required=false`）。

**我选乙**。理由不是"乙更高级"，是引擎侧那套语音插件本来就是按"浏览器给我音频流"设计的
（`…-api-speech-to-text` 的自述是"为浏览器提供录音转写接口"），走甲就得先把页面那套绕过去，两边都要改。

存储入口那条先例也读到了：`RuntimeExecution.java:102-108` 在每次 ensurePatches 时往 rootfs 的 `/root` 建一条名为**「手机存储」的软链**指向 `/sdcard`，
建失败只记一个 `OPTIONAL_STORAGE_LINK_UNAVAILABLE`，不阻断启动。③ 就是照这个形状补的。

**② 壳 0.6：麦克风这条链，装在他手机上、真按通了**

改动只有两个文件。`app/AndroidManifest.xml` 加 `RECORD_AUDIO`、`MODIFY_AUDIO_SETTINGS`、`uses-feature(microphone, required=false)`（3,991 B，versionCode **6** / versionName **0.6**）；
`app/src/com/zhl/dsh/MainActivity.java` 52,423 → **62,414 B**（模板；展开进包 62,445 B），加的是 `onPermissionRequest` → `requestMic()` 那条链：
先四道闸（有 pending 就拒 / 没 origin 就拒 / 要的不止麦克风就拒 / 来源不在放行范围就拒）+ 第五道过期闸（`micRev` 与当前文档对不上就拒，防止上一发的请求在新页面上被放行），
过了闸才去 `requestPermissions(RECORD_AUDIO)`，拿到结果再 `finishMic()` 单次闩（`micAnswered`）后 `grant(RESOURCE_AUDIO_CAPTURE)` —— **只交这一项**，
grant 那一步包了 `catch(RuntimeException)`，抛了就退成 deny，不留一个"页面以为有麦其实没麦"的中间态。
`micTrusted()` 收得比先例还紧：只放 http、不许带 userinfo、端口必须 1-65535、host 必须正好是 `127.0.0.1`/`localhost`，且 origin 必须等于入口自己那条。

真机读数（`shell.log` 六行，时间戳原样）：

```
23:07:18.146 mic :: 拒绝 ｜ 原因：要的不只是麦克风（android.webkit.resource.VIDEO_CAPTURE）
23:07:58.231 mic :: 系统层还没有 RECORD_AUDIO ⇒ 弹给用户（他点了录音插件才会走到这一步）
23:08:01.476 mic :: 系统那一层的结果=允许
23:08:01.477 mic :: 已把麦克风交回页面（只交 AUDIO_CAPTURE 这一项）
23:09:00.938 mic :: 系统权限本来就有 ⇒ 直接把这一发放行给页面
23:09:00.939 mic :: 已把麦克风交回页面（只交 AUDIO_CAPTURE 这一项）
```

页侧同刻读到 `kind=audio state=live muted=false label=[]`（轨道真开起来了，录完立刻停）。`dumpsys package` 那侧 `RECORD_AUDIO: granted=true, flags=[USER_SET|…]`
⇒ 是他在系统弹窗上点的允许，不是我替他点的（**这条我必须写清楚**）。第一行那条"要的不只是麦克风"是**放行了摄像头会出事**那一条闸门的实弹证据。

**没验的东西**：`MODIFY_AUDIO_SETTINGS` 缺了会被 Chromium 拒这一条是从 DSHA 的 `docs/releases/v0.1.7-rc2-apk-size.md:30`（vivo V2463A / Android 16 / WebView 150）
**转述**来的，我在这台 PJZ110 上**没单独验过**（验它要故意拆权限再重装，这轮没做）。manifest 的注释里也是这么标的。

**③ 选择器那一屏为什么是空的：成因、修法、修后读数**

成因是引擎自己的回答给的，不是我猜的。`directoryPicker/list` 不带 path 那一发列的是**引擎进程的 HOME**，这轮修之前那一发是：

```
{"path":"/root","home":"/root","entries":[{"name":".dsh","hidden":true},{"name":".npm","hidden":true}]}
```

两条都 `hidden:true` ⇒ 界面渲染出来就是**空的一屏**。他的真实文件夹在 `/phone`（bind 自 `/data/media/0`），
从 `/` 出发是点得到的，问题是那一屏的起点在 `/root`，一步都走不动。这一条不是"没连 API"、不是 403、不是接口挂了。

修法就一条软链（照 ① 那条先例）：`scripts/dsh-chroot.sh` 新增 `home_entry_ensure()`（`:135-147`），在建好 `/phone` 挂载之后往 `/root` 建 `手机存储 -> /phone`，
挂在 `--web`(`:244`)、`--entry`(`:281`)、`--run`(`:373`) 三条路径的 `mount_fs` 后面；`DSH_NO_PHONE=1` 时自动跳过；建失败只打一行 `!!`，不影响服务起来。
选软链不选再 bind 一次的理由也是读了盘：选择器**跟软链**（`path=/lib` 那发能正常列出 `usr/lib` 的内容），所以一条链就够，删起来就是一个 `rm`。

修完的真读数（`scripts/dsh-voice-picker-probe13.sh`，推上机上 3,001 B、零 CR、跑完即删）：

| 那一发问的是什么 | 引擎原样回答（截） |
| --- | --- |
| 不带 path（= 那一屏打开时看到的） | `entries` 三条：`.dsh`(hidden:true)、`.npm`(hidden:true)、**`手机存储`(hidden:false)**，`crumbs` 给到 `/` → `root` |
| `path=/root/手机存储`（顺着链进去） | `path":"/root/手机存储"`，`entries` 从 `.aaa`/`.android`/`.DataStorage`… 开始，点得到的都在 |
| `path=/root/手机存储/Download` | 再进一层照样列得出，`crumbs` 变成 `/` → `root` → `手机存储` → `Download` |

**这一条验到的是"引擎那一发返回里有这一条、且标着非隐藏"**，界面上那一行他点不点得动还得他自己开一次 App 才算闭环（这轮他没在手机上，我没替他点）。
零改动的备用路径也还在：在那一屏点面包屑里的 `/`，再点 `phone`。

**④ 语音那条：这台机跑不跑得起、要不要下模型、模型下得下不动 —— 全读到源码那一层**

他问的是"在手机上用难道不应该直接拿麦克风就输入吗，还要下载那个模型吗"。这轮把这句话拆成三个能回答的问题，三个都有盘上读数了。

**(a) 手机侧能不能跑这个识别：能。** 包在 dsh 自己的 `node_modules` 里（宿主路径 `/data/local/dsh-rootfs/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/`，
四个语音包都在位：`dsh-experimental-api-speech-to-text`、`…-client-ui-voice-input`、`…-speech-to-text`、`…-speech-to-text-sensevoice`，另有 `…-voice-input-bundle`）。
它的硬闸门是 `lib/index.js:202-207` 那张平台表白名单：`darwin-arm64 darwin-x64 linux-arm64 linux-x64 win32-x64`，判的是 `${process.platform}-${process.arch}`。
我们 chroot 里跑的是 Ubuntu arm64 的 node ⇒ `linux-arm64`，**在白名单内**。再一条：`sherpa-onnx-node@1.13.8` 和 **`sherpa-onnx-linux-arm64` 两份都已装**（同一层 `node_modules` 里 find 到）。
⇒ 所以"手机上不能跑本地识别"这个假设是**错的**，拦路的不是 CPU 也不是 ABI。

**(b) 它要的是什么：三个文件，字节数写在包里，不是估计。** `runtime/assets.json`（1,242 B）原样：

| 项 | 文件名 | 字节 | 来源（固定 revision） |
| --- | --- | --- | --- |
| int8（默认 precision） | `model.int8.onnx` | **239,233,841** | `huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/2365bae…` |
| fp32（可选，"较大的参考权重"） | `model.onnx` | 937,617,178 | 同上 repo |
| 词表 | `tokens.txt` | 315,894 | 同上 repo |
| VAD | `silero_vad.onnx` | 1,807,522 | `huggingface.co/csukuangfj/vad/resolve/fba88cd…` |

⇒ 默认那条路要 **int8 + tokens + VAD ≈ 241 MB**（`/data` 这卷 935 G、可用 341 G，空间不是问题）。
下载完它自己按 `bytes` 与 `sha256` 双校验（`lib/index.js:270-312`：多一个字节就 `reason:"integrity"` 抛掉，`completedBytes !== asset.bytes || digest !== sha256` 也抛），
落点是 `modelRoot = config.modelDirectory ?? join(config.dataRoot, "models", "sensevoice-onnx")` —— 也就是这台机上的
`/root/.dsh/speech-to-text/sensevoice/models/sensevoice-onnx`（`modelDirectory`/`vadModelPath` 也允许直接指现成目录，README.zh 里"显式部署路径只检查可访问性，文件内容由部署者负责"）。

**(c) 那四层目录里有没有字节：没有，一个文件都没有。** `find` 只出四个 `d`（`speech-to-text` → `sensevoice` → `models` → `sensevoice-onnx`，各 3,452 B 是目录项本身），
`-type f` 那一段一条没出。⇒ 上一轮挂着的"里面到底有没有模型"这条现在有答案了：**零字节**。
顺带一个口径纠正：同轮 `du -sk` 报 **14 KB**，那 14 KB 是四个目录的 inode 空间，**不是模型碎片**，别读成"下了 14 KB"。

**(d) 为什么他点下载会挂住：两个默认源在这台机上都是死的，而且死法不一样。**
包里的默认源是 `.default(["https://huggingface.co", "https://hf-mirror.com"])`（`lib/index.js` 里 zod 那句，可配置）。这台机上的实测：

- `/etc/hosts` 28 行、`huggingface`/`hf-` 打头的 **0 行**（没钉过）；`/etc/nsswitch.conf` 是 `hosts: files dns` ⇒ 这两个名字走 DNS。
- `getent hosts huggingface.co` 首选给的是 `2001::343a:1a1`，`cdn-lfs.huggingface.co` 给 `2a03:2880:f12c:83:face:b00c:0:25de`（脸书段的形状），
  而 `ip -6 route` **一行都没有** ⇒ 拿到的是不可用的地址。`getent ahostsv4` 那边到 `108.160.167.148`，强制 `curl -4` HEAD 仍然 `Connection timed out`。
- `hf-mirror.com` 连解析都不给：`Could not resolve host`（13 那一发是 `Resolving timed out`）。
- 对照位：`api.deepseek.com` 在 `/etc/hosts` 里钉过（`39.174.179.5`），HEAD 直接 `http=401`，170 ms 完成 ⇒ **这台机出网本身是通的**，死的是这两台模型站。

**这里要改一句旧话**：之前我写过"这台机 53 端口出站被拦，所以靠 `/etc/hosts` 钉 IP"。那句的测法是 `/dev/tcp/223.5.5.5/53`，那是 **TCP** 53。
本轮 `getent` 明明拿到了答案（虽然是被污染的答案），说明 **UDP 53 是通的**。准确说法是：**TCP 53 不通、UDP 53 通但答案不可信**，
所以钉 hosts 仍然必要，但"解析不了"和"解析错"是两件事，以后别混着报。

**(e) 电脑这侧对照（本轮唯一另一次出网）**：同一批 URL 从 Windows HEAD 一发 —— `huggingface.co` → `http=000`（0.15 s 就断），
`hf-mirror.com` → **`http=200`**，跟着重定向落到 `cas-bridge.xethub.hf.co`。⇒ 镜像从他电脑上是通的。

**(f) 所以给他的答案是两半分开的**：**手机侧那半已经通了**（② 那六行），拿到麦克风、页面能开录音轨道，这条不需要任何模型；
**引擎侧那半现在下不动**，而且是"下不动"不是"不该下"。既然电脑上镜像通、包又支持"校验现成目录"，那就不必让手机去联那两台站：
**在 Windows 上按 `assets.json` 那几个固定 URL 下三个文件、本地算 sha256 对上、再 `adb push` 进 `sensevoice-onnx` 那层目录**，
插件"每次启用都会检查磁盘上的所选模型、词表与 VAD，缓存完整且校验通过后立即恢复就绪"（README.zh 原话），手机全程零出网。
**这 241 MB 我没动** —— 他没说下，我就不下（这是他的红线，也是我的）。

**⑤ 出网计量（这一轮全部）**：chroot 内 3 发 HEAD（`api.deepseek.com` 401 / `huggingface.co` 超时 / `hf-mirror.com` 超时，body 全 0 字节）+ Windows 侧 2 发 HEAD（同一批 URL）。
**没有任何模型字节落盘**，没有 clone、没有 npm install。除 HEAD 之外零请求。

**⑥ 竖屏/横屏这件事：不用改代码**

`app/AndroidManifest.xml` 里**根本没有 `screenOrientation` 这一条**（这轮又 grep 过一遍），`configChanges` 里带着 `orientation|screenSize|screenLayout`
⇒ 方向本来就跟着传感器走，他看到的那个横屏是传感器给的，不是我钉的。系统那边 `accelerometer_rotation=1`。
**但先例提醒了一件我还没量的事**：DSHA 那套里真做的手感活不是"允许转"，是**竖屏时桌面那套布局在 360 CSS px 上会散**，它用 `narrow-sidebar`/`narrow-rightbar`
两套 class 收（列宽夹在 264-420、中栏最小 400 px、视口 <768 就整宽）。**这套在我们这台机上没量过**，所以"竖着拿会不会一屏挤成一团"这条还是待办，不是已解决。

**⑦ root 那件事自己好了（上一轮的读数这条要挂个箭头）**

上一轮记的是"`su` 给的 uid 是 0 但域还是 `shell:s0`，写不进 chroot"。这轮复测同一条命令：`su -c "id"` → `uid=0(root) … context=u:r:su:s0`，
`su -c "cat /proc/self/attr/current"` → `u:r:su:s0`，`--status` 六样读数全拿到 ⇒ 能用。**成因没定位**（推断：KernelSU 那侧的授权被回收后又生效了，
可能是他重开过 App 或授权到期；这条是**推断，没证据**）。上一轮那句"探针副本已删"也在这轮改口：那句是拿 `test -e` 测的，而 `test -e` 在 EACCES 下**返回 false**，
所以当时其实是"看不见"不是"没了"。这轮真数出来是 **9 份**（`p.sh p2.sh p3.sh p4.sh p5.sh p6.sh` + 本轮新推的 `p13.sh p14.sh p15.sh`），
逐条 `rm` 之后复点 `ls | grep -cE '^p[0-9]*\.sh$'` = **0**。`/data/local/tmp` 下我自己的暂存件（`.dshdeploy.*`）复点 = **0**，他那堆还是一个字节没碰。

**产物与落位**：`app/AndroidManifest.xml` 3,991 B（0.6）、`app/src/com/zhl/dsh/MainActivity.java` 模板 62,414 B、`app/build.sh` VER_CODE=6 / VER_NAME=0.6，
`scripts/dsh-chroot.sh` 20,763 → **23,047 B**（已部署，机上复点同字节）。成品 `app/out/dsh-app.apk` **90,729 B**，
sha256 `12ddf7e3abd7b4d9c704a4bb2eb980023ee299d0bf50f08bfa2727f0bbc2a10a`，dex 38,100 B —— **字节数和 0.5 那两发一模一样**，
这是 14.19 立的那条"别拿字节数认产物"自己又验了一遍，认这一发只能拿 sha 和 `dumpsys` 的 `versionName=0.6`。
本轮新探针（只读，全 `bash -n` 过、零 CR）：`scripts/dsh-voice-picker-probe13.sh` 3,001 B、`…probe14.sh` 3,055 B、`…probe15.sh` 3,557 B，
机上读数留在 `downloads/p13.txt` / `p14.txt` / `p15.txt`；插件清单那份 82,792 B 仍在 `downloads/probe-p9-plugins.json`。
服务没重启：入口 pid 17611、引擎 pid 17637，跑 `--entry` 前后同一对（那发只走到 `[skip] :3081 已在听`）。
**这轮没做的**：没点过 App 上那行「手机存储」（要他人工闭环）、没触发模型下载、没验 `MODIFY_AUDIO_SETTINGS` 缺了会怎样、
没量竖屏布局、没动他的 KernelSU 配置、没提交 git。
