# 即装即用：把这套东西装到另一台手机上

> 面向对象：拿到这份仓、手上有一台**已 root 的 arm64 Android**、想让 dsh 在手机上跑起来的人。
> 现役那台机（作者本人的）别照这页跑 —— 第 3 步有"目录非空就停"的闸，但那不是给你用的路径。

## 三层是什么

```
壳 App com.zhl.dsh（桌面图标，自己的窗口，不走浏览器）
   ↓ http://127.0.0.1:3081/   常驻入口 dsh-entry.js（门禁口令 + 换 30 天 cookie）
   ↓ http://127.0.0.1:3080/   引擎：真 Ubuntu 24.04 arm64 chroot 里的 dsh web
```

## 大件为什么不在仓里（一句话 + 证据）

`git` 的树对象没有存 uid/gid 的字段，也没有 setuid/setgid 位，设备节点存不了。这棵 rootfs 里实测
root:root 119,474 个、1001:1001 6,194 个、setuid/setgid 17 个（`passwd`/`su`/`mount` 那一族），
整树 4,554,034,779 B（读数：`downloads/p89.txt` 第 1/2/3 节）。checkout 出来属主全变、那两位全丢 ⇒ chroot 里起不来。
**这不是配额问题，是格式装不下**，所以走 tar.gz 产物 + GitHub Release，仓里只放再造它的两支脚本
（`tools/make-payload.sh` 与 `scripts/dsh-payload-pack.sh`）。

## 包里有什么 / 明确没有什么

有：Ubuntu rootfs、Node、`@deepseek-ai/dsh` 本体与它的 web profile 层栈、SenseVoice 与 silero 语音模型（离线能用）、
`/etc/hosts` 里那 29 行 DoH 钉址、purge 的备份目录。

没有（都是故意剥的，清单单一真源在 `scripts/dsh-payload-pack.sh` 的 `DROP` / `DSH_KEEP`）：
入口口令 `entry.key`、`/root/.dsh-env` 与它的所有备份、任何 provider 的 API key、会话记录与附件与 storages 与日志、
npm/apt 缓存、`/tmp`、`/phone`（那是你的手机存储，bind 进来的，不该进包）、还有 frida 那套非交付物。
⇒ **装完第一件事是自己在网页「设置」里填你自己的 key**，不是"缺装"。

## 装（PC 侧一条命令）

```
bash tools/install-from-scratch.sh                 # 本地 release-assets/ 有包就用本地，没有就 gh 拉 Release
bash tools/install-from-scratch.sh <tar.gz 路径或下载 URL>
bash tools/install-from-scratch.sh --skip-app      # 只起 chroot + 入口，不打/不装 APK
bash tools/install-from-scratch.sh --verify        # 只复点现场，一个字节都不写
```

它会按顺序做完：前置检查（root / arm64 / 剩余空间）→ 取包并**逐字节撞 sha256** → push → **在设备上以 root 解压**
（只有这样才能保住属主与 setuid）→ 建挂载点目录 → `tools/deploy-entry.sh` 推那四件 → 起入口（第一次会造口令）→
把口令拉回 PC 烤进 APK → `tools/install-apk.sh` 只装机不重打 → 跑一遍 `dsh-entry-check.sh` 体检。

## 怎么算装好了

判据只认落下来的字节，不认端口在听（`AGENTS.md` 铁律 3）。体检那一步应当读到：

| 打哪里 | 应当 | 含义 |
|---|---|---|
| `:3080/` 裸打 | `401` / 68 B | 引擎活着、要券 |
| `:3081/` 不带口令 | `404` / 10 B | 门禁按设计不像"有东西" |
| `:3081/` 带口令 | `200` / 约 53,000 B | 这才是点开图标那一发 |

口令在设备上 `/data/local/dsh-rootfs/root/.dsh/entry.key`（44 B，别外发）。不想装壳，手机 Chrome 打开
`http://127.0.0.1:3081/` 进口令也一样能用。

## 产物本身

包大小、sha256、条目数、生成时间这些**只写在** `release-assets/payload-meta.txt`（随 Release 一起发），
本页不抄第二份 —— 抄了就会有两边对不上的一天。

## 装不起来时先看这几条

- `adb devices` 里是 `offline`：手机侧授权掉了，重插 USB / 在弹窗里勾"一律允许"；这台机的
  USB 安装闸口默认拦 `adb install`（`Failure [-99]`），装机走的是 `tools/install-apk.sh` 里那条
  `cp 到 /data 根 + restorecon + pm install -r`，别改回去。
- chroot 里 `tar/du/find` 报"not found"或行为古怪：chroot 之后继承的是 Android 那套 PATH，
  必须 `/usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`（两支脚本里都这么写）。
- 解出来的 `passwd`/`su` 没有 setuid 位：说明解压不是在设备上以 root 做的（见上面那条顺序）。
- 网页起不来但端口在听：先 `bash tools/deploy-entry.sh --check`，再看 `:3080` 裸打有没有 401。
