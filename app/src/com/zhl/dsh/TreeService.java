package com.zhl.dsh;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.accessibilityservice.GestureDescription;
import android.graphics.Path;
import android.graphics.Rect;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.util.DisplayMetrics;
import android.view.ViewConfiguration;
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
 * 壳 0.12：控件树读取 + 操作（第二里程碑，完整控制环）。
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
    private static final int MAX_NODES = 2000;
    private static final int MAX_DEPTH = 80;
    private static final int MAX_LINES = 300;
    private static final int LABEL_CHARS = 60;
    // EventClock（DSH Go 同款口径）：首个事件 ≤1.5s，之后静默 300ms 算稳，硬封顶 3s。
    private static final long SETTLE_FIRST_MS = 1500;
    private static final long SETTLE_QUIET_MS = 300;
    private static final long SETTLE_MAX_MS = 3000;

    private LocalServerSocket server;
    private volatile boolean running;
    private HandlerThread gestureThread;
    private Handler gestureHandler;

    // 事件时钟：onAccessibilityEvent 累加，settle() 据此判稳。
    private volatile long eventCount = 0;
    private volatile long lastEventAt = 0;

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
            else if ("screen".equals(line)) resp = screenText();
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
                case "screen": return ok(null, screenText());
                case "tap":    return doTap(req);
                case "tap_xy": return doTapXy(req);
                case "type":   return doType(req);
                case "scroll": return doScroll(req);
                case "key":    return doKey(req);
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
        String how = click(n, longPress);
        settle();
        return ok(how, screenText());
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
        if (!tap(x, y)) return err("坐标手势未派发");
        settle();
        return ok("已点击坐标 (" + x + "," + y + ")", screenText());
    }

    private String doType(JSONObject req) throws Exception {
        int id = req.getInt("id");
        String text = req.getString("text");
        Item it = find(id);
        if (it == null) return err("编号 " + id + " 不在最近一次屏幕里（先读 screen）");
        if (it.password) return err("密码框不代填（交给用户）");
        AccessibilityNodeInfo n = it.node;
        if (!n.refresh()) return err("编号 " + id + " 的控件已失效（重新读 screen）");
        if (!n.isFocused()) {
            n.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
            if (!n.isFocused()) {
                click(n, false);
                n.refresh();
            }
        }
        Bundle args = new Bundle();
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text);
        boolean set = n.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
        if (!set) {
            click(n, false);
            n.refresh();
            set = n.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
        }
        n.refresh();
        CharSequence now = n.getText();
        String readback = now == null ? "" : now.toString();
        settle();
        return ok((set ? "已输入" : "输入动作未确认") + "，回读：" + quote(readback), screenText());
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
                // 节点只有 FORWARD/BACKWARD（纵向通用）；横向没有专用节点动作 ⇒ left/right 直接走滑动。
                int action = dir.equals("down") ? AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                        : dir.equals("up") ? AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
                        : 0;
                if (action != 0 && n.performAction(action)) {
                    settle();
                    return ok("已滚动（控件动作）", screenText());
                }
                Rect b = new Rect();
                n.getBoundsInScreen(b);
                if (swipeScroll(dir, b)) {
                    settle();
                    return ok("已滚动（区域内滑动）", screenText());
                }
            }
        }
        Rect area = contentArea();
        if (!swipeScroll(dir, area)) return err("滑动手势未派发");
        settle();
        return ok("已滚动（主区滑动）", screenText());
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
        return ok(done ? "已按 " + key : "按键动作未确认", screenText());
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

    /** 等界面稳：见过事件且静默 300ms，或一直没事件熬过 1.5s，或硬封顶 3s。 */
    private void settle() {
        long start = SystemClock.uptimeMillis();
        long startCount = eventCount;
        while (true) {
            try { Thread.sleep(40); } catch (InterruptedException e) { return; }
            long now = SystemClock.uptimeMillis();
            boolean changed = eventCount != startCount;
            if (changed && now - lastEventAt >= SETTLE_QUIET_MS) return;
            if (!changed && now - start >= SETTLE_FIRST_MS) return;
            if (now - start >= SETTLE_MAX_MS) return;
        }
    }

    // ---- 读树 ------------------------------------------------------------------------------------

    private final StringBuilder sb = new StringBuilder();
    private int nodes;
    private int lines;
    private int nextId;
    private boolean truncated;

    private String screenText() {
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
        sb.setLength(0);
        nodes = 0; lines = 0; nextId = 1; truncated = false;
        cache.clear();
        walk(root, 0);
        StringBuilder head = new StringBuilder();
        head.append("屏幕 · ").append(pkg).append(" · 共 ").append(nextId - 1).append(" 项");
        if (truncated) head.append("（树被截断：节点/行数到上限）");
        head.append('\n');
        return head.append(sb).toString();
    }

    /** 只收「可交互或有文字」的节点；布局壳折叠掉（DSH Go ScreenFormat 的同款口径，简化版）。 */
    private void walk(AccessibilityNodeInfo n, int depth) {
        if (n == null || depth > MAX_DEPTH || nodes >= MAX_NODES || lines >= MAX_LINES) {
            if (nodes >= MAX_NODES || lines >= MAX_LINES) truncated = true;
            return;
        }
        nodes++;
        String label = labelOf(n);
        boolean interactive = n.isClickable() || n.isLongClickable() || n.isFocusable()
                || n.isScrollable() || n.isEditable() || n.isCheckable();
        if (depth > 0 && (interactive || !label.isEmpty())) {
            Rect b = new Rect();
            n.getBoundsInScreen(b);
            int id = nextId++;
            cache.add(new Item(id, n, n.isPassword()));
            sb.append("  [").append(id).append("] ").append(roleOf(n));
            if (!label.isEmpty()) sb.append(' ').append(quote(label));
            if (n.isPassword()) sb.append(" · 密码框");
            else if (n.isEditable()) sb.append(" · 可输入");
            if (n.isFocused()) sb.append(" · 已聚焦");
            if (n.isScrollable()) sb.append(" · 可滚动");
            if (n.isCheckable()) sb.append(n.isChecked() ? " · 已选中" : " · 未选中");
            sb.append(" @(").append(b.left).append(',').append(b.top)
              .append('-').append(b.right).append(',').append(b.bottom).append(")\n");
            lines++;
        }
        for (int i = 0; i < n.getChildCount(); i++) walk(n.getChild(i), depth + 1);
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
    }
    @Override public void onInterrupt() { }

    @Override
    public void onDestroy() {
        running = false;
        if (server != null) try { server.close(); } catch (Exception ignored) {}
        if (gestureThread != null) try { gestureThread.quit(); } catch (Exception ignored) {}
        super.onDestroy();
    }
}