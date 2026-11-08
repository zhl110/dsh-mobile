package com.zhl.dsh;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.accessibilityservice.GestureDescription;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Point;
import android.graphics.BlurMaskFilter;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Shader;
import android.hardware.display.DisplayManager;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import android.util.DisplayMetrics;
import android.view.Display;
import android.view.Gravity;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/**
 * 壳 0.18：控件树读取 + 操作 + 操控提示 + 提速 + 交还用户（handoff/open）。
 *
 * 形状参照 DSH Go 的 TreeCapture/ScreenFormat/Actuator/EventClock/PhoneBridge（调研件在
 * downloads/dsh-go-*，AGPL，只借形状不抄代码）：读当前屏幕的无障碍控件树压成带编号文本；
 * 经 abstract unix socket 递给本机引擎；引擎经 MCP 桥调本服务做点击/输入/滚动/按键。
 * chroot 与宿主共用网络命名空间（scripts/dsh-chroot.sh 不 unshare net），abstract socket
 * 按 netns 归属 ⇒ chroot 里的 Node 用 net.connect('\0dsh-mobile-tree') 直达，不需要 TCP。
 *
 * 协议（一行 JSON 请求 → 一行 JSON 响应 + "\n"；兼容裸 ping/screen 文本）：
 *   {"cmd":"ping"}                 → {"ok":true,"result":"pong"}
 *   {"cmd":"screen"}               → {"ok":true,"screen":"<编号控件树>"}
 *   {"cmd":"tap","id":N,"long":b}  → 三段式点击 + 等稳 + 新屏幕
 *   {"cmd":"tap_xy","x":X,"y":Y}   → 坐标手势 + 等稳 + 新屏幕
 *   {"cmd":"type","id":N,"text":S} → 聚焦 + 设文字（密码框拒绝）+ 回读 + 新屏幕
 *   {"cmd":"scroll","id":N?,"direction":"up|down|left|right"} → 控件动作或滑动 + 新屏幕
 *   {"cmd":"key","key":"back|home|recents|notifications"}    → 全局键 + 新屏幕
 * 动作成功 → {"ok":true,"result":"…","screen":"<新树>"}；失败 → {"ok":false,"error":"…"}。
 * 编号只在最近一次 screen 里有效；屏幕一变就要重读。
 *
 * 只认本 App uid 或 root（uid 0）的连接：我们的引擎在真 chroot 里以 root 跑，root 必须放行
 * （p90 首验 EPIPE 就是被这条挡的）。真正的闸是用户亲手开无障碍开关；关掉开关即停一切操作。
 * 密码框内容一律不渲染、不代填。按铁律 19：直跑、不弹窗，不做确认 UI。
 */
public class TreeService extends AccessibilityService {

    /** abstract 命名空间里的固定名字；Node 侧写 '\0dsh-mobile-tree'。保住它，开关不用重开。 */
    public static final String SOCKET_NAME = "dsh-mobile-tree";
    private static final String INJECT_NAME = "dsh-inject";
    private static final int MAX_NODES = 2000;
    private static final int MAX_DEPTH = 80;
    private static final int MAX_LINES = 300;
    private static final int LABEL_CHARS = 60;
    // EventClock（提速版）：窗口切换最快回（150ms），内容变化静默 200ms 回，一直没事件 900ms 回，硬封顶 2s。
    private static final long SETTLE_WINDOW_MS = 150;
    private static final long SETTLE_QUIET_MS = 200;
    private static final long SETTLE_FIRST_MS = 900;
    private static final long SETTLE_MAX_MS = 2000;
    private static final long BADGE_HOLD_MS = 8000; // "AI 正在操控"提示：最后一次动作后留这么久
    private static final long HANDOFF_HOLD_MS = 60000; // 交还用户时，提示条留久一点

    private LocalServerSocket server;
    private LocalServerSocket injServer;
    private volatile boolean running;
    private HandlerThread gestureThread;
    private Handler gestureHandler;

    // 事件时钟：onAccessibilityEvent 累加，settle() 据此判稳。
    private volatile long eventCount = 0;
    private volatile long lastEventAt = 0;
    private volatile long windowStateCount = 0; // 窗口切换计数（settle 的最快一档靠它）
    private volatile String lastTargetPkg = null; // 最近一次操作的非本 App 前台包（handoff 用来说"刚才在操作谁"）

    /** 最近一次 screen 的编号 → 控件。屏幕一变（再读 screen）就重建。 */
    private static final class Item {
        final int id;
        final AccessibilityNodeInfo node;
        final boolean password;
        Item(int id, AccessibilityNodeInfo node, boolean password) {
            this.id = id; this.node = node; this.password = password;
        }
    }
    private final ArrayList<Item> cache = new ArrayList<>();

    // "AI 正在操控你的手机" 悬浮提示：TYPE_ACCESSIBILITY_OVERLAY 不需要悬浮窗权限，点不着、也抢不走焦点。
    private final Handler ui = new Handler(Looper.getMainLooper());
    private WindowManager wm;
    private View badge;
    private final Runnable hideBadge = new Runnable() { @Override public void run() { hideBadgeNow(); } };

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        AccessibilityServiceInfo info = getServiceInfo();
        if (info != null) {
            info.flags |= AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
            setServiceInfo(info);
        }
        gestureThread = new HandlerThread("dsh-gesture");
        gestureThread.start();
        gestureHandler = new Handler(gestureThread.getLooper());
        running = true;
        Thread t = new Thread(new Runnable() {
            @Override public void run() { serve(); }
        }, "dsh-tree-server");
        t.setDaemon(true);
        t.start();
        Thread ti = new Thread(new Runnable() {
            @Override public void run() { serveInject(); }
        }, "dsh-inject-server");
        ti.setDaemon(true);
        ti.start();
    }

    /** uinput 守护（root）会连到这里；SELinux 只放行 root→app 的 connectto，所以方向是它来找我们。 */
    private void serveInject() {
        try {
            injServer = new LocalServerSocket(INJECT_NAME);
        } catch (Exception e) {
            return;
        }
        while (running) {
            LocalSocket c = null;
            try {
                c = injServer.accept();
                Uinput.attach(c);
                c = null;   // 连接交给 Uinput 管，别在 finally 里关掉
            } catch (Exception e) {
                // 继续等下一发
            } finally {
                if (c != null) try { c.close(); } catch (Exception ignored) {}
            }
        }
    }

    private void serve() {
        try {
            server = new LocalServerSocket(SOCKET_NAME);
        } catch (Exception e) {
            // 名字被占（上一发服务还没死干净）等：不崩，开关重开一次即可
            return;
        }
        while (running) {
            LocalSocket client = null;
            try {
                client = server.accept();
                int uid = client.getPeerCredentials().getUid();
                if (uid != android.os.Process.myUid() && uid != 0) {
                    client.close();
                    continue;
                }
                handle(client);
            } catch (Exception e) {
                // accept 失败/对端断开：继续下一发
            } finally {
                if (client != null) try { client.close(); } catch (Exception ignored) {}
            }
        }
    }

    private void handle(LocalSocket client) throws Exception {
        client.setSoTimeout(30_000);
        BufferedReader in = new BufferedReader(new InputStreamReader(client.getInputStream(), StandardCharsets.UTF_8));
        OutputStream out = client.getOutputStream();
        String line;
        while ((line = in.readLine()) != null) {
            line = line.trim();
            if (line.isEmpty()) continue;
            String resp;
            if ("ping".equals(line)) resp = "pong";
            else if ("screen".equals(line)) resp = screenText(false);
            else resp = dispatch(line);
            out.write((resp + "\n").getBytes(StandardCharsets.UTF_8));
            out.flush();
        }
    }

    private String dispatch(String line) {
        JSONObject req;
        try {
            req = new JSONObject(line);
        } catch (Exception e) {
            return err("请求不是合法 JSON");
        }
        String cmd = req.optString("cmd", "");
        try {
            switch (cmd) {
                case "ping":   return ok("pong", null);
                case "screen": return ok(null, screenText(req.optBoolean("detail", false)));
                case "tap":    showBadge(); return doTap(req);
                case "tap_xy": showBadge(); return doTapXy(req);
                case "type":   showBadge(); return doType(req);
                case "scroll": showBadge(); return doScroll(req);
                case "key":    showBadge(); return doKey(req);
                case "handoff": return doHandoff(req);
                case "open":    showBadge(); return doOpen(req);
                default:       return err("未知命令：" + cmd);
            }
        } catch (Exception e) {
            return err("执行出错：" + e.getMessage());
        }
    }

    private String ok(String result, String screen) {
        JSONObject o = new JSONObject();
        try {
            o.put("ok", true);
            if (result != null) o.put("result", result);
            if (screen != null) o.put("screen", screen);
        } catch (Exception ignored) {}
        return o.toString();
    }

    private String err(String msg) {
        JSONObject o = new JSONObject();
        try { o.put("ok", false); o.put("error", msg); } catch (Exception ignored) {}
        return o.toString();
    }

    // ---- 操作 ------------------------------------------------------------------------------------

    private Item find(int id) {
        for (Item it : cache) if (it.id == id) return it;
        return null;
    }

    private String doTap(JSONObject req) throws Exception {
        int id = req.getInt("id");
        boolean longPress = req.optBoolean("long", false);
        Item it = find(id);
        if (it == null) return err("编号 " + id + " 不在最近一次屏幕里（先读 screen）");
        AccessibilityNodeInfo n = it.node;
        if (!n.refresh()) return err("编号 " + id + " 的控件已失效（屏幕变了，重新读 screen）");
        Rect b = new Rect();
        n.getBoundsInScreen(b);
        String how = null;
        // 优先走 uinput（真实触摸设备）；守护不在才退回控件动作/无障碍手势
        if (!b.isEmpty() && uiTap(b.centerX(), b.centerY(),
                longPress ? ViewConfiguration.getLongPressTimeout() + 300 : -1))
            how = longPress ? "已长按（触摸）" : "已点击（触摸）";
        if (how == null) how = click(n, longPress);
        settle();
        return ok(how, screenText(false));
    }

    /** 三段式（DSH Go Actuator 同款）：本控件 ACTION_CLICK → ≤4 层可点父控件 → 坐标手势。 */
    private String click(AccessibilityNodeInfo n, boolean longPress) {
        Rect b = new Rect();
        n.getBoundsInScreen(b);
        if (!longPress) {
            if (n.isClickable() && n.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                return "已点击（控件动作）";
            AccessibilityNodeInfo p = n.getParent();
            for (int i = 0; i < 4 && p != null; i++) {
                if (p.isClickable()) {
                    Rect pb = new Rect();
                    p.getBoundsInScreen(pb);
                    if (pb.contains(b.centerX(), b.centerY())
                            && p.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                        return "已点击（可点击的父控件）";
                }
                p = p.getParent();
            }
        }
        boolean done = longPress ? longPress(b.centerX(), b.centerY()) : tap(b.centerX(), b.centerY());
        if (!done) throw new RuntimeException("点击失败：控件不可点且手势未派发");
        return longPress ? "已长按（坐标手势）" : "已点击（坐标手势）";
    }

    private String doTapXy(JSONObject req) throws Exception {
        int x = req.getInt("x");
        int y = req.getInt("y");
        boolean done = uiTap(x, y, -1) || tap(x, y);
        if (!done) return err("手势未派发");
        settle();
        return ok("已点击坐标 (" + x + "," + y + ")", screenText(false));
    }

    private String doType(JSONObject req) throws Exception {
        int id = req.getInt("id");
        String text = req.getString("text");
        Item it = find(id);
        if (it == null) return err("编号 " + id + " 不在最近一次屏幕里（先读 screen）");
        if (it.password) return err("密码框不代填（交给用户）");
        AccessibilityNodeInfo n = it.node;
        if (!n.refresh()) return err("编号 " + id + " 的控件已失效（重新读 screen）");
        // 先"点"进输入框：ACTION_CLICK（点不着就坐标手势）会给它真焦点、唤出你手机的原生输入法；
        // ACTION_FOCUS 常常只挪焦点不弹键盘（0.14 之前就是这么写的，用户反馈"用不了原生输入法"）。
        if (!n.isFocused()) {
            Rect b = new Rect();
            n.getBoundsInScreen(b);
            boolean tapped = !b.isEmpty() && uiTap(b.centerX(), b.centerY(), -1);
            if (!tapped) { try { click(n, false); } catch (Exception ignored) {} }
            n.refresh();
            if (!n.isFocused()) { n.performAction(AccessibilityNodeInfo.ACTION_FOCUS); n.refresh(); }
        }
        Bundle args = new Bundle();
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text);
        boolean set = n.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
        if (!set) {
            n.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
            n.refresh();
            set = n.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
        }
        n.refresh();
        CharSequence now = n.getText();
        String readback = now == null ? "" : now.toString();
        settle();
        return ok((set ? "已输入" : "输入动作未确认") + "，回读：" + quote(readback), screenText(false));
    }

    private String doScroll(JSONObject req) throws Exception {
        String dir = req.optString("direction", req.optString("dir", "down"));
        if (!dir.equals("up") && !dir.equals("down") && !dir.equals("left") && !dir.equals("right"))
            return err("方向只认 up / down / left / right");
        if (req.has("id")) {
            int id = req.getInt("id");
            Item it = find(id);
            if (it == null) return err("编号 " + id + " 不在最近一次屏幕里（先读 screen）");
            AccessibilityNodeInfo n = it.node;
            if (n.refresh()) {
                Rect b = new Rect();
                n.getBoundsInScreen(b);
                if (!b.isEmpty() && uiSwipeScroll(dir, b)) {
                    settle();
                    return ok("已滚动（滑动）", screenText(false));
                }
                // 节点只有 FORWARD/BACKWARD（纵向通用）；横向没有专用节点动作 ⇒ left/right 直接走滑动。
                int action = dir.equals("down") ? AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                        : dir.equals("up") ? AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
                        : 0;
                if (action != 0 && n.performAction(action)) {
                    settle();
                    return ok("已滚动（控件动作）", screenText(false));
                }
                if (swipeScroll(dir, b)) {
                    settle();
                    return ok("已滚动（区域内滑动）", screenText(false));
                }
            }
        }
        Rect area = contentArea();
        if (uiSwipeScroll(dir, area)) {
            settle();
            return ok("已滚动（主区滑动）", screenText(false));
        }
        if (!swipeScroll(dir, area)) return err("滑动手势未派发");
        settle();
        return ok("已滚动（主区滑动）", screenText(false));
    }

    /** 与 swipeScroll 同一套坐标，但走 uinput；守护不在回 false。 */
    private boolean uiSwipeScroll(String dir, Rect r) {
        int cx = r.centerX(), cy = r.centerY();
        int dx = r.width(), dy = r.height();
        int x1, y1, x2, y2;
        switch (dir) {
            case "up":    x1 = cx; y1 = r.top + dy / 4;    x2 = cx; y2 = r.bottom - dy / 4; break;
            case "down":  x1 = cx; y1 = r.bottom - dy / 4; x2 = cx; y2 = r.top + dy / 4;    break;
            case "left":  x1 = r.left + dx / 4; y1 = cy;   x2 = r.right - dx / 4; y2 = cy;  break;
            default:      x1 = r.right - dx / 4; y1 = cy;  x2 = r.left + dx / 4; y2 = cy;   break;
        }
        int ms = 260 + (int) (Math.random() * 120);
        return uiSwipe(x1, y1, x2, y2, ms);
    }

    /** 在给定矩形里按方向滑：down=手指向上（看下面），up=向下，left=向右，right=向左。 */
    private boolean swipeScroll(String dir, Rect r) {
        int cx = r.centerX(), cy = r.centerY();
        int dx = r.width(), dy = r.height();
        int x1, y1, x2, y2;
        switch (dir) {
            case "up":    x1 = cx; y1 = r.top + dy / 4;    x2 = cx; y2 = r.bottom - dy / 4; break;
            case "down":  x1 = cx; y1 = r.bottom - dy / 4; x2 = cx; y2 = r.top + dy / 4;    break;
            case "left":  x1 = r.left + dx / 4; y1 = cy;   x2 = r.right - dx / 4; y2 = cy;  break;
            default:      x1 = r.right - dx / 4; y1 = cy;  x2 = r.left + dx / 4; y2 = cy;   break;
        }
        return swipe(x1, y1, x2, y2, 350);
    }

    /** 主内容区：避开顶部状态栏与底部导航条。 */
    private Rect contentArea() {
        Rect r = new Rect();
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root != null) root.getBoundsInScreen(r);
        if (r.isEmpty()) {
            DisplayMetrics dm = getResources().getDisplayMetrics();
            r.set(0, 0, dm.widthPixels, dm.heightPixels);
        }
        int top = r.top + (int) (r.height() * 0.12);
        int bottom = r.bottom - (int) (r.height() * 0.10);
        int left = r.left + (int) (r.width() * 0.10);
        int right = r.right - (int) (r.width() * 0.10);
        return new Rect(left, top, right, bottom);
    }

    private String doKey(JSONObject req) throws Exception {
        String key = req.getString("key");
        // 系统级按键走无障碍 globalAction（它不产生 MotionEvent，没有 deviceId/flags 可看）；
        // uinput 的虚拟键盘在这台机上按 HOME 不生效（实测 probe 116），别硬换。
        int action;
        switch (key) {
            case "back":          action = GLOBAL_ACTION_BACK; break;
            case "home":          action = GLOBAL_ACTION_HOME; break;
            case "recents":       action = GLOBAL_ACTION_RECENTS; break;
            case "notifications": action = GLOBAL_ACTION_NOTIFICATIONS; break;
            default: return err("按键只认 back / home / recents / notifications");
        }
        boolean done = performGlobalAction(action);
        settle();
        return ok(done ? "已按 " + key : "按键动作未确认", screenText(false));
    }

    /** 当前前台应用的包名（优先 TYPE_APPLICATION 窗口，避开状态栏/系统 UI 覆盖层；拿不到回 null）。 */
    private String currentForegroundPkg() {
        try {
            List<AccessibilityWindowInfo> ws = getWindows();
            for (int i = ws.size() - 1; i >= 0; i--) {
                if (ws.get(i).getType() == AccessibilityWindowInfo.TYPE_APPLICATION) {
                    AccessibilityNodeInfo r = ws.get(i).getRoot();
                    if (r != null && r.getPackageName() != null) return r.getPackageName().toString();
                }
            }
        } catch (Exception ignored) {}
        try {
            AccessibilityNodeInfo r = getRootInActiveWindow();
            if (r != null && r.getPackageName() != null) return r.getPackageName().toString();
        } catch (Exception ignored) {}
        return null;
    }

    /** 遇到要用户决定的事：把 DSH 自己切到前台、把控制权交回聊天；记住刚才在操作的 App 供 open 回来。 */
    private String doHandoff(JSONObject req) {
        String reason = req.optString("reason", "").trim();
        String where = currentForegroundPkg();
        if (where != null && !where.equals(getPackageName()) && !where.equals("com.android.systemui")) lastTargetPkg = where;
        String target = lastTargetPkg == null ? "（未知）" : lastTargetPkg;
        try {
            Intent i = getPackageManager().getLaunchIntentForPackage(getPackageName());
            if (i != null) {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP);
                startActivity(i);
            }
        } catch (Exception ignored) {}
        showBadgeText(reason.isEmpty() ? "AI 需要你选择（已切回 DSH）" : "AI 需要你选择：回到 DSH", HANDOFF_HOLD_MS);
        return ok("已把 DSH 切到前台，等你回答。"
                + (reason.isEmpty() ? "" : "要用户决定的是：" + reason + "。")
                + "你刚才在操作 " + target + "。请在这里把问题和可选项告诉用户；用户回答后，用 open 工具重新打开 " + target + " 再继续。", null);
    }

    /** 打开一个 App（包名或名称，名称按启动器标签模糊匹配），返回打开后的新屏幕。用于用户答完后回到原 App。 */
    private String doOpen(JSONObject req) throws Exception {
        String app = req.optString("app", "").trim();
        if (app.isEmpty()) return err("open 需要 app（包名或应用名）");
        PackageManager pm = getPackageManager();
        Intent launch = null;
        String resolved = app;
        if (app.contains(".")) {
            launch = pm.getLaunchIntentForPackage(app);
            if (launch != null) resolved = app;
        }
        if (launch == null) {
            Intent main = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
            List<ResolveInfo> ris = pm.queryIntentActivities(main, 0);
            String q = app.toLowerCase();
            for (ResolveInfo ri : ris) {
                String lbl = String.valueOf(ri.loadLabel(pm)).toLowerCase();
                String pn = ri.activityInfo.packageName;
                if (lbl.equals(q) || lbl.contains(q) || pn.equalsIgnoreCase(app)) {
                    launch = pm.getLaunchIntentForPackage(pn);
                    resolved = pn;
                    if (launch != null) break;
                }
            }
        }
        if (launch == null) return err("找不到可启动的应用：" + app);
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
        startActivity(launch);
        // 等目标 App 真到前台，避开启动动画里的 systemui 过渡帧（否则会读回 systemui 那种假屏）。
        long end = SystemClock.uptimeMillis() + 3000;
        while (SystemClock.uptimeMillis() < end) {
            String cur = currentForegroundPkg();
            if (cur != null && !cur.equals("com.android.systemui") && !cur.equals(getPackageName())) break;
            try { Thread.sleep(80); } catch (InterruptedException e) { break; }
        }
        settle();
        return ok("已打开 " + resolved, screenText(false));
    }

    // ---- uinput 注入（守护在就走内核输入层；不在就 false ⇒ 退回下面的无障碍手势） ------------------

    private float _w() { return _px().x; }
    private float _h() { return _px().y; }

    /** 真实屏幕像素：服务进程的 DisplayMetrics 会跟着自己窗口的配置变（实测给的是 3168x1440），不能用。 */
    private Point _px() {
        Point p = new Point();
        try {
            DisplayManager dm = (DisplayManager) getSystemService(DISPLAY_SERVICE);
            Display d = dm.getDisplay(Display.DEFAULT_DISPLAY);
            d.getRealSize(p);
        } catch (Exception e) {
            DisplayMetrics m = getResources().getDisplayMetrics();
            p.set(m.widthPixels, m.heightPixels);
        }
        return p;
    }

    private boolean uiTap(int x, int y, int holdMs) {
        float[] n = _norm(x, y);
        return Uinput.tap(n[0], n[1], holdMs);
    }

    private boolean uiSwipe(int x1, int y1, int x2, int y2, int ms) {
        float[] a = _norm(x1, y1), b = _norm(x2, y2);
        return Uinput.swipe(a[0], a[1], b[0], b[1], ms);
    }

    /**
     * 当前屏幕坐标 → 注入器用的自然方向归一化坐标。
     * 实测：旋转 90° 时 InputReader 仍按自然方向(1440x3168)映射我们的 uinput 设备，
     * 所以先按 Display.getRotation() 转回自然方向再归一化，否则横屏下点会落错地方。
     */
    private float[] _norm(int x, int y) {
        Point p = new Point();
        int rot = 0;
        try {
            DisplayManager dm = (DisplayManager) getSystemService(DISPLAY_SERVICE);
            Display d = dm.getDisplay(Display.DEFAULT_DISPLAY);
            d.getRealSize(p);
            rot = d.getRotation();
        } catch (Exception e) {
            DisplayMetrics m = getResources().getDisplayMetrics();
            p.set(m.widthPixels, m.heightPixels);
        }
        int wc = p.x, hc = p.y, xn, yn, wn, hn;
        switch (rot) {
            case 1:  xn = hc - y; yn = x;      wn = hc; hn = wc; break;  // ROTATION_90
            case 3:  xn = y;      yn = wc - x; wn = hc; hn = wc; break;  // ROTATION_270
            case 2:  xn = wc - x; yn = hc - y; wn = wc; hn = hc; break;  // ROTATION_180
            default: xn = x;      yn = y;      wn = wc; hn = hc; break;
        }
        if (wn <= 0 || hn <= 0) return new float[]{ 0, 0 };
        return new float[]{ xn / (float) wn, yn / (float) hn };
    }

    // ---- 手势 ------------------------------------------------------------------------------------

    private boolean tap(int x, int y) {
        Path p = new Path();
        p.moveTo(x, y);
        p.lineTo(x, y);
        return gesture(p, 60);
    }

    private boolean longPress(int x, int y) {
        Path p = new Path();
        p.moveTo(x, y);
        p.lineTo(x, y);
        return gesture(p, ViewConfiguration.getLongPressTimeout() + 300);
    }

    private boolean swipe(int x1, int y1, int x2, int y2, long duration) {
        Path p = new Path();
        p.moveTo(x1, y1);
        p.lineTo(x2, y2);
        return gesture(p, duration);
    }

    private boolean gesture(Path path, long duration) {
        final CountDownLatch latch = new CountDownLatch(1);
        final boolean[] done = {false};
        GestureDescription g = new GestureDescription.Builder()
                .addStroke(new GestureDescription.StrokeDescription(path, 0, duration))
                .build();
        boolean dispatched = dispatchGesture(g, new GestureResultCallback() {
            @Override public void onCompleted(GestureDescription d) { done[0] = true; latch.countDown(); }
            @Override public void onCancelled(GestureDescription d) { latch.countDown(); }
        }, gestureHandler);
        if (!dispatched) return false;
        try {
            latch.await(duration + 2000, TimeUnit.MILLISECONDS);
        } catch (InterruptedException e) {
            return false;
        }
        return done[0];
    }

    /** 等界面稳（提速版）：窗口切换 150ms 回，内容变化静默 200ms 回，一直没事件 900ms 回，封顶 2s。 */
    private void settle() {
        long start = SystemClock.uptimeMillis();
        long startCount = eventCount;
        long startWin = windowStateCount;
        while (true) {
            try { Thread.sleep(25); } catch (InterruptedException e) { return; }
            long now = SystemClock.uptimeMillis();
            if (windowStateCount != startWin) {
                if (now - lastEventAt >= SETTLE_WINDOW_MS) return;
            } else if (eventCount != startCount) {
                if (now - lastEventAt >= SETTLE_QUIET_MS) return;
            } else {
                if (now - start >= SETTLE_FIRST_MS) return;
            }
            if (now - start >= SETTLE_MAX_MS) return;
        }
    }

    // ---- 悬浮提示（"AI 正在操控你的手机"） ----------------------------------------------------------

    /** 有动作时在屏幕顶部叠一条提示；最后一次动作后自动收。 */
    private void showBadge() { showBadgeText("AI 正在操控你的手机", BADGE_HOLD_MS); }

    private void showBadgeText(final String text, final long hold) {
        ui.post(new Runnable() { @Override public void run() {
            ui.removeCallbacks(hideBadge);
            if (badge == null) {
                try {
                    float d = getResources().getDisplayMetrics().density;
                    BadgeView bv = new BadgeView(TreeService.this);
                    bv.setText(text);
                    WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
                            WindowManager.LayoutParams.WRAP_CONTENT,
                            WindowManager.LayoutParams.WRAP_CONTENT,
                            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                                    | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                                    | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                            PixelFormat.TRANSLUCENT);
                    lp.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
                    lp.y = (int) (40 * d);
                    if (wm == null) wm = (WindowManager) getSystemService(WINDOW_SERVICE);
                    wm.addView(bv, lp);
                    badge = bv;
                } catch (Exception e) {
                    badge = null;
                }
            } else if (badge instanceof BadgeView) {
                ((BadgeView) badge).setText(text);
            }
            ui.postDelayed(hideBadge, hold);
        }});
    }

    private void hideBadgeNow() {
        if (badge != null) {
            try { if (wm != null) wm.removeView(badge); } catch (Exception ignored) {}
            badge = null;
        }
    }

    /** 渐变 + 边缘虚化的淡蓝提示条：不要纯色实心块，要一层光晕包着一层淡蓝。 */
    private static final class BadgeView extends View {
        private String text = "";
        private final float blur;
        private final float padH;
        private final float padV;
        private final Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint textHalo = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint pillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint glowPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF box = new RectF();

        BadgeView(Context c) {
            super(c);
            float d = c.getResources().getDisplayMetrics().density;
            blur = 10f * d;
            padH = 20f * d;
            padV = 10f * d;
            textPaint.setTextSize(13f * d);
            textPaint.setColor(0xE60E2A52);
            // 文字底下一层白色柔光：半透明底在深色页面上也能读清
            textHalo.setTextSize(13f * d);
            textHalo.setColor(0x99FFFFFF);
            textHalo.setMaskFilter(new BlurMaskFilter(2.5f * d, BlurMaskFilter.Blur.NORMAL));
            pillPaint.setStyle(Paint.Style.FILL);
            pillPaint.setMaskFilter(new BlurMaskFilter(blur * 0.8f, BlurMaskFilter.Blur.NORMAL));
            glowPaint.setStyle(Paint.Style.FILL);
            glowPaint.setMaskFilter(new BlurMaskFilter(blur * 1.5f, BlurMaskFilter.Blur.NORMAL));
            setLayerType(View.LAYER_TYPE_SOFTWARE, null);
        }

        void setText(String t) {
            text = t == null ? "" : t;
            requestLayout();
            invalidate();
        }

        @Override protected void onMeasure(int wSpec, int hSpec) {
            Paint.FontMetrics fm = textPaint.getFontMetrics();
            int w = (int) Math.ceil(textPaint.measureText(text) + (padH + blur) * 2);
            int h = (int) Math.ceil((fm.descent - fm.ascent) + (padV + blur) * 2);
            setMeasuredDimension(w, h);
        }

        @Override protected void onDraw(Canvas canvas) {
            float inset = blur;
            box.set(inset, inset, getWidth() - inset, getHeight() - inset);
            if (box.height() <= 0 || box.width() <= 0) return;
            float r = box.height() / 2f;
            // 外层淡蓝光晕（模糊半径大 ⇒ 边缘散开；低 alpha ⇒ 只是"有光"，不遮背景）
            glowPaint.setShader(new LinearGradient(box.left, box.top, box.right, box.bottom,
                    0x388FC6FF, 0x14D9ECFF, Shader.TileMode.CLAMP));
            canvas.drawRoundRect(box, r, r, glowPaint);
            // 主层：半透明淡蓝渐变 + 轻度模糊 ⇒ 透过它能看到底下的东西
            pillPaint.setShader(new LinearGradient(box.left, box.top, box.right, box.bottom,
                    0x7A8FC6FF, 0x82E2F1FF, Shader.TileMode.CLAMP));
            canvas.drawRoundRect(box, r, r, pillPaint);
            // 文字不模糊
            Paint.FontMetrics fm = textPaint.getFontMetrics();
            float tw = textPaint.measureText(text);
            float ty = box.centerY() - (fm.ascent + fm.descent) / 2f;
            canvas.drawText(text, box.centerX() - tw / 2f, ty, textHalo);
            canvas.drawText(text, box.centerX() - tw / 2f, ty, textPaint);
        }
    }

    // ---- 读树 ------------------------------------------------------------------------------------

    private final StringBuilder sb = new StringBuilder();
    private int nodes;
    private int lines;
    private int nextId;
    private boolean truncated;

    private String screenText(boolean detail) {
        if (Build.VERSION.SDK_INT < 21) return "ERR 需要 Android 5+";
        List<AccessibilityWindowInfo> windows = getWindows();
        AccessibilityNodeInfo root = null;
        String pkg = "?";
        for (int i = windows.size() - 1; i >= 0; i--) {
            AccessibilityWindowInfo w = windows.get(i);
            if (w.getType() == AccessibilityWindowInfo.TYPE_APPLICATION) {
                AccessibilityNodeInfo r = w.getRoot();
                if (r != null) {
                    root = r;
                    CharSequence p = r.getPackageName();
                    if (p != null) pkg = p.toString();
                    break;
                }
            }
        }
        if (root == null) {
            root = getRootInActiveWindow();
            if (root != null && root.getPackageName() != null) pkg = root.getPackageName().toString();
        }
        if (root == null) return "ERR 当前没有可读的窗口（锁屏/受保护页面，或无障碍刚开还没拿到树）";
        if (pkg != null && pkg.length() > 0 && !"?".equals(pkg) && !pkg.equals(getPackageName())
                && !"com.android.systemui".equals(pkg)) lastTargetPkg = pkg;
        sb.setLength(0);
        nodes = 0; lines = 0; nextId = 1; truncated = false;
        cache.clear();
        walk(root, 0, detail);
        StringBuilder head = new StringBuilder();
        head.append("屏幕 · ").append(pkg).append(" · 共 ").append(nextId - 1).append(" 项");
        if (truncated) head.append("（树被截断：节点/行数到上限）");
        head.append('\n');
        return head.append(sb).toString();
    }

    /** 只收「可交互或有文字」的节点；布局壳折叠掉（DSH Go ScreenFormat 的同款口径，简化版）。 */
    private void walk(AccessibilityNodeInfo n, int depth, boolean detail) {
        if (n == null || depth > MAX_DEPTH || nodes >= MAX_NODES || lines >= MAX_LINES) {
            if (nodes >= MAX_NODES || lines >= MAX_LINES) truncated = true;
            return;
        }
        nodes++;
        String label = labelOf(n);
        boolean interactive = n.isClickable() || n.isLongClickable() || n.isFocusable()
                || n.isScrollable() || n.isEditable() || n.isCheckable();
        if (depth > 0 && (interactive || !label.isEmpty())) {
            int id = nextId++;
            cache.add(new Item(id, n, n.isPassword()));
            sb.append("  [").append(id).append("] ").append(roleOf(n));
            if (!label.isEmpty()) sb.append(' ').append(quote(label));
            if (n.isPassword()) sb.append(" · 密码框");
            else if (n.isEditable()) sb.append(" · 可输入");
            if (n.isFocused()) sb.append(" · 已聚焦");
            if (n.isScrollable()) sb.append(" · 可滚动");
            if (n.isCheckable()) sb.append(n.isChecked() ? " · 已选中" : " · 未选中");
            if (detail) {
                Rect b = new Rect();
                n.getBoundsInScreen(b);
                sb.append(" @(").append(b.left).append(',').append(b.top)
                  .append('-').append(b.right).append(',').append(b.bottom).append(')');
            }
            sb.append('\n');
            lines++;
        }
        for (int i = 0; i < n.getChildCount(); i++) walk(n.getChild(i), depth + 1, detail);
    }

    /** text → contentDescription → hint；密码框内容一律不渲染；每标签 60 字符封顶。 */
    private String labelOf(AccessibilityNodeInfo n) {
        if (n.isPassword()) return "";
        CharSequence c = n.getText();
        if (c == null || c.length() == 0) c = n.getContentDescription();
        if ((c == null || c.length() == 0) && Build.VERSION.SDK_INT >= 26) c = n.getHintText();
        if (c == null) return "";
        String s = c.toString().replace('\n', ' ').trim();
        return s.length() > LABEL_CHARS ? s.substring(0, LABEL_CHARS) + "…" : s;
    }

    private String quote(String s) {
        return '"' + s.replace("\"", "'") + '"';
    }

    private String roleOf(AccessibilityNodeInfo n) {
        CharSequence cn = n.getClassName();
        String c = cn == null ? "" : cn.toString();
        if (c.endsWith("Button") || c.endsWith("ImageButton")) return "按钮";
        if (c.endsWith("EditText")) return "输入框";
        if (c.endsWith("CheckBox")) return "勾选框";
        if (c.endsWith("Switch") || c.endsWith("ToggleButton")) return "开关";
        if (c.endsWith("RadioButton")) return "单选";
        if (c.endsWith("ImageView")) return "图片";
        if (c.endsWith("RecyclerView") || c.endsWith("ListView") || c.endsWith("ScrollView")
                || c.endsWith("HorizontalScrollView")) return "列表";
        if (c.endsWith("TextView")) return "文本";
        if (c.endsWith("SeekBar")) return "滑杆";
        if (c.endsWith("Spinner")) return "下拉";
        return "控件";
    }

    // ---- 生命周期 --------------------------------------------------------------------------------

    @Override public void onAccessibilityEvent(AccessibilityEvent event) {
        eventCount++;
        lastEventAt = SystemClock.uptimeMillis();
        if (event.getEventType() == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) windowStateCount++;
    }
    @Override public void onInterrupt() { }

    @Override
    public void onDestroy() {
        running = false;
        hideBadgeNow();
        if (server != null) try { server.close(); } catch (Exception ignored) {}
        if (injServer != null) try { injServer.close(); } catch (Exception ignored) {}
        Uinput.close();
        if (gestureThread != null) try { gestureThread.quit(); } catch (Exception ignored) {}
        super.onDestroy();
    }
}