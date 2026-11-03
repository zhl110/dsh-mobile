# dsh-mobile

把 DeepSeek Harness（`@deepseek-ai/dsh` 0.2.1-rc.2）**完整跑在手机本机**：一个真 chroot 的 Ubuntu 24.04 arm64，推理走联网调 API，用法像桌面应用——桌面图标点开就能用、能关掉、能挂后台。

这个仓里是**源码 + 脚本 + 全过程记录**；那棵 GB 级的 rootfs 不在仓里（git 存不了属主与 setuid 位，单文件也有 100 MB 硬限），它挂在 **[Releases](https://github.com/zhl110/dsh-mobile/releases)** 上。

## 三层结构

```
壳 App com.zhl.dsh（Android，自己的窗口，不走浏览器）
   ↓ http://127.0.0.1:3081/
常驻入口 scripts/dsh-entry.js（换 30 天 cookie · 兼容层出口内联 · 门禁口令）
   ↓ http://127.0.0.1:3080/
引擎 chroot 里的 dsh web（真页面与 RPC）
```

服务只绑 `127.0.0.1`；不做端口转发，局域网里摸不到。

## 要什么机器

已 root 的 **arm64** 安卓机（本机现役那台是 Android 15 + KernelSU；真 chroot 要靠 root 进，没 root 起不来）。`payload-meta.txt` 量到解压后 **2,633,803,541 B ≈ 2.6 GB**，加上下载那发 901 MB 的包，`/data/local` 下**建议留 3.5 GB**。PC 侧要 **adb** 与 **git-bash**（脚本按 Windows + MSYS 的坑都写死了绕法）。

## 装（给别人的一键路径）

```bash
git clone https://github.com/zhl110/dsh-mobile.git && cd dsh-mobile
gh release download payload-20261103-132346Z -R zhl110/dsh-mobile -p '*.tar.gz'   # 库是公开的，不登录也能下
gh release download payload-20261103-132346Z -R zhl110/dsh-mobile -p 'payload-meta.txt'
bash tools/install-from-scratch.sh        # 取包 → 校 sha → 设备上以 root 解压 → 推四件 → 起入口 → 造口令 → 装 APK
```

细节与前置体检在 **[docs/INSTALL-from-scratch.md](docs/INSTALL-from-scratch.md)**。包的体积、sha256、条目数、剥除口径以随包的 **`payload-meta.txt`** 为单一真源，本文件不抄第二份。

**说句实话**：`tools/install-from-scratch.sh` **没有在干净机上实机跑过**（作者手上只有那台现役机）。所以"装完能用"目前只有设计证据与两道泄露闸门的本机自测，**没有实测读数**。跑通的人欢迎开个 Issue。

## 包里有 / 明确没有

含：Ubuntu 24.04 arm64 整棵运行时（`/usr` 里的 Node 与 npm 全局那棵树、dsh 0.2.1-rc.2 及其插件）、`dpkg -l` 那 428 件、离线语音模型、`web` profile 的层栈配置。

不含：**入口口令**（`entry.key`，装机时现场造）、任何 provider 的 **API key**、`/root/.dsh-env` 与它的备份、会话/附件/日志/缓存、`/tmp`、`/phone`、frida、以及 **`/etc/shadow` 原件**——包里发的是一份 root 栏锁掉的替代件，装机脚本第 3b 步放回。剥除清单的单一真源是 [`scripts/dsh-payload-pack.sh`](scripts/dsh-payload-pack.sh) 里的 `DROP` / `DSH_KEEP`。

装完第一件事：在网页里填你自己的 API key。

## 重新造一个包（自己的机器）

```bash
bash scripts/dsh-payload-pack.sh --selftest        # 闸门自测，不需要手机
bash tools/make-payload.sh --publish               # 普查 → 机上 tar -czf → adb pull → 三方复点 → 两道闸门 → 挂 Release
```

这台机的 adb 带不了大二进制流，所以产物必须"设备上落文件 → `adb pull` → 两边各算一遍 sha256"；做法与读数见 [RUNBOOK.md](RUNBOOK.md) 14.40。

## 想改档位 / 加环境变量

`config/dsh-env` 是服务环境模板，部署走 `bash tools/deploy-env.sh --check` 再 `sh tools/deploy-env.sh`；**写完必须重启引擎才吃得进**（`AGENTS.md` 铁律 13 说明了最小的重启是哪一条）。

## 提交之前跑一下这道闸门

```bash
bash tools/check-private.sh --selftest    # 7 条：埋雷要抓到、撤雷要回 0
bash tools/check-private.sh               # 扫跟踪区：本机可识别项与凭证形状
```

仓库是公开的，写进跟踪文件的用户名、家目录路径、设备序列号、邮箱、口令默认值就永久可回看（改历史不算收回去）。这道闸门只报形状名与文件处数，不打印命中的内容；真值名单放在**不入库**的 `tools/private-values.txt` 里。

## 目录

```
app/          Android 壳源码与 build.sh
scripts/      引擎侧：chroot 总入口 / 常驻入口 / 控制台菜单 / 历次只读探针（编号即轮次）
tools/        PC 侧工具：探针包装器、hosts 钉 IP、部署器、打包与发布、装机
config/       服务环境模板
docs/         安装说明与两份对比报告
PROGRESS.md   现在做到哪一步、下一步、遗留问题
RUNBOOK.md    逐轮读数与做法（踩过的坑都在这里）
```
