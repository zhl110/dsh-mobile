# dsh-mobile — 项目目标与进度

> **接班先读这一段（2026-10-21 深夜改写，给冷启动的人）**
> **最新一格是状态 53**（他："桥、cordis、注入器都做完，然后提交"。北京 11-08 11:1x，手机在场）：
> **三件与仓库逐字节一致**：桥 14,424 B md5 `5b92b309…`、注入器 9,512 B md5 `e9f6c113…`（`--check` 两条都 `[ok]`）；cordis 里 phone-mcp 命中 2，`--dump-config` 组合树 **phone-mcp 1 / bridge 1**；桥自测 **19/19**。
> **端到端**：`tap_xy(2693,782)`（横屏）→ `ok=true 436ms`；`dumpsys input` 最新一发 **deviceId=4**、自然坐标 (658.4,2692.1) = `_norm` 期望值 ⇒ 壳重装后注入器自动重连、仍走真触摸设备。进程：引擎 25088 / 桥 25618 / 注入器 15360。
> **日志第一批真实数据（拍到了"点进表情包"）**：`screen items=69` → `tap id=18 图片 "" center=1239,1532 via=已点击（触摸）` → `screen items=131` ⇒ 点的是**没有文字标签的 `图片` 节点（表情按钮）**，不是识图、不是脚本；下一步可给无标签图标补"相邻文字"提示（未做）。
> **没做什么**：cordis 没改、引擎没重启；14.50 起的那批改动一起进本轮提交。全文 **RUNBOOK 14.52**。
> **提交**：子仓 `44b5410` 已上 `origin/main`（回声 `587bbe9..44b5410`；HEAD 与 origin/main 都是 33、ahead 0）；父仓 `4ffa132`（主件）+ `2bee1a0`（七支新探针）。回填这一发自己的号不写。
> 上一格是**状态 52**（他："改成小鲸鱼，按动作换词；提示别在思考时消失"，并同意加动作日志。北京 11-08 11:0x，手机在场）：
> **壳 0.28**：提示条按动作换词 —— `🐳 小鲸鱼正在看屏幕 / 正在点一下 / 正在打字 / 正在发消息（点的控件文字含"发送"）/ 正在翻页 / 按了一下返回 / 回到了桌面 / 打开了最近任务 / 拉下了通知栏 / 正在打开「微信」/ 想请你定一下`，兜底仍是"正在操控你的手机"。**`screen` 也刷新提示**，末次动作后留 **60s**（原 8s，模型思考那一两轮里不再灭）。**动作日志**：`/data/data/com.zhl.dsh/files/actions.log`，环形 300 行：`screen 包名 items=N`、`tap 编号 角色 "文字" center=x,y via=做法`、`type 编号 chars=N`（**内容不记**）、`scroll id+方向`、`key 键名+返回值`、`open 请求名→解析名`。
> **读数**：APK **176,812 B sha256 `1a03b0d1…29e058`**，`pm install -r` 后机上 base.apk 逐字节撞、`versionName=0.28`；探针 144 只发 `screen` → `ok=true ms=44 bytes=638`、`屏幕 · com.tencent.mm · 共 35 项`；截图 `downloads/badge028.png`（`🐳 小鲸鱼正在看屏幕` 叠在微信聊天页顶部）；日志当场读回 `11-08 11:03:25 screen com.tencent.mm items=35`（与 35 项对上）。
> **装完一个坑**：重装杀掉进程后 **FGS 不会自己起**（`dumpsys activity services` 只剩 `TreeService`）⇒ `am start -n com.zhl.dsh/.MainActivity` 拉一次，`PhoneKeepAlive isForeground=true types=0x40000000` 复点，再把前台还回他原来的 `ChattingUI`。
> **没做什么**：桥/cordis/注入器没动；`tap` 的日志行没在真机触发（微信正聊着，只读了 screen）；提示条位置没动（仍 40dp，压在 App 标题栏上）；**未提交**。全文 **RUNBOOK 14.51**。
> 上一格是**状态 51**（"提交一下，再继续做"之后的继续：注入改写真触摸设备。北京 11-08 10:4x–11:0x，手机在场）：
> **把"多一个 touchpanel"的指纹也去掉了**：`dsh-uinput.py` 现在优先打开**真触摸设备** `/dev/input/event8` 写 MT 事件（`touchpanel`，X 0..23040 / Y 0..50688），写不进才退回自建 uinput。读数：`dumpsys input` 里 `touchpanel` **只剩 Device 4**；`tap_xy(1000,1250)`（横屏）→ **`deviceId=4`**、自然坐标 (190.5,999.9)；`scroll` 也是一串 `deviceId=4` 的 MOVE；竖屏复测 (999.6,1250.2)（`p140/p141/p142/p143`）。注入器 9,512 B md5 `e9f6c113…`，pid 15360（父桥 25618）。
> **踩的坑**：`B: PROP=2` 是位图（bit 1 = DIRECT），第一版 `& 1` 恒 0 ⇒ 静默退回 uinput、多出一个设备；改成 `& (1 << INPUT_PROP_DIRECT)` 才对（probe 135→137→139→140）。
> **没做什么**：APK 没动（0.27）、桥/cordis 没动；写真设备依赖 root 与这台机的 evdev write 行为（换机先跑 probe 133/134）；**未提交**。全文 **RUNBOOK 14.50**。
> 上一格是**状态 50**（他选了"换动作层 + 人性化（推荐）"，不要 LSPosed。北京 11-08 10:1x–11:0x，手机在场）：
> **动作层换掉了**：新增 `scripts/dsh-uinput.py`（6,621 B，md5 `9567cbd8…`）用 `/dev/uinput` 造虚拟触摸屏（名字 `touchpanel`），事件走 evdev → InputReader；人性化写在注入器里（落点 ±1px、随机按下/按住时长、滑动 ease-in-out）。壳新增 `Uinput.java`，`tap/tap_xy/scroll/type 的聚焦` 优先走它，**注入器不在就自动退回无障碍手势**。桥启动时拉起注入器（挂了 3 秒重起），`deploy-phone-control.sh` 一起推。**服务标签改成「屏幕辅助」**。
> **方向踩过一次坑**：App 连 root 的 socket 被 SELinux 拒（`avc denied connectto untrusted_app→su`）⇒ 反过来：壳起 `@dsh-inject` 服务端，注入器连壳。
> **读数**：raw 8192/16384/24576 → 360/720/1080（X）、792/1584/2376（Y）线性；竖屏 tap(1000,1250) 落 998.9,1249.4；注入器在 `deviceId=16`、被 kill 后 `deviceId=-1` 且操作仍成功（退回无障碍）、3 秒后重起 `deviceId=18`（`p127a/b/c`）；`scroll` 让 Settings 项数 32→33。引擎 8423→25088、桥 25618、注入器 25629（父 25618）。
> **横屏三种旋转已实测**（DSH 前台时 `cmd window user-rotation lock 1/3/2` 能真转；测完 `free`）：90° → 落 (190.5,1000.1)、270° → (1249.1,2170.5)、180° → (440.6,1918.3)，与 `_norm()` 公式逐一对上（`p129/p130/p131`）。
> **真设备对照已做**（`p134`）：直接往真触摸设备 `/dev/input/event8` 写一发 MT 触摸（手指走的就是它），系统收到 **`deviceId=4 flags=0x00000800`** ⇒ **0x800 是"开着会派手势的无障碍服务"给硬件事件打的标，不是 AI 专用**；与真手指在 flags 上没有差别。顺带发现 evdev write 不用 grab 就能注入 ⇒ **下一步换成写真设备，连"多一个 touchpanel 设备"的指纹也一起去掉**。
> **APK 0.27 = 176,813 B sha256 `592de335…88f6e1`**，装机逐字节撞、`versionName=0.27`（0.27 只多了保活通知文案改中性：`屏幕辅助运行中`）。**还没做**：`type` 没重新端到端跑、设备表里多出一个 `touchpanel`（下一步换 evdev 真设备解决）、另外三条无障碍服务照旧在列表、没写 LSPosed。全文 **RUNBOOK 14.49**。
> **提交**：子仓 `7e985bc`（完整 `7e985bccebed5ac605d193a58ff37028f1501058`）已上 `origin/main`（回声 `84a482f..7e985bc`，HEAD 与 origin/main 都是 31）；父仓 `68d405b2`（完整 `68d405b2ec70a4dd923e1b3aedd670847cac20a4`）。回填这一发自己的号不写。
> 上一格是**状态 49**（他两件事：①"再淡一些，我要透明的质感"；②"要保证我这个手机上的 AI 在操控我手机的时候，其他软件识别不到是 AI 在操控"。北京 11-08 09:5x–10:0x，手机在场）：
> **① 提示条 0.21**：主层 alpha 再降到 `0x7A/0x82`、光晕 `0x38/0x14`，另加文字白柔光（`0x99FFFFFF`+`BlurMaskFilter(2.5dp)`）⇒ 半透明、能透出底下内容，深浅背景都读得清。APK **172,716 B** sha256 **`31b56f67…f853a4`**、装机 `versionName=0.21`、机上 base.apk 逐字节撞；截图 **`downloads/badge21.png`**（深色）与 **`downloads/badge21-light2.png`**（浅色）。
> **② "识别不到"先量成硬读数：现在做不到，且不是推断**（`downloads/p101/p102.txt`）：
> - 无障碍服务在**公开列表**里：`dumpsys accessibility` 打出 `Service[label=DSH 手机控制, capabilities=33, ...]`；`AccessibilityManager.getInstalledAccessibilityServiceList()/getEnabledAccessibilityServiceList()` 是**公开 API、不要权限**。他机上另有 GKD / 喵喵记账 / #一指禅 三条常开。
> - **每一发触摸自带标记**：`tap_xy(1000,1250)` 后 `dumpsys input` 的 RecentQueue 原文是 `MotionEvent(deviceId=-1, ..., flags=0x00000800, ...)`（DOWN/UP 都是）；AOSP `MotionEvent.FLAG_IS_ACCESSIBILITY_EVENT = 0x800` ⇒ App 在 `onTouchEvent` 里读 flags/deviceId 就知道不是手指。
> - **换注入层的地基是通的**：chroot 里 `/dev/uinput` 在（`uhid_device`）、**open 成功**、python3 3.12+fcntl 在位 ⇒ 可建虚拟触摸屏（evdev→InputReader，真实 deviceId、flags=0）；机上有 **LSPosed/Shamiko/ZygiskSU**（"对指定 App 隐藏无障碍服务"这条路存在，但要另写模块）。`/proc/1/root/system/bin/screencap`、`uiautomator` 也在（读屏备用路）。
> **这轮没做的**：**动作仍是无障碍手势**（三个标记一个没去）、没改服务标签、没隐藏服务列表、没写 LSPosed 模块、没做抖动/间隔的人性化、没在具体 App 里跑检测 SDK；银行/支付这类把无障碍当安全边界的 App 没碰（要不要用他定）。**未提交**（铁律 9）。全文 **RUNBOOK 14.48**。
> 上一格是**状态 48**（他说"不要这种纯蓝色的实心框，要那种渐变色的。边缘虚化的那种淡蓝色"——指 0.14 那条操控提示。北京 11-08 09:2x，手机在场）：
> **提示条换成 `BadgeView`（壳 0.19）**：原来是 `TextView` + `GradientDrawable` 纯色 `0xE61B6EF3` ⇒ 就是他不想要的实心蓝块。现在改成自定义 View + **软件层**（`BlurMaskFilter` 只在软件层生效），两层画：外层 `BlurMaskFilter(1.5×)` 淡蓝光晕、主层 `BlurMaskFilter(0.8×)` + `LinearGradient(0xDF8FC6FF→0xE0D9ECFF)`（左上淡蓝→右下近白）⇒ **渐变 + 边缘虚化**；文字深海军蓝、不模糊、居中。尺寸按文字现算，`lp.y` 44→**40dp**（算上模糊外扩）。
> **读数**：APK 0.19 = **172,717 B** sha256 **`d62190cd…834566`**，装机逐字节撞上、`versionName=0.19`；截图 **`downloads/badge19.png`**（顶部一条左淡蓝→右近白的胶囊，四周散开一圈淡蓝光晕，文字深蓝）——与 0.14 那张实心蓝块 `downloads/badge14.png` 是两种东西。探针 99（`downloads/p99.txt`，只按 `key home`）为截图提供干净背景。
> **没做什么**：桥没改（仍 `9f249c45…`）、引擎没重启、cordis 没动；没让真模型跑聊天回合（这格只是外观）；**未提交**（铁律 9）。全文 **RUNBOOK 14.47**。
> 上一格是**状态 47**（他说"别的页面执行时突然弹选项框，AI 就停在那、我不回 DSH 也不知道也没法点；遇到选择要切回它自己界面让我选、再继续"。北京 11-08 09:2x，手机在场）：
> **加了两个工具（第 7、8 个）**：`handoff(reason)` = 把 DSH 自己 `startActivity` 拉到前台、交还控制权，并记下"刚才在操作哪个 App"；返回里让模型在聊天里问用户、答完用 `open` 回来。`open(app)` = 按包名或应用名拉起 App、回新屏，用于答完回原 App 继续。badge 在 handoff 时变「AI 需要你选择：回到 DSH」留 60s。manifest 加 `<queries> MAIN/LAUNCHER`（按名字找 App）。
> **实测（`downloads/p98e.txt`，0.18）**：`open com.android.settings` → 回 `com.android.settings 32 项`；`handoff` → "你刚才在操作 com.android.settings"；再读屏 = **`com.zhl.dsh`** ⇒ **切回 DSH 成功**（`startActivity` 从无障碍服务起没被 BAL 拦，`ResumedActivity` settings→com.zhl.dsh 实测）。
> **两个坑**：① `open` 后立刻读会抓在启动动画里、读回 `com.android.systemui` 假屏 ⇒ 改成"轮询到前台包不再是 systemui/本 App 再读"；② **熄屏也会冻 App**（`scene: LcdOff`，前台服务都拦不住）⇒ 真机测试先 `keyevent 224` 唤醒。
> **APK** 0.18 = **172,717 B** sha256 **`52ae9dfa…61190`**（versionName=0.18）；桥 md5 `9f249c45…`（含 handoff/open），引擎 20982、桥 21515。**没让真模型跑一次 handoff 的聊天回合**（要他在 DSH 里试）。**未提交**（铁律 9）。全文 **RUNBOOK 14.46**。
> 上一格是**状态 46**（他问"操控太慢 / 没有'AI 正在操控'提示 / 没法用原生输入法，在哪儿优化"，我建议先做 ②提示 + ①提速，他说"可以，你继续吧"。北京 11-08 09:0x，手机在场）：
> **② 操控提示做成了**：壳 0.14 用 `TYPE_ACCESSIBILITY_OVERLAY` 在屏幕顶部叠一条"AI 正在操控你的手机"（**不需要悬浮窗权限**，点不着、不抢焦点，最后一次动作后 8s 自动收；`screen` 只读 `TYPE_APPLICATION` 窗口所以不会读到自己）。截图 `downloads/badge14.png` 肉眼确认。
> **① 提速**：settle 改分档（窗口切换静默 150ms 回 / 内容变化 200ms / 无事件 900ms / 封顶 2s，旧版 1.5s/300ms/3s）；`screen` 默认不带坐标（新增 `detail` 参数，给 tap_xy 才要）。实测 `downloads/p96.txt`：纯读 68ms、按键 256–962ms。**结论写清：动作本身不是瓶颈，大头是每步一次模型推理（几秒）⇒ 要更快得减轮次或换模型，不是再抠 settle。**
> **③ 原生输入法**：他一句"聚焦输入框就可以了"，所以 0.15 只做聚焦唤键盘 —— `type` 先 `ACTION_CLICK` 点进输入框（ACTION_CLICK 会真聚焦并弹原生键盘，`ACTION_FOCUS` 不弹），再 `ACTION_SET_TEXT` 填字。不逐键、不自装输入法。**机器验证有缺口**：安全的几个原生界面（DSH WebView 输入 / Settings / 拨号盘）可输入节点都读不到 `isEditable` ⇒ "键盘真弹出来"要他在真 App（微信搜索框这类）里试。
> **APK** 0.15 = **172,719 B** sha256 **`0ff34206…cb6b91`**（versionName=0.15）；桥 md5 `459df410…`（本轮未再改桥、未再重启引擎）。**没在真机点过 tap/type/scroll 落点**。**未提交**（铁律 9）。全文 **RUNBOOK 14.45**。
> 上一格是**状态 45**（他连说四遍："你一步做到位，做到位之后，然后我在手机上试一下。"＋"继续"。北京 11-08 08:2x–09:0x，手机在场、无障碍开关他自己开的）：
> **做成了，完整控制环**：壳 **0.13**（versionCode 13）把 0.11 的只读扩成 **screen/tap/tap_xy/type/scroll/key** 六件（`TreeService.java` 520 行：三段式点击 = 本控件 ACTION_CLICK → ≤4 层可点父控件 → 坐标手势；EventClock 等稳 = 首事件 ≤1.5s + 静默 300ms、硬封顶 3s；手势走 HandlerThread + CountDownLatch；编号→节点缓存，动作后回新屏；密码框只标不填不渲染）。JSON 行协议（`{"cmd":…}`→`{"ok":…,"screen":…}`），兼容裸 `ping`/`screen`；`tree_service.xml` 补 `canPerformGestures="true"`（缺了 dispatchGesture 全回 false）。
> **引擎侧接线**：壳没有 server SDK（探针 92）⇒ 手写零依赖 MCP stdio 桥 `scripts/dsh-phone-bridge.js`（11,488 B，`--selftest` 本机 **16/16 PASS**），工具名 `mcp__phone__*`。接线 = `config/cordis-phone-mcp.snippet.yml`（`- insert:` 一个 `@deepseek-ai/dsh-mcp-client` 实例，serverName=phone，stdio 起桥），`tools/deploy-phone-control.sh` 推桥 + 备份 cordis（sha256 撞上才写）+ 追加，`--dump-config` **phone_mcp=1 / bridge=1**（不重启判据，铁律 14）。
> **端到端硬证**：最小重启引擎（13269→21616，入口 9685 自己拉新一代），新引擎 spawn 的桥 **pid 22254 父进程正是 21616** ⇒ mcp-client(phone) 已加载、工具已注册。探针 94（`downloads/p94i.txt`）：shell JSON ping/screen/key_home 全 ok、bad-id 回正确错；桥 MCP 6 工具；桥 `tools/call` screen+key home → `isError=false` + 新屏。链 = MCP → 桥 → abstract socket → 壳 → 动作 → 新屏。
> **本轮最大的一条坑：OOS 的 cached-app 冻结**（`downloads/p94e/f/g/h.txt`）。重装后进程被冻，thread wchan = **`do_freezer_trap`**，abstract socket 还在听但没人 accept ⇒ connect 成功、写出去、**没数据也不关**（看着像"服务没应答"，其实是被冻）。**doze 白名单 + standby active 都挡不住**（25s 后台仍冻）。修法：0.13 加前台保活 `PhoneKeepAlive.java`（`MainActivity.onCreate` 起，`foregroundServiceType=specialUse`，不请求 POST_NOTIFICATIONS）⇒ 进程停在 FGS 档（oom_adj → **50**），后台 25s 后 ping 仍 `pong`。教训：判"服务 socket 不应答"先看进程 thread 的 wchan 是不是 `do_freezer_trap`。
> **顺手修的两处**：`app/build.sh` 的 javac 闸只查 `MainActivity.class` ⇒ 0.12 第一发 TreeService 用了不存在的 `ACTION_SCROLL_LEFT/RIGHT` 编失败、MainActivity 却编过、**差点签出没有 TreeService 的废 APK**；现在闸要两个 class 都在（scroll 的 left/right 改成只走滑动，节点只有 FORWARD/BACKWARD）。`deploy-phone-control.sh` 的 chroot 命令禁单引号/`$()`（四层引号会塌）。
> **APK**：0.13 = **168,620 B** sha256 **`3d4d19d1808adf1bd58a82c594e957eab0c3ef276537df2102b27a814d3206f3`**（root-cp 装机 `Success/pm_rc=0`，机上 base.apk 与它逐字节撞、`versionName=0.13`）。
> **我这轮没做什么**：**没在真机上点过 tap/type/scroll**（手势层只验了 key home + screen，tap 走同一条手势管道、映射单测在本机 `--selftest`）；**没触发引擎自己那次 tool call**（证了"引擎 spawn 了桥、桥↔壳通"，模型→工具那一跳要他在聊天里试）；**未提交**（铁律 9）；没碰他的 `/data/local/tmp`、cordis 只 append 了 phone-mcp、purge、自启；没 reboot。全文 **RUNBOOK 14.44**。
> 上一格是**状态 44**（他一句："我等会儿把手机接上，你就说你能不能做。就是说，做这个控件树这个东西。"＋"好了，手机已经连接上了"＋"开了"。北京 11-08 07:4x–08:0x，手机在场、无障碍开关他自己开的）：
> **做成了，只读那一步**：壳 **0.11**（versionCode 11）新增 `app/src/com/zhl/dsh/TreeService.java`（AccessibilityService，229 行）——abstract socket `dsh-mobile-tree` 上两条命令：`ping`→`pong`、`screen`→带编号的控件树（上限 2000 节点 / 80 层 / 300 行 / 每标签 60 字符；密码框内容永不渲染；**performAction / dispatchGesture 调用点为零**，grep 命中 1 是文件头自述注释）。chroot 与宿主共用 netns ⇒ 引擎侧 Node 直连这个 socket（DSH Go PhoneBridge 同形状；他明说不二创 ⇒ 只参照形状、代码自写，对方 AGPL）。
> **端到端读数**（`downloads/p90-2.txt`）：`PING_REPLY="pong" / ping_rc=0`，`BYTES=1883 / HEAD=屏幕 · com.android.launcher · 共 38 项 / ITEM_LINES=38 / screen_rc=0`。装机走 root-cp 路 `Success / pm_rc=0`、机上 `versionName=0.11`；APK **164,524 B**，现役那发 sha256 **`bc70ac388154cda2495f781ad393d8c37cc75bcdaf059090ef4b023e5bddab23`**（第一发 `3b3c2ce8…` 被 uid 修复那发替掉）。开关他亲手开的，重装后仍在（名单 `grep_rc=0`、计数 1）。
> **本轮最大的一条坑**：第一版 socket 只放行 App 自身 uid ⇒ chroot 的 Node 是 **root（uid 0）**，connect 成功、一写就 **EPIPE**（`p90.txt`，证据留着没覆盖）；DSH Go 引擎在 proot 里与壳同 uid 所以没这条坑，我们是真 chroot ⇒ 放行 uid 0，重建重装后全绿。
> **交叉对账**：系统 `uiautomator dump` = **27 节点、全 `com.android.launcher`**；我们 **38 项** —— **口径差不是失败**（我们留跨窗口的文本/可交互节点，含文件夹第二页的屏外坐标与 hotseat 的零宽坐标）；两边都认前台包是 launcher。屏外/零宽坐标给下一步"点"提了个醒：要取可见区域内的点，不能裸用中心。
> **我这轮没做什么**：**没有点击/输入/手势**（下一步，他点头才做）；引擎与入口没起停（开工复点 pid 9685 / 13269 全程未动）；他的东西一个没碰、没 reboot；开关不是我拨的；DSH Go 代码一行没抄；引擎侧还没接 MCP 工具（socket 现在只有探针在用）；没在别的 App 页面验过树（只验了桌面这一屏）；**未提交**（铁律 9）——代码六件＋文档三份已暂存（**9 件 361/5**），隐私闸门 `--staged` **合计命中 = 0**（名单 5 条全干净），等他一句话就提交。全文 **RUNBOOK 14.43**。
> 上一格是**状态 43**（他两句："Readme 文件还有 Release 都要一起" ＋ "注意不要在里面提交我本地的一些私密的信息"。北京 11-03 22:1x–22:4x，手机在场但一个字节没动）：
> **这仓之前没有 README**（GitHub 首页是空的，而"即装即用"的门面就在首页）⇒ 建了 [README.md](README.md)：三层结构、要什么机器、`gh release download` + `bash tools/install-from-scratch.sh` 的装法、包里有/明确没有、怎么重造包、提交前那道隐私闸门、目录表。**体积与 sha 没抄第二份**（指回随包的 `payload-meta.txt`）。Release 说明同步改了并**读回**：body **522 字符**、里面 `README.md` 命中 **1**，三件资产名字与字节照旧（**没重新上传、没换 sha**）。
> **隐私普查**（口径 `git grep -I -c` 数跟踪区，遮之前）：序列号 3 件 7 处、本机用户名 8 件 10 处（其中 **6 处是写死的 adb 默认路径**）、Windows 家目录 7 处、提交邮箱 6 处、**签名库口令的默认值 1 处**；`github_pat_` 那 2 处 `len=11` 是 RUNBOOK 里的**词**、`sk-{20,}` 那 1 处是闸门自测埋的假串 ⇒ **没有真令牌、没有真 API key、没有私钥**。`ghp_`/`AKIA`/`PRIVATE KEY` 全 0。
> **全历史也扫了**（`git log --all -p` = 2,718,119 B）：序列号 8 行涉 5 发、用户名 12 行涉 6 发、邮箱 36 行涉 4 发（**大头是每发的 Author/Commit 元数据**）、口令默认值 3 行涉 1 发 ⇒ **这些在已公开的历史里仍看得见**；要收回只能改写历史 + 强推或删库重建，**本轮一条历史没动**（那是他的决定，不是我的）。
> **遮法与两条改动**：文档就地写成 `〈序列号·已遮〉`/`〈本机用户名·已遮〉`/`〈提交邮箱·已遮〉`（看得见是遮过，不是悄悄删）⇒ 复点四个形状**全 0**。可用那条路一起修了：五支脚本 + `pin-hosts.py` 的 adb 找法改成 **`DSH_ADB` → PATH → `/d/mycode/.agent-tools/…`**，`build.sh` 的口令默认值撤了 ⇒ 他本机那把 `app/local/dsh.keystore`（2,706 B）用的正是老默认值，**把值写进 `app/local/ks-pass`（0600，gitignore）并用 `keytool -list` 当场开库成功** ⇒ 重打 APK 不用他手传；**没重打 APK**（报过的 sha 不作废）。机型与 root 方案那 57 处、`D:\mycode` 那 36 处**按判断留着**（是装机前提与指令坐标，不是身份标识）—— 要遮他一句话。
> **新闸门 `tools/check-private.sh`**：`--selftest` **合计 7 条 PASS 7**（埋雷要抓到 / 撤雷要回 0），无参扫 **合计命中 0**（5.0 秒）。真值名单在**不入库**的 `tools/private-values.txt`；名单不在位算命中，不静默通过。第一跑抓到三个自伤（闸门扫到自己写的正则字面量 / 计数与文件列表不同源 / `git add -q` 这版 git 不认），都改了并留痕（RUNBOOK 14.42 四）。
> **提交与推送**：子仓 **`e3dd32c`**（完整 `e3dd32c52bfc59fb68e5252c4d7b35873122d21f`，14 件 **285/32**，新增 `README.md` 4,717 B 与 `tools/check-private.sh`）—— 提交前 `bash tools/check-private.sh --staged` **合计命中 0** 才动（第一跑可是 **2**：我自己新写的文档把那条家目录形状的字面量写了出来，被自家闸门拦住）；一次性 SSH URL 回声 `8f92921..e3dd32c`，fetch 后 HEAD 与 origin/main **都是 28**、`origin/main..HEAD` = 0。README 在 GitHub 上按**逐字节**认：`api.github.com/…/contents/README.md` 回 **200 / 4,717 B / sha256 前缀 `4216b413749ea6f2`**，与本机那份 `cmp` 撞（`raw.githubusercontent.com` 那发是 **502 / 0 B**，别拿它判死）。父仓 **`23fbbead`**（无 remote，只落本地）。回填这一发自己的号不写。
> **我这轮没做什么**：**没改写历史、没强推**（所以二里那四项仍永久可回看）；没删库、没动默认分支与分支保护、没重新生成令牌；没重打 APK；**没在干净机上跑 `install-from-scratch.sh`**（README 正文那句实话就是为这格写的）；没验整包从 GitHub 拉回来能不能解；**手机一个字节没动**（没起停引擎、没推件、没跑探针）；没跑真机上的隐私复点。全文 **RUNBOOK 14.42**。
> 上一格是**状态 42**（他一句："把仓库改成公开"。北京 11-03 21:4x–21:5x，手机在场、他人也在电脑前）：
> **库现在是 PUBLIC**：<https://github.com/zhl110/dsh-mobile>（`gh repo view` 复点 `PUBLIC isPrivate=false`），Release 那三件资产**外人真下得动** —— 判据不是 200 也不是退出码，是**匿名 Range**：`curl` 不带任何令牌拉 `dsh-rootfs-20261103-132346Z.tar.gz` 的头 `0-1023` ⇒ **HTTP 206 / 收到 1024 B / 头四字节 `1f 8b 08 00`（gzip 魔数）**，`payload-meta.txt` 全量 **200 / 1,611 B / sha256 前缀 `fbcf1da545ceeaa1` 与本机那份撞上**；repo 页与 tag 页匿名都 200。测试件当场删。
> **翻开关之前先把全历史扫了一遍**（公开不可逆：历史里的 blob 后来删了也还在）：187 个跟踪文件 / `.git` 18 MB / 最大单文件 3.9 MB ⇒ 体积条件都在限内；`sk-…{20,}` 全历史只命中 **1 行**，追进去是闸门自测埋的假串，另一发 `apiKey|secret|password` 带长值的命中是归档 RUNBOOK 里那行 **`sk-dummy-invalid-do-not-use`**（故意无效的哑 key）；`config/dsh-env` 只有 3 个 export、**没有 API key**；`reference/` 那份默认配置"键名带 ≥12 位值"命中 **0**。⇒ **没有真凭证会被公开。**
> **会露出去的是设备信息**（序列号 `〈序列号·已遮〉` 6 处、一加 13、KernelSU/susfs 这套 root 方案、"引擎直跑不弹窗"这个形态）与那 **901 MB 包本身**；服务只绑 `127.0.0.1`，不做端口转发就摸不到 —— **这是读数不是保证**。提交邮箱 `〈提交邮箱·已遮〉` 在他另外两个**公开**库里早就是公开的 ⇒ 这次不多露一次。
> **中间那堵权限墙**：`gh repo edit --visibility public` 回 **HTTP 403**（那把 fine-grained PAT 只有 Contents + 建库，没有 **Administration**）。摊开两条路让他一次决定（他自己点两下 ／ 给令牌加权限），**他选加权限** ⇒ 当场复点 `.permissions` 回 **`admin=true`**，再翻就过了。**编辑权限不换令牌值**（只有 Regenerate 才换）⇒ gh 与 GCM 里还是同一把，没重登、没改配置。代价他也认了：Administration 还管**删库、改默认分支、改分支保护**。
> **驱动浏览器那一段我停过一次手**：Qoder 内置浏览器**没有他的 GitHub 登录态**（一进设置页就跳 `/login`）⇒ 只能开他的 Edge（`msedge.exe <URL>` 在现有实例开新标签，进程 18→20 复点到）+ 坐标点击。**第一发点中了**（`CURSOR_AFTER` 与请求值一致），**接着两发被抢**（请求 `617,437` 回 `461,282`、请求 `600,30` 回 `636,35`）⇒ 他手在鼠标上，**在令牌设置页盲点不安全**，改成"每一步说给他点"，他自己走完了 `Edit → Administration → Read and write → Save`。顺带纠正一次走偏：他先开的是 **Tokens (classic)** 那把（页顶红字 `expired on Fri, Aug 14 2026`），**不是 gh 在用的** `ZHL110`。
> **还欠两格没变**：① `install-from-scratch.sh` 仍**没在干净机上跑过**（现在别人能下载了，但"装完能用"还是只有设计证据）；② **没验"从 GitHub 整包拉回来能不能解"**（只验了匿名取到头部 1024 B 与 meta 全文）。
> **提交与推送**：子仓 **`836b36a`**（完整 `836b36ae5585b9ff130f7f0be2a08e4edd309ef7`，4 件 66/2）已上 `origin/main` —— 一次性 SSH URL 回声 `03135a7..836b36a`，SSH fetch 后 `rev-list --count` HEAD 与 origin/main **都是 24**；父仓 **`554e767`**（完整 `554e7676a6e8c6db6d01cac0fa0d9a5c1297d3f1`，那仓无 remote）。回填这两行那一发自己的号不写。
> **收尾补一发（同轮，北京 22:0x）**：上一发文档指着忽略区的 `downloads/*.ps1`（别人拉不到）⇒ 两支抄进 `tools/win-click.ps1`（1,126 B）与 `tools/win-shot.ps1`（466 B）、引用两处就地改口，子仓 **`fd93ac8`**（4 件 38/2，回声 `2484d7f..fd93ac8`）、父仓 **`f101dc1`**；报告发出前重撞：`visibility` = **PUBLIC**、HEAD 与 origin/main **都是 26**（`origin/main..HEAD` = 0）、匿名 Range 仍 **206 / 1024 B / `1f 8b 08 00`**、meta 仍 **200 / 1,611 B / `fbcf1da545ce`**。RUNBOOK 14.41 六·补。
> **我这轮没做什么**：没删库、没改默认分支、没开分支保护、没动那把令牌的其它权限项、没重新生成令牌值、没碰 `agent-hub` 那条 SSH；没跑完整 901 MB 匿名下载；没在第二台机装过；他的东西一个没碰、没 reboot、没装包、没重启引擎、没改 git 配置。全文 **RUNBOOK 14.41**。
> 上一格是**状态 41**（他两句："adb 重新连上了，开始发布吧" ＋ "跑完给我链接和读数"。北京 11-03 21:0x–21:2x，手机全程在场）：
> **包真打出来了、Release 真挂上了**：<https://github.com/zhl110/dsh-mobile/releases/tag/payload-20261103-132346Z> —— tag `payload-20261103-132346Z`，**3 件资产**（gz **945,106,711 B** / `payload-meta.txt` 1,611 B / `SHA256SUMS` 101 B），
> `gh release view` 读回 `state=uploaded` + 三枚 digest，`gh api …/releases -q length` = **1**，**本机 `sha256sum` 那三件与 GitHub 的 digest 一字不差**（`ea33b2b0… / fbcf1da5… / 2df52745…`）。判成只认读回来的资产，不认 `gh` 的退出码。
> 产物指纹：机上保留体积 2,633,803,541 B ÷ **2.79** = **901 MB**，条目 **112,172**，sha256 `ea33b2b098f6ef2215f83841c6722e936637fd035782dce9a472a12ea327bbce`；耗时：机上打包 **133 秒**、`adb pull` **20.8 秒（43.3 MB/s）**、上传 **175 秒**（⇒ **推算约 5.4 MB/s**，这条是推断不是读数）。
> **这一轮最大的一条**：**这台机的 adbd 带不了大二进制流** —— `exec-out` 的 fd 是 `/dev/pts/0`（tar 报"输出是终端"，PC 只收到 **427 B 而退出码 0**）；`shell` 那条 socket **64 KiB 全换行逐字节撞上**、换成 **120 MB** 真流则 PC 侧**多 614,713 B 且 md5 不对** ⇒ 形状是"小样过、大样翻车"。
> ⇒ 改成**机上 `tar -czf` 落文件（`GZIP=-1`）→ `adb pull` → 机上自报的字节数/sha256/条目数与 PC 重算的三份逐字节撞**；`tar_stream()` 已被 `tar_to_file()` 替掉，**没给输出路径直接 rc=2**（不留"顺手流一下"的路径复活）。代价：机上临时多占 901 MB。
> **闸门二第一次真跑就抓到一条真阳性**：第 3 发 **55 命中**退出码 1、产物当场停。拆开是两种东西 —— **9 条该拦**（`./usr/local/lib/python3.12/dist-packages/frida-17.24.3.dist-info/*`；`DROP` 原本只写了 `frida` / `frida_tools` 两个目录名，**没盖住 dist-info** ⇒ 宽成 `frida*`，条目 **112,181 → 112,172**）＋ **46 条同名误伤**（`node_modules/dsh-purge/{lib,presets}/redteam/*`，那是**他装那个插件的源码**、不是这台机的数据）⇒ 名单闸门从此分「**拦（本机写过的路径）/ 参考（上游包里的同名词）**」两批计数，两条都印。
> **上一格那条降级判据现在有读数了**：机上 `/etc/shadow` 的 root 栏 = **锁定/无哈希**、474 B / 18 行 ⇒ 就算按老规矩判也不需要停下来问他。**做法一条没改回去**（原件永不进包，包里发替代件，装机 **3b** 放回）—— "默认就安全"比"这次恰好安全"值钱。
> 另两条同族坑：`du -sbx /` **不 prune bind 进来的 `/phone`**（与 rootfs 同一个 `st_dev`）⇒ "整树"读出 **375,699,793,028 B** 那种假数，已加 `--exclude=/phone`；PC 侧包装函数 `CHRUN` 写了 `$1` ⇒ `--pack <路径>` 只过去第一个参数（**adb 那侧全程 0**），靠新加的"没读到 `[pack] tar rc=0` 就 exit 1"才抓住。
> **还欠三格（都是实测缺口，不是待办）**：① `install-from-scratch.sh` **一行都没在干净机上跑过**；② **库是 PRIVATE ⇒ 外人拿不到那三件资产**，"给别人装"这一句目前只对他 invited 的人成立；③ 那 **46 条 `redteam` 随包走了**（要剥是他一句话，剥了那份插件就缺文件）。
> **提交与推送**：子仓 **`8ab847c`**（完整 `8ab847cb48f2862cd47fa31a673643608219746c`，6 件 197/36）已上 `origin/main` —— 一次性 SSH URL 回声 `f225e24..8ab847c`，`ls-remote` 复点 `8ab847cb48f2…`，SSH fetch 后 `rev-list --count` HEAD 与 origin/main **都是 22**（HTTPS 那发 fetch 仍撞 `CRYPT_E_NO_REVOCATION_CHECK`）；父仓 **`b006ccf`**（完整 `b006ccf9e0c159a9002864bd11df2abdaee41598`，那仓无 remote）。
> **顺带一条形状**：`gh release create` 在远端建的 git tag `payload-20261103-132346Z` 指向 **`f225e24`**（发布那一刻的 HEAD），**不是产出这一发产物那两支脚本所在的提交** ⇒ 要复现产物请用 `8ab847c` 的脚本，tag 只当坐标（RUNBOOK 14.40 九）。回填这两行那一发自己的号不写。
> **我这轮没做什么**：没在第二台机装过、**没验"从 GitHub 拉回来能不能解"**（只验了上传侧 digest 与本机体侧 sha —— 那是两件不同的事）、`--split` 那条路没跑到（901 MB 没超档）、`/usr` 那 1 GB 多仍未逐文件扫、闸门一那 **539** 个凭证串的值一个都没打印、他的东西一个没碰、没 reboot、没装包、没重启引擎、没动自启、没改 git 配置。全文 **RUNBOOK 14.40**。
> 上一格是**状态 40**（他一句："先不验证，直接提交"。北京 11-03 凌晨，手机**仍不在场**）：
> **先说这句我按哪个意思做的**（免得下一个人读成"把闸门拆了"）：拆掉的是**需要他在场才能判的两格** —— ① `/etc/shadow` 里 root 有没有哈希（原打算等上机看一眼再定）、② 打包与发布之间那一步人工确认。
> **两道泄露闸门一条没松**（它们不需要人，跑不过就不出包），而且**多了一条**。"不验证"落到实物上的部分是：`install-from-scratch.sh` 从没实机跑过这件事**不再当发布前提**，改为在文档与 `payload-meta.txt` 里明写"未经干净机验证"。
> **`/etc/shadow` 改成"默认就安全"**：原件永不进包（进 `DROP`），`--pack` 时 `stage_shadow()` 现造一份 **root 栏 `!`、其余行原样**的替代件，落 `./root/payload-stage/etc/shadow`（`640` / `chgrp shadow`），装机脚本新增 **3b** 把它放回并复点三个数（root 首字符 / 行数与替代件相等 / 落点存在）。
> 两条护栏都在 `--selftest` 里：**行数不撞就删掉替代件不随包走**、**原件读不到退码非 0 且不产出空件**（空文件放回 `/etc/shadow` 会抹掉整棵树的身份信息，那是更坏的形状）。
> **代价写明白**：只解压、不走装机脚本的人拿到的 rootfs 没有 `/etc/shadow` —— 不影响 chroot 起来（我们全程是 Android 侧 root 进的），但 `passwd`/`su` 那条口令登录不可用。
> **出包到挂 Release 现在是一条命令**：`bash tools/make-payload.sh --publish`（本机自测 → 设备普查 → 取流 → gzip → 两道闸门 → `SHA256SUMS`/`payload-meta.txt` → 超 1900 MB 切卷 → `gh release create payload-<UTC>`），**判成没成只认读回来的资产**（名字/字节/sha256 摘要），不认 `gh` 的退出码；切卷时只传卷。
> **顺手抓出两个真 bug**（都是今晚不依赖手机就能验的那类）：① `gh -q '(|.assets|length|tostring)'` —— 开头那个 `|` 让 jq 直接报 `failed to parse jq expression`，**而退出码还是 0**（管道尾巴是 `tr` 的码），正确写法 `(.assets|…)`；
> 用 canary 资产验通（2 件 9 B：建 → 读回名字/字节/digest → 删净，`releases` 长度复点 **0**）。② `--notes` 又用了 `"…\` + 换行` 续行（**同一条老坑的第 3 次出现**），改成多段 `NOTES="${NOTES}…"` 拼接。
> **`--selftest` 从 3 条长到 5 条**，11-03 凌晨本机当场 **`合计 5 条：PASS 5 / FAIL 0`**（新增 D = 替代件 root `!` / 别的行在 / 原哈希不残留，E = 原件读不到不产出空件）；三份脚本 `bash -n` 都过、CR 都是 0。
> **包与 Release 今晚还是没有**：`adb devices` 现在**连 `offline` 那行都不回了**（空列表），Windows 侧 `VID_22D9` 三条仍 `OK` ⇒ 只能他重插 USB / 勾"一律允许"。
> **提交与推送**：子仓 **`5adcf94`** 已上 `origin/main`（一次性 SSH URL，回声 `752c4af..5adcf94`，`ls-remote` 复点 `5adcf94978ce…`，fetch 后 `rev-list --count` HEAD 与 origin/main **都是 20**）；父仓 **`d568008f`** 本地提交（那仓没配 remote）。回填这两行那一发自己的号不写。
> **我这轮没做什么**：没打成包、没建 Release（`releases` 长度复点 **0**）；`install-from-scratch.sh` 新增的 **3b 一行都没实机跑过**（本机连不通 adb）；`--publish` 只验到 `gh` 的表达式与"建 / 读回 / 删资产"，**真 GB 级上传没跑过**；
> `/usr` 那 1 GB 多没扫；新闸门与 shadow 替代件**在真机上一次都没跑过**（只在 PC 同型树上验的）；他的东西一个没碰；没 reboot、没装包、没重启引擎、没改 git 配置。全文 **RUNBOOK 14.39**。
> 上一格是**状态 39**（他一句："那你就先打包一个 release 出来，然后上传上去。" 北京 11-02 深夜到 11-03 凌晨，**手机不在场**）：
> **包还是没打成，而且是硬卡**：`adb devices -l` 一直是 `〈序列号·已遮〉 offline`，`reconnect offline` 后条目直接消失，`kill-server`/`start-server` 两轮、
> 4×12 秒轮询、`mdns services`（空，机上没开无线调试）都没救回来；`Get-Process` 复点机器上**只有一发 adb**（pid 53652，不存在两个版本抢 5037），
> 而 Windows 侧 `VID_22D9` 三条都是 `OK`（ADB Interface / USB Composite / WPD 一加 13）⇒ **手机侧那条调试会话掉了，PC 侧没有能自己按的按钮**。
> 也量过"PC 上有没有现成的一份可以替着打包"：三处目录 `+50M` 只回他的 `stock_boot.img` 与别项目的 `sokuji.tar.gz` ⇒ **rootfs 只在那台机上**。
> **这段时间把唯一还能推进的一格推了：Release 上传权限 + 闸门一重估。** ① 权限用一发 80 B 的 canary 量死 ——
> `gh release create --draft` 退出码 0、`view --json assets` 读回 `size=80 / digest sha256:1f000dd…`、`gh release delete --yes` 后 `releases` 长度复点 **0**，
> ⇒ **建 Release 与传资产都有权**，真包出来直接推（小坑：资产名不能以 `.` 开头，gh 会改成 `default.xxx`）。
> ② 闸门一原来判"词形"（扫 `password|secret|sk-|Bearer ` 这类词）在本机同型 profile 树上**必然误报**：`password` 43 个文件、`sk-` 26、`Bearer ` 13、`secret` 28，
> 一条真凭证都没有；换成猜"值形状"也不成（`sk-[0-9a-f]{32}` 整棵 `~/.dsh` **0 命中**，`AKIA…` 反倒在 PIL 与 pnpm 里误报 2 发）。
> ⇒ **判据换成"已知凭证串回归"**：从 `entry.key` / `.dsh-env` 的每个值 / `llm-deepseek` 里取真串（只进内存、绝不打印），回扫保留集；
> 顺带抓出一条**会永久出不了包的死锁** —— 旧版扫的是活盘，会把**脚本自己**（里面就写着这些词）和已剥掉的 `.bash_history`/`.dsh-env` 算成命中。
> 扫描面改成从"与 `tar --exclude` 同源的那份保留清单"里筛，普查范围与包体范围从此恒等。
> ③ 新闸门**不需要手机就能验**：`bash scripts/dsh-payload-pack.sh --selftest` 今晚本机实跑 **合计 3 条：PASS 3 / FAIL 0**
> （埋雷要抓到 / 撤雷要 0 且当场取到过串 / 凭证源为空要明确报"取不到串"而不是蒙成 0），`make-payload.sh` 出包前先跑它一次。
> 名单闸门（闸门二）也单测了一发：**必须命中的 15 条漏 0、故意保留的 7 条误伤 0**；计数解析器三种输入形状都对。
> **出包前还差一格判断**：`/etc/shadow` 里 root 有没有哈希今晚拿不到（那要在机上跑第 4 节）——**有哈希就不能随包走**，这是打包前的最后一道内容关。
> **提交与推送**：子仓 **`3cc7dbf`** 已上 `origin/main`（一次性 SSH URL，`ls-remote` 复点 `3cc7dbf56ee5…`，HEAD 与 origin/main 都 **18**）；父仓那发同内容本地提交（那仓没 remote）。
> **我这轮没做什么**：没打成包、没建 Release；`install-from-scratch.sh` 仍一行都没实机跑过；新判据**在真机上一次都没跑过**（只在 PC 同型树上验的）；
> `/usr` 那 1 GB 多没扫；他的东西一个没碰、没 reboot、没装包、没重启引擎、没改 git 配置。全文 **RUNBOOK 14.38**。
> 上一格是**状态 38**（他两句："把引擎、Ubuntu rootfs、Node、dsh 本体，全部提交到仓库里，让他们即装即用"＋"你不用问我，你就直接做完，做到最后打包完结束之后，你再跟我说"。北京 11-02 22:0x–23:5x，手机**前半程**在场）：
> **先给判据（这是决定形状的那一句）**："提交进 git"这条路**不通不是因为配额，是因为格式装不下** —— git 树对象没有 uid/gid 字段、没有 setuid/setgid 位：
> 这棵树实测 root:root **119,474** 个、1001:1001 **6,194** 个、setuid/setgid **17** 个（`passwd`/`su`/`mount` 那一族），整树 **4,554,034,779 B**（`downloads/p89.txt`）。
> checkout 出来属主全变、那两位全丢 ⇒ chroot 里起不来。**我第一版把"设备节点存不了"当决定性证据，那条被读数推翻**：`/dev` 是运行时 tmpfs，本来就不在树里。
> **交付形状改成"产物 + 一键装"**：`scripts/dsh-payload-pack.sh`（设备侧，**剥除清单的单一真源**）＋ `tools/make-payload.sh`（PC 侧：收流 → 本机 gzip → 两道泄露闸门 → `SHA256SUMS`/`payload-meta.txt` → 超 1900 MB 切卷）
> ＋ `tools/install-from-scratch.sh`（取包**撞 sha** → **设备上以 root 解压**才保得住属主与 setuid → 建挂载点 → `deploy-entry` → 新机才 `deploy-env` → 起入口造口令 → 体检 → 拉口令烤 APK → `install-apk`）＋ `docs/INSTALL-from-scratch.md`。
> 包里**明确没有**：入口口令、`/root/.dsh-env` 与它所有备份、任何 provider 的 API key、会话/附件/storages/日志、缓存、`/tmp`、`/phone`、frida —— 所以别人装完第一件事是**在网页里填自己的 key**，不是缺装。
> **可行性有实测**：`/usr` 那一发 `tar+gzip -6` = **802,531,136 B**、99 秒、**比 3.05** ⇒ 整包估在 1 GB 上下，单发 Release 附件装得下（保留体积普查 **2,763,876,302 B**，`du` 口径，与 tar 同一批 `--exclude`）。
> **没做成的那半要说清**：**包没打成** —— 手机在这一轮中途从 `device` 掉回 **`offline`** 就再没回来（`reconnect`、`kill-server` 两轮、两个 adb 二进制读数一致，Windows 侧 `ADB Interface Status=OK` ⇒ 是手机侧调试会话掉了，要重插 USB / 勾"一律允许"）。
> ⇒ `release-assets/` 还是空的、**GitHub Release 一个都没创建**（`gh api …/releases` 读数：**空**）。脚本齐、判据齐、两道闸门齐，**只差取数那一发**。
> **新坑两条**（都白花一轮 adb，已进 AGENTS.md）：① `chroot` 之后继承的是 **Android 那套 PATH** ⇒ `tar/head not found`，看着像"chroot 里没 GNU tar"；
> ② 三层引号里写 ERE，`{12,}` 被设备 shell 展成好几个词、`|` 被当管道 ⇒ 一发普查打出 **770 行 `/dev` 报错**还**退码 0**，那种输出**一条都不能信** ⇒ 清单/模式一律搬进设备侧脚本文件用数组。
> 还有一条旧坑复发：`"…\` + 换行` 的续行**把反斜杠留在了值里**，普查里冒出 `[状态 ] \` 那种条目。
> **提交与推送**：子仓 **`b5ff594`** 已上 `origin/main`（HTTPS 仍撞 `CRYPT_E_NO_REVOCATION_CHECK` ⇒ 一次性 SSH URL 推，`ls-remote` 复点 `b5ff5946dc0d…`，HEAD 与 origin/main 都 **16** 发）；父仓 **`4f083967`** 本地未推（那仓没配 remote）。
> **一处我自己的事故**：中途用 Write **覆盖了仓里已有的 `.gitattributes`**（10-20 就建好、比我要写的那份更全），已 `git restore --source=HEAD` 还原并复点 `git diff HEAD` **空**。
> **我这轮没做什么**：没打成包、没建 Release；`install-from-scratch.sh` **一行都没实机跑过**（这台是现役机，第 3 步"非空就停"本来就该拦住它，真验证要第二台机）；
> `/root/.dsh` 那层的**内容普查只跑了一半**（那发作废），所以 DROP 是按"运行态一律剥"定的、不是逐条按普查定死的；`/usr` 那 1 GB 多上游 js **没扫**；
> 没 reboot、没装包、没重启引擎；他那批（`/data/local/tmp`、cordis、锁屏、自启、purge）一个没碰。全文 **RUNBOOK 14.37**。
> 上一格是**状态 37**（他追问两问："这两个现在是没实现，而不是坏了。**那为什么不给它实现**？我跟你说的就是把所有的功能全部都接上，**是有什么隐患吗**？"＋"你下次别拿'两个开关没翻'这种话回我，**把没做的东西列个清单，写清楚它到底是怎么回事**"。北京 22:0x–23:2x，手机在场）：
> **先答那问：不是隐患，是我上一轮设了一道"有实证需求才接"的门槛，而那道门槛的判据我用错了范围。** 我只扫了前端产物（`dsh-web-frontend/dist`，64 个文件）就判"页面不用下载、不用全屏"——**这个"不用"是错的**：真页面除了 dist 还有 **57 个 `dsh-client-ui-*` 包**（186 个文件 / 29,396,960 B）在往里注入 UI，pdf 预览那颗"下载"就是 `a.download = filename` + `a.click()`，文档预览里就有 `<video>` ⇒ **两条都有真实用户**，0.9 及之前的真表现就是"点了没反应"，与他报的加号那发**同一个病族**（表在 RUNBOOK 14.35 四，p79→p86 七发探针每一发都在推翻上一发的范围）。
> **壳 0.10 一次接完并装机**（160,359 B / sha256 `d4476e4e…`，机上同名同尺寸撞上、`versionName=0.10`、`lastUpdateTime=2026-10-22 22:51:43`、**权限一个没加**）：HTML5 全屏（`onShowCustomView`/`onHideCustomView` ＋ 返回键 `handleBack` ⓪ 分支）、页面下载（`setDownloadListener` 三条路：http 交系统下载器并**抄 WebView 那份 cookie**、blob 让页面自己取字节 base64 回传后壳写盘、data: 只有代码**没实测**）、再加一发"页面自己起的文件名"通道（**WebView 的 `onDownloadStart` 把 `<a download>` 的名字丢了**，`contentDisposition` 交过来是空串，桌面 Chrome 不会）。
> **每条一个实测读数**（全文 14.35 三）：全屏 进/退/返回三条日志都齐；http 那发落盘 **27,312 B / md5 `1c35dff0…` 与源文件逐字节相同**；blob 那发 900,000 B 从点击到落盘 **0.42 秒**；改名通道两条 `名字来自=页面 download 属性（prompt 通道记回来的）`；剪贴板**写 = 通**（原生粘贴键粘回同一个串 ⇒ 那些"复制"按钮不需要壳做任何事，上一轮标"未验"是我漏做一次实测）、**读 = 不通**（`readText` 回 `NotAllowedError`，WebView 不给壳任何回调 ⇒ 要通只能自己垫桥，等他点头）。
> **撞出一条这台机特有的坑**：**下载要真手势** —— 在 `evaluateJavascript(…, userGesture:true)` 里 `a.click()` 一次都不进 `onDownloadStart`，必须用 CDP `--tapsel` 发触摸（我第一轮因此以为监听没生效）。
> **他点名的那句"两个开关没翻"是我写人话失败**：那是 `setAllowFileAccess` / `setAllowContentAccess` 两个 WebView 开关，修附件**不需要翻**（翻了反而打开"页面能自己加载 content URL"那扇门）。以后"没做的事"一律按 **是什么／现在什么状态／为什么／对他有什么影响** 四列成清单给他 —— 这一轮的清单在 RUNBOOK 14.35 五（**23:4x 他又追了一句"黑屏／不自动重试／市场转圈昨天不是修好了吗"，那张表第 10 行按读数拆成三行**：市场是"病根 10-21 晚改了、欠屏幕上那一格验收"，黑屏与自动重试确实一行代码没动；**我把三条并成一行还写"都还没修"是我把账记粗了**）。
> **两件我自己的事故先说坏的那半**：① 新探针的输出写进了 `downloads/p75.txt`，**覆盖了 14.33 引用过的那一份**，已按原脚本重跑（10,645 B、两条关键原文都在），**差的 1 字节没定位** ⇒ 只能记"抽查等价"不能记"完全复原"；② **他系统剪贴板现在是我写的串**（`剪贴板复点-2257`），我唤了屏看到锁屏但**没解锁没碰 PIN**，3 件测试下载件与页面注入件都删净了（只留 `dsh-upload-test.{txt,png}` 那两件，第 8 格还要用）。
> **我这轮没做什么**：前端一行没动、manifest 权限没加、`data:` 那条没实测、剪贴板读没垫桥、`onGeolocationPermissionsShowPrompt` 没接（0 个用户）、没在他的会话里发过任何消息、没打开他的文档预览点下载、他那批（`/data/local/tmp`、cordis、锁屏、自启、purge）一个没碰；**代码＋三份文档全部未提交**。全文 **RUNBOOK 14.35**。
> **→ 10-23 00:2x 就地补两格（旧话不删）**：他一句"**能装，我已经测试过了，装了几个插件了，能用，没问题**"当场把"插件市场"这一整条关掉 —— 我 00:14 复点到的那发 `装插件 → 500` 只留作一次尝试的留痕，**不当缺陷、不再追**；他能装也就顺手补上了"屏幕上到底转不转圈"那欠了三天的**一眼**（读数 `downloads/p87.txt`，全文 RUNBOOK 14.36 五）。**这一格真正还挂着的只剩两条**：重进后黑屏十几秒、报错（503/502）后不自动重试 —— 这两条代码一行没动，**修法现成（只改常驻入口，不用重装 App）**，走法等他一句。
> 上一格是**状态 36**（他报"手机上点加号选文件/图片没反应"，并要我顺带查"其他这些功能有没有一一对应上"。北京 21:0x–21:57，手机在场）：
> **断点找到了，也修到能取读数**：病在壳没实现 `WebChromeClient.onShowFileChooser` —— 它的默认实现**直接 `return false`**，Chromium 把这一发**静默丢掉**
> （页面侧 CDP 记录到 `input[type=file].click()` 发了 1 次；清空后的 logcat 里 `START` / GET_CONTENT **0 条**）。系统侧不缺件：GET_CONTENT 可解析项 `-t "image/*"` **12** 个、`-t "*/*"` **20** 个。
> 壳 **0.8** 接上选择器与回调（装机 152,167 B / sha `6d25f79e…`），**0.9** 再加一行"壳自己复点这张通行证"（本地=机上逐字节撞上：**152,166 B / sha256 `2b2dc8dd…f30c957d`、`versionName=0.9`、`lastUpdateTime=2026-10-22 21:48:31`）。
> **一次真选跑到第七格**：`21:54:46.057 选中 1 个（上限 20）｜首个=content://com.android.providers.downloads.documents，路径 62 字符` → `21:54:46.086 壳侧复点 #0 ⇒ 打得开｜text/plain｜92 B`
> → 页面侧在 `change` 里抓到 `size:92 / type:text/plain / head:"dsh-mobile 附件链端到端测试件"`、附件栏出 `dsh-upload-test.txt TXT 92B`。
> ⇒ **新知一条：`setAllowFileAccess(false)` / `setAllowContentAccess(false)` 不影响附件通道**，别为了修上传去翻这两个开关（之前当隐患挂着）。取消也结得干净（两次 `结果码=0 ⇒ 交 null 给页面`）；
> 插件那条 input 的 `accept=.zip,.tgz,.tar.gz,.tar,.skill` **原样进了 Intent**（21:55:58），但**没真选** —— 一选就往他引擎里装插件，那一步等他点头。
> **只剩最后一格要他点**：按"发送"之后 multipart 有没有真把 92 B 送过 `:3081` → `:3080`。**现场已备好**：他输入框里现在挂着 `dsh-upload-test.txt` 那一发待发附件，按下发送即成，不想要点 × 撤掉。
> **其他对应关系的账**（表在 RUNBOOK 14.34 四）：语音 ✅（0.6 已端到端）、相机按设计拒（`audioOnly` 闸 ＋ manifest 无 `CAMERA`）、页面下载**没接 `setDownloadListener`**、HTML5 全屏**没接 `onShowCustomView`**（与附件这次同族的静默无反应，页面用到就会复现）、`navigator.clipboard` 3 处**未验**（那次 `--tapsel` 量到中心 `y=−6725` ＝元素在屏外，是我的判据失效，不算页面缺陷）。
> **我这轮没做什么**：前端一行没动；两个开关没翻；权限没加；没在他的会话里发过任何消息；`/data/local/tmp` 他那批、cordis、锁屏、自启开关一个没碰；**代码与文档全部未提交**（他说提交我才提交）。全文 **RUNBOOK 14.34**。
> 上一格是**状态 35**（他一句"不撤，插件你先不用管"＋"这段回复我没看懂，你给我解释一下"。北京 22:43–22:58 手机在场）：
> **这一格的主体不是我做的动作，是手机上那个 dsh 自己动了一次盘** —— 它备份（508 B，sha 与我那份逐字节相同）、把 `runnerCommand` 两行接回 cordis（**508 → 1,627 B**，位置挂在 `- id: sandbox`，是对的）、
> 用 `--dump-config` 不重启验到命中 1、手工调 runner 量了三个 YES、然后 `setsid bash -c 'sleep 15; kill -TERM 26114'` 自己把自己重启成**第 6 代 pid 28833**（入口 **17611 没动**，实测断 **4.1 秒**，cookie 自动重换 303）。
> **它自述六条里五条我撞上了读数**（备份 / 接线 / dump / 换代 / 会话没断点），**但那条最要紧的是错的**：
> 机上真在加载的那一份 `confine()`（22,231 B、md5 `b976570f…` ＝ 我本地 `downloads/sbx-dev-index.js` 逐字节相同）我直接调了一次 —— **`ARGV_HAS_RUNNER=no`、`FAILURE_RULES=[]`**，
> `pgrep -f dsh-unshare-run` 两次 **0** ⇒ **它接的线在 purge 在位时是死配置，围栏没有回来**。
> **它为什么没看出来（这条最值）**：它读的是 `/root/.dsh/dsh-purge/host-backups/9dac90ce22cf7f551f319a5e.bak` —— **purge 动手前存的原件**，磁盘上早就不加载了；同名代码有两份，读错一份就得错结论（已进 AGENTS.md 铁律 17）。
> **反过来这一格有一件白捡的收获**：14.30/14.32 欠了三轮的那条判据（"到 App 里让 Agent 跑一条 `echo` 才算 ✅"）**被它替我们答了** ——
> `dpkg.log` 14:39:47 落了 `install libonig5 / libjq1 / jq / ripgrep` 四行、`dpkg -l` **411 → 415**，命令原文在它会话记录第 30 条 `apt-get install -y --no-install-recommends ripgrep jq`，
> 而那会儿跑的还是第 5 代、purge 已短路 ⇒ **`workspace-write` 档位下命令真执行、真装包、没被拒、没弹窗**（反面同义：**没有围栏**；它是"强推断"级：命令串＋安装时刻两条独立来源，不是引擎侧进程审计）。
> **→ 23:3x 他一句「那是我让他装的，没关系，我要的就是这种效果」**：这条判据的效力不变，但**发起者是他授意**、不是它自作主张 ⇒ "没有围栏／不弹窗／root 直跑"这三层**就是他要的交付形态**，以后**只陈述读数、不再当风险反复报**（AGENTS.md 铁律 19）。
> 它最后问他"要不要先实测 `setpriv` 降权堵 `/proc/1/root`" —— 我量了：**围内与围外四条读数一模一样**（`LS=acct apex bin` / `TOP=71` / `ST=emulated persist self`）
> ⇒ 那条缺口不是 runner 漏了 `/proc`，是**现在根本没有 runner 在中间**；他 purge 不撤 ⇒ **这条挂起，不做**。
> **他对 purge 的回答记死在本格**：选 ①（留着 purge、我不动插件），②③ 关掉。他那三层我一件没动，我这边复点也全等：入口 `70,487 B 4af378c9…`、兼容层 `13,521 B 23b672dc…`、`/root/.dsh-env` `8,066 B a1dad02f…` 三个 md5 与仓库逐字节相同。
> 全文 **RUNBOOK 14.33**（六条对账表、它 44 次工具调用的命令串清单、`findmnt --target` 那条假口径、`/data/local/tmp` 里我自己 8 件旧残留的 md5 对账表都在里面；读数 `downloads/p71.txt`–`p75.txt`）。
> **待他一句的两个小选择**：① cordis 那两行撤 / 留（留 = 一条死配置挂在盘上，且它写的注释里那句"confine() 走 :311 那条分支"是错的）；② 我 10-19 落在他 `/data/local/tmp` 的 8 件清不清（4 件与仓库 md5 全等、`cfg-after.txt` 内容与本地 `cfg-before.txt` 全等、`env10150.txt` 与 `w.xml` 本地没有 ⇒ 要清就先 pull 再删）。
> **→ 23:3x 之后这两个还挂着，但优先级降了**：他"我要的就是这种效果"把"围堵要不要补回来"这整问关掉 ⇒ 那两行**按留处理、我不再催**（撤法与备份 sha 都记在 14.33 七①，一句话就能还原）。
> **→ 10-22 00:0x 他一句「提交并推送」做完**：改口那一发工作仓 `198c49a`（三件 `+16 / −1`）**已推到 `zhl110/dsh-mobile`**（`22faf1d..198c49a`，`ls-remote` 服务端复点同号、`rev-list --count origin/main..HEAD` = 0），父仓 `18039cd8` 同步 —— **父仓没有 remote，那侧仍只是本地提交**（"提交≠上传"这条第二次撞上，见 AGENTS.md 已知坑）。
> 再往前是**状态 34**（他那六件事一轮做完四件半，剩下半件撞出一个更大的数。北京 21:2x–22:1x 手机在场）：
> **① 键盘跟随修好了并装了机** —— 病根不在页面：0.6 上取到自证读数（真触摸 → 安卓 `mInputShown=true` 而页面 `innerH` 仍 **360** 一字不改），
> 是壳 0.4 那版沉浸式全屏让 `adjustResize` 失效；壳 **0.7**（152,166 B、sha256 `be025bb3…`，**与机上 `base.apk` 逐字节撞上**）把 `Type.ime()` 的 bottom 压成 root 下内边距，
> 复点 `innerH 360 → 152`、composer `240 → 32`、收起复原，截图 `downloads/kbd-up.png`。
> **② 横屏左栏现在是整列能滑**（兼容层 **9,793 → 13,521 B**、机上 md5 `23b672dc…` 撞上；rail `scrollHeight 360 → 746`、被压那层可视 `16 → 402`、松掉 6 层 `flex-grow`，**真手指 `input swipe` 把 `scrollTop` 0 → 386**）。
> **③ 最要紧的一条：这台机现在没有任何进程围堵。** 按他"重启没关系"把 `runnerCommand` 接到 `- id: sandbox` 底下（`--dump-config` 不重启就验到命中 1）、
> 只 SIGTERM 引擎（**21363 ⇒ 26114**，入口 17611 没动、10 秒自动换到第 5 代 cookie），端到端一打 ——
> **`confine()` 返回的 argv 根本没被包装**：purge 今天北京 18:35 给上游 **42 个文件**打了补丁（备份件 56 份），沙箱 / 文件围栏 / 审批弹窗 / 档位升级各有一处直通。
> ⇒ 接线**已逐字节撤干净**（cordis 回到 508 B、sha 与备份相同、`runnerCommand` 命中 0；两行原文存进 `config/cordis-sandbox-wiring.snippet.yml` 待用），
> **14.30 那句"Bash 在 `workspace-write` 下仍然明确拒绝执行"按代码判据已作废** —— 但**我没跑真回合**，所以他 App 里让 Agent 跑一条 `echo` 才算新的 ✅/❌。
> **④⑤⑥**：`/root/*.sh` 9 → 3、`/tmp` 13 → 9（只删我自己造的，删前逐条撞 md5；剩的都不是我的）；四批包的数**重量并改口**（旧 84/6/**61**/29 里 61 是错的、且少一口径；
> 含 recommends **161/6/103/78**，四批**并集**才是 **281 个 / 503.4 MB 下载 / 1,992.2 MB 占盘**，容器那批我建议不装）；镜像那条**装了 → 查出形状错（gitee mirrors 不带 owner）→ 撤了，实装 0 条**，
> 同一发里 **GitHub 又活了**（200 / 353,218 B，`git ls-remote` 真回 SHA）⇒ **状态 33 那句"今晚死了"按当次落字节改口：这条路由在漂**。
> 全文 **RUNBOOK 14.32**（接线五步与全部撤法、三档留给他的裁决都在里面）。
> **等他点的三档**（我不替他选）：留着 purge（现状＝全直跑、无围堵、档位是装饰）／撤 purge＋接 runner（真围堵，但降级跑能 kill 宿主 pid 且 #18 的 `/dev` 窟窿没堵）／撤 purge 不接（回到 Bash 全灭）。
> 再往前是**状态 33**（14.30 交完我自己又追了七发探针 56–62，就问一件事：**今晚这台机还有哪条网路活着**。北京 20:4x–21:1x 手机在场）：
> **交付物一件没跑掉** —— 引擎 21363 / 入口 17611 没换代、dpkg 仍 411、机上兼容层仍 9,793 B（md5 `268f90ad…`）、出口首页 49,958 B 里侧栏那段属性在位；
> **GitHub 这一跳今晚死了**：curl `(28)` 超时 / `/dev/tcp` 说连上 / node TLS 8 秒没动静，三种口径、**硬事实是 0 字节**，而对照组 `objects.githubusercontent.com` TLS 400 ms 握手成 ——
> 连文档里那条退路 `gh-proxy.com` 也被重置（`(35) Connection reset by peer`），已归进 `doh-hosts.sh` 的 WATCH 摞（**不钉**，机上 7,660 → 8,379 B、md5 `f046d046…` 逐字节撞上）。
> **git 因此这一步才算真落地**：`git clone --depth 1 https://gitee.com/mirrors/git.git` **rc=0 / 76,737 KB / HEAD `c514088` / 4,857 个文件**，复点后删净 ⇒
> **DSH 里跑 git：走 gitee 通、走 GitHub 今晚不通**；npm 与 pypi 同刻都活着。我自己这轮又造了三类假读数（贪婪 `sed` 抓末位答案、`awk $0~d` 子串拿错行、`rm -rf` 掉自己正站的目录 ⇒ 整批 git 假红），
> 全部按读数改口并写进 `AGENTS.md` 第 2 条。状态 32 那格欠的还是他那四件，只是**第 ② 件（打开市场）现在多了一个外部变量**：region=global 的第一源在 GitHub，今晚多半取不到 ⇒ 全文 **RUNBOOK 14.31**。
> 再往前是**状态 32**（他一句话塞来四件事并排了序：文档先瘦身 → 装 git/python3 → 横屏左侧栏要能划 → 《手机端情况.md》逐条清，"你给我最终结果就可以了"。北京 19:5x–20:3x 手机在场）：
> **文档**拆完了（`RUNBOOK.md` 284,811 B → 现役 106,666 B + 归档 185,927 B；`PROGRESS.md` 状态 12–25 → 归档件 40,036 B，**只搬不改**，多的字节全是新加的说明头）；
> **环境**B 类装齐（dpkg **141 → 411**，四批"模拟数 = 差集数"每批各等，20 个命令名 `command -v` 全在位，`df` 多 1,010 MiB，**引擎 21363 没被带倒**）；
> **pip 装了但门没开**这件事查到底了 —— 病还是"域名没钉"，补 `pypi.tuna.tsinghua.edu.cn` 一条后不带 `--resolve` 真下到 60,166 B 索引与一个 wheel，
> `pip install --target` 装的包能 import 且真打了一次 `api.deepseek.com`（`2.34.2 401`）；npm 那侧本来就是 npmmirror，`npm pack` 落 604 KB，我没动。
> **市场**那条路由端到端（**200 / 7,000,459 B / 1,110 ms，第二发 208 ms**）；**横屏侧栏**上游产物里根本没有语义类名（`sidebar`/`_rail`/`aside` 命中全 0），
> 所以补丁挂在兼容层、靠**页面上真存在的文字**定位，**注入层已证实生效**（机上 9,793 B 与本地 md5 逐字节撞、入口热读 8,265 字符、出口 HTML 里属性在、`injectMiss=0`）。
> **这一格欠的全是他那双眼与那一下**：转横屏划侧栏、在 App 里打开市场页、pip 三条路（21 个包 / `--break-system-packages` / `--target`）挑一条 + 剩下四摞（84/6/61/29 个包）装不装、runner 接线何时重启。**Bash 在 `workspace-write` 下仍然拒绝执行**。全文 **RUNBOOK 14.30**。
> 再往前是**状态 31**（他一句"提交到我的 GitHub 仓库里去，权限是私密的"。查出来 `D:\mycode` 那仓**从没配过 remote**（227 发全在本地），他账号下是一项目一库、没有 dsh-mobile
> ⇒ 新建**私密**库 `zhl110/dsh-mobile`，本目录成了独立 git 仓（照他 `agent-hub` 那个"父仓照样跟踪 + 子目录自己有 `.git`"的形状），历史用 `git subtree split` 切过来：**5 发 / 109 个文件 / 名字+blob 双列对账空输出**。
> **已经推上去了（北京 19:40）**：`git push -u origin main` 退出码 0，两边**同号** `bf18e733be…2919`、提交数 **6=6**、文件数 **132=132**，`gh` 回 **`private=true`/`PRIVATE`**；远端树里 `downloads/`、`reference/gh-3p/`、`app/out/` 各 **0** 条。那把 fine-grained PAT **能建库**（这条本轮才量出来，之前是未知）。
> **这一格里我自己摔了一发并还原**：`git init --initialBranch=…` 选项名少连字符 ⇒ init 失败，后面用 `;` 串的四条 git 命令**往上找到父仓**、把它的 `main` 挪走并 reset 了 index；靠 reflog 找回 `175bcfbf`，**盘上一个字节没动**，代价只是"他暂存区若有东西会被打回未暂存"。全文 **RUNBOOK 14.29**。）
> 再往前是**状态 30**（他回来报的两个症状，北京 18:5x–19:1x 手机在场一整轮：**插件市场一直转圈**查到两条叠在一起的根因（区早已落盘成 `global` 且永不重探 ＋ 那个区的两个目录 host 一个都没钉进 hosts），
> 按他「**两个都弄，当场重启**」改完了 —— `tools/doh-hosts.sh` 钉名单加 `awesome-dsh-plugin.com`（新增 1 条、备份 sha 撞了才写）、
> `config/dsh-env` 加 `DSHM_NPM_MIRROR=npmmirror` 并用**新写的 `tools/deploy-env.sh`** 推上机（顺带查出来机上那 1,687 B 是 10-20 那发、14.25 的模板改动从没推上去过），
> 然后只 `SIGTERM` 引擎让入口自己重拉 ⇒ **14851 ⇒ 21363，10 秒，cookie 自动重换、他那条入场链接没废**，新引擎 environ 里 `DSHM_` 计数 = 1、不带 `--resolve` 的 HEAD 已回 200。
> **图标那条判成启动器缓存**（装机件是新的：152,167 B / sha `17c280ac…` 逐字节正证；缓存按包名+versionCode 认，这发还是 6）⇒ 他挑了"先重放一次图标"，我**没重打没重装**，那发 sha 仍然有效。
> **这一格差的只剩他一眼**：在 App 里打开市场页 —— 探针 44 时 `log.ndjson` 仍停在 18:40:50（换代后没人请求过目录），"没报错"不算通过。全文 **RUNBOOK 14.28**）。
> 再往前是**状态 29**（手机在场的一整轮：新图标那发 APK **已装机**（机上 `base.apk` 152,167 B / sha256 `17c280ac…bfc964cb`、`lastUpdateTime=2026-10-21 17:48:31`，装机后又用 `tools/install-apk.sh --verify` 逐字节复点过）；
> **两发社区插件也进了手机那台 `web` profile**（三个计数 2/2/2、`bundles` 5→7、`list` rc=0、形状与电脑那台完全同形），
> 而且**没重启引擎它自己就接住了** —— 为判这条连开五发探针，最关键一记是引擎 fd 23 的 inotify 正在听 `package.json`。过程与读数在 **RUNBOOK 14.27**（八小节））。
> 再往前是**状态 28**（电脑上官方 DSH 0.2.1-rc.2 里现在装着**两个社区插件**：`dsh-purge 1.1.72-dsh021rc2.4`（**他已点「应用」，宿主已被打补丁**：`resources\app` 453 M、`.dshpurge.bak` 57 份、`dsh.cmd` 已改写并留 `.bak`，而 `app.asar` 一字未动）
> 与 `dshmarket 1.66.45`（**不写宿主**：装完 2 秒宿主 HMR 就把它组合进层栈了，正证是 profile 里新落的 `.dsh-market/state.json` + `log.ndjson`；**只差他在设置页看到那条 Plugin Market 入口**）。purge 与 market 的源码/打包件都在 `reference/gh-3p/` 与 `D:\tools\dsh-plugins\`，取证口径写在状态 27–28）。
> 再往前是**状态 27**（他要 dsh-purge：上游已删库，本地留了上游全量镜像 + evilevil 的 0.2.1-rc.2 适配版两份，并把后者装进 desktop profile）、
> **状态 26**（他嫌图标不好看 → 换成那张满幅图，APK 重打但**还没装进手机**——这句按状态 29 作废），再往前是状态 25（网络解析）/ 24（241 MB 语音模型）。
> 状态 23 / 24 / 25 / 26 / 27 / 28 / 29 / 30 / **31** **不在下面"当前状态"那一节**，写在 `## 文件变更` 节的末尾（历史写法，没搬动）
> —— 只看"当前状态"就以为最新是状态 22，那是错的。
> **→ 2026-10-21 晚整理文档，上面那句只到"没搬动"为止已经不准了（就地加箭头，旧话不删）**：
> 状态 23 / 24 / 25 现在在 **[PROGRESS-archived.md](PROGRESS-archived.md)**（连同状态 12/13 到 25 那十几格，整段搬的、原文一字未改），
> 现役件 `## 文件变更` 里从**状态 26** 起，最新仍是**状态 31**。`grep -n "状态 25" PROGRESS-archived.md` 一步到行。
> **→ 深夜再改口（状态 33 写完之后）**：现役件里现在是 **26 → 33**，最新一格是**状态 33**；32 与 33 都写在 `## 文件变更` 末尾。
> 同一轮把 `RUNBOOK.md` 也瘦身了：§1 与 14.1–14.23 进 [RUNBOOK-archived.md](RUNBOOK-archived.md)，现役只剩第 0 节 + 一张索引表 + 14.24 起（为什么搬、怎么验没丢、字节对账都写在那份的顶部）。
> **10-21 傍晚还有两轮没有状态号、写在 `## 下一步` 第 21–23 条**：
> 21–22 = 逐条对表他交的那份《手机端情况.md》（RUNBOOK 14.25 —— **取证脚本 `scripts/dsh-envclaim-probe33.sh` 已在 北京 17:57（= UTC 09:57） 跑过，读数 `downloads/p33.txt`，对表结论已按读数改口**），
> 23 = 读完 `docs/` 那两篇 REA 对比报告后跟我们自己的代码做的差分（RUNBOOK 14.26：**20 条已做 / 5 条真缺口 / 6 条明确不抄**，新增待办 #43–#46）。
> 最后一次读到的现场（**北京 19:08（= UTC 11:08） 那一发换代＋复点，`downloads/p44.txt`；写这段时手机还连在这台电脑上、adb server 在跑**）：
> 三层都在跑（壳 App `com.zhl.dsh` **0.6**＝装机件 → 常驻入口 `:3081` pid **17611**（**出生 2026-10-20 13:27:14Z，这轮一次没动**）→ 引擎 `:3080` 已是**第 4 代 pid 21363、出生 11:08:18Z**（19:08 那发之前读到的是第 3 代 **14851**，生于 10:35:33Z＝北京 18:35；**那次换代不是我做的**，我从没执行过 kill，`entry.log` 在 10:35:35 有两条 `ECONNREFUSED` ⇒ 上一代在那一刻自己死了、入口按 backoff 重拉，死因未查。更早 18:17 那记读到的是与入口同批出生的 **17637**））；
> `/root/.dsh-env` = **5,567 B / md5 `cd1ed15c…` / 600 root:root**，与仓库 `config/dsh-env` **逐字节相同**（`deploy-env.sh --check` 回"不用推"；两个 export：`DSH_PERMISSION_MODE`、`DSHM_NPM_MIRROR`），`/etc/hosts` 钉名单里现在**有** `awesome-dsh-plugin.com`；
> 市场那侧 `state.json` 仍 `"region":"global"`、`log.ndjson` 仍 **6,606 B / 改于 18:40:50**（换代后没人请求过目录 ⇒ 这一格欠他一眼）；
> 旧一记留着对照（北京 18:17 的 `downloads/p40.txt`：`/root/.dsh` 245 M、`profiles/web` 13 M、pnpm store 14 M、盘上可用 341 G、引擎空转 45 秒出网 200 B 级／回环 82 KB／`/root/.dsh` 零写、语音模型三份 241,357,257 B 在位）；
> 这一轮流量差集（18:56:12→19:08:16）= **出网 1,340,503 B ≈ 1.28 MiB，几乎全走 WiFi**（蜂窝只 10,532 B）。
> **→ 北京 20:4x–21:1x 又有一发复点（状态 33 的 p56），上面那三行"最后一次读到的现场"按它读**：引擎 **21363** / 入口 **17611**（都还没换过代）、
> `/etc/hosts` **29 行**、dpkg **411**、机上兼容层 **9,793 B / md5 `268f90ad…`**、出口首页 **49,958 B** 里侧栏属性在位；**写状态 33 的此刻手机仍连着、adb server 在跑**。
> **→ 22:1x 再往上一格（状态 34 的 p70 + 装机复点），上面那两行按它读**：壳 **0.7**（`versionCode=7`、机上 `base.apk` 152,166 B / sha `be025bb3…`＝本地件）、
> 引擎 **26114**（第 5 代，22:09 换代）/ 入口 **17611 仍未动**、兼容层 **13,521 B / md5 `23b672dc…`**、出口首页 **200 / 53,687 B**（带口令；不带口令按设计 404/10 B）、`:3080` 裸打 **401/68 B**、
> cordis **508 B 且 `runnerCommand` 命中 0**（接线已撤）、`/root/.dsh-env` **8,066 B = 仓库件**（多了 `DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=1`）、dpkg 仍 **411**、hosts 仍 **29 行**、`/tmp` 顶层 **9**、`/root/*.sh` **3**；
> **写状态 34 的此刻手机仍连着、adb server 在跑**；purge 那 42 个文件与 56 份 `.dshpurge.bak` **原样在位**（我没动）。
> **→ 22:58 再往上一格（状态 35 的 p71–p75），上面那两行按它读 —— 这一格动的不是**我**：引擎 **28833**（第 6 代，出生 14:43:58Z＝北京 22:43:58，是手机上那个 dsh 自己 `kill -TERM` 换的）/ 入口 **17611 仍未动**、
> 兼容层 **13,521 B / md5 `23b672dc…`** 与 `.dsh-env` **8,066 B / `a1dad02f…`** 与入口 `/usr/local/bin/dsh-entry.js` **70,487 B / `4af378c9…`** 三件仍＝仓库件（它没碰我这三层），
> 出口首页仍 **200 / 53,687 B**、`:3080` 裸打仍 **401/68 B**；**变的只有两处**：cordis **508 → 1,627 B、`runnerCommand` 命中 4**（它接回去的，内容是**死配置**，见 14.33 三）、dpkg **411 → 415**（它 14:39:47Z 自己 `apt-get install ripgrep jq`）；
> hosts 仍 **35 行**（我 14.30 那轮加的，本轮没再动）、`/tmp` 顶层 **6**（那 6 项都不是我的，见 14.32 六）、`/root/*.sh` **2 + 探针自己**；purge 那 42 个文件与 56 份备份件**仍原样在位**，**模块 mtime 仍是 10:35:16 ⇒ 今天没被再应用一次**。
> **→ 10-22 深夜再往上一格（状态 36 装机与状态 37 的现场，读数分别写在 14.34 七与 14.35 七），上面那几行按它读**：壳 **0.10**（`versionName=0.10`、`lastUpdateTime=2026-10-22 22:51:43`、机上 `base.apk` **160,359 B / sha `d4476e4e…`＝本地件**；
> 0.8 = `6d25f79e…` 21:26:51、0.9 = `2b2dc8dd…` 21:48:31 是同一晚前两发），→ 入口 pid **10326**（`etime 11:46:49`）→ 引擎 pid **4409**（`etime 08:31:06`）⇒ **这两号与状态 35 那记的 17611 / 28833 都不同＝入口与引擎各换过一次代**；
> **换代不是这两轮我做的**（状态 36/37 这两轮我没执行过 `kill`、没重启服务，只装过 APK），但**具体哪一刻、被谁换的没查** —— 按 etime 反推入口生于 10-22 北京 11:1x、引擎生于 14:3x 前后，都在今天白天，比这两轮早；要归因得另取一发现场（task #60）；
> 健康口径两条仍成立：`:3080` 裸打 **401/68 B**、`:3081` 无 cookie **404/10 B**；`shell.log` 到 22:55 共 **962 行**。
> **本轮没复点的**（别当成"没变"）：cordis 那份（508 B / 1,627 B 两档的判据）、dpkg 计数、hosts 行数、`/tmp` 与 `/root/*.sh` 残留数、purge 的 42 个文件与 `.dshpurge.bak` 计数 —— 全在 **task #60** 那格欠着。
> 电脑上：**客户端此刻没在跑**（`Get-Process -Name 'DeepSeek*'` = 0，是他下午自己退的，不是这个会话做的），
> `dshmarket 1.66.45` 已进层栈并**自己起过一次**，他开一次客户端确认那条 Plugin Market 入口就闭环。
> 接下来该干什么：先扫 `## 下一步` —— **最新那条是第 31**（状态 33 判出来的：今晚 GitHub 那跳死了、gitee 能干活，要不要给 git 配一条 gitee 镜像路由他定）；
> **→ 22:1x 改口（状态 34）**：**第 31 条已被自己的读数解掉**（那条 `insteadOf` 形状错、已撤，实装 0 条；GitHub 今晚又活了 ⇒ "要不要镜像"这个问题今天不成立），
> **最新是第 33 条**（状态 34 新加的：purge 那三档他挑哪档 + 唯一那条判据＝在 App 里让 Agent 跑一条 `echo`），第 32 条是**重量后的四批包**（并集 **281 / 503.4 MB / 1,992.2 MB**，容器我建议不装）；
> **→ 22:5x 改口（状态 35）**：**第 33 条的两问都由他这一句答完了**（"不撤，插件你先不用管"＝选 ①，②③ 关掉；那条 `echo` 判据也被手机侧 14:39:47Z 的 `apt-get install` 替我们跑了 —— 见 14.33 四），
> **最新是第 35 条**（状态 35 新加的两件一句就够的小选择：cordis 那两行撤/留、我 10-19 落在他 `/data/local/tmp` 的 8 件清不清），第 34 条是**手机侧现在是第二个写手**这件事带来的新规矩；
> **→ 10-22 深夜再改口（状态 36–37）**：**最新是第 38 条**（本轮接完的下载／全屏还剩两格没实测：`data:` 那条只有代码、没在他的文档预览里真开过一次），
> 第 **37** 条是**剪贴板"读"要不要垫那发桥**（约 30 行、走 `dlname` 同一条无来源校验的通道，等他点头），第 **36** 条仍是**他按一次"发送"**（附件链第 8 格，唯一验收）；
> 第 36 条末句那三格"只有他能答"的事，**后两格本轮已由读数答完**（复制按钮通、剪贴板读不通、下载与全屏页面真在用且已接）⇒ 只剩"按发送"与"插件要不要真选一发"。
> 第 **28–30** 条是状态 32/33 欠他的（① pip 走 A/B/C 哪条 + 剩下四摞装不装 + apt 缓存清不清；② 转横屏划一下侧栏 → **本轮已改完并验过滚动，还欠他那一眼睛**；③ `doh-hosts.sh --check` 要不要做成周期性对账），
> 第 **26** 条是状态 30 欠他两下（① App 里打开插件市场 = 那一格唯一验收，**深夜补一句：今晚 GitHub 死了，若还转圈先看时间再看改动 —— 14.31 五**；② 桌面图标删了重放一次）；
> **第 18 与 21 条本轮做完已划掉**；要他亲手做的还有第 12 / 15 条与"开 App 看那三处 + 点不点「应用」+ 红队预设留不留"（状态 29 末），
> 第 13 / 16 / 17 / 24 与新增的 #43–#47 等他点头（第 24 条是"开 App 看那三处 + purge 点不点「应用」+ 红队预设留不留 + 那 6 份一次性 `.sh` 清不清"）。
> 再扫 `## 遗留问题`（那里全是"别只读表面就下结论"的坑）。
>
> **今晚这一轮的顺序（2026-10-21 午后排，他一句"先整理一下晚上要做哪些事"；`adb devices` 当时回空 = 手机还没插）**
> **→ 执行记录（18:2x 就地补，别删这段）**：① 复点 ✅（引擎活 73,223 秒、`injectMiss=0`、`up401=0`，读数在 RUNBOOK 14.26 之后那段）
> ② 装机 ✅ **而且没重打**：`lastUpdateTime=2026-10-21 17:48:31`、机上 `base.apk` 152,167 B 与本地**逐字节撞 sha**（`install-apk.sh --verify` 复点）。
>    **这句要改口**：午后排的"`bash app/build.sh --install`"做不到"不重打"—— `build.sh` 前六步无条件跑，装机只是第七步，同源码重打 sha 就变。
>    实际走的是新写的 `tools/install-apk.sh`（只推现成这发）；**桌面那张满幅图还欠他一眼**。
> ③ 未做（要他亲手）④ 三步全走 ✅：`--check` → 探针 32 → 真装 **2/2/2**，`bundles` 5→7、`list` rc=0；
>    预留那两个坑当场失效一个（**机上早有 pnpm 12.14.0**，不用往他机上装包），另一个判完了（**不用重启引擎**，14.27 二）
> ⑤ 未做（要他在场）⑥ 一行没动，但读数备好了（`apt-get -s` 三档 **291 / 440 / 35** 个新包，`p33.txt`）⇒ 等他挑 ⑦ 未做（等他开客户端）
> 1. **他插上手机，我先复点，不动手**：`adb devices` → `dsh-chroot.sh --status` → `:3081` 与 `:3080` 各读一次。
>    **不许假设"上次还在跑"**；复点结果与上面那批读数不一致，先改口再干活。
> 2. **装新图标那发 APK**（我做）：`bash app/build.sh --install` 走那条 `push → cp /data → restorecon → pm install -r`，
>    **别为了装它重打**（重打 sha 就变，报过的数作废）。装完认两个数：sha256 `17c280ac…cb` 与 `dumpsys package com.zhl.dsh` 的 `versionName 0.6`（**字节数不能单独当身份**）。
>    然后**他解锁点一下图标**，看桌面那张满幅图（白角没了）+ 顺便把"点开就能用"补成 ✅。
> 3. **他亲手一步**（语音那半已他自己结案，**不再测也不再提**）：添加工作区 → 选择工作区目录 → 看第一屏有没有「手机存储」那一行、点不点得动。
> 4. **新到的活（他一句"把刚才装的那两个插件也装到手机上"）：把 dsh-purge 与 dshmarket 装进手机那台 `web` profile**。
>    脚本这轮已经写好，晚上照这三步走，**别一上来就 add**：
>    ① `bash tools/install-phone-plugins.sh --check` —— 只量前置（本地清单 + 设备数 + chroot 里 `pnpm` / `dsh` / registry），**一个字节不写**；
>    ② `bash tools/run-probe.sh scripts/dsh-plugins-probe32.sh downloads/p32.txt` —— 只读探针，把 profile 现状、`dsh plugin list` 通不通、npmmirror 出口落多少字节、空间与引擎进程一次量全；
>    ③ 前置都绿了才 `bash tools/install-phone-plugins.sh`（三计数：清单 2 / 推上去 2 / sha256 撞上 2，不等就停）。
>    **三条已知的不对等，先写在这免得照抄电脑那套**：手机上 profile 叫 **`web`**、电脑上叫 `desktop`；
>    宿主是 **npm 装的全局 dsh**、不是 Electron 的 asar/解包目录 ⇒ purge 那套「应用」在这台上改的是什么、能不能改，**未验**；
>    `dsh plugin` 只是把参数转给 **pnpm**，而**手机 chroot 里有没有 pnpm 我还没读到**（没有就得 `npm i -g pnpm`，那是往他机上装包 ⇒ **要他点头**）。
>    装完**不自动重启引擎**、**不替他点「应用」**；电脑上那发是 HMR 2 秒接住的，**手机这台没验过**，别默认不用重启。
> 5. **最大一块技术债，要他在场我才量**：重进 App 那段 **10–37 秒黑屏**（卡在哪一层还没定位，我不在自己身上猜）。
>    同场顺手可定的是**从插件页按返回**那条：我荐"先不动"（两条副作用都比现状贵）。
>    **今天傍晚从对比报告里捡回来一条更便宜的解（#44，见 RUNBOOK 14.26 二·2）**：那 10~37 秒里入口回的是 **503 纯文本**（`dsh-entry.js:354-358`），
>    壳拿到 503 只弹一屏"要他手动点重试"（`MainActivity.java:220-221`），那个 `retryLeft=2` 的看门狗管的是另一种症状（导航**根本没开始**）。
>    前人的解是"主框架失败重试 120 次 × 2.5 s"（要动 APK）；**我们这层有一个不用重装 APK 的走法** ——
>    让入口对"主帧导航"回一段带 `Refresh: 2` 的最小 HTML，`tools/deploy-entry.sh` 推上去就生效。**哪条走法归他挑，我今晚不自己动。**
> 6. **两件等他点头的（我一行都不动）**：① chroot 里 `apt install git`（GitHub 实测 22–26 KB/s，几十 MB ⇒ 十几分钟量级，这数没实测过、是推的）；
>    **今天他让手机上 dsh 自述那份《手机端情况.md》把这条范围撑大了**（它问要不要把 python3/git/gcc/ffmpeg 那批一起装上）——
>    别照它那串装，先用探针 33 第 6 节的 `apt-get -s` 把"新装包数 / Need to get MB / 多出多少盘"量成读数再让他挑；
>    ② 要不要把 `bash /root/doh-hosts.sh --check` 挂进那条开机服务做周期对账（钉进 hosts 的 IP **会漂**，不周期对账哪天 apt/npm 突然坏会误判成"网络又不通"）。
> 7. **电脑端只差他一眼**：开客户端 → 账号菜单 → 设置/插件，看 **Plugin Market** 那条在不在（层栈已含它，**不用重启、不用点应用**）。
>    不在别急着重装，把屏给我，我按 `bundles` 四项 + profile 里 `.dsh-market/` 那两个文件对。
>    同日两句要记：**官方自动更新会把 dsh-purge 的补丁冲掉**（更新完要重新点一次「应用」）；市场里**别顺手一键装东西**，想装哪件先报给我，我按 purge/market 这两轮的口径量一遍源码、出口、写盘动作。
> 8. **不需要他点头、我可以自己推进的**（他不在也能干，但只在项目内与只读探针范围内）：`/dev` 裸设备那条窟窿（#18，纯项目内 + 只读验收）、
>    以及"接线"这件事的**准备部分**。
>    **改口一条（对着 `scripts/dsh-entry.js` 复点出来的）**：以前我写"接沙箱 runner 要重启，重启会换 token、他手机里那条入场链接就废了"，
>    那是常驻入口之前的形状 —— 现在入口自己认新一代启动行、重换 cookie，壳里种的又是不含 token 的 base URL，
>    **引擎重启不再打断他那条链接**，代价只剩"重启那几秒正在跑的会话断掉"（细则见 RUNBOOK 14.11 四·2 与 14.25 一·1）。
>    但**重启本身要他在场**：他手机上那条对话正跑着，我不自己按 ⇒ 这条从"我可以自己推"挪到"等他点头"。
> 9. **新到的活（他给了一份 `手机端情况.md`，是让手机上的 dsh 自己写的"我什么干不了"，要我针对它给解法）**：
>    逐条对表已经写完（RUNBOOK 14.25），今晚插上手机就按探针复点，别拿它那份自述当事实、也别拿我这份对表当事实 ——
>    `bash tools/run-probe.sh scripts/dsh-envclaim-probe33.sh downloads/p33.txt`。
>    三件要对表的核心：**它说"内核禁止 namespace、只能完全访问"**（我们 14.11 量过 mount ns 是通的、runner 已建好并 34 项验收，只差没接线）；
>    **它说"不能开机自启"**（自启那条服务在位、是他选的 `.off`，且入口自己带重拉）；
>    **它报的 6 个"连不上"域名**（`github.com` 不通而 `codeload` 通这个形状，正是 14.22 那个解析病，不是墙）。
> 10. **两篇 REA 对比报告读完之后，今晚要做的不是"补清单"，是"别重复做"**（差分表 RUNBOOK 14.26）：
>    它那 66 条做法里 **20 条我们已经做了**、**真缺口只有 5 条**，另有 proot / bionic 那一整族**我们路线上本来就没有的债**。
>    五条缺口的账：#43（壳的 prompt 通道无来源校验 + 无崩溃处理器 + 前台服务要不要）＝**APK 改动，归 0.7，今晚那发 sha 不动**；
>    #44（503 后不自动重试）＝**有只改入口的路，见上面第 5 条**；#45（pidfile 无出生身份，杀之前不比"是不是我生的"）；
>    #46（机上缺一份常驻资产清单：现在只在"推的那一刻"撞 sha，"今天还是不是那份"答不了）。
>    **今晚只有一件是顺手能验的**：插上手机后跑一遍探针，把 #46 那份清单的期望字节与 sha 一次读出来（读操作，不写盘）。
> 11. **收尾**：读数写回 RUNBOOK 的下一节 + PROGRESS 改口，`downloads/` 里临时件清掉（**只删我自己建的**），报这轮流量，adb 关不关听他一句。
>    **红线不变**：不 reboot、不绕他锁屏、不替他点 App、凭证不进命令行进日志、他那批 `/data/local/tmp` 的东西与 KernelSU 配置一律不碰。
> 逐轮读数与过程在 [RUNBOOK.md](RUNBOOK.md) 的 14.x（14.21 = 模型那格，14.22 = 网络那格，14.23 = 图标那格，14.24 = 电脑上装 purge/market 那格，
> **14.24 末节 = 今晚往手机装那两发的准备**：语音由他自己结案、三处电脑↔手机不对等、两支脚本各自管什么，都写在那儿；
> **14.25 = 把他那份《手机端情况.md》逐条对表**：它判早了的三条、我们早建好但它看不见的三样、真补不上的三条、外加一条它自己没说但更该管的暴露面（`/phone` 里能看见各 App 数据目录）；
> **14.26 = 把 `docs/` 那两篇 REA 对比报告拿来跟我们自己的代码做差分**：20 条已做（逐条带我们自己的行号）、5 条真缺口、proot/bionic 那一族不适用、它警告别抄的六条一条都没踩。本文件只存结论与指向）。
> **动手前先过一遍 [AGENTS.md](AGENTS.md)** —— 那里是设备路径两套、报数怎么算才可信、哪些东西一律不碰、
> 以及已经踩过的坑（每条都真摔过一次，省得再摔）。

## 目标

把 DeepSeek Harness（`@deepseek-ai/dsh`）**完整跑在手机本机**，不连电脑、不依赖电脑上的任何服务；
推理走联网调 DeepSeek API；用法要「像桌面应用一样，能挂后台、能关掉、点开就能用」。
选定路线：root + 真 chroot 一个 Ubuntu 24.04 arm64（glibc），Web UI 绑 `127.0.0.1:3080`，KernelSU `service.d` 开机常驻。

## 验收标准（每条都要有读数，不接受"没报错"当通过）

1. 设备上是 glibc 环境、`node -v` 满足 dsh 引擎要求、`dsh --version` 出得来。
2. 两个平台敏感件（koffi / ripgrep）在设备上真加载、真跑得动，且不需要编译器。
3. `127.0.0.1:3080` 在听 **且** 页面 `HTTP=200`（端口在听 ≠ 页面能用）。
4. 手机自己出网到 `api.deepseek.com`，key 对了能回话。
5. 服务能被关掉、能重新点开、开机后自己在。
6. **桌面上有个能点开的软件**：进程看得见、能起能停能杀，不用连电脑。（这条是他 2026-10-19 深夜
   看完第一版之后新加的：原话「你这个跟我想的不一样……我连一个后台的那个进程我都看不到，我怎么给它关掉？
   ……就像你说的啊，装了一个能拿 root 的终端，然后直接用，就是在桌面一个软件一样，那这样才可以」）
7. **客户端不要是网页**：2026-10-20 凌晨他一句「网页太麻烦了，想办法整个桌面端」，
   于是这一层要的是一个真 App 图标 + 自己的窗口，不是"浏览器打开一个本地地址"。
   → **2026-10-20 晚按他后来那句"功能要齐全"重做了这一条的形状**（状态 17）：交付的是
   **真 App 图标 + 自己的窗口 + 不经过任何浏览器**（`com.zhl.dsh` 0.2），窗口里画的是**那个完整前端**。
   口径上"网页"与"网页内容"现在必须分开：他嫌的是"要开浏览器、要找地址、要粘 token"这套流程，
   不是嫌 HTML 本身 —— 那三家（DSHA / Soodok / woaiys3）装的也是同一套网页内容，
   这也是他那句"为什么他们装的 APK 功能和网页一样"的答案。16 MB 那个真·非网页的原生客户端
   按他的决定**留在桌面当对照**，两条并排，随时可比。

## 当前状态（2026-10-19，客户端那一层更新到 2026-10-20 晚，网络这一层查到底到 2026-10-21 凌晨）

1 ✅ `aarch64` / Ubuntu 24.04.5 / node v22.20.0 / npm 10.9.3 / dsh 0.2.1-rc.2
2 ✅ koffi require OK（预编译，盘上 cmake/gcc/g++/make/git/python3 全未装）、ripgrep 15.0.0
3 ✅ `:3080 LISTEN` + 带 token 走完 303→cookie→**200 / 37,512 B**；PWA `manifest.webmanifest` 200/255 B，`display=fullscreen`
4 ✅ 出网与鉴权链路已通（哑 key 拿到对岸的 `Authentication Fails ... request_id`，rx +27,347 B）。
   **2026-10-20 凌晨他自己把 key 填了**：盘上 `/root/.dsh/.credentials.yaml` 478 B（0600 明文），
   日志 `[llm-deepseek-account] model listing … loaded 2 model(s)`，原生客户端里真回话
   `2 回合 · 5 步 · 首字 844ms · 250 tok/s · 缓存 58%` ⇒ 这条从 ◐ 变 ✅，靠的是真回合读数不是页面出模型名。
5 ✅ 关/起重测通过：`--stop`→`--web` 换新 pid、页面仍 200；重启后旧 cookie 仍 200（cookie 30 天）；开机自启 `50-dsh.sh` 已装（当时 1,861 B / 0750）并手动 dry-run 出 `[skip]` — **真重启一次未验**
   （2026-10-20 晚：那份装载副本现为 `50-dsh.sh.off` **2,477 B** / 0750，内容与仓库逐字节相同 `4207c1bbf779…`，
   拉起的从裸引擎换成入口；**开关没拨、真重启仍未验**，见状态 17 与下一步第 5 条。
   入口这一层今晚**没有做过一次 `--entry-stop` 再 `--entry` 的循环** —— 它自述 `gen 1`、`运行 441 秒`，
   也就是从起到读数那一刻没重启过；停/起这一对只有自测里的哨兵与 SIGTERM 断言，真机上要验得连一次"重启后点开还能进"）
6 ✅ 装了 Termux 0.118.3（sha256 `72fdb596…e3a4e` 对上官方清单）+ `dsh-console.sh` 九项菜单，
   开图标即进。**2026-10-20 00:11 冷启真机验过**：菜单自己出现在屏幕上、十项齐全，选 1 打出
   `:3080 LISTEN / 32127 活着 / http=200 bytes=37512`，选 5 在 chroot 里读出 `aarch64 / v22.20.0 / 0.2.1-rc.2`。
   第一版静默失效的两个原因（app 上下文读不到 `/data/local/sh`；susfs4ksu 对未授权应用藏 `su`）
   都取到读数并改掉，`su` 那一步是他在 SukiSU Ultra 里勾上 Terminal 解决的
   （之后 `grep -ac com.termux /data/adb/ksu/.allowlist` = 1；我没手改那个二进制文件）。
   **自启已按他这句话拨到关**：`50-dsh.sh` → `50-dsh.sh.off`，菜单第 8 项一条命令拨回来。
7 ◐ 「浏览器里登不进」查到根因并补了钉：登录走 `platform.deepseek.com`（`protocol.js:98` 拼 `${origin}/auth-api/v0/dsh/…`），
   这域名原先不在 `/etc/hosts` → chroot 里 `getent` 空、`curl exit=6`，日志里 `sign-in failed errorCode:'no-response'` 就是它。
   补钉后 `/etc/hosts` 885→954 B。**2026-10-20 复核：那三条报错的时间戳(23:31:23)早于补钉(23:41:49)，是旧账**；
   用 node 自己从 chroot 里打 `auth_init` 读到 `POST=422 / GET=405`（55–214 ms，正常应答不是断连），
   PC Chrome 上点登录进到「等待登录」弹窗且日志零新增失败行 ⇒ 服务端这一跳已过。
   **只剩手机浏览器打开授权页并回跳那一跳没验**（见 8 与 RUNBOOK 13.2）。
8 ✅ 他 2026-10-20 那三句（网页端读不到手机 / 登不进 / 配不了 key）**三条成因各不相同，两条不在 dsh 身上**，
   逐条落到盘上读数与修法见 RUNBOOK §13。一句话版：
   ① 工作区原先确实是 chroot 自己的目录（`workspaceRoot = process.cwd()`），手机存储根本没挂进去 ——
   现已把 `/data/media/0` bind 到 `/phone` 并让服务从那里起步，实测顶层 116 条目、`@` 能列出 DCIM/Download；
   ② 手机预装的 HeyTap 浏览器内核低于 Chromium 116，缺 `AbortSignal.any`，页面永远卡在"正在加载工作区…"、
   选目录弹窗里直接红字报这个错 —— 已注入 polyfill（`tools/dsh-compat.js` + `dist/index.html` 加一行），
   注入后他手机上「手机存储」直接出现；③ key 的入口一直都有（开始使用 → 添加 API Key），
   用假 key 验到存进 `/root/.dsh/.credentials.yaml` 的 `refs.DEEPSEEK_API_KEY` 且模型立刻可选，
   假 key 已用 `scripts/dsh-clear-key.sh` 清掉，手机停在「开始使用」等他填真的。

9 ✅ **验收 6/7 这一层换了实现**：装的开源原生客户端 `com.labteto.dshmobile` v0.16.0
   （sorsama/deepseek-harness-mobile，MIT，APK 16,013,796 B，sha256 `8baa02db…b8df7584` 对上官方清单），
   走它自带的「本机」模式直连 `127.0.0.1:3080`，token 手粘一次。验到：登进去直接是他那个历史会话、
   真跑过回合（见状态 4）、`工作区 /phone` 能逐层翻他内部存储真实目录（backups/BaiduNetdisk/DCIM/Documents…）、
   `am force-stop` → `am start` 冷启复点**没有再要 token**。全程零出网（除了它自己那发模型列表，走的是他手机已有的账号链路）。
10 ⚠ **同一内核上 `workspace-write` 跑不了 Bash，真因已取死**：`zcat /proc/config.gz` 读到
   `# CONFIG_USER_NS is not set` + `# CONFIG_SECURITY_LANDLOCK is not set` ⇒ bwrap 建不出命名空间、Landlock 也没有。
   bubblewrap 0.9.0 我照它报错里那句"Install bubblewrap"装了并验（`Installed-Size 126`，仍不可用，不怪它）。
   同一次回合里 dsh 原生 `glob` 返回 17,056 B 正常 ⇒ **只有需要沙箱后端的工具（Bash 这一类）全灭，文件工具不受影响**。
   客户端随后弹「授予完全访问权限？……我了解其中的风险」，我按返回键退掉了 —— 但这种勾选不该我替他认。
   **可是 3 秒后它被批了**（会话记录 `approval/decided` `outcome: allowed-once`），紧接一条
   `command/run` `permission danger-full-access` `source.kind: user` ⇒ 那个会话现在停在
   `danger-full-access` + `approval/policy=never`（界面盾牌片读作 `Full access`）。
   **那 63 秒里我在用 `input tap` 盲操作他的屏幕，我说不清这一发是不是我碰的，所以按"可能是我"记账。**
   档位只写在那一个会话的 transcript 里（`profiles/` 下 grep 不到 preset）⇒ 新开会话回默认，又撞同一堵墙。
   要不要拨回 `Workspace Write`（代价：Bash 又全灭）—— **等他一句话，我不自己动**。
   **2026-10-20 他的裁决原话：「完全访问的档位肯定是要留的」**
   ⇒ 这条不再是悬着的决定，档位不动、`danger-full-access` 留着；我做的围堵 runner（状态 12）
   因此从"workspace-write 能不能用的前提"降级成"多一条更紧的可选路"，接不接线等他挑时间（代价=重启服务换 token）。

11 ✅ **社区两条 Termux 路线精读过**（`Vengisk/deepseek-harness-termux` 71★ 停在 8-26、
   `FunnelCakes/deepseek-harness-android` 46★ 停在 8-18，两份都 clone 到 `reference/gh-*` 逐文件读过，
   含 issue 区与它们引用的 `mexiaosqwq/dsh-web-mobile`、`qiannianhuanxiang/DSHA`、上游 Discussion #136/#248）。
   一句话结论：**他们 8 成补丁是在还 Bionic 的债，我们那 1.7 G rootfs 把这笔债买断了**
   （`/phone` 里 `ln` 实测 `LINK_EXIT=0` ⇒ 他们最大的 `link→rename` 补丁对我们多余）。
   更硬的一条：FunnelCakes issue #6 说 **0.2.x 起 `node-addon-require-builtin` 没有 android 平台包、
   Termux 上 `dsh web` 致命退出**，而我们设备上 `…-linux-arm64-gnu` 在位 ⇒ **0.2.x 之后 chroot 是唯一还跟得上主干的路**。
   拿回来的三件新东西（proot runner / `cordis.patch.yml` 持久档位 / `unshare -m` 在 chroot 外可用）逐条落在
   `reference/android-community-routes.md` 与 RUNBOOK 14.9。

12 ✅ **改②：权限档位钉住了，不用每开一个会话点胶囊**（细节与读数在 RUNBOOK 14.10）。
   机制是上游一个环境变量同时管住沙箱档位和审批策略：`dsh-base/cordis.patch.yml:246` 的 `mode` 和
   `:262` 的 approval `policy` 都读 `DSH_PERMISSION_MODE`。落地件 `config/dsh-env` → 设备
   `chroot:/root/.dsh-env`（0600 root:root，1,687 B，md5 `82bdb1f3…`，LF 无 CR），生效行只有一条
   `export DSH_PERMISSION_MODE=workspace-write`。验收 `scripts/dsh-verify-perm-mode.sh` T1–T7 全绿，
   其中 T4 是拿 `exec env | grep` 读"真正交给 `exec dsh web` 的那一份"，T7 复验当时在跑的服务没受影响。
   **顺带抓到自家一条隐患**：`dsh-chroot.sh:164` 那句 `. /root/.dsh-env` 早就在，但那个文件此前从未存在过
   （静默 no-op），所以"档位没法持久"那句旧话是错的。

13 ◐ **改①：`workspace-write` 的真围堵后端做出来了，围住了文件系统的写，还没接线**（RUNBOOK 14.11）。
   接线位是官方口子，不改一行源码：`dsh-sandbox-local` 的 `runnerCommand`（`lib/index.js:254/:311-321`）
   一旦非空，dsh 就把 `enforcement` 直接记成 `"full"`、**不探测不验证** ⇒ 围没围只能自己验。
   实现 `scripts/dsh-unshare-run.sh`（说 bwrap 方言，ns 内"先全冻 → 再叠可写 → 最后冻 / 根"，顺序反了会把工作区冻死，实测过）。
   验收 `scripts/verify-unshare-run.sh` + 探针 `scripts/dsh-sbx-probe.sh`：**34 PASS / 0 FAIL**
   （原文 `downloads/verify-runner-3.txt`），正反两个方向都有判据：/etc /usr /root 和 / 根上四发写不进且
   报错原文就是 `Read-only file system`（dsh 认的那条 denial 签名），同时 /phone 可写可读、/usr/bin 还能列 336 项、
   宿主 mountinfo 473→473、ns 外 /etc 照样可写。本轮抓到并改掉四个隐藏 bug，最重的一条：
   **自定义 runner 的失败签名不带退出码闸门**（`:320` 对比 windows-acl 的 `:239-242`），
   而每发都要打的降级提示原本和致命错误同前缀 ⇒ 一接线就会把每条命令判成"沙盒启动失败"、整档全废；
   现在致命用 `dsh-unshare-run:`、降级用 `dsh-unshare-run-notice:`，验收里有正反两条盯着这个。
   **◐ 而不是 ✅ 的原因有两条，都写死在 14.11 第四节**：① `/dev` 是原样不动的，里面 253 个裸分区节点
   对同为 uid 0 的被围命令敞着（bwrap 的 `--dev` 会给全新 tmpfs 只放七个 API 节点；这条路测到一半：
   tmpfs 挂得上、六个 mknod 成功、**null 那个失败**，而且失败后 `echo x > /dev/null` 是"在 tmpfs 上建了个
   叫 null 的普通文件"的假通过 —— 判据得改成 `test -c`）；② dsh 那一层的端到端一个字都没跑过（runner 由
   dsh spawn、`workspaceRoot` 由 policy 填进去），而这条要重启服务、会换他手机里那条入场链接。

14 ⚠ **交接时的设备状态，按"未复验"记**：最后一发诊断命令发出去时 ADB 掉了
   （`list of devices attached` 空 → `: no devices/emulators found`），所以**此刻 pid 10150 和 `:3080` 活不活着我没读到**。
   这一整轮我都没碰过那个服务（14.10 的验收是全程只读的），它在本轮开始时是活的。
   下次接上先跑 `sh /data/local/sh/dsh-chroot.sh --status` 再谈别的。
   同一次断线之前还有一发拿到的读数是 `chroot: /data/local/dsh-rootfs: Operation not permitted` +
   某个目录里 `chmod`/create 间歇 `Permission denied`（uid 一直是 0，`/data/local/tmp` 与 chroot 内同类操作全 rc=0）——
   **成因没查**，别把它读成"环境被我搞坏了"，也别读成"读不到"，下一条会话重发一遍就有分晓。
   → **2026-10-20 晚上重发过了，两半各有分晓**：① "环境没被我搞坏"这条成立 —— 重连后 `--status` 读到
   入口 pid 27993 / 引擎 pid 28023 / `:3080` 与 `:3081` 都 LISTEN / SELinux Enforcing，
   同一趟里对 chroot 内五处路径逐字节推件、校 sha256、改权限，**全部 rc=0**；
   ② 那一发的**最可能成因现在有我自己的复现**：`adb shell su -c "…"`（双引号）会被设备端再解析一次，
   而 `su -c 'a; b'` 里的**内层单引号会把外层那对截断** —— 截断之后 `;` 后面那些命令是 **uid 2000** 在跑，
   非 root 去 `chroot` 报的就是 `Operation not permitted`。本轮我在两处踩过同一个形状（一次报
   `chroot: /usr/local/lib: No such file`、一次报 `/data/local/dsh-rootfs/…: Permission denied`），
   改成 `S() { adb shell "su -c '$*'" }` 这一对引号后同一个命令立刻 rc=0。
   **但历史那一发我没法回放**，所以这条只能写"最可能成因已被同一形状的复现解释"，不能写"已查明"。

15 ✅ **他给的三家 APK 形态方案精读完，报告在 `reference/android-three-community-apps.md`**（2026-10-20，
   纯静态阅读 —— **一家都没跑过、没装 APK、没上机，运行时行为零读数**，这条口径写在报告第一段）。
   路线三种：DSHA 把 Ubuntu 24.04 rootfs **整个打进 APK**（273.10/345.27 MiB，`ManagedRuntimeAssets.java:126` 从
   asset 解；引擎 bxroot 默认、`Proroot` 已 `@Deprecated`）；Soodok 与 woaiys3 都是 bionic 裸跑，
   共同的钥匙是 **`targetSdk = 28` 豁免 Android 10+ 的 W^X**。**主菜只有一条**：沙箱这一项三家最终全落在
   `danger-full-access`，但表述质量差三档 —— DSHA 明说"工具审批≠强沙箱"（`ConfigStore.java:455` 默认值字面就是它）、
   Soodok 撞上我们那句一字不差的 `no sandbox backend usable on host` 之后把边界挪到 App 层
   （`EngineConfig.kt:406-414`）、**woaiys3 是谎报**：`get sandboxMode() { return "workspace-write"; }`
   而同一文件注释自己写着"**从不调用 ctx.sandbox**"（动机是 0.1.7 的 presets 构造时检查这个 getter、
   undefined 就抛"does not confine"）。**⇒ 状态 13 那条 runner 的价值不需要我再自夸，第三方样本把"为什么必须自己对外验"
   补全了：dsh 把 `sandboxMode`/`enforcement` 当可信声明用，报得比做的宽松会连审批链一起放松。**
   另有三条能马上用的、两条明确不抄（无障碍文案与能力不符、token 明文镜像到 `/sdcard`），
   以及一节"三家共同没解的那道题"（USER_NS/PID_NS/Landlock 全 not set ⇒ 他们的答案都是"所以不围"，
   我们的答案要求 root，这是**产品定位级分歧、不是技术分歧**）。RUNBOOK 记在 14.12。

16. **2026-10-20 13:26 他点名的两仓已到本地，且上游真历史也到了**（任务 #21，RUNBOOK 14.13，报告"第六·补"节）：
    `reference/gh-3p/` 里现在两份是**真 git 仓库**、两份带**上游历史**：
    `DSHA-main`（快照提交 `a92928f`，2,861 文件）+ `DSHA-hist`（**627 条提交**，2026-08-14 起，28 标签，1.6 M）、
    `deepseek-harness-android-app-main`（`72f553e`，266 文件）+ `dsh-android-app-hist`（**298 条提交**，2026-08-17 起，28 标签，481 K）。
    **两份历史的 HEAD 逐字等于两份快照出处提交里记的上游 sha**（`fe07a02…` / `98162a2…`）
    ⇒ "我读的到底是哪一版"这件事从此有硬答案：就是上游主干尖端。全程 Windows 侧，一次 adb 都没发。
    历史到手新读出五条（报告第六·补），其中**两条改了本文的口**：① woaiys3 的 `0.2.1-rc.2` 从【文】升到【史】
    （追版轨迹 0.1.7-rc.1 → 0.2.0-rc.2 → 0.2.1-rc.2 就写在提交消息里，`26be089` 2026-10-18），
    ④ **release 资产能在不改版号的情况下被就地替换**（`984ba3d` 自陈"资产已就地替换到同一 Release（未新建 Release）"，
    只把 versionCode 54→56）⇒ tag 名和版本号都不是内容指纹，这条让"我下的是 main 不是 APK"那条遗留问题**更硬不是更松**。
    另三条：DSHA 627 条里 **42 条标题就是 `chore(star-history):`**（带 Star History / 刷新曲线 / 星标曲线字样的并集 48）
    ⇒ **提交条数不能当迭代勤的证据**、
    DSHA 的 tag 命名三套混用不能当引擎版本台账（`v0.2.0-rc2` 比 `v0.2.1-build150` 还晚 8 天）、
    woaiys3 重复标题最多 37 条一模一样 —— 纪律比我初稿写的还松。
    **还有一条是"确认我们自己没踩"**：`984ba3d` 修的是他们 bash shim 拼字符串再未加引号展开导致
    **argv 被 word-split**（`bash -c 'touch probe1'` 变 `sh -c touch probe1`，"命令在第一个空格处被截断"）。
    这是 runner 的同型风险（上游按数组交命令进来）。查过我们的 `scripts/dsh-unshare-run.sh`：
    `:53-60` 全程数组 + `shift`、`:125` 单引号字面量 `exec "$@"`、`:142` `exec unshare "${UA[@]}" bash -c "$SCRIPT" dsh-unshare-run "$@"`
    ⇒ **边界不丢，不用抄**。但他们那份判据形状要抄：**5 条离线用例跑的是 APK 包里那份产物本身**（旧 shim 0/5、新 shim 5/5）
    —— "拿交付物本身跑判据"比我们只跑仓库脚本更硬，该并进 `scripts/verify-unshare-run.sh`。
    链路上唯一的败绩是**轴选错了一次**：按深度切的 `tools/clone-upstream.sh` 跑 4 分钟看出不可能落地
    （浅克隆那一包必须装下当前整棵树，而 DSHA 光三个 asset 就 20.4 MB 不可压缩字节，19~28 KB/s 折 13~18 分钟，
    镜像每 4~6 分钟必掐），换成按对象类型切的 `tools/fetch-history.sh`（`--filter=blob:none --no-checkout`）
    **9 秒 / 27 秒各成一仓**。两份脚本都留着，深度那份是"连历史 blob 也要"时的退路。

17. **2026-10-20 晚上这一轮：手机入口换成「常驻入口 + WebView 壳」，"点开就用"和"功能齐全"这两件事第一次同时成立**
    （任务 20，读数与三个坑全在 RUNBOOK 14.14）。形状：`scripts/dsh-entry.js` 落在 chroot
    `/usr/local/bin/dsh-entry.js`（47,151 B，只绑 127.0.0.1:3081），它起引擎、认那条一次性 token 的启动行、
    在内存里换成 30 天的 `dsh-auth-*` cookie；壳 App `com.zhl.dsh` 0.2（82,537 B，
    sha256 `65c49666…161e8b3`，**机上 base.apk 与本地产物逐字节相同**，两个读数同时贴才算数 ——
    我第一版写的是重打之前的旧构建 `b59834b0…`，按盘上读数改口，见 RUNBOOK 14.14）
    地址写死 `http://127.0.0.1:3081/`，首次加载前用 `CookieManager` 种入口口令。
    **端到端读数**：壳四行日志 `open-entry`（口令 43 字符，值不打印）→ `cookie accepted=true` →
    `page-start` → **`page-finish｜标题=DeepSeek Harness｜进度=100`**；入口侧 `injected=2`、`ws=18`、
    `injectMiss=0`、`up401=0`；门禁四种全对（无 cookie / 错 cookie / 错 Host 一律 **404**，裸 3080 **401**）；
    首页 42,740 B，内联在 `at=41`、上游第一段脚本 `at=254`、第一段 module `at=38534` ⇒ `order=ok`；
    盘上那份 `dist/index.html` 876 B、`grep -c data-dsh-entry-compat` = **0 行** ⇒ 上游文件没被我们改过。
    自测 **46 条判据，Windows 与机上交付物自身都是 46/46**，机上那条还拿真首页文件当用例。
    **他验收标准里"点开就能用"以前不成立的那半，现在有了机制**：token 一次性、服务一重启就换
    （旧遗留问题"点开就能用只在服务不重启时成立"），现在换 cookie 这件事由常驻入口做，
    壳与引擎之间永远是那条固定地址 ⇒ 这条从"要重新粘一次"变成"零输入"。
    **◐ 而不是 ✅ 只有一条**：屏幕此刻 `mWakefulness=Dozing` + `isKeyguardShowing=true` +
    `locksettings get-disabled=false`，截屏只有全黑，而**我不绕他的锁** —— 所以"画面上真的渲染对了"
    目前只有间接证据（标题、进度 100、ws 隧道、资源全 200），**要他解锁点一下图标才算验完**。
    **这轮顺手堵掉的一个口子**（不堵的话"点开就能用"会在真重启那天恰好失效）：自启脚本拉的是裸引擎 `--web`，
    App 指的是入口 `:3081` ⇒ 拨回自启并重启之后，图标点开停在「连不上工作台」。已改成入口在位就 `--entry`
    （读数与口径见 RUNBOOK 14.14 里那句"**一个只在真重启那天才会咬人的口子，今晚先堵了**"，**自启本身仍然是关的**）。

18. **2026-10-20 深夜这一轮：他验收时报的四个症状，两个查到根因并有前后差分，两个只有嫌疑**（读数全在 RUNBOOK 14.15）。
    他那四件事是：**屏幕上头一大片代码** / **迟钝不丝滑容易卡** / **点了插件不跳转、要自己返回** /
    **选工作区目录报「…PICK…LIST… HTTP 403」，并问我"是不是没连 API，要不要你连上实测"**。
    **先答那句"要不要连 API"：不用。** 这个 403 发生在我们自己的入口与裸引擎之间那一跳，跟外网、跟模型、
    跟登录都无关（key 是他早就填好的那条，状态 4 的真回合读数照旧）。
    ① **代码墙**根因是 HTML 解析规则：`<script>` 里看到**第一个** `</script` 就闭合，不看它在不在注释里 ——
    我们那份 polyfill 的注释（`tools/dsh-compat.js:8`）原样写着 `<script src=…>`，于是内联段在字节 533 处被提前
    关掉，剩下 2.6 KB 源码成了页面上的可见文字。修法：内联前过一次 `escapeForInline()`。
    判据不是复用"顺序 ok"那条（它管不了这件事，我一开始就是被它骗过去的）：新加**"我们这段之后紧跟的是不是标签"**
    与**"摘掉所有 script/style 之后正文还剩多少可见文字"**两条，机上读到
    `紧跟 "<base href=…"`、`正文可见文本 16 字符`、`元素完整性=ok at=2805 完整`。
    ② **403** 根因是引擎的同源栅栏：`dsh-client-connection` 的 `isTrustedApiRequest()` 要求 **Origin 的 host:port
    逐字等于 Host 头**，否则 403；入口把 Host 改成 `:3080` 而 WebView 的 Origin 是 `:3081` ⇒ 凡带 Origin 全死，
    导航请求不带 Origin 所以页面能开 —— 和他"页面在、一点就 403"完全对得上。
    裸引擎差分：`Origin=:3081 ⇒ 403` / `Origin=:3080 ⇒ 401` / `不带 ⇒ 401`；穿过入口 A/B：修前
    `带 Origin ⇒ 403`，修后 `⇒ 404`（404 是放行，我那条路径本就不存在）。修法是转发时连 Origin/Referer 一起换，
    HTTP 与 upgrade 隧道**两处**都换（上游 `stream-server.js` 里那个 `rejectRemoteStreamUpgrade(..., 403)`
    是同一族问题在隧道上的另一个入口，只修 HTTP 会留一条更隐蔽的）。自测 4f 三条 + 隧道两条盯住它。
    **这条里我没做到的**：选择器真正走的那条 HTTP 路径没找到（盘上是 RPC 方法名 `directoryPicker/list|pick|createDirectory`，
    我猜的 `POST /api/rpc` 带不带 Origin 都 404）⇒ **"他真点一次的那条路径"仍然没量到**，只能等他点一下，
    由入口新加的**非 2xx 环（方法 + 路径 + 码 + UA + Origin）**接住它。
    → **已被状态 19 那趟真用付清**：环里读到 `POST /api/directoryPicker/list → 200 6ms UA=App`，
    这句里"还没量到"不再成立（读数与原委见 RUNBOOK 14.16）。
    ③ **迟钝**：App 那侧四条静态资源全是 157–163 ms、且与体积无关，curl 串行重打同一批是 **2.1–4.6 ms**
    （940 KB 那条 4.4 ms）⇒ **入口与引擎不是瓶颈**，那 160 ms 在 WebView 并发或引擎每请求固定开销那一侧，
    我还没分开，所以这条**不许读成已解决**；SSE/WS 隧道**没做背压**，是嫌疑不是读数。
    ④ **点了插件没反应**：`setSupportMultipleWindows` 默认 false 时 Chromium **静默丢掉** `target=_blank`/`window.open`
    —— 形状对得上，所以按这条改了壳（APK 0.3 开多窗口 + `onCreateWindow` 把同域 URL 收回当前 WebView），
    另补 `OVER_SCROLL_NEVER`（边界回弹是"不丝滑"最常见那条）与深色 `windowBackground`（冷启动白闪）。
    **一条都没在屏幕上验过**；`enableOnBackInvokedCallback="false"` 那处我按事实/推断分开写：`dumpsys` 读到
    `targetSdk=35` 是事实，"所以返回键不生效"是推断，要他真按一次。
    **两件顺手做掉的**：入口的**停 → 再起循环第一次真跑**（`[ok] :3080 已关闭（等了 1s）` ⇒ 补掉 14.14 遗留 ④；
    同时抓到 `--entry-stop` 那条假警报的成因 —— 引擎是子进程要一两秒才退，发完 SIGTERM 立刻查端口必然谎报，
    同一条链路上 `pgrep -f` 还会匹配到自己那条 `su -c` 包装 ⇒ 这台机判活只认端口）；
    **上游目录真还原成"我们没动过"**：`dist/index.html` 825 B、md5 读到 `5a1bf510…` 与仓库那份原样**逐字节相同**，
    `assets/dsh-compat.js` 删掉，打过补丁那版备份在 `/root/.dsh/index.html.patched-876.bak`（md5 `50c5ee3f…`）
    ⇒ **14.14 我那句"盘上 index.html 一个字节没改"当时是错的**（它带着更早一轮的 51 B），现在才成立，已在原处改口。
    **产物的指纹这次两边都读**：装机 base.apk 与本地产物都 86,632 B、sha256 都 `84ce80fafe1747d9…`，`versionName=0.3`；
    入口 64,791 B，机上跑交付物自身 **59/59**，Windows 同 59/59。
    （我这一轮先前记的装机 sha `2511557f…` 是没按盘读数写下来的，已改掉 —— 和"46 条判据"那个旧数一起，
    说明**凡是抄自己上轮结论的数字都要重读一遍**。）
    **◐ 而不是 ✅ 还是那一条，而且现在更明确**：手机锁着（`mWakefulness=Dozing` 时截屏全黑、DevTools attach 超时，
    新写的 `scripts/dsh-cdp.js` 因此直接拒绝在那状态下跑），而**我不绕他的锁**。他回来只要做三下：
    点开图标（看那片代码真没了）、点一次插件再按返回、点一次选目录 —— 之后我读屏 + 读非 2xx 环，这四条里
    ②③④ 才有真机结论。任务 22 仍挂着。
    → **状态 19 他真机用了，这三下付清两下**（截图 + 选目录那条 HTTP 路径），剩**插件**与**返回键**两下；
    所以 ① 代码墙从"只有字节级证明"变成"屏幕上看过"，② 403 从"修好了但没读数"变成"200 6ms"，
    ③ 迟钝这一条他说"非常好"，但那 160 ms 还没归因、背压还没做 ⇒ **③ 仍不许读成已解决**，④ 仍欠两下。
    这一轮另外从他自己的流量里挖出两个真 bug 并修掉，见下面状态 19。

19. **2026-10-20 深夜的下一格：他真机用了，发了一条消息，回「使用体验非常好，没什么大毛病」**（读数全在 RUNBOOK 14.16）。
    这条的价值不在那句好评，在于**他这一用把我上一轮欠的读数一次性付清了**，而且**从我自己写的非 2xx 环里挖出了两个真 bug**：
    ① **选择器那条路的真路径量到了**：`POST /api/directoryPicker/list → 200 用时 6ms UA=App`，
    同环里还有 `POST /api/session/prompt → 200 34ms App`，`req=122`、`ws=5` ⇒ 上一轮那句"我猜的 `POST /api/rpc`
    带不带 Origin 都 404、所以选择器已通还没有读数"**作废**，路径与状态码都在盘上，14.15 里那条箭头就地改口。
    ② **屏幕上那片代码也没了**：`downloads/dsh-shot-2040.png`（363,580 B）是这套东西第一张真渲染截图 ——
    深色前端整页、没有漏出来的源码。状态 17/18 那两条"◐ 只因为我不绕他的锁"到此才有✅的一半。
    ③ **他这一用抓到两个我的 bug**（都在 upgrade 隧道上，`ws=5` 与 `最后错误 ws upgrade 连不上上游` 是那两条的现场）：
    **其一**，`socket.setTimeout()` 是**空闲**计时（每来一个字节重新上弦），我却当成**握手**计时用 —— 一条安静待着的
    健康隧道到点被我自己的计时器掐死，还把"我们自己掐的"报成"连不上上游"。修法：上游首字节一到就 `up.setTimeout(0)`
    摘表，只在"首字节始终没来"时保留 8 s 上限（新增 `CFG.wsHandshakeMs`，可用 `DSH_ENTRY_WS_HANDSHAKE_MS` 调）。
    **其二**，`up.on('error')` 挂在 `net.connect` 回调**里面** ⇒ 连不上的那些 socket 在回调执行前就已经报错，
    没人接 ⇒ **整个入口进程被 unhandled 'error' 打死**（上游拒接 = 入口自杀）。修法：把 `close/error` 处理器移到
    回调外。崩溃形状单独量过：`Unhandled 'error' event / ECONNREFUSED 127.0.0.1:1` 退出码 **1**，
    同一段挪到外面后 `外层接住了：ECONNREFUSED` 退出码 **0**。
    ④ **新判据一组**（自测 **59 → 62**）：块 **6b** 三条 —— 空闲 4 倍窗口不断、卡住的上游在握手窗口内被杀且
    `最后错误` 含"握手"二字、被拒的 upgrade **不打死入口**（后面 `GET /__origin-echo` 仍 200）。
    Windows 与机上交付物**都是 62/62**；把 `up.setTimeout(0)` 那行删掉的降级副本 **61/1**，红的正是空闲那条
    ⇒ 这三条判据真的在管事，不是恒真。
    → **这三个数（59/62/61）全是推出来的，不是读出来的，状态 20 那轮按"合计"行改口**：本轮交付物实测
    **Windows 与机上都是 58 条 PASS 58 / FAIL 0**（含状态 20 新加的一条），倒推 6b 加进去之前是 57。
    6b 那三条**确实在输出里逐条 PASS**（错的只是汇总数），降级版那条"红的是空闲"也是真读到的。
    立新口径：**判据条数只许抄脚本自己打的"合计 N 条"那一行**，`R()` 调用点数（65）也不等于跑出来的条数。入口 64,791 → **69,556 B** 已部署并重启（`[ok] :3080 已关闭（等了 1s）`
    ⇒ 引擎 pid 18741，`auth cookie 有，已用 1 秒`，`req=6 ws=0 最后错误（无）`）。
    **仍然欠着的只剩两条，都在壳那一侧、要他在场点**：插件那一下跳不跳（`onCreateWindow` 还没在屏幕上验过）、
    返回键退不退得回去（`targetSdk=35` 是事实，"所以返回键不生效"仍是推断）。
    **14.15 记的两条没做也照旧**：App 侧那 ~160 ms 还没归因（curl 串行同批 2–5 ms 只证明入口与引擎不是瓶颈），
    SSE/WS 隧道**背压还没做** —— 他现在说"不迟钝"，所以这条从"症状"降级成"已知没做的工程项"，但**不许读成已解决**。

20. **2026-10-20 深夜再下一格：他说"体验非常好"之后我又读了一遍流水，里面有一簇 40 秒的请求；本轮不修，只把它做成下次一读就能定侧的事**（读数全在 RUNBOOK 14.17）。
    那六条是 `modelCatalog 40407ms` / `account/getUnnotifiedBonuses 40164` / `getProfile 40160` / `getBalance 40160`
    / `credentials/describe 40079` / `commands/list 40698`，**全 200、全是 App 那侧发出来的**；同一条
    `credentials/describe` 在同一个环里还有 4/5/12/17ms ⇒ **不是那个接口天生慢，是有一批被整体按住了一下**。
    **这条必须和他那句"不迟钝"同时成立**，否则两个人在读不同的东西。能同时成立的只有两种故事，**修法相反**：
    甲＝引擎那侧慢（冷启/等出网）⇒ 动引擎或出网链路；乙＝他那一侧被 Android 冻结节流 ⇒ 动保活，或者根本别管。
    **先把甲按下去一半**：新增只读探针 `scripts/dsh-slow-probe.sh`（1,381 B，口令只走 `curl -K -` 的 stdin，
    不进 argv、不打出来），在 chroot 里**绕过 WebView、照样穿过入口 :3081** 串行重打四条端点各 2–3 次 ⇒
    **全是 3–6 ms，一次 40 秒都没复现**。要说准：这证明的是"**这些接口此刻**不慢"，不是"引擎任何时刻都不慢"，
    所以我打完时引擎已经热了、那一簇发生在刚重启的窗口 ⇒ 甲只是没复现，**没排除**；反而 `entry.log` 里重启后各有一条
    `存活探测失败：probe timeout`（入口自己那发 4 秒 `/health`，`dsh-entry.js:227`）说明**引擎刚起来那段确实有过不应答的窗口**。
    **本轮真正的改动是让这两种能分开**：流水那行的耗时在"上游回头"那一刻结算，甲乙在旧格式下一模一样 ⇒
    加一列 **`体Nms`＝入口把请求体收完的时刻**（`req.on('end')`，只加监听不碰数据流，没收到显示"未收完"）。
    下次再出现 40 秒：**`体40000ms` ⇒ 乙**，**`体1ms` 而总 40 秒 ⇒ 甲**。部署后实测格式真的两列都打出来了
    （`POST /api/account/getBalance → 200 3ms 探针 体1ms`）。入口 69,556 → **70,487 B**（机上 md5
    `4af378c95d0bab8a9bf0681e50095cc1`，与 `/data/local/tmp` 暂存件相同 ⇒ 推上去没走样），停/起一轮
    （入口 pid 17611、引擎 pid 17637、`auth cookie 有，已用 7 秒`、`req=15 ws=0 最后错误（无）`），
    自测**合计 58 条 PASS 58 / FAIL 0**（Windows 与机上交付物各 58；上一轮那个"62"见状态 19 原地的改口）。
    **机上临时件跑完当场删并复点**（chroot 里那份从外面 `ls` 会被 SELinux 拦成 Permission denied ⇒ 进 chroot 复点）。
    **本轮没修任何东西**，做的是把"该修哪一侧"变成一次读数就能定的事；欠的照旧：插件、返回键、160 ms、背压。

21. **2026-10-20 深夜最后一格：他提了三件手感事（全屏 / 返回键要问一句 / 重进后黑屏），壳出到 0.4**（读数在 RUNBOOK 14.18）。
    ① **先答他那句"左边那一列按钮是不是 Harness 自己的"** —— 是，用 CDP 直接问页面 DOM 读回 `aria-label`：
    `打开侧边栏 / 新建会话 / 全局面板 / 插件 / 自动化任务 / 添加工作区 / 搜索会话 / 账号菜单`，
    全是前端的按钮；**我这个壳在屏幕上没有任何自己的东西**（只有窗口底色和那屏"连不上工作台"说明页）。
    顺带读出他此刻档位是**工作区内修改**，不是 `danger-full-access`。
    ② **全屏做完了并且拍屏验过**：`downloads/dsh-shot-04-fullscreen.png` 里状态栏整条不见了、
    底部手势条也收了（边缘滑一下临时露出、一两秒自己收回去）。走运行时 `WindowInsetsController`，
    不用 manifest 那条 `windowFullscreen`（管不到导航栏，且 targetSdk 35 上旧旗标不保证生效）。
    ③ **返回键按他说的三层写了**（能退就先退一层 → 首页上弹"退出工作台？"→ 确认屏还开着时再按才真退），
    `onKeyDown` 与 `onBackPressed` 两个口都接到同一个函数，哪条真被走到由 `shell.log` 那行 `back ::` 说。
    **这一条今天没有读数**：我发 `input keyevent 4` 的时候手机已经睡了（截屏拉回来是锁屏 AOD，
    `21:47:02 DOZE → OFF`），那一发打在锁屏上没进 Activity，日志只留了一条 `onPause` ——
    **立新判据：给手机发输入事件之前必须先读 `mWakefulness`**，`dsh-cdp.js` 本来就拒绝在 Dozing 跑，
    我这次用裸 adb 把这条规矩绕过去了。他 0.3 那句"侧滑一下就到桌面"本身就是行为读数，
    顺带把 14.15 挂着那条推断解开：**返回这一发到得了 Activity**，缺的只是"问一下"那一层。
    ④ **那 37 秒黑屏量出来了，而且不是他估的那个量级**：`21:32:39.226` 已 loadUrl → `21:33:16.853` 才 page-start
    = **37.6 秒**（他估 10 秒是"黑到看见东西"）。同一段路我干净冷启量两次：**40ms / 83ms** 到 page-start、
    639ms / 657ms 到 page-finish ⇒ **偶发，不是每次都慢**，所以"修好了"这三个字我没资格说。
    0.4 做的是让它下次犯的时候**看得出来且不至于黑那么久**：生命周期全打进日志、
    `loadUrl` 后 5 秒没等到 `onPageStarted` 就自己重试（最多两次、重试前清缓存、每次记 `stall ::`）、
    删掉 `web.pauseTimers()`（**进程级**冻结，Activity 换实例时旧 onPause 可能排到新 onResume 之后 ⇒ 没人解冻；
    **这条是嫌疑不是结论**）。`ACCESS_NETWORK_STATE` 那条网上流传的权限**没加**，两次 40–83ms 就是不加的理由。
    ⑤ **产物**：壳源码 34,647 → **42,773 B**（模板）、versionCode **4** / versionName **0.4**、
    APK **86,632 B**、sha256 `b20c6ddfa38d53b4…`，机上 base.apk 逐字节同串、`dumpsys` 读到 `versionCode=4`。
    **体积和 0.3 撞巧一样**（86,632 B）⇒ 记一条：认版本只认 sha 与 versionName，别拿字节数当版本。
    装机是 `-r` 覆盖（同一把自签 key），他那个 16 MB 对照客户端没动。

22. **2026-10-20 深夜再收一格：他把返回键那两件事退回给我，壳出到 0.5**（读数在 RUNBOOK 14.19）。
    ① **他指出的毛病是真的，而且一条读数就能说完**：`history.length` 在他这个页面上**恒为 1**（hash 也一直是空）
    ⇒ 0.4 那句 `web.canGoBack()` 是条**死层**，永远走不进去，所以侧边栏摊开盖住主界面时照样弹确认。
    这不是他按错，是我把"页面能退一层"当成了活的第一层。
    ② **"侧边栏摊开"壳在 Java 这边看不见，只能问页面**：CDP 量到那一列收起 56 px、摊开 **280 px（屏宽 360 CSS px 的 78%）**，
    摊开那屏截在 `downloads/dsh-shot-05-sidebar-expanded.png`，跟他描述的同一件事。
    判据用**看得见的 `aria-label`**（收起时只有「打开侧边栏」可见，摊开时换成「收起侧边栏」）——
    坑在于**两颗按钮两种状态下都在 DOM 里**，只按 label 找会在没摊开时也"关"一把。
    壳里 `OVERLAY_JS` 按 `退出全屏 → 收起右侧边栏 → 收起侧边栏` 找第一颗看得见的点掉，正反各当场验过。
    ③ **那张要点「留下/退出」的 AlertDialog 整段删了**，换成底部一枚自消散的浮层
    （15sp 白字"再按一次返回，退出工作台"、圆角 21dp、淡入 120ms / 停 1500ms / 淡出 300ms、1800ms 内再按一下才退）。
    `setContentView(web)` 外面套了一层 `FrameLayout` 给它当落点（不画进页面 DOM）。
    位置装完看过一眼才定：第一版 96dp 压在输入框上，改 40dp 落到框下面。
    ④ **机上真按的三条读数**（这轮每次发 `input keyevent` 前都先读到 `mWakefulness=Awake`，0.4 那轮的失手没重犯）：
    摊开时按一下 → 列宽 280→**56**、焦点没走、**没飘提示**（22:19:41.976 那行 `back ::`）；
    聊天页上按一下 → 飘提示、焦点还在 App；隔 609ms 再按一下 → `onPause`/`onDestroy`、焦点交回 launcher；
    提示飘出等 3 秒 → 两张截屏逐像素差只剩那枚浮层那块 1004×178 的区域 ⇒ **它自己消散了**。
    ⑤ **有一件他要的这轮没做，因为页面不给路**：点开「插件」之后侧边栏**并不摊开**（列宽仍 56），
    而从插件页回聊天只有两条路 —— `新建会话`（真建一个会话）或摊开侧边栏点某条会话（换掉他当前那条），
    再点一次「插件」和发 `Escape` 都切不回去（都实测了）。**要不要接受这两条副作用之一，等他点头。**
    ⑥ **没验到的写清楚**：`退出全屏`/`收起右侧边栏` 那两条分支只见过节点存在、**没造出可见状态**；
    800ms 兜底这轮一次没触发（回调实测 1ms 内回来）；浮层"不吃点击"是按 Android 分发规则写的，
    **没真在提示飘着时点一下页面验**，最坏是这 1.8 秒点不动。
    ⑦ **产物**：壳源码 42,773 → **52,266 B**（模板，展开 52,297 B）、versionCode **5** / versionName **0.5**、
    APK **90,729 B**。同版本号装了**两发**：`d5432fa67c826301…`（96dp 那发）与 `251282084c113dcc…`（40dp，**机上现在这发**）
    ⇒ `dumpsys` 两回都只读到 `versionName=0.5`，**版本号区分不了这两发，只有 sha 能**。
    又拿**没改过一个字的同一份源码**重打第三遍：字节数仍是 90,729，**sha 却变成 `09920b6af77f7c3a…`**
    ⇒ 这套打包**不是逐字节可复现**的，**sha 认的是"哪一次打包"而不是"哪一版代码"**：sha 相同能证明代码没变，
    sha 不同**不能**证明代码变了。盘上 `app/out/` 那发现在是第三遍，**他手机上装的是 `25128208…`**，代码相同、字节不同。
    入口(:3081)与引擎(:3080)这轮没重启，他那个 16 MB 对照客户端没动，`/data/local/tmp` 一个字节没碰，零出网。

全程 SELinux **Enforcing**，没 setenforce 过。rootfs 1.7 G。

## 文件变更

### 状态 12–25 那十几格搬到了 `PROGRESS-archived.md`（原文一字未改）

> 搬的是原文件第 463–799 行（**337 行 / 39,668 B**），也就是 `## 文件变更` 节里 **2026-10-20 那一轮（状态 12/13）到 2026-10-21 凌晨（状态 25）** 那十几格。
> **→ 就地改口（铁律 12：文档里的计数要能当场重跑）**：这行第一版写的是"39,667 B"，差的是段尾那一个换行 —— 复算口径
> `python -c "import subprocess;o=subprocess.run(['git','show','HEAD:PROGRESS.md'],capture_output=True).stdout.decode('utf-8').split('\\n');print(len(('\\n'.join(o[462:799])+'\\n').encode()))"` → 39,668；归档件 40,036 B 里其余 368 B 是那 5 行说明头。
> **现役从状态 26 起**（下面第一格就是），最新一格是**状态 33**（32 与 33 都写在 `## 文件变更` 末尾）；要往前翻就 `grep -n "状态 22" PROGRESS-archived.md` 这类直接跳。
> **→ 深夜复点（写状态 33 那一刻取的，`downloads/p56.txt`）**：手机又插上了（`adb devices` 回 `〈序列号·已遮〉 device`），引擎 **21363** / 入口 **17611** 都没换过代、dpkg 411、hosts 29 行、机上兼容层 9,793 B（md5 `268f90ad…` 未变）。
> 归档里那十几格是：2026-10-20 这一轮（状态 12/13，改②与改①）新增/改；2026-10-20 追加这一轮（状态 15，三家对比调研）新增/改；2026-10-20 追加（他点名的两仓落到本地，任务 #21）；2026-10-20 晚上这一轮（状态 17，手机入口换成常驻入口 ；2026-10-20 这一轮；2026-10-20 凌晨这一轮；2026-10-20 同一晚的追读；2026-10-20 深夜这一轮（状态 18，他验收那四个症状）；2026-10-20 深夜再下一轮（状态 19，他真机用了一趟）；2026-10-20 深夜最后一格（状态 20，那簇 40 秒的请求；2026-10-20 深夜收尾（状态 21，他提的三件手感事 → 壳；2026-10-20 深夜再收一格（状态 22，他把返回键那两件事退；2026-10-20 深夜再收一格（状态 23，他一句"先去看那两个；2026-10-21 凌晨那一格（状态 24，他一句"提交，然后下模；2026-10-21 凌晨再收一格（状态 25，他那句"以后难道全得。

> **这份文件为什么留这些、搬那些**：他 10-21 晚那句"PROGRESS 和 RUNBOOK 太长了，读的时候消耗你太多上下文"。规矩没变 —— 只搬不改，`## 当前状态`、`## 下一步`、`## 遗留问题` 三节**一行没动**。
**2026-10-21 早上收一格（状态 26，他嫌我做的图标不好看、自己放了三张进 `app/icon/` → 换掉了）**
他放进来三张，都是 **2048×2048**：`1792543659137.png` **3,961,128 B**（蓝发小女孩抱鲸鱼，**满幅无白角**）、
`share_1792543567542.png` **3,823,912 B**（同一张画，但导出成了圆角方 + 白底）、
`share_1792543661221.png` **3,309,864 B**（另一张画：深蓝底的鲸鱼剪影 + 女孩侧影，同样圆角方 + 白底）。
旧 `icon-src.png` 是 **1024×1024 / 711,195 B**，四角 RGB **250–252** —— 也就是说它自己就带着白角，
桌面上看到的那四个白点不是启动器的锅，是图里烤进去的。
判据先量：满幅那张四角 `A=255`、RGB `11,36,90 / 16,37,90 / 69,148,227 / 66,150,223`（上暗下亮的渐变），没有一处白。
剪影那张四角是纯 `255,255,255`，我写了 `app/tools/SquareIcon.java` 把白角补上（边界漫填 + 往里吃 3 px 抗锯齿 + 从暗像素往里灌色），
补完四角 `10,21,49 / 11,22,52 / 24,30,54 / 35,46,76`，**但 1024 和 192 下都看得见一圈很淡的圆角接缝**
（补色是取边界内侧的颜色，和原图那层径向渐变对不齐）—— 所以没选它。前两版还试错过两次，都写在那个工具的注释里（一次没设亮度下限、一次下限 150 太松）。
选定 **`1792543659137.png`** 那张满幅的：不补角就没接缝，48 px 下蓝发+鲸鱼仍认得出。
落地：`icon-src.png` 换成它（sha256 `7b0ab834…`，旧图没删，`git show HEAD:./app/icon/icon-src.png` 随时取回），
`sh app/icon.sh` 出五档 **5,971 / 12,319 / 20,965 / 43,477 / 74,897 B**（上机前的切图，不在机上），
`bash app/build.sh` 出 **`app/out/dsh-app.apk` 152,167 B、sha256 `17c280ac482263ac94f1592e99471047408ff26c8dbdfebeca2a9140bfc964cb`**；
包里的五档图标是 **aapt2 重压过**的（4,501 / 9,533 / 16,034 / 33,745 / 56,997 B，文件 sha 跟源图不同），
所以验收没比文件 sha，而是把五张从包里解出来**逐像素**跟 `app/res/` 比 —— 五档全 `SAME`。版本号没动（0.6 / code 6），改的只是图案。
文档：RUNBOOK 加 14.23 整节（1,979 → **2,009 行**，186,630 B），本文件加状态 26 与这段；AGENTS.md 加"图标要喂满幅方图"
与"验包里的图标不能比文件 sha"两条坑，以及切图那条命令（106 → 112 行）。
**这轮没做**：没装机（手机不在电脑上）、没提交（他没让）、没给 C 那套渐变外推补角、没做 adaptive icon / 主题图标、没动运行中的三层。

**2026-10-21 上午（状态 27，他要 dsh-purge：上游已删库，我把三个版本都拉下来按内容比了一遍）**
先记边界：这是**破甲/越狱类插件**，我按他的要求拉了源码、做了只读对比，但**不替他编写或改写绕过模型拒绝的提示词**，
装不装、装在哪仍由他定；本轮**没有安装、没有运行、没有碰手机**。
上游 `YuJunZhiXue/dsh-purge` 现在 `api.github.com/repos/...` 回 **404**（账号 200、18 个公开仓里没有它）= 删库；
npm 侧 npmmirror 回 `NOT_FOUND dsh-purge`、`registry.npmjs.org` 直连 8 秒超时 ⇒ 版本只能按 git 标签说。
本地三份都在 `reference/gh-3p/`（只读参照区）：`dsh-purge`（mmparko 全量镜像，HEAD `033e6bd`、231 提交、72 个 `v*` 标签最高 `v1.1.71`、109 文件、8,698,843 B，
含上游最后提交标签 `upstream-snapshot-6c1d638` 与 issue/PR 存档分支 `upstream-archive`）、`dsh-purge-021rc2`（evilevil，`8d5bcff`、7 提交、`1.1.72-dsh021rc2.4`、125 文件、6,439,706 B）、
`dsh-purge-lanjing`（LanJinGod，`8023a74`、4 提交、`1.1.73+dsh0.2.1`、112 文件、5,495,326 B）。
**两个后辈与上游无共同祖先**（`git merge-base` 空）⇒ 不能按 commit 比，只能按内容比；差异清单存 `downloads/purge-cmp/{rc2,lanj}-{namestatus,stat}.txt`。
同口径（`lib` + `bin` + `client.js` + `cordis.patch.yml`）：**rc2 = 25 个文件 +2,941/−1,238 行**，**lanj = 9 个文件 +1,536/−142 行**。
方向不同：**rc2 做的是 0.2.1-rc.2 宿主适配**（`dshTarget` 改 0.2.1-rc.2、`identity.js` 加 `cwdVariableSupported()` 修 `unknown prompt variable "{{cwd}}"`、
`core.js` 补丁 #40 补 0.2.1 形状 pattern、`desktop.js` 的 `repairOfficialCliAfterUnpack` 改 async、`extract-asar.js` 的 `HOST_SYNC` 补 6 个 fd 方法、红队预设 `toolFilter` 移除）；
**lanj 做的是"写完≠生效"**（新增 `lib/patch-effect.js` 讲 `app.asar` 优先加载、`bin` 的 `--swap`、`selftest/smoke-swap/smoke-idle` 三个自检脚本、1.1.73 修 idle watcher 撞官方重启标记不撤锁）。
两条要留神的读数：**lanj 的 `dshTarget` 仍写 0.2.0-rc.2**（版本号却叫 `1.1.73+dsh0.2.1`），且 `lib/core.js` 里 rc2 那个 `fold-complete` 标记 **0 处** ⇒ 它没做 0.2.1 补丁语义；
仓库里还提交了个 `.backup-cwdfix-212947/`（改前的 cordis/core/identity 三份备份）没收尾。rc2 则把默认注入文本以 `.en.md` 29,657 / `.md.bak` 24,687 / `.zh.md` 25,902 B 三份提交进仓（base 与 lanj 的 `lib/` 里没有这个文件，我只量字节没读内容）。
按代码路径推（**未在他机上实测**）：他那台是 chroot 里 npm 装的 `dsh web` 0.2.1-rc.2，lanj 那套 asar/`--swap`/idle watcher 是 Windows 桌面端的东西，用不上；rc2 修的 `{{cwd}}` 崩与补丁 #40 不命中才是 0.2.1 宿主共有的 ⇒ 真要试，**rc2 那条线**。
**同轮改口（他一句"那 lanjing 那个下载的清理掉"）**：`dsh-purge-lanjing` 已删（删前 `du -sb` = 5,495,326 B，删后 `[ -e ]` 复点"已无"），
base 镜像仓里的 `lanj` 远端与 `refs/remotes/lanj/*` 一并 `git remote remove` 掉并 `git gc --prune=now`（`.git` 8,698,366 → **8,182,818 B**）；
现在 `reference/gh-3p/` 下只剩 `dsh-purge`（上游全量镜像）与 `dsh-purge-021rc2` 两份。上面那段关于 lanj 的对比结论**按当时读数继续成立**，
比对文本留在 `downloads/purge-cmp/lanj-{namestatus,stat}.txt`，要看它改了什么不必重新下载，读这两份文本即可。

**同轮再补（他一句"把这个插件装到本机的 deepseekharness 里，电脑端"）**
先量环境：注册表 `HKCU/HKLM\...\Uninstall` 读到 **DeepSeek Harness 0.2.1-rc.2**，安装位 `D:\program files\DeepSeek`；
CLI 不在 PATH，实际入口是 `D:\program files\DeepSeek\resources\runtime\cli\bin\dsh.cmd`（243 B，内部用 `ELECTRON_RUN_AS_NODE=1` 把主 EXE 当 node 跑 `app.asar\dsh\...\dsh-desktop-host\lib\cli.js`），
`--version` 回 `0.2.1-rc.2`；`~/.dsh/profiles/desktop` 在位（`bundles` 原本只有 `dsh-base` + `dsh-web-app`）；系统 node v24.18.0 / pnpm 11.28.5。
装的是 **rc2 那条线**：`npm pack` 出 `dsh-purge-1.1.72-dsh021rc2.4.tgz` **2,026,964 B / 113 文件 / sha256 `7f43fb87…`**，
`dsh plugin --profile desktop add <tgz>` 走 pnpm，**零下载**（它只有 peer `@deepseek-ai/cordis`，而 workspace 里 `autoInstallPeers: false`），843 ms 完成。
**装完我把依赖改指到稳定路径**：第一发 `file:` 指向我项目 `downloads/`（会被清理掉 ⇒ 将来重装就断），
所以复制一份到 `D:\tools\dsh-plugins\`（sha 同 `7f43fb87…`）再 add 一次，现在 profile 的 `dependencies.dsh-purge = file:D:/tools/dsh-plugins/...tgz`，
`bundles` 三项含 `dsh-purge`，`node_modules/dsh-purge` 4,088,639 B、版本 `1.1.72-dsh021rc2.4`、`dshTarget 0.2.1-rc.2`（与他装的宿主版本一致）。
**宿主一个字节没改**：`resources\app` 不存在、`*.dshpurge.bak` 计数 0、`app.asar` 仍是 182,794,869 B / sha 前缀 `47874618BF5B3011` / mtime 10-17 17:20。
⇒ 插件只是"装进列表"，**真正改提示词与补丁的那一步是 App 里它自己设置页上的「应用」**，按它 README 的写法这一步不该由助手代点，留给他。
**没做**：没点「应用」、没重启他的 App、没动 `D:\program files\DeepSeek` 任何文件、没碰手机端。

**同轮再补（2026-10-21 午后，状态 28：他接着要 dsh-market，同样装进电脑上那台）**
先定"哪一个是它"：GitHub 搜 `dsh-market` 回 284 个仓，同名两家 —— `dsh-market/dsh-market`（**7,811 星**、MIT、TypeScript、homepage `dshmarket.com`、100 个标签里最高 `v1.66.45`、`size` 19,977 KB）与
`2BingLing/dsh-market`（162 星、license `NOASSERTION`、homepage `dsh.market`、**0 标签**、150,843 KB）。**选前者**。
npm 侧一条要看清：**包名不是 `dsh-market` 而是 `dshmarket`**（npmmirror 上 `dsh-market` 回 `NOT_FOUND`，`dshmarket` 在：184 个版本、`latest 1.66.45`、维护者 `fkysly`、首发 08-14、末版 10-20 17:40）。

取件与校验（三个口径对上才算数）：npmmirror tarball **1,350,488 B**；它的 **sha512 base64 与 registry 的 `integrity` 逐字符相同**、
**sha1 与 registry 的 `shasum` `f58d87e0…` 相同**、**解出来 186 个文件 / 4,893,393 B 与 registry `unpackedSize` 相等**；sha256 `5267bdcdf6…`。
按状态 27 那条规矩复制到稳定路径 `D:\tools\dsh-plugins\dshmarket-1.66.45.tgz` 再装（`file:` 依赖是把路径写进配置的，指我 `downloads/` 就等于埋雷）。
`dsh plugin --profile desktop add <tgz>` → pnpm **`Packages: +4`、downloaded 3、1.5 s、rc=0**。装后读数：`package.json` 两条 `dependencies`、`bundles` 四项含 `dshmarket`、
`node_modules` 里 `dshmarket` **4,893,393 B / 186 文件**（与解包字节同）、外加 `undici 7.30.1` / `js-yaml 4.3.2` / `argparse 2.0.1`（`.modules.yaml` 的 `hoistedLocations` 四条）。
**它要的对端都在宿主层**（静态读数，`resources/app/dsh/node_modules/@deepseek-ai/`）：`cordis 4.0.5`（peer 要 `^4.0.1` ✓）、`dsh-settings 0.2.1-rc.2` ✓、`schemastery 3.18.5` ✓，
它 `dsh.client.inject` 点名的 `dsh-client-locale` / `dsh-client-ui-settings` / `dsh-client-ui-theme` 三件**全在、都是 0.2.1-rc.2**；profile 里没有 `cordis`（`autoInstallPeers: false`，由宿主提供 —— 与 dsh-purge 同形状，**属推断、未实测**）。

**这一发不需要点「应用」**：它自带的 `cordis.patch.yml` 只有 125 B、内容就一条 `insert: id: dsh-market / name: dshmarket` ⇒ 插进 profile 的层栈，**不写宿主一个字节**。
~~**要的是重启客户端**：层栈在启动时组合，而我装的时候客户端在跑（`Get-Process -Name 'DeepSeek*'` = **5 个进程**）~~
→ **这句当场被读数推翻了**：装完 **2 秒**后 profile 根下就冒出了 `.dsh-market/`（`state.json` 78 B + `log.ndjson` 124 B，mtime 14:30:37，我的 `add` 落盘是 14:30:35），
   日志那一行是 `{"at":"2026-10-21T06:30:37.986Z","event":"region","detail":"no region on record; network check chose china"}`（**这时刻按 UTC 读 = 北京 14:30:37**）
   ⇒ **宿主 HMR 真的把新 bundle 重组合进去了，不用重启**；而且它自己跑了网络探域并选了 `china`，这既是"真加载了"也是"出口通"的正证。
   还欠的只剩**眼睛那一验**：设置页里那条 **Plugin Market** 在不在，我不能替他看。
   （复测时客户端已经不在跑了：`Get-Process -Name 'DeepSeek*'` = **0** —— 他自己退了；`package.json` mtime 仍是 14:30:35、`bundles` 四项、`cordis.patch.yml` 仍是 10-18 的 829 B ⇒ **应用退出没把我的写入冲掉**。）

**顺手把状态 27 那句"宿主一个字节没改"改口（他自己点了「应用」）**：14:31 复测与 14:1x 我报"没改"之间变了 ——
`resources\app` **存在**（**453 M**、目录 mtime 14:18）、`*.dshpurge.bak` **57 份**、`dsh.cmd` 变 **562 B / mtime 14:18**（原 243 B 留成 `dsh.cmd.dsh-purge.bak`），
里面多了三段 `if not exist` 回退（`app.asar` → `app.asar.unpacked` → `app`）、`~/.dsh/dsh-purge/` 状态目录 14:18。
**`app.asar` 本身仍未动**：182,794,869 B / sha 前缀 `47874618BF5B3011` / mtime 10-17 17:20:50 ⇒ purge 走的是"**解包目录优先加载**"，原 asar 当底不动。
（`~/.dsh/prompt-inject.md` 24,455 B、`~/.dsh/redteam/` 14:13 是他点完之后的东西，**我只量字节、没读内容**。）

它自己的两条规矩（从装进去的代码里读的，将来我或他走 CLI 都要知道）：`lib/official-desktop.js` 的 `OFFICIAL_PAGE_HINT` 明写
"**官方桌面客户端的这个插件操作需要在「设置 → 插件」里完成；市场无法通过命令行修改桌面端的 profile**" ⇒ 市场进去之后的**一键安装走宿主自带的插件管理器**，不是我这条 pnpm；
同一文件还记着宿主的 `checkGithubConnection` **5 秒不通就拒装、且不碰 profile**（拒装 ≠ 写坏了，别当事故处理）。
它会连的外域（grep `lib`+`client`+`locale` 里的 URL、只按主机名归类）：`github.com` 37、`raw.githubusercontent.com` 6、`codeload.github.com` 6、`bitbucket.org` 4、`cdn.jsdelivr.net` 2、
`awesome-dsh-plugin.com` 2、`gist.github.com` 2、`registry.npmjs.org`、`mirrors.cloud.tencent.com` 2、`images.weserv.nl`、`gitlab.com`；`dav.example(.com)` / `proxy` / `host` / `evil.com` 那几条是示例与测试串，不是出口。
不留凭证有正证：`lib/http.js:125` 注释写明转发进宿主前剥掉 `cookie` 与 `sec-fetch-site`、`lib/gist.js:32` "host-configured token (**never read from disk**)"、仓里带 `scripts/check-web-auth-capture.mjs` 当测试；
反面一条要知道：WebDAV 备份会把**他填的账号密码**转成 Basic 头发出去（`lib/backup.js:239`）—— 只在他自己去开那个功能时。

**代价与选择交给他**：这是"能往同一个 profile 里一键装任意第三方插件"的一扇门，装进来的每一件都以 dsh 的权限跑；
现在是 `file:` 钉死 1.66.45 ⇒ **它的自更新不会生效**（README 写明"从归档装的只认自己那条源，不会拿同名目录条目当更新"，所以不会静默换包，但也不会提示升级）。
要自动更新就按名字装（`dsh plugin --profile desktop add dshmarket`，源是他 npm 配的 npmmirror），退法同为 `remove dshmarket`。
仓也照 purge 的规矩落了一份只读参照：`reference/gh-3p/dsh-market`（`gh-proxy.com` 全量 clone）—— HEAD `eee2281`、**1,011 提交 / 173 标签 / 21 条远端分支 / 271 个跟踪文件 / 31,331,959 B（`.git` 21,847,895 B）**。
**装的那发不是 HEAD**：`v1.66.45` = `eb72f89`，HEAD 之上还多 3 个提交，其中一条是 `Fix market self-install target (#890)` ⇒ 在市场上遇到"装它自己"的怪事，先记住**盘上是 1.66.45，main 上没这条**。
它仓里 `SECURITY.md` 自述（**它的说法，不是我验的**）："runs shell commands (`pnpm`, `dsh plugin`, `git`) against the user's own profile, **by design**"、"holds **no credentials of its own**"、"只有 npm 最新版受修"。
**没做**：没重启他的客户端、没在 App 里替他点任何按钮、没读 purge 注入文本与 `redteam/` 的内容、没装目录里的任何第三方插件、没碰手机端、没提交。


**2026-10-21 傍晚（状态 29：手机在场的一整轮 —— 新图标装机、两发插件进手机 `web` profile、把"要不要重启引擎"判死、他那份自述的复点读数补齐）**

过程、表格与全部读数在 **RUNBOOK 14.27**（八小节），这里只留接班要用的五句：

1. **新图标那发 APK 已在机上**：`versionName 0.6` / `lastUpdateTime=2026-10-21 17:48:31` / 机上 `base.apk` **152,167 B**，
   与本地 `app/out/dsh-app.apk` **sha256 逐字节相同**（`17c280ac482263ac…bfc964cb`）⇒ 状态 26 那句"APK 重打但还没装进手机"作废。
   为此新写 `tools/install-apk.sh`：**只装机、不重打**（`build.sh --install` 做不到这条），`--verify` 那支分支一个字节不写。
   **欠他一眼**：解锁点图标看桌面满幅图（白角没了），顺带把"点开就能用"补成 ✅。
2. **两发插件真进机了**：三个计数 **2 / 2 / 2**（清单 / 推上去 / sha256 撞上），`bundles` **5→7**，`node_modules` 可见 5 条 + `.pnpm` 1 条，
   `dsh plugin --profile web list` **rc=0**，**与电脑那台完全同形**；体积 store 14 M / profile 13 M / `/root/.dsh` 232→**245 M**。
   第一发跑崩在我自己的 push 上（`adb.exe` 看不见 git-bash 的 `/d/tools/…`），症状正是铁律 2 那个形状（撞上 **0** ⇒ 脚本自己停了、没往下装）。
   `pnpm` 前置没卡住 —— 机上早有 `/usr/local/bin/pnpm` 12.14.0（standalone ELF），14.24 预留的"要不要往他机上装 pnpm"作废。
3. **"手机上要不要重启引擎"判死了：不用**。四条独立读数在 14.27 二，最关键一记是**引擎 fd 23 那个 inotify 正在听 `package.json`**（ino 十进制 1614790）；
   我第一发把 inotify 的 inode 当十进制比，报了个假的"命中 0 个"，**差点得出反结论**（fdinfo 里是十六进制）。
   反面证据也留了：入口 `entry.out` 从 10-20 13:32:48 起没长过一行（68 行），所以"日志里看到它接住了"这条指望不上，得看 inode 与写盘时刻。
4. **purge 在他机上写的东西已如实报给他**（`~/.dsh/redteam/` 231 K 25 件 + `.agent-presets/redteam/` 47 K（含 `agent.cordis.yml` 28,456 B）+ `prompt-inject.md` **24,455 B**，
   内容是那套"去掉拒绝"的人设文本，我读了开头 12 行才敢这么写）；**手机上没有 `applied.json`** ⇒ 注入到底挂没挂上会话**在我这侧看不见**，
   留/删、点不点「应用」都归他，我不替他点。
5. **他那份《手机端情况.md》的复点读数补齐了**（探针 33 于 北京 17:57（= UTC 09:57） 跑过，`downloads/p33.txt`，摘要在 14.27 七）：dpkg **119** 而非它自述 124；
   `python3/git/gcc/ffmpeg/sqlite3/wget/rsync/unzip/file/tmux` 逐个复点**全无**；`/phone` 暴露面 **135（含隐藏，`ls -1A`）/ 533 / 16**（`--status` 那格 117 是不含隐藏的口径，同源不同口径，见 14.27 九）；
   `apt-get -s` 三档 **291 / 440 / 35** 个新包；`binder hwbinder vndbinder binderfs ashmem kgsl-3d0 dri` **都在**（#42 那条"没挂 /system ≠ 没接口"现在有硬证）。
   顺带把我自己那四个读数坑（`%F` 当 mtime、`/proc/<pid>` 目录 mtime 当出生、inotify 进制、`--dump-config` 其实会写 `cordis.yml`）写进 14.27 四，
   收尾那发（探针 39，`p39.txt` + 修好重跑的 `p40.txt`）又抓出四个（stat 第 22 字段减法用反、`ss` 计数与列表不同源打脸、`ls -l long-iso` 列号、`df` 的 Avail 是 `$4`）——
   **两发的结论：引擎空转 45 秒出网 200 B 级、回环 82 KB、`/root/.dsh` 零写**。
   还有一件当场对清的：`/phone` 顶层条目今晚同时有三个数（探针 33 的 **135**、`--status` 的 **117**、我随手一条命令回的 **"没这个目录"**），
   对完是**前两个同一挂载的两种口径**（`ls -1A` 含隐藏 / `ls -1` 不含，差 **18** 个点开头的条目）、**第三个是我的引号塌了、命令被宿主 shell 求值**（铁律 1 今晚第二次现身，症状从"假读数"变成"文件凭空没了"）；
   引擎自己的 `mountinfo` 里那行与入口逐字符相同，`cwd=/phone`、`PWD=/phone`、`HOME=/root` ⇒ "工作区就是整机存储根"这句现在有进程自己的读数（14.27 九，探针 40 / `p41.txt`）。

**没做**：没重启引擎、没点「应用」、没在 App 里替他操作插件页；没删 `/root/dsh-plugins/` 那两份 tarball（`file:` 引用还指着它们）；
没动 `runnerCommand`、权限档位、hosts 名单、自启；没重建 APK；机上那 8 份 `.sh` 一份没删（2 份常驻 + 6 份一次性，分类与 **md5 对账 8/8 与本地逐字节相同**见 14.27 八，
对账全文 `downloads/root-sh-residual-md5-20261021.txt` ⇒ 删哪一份都还得回来，等他一句话）；
黑屏那条（#25 / 顺序 ⑤）没量 —— 要他在场。**等他三件事**：① 开 App 看那三处（插件页 / 侧栏市场入口 / 预设列表）；② purge 要不要点「应用」；③ 红队模式那套预设留不留。

**2026-10-21 晚（状态 30：他回来报的两个症状 —— 图标还是旧的、市场一直转圈；市场两处根因都改了并当场换代引擎，图标那条判成启动器缓存、归他重放）**

过程、表与全部读数在 **RUNBOOK 14.28**，这里只留接班要用的六句：

1. **"DSH 工作台"就是手机上那发壳**（`app/res/values/strings.xml` 的 `app_name`），不是电脑上的快捷方式 —— 这句先定下来，后面两问才有主语。
2. **图标：装机件是新的，旧的是 launcher 的缓存**。`base.apk` 152,167 B / sha `17c280ac…` 逐字节正证在状态 29，像素级也验过那几发 `ic_launcher.png` 是满幅那张；
   缓存按**包名 + versionCode** 认，这发还是 `versionCode 6` ⇒ 同版本号 `pm install -r` 也不会换位图。**他挑了"先重放一次图标"**（删了拖回去，零改动），
   所以我**没重打 APK、没抬 versionCode、没重装** —— 那发 152,167 B 的 sha 仍然有效，别为了这张图作废它。
3. **市场的根因是两条叠在一起**（探针 42 `downloads/p42.txt`）：`state.json` 里 `"region":"global"` **早已落盘、且源码只在没定过时探一次**（定了永不重探）＋
   那个区的目录地址 `awesome-dsh-plugin.com` / `registry.npmjs.org` **在 `/etc/hosts` 那 27 条里一条都没有** ⇒ 每次 4 发全 `fetch failed`，`log.ndjson` 里 18 条 `fetch failed (42s, 4 attempts)` 就是这么来的。
   同时排掉一整族假设：`:3080` 上 `/dsh-market/*` 回 **401 got=156B**（插件挂着）、`:3081` 同路径回 **404**（那是门禁按设计挡的，`dsh-entry.js:484-485`），`bundles` 里 `dshmarket` + `dshmarket-1.66.45.tgz` 都在。
   这台机的病根还是 14.22 那个"**UDP 53 废**、解析要靠钉"，不是墙。
4. **两处都改了**（他原话「两个都弄，当场重启」）：`tools/doh-hosts.sh` 的钉名单加 `awesome-dsh-plugin.com` → `--sync` **新增 1 条 / 本来就在 14 / 问不到 0**，钉进 `185.199.108.153`（备份 `/root/.dsh/hosts.bak.20261021-105919`，sha 撞了才写）；
   `config/dsh-env` 加 `export DSHM_NPM_MIRROR=https://registry.npmmirror.com`，并用**新写的 `tools/deploy-env.sh`** 推上机 —— **这文件在机上一直是 10-20 那发 1,687 B，14.25 那次模板改动从没推上去过**（⇒ 现在 `--check` 能主动量出这种不对等），换完 **4,738 B / md5 `61f6d030…` / 600 root:root**，备份 `/root/.dsh/dsh-env.bak.20261021-110024`
   （→ 19:17 为补注释又推一发：现在 **5,567 B / md5 `cd1ed15c…`**，`--check` 回"逐字节相同"；多的全是注释、两个 export 没动 ⇒ **不用为此再重启**）。
   为什么这两处就够、**不点"中国大陆"也能加载**：`lib/regions.js:136-144` 的 `catalogSourcesFor()` 会给每个区**追加一条"本区 registry 上的目录包"**，而 `:233-236` 用 `DSHM_NPM_MIRROR` 覆盖那个 registry ⇒ global 区第二源从死掉的 `registry.npmjs.org` 变成 npmmirror（探针 43：`code=200`、**2,582,974 B / 1.53 s**，且带版本当缓存校验）。
5. **当场重启走的是最小那条**：只 `SIGTERM` 引擎、入口不动（`dsh-entry.js:168-177` 自己 2 s backoff 重拉）。探针 44 读数：cmdline 含 `dsh web` 的进程数 **= 1** 才杀 → **14851 ⇒ 21363，10 秒**；
   `entry.log` 五行连成一条正证（退出 `code=0` → `2000ms 后重拉` → 第 4 代 spawn 命令原文里那句 `. /root/.dsh-env` → 认到启动行 → `凭据已换取 … http=303`）⇒ **他那条入场链接与 cookie 都没废**；
   新引擎 `/proc/21363/environ`：**`DSHM_` 键计数 = 1**、`DSH_PERMISSION_MODE` 在、`cwd=/phone`、入口仍是 17611；换代后路由仍 401；**不带 `--resolve`** 复点 `plugins.json` HEAD `200 dns=0.000286s`（dns≈0 = 命中 hosts）。
6. **这一格没闭环**：`log.ndjson` 到探针 44 仍停在 **6,606 B / 10:40:50Z（北京 18:40:50）** —— 换代后**没人再请求过目录**，"没报错"不等于修好了。
   **19:17:54 探针 45 复点：还是一字节没长**（20 行、`info` 2 / `warn` 18 / `catalog fetch failed` 4），引擎 21363 活着 575 秒、入口未动、hosts 生效行数 27→**28**（多的正是 `awesome-dsh-plugin.com`）⇒ 确认他还没打开过页面。
   **要他亲手**：在 App 里打开插件市场。好了我补最后一格；还转圈，`log.ndjson` 必写新行，按新行继续查。
   留一笔账给他挑：global 第一源是**无缓存的 4 MB**，把设置里「下载区域」改成**中国大陆**才会先走那条 2.58 MB 且按版本缓存的 npm 路径（代价：china 那套把 GitHub raw/git 改走 `gh-proxy`）——**那一下我不替他点**。

我自己在这轮抓出的五个坑（都就地改了，全文在 14.28 末）：`who()` 用脚本开头的 uptime 快照 ⇒ 新进程报"**活着 -3 秒**"（年龄必须现读 `/proc/uptime`）；
基线 `/tmp/net_full_before.txt` 存在 **PC 的 git-bash /tmp**、探针查的是**手机 chroot 的 /tmp** ⇒ 差集只能在 PC 上算（基线已抄进 `downloads/net-full-20261021-185612.txt`）；
`lo` 的 rx 与 tx **同值**（一批字节两侧各计一次）⇒ 全表求和会双计、且它不是出网；流量 awk 又把列用错（`$4−$2`，正确 `rx=$2 tx=$10`）；
**探针第一版 `grep '^export' | cut -d= -f2` 打的是等号右边的值**，与注释里"只列键名"正好相反 —— `/root/.dsh-env` 以后放 key 就会被写进读数文件 ⇒ 改成 `sed` 取键名，**凭证纪律要靠代码兜，不能靠我记得**。

**这轮流量**（同一基线开两个窗口，差集在 PC 上算）：**18:56:12→19:08:16 出网 1,340,503 B ≈ 1.28 MiB**（`wlan0` 1,329,971、蜂窝 10,532）；**18:56:12→19:17:54 出网 1,592,898 B ≈ 1.52 MiB**（`wlan0` 1,557,964、蜂窝 34,934）⇒ **几乎全走 WiFi**；
两窗口之间那 252,395 B 我这边对不上号（那 9 分半只做了 adb 侧部署与一发只读探针，都不该走出网）⇒ 照实写**归属未定**。
**没下过那 4 MB 正文、也没下过目录包**（HEAD 与元数据而已）。基线两份都在 `downloads/net-full-20261021-185612.txt` / `-191754.txt`（抽名字别用 `[a-z0-9_.]`，`wifi-aware0` 会被丢掉，用 `[^ ]+` 并比名字集合）。
退回：hosts 与 env 各一条 `--revert`（还原后都要再重启一次引擎才吃得进）。

**2026-10-21 晚（状态 31：他一句"提交到我的 GitHub 仓库里去，权限是私密的"—— 本目录成了独立 git 仓，历史从工作区仓 split 过来；过程中我把父仓分支挪走了一次并还原）**

1. **先查现状才发现"从来没上传过"**：`D:\mycode` 那仓 `git remote -v` **回空**（227 发全在本地），他账号 `zhl110` 下 8 个库是**一项目一库**的形状、**没有 dsh-mobile**。
   所以他那句"提交到我的 GitHub 仓库"在这台机上不是一句"push 就行"，而是要**新建库**——新建就是对外且不好撤的动作，我先问三件事（内容边界 / 本地管法 / 那份《手机端情况.md》要不要出去），他点的是"只推 dsh-mobile + 本目录建独立仓 + 一起推"。
2. **推前体检（私密库也是给未来的一次泄露）**：待推 **143** 个文件（109 已跟踪 + 34 新增 **15.2 MB**，最大四张是图标 PNG）。凭证式样扫下来**零命中**；
   **→ 这句当场改口**：`git add --dry-run` 那 34 行是**新增 23 + 修改 11**（它对已跟踪的修改件也打 `add '…'`），我拿它去加 109 得出"143"是**重叠计数**。暂存后的真数：**本仓跟踪 132 件**、合计 **15.7 MB**、**新增 23 件 = 11,302,343 B**（全文与列语义在 RUNBOOK 14.29）。
   唯一一条像 cookie 的在 `scripts/dsh-entry.js:625`，读上下文是**自测假上游的 fixture**（`dsh-auth-aaaa…`），不是真凭据；`entry.key` 只以路径出现；`downloads/`（全部读数）在库外。
   LFS 那对读数也顺手取了：git 配了 `filter.lfs.*` 但 PNG 的 `check-attr filter` 回 **unspecified**、`cat-file` 打出来是 `\211PNG…IHDR` 真字节 ⇒ 库里**没有指针件**，GitHub 那边不占 LFS 配额。
3. **历史留住了**：父仓 `git subtree split --prefix=dsh-mobile -b dsh-mobile-split` 跑 **49 秒** ⇒ `8e8706f6`，对账三件事全等（**5** 发 / **109** 个文件 / 名字+blob 号双列 `diff` **空输出**）。
   本目录 `git init` + `fetch` + `update-ref`/`symbolic-ref` + **`reset --mixed`（不带 --hard）** ⇒ 工作树零改动，今晚那批未提交件原样在（**改 11 / 未跟踪 22**，与父仓对本项目的读数一字不差）。
4. **我自己那一发（全文在 RUNBOOK 14.29）**：`git init -q --initialBranch=main .` —— **选项名少一个连字符** ⇒ init 报错退出，
   而我那串命令用 `;` 串着 ⇒ 后面四条 git 命令在"本目录还没有 `.git`"的状态下**往上找到父仓**，四条全打在 `D:\mycode` 上：它的 `main` 被我挪到 split 那一发、index 被 reset 成 split 的树。
   发现是因为我照常读数，`rev-list --count HEAD` 回 **5** 而不是 227。靠 `reflog` 找回 `175bcfbf` 还原（还原后读数：`HEAD=175bcfbf`、`rev-list=227`、`remote` 空、本项目脏项 11/22、全仓脏项 577）。
   **盘上一个字节没动**（`reset --mixed` 只改 index），代价只有"他暂存区里若有东西会被打回未暂存"。两条规矩进铁律 9：**建仓这类"前一条不成功后一条就不该跑"的动作用 `&&` 串并留 `[ok]` 回声**；**挪分支前先把 `rev-parse HEAD` 与 `rev-list --count HEAD` 打出来**，别到时候只能靠会过期的 reflog。
5. **从现在起每轮两个仓都要提交**：`dsh-mobile` 这个仓对应 GitHub（`origin` = 私密库 `zhl110/dsh-mobile`），`D:\mycode` 照旧跟踪同一批文件（与他另一项目 `agent-hub` 同形状）。
   pathspec 在两处写法不同：父仓里要带 `dsh-mobile/` 前缀，本目录里写 `./<路径>`；动手前 `git rev-parse --show-toplevel` 认一遍人在哪个仓。
6. **验收认三个数**：本地 `rev-list --count HEAD` = 远端 `rev-list --count origin/main`；远端树文件数 = 本地 `git ls-files | wc -l`；`gh repo view --json visibility` 回 **PRIVATE**。

**没做**：没推整个工作区（他其他项目的东西一个字节都没出去）；没动 `agent-hub`；没删父仓那发 `dsh-mobile-split` 分支（留着当还原依据，他说删我就删）；没配 SSH；`gh` 用的还是那把 fine-grained PAT。
**本轮提交号**：本目录仓填到 **`bf18e73`** 为止（本轮全部工作 + 状态 30 那格成果 + 这两发事故记录）；再往后的号不往文档里抄（抄了就得再来一发、又没号可填），要认当场取：本仓 `git log --oneline -3`、父仓 `git -C /d/mycode log --oneline -1 -- dsh-mobile`。
**推送验收三个数全等（北京 19:40）**：本地 `rev-list` **6** = 远端 `origin/main` **6**；本地 `ls-files` **132** = 远端 `ls-tree -r` **132**；两边 HEAD 同号 `bf18e733be…2919`；`gh` 回 **`private=true` / `PRIVATE`**。
远端树里 `downloads/`、`reference/gh-3p/`、`app/out/` 各 **0** 条；`lfs/objects` 回 Not Found ⇒ 无 LFS。全文读数与那发"PAT 能不能建库"的答案在 **RUNBOOK 14.29** 末。
**等他一件事**：`github.com/zhl110/dsh-mobile` 这形状是不是他要的（要不要 README、`reference/` 要不要也带上）——这条只能他眼睛看。

**2026-10-21 晚（状态 32：他一句话塞来四件事并排了序 —— 文档先瘦身、git/python3 那件解决掉、横屏左侧栏要能划、《手机端情况.md》逐条清；过程与全部读数在 RUNBOOK 14.30）**

1. **文档按他排的序先做**：`RUNBOOK.md` **284,811 B** 拆成现役 **106,666 B** + `RUNBOOK-archived.md` **185,927 B**（只搬不改，多的 7,782 B 全是新加的说明头与索引表）；
   `PROGRESS.md` 里状态 12–25 那 **337 行 / 39,668 B** 搬进 `PROGRESS-archived.md`（**40,036 B**）。冷启动的三处撞空（"见 10.11 / 13.4"、"最新三格在文件变更节里"）都补了指向，
   `AGENTS.md` 加了四条文档纪律。我自己另开了一发冷启动自测，挑出六条，其中**两处已就地改掉**（缺空行、39,667→39,668 的字节数），其余是拆分之前就存在的老账。
2. **B 类装齐了**：四批 `apt-get install -y --no-install-recommends` 全 rc=0，**每批三个数各数各的都等**（pip 4/4、编译 54/54、媒体文档 201/201、杂项 11/11），
   dpkg **141 → 411**，`df -k /` 多 **1,010 MiB**；**20 个命令名逐个 `command -v` 全在位**（gcc 13.3.0 / ffmpeg 6.1.1 / ImageMagick 6.9.12-98 / pdftoppm 24.02.0 / sqlite3 3.45.1 / tmux 3.4…）。
   剩下要不要装的我把数给他了：文档办公 84、OCR 6、语言栈 61、容器 29 个包 —— **一个都没装**，`apt-get clean` 也没跑（缓存 242 MB / 324 个 .deb）。
   **服务没被带倒**：引擎 pid 前后都是 **21363**、入口 **17611** 没动。
3. **但"装了 pip"≠"装得了包"**（这是他那份文件里 A/B 两类的交界）：54 那发把 index 指到清华 pypi 后仍 `(from versions: none)`，
   同条 `getent` 空、hosts 计数 0 ⇒ **病在解析层**（这台机 UDP 53 废，14.22 那个老病根）。55 补 `pypi.tuna.tsinghua.edu.cn` 一条钉进 hosts（`--sync` **1 新增 / 15 已在 / 0 问不到**，行 **28 → 29**，备份 `/root/.dsh/hosts.bak.20261021-123435`），
   **不带 `--resolve`** 复点：index **200 / 60,166 B / 0.543 s**、`pip download` rc=0 拿到 `requests-2.34.2-py3-none-any.whl`、
   `pip install --target` rc=0 装出 5 个包并 **`import requests` 真打了一次 api.deepseek.com → `2.34.2 401`**（401 = 没带 key，路是通的），临时目录当场删净。
   npm 那侧**不用动**：`npm config get registry` 早就是 npmmirror，`npm pack zod@3` rc=0 落 **604 KB**（我只复点，没改配置）。
   **PEP 668 的坎给他三条路带数（我不替他选）**：A 装 `python3-venv python3-full` = 21 个包（现在 `venv` 能导入但 **ensurepip=False**，`python3 -m venv` 起不来）；B `--break-system-packages`；C `--target`（本轮实测就是这条，代价是要带 `PYTHONPATH`）。
4. **市场那条路由端到端**（探针 48）：`:3081/dsh-market/registry` 带口令（从 stdin 递，口令不进 argv）**200 / 7,000,459 B / 1,110 ms**，第二发同字节 **208 ms** ⇒ 缓存住了。
   `log.ndjson` 两发前后一字节没长（6,606 B / 20 行），照实记着。**还欠他一眼**：在 App 里打开插件市场，屏幕上不转圈我才闭环（14.28 那格欠的就是这个）。
   同时把我自己先前那句"症状 = 42 秒等待期"**从推断降级成未定** —— 非 2xx 在 `MarketSection.tsx` 里是走错误分支的（`:2678` / `:6437-6446`），与"永远转圈"对不齐，两种解释都没被证死，根因与修法不受影响。
5. **横屏侧栏：类名一条都没有**（探针 49/50，`p49.txt`/`p50.txt`）—— 真产物 `index-BxpfOGf3.css` 77,343 B 里 `sidebar`/`_rail`/`aside` 命中**全 0**，
   JS 里 137 个 `data-*` 全是 dockkit/window/modal。⇒ 不写死选择器，改用**页面上真存在的文字**定位，补丁挂在兼容层（`tools/dsh-compat.js` 3,123 → **9,793 B**）：
   只在横屏生效、少一个锚点就不下手、找"内容高>可视高且 overflow hidden"那一层挂属性、规则写进 `<style>` 用 `!important`（防 React 盖掉 inline）、自证读数留在 `window.__DSH_SIDE__`。
   **注入这一层已经证实生效**：机上那份与本地 **md5 逐字节撞**（`268f90ad…`），入口按 mtime 热读（`entry.log`：**已读入 8265 B**，8,265 是字符数 / 9,793 是字节数，差的是中文注释），
   出口 200 的 HTML **49,959 B** 里 `data-dsh-side-scroll` **1**、内联段 **9,794 B**（= compat + 1 个反斜杠，那句注释被正确转义）、`injectMiss=0`、引擎 21363 未换代。
   **没闭环的是屏幕**：手机此刻 `Dozing`、壳不在前台，CDP 第一步就拒灭屏（`scripts/dsh-cdp.js:113`）⇒ **要他解锁、点图标、转横屏划一下**。
6. **我自己在这轮又抓出两条读数坑**（都按读数改口了，全文在 14.30 五）：① 探针 51 里 `grep -o '<\\\\/script>'` 传下去的模式匹配**两个**反斜杠，而转义产物只有一个 ⇒ 打出"0 次"看着像 2026-10-20 那起事故重演，其实是假读数；
   ② 同一条判据 `<script src=` 本来就不是判据（上游自己就有），真判据是"内联段里有没有裸 `</script>`"。两条都换成 **python3 精确子串计数 + 内联段字节对账**（探针 52）。
   还有一条更早的：49 那发用 `find -name '*.css' | head -1` 抓到的是 Chrome DevTools 自己的 `application_tokens.css`、JS 抓到 `langs/asciidoc-*.js` ——
   **产物名要先从 `index.html` 里抄 hash 文件名**，别拿 find 的第一个当上游产物。

**没做**：没重启引擎/入口、没动 `DSH_PERMISSION_MODE` 与 `runnerCommand`（**Bash 在 `workspace-write` 下仍然拒绝执行**，接线还是等他，见 #40）、没动自启（仍 `.off`）、
没清 apt 缓存、没把任何 pip/npm 包装进系统环境、没装他清单里我判"要不要他点头"的那四摞、没在 App 里替他点一下、没重打 APK、没碰 `/data/local/tmp` 他那批件、
没删机上 `.sh`（chroot `/root` 仍 9 份）、`doh-hosts.sh` 只加了 pypi 那一条。**两个仓这轮都还没提交**（他说提交我才提交）。
**还欠他的四件**：① 转横屏划一下侧栏（#52）；② 在 App 里打开插件市场（#48/#37）；③ pip 走 A/B/C 哪条、剩下四摞装不装（#32）；④ runner 接线（#40，要他在场挑重启时机）。桌面图标缓存那张按他话先挂着（#53）。

**2026-10-21 深夜（状态 33：14.30 交完之后我自己又追了七发探针 56–62，判"今晚这台机还有哪条网路活着"—— 结果 GitHub 那跳死了、gitee 活着，git 因此才算真落地；全文 RUNBOOK 14.31）**

1. **14.30 交付的东西一件没跑掉**（p56）：引擎 **21363** / 入口 **17611** 都没换过代，dpkg 仍 **411**（`ii` 也 411），
   机上兼容层仍 **9,793 B / md5 `268f90ad…`**，出口首页 **49,958 B** 里 `data-dsh-entry-compat` = **1**、`__DSH_SIDE__` = **2**、`data-dsh-side-scroll` = **1**
   ⇒ **横屏那段确实产品在用**（这一条是 14.30 第五节的复点，不是新证）。
   `git 2.43.0 / Python 3.12.3 / pip 24.0 / gcc 13.3.0 / cmake 3.28.3 / ffmpeg 6.1.1 / rsync 3.2.7` 逐条 `command -v` + 版本都在位；
   **三条不是没装而是我挑错行**：`pdftoppm`／`tmux`／`unzip` 这三个工具不认 `--version`，打回来的是用法行（包都在 dpkg 那 411 里）。
2. **GitHub 这一跳今晚不通（p59 / p60）**，三个口径三种读数、硬事实是 **0 字节**：`curl -m 40` 回 `(28)` 超时、`bash /dev/tcp/20.205.243.166/443` 却"连上"、
   node `tls.connect` 给"8 秒窗内没动静"；对照组 `objects.githubusercontent.com` **TLS 400 ms 握手成、证书 `*.github.io`、404 / 424 B**，`codeload` 20 s 超时。
   14.22 那轮"30 秒传回 676,496 B"**不能当今天的结论**。**`gh-proxy.com` 那条退路在手机上现在也不成立**：DoH 给 8 个 Cloudflare IP，但 hosts 没钉 ⇒ `(6) Could not resolve`；
   拿首选 `--resolve` 打过去 ⇒ **`(35) Recv failure: Connection reset by peer`**（三发同一错误）⇒ 已把它加进 `doh-hosts.sh` 的 **WATCH 摞（只看不钉）**，
   机上 **7,660 → 8,379 B**、md5 **`f046d046…`** 与仓库逐字节撞上（写之前 `cp -p` 备份 `/root/.dsh/doh-hosts.sh.bak-20261021-205627`，备份与原件 sha256 相同才动手）。
3. **git 到这一步才算真落地（p62 重跑 = `p62b.txt`）**：`git ls-remote --heads` 四个 gitee 候选 **rc=0、refs 8/7/23/26**，
   `git clone --depth 1 https://gitee.com/mirrors/git.git` → **rc=0、76,737 KB、HEAD `c514088`、`ls-files` 4,857 个、`status` 0 行**，复点后 `/tmp/p62-clone` 删净；
   本地那层 `init` + 两次 commit + `branch` + `diff HEAD~1` **109 B / 7 行** 也真跑过。⇒ **DSH 里 `git clone` 走 gitee 通、走 GitHub 今晚不通**；npm（`npm view zod` → **4.6.7**）与 pypi（`pip download six` → 1 个文件）同刻都活着。
4. **我又造了三类假读数，全部按读数改口并写进 `AGENTS.md` 第 2 条**：① 贪婪 `sed` 抓的是**末位** A 记录 ⇒ p56 报的"漂了 3 条"里两条是假的（github / awesome-dsh-plugin 其实与 DoH 首选一致）；
   ② `awk '$0 ~ d'` 在 hosts 里做子串匹配 ⇒ 问 `github.com` 拿到隔壁 `codeload.github.com` 的 `.165`（真值 `.166`）；
   ③ **p62 第一遍整发作废**：我 `cd /tmp/p62-local` 之后把它 `rm -rf` 了，cwd 成空洞 ⇒ 后面每条 git 都 `rc=128 / refs=0`，看着像"五个远端全拉不到"，其实一个包都没发。
   **教训形状**：一批读数**全红**时先怀疑自己的环境与取数管道，再下网络的结论。
5. **CDN 类域名"IP 撞不上"从来不是判据**（p58 精确对账：27 行 hosts ⇒ 首选一致 13 / 在候选集合里 4 / 对不上 10，**那 10 条里 8 条是 `cdn.npmmirror.com` 一个名字占 8 行**）：
   落字节实测 `registry.npmmirror` 三种打法都 **200 / 1,341 B**、`aliyun` 301 / 239 B、`cdn` 403 / 408 B、`plugins.json` Range **206 / 1,024 B**（钉的旧 IP 与新 IP 都成）⇒ **本轮没有任何一条判"坏"**。
   顺手记两条新读数：`platform.deepseek.com` 回 **429 / 1,971 B**（限流，**本轮没深究**）。
6. **市场那一格多了一个外部变量（改口）**：`region` 仍是 global、而目录第一源在 GitHub ⇒ **今晚他在 App 里打开市场若还转圈，那不是 14.28 的改动没生效，是路由坏了**。
   两条摆着：① 把「下载区域」改成中国大陆（先走 npmmirror，今晚实测 200 / 1,296 B）；② 等 GitHub 回来再验。**"欠他一眼"这条不变**。
7. **机上干净了一点（p61）**：chroot `/tmp` 里我的 `dsh-*` **33 → 4 项**，删的 29 项逐条打印过（26 个 `dsh-entry-selftest-<pid>/` + `dsh-devnull-inner.sh` + 两份 `dsh-entry-check-*.html`），
   白名单只允许 `/tmp/dsh-` 开头；**留下的 4 项不是我建的**（`dsh-subprocess-KF4KVK`、`dsh-spill-wjnyJP`、`dsh-spill-92RWpY`、`dsh-purge-desktop.log`）⇒ 要清得他点头。
   **14.30"没做"那句里的 `/root` 仍 9 份**就地改口：**是 8 份**（探针把自己也数进去了，runner 跑完才删）。

**没做**：没 `--sync`（只 `--check`，`/etc/hosts` 仍 29 行）、没改 git 全局配置（`/root/.gitconfig` 本来就不在）、没重启引擎/入口、没 reboot、没清 apt 缓存、
没装那四摞、没在 App 里替他点、没碰他那批件、没追 `platform.deepseek` 那个 429、没给 GitHub 找替代路由（没有可钉的活 IP）。
**两个仓仍未提交**（他说提交我才提交）。**一个字节级的悬案**：同一份首页 p52 量到 **49,959 B**、p56 量到 **49,958 B**，差 1 B，**成因未查**（不影响注入层判据：两次标签计数都是 1）。

**2026-10-21 晚 21:2x–22:1x（状态 34：他那六件事一轮做完四件半 —— 键盘（壳 0.7）、整列可滑（兼容层 13,521 B）、清残留、四批包的数重量；剩下半件按他"重启没关系"去接 runner，量出来的一件事比接线大得多：这台机现在没有任何进程围堵；全文 RUNBOOK 14.32）**

1. **⑤ 键盘跟随：根因在壳不在页面，0.7 已装机已验**。0.6 上就取到自证读数（`downloads/kbd-212829/`）：对输入框中心发**真触摸**、安卓侧 `mInputShown=true`，
   而页面 `innerHeight` / `visualViewport.height` 仍是 **360 / 360 一字不改**、输入框 `top/bottom` 仍是 **240/276** ⇒ 页面收不到键盘高度，纯前端修不了
   （病根是 0.4 起的沉浸式全屏让 manifest 的 `adjustResize` 失效）。改法在 `MainActivity.watchImeInset()`（`:374-394`，只挂 API 30+）：
   把 `Type.ime()` 那截 bottom 压成 root 的下内边距，WebView 跟着变矮、页面自己贴底上移。**修后读数**：`innerH 360 → 152`、composer `240 → 32`、收起复原 `360/240`，截图 `downloads/kbd-up.png`。
   装机复点：`versionCode=7 / versionName=0.7`，机上 `base.apk` **152,166 B** 且 `toybox sha256sum` **与本地 `app/out/dsh-app.apk` 逐字节相同**（`be025bb372645d34…`）。
   **我自己一处要记的错**：§0 那张表第一版把 sha 写成 `c9edd7ee…` —— **那个数我根本没读过盘**（第四类错：写了没读过的数），已按实测值改回。
   另一条假读数：第一版用 `focus()` 唤键盘，`mInputShown` 一直 false ⇒ 那次的"窗口没变化"是**键盘根本没出来**（`downloads/kbd-212522/`）；量键盘只认真触摸。
2. **⑥ 左侧整列可滑：上一版只治了被压扁那层自己滚，这次松掉中间那六层**。CDP 打树（`downloads/cdp-rail-1.txt`）：rail `hHd-Xa_root` 的 `scrollHeight == clientHeight == 360` ⇒ **它自己不滚**；
   真凶是 `bhn1Oq_list` **可视只有 16 px 而内容 402 px**，它到 rail 之间**六层全是 `flex-grow:1` + `min-height:0`**。
   `tools/dsh-compat.js:117-271`（**9,793 → 13,521 B**）改成：给那六层取消 grow（`data-dsh-side-grow`）、被压层展开（`data-dsh-side-inner`）、**rail 自己滚**（`data-dsh-side-scroll`），
   外加三道闸门防误伤。**读数**：rail `scrollHeight 360 → 746`、内层可视 `16 → 402`、**松掉 6 层**、可滚余量 **386 px**；
   **真手指** `adb shell input swipe` 在列区划一次 `scrollTop 0 → 386`（这条才算"他那一划有用"），撤回后回到 `360/360` ⇒ 注入可摘、不永久改坏。
   机上 `/root/.dsh/entry-compat.js`（宿主侧 `/data/local/dsh-rootfs/root/.dsh/entry-compat.js`）**13,521 B / md5 `23b672dccda5…` 与仓库逐字节撞上**，出口首页 **200 / 53,687 B**、属性命中 1；**入口 17611 没重启**（按 mtime 热读）。
3. **③ 接线撞出一个更大的数：purge 把 `confine()` 换成"永不包装 argv"**。按他"接 `runnerCommand` 要重启，重启没关系"走完五步：
   precheck（p67：cordis **508 B/13 行**、`- id: sandbox` = `dsh-sandbox-local` 而 `sandbox-policy` 只吃 `mode`、**两个 zod Config 都没 `.strict()`** ⇒ 键放错 id **静默丢掉**、runner 在位 9,530 B / `50788b29…`）→
   备份并 sha 撞上才写（p68：`cordis.patch.yml.bak.20261021-140720`，`29d79784…`）→ **`--dump-config` 不重启就判死接对**（树第 **141-147** 行、`runnerCommand` 命中 1、文件 508 → 1,063 B）→
   **只 SIGTERM 引擎**（p69：**21363 ⇒ 26114**，10 秒入口重拉、自动换到第 5 代 cookie `http=303`，入口 17611 没动）→ 端到端拿上游算出来的 argv 跑判据。
   决定性读数不是那四条，而是 **`ARGV_HAS_RUNNER=no`、`SEPARATOR=no`、`FAILURE_RULES=[]`、`DENIAL_SIGNATURES=[]`** ⇒ **`confine()` 根本没包装**。
   足迹（p70 两条独立口径）：`.dshpurge.bak` **56** 份、正文含 `[dsh-purge]` **42** 个文件、mtime **2026-10-21 10:35:16–17Z**（＝**北京 18:35**，正是装 purge 那轮）。
   拉回本地 grep 到的 bypass 不止沙箱一层：`dsh-fs-sandbox` 的 `checkedTarget()` **原样返回不做越界检查**、`dsh-user-approval` **弹窗前先回 `allowed-once`**、升级阶梯"never rejected"、denial 标记中性化。
   ⇒ **三条后果**：(a) 接线在 purge 在位时**是死配置**，已**逐字节撤干净**（还原 508 B、sha 与备份相同、文件与树里 `runnerCommand` 命中都 **0**，不留"假装已围堵"的东西；两行原文存进 [`config/cordis-sandbox-wiring.snippet.yml`](config/cordis-sandbox-wiring.snippet.yml) 待用）；
   (b) **这台机现在没有进程围堵、文件工具没有围栏、审批不会弹窗，档位 UI 是装饰**；
   (c) 于是 14.30 那句加粗的"**Bash 在 `workspace-write` 下仍然明确拒绝执行**"**按代码判据已不成立**（走不到 `selectRunner` 就抛不出 `SANDBOX_UNAVAILABLE`）——
   **但我没跑过真回合**，所以只降级成"旧结论作废"，**到他 App 里让 Agent 跑一条 `echo` 才算新的 ✅/❌**。
   顺带把 69 那两个"看着像坏了"的读数问干净：`:3080` 裸打 **401/68 B**（引擎活着、要券）、`:3081/` 不带口令 **404/10 B**（入口按设计）、带口令 **200 / 53,687 B**；口令一律 `curl -K -` 从 stdin 递。
4. **① 镜像：装了、查出形状错、撤了，GitHub 今晚又活了 ⇒ 实装 0 条**。p64 装的那条 `url.https://gitee.com/mirrors/.insteadOf=https://github.com/` **本身是错的**：
   gitee 的 mirrors 组织**不带 owner 段**，它拼出的 `…/mirrors/git/git` 回 **401 / 40 B**，而真形 `…/mirrors/git` 回 **200 / 134,344 B**；
   `gh-proxy.com` / `gitclone.com` / `hub.gitmirror.com` 今晚**全部 rc=6 / 0 字节**（解析失败），而**同一发里 `github.com` 本体 200 / 353,218 B / 15.09 s** ⇒
   撤规则（**撤完剩 0 条 `url.*`**）后真解析 `git ls-remote` 回**真 SHA**（`git/git` `47fdf220…`、`golang/go` `ace5a752…`；`rust-lang/rust` **rc=124**＝我给的 40 s 超时，仓大不是路由坏）。
   **改口**：状态 33 判"GitHub 今晚死了"，本轮它活了 ⇒ **这条路由在漂，"通不通"只认当次落字节，别把上一轮结论当今天的**（写进 AGENTS.md）。以后真要钉 gitee 只能**逐仓映射**，别再用整段前缀替换。
5. **② 四批工具包的数重量了两口径 + 并集，并改了我自己两处口**（p66 / p67，一个不装）。
   **改口一**：那句"`apt-get -s` 把 Need to get / After this operation 打到 stderr 被我 `2>/dev/null` 吞了"**是错的** —— 它**根本不打**（rc=0、428 行、只有 `106:0 upgraded, 161 newly installed`）；
   只能自己算：下载量取 `--print-uris -qq` 每行第 **3** 字段（字节），占盘取 `apt-cache show` 的 **`Installed-Size`**（**KiB**，一个候选版本一条）。
   **改口二**：14.30 报的**语言栈 61 个数错，真值 63**，而且那套只有"不含 recommends"口径。
   **两口径**：文档办公 **161 / 84**（135.9 / 123.7 MB 下载，612.2 / 559.9 MB 占盘）、OCR **6 / 6**（8.0 MB，21.7 MB）、语言栈 **103 / 63**（268.8 / 262.8 MB，981.3 / 958.5 MB）、容器 **78 / 29**（103.4 / 84.2 MB，425.5 / 355.8 MB）；
   **四批并集 281 个 / 503.4 MB / 1,992.2 MB**（不含 recommends **159 / 475.6 / 1,886.0**）—— 各批相加是 348 / 182，**多出来的是重复计**（systemd、libpython3.12 这类被几批同时拖进来），**"还剩四批 ≈ 350 个包"这句作废**。
   "到底装的是什么"：pandoc **207.5 MB** + libreoffice-core **149.2** + openjdk-21-jre-headless **194.6** + libstd-rust-dev **171.4** + golang-1.22-src **119.0** + docker.io **124.9** + containerd **94.1**；
   recommends 差集 **77 / 0 / 40 / 49** 个（poppler-data、fonts-*、apparmor、buildah 这类"顺手带上"）；
   **OCR 那批最便宜（21.7 MB 就能图片认字）**、**容器那批我建议不装**（`# CONFIG_USER_NS is not set` + 没有 cgroup 委派，425 MB 换一条起不来的路）。
   现状一个字节没动：dpkg **411**、apt 缓存 **237 MB / 324 个 .deb**、`/` **340 G 可用 / 935 G**；四批里已在位的只有 `git` 与 `python3`。
6. **④ 清残留：只删我自己造的，删前逐条校 md5**（p64 ②②b / p65 ②）。`/root/*.sh` **9 → 3**：删 6 份一次性取证脚本
   （`dsh-ask.sh` 732 B `417cf35c…`、`dsh-auth-host-probe.sh` 1,464 B、`dsh-probe.sh` 3,681 B、`dsh-sbx-probe.sh` 3,318 B、`dsh-setup-in-chroot.sh` 5,958 B、`dsh-terminal-probe.sh` 1,189 B，**每份先与仓库孪生件撞 md5**）、
   **留 2 份不是残留**：`doh-hosts.sh` 8,379 B（`.dsh-env` 引用它）、`dsh-entry-check.sh` 13,579 B（`deploy-entry.sh` 每次推的交付件）；**那"3"里含探针自己**（老坑）。
   `/tmp` 顶层 **13 → 9**，删的 6 项都是我的（`dsh_page.html` 42,740 B、`w`、`xz.log`、`apt-lite.log`、`entry-selftest.out` 13,154 B、`dsh-entry-selftest-3185/`）；
   **剩 9 项逐个报归属、一个没动**（`dsh-purge-desktop.log` / `dsh-spill-*` / `dsh-subprocess-*` = 引擎与插件，`node-compile-cache` / `node-addon-*` / `pnpm-store-*` = node 与 pnpm 缓存）。
   **"临时键"如实回答：我这边从没留过临时密钥** —— 探针都借他已登录的会话，凭据只走 stdin；`entry.key` 与 `.credentials.yaml` 是他的常驻凭证，没碰、没移、没改名。
   本轮新增持久件只有**备份**（可逆依据）：`cordis.patch.yml.bak.20261021-140720` 1 份、`dsh-env.bak.*` 4 份。
7. **`config/dsh-env` 这轮加了一行并部署上机**：`export DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=1`（这台 `# CONFIG_PIDNS is not set`，不加 runner 直接拒跑；
   加了以后**被围命令能看见宿主 pid 并可 kill 它，含 dsh 自己** —— 代价写在那段的注释里，撤就是一行）。部署走 `tools/deploy-env.sh`：
   备份 `/root/.dsh/dsh-env.bak.20261021-140826`（5,567 B、`c818a310…`），机上 **8,066 B / md5 `a1dad02f…` = 仓库件**（`--check` 事先报出差集才推的）。

**没做**：**没撤 purge**（那 42 个文件与 56 份备份件是他装插件留下的，动它＝动他的东西，我只报数）；没重启入口、没 reboot、没 `apt install` 任何一批（只量数）、没清 apt 缓存、
没动自启（仍 `.off`）、没碰 `/data/local/tmp` 他那批件、没在 App 里替他点任何一下（⑤⑥ 的视觉判据仍归他那双眼）、没装镜像规则（实装 0 条）、没 `--sync`（hosts 仍 29 行）、
没验 #18 那个 `/dev` 窟窿（本轮只到"接线无效"）、**没跑真回合**（所以旧结论只能作废，不能反向宣布"Bash 能用了"）、**没取到壳那行 `输入法 inset=…px` 原始日志**（`logcat` 已滚掉，那 208 px 是两个页面读数相减得到的）。
**两个仓仍未提交**（他说提交我才提交）。**→ 23:1x 已提交**：工作仓 `6338ab9` / 父仓 `3dd37f49`，细节写在下面状态 35 那条箭头里。

**2026-10-21 晚 22:43–22:58（状态 35：他一句"不撤，插件你先不用管"关掉 ②③、＋"这段回复我没看懂，你给我解释一下"把手机上那个 dsh 自己写的报告交给我对账。这一格的主体不是我动盘，是「它」动了一次盘；我对完六条：五条撞上读数、最要紧那条错。全文 RUNBOOK 14.33，读数 `downloads/p71.txt`–`p75.txt`）**

1. **它真做了的五条（逐条撞上读数）**：备份 `cordis.patch.yml.bak-20261021-144328`（508 B、sha `29d79784…` **与我那份备份逐字节相同**）→ 把两行 `runnerCommand` 写回 `- id: sandbox`（**508 → 1,627 B、命中 4**，位置挂对了）→ `--dump-config` 不重启验到命中 1（组合层确实收到了）→ 手工调 runner 量三个 YES → `setsid bash -c 'sleep 15; kill -TERM 26114'` 自杀换代 **26114 → 28833（第 6 代，14:43:58Z）**，入口 **17611 没动**，实测断 **4.1 秒**、cookie 自动重换 `http=303`，会话记录 `session.v4.jsonl.zstd` 292,649 B 无断点（FRAMES=133 / DECOMP_FAILS=0）。
2. **错的那条与它的成因（这一格唯一要记死的规矩）**：它说"填 `runnerCommand` 后 `confine()` 走 :311 那条分支、把 argv 改写成 `dsh-unshare-run`" —— 机上**真在加载**的那一份（`…/dsh/node_modules/@deepseek-ai/dsh-sandbox-local/lib/index.js` 22,231 B、md5 `b976570f…` ＝ 本地 `downloads/sbx-dev-index.js`）我按它写的 cfg **直接调了一次**：
   **`ARGV_HAS_RUNNER=no`、`ARGV0..2=["bash","-c","echo hi"]`、`FAILURE_RULES=[]`、`DENIAL_SIGNATURES=[]`**，`pgrep -f dsh-unshare-run` **0** ⇒ **它接的线在 purge 在位时是死配置，围栏一点没回来**。
   它为什么没看出来：p75 第 36 条命令是 `sed -n '240,340p' /root/.dsh/dsh-purge/host-backups/9dac90ce22cf7f551f319a5e.bak` —— 读的是 **purge 动手前存的原件**，磁盘上早就不加载了。**同名代码两份，读错一份就得错结论**（进 AGENTS.md 铁律 17）。
3. **白捡的收获**：14.30/14.32 欠了三轮的那条判据（"跑一条 `echo` 才算 ✅"）**被它替我们跑了** —— 它会话第 30 条命令 `export DEBIAN_FRONTEND=noninteractive; apt-get install -y --no-install-recommends ripgrep jq`，`dpkg.log` 14:39:47–48 落 8 行、`dpkg -l` **411 → 415**，而那会儿跑的是第 5 代、purge 已短路 ⇒ **`workspace-write` 档位下命令真执行、真装包、没被拒、没弹窗**（反面同义：没有围栏）。判级 **强推断**：命令串＋安装时刻两条独立来源，不是引擎侧进程审计。
   **→ 23:3x 补一句（他原话）**："**那是我让他装的**" ⇒ 这条判据的**效力不变**（照样证明 `workspace-write` 下命令真执行、不弹窗），只是**发起者是他授意**，我上面写成"它替我们跑了"容易被读成"它自己乱装"，按他的话改口。
4. **它最后问的那件（`setpriv --reuid=1000` 先不先测）我按读数答了：不做、挂起** —— 围内（runner 包装后）与围外（chroot 直接）**四条读数一模一样**（`LINK=/`、`LS=acct apex bin`、`TOP=71`、`ST=emulated persist self`）⇒ `/proc/1/root` 那条缺口不是 runner 漏了 `/proc`，是**现在根本没有 runner 在中间**；purge 不撤 ⇒ 整条围堵话题按他的裁决挂起。顺手记一条**假口径**：`findmnt -o OPTIONS --target` 在这台 chroot 里对 `/etc` 回的是**底下 f2fs 的选项**、对 `/phone` 回**两行**，不能拿来判只读。
5. **它的 44 次工具调用我全提出来了**（42 bash + 1 read + 1 edit；前有两发提取失败，坑是 **`tool/call` 的 `data.arguments` 是 JSON *字符串*不是对象** —— 第五种"无关内容进我要数的字段"）。里面几件是它自己发起的动作（不是我做的）：`iptables -t nat -L`（看 nat 表）、往 `/root/.sandbox_probe_$$` 试写、以及**它自己 `apt-get install`**（那正是"装包要他点头"这条红线我这边从不越、它那边没有）。
   **→ 23:3x 这半段的归因作废**（他原话"**那是我让他装的，没关系，我要的就是这种效果**"）：那条 `apt-get install ripgrep jq` **是他授意的**，不是它自作主张 ⇒ **"红线我这边从不越、它那边没有"那句对比是我替他担心错了对象**；命令真执行＝没围栏这个读数不变，**但别再当风险报**（AGENTS.md 铁律 19）。
6. **残留与"我没动它的东西"**：cordis 那两行**我没撤**（两个写手来回改同一个文件＝打转，撤/留等他一句，见 下一步 35）；`ripgrep`/`jq` **我没卸**（那是他的机、他的包）；purge 的 42 个文件与 56 份备份、`/data/local/tmp` 他那批（71 条，最新仍是 10-19 23:32 我那批）**一个不碰**；`/phone/mycode-oneplus` **空的（条目 0）**，它自述写过的两处目录都没留东西；我这五发探针 `/tmp` 残留 **0**、`/root/*.sh` 2 件＋探针自己（收尾删）。
   **没做**：没撤 purge、没撤它那两行、没卸包、没重启引擎或入口、没 `--sync` hosts、没验 #18 那个 `/dev` 窟窿（本轮不必了——围堵整体挂起）、**没在他 App 里点任何一下**、没提交两个仓。
   **→ 23:1x 他一句「提交」，上面那句作废**：两发都进去了 —— 工作仓（本目录，`origin = zhl110/dsh-mobile`）**`6338ab9`**、父仓（`D:\mycode`，pathspec 只带 `dsh-mobile/` 前缀）**`3dd37f49`**，
   各 **50 个文件**（39 新 / 11 改）、`+6,835 / −2,332`，`git status --short -- .` 两边都回 **0 行**；三处 blob 对账全等（`RUNBOOK.md` `b8d0945a`、`config/dsh-env` `dfe8cd8d`、`手机端情况.md` `9a3512c8` 在**工作仓树 = 父仓树 = 盘上 `git hash-object`** 三处同号）。
   身份按已知坑那条走**单发传参** `-c user.name/-c user.email`（本仓没有 git 身份，**没改任何 git 配置**），作者落的是他 `再来一杯海星酒 <〈提交邮箱·已遮〉>`。
   **没 push**：他说的是"提交"，所以只提交。23:19 当场量 `git rev-list --count origin/main..HEAD` = **2**（`6338ab9` + 回填提交号那发），远端仍停在 `22faf1d`。
   **认这个数只认当场跑那条命令**：写这句话的这一发本身会让计数再 +1，所以别把文档里的数当恒等值。推不推等他一句。
   **→ 23:2x 收尾把三发全号列死（免得下一个人只看到前两发）**：工作仓 **`6338ab9`**（50 个文件那发）/ **`c02e4ab`**（提交号回填）/ **`a1bf414`**（"未推数改成当场量 + 更正 `c02e4ab` 正文里那处归属"）；
   父仓同三件 = **`3dd37f49`** / **`b97d05a`** / **`24f4d5c7`**。
   **两处我自己刚犯的错都记在这**：① `c02e4ab` 正文说"cordis 行号重数与 42/1/1 那三处改口是它做的"——错，那些进的是 `6338ab9`（改口发生在 `git add` 之前）；② 父仓 `24f4d5c7` 正文把工作仓上一条写成"**641…**"——那是我**没查号就写**，真号 `a1bf414`。
   两条都**不改历史**（不 amend），只在这里留痕；判据是"往文档写号之前先 `git log` 复点"，与 14.22 那条"没算就写"同源（已进 AGENTS.md 的 git 那条坑旁边）。

**2026-10-22 晚 21:0x–21:57（状态 36：他报"点加号选文件/图片没反应"，并要我查"其他这些功能有没有一一对应上"。全文 RUNBOOK 14.34）**

1. **一句话结论**：不是前端坏了，也不是手机缺选择器 —— 是**我们的壳没接 `WebChromeClient.onShowFileChooser`**，Android 的默认实现直接 `return false`，Chromium 于是**静默丢掉**这一发：console 干净、网络 0 请求、屏幕没反应。与 0.6 之前"点语音没声"（`onPermissionRequest` 默认全拒）是**同一族**。
2. **两侧取证的形状**（这套办法本身值得留）：页面侧 CDP 挂 hook 记到 `input[type=file].click()` 发了 1 次；壳侧 `logcat -c` 清空后再点，`START` / GET_CONTENT / documentsui **0 条**；系统侧 `cmd package query-activities` 数出 GET_CONTENT 可解析项 `image/*` **12**、`*/*` **20** ⇒ 三段把"断点在壳"钉死。
   （那两个 12/20 是**加了引号重跑**才拿到的：`-t */*` 不加引号被**设备上的 shell** 展成文件名，读出过假 0；同一条链上还有 `grep -c` 未命中退出码 1 会把 `&&` 后半条带走。都进了 AGENTS.md 已知坑。）
3. **代码只动壳**：0.8 加 `onShowFileChooser`（走 `params.createIntent()`，保 accept 列表）＋ `onActivityResult`（**选中/取消/抛错三条出口全部结掉 `ValueCallback`**，漏一条就自家复现同一症状）；0.9 再加一行壳自己 `openFileDescriptor(uri,"r")` 的复点读数（只报 mime 与字节数，**内容不进壳**，数据路径没加间接层）。manifest 与 build.sh 版本号 7→8→9；**权限一个没加**。
4. **装机与撞号**：`bash tools/install-apk.sh`（只装不重打）—— 本地 `app/out/dsh-app.apk` **152,166 B / sha256 `2b2dc8dd7668674fe0061f9a2eaeeacf141e0d914cfbc868de692200f30c957d`**，推上去逐字节撞上，装完机上 `base.apk` **同一个 sha、152,166 B**、`versionName=0.9`、`lastUpdateTime=2026-10-22 21:48:31`、两处副本清零。0.8 那发 = 152,167 B / `6d25f79e…`（21:26:51）；**0.7 原件已 pull 回 `downloads/apk-0.7-installed-base.apk`（152,166 B / `be025bb3…`）＝退回路径**。
5. **一次真选跑到第七格**（读数全在 14.34 三）：`21:49:27 要开选择器：GET_CONTENT｜多选=true` → `mCurrentFocus=…documentsui/.picker.PickActivity` → `21:54:46.057 选中 1 个｜首个=content://com.android.providers.downloads.documents，路径 62 字符` → `21:54:46.086 壳侧复点 #0 ⇒ 打得开｜text/plain｜92 B` → 页面侧 `change` 抓到 `size:92 / head:"dsh-mobile 附件链端到端测试件"` → 附件栏 `dsh-upload-test.txt TXT 92B` → 两次取消各一条 `结果码=0 ⇒ 交 null`，之后同一 input 还能再开。
   **由此定死的两条**：① `setAllowFileAccess(false)` / `setAllowContentAccess(false)` **不管附件通道**，别为修上传去翻；② 这页的 React 在 `change` 后会把 `input.value` 清空 ⇒ CDP 之后读 `files.length` 必是 0，**那是假证**，必须在回调里当场抓 File（`--setfile` 那条新通道已按这个写法）。
6. **只剩最后一格，而且要他点**：按"发送"后 multipart 是否真把 92 B 送过 `:3081` → `:3080`。**我没替他在他的会话里发消息**；现场留着他输入框里那发 `dsh-upload-test.txt`（待发附件），他按下发送我就用 logcat + `/__entry_status` 复点。测试件 `/sdcard/Download/dsh-upload-test.{txt,png}` 因此**先不删**。
7. **"其他功能"那一半的账**（表在 14.34 四）：语音 ✅；相机按设计拒；**下载没接 `setDownloadListener`**、**全屏没接 `onShowCustomView`** —— 这两格现在是"没实现"而不是"坏了"，页面真用到就会复现同一症状；`navigator.clipboard` 3 处未验（那次 `y=−6725` 是元素在屏外、触摸落不到，判据失效不算页面缺陷）；插件上传 input 只验到 `accept` 原样进 Intent，**没真选**（要装进他引擎）。
8. **我这轮没做什么**：前端一行没动、两个开关没翻、权限没加、`setDownloadListener`/`onShowCustomView` 没实现、没在他的会话里发消息、他那批（`/data/local/tmp`、cordis、锁屏、自启）一个没碰；设备上只有我自己那两件（`dsh-cdp-upload.txt` 已删，删后目录只剩 `shell.log`）。**代码＋三份文档全部未提交**（他说提交我才提交，提交号回来填死）。
   **→ 同夜 23:2x 这第 8 条里那句"`setDownloadListener`/`onShowCustomView` 没实现"已作废**，壳 0.10 接完并实测（下一格状态 37）；那句"两个开关没翻"他也点名问是什么意思 —— 判据没错（这两个开关确实与附件通道无关），**错在我把内部黑话当人话交给他**，已改成四列清单（RUNBOOK 14.35 五）。

**2026-10-22 晚 22:0x–23:2x（状态 37：他追问"为什么不给它实现？是有什么隐患吗？"＋"把没做的列个清单写清楚"。全文 RUNBOOK 14.35）**

1. **改口的是判据，不是代码**：上一轮我用"扫前端产物 0 命中"当"页面没在用"，据此不接全屏与下载。**这个范围错了** —— 真页面 = `dsh-web-frontend/dist`（64 个文件 / 4,903,891 B）**＋ 57 个 `dsh-client-ui-*` 包**（186 个文件 / 29,396,960 B）。修正后的扫描（`downloads/p82.txt`、`p84.txt`、`p85.txt`、`p86.txt`）读出：`a.download = filename` 在 `dsh-client-ui-sidebar-documentpreview/lib/client.pdf.js`、`URL.createObjectURL(new Blob(...))` 在 pdf/excel/conversation 三处、`<video` 在 `documentpreview/lib/client.js`、`clipboard.writeText` 5 个文件、`clipboard.readText` 2 个文件。⇒ **两条都有真实用户**，0.9 及之前的表现就是"点了没反应"（与状态 36 那发同族）。**答案：没有一条是"因为危险所以不做"**，他这句"全都接上"我按"接"执行。
2. **代码只动壳**（前端一行没动）：`MainActivity.java` 加 `onShowCustomView`/`onHideCustomView`＋`exitFullscreen`/`hideFullscreenCb`＋`fullscreenBox`、`handleBack()` ⓪ 分支（全屏里按返回只退全屏）、`setDownloadListener` → `onPageDownload` 按 http(s)/data:/blob: 分三条路、`downloadViaManager`（`addRequestHeader("Cookie", …)`，**API 名不是 `addHeader`**，第一发就撞在 javac 上）、`readBlobAndWrite`+`BLOB_FETCH_JS`（页面自取 → base64 → 每 300 ms 分 192 KB 段捞回，**上限 8 MiB**）→ `saveBytes` 走 MediaStore、`DL_NAME_JS`+`injectDownloadNameHook`+`fromPanel` 新增 `dlname` 分支＋`pendingDlName/pendingDlAt/fileNameSource` 三字段（页面起的名字经无来源校验的 `prompt()` 通道记回来，只在入口同源注入、只存 6 秒、过 `sanitizeName` 才落盘）。`AndroidManifest.xml`／`app/build.sh` versionCode 9→10、versionName 0.9→0.10，**权限一个没加**（仍无存储权限、无 `CAMERA`）。
3. **装机**：`bash tools/install-apk.sh` —— 本地 `app/out/dsh-app.apk` **160,359 B / sha256 `d4476e4ed078f71ca67d1096ab75197e2a803d6faad520ebccdb47036a1c9f7a`**，推上去逐字节撞上，机上 `base.apk` 同一个 sha／同一个尺寸、`versionName=0.10`、`lastUpdateTime=2026-10-22 22:51:43`、两处副本清零。**同一夜 0.10 打过三发**（同尺寸不同 sha ⇒ 只能认 sha）：22:45:36（`40065847…`，全屏＋三条路由）与 22:51:43（`d4476e4e…`，加改名通道）装机过，中间 `ab845453…` 那发装没装过从读数分不出来、只列着不当结论。**回退路径说清楚**：盘上留着的旧 APK 只有 **0.7 原件**（`downloads/apk-0.7-installed-base.apk` 152,166 B / `be025bb3…`）和 0.6（`downloads/dsh-app-0.6.apk`）；0.8（`6d25f79e…`）与 0.9（`2b2dc8dd…`）那两个 APK 已被重打覆盖没了件，而它们的**源码也还没提交**（`MainActivity.java` 最后一次入库是 `6338ab9`＝0.7 那一代）⇒ 想回到 0.8/0.9 只能手工撤本轮那三处新代码再重打，不是装个旧件就完事。
4. **实测读数**（每条一条以上，原文在 14.35 三）：全屏 `22:31:21.864 已进入页面元素全屏｜WebView 已置 GONE` → `22:32:22.396 页面自己要求退出` → `22:32:22.397 在页面元素全屏里按了返回`；http `22:46:21.706 已交给系统下载器（任务号=78）` 落盘 **27,312 B / md5 `1c35dff012e628830393e650464f612b` 与源件逐字节相同**；blob `22:36:37.138 已自己写盘：878 KB`（900,000 B 用 **0.42 秒**）；改名通道 `22:54:01.720 文件名=页面起名-测试-01.css｜名字来自=页面 download 属性` 与 `22:55:13.318 文件名=blob-改名复点.txt`（blob 那发原本落的是 UUID 名）；剪贴板**写通**（`writeText('剪贴板复点-2257')` → `keyevent 279` 原生粘贴 → 回读同一个串）、**读不通**（`readText` → `NotAllowedError`，且 WebView 无壳侧钩子）。
5. **新撞的三条坑**（都已进 `AGENTS.md` 已知坑）：① **下载要真手势** —— `evaluateJavascript(userGesture:true)` 里 `a.click()` 一次都不进 `onDownloadStart`，只能用 CDP `--tapsel`；② **WebView 把 `<a download>` 的名字丢了**（`contentDisposition=(空串)`），名字只能在点击还在页面里时经 `prompt` 通道记回；③ **`blob:` URL 里没有字节** ⇒ DownloadManager 取它必失败，唯一出口是页面自取（cookie 那条另说：交系统下载器必须 `addRequestHeader` 抄一份，不抄直接 401）。
6. **我这轮没做什么 ＋ 两件自己的事故**：没做的 —— 前端一行没动、权限没加、`data:` 那条只有代码没实测、剪贴板读没垫桥（约 30 行，等他点头）、`onGeolocationPermissionsShowPrompt` 没接（p82 那 8 个模式各 0 命中）、没在他的会话里发过任何消息、没打开他的文档预览点"下载"（那要动他的会话内容）、他那批（`/data/local/tmp`、cordis、锁屏、自启、purge 的 42 个文件与 56 份备份）一个没碰。事故 —— ① 新探针输出覆盖过 `downloads/p75.txt`，重跑复原 **10,645 B / 47 行 / 42 条 command**，**差的 1 字节没定位** ⇒ 记"抽查等价"不记"完全复原"；② 他机上留痕：系统剪贴板现是我写的串（先后 `你好`、`剪贴板复点-2257`；他原内容我没读也读不出来，所以"没覆盖"这句我不能说满）、唤屏一次（`keyevent 224`）看到锁屏但**没解锁**、建过又删净的 3 件测试下载件＋2 个注入锚点＋1 个临时 textarea，**留着的只有** `dsh-upload-test.{txt,png}`。**代码＋三份文档全部未提交**。
7. **→ 10-23 00:1x 他追一句"黑屏／报错不自动重试／市场转圈这三个昨天不是修好了吗"，那张清单第 10 行按读数拆开重记**（全文 RUNBOOK 14.36，读数 `downloads/p87.txt`）： **其中一条是我把账记粗了** —— 我把三条并成一行还写"都还没修"，而市场那条**病根 10-21 傍晚 14.28 就改了**；这一发当场重跑老探针复点，取目录这条路是通的：**`GET :3081/dsh-market/registry` 两发 200 / 7,171,002 B，586 ms → 250 ms**（按铁律 3 落字节才算，屏幕那一眼不再欠）。 **确实一行代码没动的是另两条**：503/502 之后不自动重试（`grep -c Refresh scripts/dsh-entry.js` = **0**，壳 `MainActivity.java:260-261` 只弹一屏等他手动点）；重进后黑屏十几秒（唯一自动重试那发 `:1493-1495` 管的是"导航压根没开始"，与这一屏是两种症状）。这两条**我可以现在就修**，走法归他挑 ⇒ #44 / #25 一直挂着。 **顺带撞到新的一格**：入口流水里 `POST /dsh-market/install → 500`，插件日志北京 23:41:54→58 两行对上 `cannot get required service "loader" in inactive context` ⇒ **不是我这轮做的动作、根因未查**，要不要查等他一句（#65）。 **→ 00:2x 他一句"能装，我已经测试过了，装了几个插件了，能用，没问题"当场结案**：那一发 500 只留作一次尝试的留痕，不当缺陷、不再追（#65 划掉）；他这句同时把"市场屏幕上转不转圈"那一眼补上了（#48 划掉）。




## 下一步

1. ~~解锁 → 点 **Terminal** 图标 → 授权 → 看状态~~ **已做完并拍屏验过**（2026-10-20 00:11）：
   冷启图标菜单自己出来，选 1 读到 `:3080 LISTEN / 32127 活着 / http=200 37,512 B`。
2. ~~**他现在只需要做这一件**：填 key~~ **已做完**（他自己填的，真回合读数见状态 4）。
3. 登录那条只剩手机浏览器这一跳没验：页面里点 **登录**，看 HeyTap 会不会打开 DeepSeek 授权页、
   授权完能不能自己回到 `127.0.0.1:3080`。回不来就用第 2 步那条 key 的路，两者互不影响。
   **现在多一条更省事的路**：原生客户端已经用账号链路跑通了，这一跳大概不用再验了，等他哪天在意"登录"这个按钮再提。
4. ~~浏览器「添加到主屏幕」~~ **作废**（他嫌的就是网页）；~~我自己那个 77 KB 的壳留在原地当退路，不装~~ **也作废**：
   它现在就是**主路** —— `com.zhl.dsh` 0.2 已装机已验（状态 17）。16 MB 原生客户端按他点的"留着当对照"原地保留，
   菜单里的 `w)`（裸引擎 + 手动粘 token）也留着当退路。
   **这一条现在只剩一件事要他做**：解锁手机点一下 **dsh** 图标，把"画面上真的渲染对了"从 ◐ 补成 ✅（我不绕他的锁）。
5. 哪天想让它开机自己在后台起来：控制台 **8)** 拨回来即可（现在是 `.off`）。
   **今晚顺手补的那个口子就落在这**：那份自启脚本原来只会 `--web`（裸引擎），而 App 指的是入口 `:3081` ⇒
   真重启之后点开图标会停在「连不上工作台」。已改成**入口脚本在位就 `--entry`、不在位才退回 `--web`**
   （`scripts/dsh-boot.sh` 1,861 → 2,477 B，机上 `50-dsh.sh.off` 同步为逐字节相同 `4207c1bbf779…`，
   **仍然是 `.off`、仍然没开**）。愿意的话重启一次手机验三件：① 自启自己在不在；② 重启后**不用碰任何输入**
   图标点开还能进（这条现在由入口兜，理论上成立、真重启没验过）；③ 那次"服务死掉"到底会不会复现。
6. 哪天 apt/npm/模型/登录突然连不上，先 `python tools/pin-hosts.py`（IP 会漂，实测一分钟内换过两次；
   域名表现在含 `platform.deepseek.com`）。
   → **状态 25 之后这条多了一个不依赖电脑的前置**：手机上直接 `bash /root/doh-hosts.sh --check`（只读对账）再 `--sync`（补钉、带逐字节备份与 `--revert`）。
   那条 `pin-hosts.py` 是"电脑算好 IP 再推过去"，现在这台机自己能拿阿里的 DoH 问答案，**先跑手机这一发，不灵再回到电脑那一条**（RUNBOOK 14.22）。
   **升级 dsh 之后要重做 polyfill**（第 10.11 与 13.4 节 → 2026-10-21 晚这两节已在 [RUNBOOK-archived.md](RUNBOOK-archived.md)，
   定位：`grep -n "^## \|^### " RUNBOOK-archived.md`），
   否则症状还是"工作区永远在加载"。
7. **等他一句话的三件**（我都不自己动）：
   ① 那个会话要不要从 `danger-full-access` 拨回 `Workspace Write`（拨回去 = Bash 又全灭，见状态 10）；
      → **已裁决，这条作废**（2026-10-20 他原话：完全访问的档位肯定是要留的；见状态 10 末段）。
   ② 要不要给手机装个 Chrome/Edge 116+ 好把 polyfill 那根补丁整个拆掉；
   ③ 要不要把 `bubblewrap` 从 chroot 里卸掉（留着不生效，126 KB）。
8. **读完社区两条路线之后，①那个二选一其实有三个选项**（详见 RUNBOOK 14.9 与 `reference/android-community-routes.md`）：
   保持现状但把档位写进 `cordis.patch.yml` 持久化 / 试 proot runner（名义围堵、会变慢）/
   试 `unshare -m` 真围堵 runner（**我只验到 ns 建得出来，没验到只读 bind 真挡得住写**，是"值得试"不是"可行"）。
   我荐先花一次会话把第 3 条验穿 —— 挡住就是**既有 Bash 又有真边界**，这问题直接消失。
   → **第 2、3 条都已经做完**：持久档位走的是环境变量、落在 `/root/.dsh-env`（状态 12，RUNBOOK 14.10，
   比写进 `cordis.patch.yml` 更省事，别两处都钉）；`unshare -m` 真围堵 runner 已经写出来并验到 34/0（状态 13，RUNBOOK 14.11）。
   **剩的最后一段不是"再验一次"，是两个决定**：
   ① 接不接线（`profiles/web/cordis.patch.yml` 加 `runnerCommand` + `runnerFailureSignatures` 两行）——
      代价是重启服务、他手机里那条入场链接换 token；不接就一直是盘上一个躺着的脚本。
   ② `/dev` 那条窟窿要不要堵（换新 tmpfs + 只放 API 节点；`scripts/dsh-devnull-inner.sh` 已经写好退路，没跑过）。
      堵不堵决定"围住了"这句话能说到哪一步：现在只能说**围住了文件系统的写**。
   另外这条要记着：本机内核 `# CONFIG_PID_NS is not set` ⇒ 被围命令能看见并 kill 宿主 pid（含 dsh 自己），
   runner 默认因此 **127 拒绝执行**；要整档可用就得在 `/root/.dsh-env` 里给
   `DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=1`，那等于替机主认下这条后果 —— 这两行都不该我随手写。

9. **读完三家 APK 方案之后多出来的三件便宜活**（`reference/android-three-community-apps.md` 第五、八节，
   全都**不动他正在用的东西、不需要重启服务**，跟上面 ①② 那两个决定互不相干）：
   ① 把环境事实（chroot 边界、PATH、工作区是 `/phone` 这块 FUSE bind、哪些命令在这台机上会假成功）
      预写进 `$DSH_HOME/AGENTS.md` —— 照 Soodok `AgentContextSeed.kt:159-332` 的形状抄，我们目前**完全没做**，
      agent 每轮自己重踩；成本最低、收益最高的一条。
   ② 三处 FUSE 语义容忍（`link`→`rename`、`open("wx")` 保 EEXIST、目录 fsync 吞 EINVAL/ENOTSUP）——
      我们现在 `/phone` 零报错只是**还没撞**，出处 woaiys3 `dsh-bash-local/lib/index.js:3264-3272` / `:2055-2066`。
   ③ 把"一次性 token 不许被健康探测消费"从 RUNBOOK 里的散文变成脚本断言（两家独立踩过这个坑）。
   ④（状态 16 读历史补上的）验收判据要**跑交付物本身**，不只跑仓库里的脚本 —— woaiys3 `984ba3d` 那 5 条
      argv 用例是拿"APK 包里那份 shim"跑的（旧 0/5、新 5/5）。我们的 `verify-unshare-run.sh` 现在跑的是
      `/data/local/tmp` 那份副本，理论上和 chroot 里 `/usr/local/bin/dsh-unshare-run` 可以不是同一个字节。
   另有两条**写死别改的**：日志留在 chroot 私有路径（woaiys3 把 stdout 连 token 明文镜像到 `/sdcard`，
   `MainActivity.java:3934-3966`）；不学 Soodok 那个无障碍服务（声明 `canRetrieveWindowContent`+`canTakeScreenshot`
   却对用户写"不读取屏幕内容"，`strings.xml:38`）。

10. **他今天问的那句"为什么他们装的 APK 功能和网页一样，咱们那个小的缺东西"——答案已经给了，活留到晚上**
    （他原话"等我晚上回来再搞"）。诊断：那三家**就是把那个网页装进壳里**，不重写界面，所以结构上不可能缺功能
    （DSHA 侧证据：WebView 加载本机的 `dsh web`，外面套一层内容脚本清单 `assets/web-integration/manifest.json`，
    匹配 `http://127.0.0.1/*`，`document_start` 一批、`document_end` 一批）；我们装的
    `sorsama/deepseek-harness-mobile` v0.16.0 是**另一件东西** ——
    Kotlin 手写的原生客户端，功能集 = 作者实现了多少，且它钉的协议 `0.2.1-alpha.2` 比设备引擎 `0.2.1-rc.2` 低，
    于是"没实现的就没有"+"不认识的事件被原样透传出来"（他看到的 `job/registered`、"待处理回合 1" 那种碎片）。
    **⇒ 这条不是接线错，是选件错**；14.6 那个做完没装的 78 KB WebView 壳就是对症的那一件。
    晚上开工前先读报告第二节 DSHA 那几段（机制与补丁形状都写在那儿，含一条 `es-compat.js` 是
    **由 `pdf-compat-patch.json` 按"上游模块 + 原文锚 + `dshVersion` 钉版本"前置进去的**，不是靠浏览器插件清单注入）。
    顺序（任务 20，一步都别省）：① 插上手机先读 **WebView 内核包名与版本**，
    **并且把预期摆对：DSHA 那份补丁说明他们针对 Chromium 116 档 WebView 的行为差异做内联修，
    同时仍在前置一整个 core-js 3.50 兼容包** ⇒ "内核新一点就能拆掉兼容层"别默认成立；② 把壳的 token 取法
    **从"打包时烧进 `app/local/url.txt`"改掉** —— 现在这样装上去等于埋一个"服务一重启就打不开"的坑，
    改成读设备上一个文件、或失效时走已有的 `dsh-app://set` 出口粘一次；③ `sh app/build.sh --install` 重打装机，
    验"点开就能用"和"功能与网页一致"；④ 把我们的兼容层从"直接改在网页产物 `dist/index.html` 里"
    **改成声明式补丁**（抄他们的形状：目标上游模块 + `dshVersion` 钉版本 + 一段上游源码原文当定位锚 +
    要前置的资产，锚对不上就当场报错，再配逐资产 sha256 台账）—— 这样"上游一升级就把 polyfill 静默冲掉"
    这条老遗留问题会从"静默失效"变成"装的时候就叫"。
    原生那个 App 卸不卸，等他当场上决定 —— 它是唯一一份"不是网页"的入口，留着当对照也有道理。
    → **这一轮四步全落了，只有第 ④ 步换了形状**（状态 17，读数在 RUNBOOK 14.14）：
    ① **已读**：机上 WebView 提供者是 `com.google.android.webview 130.0.6723.58`（`dumpsys webviewupdate`，
    versionCode 672305833，`Preferred` 与 `Current` 同一份）—— 比 DSHA 补丁注释里那条"WebView 116 把非特殊协议的
    主机放在 pathname"的坑高一个档，**但兼容层现在不拆**：拆它的判据是"App 里没有兼容层也走得完一个真回合"，
    那要他解锁点图标 + DevTools 才看得见，curl 拿不到 JS 异常（列在下面第 11 条）。
    ② **已改掉**：`app/local/url.txt`（活 token）删了，壳的地址写死 `http://127.0.0.1:3081/`，
    一次性 token 由常驻入口在内存里换成 30 天 cookie —— "服务一重启就打不开"那个坑从根上填了。
    ③ **已做**：`sh app/build.sh --install` 重打并装上 0.2，`page-finish｜标题=DeepSeek Harness｜进度=100`。
    ④ **形状换了**：没做"声明式补丁 + 逐资产 sha256 台账"那套，改成**出口内联**（`dsh-entry.js` 在 serve 时
    把 `tools/dsh-compat.js` 插进 HTML，盘上 `dist/index.html` 一个字节不改）。原因是这条把"升级静默冲掉"
    变成了"根本没有可被冲掉的东西"：polyfill 按 mtime 热读、锚点对不上就在 `--entry-check` 里报，
    比"装的时候叫"更省事。**没做的那半**：钉 `dshVersion` 这件事现在只由自测的 46 条判据兜，
    上游页面形状若改到三个锚点全消失，会打 `COMPAT_ANCHOR_MISSING` 而不是装的时候就叫。

11. **兼容层能不能拆，现在有了前提但没有读数**：壳用的是 Chromium 130 的 WebView（上一条①），
    而 HeyTap 40.10.23.1 / Quark 10.18.5.1160 那两个浏览器**仍旧没有** `AbortSignal.any` ——
    所以拆 polyfill 只会让 App 那条更干净、浏览器那条更脆。要拆得先做一次"拔掉兼容层跑真回合"的实测：
    把 `chroot:/root/.dsh/entry-compat.js` 临时改名（入口自己会 `injectMiss+1` 并原样交付），
    他解锁点图标、发一句话、看首字与 `:3081` 自述有没有新增 `最后错误`，验完改回来。
    **这动作要他点头并当场在场**，我不自己在他手机上做半套。

12. **他验收那四个症状里，剩下的都卡在同一件事上：他人在手机旁边解锁点两下**（状态 18 起，读数在 RUNBOOK 14.15–14.16）。
    ~~① 点开图标拍一张屏~~ → **已付清**（状态 19：`downloads/dsh-shot-2040.png` 真渲染、那片代码在屏幕上确实没了）。
    ~~③ 点一次选工作区目录 + 我读非 2xx 环~~ → **已付清**（`POST /api/directoryPicker/list → 200 6ms UA=App`；
    上一版"我猜的 `POST /api/rpc` 带不带 Origin 都 404 ⇒ 选择器还没有读数"那句作废）。
    **还欠的只剩两条**：① 点一次**插件**看跳不跳（`onCreateWindow` 那处改动还没在屏幕上验过）；
    ② ~~按一次返回键把"targetSdk=35 那条推断"变成读数~~ → **0.4 上改成按两下**：
    返回键到不到得了 Activity 已经被他那句"侧滑一下就掉回桌面"解开了，现在要验的是新写的三层
    —— **进一个子页面（比如插件）按一次返回，看是不是退回聊天页；在聊天页再按一次，看是不是弹出"退出工作台？"；
    确认屏上还开着时再按一次，才应该真的回桌面**。三下各对应日志里一行 `back ::`，我读一行就知道走的哪一支。
    0.4 装完我发过一次 `input keyevent 4` 想替他验，结果那一发打在**锁屏**上（手机 21:47:02 就睡了），
    所以这条**只能他在场按**，我不替他解锁。
    → **状态 22 这条我自己验掉了，但语义是他退回重做过的**：0.5 上我用裸 adb 连按了四发（每次都先读到
    `mWakefulness=Awake` 再发），三行 `back ::` 对上三种走法 —— 摊开时按一下只收侧边栏（280→56 px、焦点没走）、
    聊天页按一下飘提示、隔 609 ms 再按一下才真退到 launcher。**他要不要再亲手按一遍算验收，不算欠读数**。
    还欠的一条改成新的：**从「插件」这一页返回到聊天**这件事 0.5 故意没做（页面只给两条带副作用的路，
    见下面第 13 条）。
    他那侧还有一步**必须做**：入口到状态 20 这一轮已经换成 **70,487 B** 那一版，**页面要退出去重开一次**才吃得到，
    挂着的老页面还是旧的隧道逻辑与旧的流水格式。我自己还能做、不必等他的两件照旧：③ **SSE/WS 隧道的背压**
    （`res.write()` 返回 false 时 `from.pause()` + 等 `drain`）—— 状态 19 之后这条从"症状嫌疑"降级成
    "已知没做的工程项"，但仍没做；④ 那 160 ms 与 4 ms 的差要归因，同一批资源在壳里用 `dsh-cdp.js --watch`
    量一遍 Network 时间线（需要他解锁，只在页面上读，不改任何东西），才能分清"WebView 并发排队"还是
    "引擎每请求固定开销"。
    → **状态 20 之后第 ④ 条多了一个更省事的前置**：流水里已经带上 `体Nms` 那一列了，**下一次再看到几十秒的
    请求，先读那一列**（`体 ≈ 总` ⇒ 卡在他那侧的 WebView 冻结；`体` 很小而`总`很大 ⇒ 卡在引擎），
    分开了再谈修哪一种 —— 两种故事的修法相反，没分开之前动手就是猜。读数与那六条 40 秒的原文在 RUNBOOK 14.17。

13. **等他点头的一件小事：从「插件」这类子页面按返回，要不要付出那两条副作用之一**（状态 22 起）。
    他那句"正常点返回，最终退回是退回到聊天界面"里，"侧边栏摊开盖住主界面"那一半 0.5 已经做到；
    另一半（**侧边栏没摊开、但主视图停在插件页**）现在按返回会飘"再按一次退出"，因为页面上回聊天只有两条路：
    点 `新建会话`（**真的建一条会话**）或摊开侧边栏点某条会话（**换掉他当前开着的那条**）——
    再点一次「插件」和发 `Escape` 都切不回去（都实测过）。
    我的荐法：**先不动**。要动的话我倾向"点侧边栏里他上一次开着的那条会话"，代价是要在壳里存一个"上一次
    的会话"读数，且他中途换过会话就会跳错；比起这个，"停在插件页时按返回就是问退不退出"这个行为他其实
    一天碰不到几次。他说要做我再做，并把他选的那条路写进 RUNBOOK。

14. ~~**等他点头的一件有字节的事：语音那条要不要我在他电脑上把那 241 MB 取回来**~~ **已做完**（他一句"提交，然后下模型"，
    状态 23 起 → 2026-10-21 凌晨结掉，读数在 RUNBOOK 14.21 与 14.22）：电脑侧从 hf-mirror 取三份共 **241,357,257 B**、
    逐个 sha256 与包里 `assets.json` 对上、`adb push` 进 `/root/.dsh/speech-to-text/sensevoice/models/`
    （注意是**两个兄弟目录**：`sensevoice-onnx/` 放模型与 tokens、`silero/` 放 VAD，我一开始按 `sensevoice-onnx/silero/` 推过、插件不认）；
    插件那侧 `speech/prepare` **10 秒落 `ready`、零下载字节**（`matchesAsset()` 撞上清单就跳过 `download()`，连 DNS 都不查），
    再拿一句 SAPI 合成的中文实测出字 `text:"今天天气怎么样？我想出门散步。"`（4.24 秒音频、识别 0.10 秒）。
    ~~还剩他那一步：App 里把语音插件关掉再打开，真人录一句（合成音只证明链路通，不证明真人准确率）~~
    → **他已亲手做完并当场结案**（2026-10-21 午后他原话："插件里面把语音关掉再打开…语音已经完全可以用了，问题应该不大；后续再出问题我再跟你说，你也不用再测这个东西了"）：
    **这条从待办里划掉，以后不再测、不再提**；他哪天说语音出问题了，再按当场读数起新一轮。

15. **要他亲手做的一步闭环（零成本）：打开 App → 添加工作区 → 选择工作区目录，看第一屏有没有多出「手机存储」那一行，点进去**。
    引擎那一发返回里这条已经在了（`hidden:false`，顺着进去 `Download` 也列得出来），但**"界面上这一行点得动"我不能替他验**。
    如果他那一屏还是空的，那前端就不是直接渲染 `entries` 这一发，我按他的屏再对一次（那条备用路不依赖这一步：同一屏点面包屑里的 `/` 再点 `phone`）。

16. **等他点头的一件装东西的事：要不要在手机的 chroot 里 `apt install git`**（状态 25 起）。
    背景是他那句"以后难道全得通过电脑下载吗"。量完了：**病在解析不在出口**，解析这层已经在手机上用 `tools/doh-hosts.sh --sync` 自己补好
    （新增 5 条、备份 + sha256 + `--revert` 都在，读数 RUNBOOK 14.22），所以 **apt / npm / GitHub 这三类以后手机上自己能走**，
    只有 **HF 那一类模型**还断着（hf-mirror 的 302 落点 `cas-bridge.xethub.hf.co` 在手机上 0 字节；ModelScope 我猜的三个仓库名全 404，**是没验到、不是没有**）。
    GitHub 这一类唯一的缺口是 chroot 里**没有 `git`**（`p30` ③那一发，与验收第 2 条那句"盘上 git 全未装"是两份独立读数、同一形状）：
    直连速度实测约 **22–26 KB/s**（`codeload` 30 秒传回 790,533 B），
    不下 git 也能拿 tarball，装了 git 才能 clone 与后续 `pull`。**装 = 用 apt 往他机上落包**（源本就配在 tuna，Range 已实测落真字节），
    所以我一行都不动，等他一句话。我的荐法：**装**，代价是一个 git 包体（几十 MB 级、按实测速度十几分钟量级，这数我没实测过，是推的）。
    → **已结（2026-10-21 晚，状态 32）**：他一句"这个需要你去解决一下"，git 与 python3 当夜就装了（22 个包，三个数对账全等），
    随后按《手机端情况.md》B 类把四批一次补齐（dpkg **141 → 411**，读数 `downloads/install-batch-b-20261021-2022.txt`，过程在 RUNBOOK 14.30）。
    我那句"代价是几十 MB / 十几分钟"也被现值替掉了（数从机上 apt 自己的日志里 `grep` 出来的，
    `grep -hE 'Need to get|After this operation' /root/.dsh/apt-install-*.log`，不是我估的）：
    下载 **22.0 + 1.938 + 92.6 + 121 + 2.118 ≈ 239.6 MB**（git/python3、pip、编译、媒体文档、杂项五发），
    apt 自己声明的落盘 **106 + 10.3 + 319 + 414 + 13.5 = 862.8 MB**；我这轮实量的 `df -k /` 净增 **1,034,808 KB ≈ 1,060 MB**。
    **这两个数不冲突，但也对不平**（**下面是推断，不是读数**）：862.8 MB 之外还有一份没算进"additional disk space"的下载缓存
    `/var/cache/apt/archives` = 242,000 KB ≈ 248 MB（324 个 .deb，我**没清**，`apt-get clean` 一条能退），862.8 + 248 = 1,111 MB，比实测多约 51 MB ——
    apt 那个数是**包内声明的估算值**，`df` 是文件系统实测，两者本就不该逐字节相等，**51 MB 这个残差我没查明**。
    慢的不是网速而是 dpkg 配置那 270 个包。**这条现在欠的只剩一件**：`Bash` 在 `workspace-write` 下**仍然拒绝执行** —— 装工具不解决沙箱接线（#40，等他）。

17. **一件周期性的事，现在没人做：`bash /root/doh-hosts.sh --check`**。钉进 hosts 的 IP **会漂**（`cdn.npmmirror.com` 那条
    `223.109.3.139` 这轮已经不在 DoH 给的 16 条答案里了，只是它还连得上 ⇒ "钉旧了"不等于"坏了"）。
    不周期对账，哪天 apt 或 npm 突然坏，第一眼会误判成"网络又不通了"。要不要我把它挂进那条开机服务，等他点头。

18. ~~**新图标那发 APK 还没装机**（状态 26）：`app/out/dsh-app.apk` 152,167 B / sha256 `17c280ac…cb`。
    手机插上后装上就行（`bash app/build.sh --install`，或只推现成这发、走那条 `cp /data + restorecon + pm install`）；
    装完桌面就是那张满幅图，不会再看到白角。**别为了装它临时重打**：同源码重打 sha 就会变，报过的数就作废了。~~
    → **17:48 已装机**（状态 29）：机上 `base.apk` 与本地**逐字节撞 sha**，`versionName 0.6`、`lastUpdateTime=2026-10-21 17:48:31`。
    那句"`bash app/build.sh --install`"当场作废 —— 它前六步无条件重打，**做不到**"不重打"；走的是新写的 `bash tools/install-apk.sh`（只装机），
    以后要复点身份用 `bash tools/install-apk.sh --verify`（只比指纹、不写一个字节）。
    **这条只剩他那一验**：解锁点图标，看桌面那张满幅图（白角没了）+ 点开就能用（与 #22 / #34 同一场）。

19. ~~**电脑上那发 dsh-purge 等他点「应用」**~~ **他已点完**（14:18 那记；改口的读数是 14:31 复测那一发，写在状态 28 末段：`resources\app` 453 M 在位、`.dshpurge.bak` 57 份、
    `dsh.cmd` 562 B 带回退三段、`app.asar` 一字未动）。**这条只剩两句要留着**：
    ① 官方自动更新（`app-update.yml` 306 B 在位）会把补丁冲掉，**更新完要重新点一次「应用」**；
    ② 退干净走它自己的卸载，或 `dsh plugin --profile desktop remove dsh-purge`（CLI 全路径见状态 27）。

20. **电脑上那发 dsh-market 只差他一眼**（状态 28）：它**不需要点「应用」**（自带 patch 只往 profile 层栈插一行），
    而且**也不用重启** —— 装完 2 秒宿主 HMR 就把它组合进去了，正证是 `~/.dsh/profiles/desktop/.dsh-market/`（`state.json` 78 B + `log.ndjson` 124 B，
    北京 14:30:37 落的，日志那行还是它自己跑完网络探域选了 `china`）。
    他现在要做的：**打开客户端 → 账号菜单 → 设置/插件，看有没有那条 Plugin Market**（README 原话：0.2.1 起设置从侧栏搬进了账号菜单；0.2.1+ 还能在 **Plugins → Discover → Index sources** 里加目录源）。
    **如果那一条不在**，先别急着重装：把他看到的屏（或截图）给我，我按 `bundles` 四项 + `.dsh-market/` 这两个文件对一遍，再判是"UI 入口换了地方"还是"bundle 没进栈"。
    顺带提醒：**别顺手一键装目录里的东西** —— 装进来的每一件第三方插件都以 dsh 的权限跑（它 `SECURITY.md` 自己写着 "runs shell commands (`pnpm`, `dsh plugin`, `git`) against the user's own profile, **by design**"）；
    想装哪件先告诉我，我按 purge/market 这两轮的口径先把它的源码、外域出口、写盘动作量一遍再动。
    还有一句要记：我装的是 **npm 的 1.66.45**，仓 HEAD 在它之上多 3 个提交（含 `Fix market self-install target (#890)`）⇒ **市场上"装它自己"出怪事时先想到版本差**，别当成宿主坏了。

21. **他给的那份《手机端情况.md》已经逐条对完表**（过程与依据在 RUNBOOK 14.25，取证脚本 `scripts/dsh-envclaim-probe33.sh` 已写好、~~**还没跑**，手机没插~~
    → **北京 17:57（= UTC 09:57） 跑过了**，读数 `downloads/p33.txt`，摘要在 14.27 七；对表结论里被读数改动的那几条**就地加了箭头**，其中我自己在探针里那句"只数不列内容"是假的、已改口）。
    一句总账：**它没有说谎，但把三种不同的东西说成了一种** —— "没挂进来"（`/system`）、"建好了没接线"（沙箱 runner）、
    "在我们视角外"（自启服务与常驻入口），这三类都补得上；真补不上的只有图形界面、GL 栈、网页 JS 渲染三条。
    今晚插上手机第一件事是跑那支探针，**别拿它那份自述当事实，也别拿我对表的话当事实**，两边都要盘上读数。← **这条也照做了**：两边读数并排写在 14.27 七，dpkg 那格（它 124 / 读数 119）按读数改口。

22. **对表之后新出四件，前三件要他点头、最后一件我可以自己查**：
    ① **接线**（#40）：他自述里那句"文件沙盒不可用、只能完全访问、等于没有隔离"，真因不是内核围不住 —— mount namespace 通的，
       runner 也早验收过（34 PASS / 0 FAIL），只差 `cordis.patch.yml` 里那两行没写。**代价我原来报高了**（当时说重启会让他手机那条入场链接作废，
       那是常驻入口之前的形状；现在入口自己认新一代、重换 cookie，重启只剩那几秒正在跑的会话断掉），但**重启仍要他在场**。
    ② **暴露面**（#41）：它顺手写出"`/phone` 里能看到应用的数据目录"。这条它没说错，是我们当初没算到的口子；
       两把退路（`DSH_WORKDIR=/phone/Download` / `DSH_NO_PHONE=1`）在脚本里现成，挑哪条归他，我不自己摘也不自己扩。
    ③ **Android 接口给不给**（#42）：要 `getprop/pm/screencap/input` 就得把 `/system` 只读挂进 chroot，或者照语音那条形状在宿主侧做窄桥。
       **我倾向窄桥**（能力边界留在我们手里，别一次把整机接口交给模型），等他一句话。
    ④ 装包那批（#32）范围被他这份自述撑大了：先用 `apt-get -s` 把"新装包数 / 要下多少 MB / 多出多少盘"量成读数，再给他两档挑；
       那句"几十 MB、十几分钟"是我推的，读数回来按读数改口。

23. **docs 里那两篇对比报告我读完了，而且没有照着它的清单补东西**（差分表在 RUNBOOK 14.26，读的是
    `dsha-vs-woaiys3-rea-report.md` 与 `desktop-harness-clients-rea-report.md`）。
    做法是反过来：**拿它那 66 条判据回我们自己的三个文件里逐条找证据**（壳 `MainActivity.java` 1,095 行、
    入口 `dsh-entry.js` 70,487 B、`dsh-chroot.sh` 380 行），结果 **20 条我们早就做了**（停止哨兵 / 代次 / 按句柄防重 spawn /
    43 位整行判据 / 常数时间比较 / cookie 回调里才 loadUrl / WebView 三开关 / 传输逐字节撞 sha …），
    **真缺口只有 5 条**，另有整族**不适用**（proot 的 W^X、`--link2symlink`、bionic 那四类原生模块补丁 —— 我们是真 Ubuntu chroot，本来就没这些债），
    它自己警告别抄的六条我们一条都没踩（target 35、`allowFileAccess(false)`、零 `addJavascriptInterface`、单文件无 compat 副本、默认 `workspace-write`）。
    那 5 条已进待办：**#43** 壳那三条（prompt 通道现在只看 `dsh:` 前缀、没有来源校验；没有崩溃处理器；要不要前台服务）＝ **APK 改动 ⇒ 0.7 候选，要他点头，今晚那发不重建**；
    **#44** 503/502 之后不自动重试 —— 这条**有只改入口、不用重装 APK 的便宜路**（`Refresh: 2` 那段 HTML 由入口发），黑屏那条 #25 可能就此自愈；
    **#45** pidfile 没有"出生身份"（`/proc/<pid>` 在就杀，PID 复用风险是推断、没读数）；
    **#46** 手机上缺一份常驻资产清单（现在只在"推的那一刻"撞 sha，"今天还是不是那份"要现场比）。
    顺手做的一件事值得单独记：我当场重跑了 `node scripts/dsh-entry.js --selftest`，**合计 58 条：PASS 58 / FAIL 0**，
    而 14.16 那节抄的是 59 —— **自家文档里的旧计数也会骗人**，已就地加箭头，并把这条写成铁律 12。

24. **手机上这两发插件已经"装好"，但"能不能用"要他眼睛收尾（状态 29）**：我这边三个计数 2/2/2、`list` rc=0、层栈组合成功（`--dump-config` 打出 1,303 行、`dump_rc=0`），
    可"App 里看得见入口"这件事我不能替他看。要他开 App 三处扫一眼：① 设置/插件页里 `dsh-purge` 与 `Plugin Market` 在不在；② 侧栏有没有市场那个入口；③ 预设列表里有没有"红队模式"。
    同场两个决定归他：**purge 要不要点「应用」**（它在这台改的是什么、改得动改不动**未验** —— 手机宿主是 npm 装的全局 dsh，不是 Electron 的解包目录，电脑上那套"解包目录优先加载"在这里没有对应物）；
    **红队模式那套预设留不留**（`~/.dsh/redteam/` 231 K + `.agent-presets/` 47 K + `prompt-inject.md` 24,455 B，那是"去掉拒绝"的人设文本；
    **手机上没有 `applied.json`** ⇒ 到底挂没挂上会话我这侧看不见）。退法现成：`dsh plugin --profile web remove dsh-purge` / `remove dshmarket`，
    推上去那两发在 `/root/dsh-plugins/`（要删说一句，那是我建的文件）。
    另有一件小的也等他一句话：机上那 6 份一次性取证 `.sh`（名字与字节数列在 RUNBOOK 14.27 八）要不要清 ——
    **md5 我已经逐条撞过了：8 份（含 2 份常驻）与仓库件全部逐字节相同**（`downloads/root-sh-residual-md5-20261021.txt`）⇒ 删哪一份都还得回来，不存在"删了丢现场"；
    所以这条纯粹是"要不要让他机上干净一点"，我不自己摘。

25. **一个挂着没定位的现场**：今早 07:17（北京）App 插件页那两次操作里有一次留了
    `Command failed with ENOENT: pnpm why '@deepseek-ai/dsh-base' / spawn pnpm ENOENT`（`.plugin-manager/logs/operation-yUm4kv/pnpm.log`，78 B），
    而 `pnpm` 明明在 `/usr/local/bin`、引擎与入口的 `PATH` 都含这一条（`p38.txt` 1、2 节），另两次操作留的是 0 B 日志（没报错）。
    ⇒ **这条我没定位**，也不顺着猜"App 起的进程 PATH 不一样"。他下次在 App 里真按装包/更新按钮时我再抓现场（探针随时能跑）。

26. **他 18:5x 报的两个症状：市场那半我改完了、图标那半判成缓存（状态 30，RUNBOOK 14.28）**。
    **等他两下，都是他手上那一下，我替他做不了**：
    ① **在 App 里打开插件市场** —— 这是这一格唯一的验收。现在能报的是"目录那两个 host 从 chroot 里取得开了"（不带 `--resolve`：`plugins.json` HEAD **200 / dns=0.000286s**），
       但 `log.ndjson` 停在 **18:40:50**（换代后没人请求过目录）⇒ **"没报错"不等于修好了**。还转圈的话新行必落盘，我按新行继续查。
    ② **把桌面图标删了重放一次**（他挑的那条：不抬 `versionCode`、不重打 APK）⇒ 重放后那张满幅图要是还不换，就得付另一条代价（`versionCode` 抬到 7 重打，
       那发 `152,167 B / sha 17c280ac…` 的装机指纹作废）。
    顺带一笔归他挑的账（**那一下我不替他点**）：`region` 还是 global，第一源是**每次重取、无缓存的 4 MB**；设置里「下载区域」改成**中国大陆**才会先走那条 **2.58 MB 且按包版本缓存**的 npm 路径（代价：GitHub raw/git 改走 `gh-proxy`）。
    退回两条现成：`bash /root/doh-hosts.sh --revert /root/.dsh/hosts.bak.20261021-105919`、`sh tools/deploy-env.sh --revert /root/.dsh/dsh-env.bak.20261021-110024`（**还原后都要再重启一次引擎才吃得进**）。
    **→ 就地补一句（状态 31 那轮核备份清单时确认）**：那条 `-110024` 退的是**本轮之前**那发 1,687 B；`-111700` 退的是 4,738 B（**带 `DSHM_NPM_MIRROR`、只少注释**）。想整格退回今晚之前，用 `-110024`。

27. **项目已经在他自己的 GitHub 私密库里了（状态 31，RUNBOOK 14.29；这轮零设备改动）**：库 = `zhl110/dsh-mobile`（**PRIVATE**），
    本目录从此是独立 git 仓，`origin` 指着它；`D:\mycode` 那个工作区仓照旧跟踪同一批文件（与他另一项目 `agent-hub` 同形状）⇒ **以后每轮两个仓各提交一次**，别只提交一边。
    归他的一件事：**去 `github.com/zhl110/dsh-mobile` 看一眼那形状是不是他要的**（要不要 README、要不要连 `reference/` 那批解包参照一起带上 —— 现在它里面的 `gh-3p/` 与两个上游 clone 都被 `.gitignore` 挡着，进去的只有 `dsh-web-frontend-index.html` 这类小件）。
    还有一条他可能想知道的：`gh` 用的是 fine-grained PAT，**能不能建库当场就见分晓**；若建库被拒，改走 `agent-hub` 那种 SSH 也得他先在网页上手动建好空库。

28. **环境那批已经装完并验到"能真出字"，剩下三摞归他点头（状态 32，RUNBOOK 14.30 二/三）**：
    B 类五批 **270 个包**已进机（dpkg 119 → **411**，磁盘 +1,010 MiB），`git 2.43.0 / Python 3.12.3 / pip 24.0 / gcc 13.3.0 / cmake 3.28.3 / ffmpeg 6.1.1`
    等 **20 个名字 20 个都在位**；pip 那扇门也开了（钉 `pypi.tuna` 之后 `pip download` 与 `pip install --target` 真落字节，装出来的 requests 还真打了一次 `api.deepseek.com`）。
    **等他三句话**：① **pip 走哪条** —— A 装 `python3-venv python3-full`（**21 个新包**，之后 `python3 -m venv` 才起得来）／ B `--break-system-packages`（零安装，python 包能盖 apt 包的文件）／
    C `--target`（零安装，本轮实测通的一条，代价是每次带 `PYTHONPATH`）—— 我按"不替他选"写着，荐 A，因为 DSH 里真跑 python 项目时只有 A 是顺的；
    ② **剩下四摞装不装**（一个都没装，数量是 `apt-get -s` 现场点的）：文档办公 libreoffice-writer + pandoc **84**、OCR tesseract **6**、语言栈 rustc golang-go default-jdk **61**、容器 docker.io podman **29**（这台起不来）；
    ③ **apt 下载缓存要不要清**：现在 **242,000 KB / 324 个 .deb**，`apt-get clean` 一条就能退，我没动。

29. **横屏侧栏：注入层已经证实生效，屏幕上那一划只能他来（状态 32，RUNBOOK 14.30 五）**。
    改的是 `tools/dsh-compat.js`（3,123 → **9,793 B**，md5 `268f90ad…`，已逐字节推上机 `/root/.dsh/entry-compat.js`，入口读入 8,265 字符）：
    按页面上真存在的四字"新会话/插件/插件市场/自动化任务"定位那一列，横屏时给它 `overflow-y:auto !important`（上游 CSS 里 `sidebar`/`aside`/`_rail` 命中**全是 0**，写不了类选择器）。
    **我能报的到"内联段 9,794 B、`</script>` 14 / `<\/script>` 1、`injectMiss=0`"为止**；手机此刻 `mWakefulness=Dozing`、壳 App 不在前台，
    而 CDP 那条路第一步就查醒屏、Dozing 直接拒跑（`scripts/dsh-cdp.js:113`）⇒ **我没解锁、没强拉前台、没替他看**。
    要他做的：解锁 → 点图标 → 转横屏 → 在左边那一列上下划一下。划不动就把屏幕状态告诉我，我按新证据再改锚点。

30. **这台机的网络是"钉出来"的，所以 `doh-hosts.sh --check` 得当成常规体检（状态 32）**：
    UDP 53 废 ⇒ 所有能用的域名都靠 `/etc/hosts` 里那 **29 条**（`tools/doh-hosts.sh` 的 `LIST_PIN`），而**IP 会漂** —— 钉过的那条坏了以后，症状不是"解析超时"而是"连到假 IP"或"被拒"，比原来更难查。
    建议节奏：每次真出现"某个功能突然取不到东西"，先 `bash /root/doh-hosts.sh --check`（只读，逐条比 hosts 里的 IP 与 DoH 现在给的答案），再决定 `--sync`；
    `--sync` 前自动逐字节备份、sha 撞了才写，退法是 `--revert <备份>`，本轮两发备份分别是 `hosts.bak.20261021-123435`（pypi 那条）与前一格的 `-105919`（市场两条）。
    另有一件纯"要不要让他机上干净点"的：chroot `/root` 里我留了 **9 份 `.sh`**（含探针），md5 与仓库件逐字节相同 ⇒ 删哪份都得回来，**我不自己摘**。
    **→ 深夜改口（状态 33，`downloads/p61.txt`）**：那份数是探针把自己也数进去得到的 **9**，runner 跑完实际留 **8 份**；
    `/tmp` 里我的东西已从 **33 项清到 4 项**（删的 29 项全是我建的、逐条打印过），剩下 4 项是引擎与插件的（`dsh-subprocess-*` / `dsh-spill-*` / `dsh-purge-desktop.log`）—— **一样要他点头我才动**。

31. **GitHub 这一跳今晚是死的，所以"手机上的 git 能不能干活"要分开答（状态 33，RUNBOOK 14.31 四）**：
    我这轮用真 clone 证明了**走 gitee 能干活**（`git clone --depth 1 https://gitee.com/mirrors/git.git` → rc=0、76,737 KB、4,857 个文件、`status` 0 行，复点后删净），
    也证明了**走 GitHub 今晚不通**（curl `(28)` 超时 / `/dev/tcp` 说连上 / node TLS 8 秒没动静，三种口径都 **0 字节**；`codeload` 超时、`objects.githubusercontent.com` 反倒活着），
    连 `gh-proxy.com` 那条退路也被重置（`(35) Connection reset by peer`）⇒ 我把 github 那几条**没有**重钉（钉哪个都不落字节，钉了只会把"超时"变成"被拒"更难查）。
    **等他两件事**：① **要不要给 DSH 里所有 git 命令配一条 gitee 镜像路**（做法现成：`git config --global url."https://gitee.com/mirrors/".insteadOf "https://github.com/"`，
       一行、可 `--unset` 退回；**我没动他的 git 配置**，因为这台机上 `git clone github.com` 从此走谁是个长期口径，该他定）；
    ② 换个时间让我再打一次 github（这条路由在漂，昨天还能 30 秒传 676 KB）—— 判"通"只认落字节，判"死"要分**超时**与**快速失败**（今晚是超时那一型）。
    **→ 22:1x 这条被状态 34 的读数解掉一半（就地加箭头，旧话不删）**：① 那行 `insteadOf` 我 21:5x 真装了，**形状是错的** —— gitee 的 `mirrors` 组织**不带 owner 段**，
       整段前缀替换会给每个仓拼出 `…/mirrors/<owner>/<repo>` 那种 401 的 URL（`gitee.com/mirrors/git` 200 / 134,344 B，`…/mirrors/git/git` **401 / 40 B**）；
       规则**已撤**（撤完剩 **0 条 `url.*`**），真要钉只能**逐仓一条**：`git config --global url."https://gitee.com/mirrors/git".insteadOf https://github.com/git/git`。
    ② 我也真重打了 GitHub：**同一发对照里它 200 / 353,218 B / 15.09 s**，撤规则后 `git ls-remote` 真回 SHA（`git/git` `47fdf220…`、`golang/go` `ace5a752…`）
       ⇒ **"要不要配镜像"这个问题今晚不成立**（三个镜像候选今晚全 rc=6 / 0 字节，而正主活着）；`rust-lang/rust` 那条 **rc=124 是我给的 40 s 超时**，仓大不是路由坏。
       **判据不变**：这条路由在漂，只认当次落字节。

32. **四批工具包：数已经重量成两口径 + 并集，装不装仍等他点头（状态 34，RUNBOOK 14.32 五）**：
    旧那句"还剩四批 ≈ 84/6/61/29 个包"**两处作废**（61 真值 **63**；且只有一口径、四个数还**不能相加**）。
    现在能给他挑的是：文档办公（写 docx/odt + 格式转换）**161 / 84** 个、**135.9 / 123.7 MB** 下载、**612.2 / 559.9 MB** 占盘；
    OCR（图片认字）**6** 个 / **8.0 MB** / **21.7 MB**（**这批最便宜，想要认字就装它**）；
    语言栈（编译 Rust/Go/Java）**103 / 63** 个 / **268.8 / 262.8 MB** / **981.3 / 958.5 MB**；容器（docker + podman）**78 / 29** 个 / **103.4 / 84.2 MB** / **425.5 / 355.8 MB**。
    **四批并集 = 281 个 / 503.4 MB / 1,992.2 MB**（不含 recommends **159 / 475.6 / 1,886.0**）；盘不缺（`/` **340 G 可用**），缺的是时间与流量。
    **我建议不装"容器"那批**：这台 `# CONFIG_USER_NS is not set` 且没有 cgroup 委派 ⇒ 425 MB 换一条起不来的路（《手机端情况.md》A 类第 11 行自己也写了）。
    还有一件口径要说清：装多少包**不等于 dsh 里的 Bash 能跑** —— 而**本轮查出更根本的一条**：purge 在位时**根本没有围栏**（见第 33 条），
    所以"装完包 Bash 就能用"这件事现在的障碍不是围堵，而是**没有任何一条真回合验过**。**apt 缓存 237 MB / 324 个 .deb 我没清**（`apt-get clean` 一条能退）。

33. **purge 那三档归他挑，而每一档的判据都是同一件只有他能做的事（状态 34，RUNBOOK 14.32 三）**：
    现在盘上的事实是 —— 这台机 web profile 里 purge 已应用（上游 **42 个文件**被改、**56 份** `.dshpurge.bak`，北京 18:35），
    `confine()` 被换成"永不包装 argv"、`checkedTarget()` 不做越界检查、审批弹窗**先回 `allowed-once`** ⇒ **没有进程围堵、文件工具没有围栏、档位那个 UI 是装饰**。
    三条路（**代价各不同，我不替他选**）：
    ① **留着 purge**（现状）＝所有工具直跑、无弹窗、`runnerCommand` 接了也不生效（我已**逐字节撤干净**，两行原文在 `config/cordis-sandbox-wiring.snippet.yml`）；
    ② **撤 purge + 接 runner** ＝真围堵回来，但这台 `# CONFIG_PIDNS is not set`，runner 靠 `DSH_UNSHARE_RUN_ALLOW_NO_PIDNS=1` 降级跑
       ⇒ **被围命令能看见宿主 pid 并可 kill 它（含 dsh 自己）**，而且 #18 那个 `/dev` 裸设备窟窿还没堵；
    ③ **撤 purge 不接线** ＝回到"Bash 全灭、原生 read/glob/edit 能用"那个旧形状。
    **无论挑哪条，第一件要做的都是同一件我做不了的**：在 App 里让 Agent 跑一条 `echo` —— 它现在能不能跑、有没有弹窗，是这三档共同的判据；
    而我这边**只有代码判据、没有真回合读数**，所以 14.30 那句"Bash 在 `workspace-write` 下明确拒绝执行"我只能判它**作废**，不能反向宣布"能用了"。
    **撤 purge 我不会自己动手**：那 42 个文件是他装插件时点「应用」留下的，动它＝动他的东西。退法在插件侧：`dsh plugin --profile web remove dsh-purge`。
    **→ 22:5x 这一条两问都答完了（就地加箭头，旧话不删）**：他原话"**不撤，插件你先不用管**"＝**选 ①，②③ 关掉**；那条共同判据（"App 里跑一条 `echo`"）**不用他做了** ——
    手机侧那个 dsh 自己 14:39:47Z 跑了 `apt-get install -y --no-install-recommends ripgrep jq` 并**真装上**（`dpkg.log` 8 行、411→415），
    ⇒ 现状读数到手：**`workspace-write` 档位下命令真执行、没被拒、没弹窗**（＝没有围栏）。判级仍是**强推断**：命令串＋安装时刻两条独立来源，不是引擎侧进程审计。
    **本条结案**；后续所有"围堵/接线"话题都从属于"purge 不撤"这条裁决 ⇒ **挂起**（含 #18 那个 `/dev` 窟窿、含它自己问的 `setpriv` 降权实验）。
34. **手机上的 dsh 现在是**第二个写手**，接班口径要按这个改（状态 35，RUNBOOK 14.33 一/三）**：
    北京 22:43 那一轮它自己改了 cordis、自己 `kill -TERM` 换了代、自己装了包 —— 这些都不是我做的，但**读数全落在同一个盘上**。
    ⇒ 以后每轮接班先撞这三份再说"现场没变"：**cordis 508 B（撤干净）/ 1,627 B（它接回的死配置）**、**dpkg 411 / 415**、**引擎代际与 pid**（现在第 6 代 28833）。
    同一条规矩的另一半：**判 `confine()` 这类行为只读真在加载的那一份**（`…/dsh/node_modules/@deepseek-ai/dsh-sandbox-local/lib/index.js`，md5 `b976570f…`），
    别读 `dsh-purge/host-backups/*.bak` —— 那是 purge 动手前的原件，读了就得错结论（它这轮正是这么错的，p75 第 36 条命令）。
35. **两个一句就够的小选择（我不替他选，也都可逆）**：
    ① **cordis 那两行撤 / 留** —— 留＝盘上挂着一条**死配置**，且它写的注释里那句"`confine()` 走 :311 那条分支"是错的（将来谁照注释读都会被误导）；
       撤＝盘上恢复"命中 0"，两行原文我在 14.32 已存进 `config/cordis-sandbox-wiring.snippet.yml`，它自己的备份也在（508 B、sha 与我那份逐字节相同）⇒ 撤/再接都不丢东西。
    ② **我 10-19 落在他 `/data/local/tmp` 的 8 件清不清** —— 4 件与仓库孪生件 md5 全等（`dsh-devnull-inner.sh` `d8286f06…`、`dsh-dev-node-probe.sh` `66ad979b…`、`verify-unshare-run.sh` `8225b290…`、`dsh-sbx-probe.sh` `fc58a2ce…`）、
       `cfg-before.txt` / `cfg-after.txt` 两份同 md5 `99f9cbe8…`（内容与本地件全等），**`env10150.txt` `3d54cfe1…` 与 `w.xml` `d063260b…` 本地没有孪生件** ⇒ 要清就先 pull 回仓库再删，别直接 rm（表在 RUNBOOK 14.33 八）。
       他那批（`boot_b.img` / `init_boot_b.img` / `kpatch/` / `magiskboot` / `sukisu_*.ko`，同目录共 71 条）我一个不碰。
36. **附件这一发只剩"按发送"那一下（状态 36，RUNBOOK 14.34 三⑦/四）**：他在工作台输入框里现在挂着 `dsh-upload-test.txt`（92 B）那发待发附件 —— **按下发送**我就用 `dsh-app` logcat ＋ 入口 `/__entry_status` 的请求流水复点"字节真过了 `:3081` → `:3080`"；不想验点 × 撤掉即可（撤了我再把 `/sdcard/Download/dsh-upload-test.{txt,png}` 两件测试件删干净）。
    同一张表上还挂着三格**只有他能答**的事：插件/skill 上传要不要真选一发（选＝往他引擎里装）、`navigator.clipboard` 那 3 处复制按钮到底通不通、页面里有没有真会用 `download`/`blob:` 与 HTML5 全屏（这两条壳**没接**，接到了才可能"点了没反应"）。
    **→ 状态 37 改口（旧话不删）**：这三格后两格本轮已答完 —— 复制按钮**通**（不需要壳）、剪贴板**读不通**（`NotAllowedError`，壳侧无钩子）；下载与全屏**页面真在用**（pdf 预览的 `a.download`、文档预览的 `<video>`），壳 0.10 已接并实测。剩在这一格上的**只有他按那一次"发送"**，加上插件那发要不要真选。
37. **剪贴板"读"要不要垫桥 —— 等他一句**（状态 37，RUNBOOK 14.35 五清单第 4 条）：`navigator.clipboard.readText` 在这台机上回 `NotAllowedError`，WebView 不给壳任何回调 ⇒ 结构上没有"接上"这个动作。能用 `prompt` 通道 + 原生 `ClipboardManager` 垫一发桥（约 30 行，走本轮 `dlname` 同一条通道）让它返回内容；代价是**又多一处往页面注入、且那条通道没有来源校验**（task #43 挂的就是这个）。不垫也有绕法且已实测通：长按 → 系统粘贴，或软键盘粘贴键。**用的人**：excel 与终端那两个包里的"粘贴"按钮。
38. **本轮接完的三条还剩两格没实测，都是我有意留的**（状态 37，清单第 3/5 条）：① 下载 `data:` 那条路只有代码没跑过（真页面上我没造出走 data 的那发，blob 与 http 都造出来了）；② 全屏验的是我注入的同形状元素，**没在他的文档预览里真开过一次**（那要动他的会话内容）。他哪天在文档预览里点视频全屏或 pdf"下载"，我用 `dsh-app` logcat 复点即可；`blob` 超 8 MiB 会 toast＋记日志（不会静默失败），要不要放宽也是他一句。
39. **他这一问暴露出我那两条"其实随时能修"，走法给他挑**（RUNBOOK 14.36 三）：① **报错后不自动重试**（503/502 那一屏）—— 最便宜的做法只改常驻入口：对"主帧导航"那发请求回一段带 `Refresh: 2` 的最小 HTML 而不是纯文本，`tools/deploy-entry.sh` 推上去就生效、**不用重装 APK**；② **重进后黑屏十几秒**大概率与①同源（那段时间入口回的就是 503），所以①落地后还需要一个他在场的窗口重测一遍，才知道有没有自愈。另：复点时撞到**在市场里装插件报 500**（`cannot get required service "loader" in inactive context`，北京 23:41 那两行）——不是我这轮做的动作、根因未查，**要不要我查这一格**（#65）。 **→ 00:2x 结案**：他答"能装，我已经测试过了，装了几个插件了，能用，没问题"⇒ 不查、不再提，只剩上面那两条（黑屏／不自动重试）等他挑走法。**→ 00:3x 他又一句"就这样吧，等我使用过程中出现问题了再调整再说"⇒ 这两条按挂起处理，我不主动改代码、也不再去问要不要改**；真要动的时候判据现成（14.36 三那两条：入口回带自动重来的最小 HTML ／ 黑屏那段时间入口回的就是 503）。
40. **即装即用这一格只差"手机回来取数"那一步**（状态 38，RUNBOOK 14.37）：脚本与判据都在仓里了（子仓 `b5ff594` 已上 GitHub、父仓 `4f083967`），
    **包没打成、Release 没建** —— 因为手机在 11-02 那一轮中途掉回 `offline`。他那边要做的只有一件：**重插 USB / 在弹窗里勾"一律允许"**（或撤销调试授权后重授）；
    `adb devices` 回到 `device` 之后就是两条命令：`bash tools/make-payload.sh --dry`（先看普查有没有敏感形状命中保留集）→ `bash tools/make-payload.sh`（出包 + 两道闸门 + `SHA256SUMS`/`payload-meta.txt`），
    然后 `gh release create` 把那一发挂上 `zhl110/dsh-mobile`。**下一步之后还欠两格**：① `install-from-scratch.sh` 从没实机跑过（要第二台机或干净 rootfs）；② Release 传得上去何等速度未验（那把 fine-grained PAT 能读能建库，**资产上传权限本轮没测到**）。
    **→ 状态 39 更正两条（旧话不删）**：② 那格今晚量掉了 —— canary 一发 80 B 资产**上传成功**（`gh release view --json assets` 读回 `size=80`），建/删 Release 都有权，只剩"GB 级要多久"没量；
    ① 那句"先看普查有没有敏感形状命中保留集"**判据作废**：词形普查在本机同型树上必然误报（`password` 43 个文件），闸门一现在是"**已知凭证串回归**"，
    并且出包前会先在本机跑 `bash scripts/dsh-payload-pack.sh --selftest`（今晚 **3/3 PASS**）。
    **→ 状态 40 更正两条（旧话不删）**：那"两条命令"已经压成**一条** —— `bash tools/make-payload.sh --publish`（自测 → 普查 → 取流 → gzip → 两道闸门 → 指纹/元数据 → 切卷 → `gh release create` → 读回资产）；
    ① 那格按他一句"先不验证，直接提交"**不再是发布前提**，改为在 `docs/INSTALL-from-scratch.md` 与 `payload-meta.txt` 里明写"未经干净机验证"（自测从 3 条长到 5 条，11-03 本机 `PASS 5 / FAIL 0`）。
    **→ 状态 41 结案（旧话不删）**：这一格里"包没打成、Release 没建"**已翻案** —— 11-03 21:2x 真包（945,106,711 B / 条目 112,172 / sha256 `ea33b2b0…`）已挂上 `payload-20261103-132346Z`，三件资产读回 `state=uploaded` 且 digest 与本机逐字节撞上。
    那条"一条命令"也真跑通了（`--publish`），但**它的形状变了**：不是"取流→PC gzip"，而是"机上 `tar -czf`→`adb pull`→三方复点"，因为这台机的 adb 带不了二进制流（RUNBOOK 14.40 二）。
41. **手机回来之后，出包前只有一格还需要判断**（状态 39，RUNBOOK 14.38 八）：`--census` 第 4 节会报 `/etc/shadow` 里 root 那栏**有没有哈希**。
    "锁定/无哈希" ⇒ 可以随包走；"**有哈希**" ⇒ **不能随包走**（GB 级产物一旦公开，离线爆破是他机上那把锁的事），要在设备上把 root 栏改成 `!` 再打 ——
    那是**改机上系统文件**，做之前先备份、改完逐字节复点，并且**跟他说一句**再动。读数今晚拿不到（手机不在）。
    真包出来后 `gh release create <tag> release-assets/dsh-rootfs-<UTC>.tar.gz release-assets/SHA256SUMS release-assets/payload-meta.txt`（**资产名别以 `.` 开头**，gh 会改名）。
    **→ 状态 40：这格作废，不需要读数也不需要他点头了** —— 走的是比"看一眼再定"更安全的默认：**`/etc/shadow` 原件永不进包**（进 `DROP`），
    `--pack` 时用 `stage_shadow()` 现造一份 root 栏 `!`、其余行原样的替代件，装机脚本 **3b** 放回。所以"root 到底是不是哈希"这件事**不管是哪种答案都不改做法**。
    那句 `gh release create …` 也并进 `--publish` 了（切卷时只传卷）。全文 RUNBOOK 14.39 二。
42. **分发线现在只剩"在别人机上真装一遍"这一格，而且它需要他给一台机**（状态 41，RUNBOOK 14.40 六/七）：包与 Release 都就位了 ——
    `bash tools/install-from-scratch.sh`（不传参数就自己 `gh release download` 取那三件、撞 sha、**在设备上以 root 解压**、3b 放回 `/etc/shadow`、推四件、起入口、烤口令、装 APK、跑体检）。
    **他那边要做的只有一件**：给一台**已 root 的 arm64 Android**（自己的机也行，但那台现役机别跑这脚本 —— 它头部有"目录非空就停"的闸）。
    另外两格**只有他能判，我不替他选**：① **库现在是 PRIVATE** ⇒ 外人下载不到那三件资产；要让别人装上得开公开（或把 Release 单独挪到一个公开库）。② 包里带着 `dsh-purge` 那 **46 条 `redteam`** 源文件（他装的插件本身）—— 要剥就是在 `DROP` 里加一行的事，剥了那插件缺文件。
    **→ 状态 42 更正 ①（旧话不删）**：他一句"把仓库改成公开"，库已 **PUBLIC**（`gh repo view` 复点 `PUBLIC isPrivate=false`），匿名 Range 复点外人真下得动（**206 / 1024 B / 头四字节 `1f 8b 08 00`**）；② 那格**没动**，46 条仍随包走。全文 RUNBOOK 14.41。
43. **已公开的历史里那四项要不要收回，只有他能判**（状态 43，RUNBOOK 14.42 二）：本轮把**现役文件**遮干净了（序列号 / 本机用户名与带它的家目录路径 / 提交邮箱 / 签名库口令默认值），
    并且立了 `tools/check-private.sh` 让下一轮起不再新增 —— 但**历史改不了自己**：`git log --all -p` 复点是序列号 8 行涉 5 发、用户名 12 行涉 6 发、邮箱 36 行涉 4 发（大头是每发提交的 Author/Commit 元数据）、口令默认值 3 行涉 1 发。
    要真收回只有两条：**改写历史 + 强推**（所有提交号作废，父仓与那枚 `payload-20261103-132346Z` tag 的指向都要重对）或**删库重建**（Release 三件资产要重挂）。两条都是不可逆动作，**我没做，也不该顺手做**。
    只补一句读数：那把签名库的私钥**没入库**（`app/local/` 已 gitignore，库里只有口令默认值），所以这四项里真正"能被人拿去用"的一条都没有 —— 剩下的都是**可识别**，不是**可利用**。全文 RUNBOOK 14.42 二/七。
44. **控件树"只读"这一步做完了，下一步"点/输/手势"与"引擎接线"都等他点头**（状态 44，RUNBOOK 14.43）：壳 0.11 的 `TreeService` 已在机上验通（ping→pong、38 项树、开关他自己开的、重装后开关没掉）。**接下来两格我不自己动手**：① 要不要做操控（tap/type/scroll/key —— DSH Go 那套三层点击＋settle 等待的形状已调研清楚，证据在忽略区 `downloads/dsh-go-*`；屏外/零宽坐标那条提醒写在 14.43 五）；② 引擎侧要不要接成 MCP 工具（现在 socket 只有探针客户端，引擎还"用不上"这棵树）。另：**代码六件＋文档三份已暂存未提交**（铁律 9），他一句"提交"就走，提交前隐私闸门读数回填在 RUNBOOK 14.43 七。


## 遗留问题

- **dsh 0.2.1-rc.2 结构上就没有终端 UI**：`--profile tui` 报 `profile "tui" does not exist`，
  `headless` 是一次性任务（补丁里 `credentials`/`authorization` 都 disabled）。所以"对话"这一面只能挂在 Web 上，
  终端那面（菜单 5 项）是 Ubuntu shell + 命令行跑 dsh，不是 REPL。这条不是我没做，是这个版本没有。
- 装的 Termux 是 GitHub 官方 release 的 **`github-debug` 签名**构建（F-Droid 那路在这台 PC 上被 DNS 污染，
  只有 gh-proxy 通）。debug 签名 = 能连 adb 的人可 `run-as` 它；key 不在里面。想换签名就卸了重装。
- Termux 第一次 `su` 能不能批下来 —— **已验**（2026-10-20 00:11 拍屏）。Web 里登录能不能真回来，
  现在只剩「HeyTap 打开授权页并回跳」这一跳没验（服务端那跳已过，见状态 7）。
- **手机浏览器是这套方案最脆的一环**：这台机器上只有 HeyTap 40.10.23.1 与 Quark 10.18.5.1160，
  都没有 `AbortSignal.any`。~~我补的 polyfill 是打进 vendor 包（`dsh-web-frontend/dist/`）的，
  **升级 dsh 会被冲掉**~~ → **这句的"打进 vendor 包"已经被换掉**（2026-10-20 晚，状态 17）：
  兼容层现在由入口在 **出口内联**（serve 时插进 HTML，按 mtime 热读 `tools/dsh-compat.js`），
  盘上 `dist/index.html` 876 B、`grep -c data-dsh-entry-compat` = **0 行** ⇒ **"升级把 polyfill 静默冲掉"
  这条现在不成立了**（没有可被冲掉的落点）。早轮真打进 `dist/` 的那份 `dist/assets/dsh-compat.js`
  **原地留着**（与内联那份逐字节相同、幂等），删它要动 vendor 目录，不值一次写入。
  → **这两句在状态 18 那一轮都要改口**：① "0 行"只证明**我那版**没往里写，文件本身当时还带着更早一轮打进去的
  51 B（825 → 876），所以"盘上一个字节没改"当时**不成立**；现在真还原了 —— `dist/index.html` **825 B**、
  md5 `5a1bf510…` 与仓库 `reference/dsh-web-frontend-index.orig.html` 逐字节相同，`assets/dsh-compat.js` **已删**
  （补丁那版备份在 `/root/.dsh/index.html.patched-876.bak`）。⇒ 结论没变、依据变了：**"升级不会冲掉兼容层"
  现在是真成立的**，代价是盘上少了一份现成的补丁版首页，要推回去得从 Windows 侧 `reference/` 推。
  ② 内联这件事本身还咬过一次：polyfill 注释里原样写着 `<script src=…>`，HTML 解析器看到第一个 `</script`
  就闭合元素，把 2.6 KB 源码漏成屏幕上一片代码（他验收报的第一个症状）⇒ 现在内联前过一次 `escapeForInline()`，
  判据是"我们这段之后紧跟的是不是标签"，细节在 RUNBOOK 14.15。
  "正解是装 Chrome/Edge 116+"这半句仍然成立但**不再是前置条件** —— App 这条走的是机上
  `com.google.android.webview 130.0.6723.58`，浏览器那条才归那两个内核管。
  → **这句"116+ 就能整个删掉"要收窄**（2026-10-20 读 DSHA 拿到的反证，报告第二节）：那份
  `pdf-compat-patch.json` 同时干两件事 —— 给上游 PDF 预览模块**前置一整个 core-js 3.50 兼容包**，
  以及内联修一处注释写着"**WebView 116 把非特殊协议的主机放在 pathname**"的行为差异。
  ⇒ **他们在 116 档内核上仍然挂着兼容层**。所以"换个新内核"能解掉 `AbortSignal.any` 这**一条**，
  解不掉"上游前端用到的东西比内核新"这一整类；换内核与"把兼容层改成声明式补丁"是两件事，别并成一件。
- **工作区 = 整个内部存储**（`/phone`），`workspace-write` 权限下 Agent 真能改他照片和下载目录。
  要收窄：`DSH_WORKDIR=/phone/Download`；要完全不挂：`DSH_NO_PHONE=1`。这条我按他"要读到手机"的原话做宽了，
  收窄只要一行，等他一句话就能拨回去。
- UI 里那个 key 输入框**清空再保存不会删掉已存的 key**（placeholder 明写"留空使用已保存凭据"，实测），
  删只能走 `scripts/dsh-clear-key.sh`。key 在盘上是明文（0600）。
- `dsh-setup-in-chroot.sh` v3 是真实过程的回写，**没在干净 rootfs 上整跑过**。
- 53 端口被拦这件事只在移动数据环境下测过，换 Wi-Fi 未复测。
- dsh 是 `0.2.1-rc.2` 的 rc 版；升级后 `apiKeyEnv` 这类默认值要重新 dump 一次配置核。
- 本轮手机侧网络增量的进程级归属没做：`rmnet_data4` rx 从 4,786,914,973 涨到 4,990,513,224
  （约 194 MB），大头应是手机上那次 `npm i -g`（装完 888 M），但没按 uid/进程拆过，别的 App 也计在里面。
- **服务死过一次，原因没查到**：本轮接手时 `:3080` 零监听、pidfile 不存在，但设备没重启（`uptime` 289,844 s）、
  `MemAvailable` 8 G 不是 OOM、`/data/local/dsh.log` 尾部也没有退出行 —— 拿不到是谁杀的。`--web` 重起后 pid 10150、200。
  下次再死要先 `logcat -b crash` + `dmesg` 抓一遍才算查过。
- **那个 `danger-full-access` 我说不清是谁批的**（详见状态 10）。它现在和"工作区 = 整个内部存储"叠在一起，
  是这套东西目前最大的暴露面：Agent 发的 shell 命令不再问一声就能动他照片与下载目录。
  批档那条记录写的是 `source.kind: user`，但当时我在盲操作他的屏幕 ⇒ 只能按"可能是我碰的"记。
- **原生客户端钉的是 dsh 0.2.1-alpha.2**（它 README 自陈，另有 0.2.0-rc.1 / 0.1.7-rc.x / 0.1.6-alpha.x 的兜底），
  我们跑的是 **0.2.1-rc.2**。症状对得上：界面里会漏出 `job/registered`、`job/settled`、`待处理回合 1` 这种它没认的事件原样，
  它文档说"未知事件与内容透传"，所以这是**显示层不干净，不是链路坏**（真回合数与 tok/s 都读得出来）。
  升级 dsh 之前要想到这一层可能更花。
- **它那个「局域网模式」明文**：仓库 SECURITY.md 自陈 "Local-network mode authenticates but does not encrypt"。
  我们走的是本机模式，暂时不相干，但哪天想从 PC 连手机别照它那个模式裸奔。
- ~~**`token 每次重启服务都会换**（`dsh.log` 里数得出四条不同 token），所以"点开就能用"目前只在服务不重启时成立；
  中继模式能绕，但要在 web profile 里 `dsh plugin --profile web add dsh-relay`，这轮没装没验。~~
  → **这条已经被解决掉，用的不是 relay**（2026-10-20 晚，状态 17）：常驻入口 `scripts/dsh-entry.js`
  替客户端盯着那行启动日志、在内存里把一次性 token 换成 30 天的 `dsh-auth-*` cookie，
  壳 App 的地址永远写死 `http://127.0.0.1:3081/` ⇒ **token 换多少次都不用他动手**。
  读数是入口自述 `gen 1`、`auth cookie 有`、`token 待用 无`（用过即清）与 `reauth=0`。
  还留着的两半：① 换 cookie 这件事现在是**入口活着时才成立** —— 入口自己是关机的第一环，
  `50-dsh.sh.off` 那条自启今晚已经改成起入口，但**真重启一次没验过**（下一步第 5 条）；
  ② relay 那条路仍然没装没验，现在也不需要了。
- 取证脚本 `tools/decomp-session.js` 有个坑值得记：`session.v4.jsonl.zstd` 是**多条 zstd 帧拼起来的**，
  `zlib.zstdDecompressSync` 只会解出第一帧（186 B 那个头），要按 magic `28 b5 2f fd` 切帧逐帧解才拿得全（真文件 114,181 B / 66 条）。
  这台 rootfs 里没有 `zstd` CLI，node v22.20 自带 `zlib.zstdDecompressSync`。
- **围堵 runner 的 34/0 不等于"围住了这台机"**（状态 13 / RUNBOOK 14.11 第四节）：`/dev` 原样不动 ⇒
  253 个裸分区节点对同为 uid 0 的被围命令敞着；`--die-with-parent` 收下但做不到（后台进程不会随父退出而死）；
  本机无 PID_NS ⇒ 被围命令可 kill dsh 自己。这三条都在脚本头部写着，别只读验收计数就下结论。
- **`chroot: Operation not permitted` 那一发**（状态 14）：~~成因没查~~ → **本轮按"重发一遍就有分晓"去做，
  两半都有结果**：环境没坏（`--status` 五项读数齐、同一趟五处写入全 rc=0），成因拿到同一形状的复现
  （`su -c` 的引号被截断 ⇒ `;` 之后以 uid 2000 跑 `chroot`）。逐条读数与"只能写到'最可能成因'"那句口径在状态 14。
  原来的规避（测试件放 `/data/local/tmp`，那边同类操作全 rc=0）**现在不是必需了** ——
  本轮所有 chroot 内外操作都走 `tools/deploy-entry.sh` 里那对引号，机制写在该文件头部。
- **本轮的验收全是"我直接在 chroot 里调 runner"**，dsh spawn 它的那条链路（含 `workspaceRoot` 怎么填进来、
  denial 签名怎么被上层识别成权限拒绝）一次都没跑过。接线之前，14.11 那句"围得住"只在 shell 层面成立。
- **三家对比报告是纯静态阅读**（状态 15）：没装过任何一家 APK、没上机、没有运行时读数。报告里每条结论都标了
  【码】（给了 `文件:行`）/【文】（只在 README·docs·issue 里看到）/【疑】（我没验或读数矛盾）三档，
  引用时按档分级。**2026-10-20 下午又补了第四档【史】**（引上游提交 sha，只 DSHA 与 woaiys3 两仓有）——
  新增与改口的五条集中在报告"第六·补"节。另有两处我明确说"没做"：woaiys3 那四档 overlay 补丁集（103 / 12 / 17 / 18 个文件）**没做逐档集合比对**（四档是否一致我不知道），
  三家 issue 区**只读了标题级别**。
- **我下的是 `main` 分支源码，不是 release 里的 APK**：DSHA 的 rootfs 只在 APK 里、git 里没有，
  那 273 MiB 的实际内容我无法核对（只核对到"代码确实从 APK asset 解 rootfs"这个动作）。
  Soodok 的 `0.2.1-rc.2` 是 README 宣称，包里没找到钉这个版本号的单点常量。
- **盘上多约 100 MB 只读参照件**：`reference/gh-3p/`（三家解包）+ `downloads/gh3/`（tarball 与 API 原文 约 52 MB）。
  两份都 .gitignore 掉了（`downloads/` 本来就在忽略里，这轮加了 `reference/gh-3p/` 一行），
  **留在盘上的理由是报告里每条 `文件:行` 都指向它们**，删了下次要重下。要清就两个目录一起删，报告仍然自洽
  （校验和与 sha 在 `downloads/gh3.sha256`，随时能重建）。
  → 这轮之后**又多约 40 MB**：那两个快照仓库各自的 `.git`（DSHA 32 M / woaiys3 7.4 M，14.13）。
    数量级仍是"参照件"，不入库，删法不变。
- **上游历史与标签到本地这件事：先失败后成了，成的是另一条路**（他点名的"克隆到本地"这下整句都成立）。
  第一次按"深度"切（`tools/clone-upstream.sh`：浅克隆 → 逐段 `--deepen`），跑 4 分钟判死：
  浅克隆那一包**必须装下当前整棵树**，而 DSHA 光三个 asset 就 20.4 MB 不可压缩字节
  （`adb-wheels.tar.gz` 9,951,074 + `glibc-python.tar.gz` 6,565,414 + `pnpm-runtime.bin` 3,837,861），
  按实测 19~28 KB/s 折 13~18 分钟一趟，镜像**每 4~6 分钟必掐** ⇒ 基本不可能落地；改成按"对象类型"切
  （`tools/fetch-history.sh`：`--filter=blob:none --no-checkout`）之后 **9 秒 / 27 秒各成一仓**。
  读数（`downloads/fetch-history.log`）：DSHA 627 条提交 / 28 标签 / 1.6 M，woaiys3 298 条 / 28 标签 / 481 K，
  两份 HEAD 逐字等于快照出处提交里记的上游 sha。
  **代价说清**：历史里**没有文件内容（blob）**，`git log` 与 `git log --name-status` 全通，
  `git show` 的正文要按需经镜像拉（单文件几 KB，慢但能等）；工作区一律读同目录那两份 `*-main` 快照，
  内容已按 tarball sha256 对上，不缺东西。深度那份脚本留着当"连历史 blob 也要"的退路。
