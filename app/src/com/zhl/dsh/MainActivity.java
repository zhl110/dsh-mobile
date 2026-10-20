package com.zhl.dsh;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.webkit.CookieManager;
import android.webkit.JsPromptResult;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * dsh 的手机本机壳 —— 「点开就能用」那一档。
 *
 * 地址是**写死的**：http://127.0.0.1:3081/，不带 token。入场券由 chroot 里的
 * scripts/dsh-entry.js 负责：它从引擎 stdout 认那条官方启动行（判据照 DSHA 的
 * DshAuthUrl.java:25-26），拿一次性 token 换到 30 天的 dsh-auth-* cookie 攥在自己内存里，
 * App 只带一个固定的入口口令（cookie: dsh-entry=&lt;key&gt;）就能进那套全集 Web UI。
 *
 * 为什么要多这一层：token 每代只有一条、只打印在 root 的 chroot 的 stdout 里、用过即废，
 * 且实测没有任何配置/环境变量/参数能把它钉住或绕过（RUNBOOK 14.11 与 14.13 的读数：
 * webserver 那组字段就到 host/port/tls 为止，printUrl 是硬编码 true，requiredStartupEntryIds
 * 不许关 webserver）。三家社区方案能做到"点开就能用"走的是同一条路 —— App 自己起引擎、
 * 自己在内存里换 cookie，再把裸地址塞给 WebView（DSHA DshAuthUrl.java +
 * WebPreviewActivity.java:692-706、Soodok dsh-lan-proxy.js:60-78、woaiys3 MainActivity.java:4139）。
 * 我们的引擎在 root 的 chroot 里，非特权 App 既起不动它也读不到它的 stdout，所以
 * "起引擎 + 换 cookie"这半截只能交给那个本机守护进程。
 *
 * 从 DSHA 抄两处细节：setCookie 之后**在回调里**才 loadUrl（WebPreviewActivity.java:692-706，
 * 治首屏 401 竞态），以及把 WebView 的 provider 包名与版本写进报错页（:665-670）。
 * 明确不抄：它那份绑 0.0.0.0 的 LAN 代理（LanProxyService.java:308）—— 我们只碰 127.0.0.1。
 *
 * 口令怎么进 App：build.sh 从 app/local/entry.key 烤进包里（BAKED_KEY）。这条**只是抬高门槛，
 * 不是密不透风**：APK 能被解开。真机上其它 App 解不开的是那份 dsh-auth cookie。
 * 换口令：chroot 里改 /root/.dsh/entry.key 后重启入口，再在本页「填地址与口令」里填一次。
 */
public class MainActivity extends Activity {

    private static final String PREFS = "dsh";
    private static final String KEY_URL = "start_url";        // 入口地址（可改，留空用默认）
    private static final String KEY_SECRET = "entry_key";     // 入口口令（覆盖 BAKED_KEY）
    private static final String DEFAULT_URL = "http://127.0.0.1:3081/";
    private static final String COOKIE = "dsh-entry";
    private static final String PANEL_BASE = "dsh-app://panel";

    private static final String BAKED_URL = "__DSH_ENTRY_URL__";   // build.sh 烤；没烤就退回 DEFAULT_URL
    private static final String BAKED_KEY = "__DSH_ENTRY_KEY__";   // build.sh 从 local/entry.key 烤

    private WebView web;
    private SharedPreferences prefs;
    private volatile boolean panel = false;      // 当前这一屏是不是我们自己画的
    private volatile String panelKind = "";
    private volatile String panelDetail = "";
    private volatile String statusText = "";
    // 0.4 为"重进之后黑屏十几秒"那条读数加的三个字段：这一发导航到底开始了没有、什么时候按下去的、还允许自己重试几次。
    private volatile boolean navStarted = true;
    private long loadAt = 0;
    private int retryLeft = 2;
    // 0.5 换掉 0.4 那张 AlertDialog：退出的意思改用一枚自己会消散的浮层表达（见 showExitHint）。
    private FrameLayout root = null;             // WebView 外面那一层，只为给浮层一个落点
    private TextView hint = null;                // 那枚"再按一次返回"的浮层，null = 从没建过
    private long hintUntil = 0;                  // 过了这个时刻，下一次返回就不再算"第二下"
    private final Handler ui = new Handler(Looper.getMainLooper());
    // 0.6 为语音输入加的四个字段。形状照 DSHA 的 WebViewMicrophone.java:10-24 抄：
    // 一次只攥着一个待决的媒体请求（micPending），页面一换就把它作废（micRev 见 onPageStarted），
    // micAnswered 是"这一发的系统弹窗已经有结果了"的闩，防止 grant 被调用两次。
    private PermissionRequest micPending = null;
    private long micRev = 0;
    private boolean micAnswered = false;
    private static final int REQ_MIC = 0x6d69;   // 'mi'

    /**
     * 壳自己的一条日志通道：adb logcat -s dsh-app:V 就能看见"点了图标之后到底走到哪一步"。
     * 为什么要它：手机锁着屏（他的 PIN 我们不动）或者屏幕黑着的时候，screencap 只能拿到全黑，
     * 那时唯一能区分「App 没起来 / 起来了但 cookie 没种上 / cookie 种了但入口 404 / 页面在加载但 JS 报错」
     * 的就是这几行。口令与 token 一律只报长度，值不进日志。
     */
    private static final String TAG = "dsh-app";
    private static final String LTAG = "dsh-app";
    private static void L(String step, String detail) {
        String line = step + " :: " + detail;
        Log.i(TAG, line);
        writeLog(line);
    }

    /**
     * 同一批事件再落一份文件：/sdcard/Android/data/com.zhl.dsh/files/shell.log。
     * 为什么 logcat 不够 —— 这台机实测（2026-10-20）：logcat 主缓冲区 1 分钟就被 OEM 自己的
     * 噪音冲掉（一次 dump 出 13,927 行，其中 dsh-app 0 行），他手机上"刚才那一下点了没反应"
     * 过两分钟再去 logcat 查，什么都查不到。文件这份不受缓冲区影响，adb pull 就能拿。
     * 只写步骤名与细节，口令/token 的值本来就不进 detail（调用处一律只报长度）。
     * 写失败不能把壳带倒：整段吞异常。
     */
    private static File logFile;
    private static void writeLog(String line) {
        try {
            if (logFile == null) return;                 // onCreate 之前的事件只进 logcat
            synchronized (LTAG) {
                FileOutputStream fos = new FileOutputStream(logFile, true);
                OutputStreamWriter w = new OutputStreamWriter(fos, "UTF-8");
                w.write(new java.text.SimpleDateFormat("MM-dd HH:mm:ss.SSS")
                        .format(new java.util.Date()) + " " + line + "\n");
                w.close();
            }
            // 别让它长没边：超过 400 KB 就把前半截丢掉（留最近的那些，排查用的就是最近）
            if (logFile.length() > 400 * 1024) {
                byte[] all = readAll(logFile);
                int half = all.length / 2;
                FileOutputStream cut = new FileOutputStream(logFile, false);
                cut.write(all, half, all.length - half);
                cut.close();
            }
        } catch (Exception ignored) { }
    }

    private static byte[] readAll(File f) throws Exception {
        java.io.FileInputStream in = new java.io.FileInputStream(f);
        try {
            java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[8192]; int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
            return bo.toByteArray();
        } finally { in.close(); }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        try {
            File dir = getExternalFilesDir(null);
            if (dir != null) { if (!dir.exists()) dir.mkdirs(); logFile = new File(dir, "shell.log"); }
        } catch (Exception ignored) { }

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(false);                       // 以下四项照 DSHA WebPreviewActivity.java:671-680
        s.setAllowContentAccess(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        s.setTextZoom(100);
        // 页面里 target=_blank / window.open 的去处：默认 setSupportMultipleWindows(false)，
        // 这时候 Chromium 直接**把这一发丢掉**——不报错、不发请求、界面不动。他 2026-10-20 报的
        // "点了插件之后没反应，要我返回来才可以"就是这个形状（点下去什么也没发生，只能自己退回去）。
        // 开了之后由下面的 onCreateWindow 接管：同一个入口的落到本 WebView 里（像点了个链接），
        // 外站的交系统浏览器（照 DSHA :841-866 那条判断）。
        s.setSupportMultipleWindows(true);
        web.setBackgroundColor(Color.parseColor("#0b0d12"));
        // 关掉 Android 12+ 那套"拉到边界整页弹一下"的橡皮筋：这是手机网页的手感，不是桌面软件的手感，
        // 他要的是"像真正的桌面端"。滚动本身不受影响，只是到边不再弹。
        web.setOverScrollMode(View.OVER_SCROLL_NEVER);
        CookieManager.getInstance().setAcceptCookie(true);
        // 电脑上 chrome://inspect 能直接挂进这个 WebView 看 DOM/控制台/网络 —— 这就是他要的"1+1>2"：
        // 手机上那套 dsh 的自述页 + 壳的 logcat + 桌面 DevTools 三条观测面指着同一个页面。
        // 代价说清楚：开着它，任何能 adb 到这台机的人都能驱动这个页面（而这个页面里是一个已鉴权的
        // root 级会话）。这台机本来就常年 adb + root，所以开；不想开就把这一行删掉重装。
        WebView.setWebContentsDebuggingEnabled(true);

        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                String u = req.getUrl().toString();
                if (u.startsWith("dsh-app://")) { handle(u); return true; }
                if (sameEntry(req.getUrl())) return false;         // 入口自己那台：留在壳里
                openExternal(req.getUrl());                        // 别的 http(s)：交系统浏览器（DSHA :841-866）
                return true;
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest req, WebResourceError e) {
                if (!req.isForMainFrame()) return;                 // 子资源失败别把整页踢掉
                L("net-error", describeNet(e.getErrorCode()) + "｜" + req.getUrl());
                showPanel("netdown", describeNet(e.getErrorCode()) + "｜" + req.getUrl());
            }

            @Override
            public void onReceivedHttpError(WebView view, WebResourceRequest req, WebResourceResponse res) {
                if (!req.isForMainFrame()) return;
                int c = res.getStatusCode();
                L("http-error", "http=" + c + "｜" + req.getUrl());
                if (c == 404) showPanel("denied", "入口回了 404：它对所有不该放进来的请求一律 404，"
                        + "不区分\u201c路径不存在\u201d和\u201c口令不对\u201d");
                else if (c == 503) showPanel("engine", "http=503：入口在听，但还没从引擎的启动行里认到端口");
                else if (c == 502) showPanel("engine", "http=502：入口活着，上游（3080）打不开");
                else showPanel("http", "http=" + c);
            }

            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                navStarted = true;                 // 看门狗就等这一行：导航真的开始了
                micRev++;                          // 0.6：文档换了一代，之前那个待决的麦克风请求就地作废
                micPending = null;
                L("page-start", url);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                panel = false;                     // 真页面出来了，那屏说明就该翻篇
                L("page-finish", url + "｜标题=" + view.getTitle() + "｜进度=" + view.getProgress());
            }
        });

        // 面板 ↔ native 的唯一通道：prompt()。口令这类值走它的第二个参数，不进 URL、不进历史。
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onJsPrompt(WebView view, String url, String message, String defaultValue,
                                      JsPromptResult result) {
                if (message != null && message.startsWith("dsh:")) {
                    result.confirm("");
                    fromPanel(message.substring(4), defaultValue);
                    return true;
                }
                return false;                      // 网页自己弹的 prompt 归 WebView
            }

            /**
             * 页面要开新窗口（target=_blank / window.open）时的去处。
             * WebView 的规矩：必须给它塞一个 WebView，不然这一发被丢掉。我们并不真要第二个窗口 ——
             * 手机一屏就那么大，多开一窗只会让人找不到刚才点了什么。所以这个临时 WebView 只用来
             * **把目标地址捞出来**：同源的直接 load 进主 WebView（等于点了个普通链接），
             * 外站的交系统浏览器（照 DSHA WebPreviewActivity.java:841-866 那条判断）。
             */
            @Override
            public boolean onCreateWindow(WebView view, boolean isDialog, boolean isUserGesture, Message resultMsg) {
                final WebView tmp = new WebView(view.getContext());
                tmp.setWebViewClient(new WebViewClient() {
                    @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                        String u = r.getUrl().toString();
                        boolean mine = sameEntry(r.getUrl());
                        L("new-window", (isUserGesture ? "手势" : "脚本") + "开新窗 → " + u
                                + (mine ? "（收进本窗口）" : "（交系统浏览器）"));
                        if (mine) web.loadUrl(u); else openExternal(r.getUrl());
                        kill(v);
                        return true;
                    }
                    @Override public void onPageFinished(WebView v, String u) { kill(v); }
                });
                try {
                    ((WebView.WebViewTransport) resultMsg.obj).setWebView(tmp);
                    resultMsg.sendToTarget();
                    return true;
                } catch (Exception e) {
                    L("new-window-fail", e.getClass().getSimpleName());
                    kill(tmp);
                    return false;
                }
            }

            /**
             * 0.6：网页要设备能力的唯一入口。语音输入插件在页面里调
             * navigator.mediaDevices.getUserMedia({audio:true})，WebView 就是把这一发交到这里。
             * 0.5 之前这个回调根本没实现 ⇒ 走 WebChromeClient 的默认实现，而默认实现是**一律 deny**，
             * 所以他在手机上点语音输入时永远拿不到麦克风（这是壳的缺口，不是插件的）。
             * 放行条件与只放什么，见 requestMic() 那段逐条判据。
             */
            @Override
            public void onPermissionRequest(PermissionRequest request) {
                requestMic(request);
            }

            /** 页面自己撤回了这一发（插件取消录音、组件被卸载都会走到这里）：把手里那个作废，别等一个已经不存在的请求。 */
            @Override
            public void onPermissionRequestCanceled(PermissionRequest request) {
                if (micPending == request) {
                    micPending = null;
                    L("mic", "页面自己撤回了这次授权请求 ⇒ 待决的那个已作废");
                }
            }
        });

        // 0.5：WebView 外面套一层 FrameLayout，只为给"再按一次返回退出"那枚浮层一个落点。
        // 为什么不画进页面里：那是前端的地盘，页面一重绘/一刷新我们的提示就没了，而且它得跟着 Activity 的生命周期走。
        root = new FrameLayout(this);
        root.addView(web, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        setContentView(root, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        goFullscreen();       // 他要的"打开就是全屏"：状态栏与导航栏进来就收掉，见 goFullscreen 那段注释
        L("lifecycle", "onCreate｜WebView 已建、准备 loadUrl");
        String direct = fromIntent();
        if (!empty(direct)) loadDirect(direct);
        else openEntry();
    }

    /**
     * 进 App 就把顶部状态栏和底部导航栏收掉（他 2026-10-20 的原话：顶部那个状态栏还是要显示，
     * 我要它隐藏）。API 30+ 走 WindowInsetsController，30 以下才用那套已废弃的 systemUiVisibility。
     * 行为选 BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE：从边缘滑一下会临时露出来（要看得见电量和时间），
     * 一两秒后自己再收回去 —— 不是永久露出，也不是根本滑不出来。
     * 为什么不用 manifest 里那条 windowFullscreen：它只管状态栏、管不到导航栏，而且 Android 15 上
     * 对 targetSdk 35 那套已废弃的窗口旗标不保证生效；这条是运行时真去调控制器，装完在屏幕上量。
     */
    private void goFullscreen() {
        if (Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController c = getWindow().getInsetsController();
            if (c == null) { L("fullscreen", "拿不到 InsetsController，这一版没改成全屏"); return; }
            c.hide(WindowInsets.Type.systemBars());
            c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            L("fullscreen", "已请求隐藏状态栏+导航栏（API 30+ 控制器，边缘滑出临时显示）");
        } else {
            getWindow().getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                  | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                  | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                  | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                  | View.SYSTEM_UI_FLAG_FULLSCREEN
                  | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
            L("fullscreen", "已请求隐藏（API " + Build.VERSION.SDK_INT + " 走旧旗标那条路）");
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        String direct = fromIntent();
        if (!empty(direct)) { loadDirect(direct); return; }
        // 已经在入口页上就别重拉：SPA 里正在输入的东西会被刷掉。只有停在说明屏/别的源时才重开。
        String cur = web.getUrl();
        if (panel || cur == null || !sameEntry(Uri.parse(cur))) openEntry();
    }

    @Override
    protected void onPause() {
        super.onPause();
        CookieManager.getInstance().flush();
        // 0.3 这里还有一句 web.pauseTimers()，0.4 拿掉了。原因：pauseTimers 是**整个进程**级别的
        // "把所有 WebView 的 JS 定时器冻住"，而退出重进那条路上 Activity 会换实例 —— 旧实例的 onPause
        // 完全可能排到新实例 onResume 之后才跑，那一冻就没有人负责解冻。它省的那点电不值这个风险，
        // 页面在后台本来也会被系统节流。读数与推断见 RUNBOOK 14.18。
        L("lifecycle", "onPause（0.4 起这里不再 pauseTimers）");
    }

    @Override
    protected void onResume() {
        super.onResume();
        web.resumeTimers();          // 留着：老版本装过的实例可能还冻着，这里无条件解一次
        goFullscreen();              // 从通知栏/别的 App 回来时系统栏会露出来，回来就再收一次
        L("lifecycle", "onResume｜可见，全屏已重设");
    }

    @Override
    protected void onDestroy() {
        CookieManager.getInstance().flush();
        ui.removeCallbacksAndMessages(null);
        micPending = null;                 // 0.6：实例要没了，攥着的那个媒体请求直接作废
        L("lifecycle", "onDestroy");
        super.onDestroy();
    }

    /**
     * 网页要麦克风时的判据与去处（0.6）。
     *
     * 为什么不是"看见请求就 grant"：这一发grant 出去等于把手机麦克风交给**当前那个页面**。
     * 我们的地址是 127.0.0.1 上的明文 HTTP，本机任何进程都能在那个端口上试东西，所以判据照
     * DSHA 那份 MicrophonePolicy.java:9-36 逐条搬：必须是 http（不许 https 之外的怪 scheme、
     * 不许 blob:/file:）、主机名必须恰是 127.0.0.1 或 localhost、必须带端口、而且**请求来源与
     * 当前入口的 host+port 全等**（:3080 与 :3081 在它那套判据里就是两个不同来源，见它的单测
     * MicrophonePolicyTest.java:7-31 —— 端口不一样直接 false）。
     * 只放音频：resources 数组必须长度 1 且就是 AUDIO_CAPTURE，掺了 video 一律拒（同 :43 那条）。
     * 一次只攥一个待决请求（同 :41）；页面换了文档（micRev 变了 / 当前 URL 不再是入口）就作废（同 :33-37）。
     *
     * 系统那一层的权限什么时候要：不在启动时预申请，等网页真开口才申请 —— 这是 DSHA
     * docs/releases/v0.1.7-rc2-microphone.md:10 那条"装机后 granted=false 才是验收项"的做法，
     * 好处是用户能看清"是我刚才点了录音才弹这个"。
     *
     * 与先例不同的两处（都是被我们自己的形状逼的，不是我想省事）：
     * ① DSHA 用 AndroidX 的 ActivityResultRegistry（BrowserMicrophone.java:111-130），这个壳没有
     *    任何第三方依赖，只能走 Activity 自带的 requestPermissions + onRequestPermissionsResult。
     * ② 它每个网页文档持一个 WebViewMicrophone 实例（WebPreviewActivity.java:749-758），我们只有
     *    一个 WebView、一个 Activity，所以用 micRev 这个代号顶替"文档代次"。
     */
    private void requestMic(final PermissionRequest request) {
        final long expected = micRev;
        String why = null;
        if (micPending != null) why = "已经有一个待决的媒体请求没处理完";
        else if (request.getOrigin() == null) why = "请求没带来源，无法判定是谁在要麦克风";
        else if (!audioOnly(request.getResources())) why = "要的不只是麦克风（" + join(request.getResources()) + "）";
        else if (!micTrusted(request.getOrigin().toString())) why = "来源不在放行范围：" + request.getOrigin();
        else if (!micCurrent(expected)) why = "这一发已经过期（页面换了文档或已离开入口）";
        if (why != null) {
            L("mic", "拒绝 ｜ 原因：" + why);
            denyMic(request);
            return;
        }
        micPending = request;
        micAnswered = false;
        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            L("mic", "系统权限本来就有 ⇒ 直接把这一发放行给页面");
            finishMic(true, expected);
            return;
        }
        L("mic", "系统层还没有 RECORD_AUDIO ⇒ 弹给用户（他点了录音插件才会走到这一步）");
        try {
            requestPermissions(new String[]{android.Manifest.permission.RECORD_AUDIO}, REQ_MIC);
        } catch (Exception e) {
            L("mic", "申请系统权限这一步就失败了（" + e.getClass().getSimpleName() + "）⇒ 拒绝");
            finishMic(false, expected);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode != REQ_MIC) return;
        boolean ok = results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED;
        L("mic", "系统那一层的结果=" + (ok ? "允许" : "拒绝")
                + "｜剩下的待决请求=" + (micPending == null ? "无" : "还有一个"));
        if (!ok) toast("刚才没给麦克风权限：要用的话到 系统设置 → 应用 → DSH 工作台 → 权限 → 麦克风 打开");
        finishMic(ok, micRev);
    }

    /** 系统弹窗有了结果：要么把 AUDIO_CAPTURE 交回页面，要么 deny。两次结果打进同一个闩里，只认第一次。 */
    private void finishMic(boolean allowed, long expected) {
        PermissionRequest req = micPending;
        if (req == null) { L("mic", "没有待决请求可交付（大概是页面自己撤了）"); return; }
        if (micAnswered) { L("mic", "这一发已经交付过一次，忽略重复结果"); return; }
        if (!micCurrent(expected)) {
            micPending = null;
            L("mic", "交付时页面已经不等了（换文档或离开入口）⇒ 拒绝");
            denyMic(req);
            return;
        }
        micAnswered = true;
        micPending = null;
        if (!allowed) { denyMic(req); return; }
        try {
            req.grant(new String[]{PermissionRequest.RESOURCE_AUDIO_CAPTURE});
            L("mic", "已把麦克风交回页面（只交 AUDIO_CAPTURE 这一项）");
        } catch (RuntimeException cancelled) {
            // 照 WebViewMicrophone.java:59-61：请求可能已经被 Chromium 那边作废，grant 会抛；抛了就必须补一个 deny。
            L("mic", "grant 抛了（" + cancelled.getClass().getSimpleName() + "）⇒ 补一次 deny");
            denyMic(req);
        }
    }

    private static void denyMic(PermissionRequest request) {
        try {
            request.deny();
        } catch (RuntimeException alreadyCancelled) {
            // 页面早就撤了，deny 会抛；这一发本来就已经不存在，不用留证据。
        }
    }

    /** 到交付这一刻，页面还得是"当初那一代文档 + 还在入口上"，否则这一发不能放行。 */
    private boolean micCurrent(long expected) {
        if (micRev != expected) return false;
        String cur = web == null ? null : web.getUrl();
        return cur != null && micTrusted(cur) && sameEntry(Uri.parse(cur));
    }

    /** 只认 http + 恰为 127.0.0.1/localhost + 带端口 + 与当前入口同 host 同端口（判据出处见 requestMic 那段）。 */
    boolean micTrusted(String url) {
        try {
            Uri u = Uri.parse(url);
            String scheme = u.getScheme();
            String host = u.getHost();
            if (!"http".equalsIgnoreCase(scheme)) return false;
            if (u.getUserInfo() != null) return false;
            int p = u.getPort();
            if (p < 1 || p > 65535) return false;
            if (host == null) return false;
            if (!"127.0.0.1".equals(host) && !"localhost".equalsIgnoreCase(host)) return false;
            String got = scheme + "://" + host + ":" + p;
            String want = originOf(entryUrl());
            return got.equalsIgnoreCase(want);
        } catch (Exception invalid) {
            return false;
        }
    }

    private static boolean audioOnly(String[] resources) {
        return resources != null && resources.length == 1
                && PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resources[0]);
    }

    private static String join(String[] xs) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; xs != null && i < xs.length; i++) b.append(i == 0 ? "" : ", ").append(xs[i]);
        return b.toString();
    }

    private void toast(String s) {
        ui.post(new Runnable() {
            @Override public void run() {
                try {
                    Toast.makeText(MainActivity.this, s, Toast.LENGTH_LONG).show();
                } catch (Exception e) {
                    L("mic", "Toast 没弹出来（" + e.getClass().getSimpleName() + "），这句话只在日志里");
                }
            }
        });
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode != KeyEvent.KEYCODE_BACK) return super.onKeyDown(keyCode, event);
        return handleBack() || super.onKeyDown(keyCode, event);
    }

    /**
     * 返回键的四层语义（他 2026-10-20 提的，0.5 按他第二次的更正重排）。
     *
     * 0.4 那版错在把「页面还能退一层」当成第一层、把「弹确认」当成第二层，而他真正要的是：
     * 左边侧边栏摊开、盖住整个工作区的时候（他原话"左边的侧边栏占据全屏"），先按返回要**回到他干活的那个
     * 聊天界面**，不该在这时候问要不要退出。实测读数：这页 history.length 恒为 1（SPA 不推历史），
     * 所以 0.4 那句 web.canGoBack() 在他的页面上基本永远是 false ⇒ 侧边栏摊开时也直接走到"弹确认"，
     * 正是他看到的那个毛病。判据与量法见 RUNBOOK 14.19。
     *
     * 0.5 的顺序：① 停在壳自己画的说明屏 ⇒ 返回=回工作台；② 上一次返回的提示还飘着 ⇒ 这一发就是"第二下"，退；
     * ③ 页面上有一层盖着（侧边栏摊开 / 右侧边栏开着 / 消息全屏）⇒ 在页面里把它关掉，这一次返回到此为止；
     * ③′ 没有盖着的层、但浏览器历史还能退 ⇒ 在 WebView 里退一层（0.4 那层留着，挪到"盖着的层"后面）；
     * ④ 三层都退不动 ⇒ 飘那枚"再按一次返回，退出工作台"，1.8 秒内再按一下才真退。
     *
     * 为什么同时挂 onKeyDown 和 onBackPressed：这台机 targetSdk=35，侧滑手势到底走不走 KEYCODE_BACK
     * 我没有读数（0.3 那条注释里写的是推断）。两个口都接到同一个 handleBack()，哪一条真被调用
     * 由日志说话；handleBack() 返回 true 表示这一发我们已经处理掉了，不会再往下传，所以不会弹两次。
     */
    @Override
    public void onBackPressed() {
        if (!handleBack()) super.onBackPressed();
    }

    private boolean handleBack() {
        if (panel) { openEntry(); return true; }                       // ① 停在说明屏：返回=回工作台
        if (hintShowing()) {                                           // ② 提示还飘着 ⇒ 这一发就是"再按一次"
            L("back", "提示还飘着又按了一次返回 ⇒ 按他说的退出，不等它自己消散");
            hideHint();
            finish();
            return true;
        }
        closeOverlayOrHint();                                          // ③ / ④（问页面是异步的，见那个方法的注释）
        return true;
    }

    /**
     * 页面上有没有哪一层正盖着？有就把**最该关的那一层**关掉，没有才飘退出提示。
     *
     * 为什么这一层非问页面不可：侧边栏摊开不是浏览器历史里的一条（实测 history.length=1），
     * 壳在 Java 这边也没有任何读数能看出"那一层开着" —— 它是前端自己的一个 class 切换。
     * 唯一诚实的判据是页面上那颗按钮：收起时看得见的是「打开侧边栏」，摊开时看得见的是「收起侧边栏」
     * （2026-10-20 用 CDP 在他这个页面上量的：侧边栏那一列 56px ↔ 280px，屏宽 360 CSS px）。
     * 所以这里点那颗「收起X」，等于替他按了前端自己准备的那颗按钮，不猜布局、不自己算宽度。
     *
     * 为什么要"看得见"这一条：这些按钮在 DOM 里一直都在（侧边栏收起时「收起侧边栏」这个节点也存在，
     * 只是不可见），只按 aria-label 找就会在根本没摊开的时候也"关"一把。
     *
     * 为什么这里要绕异步：evaluateJavascript 的回调不在当前调用栈上回来，而返回键这一发必须先当场吞掉
     * （return true），不然系统直接退到桌面，等我们问出问题来已经晚了。所以先吞、再在回调里决定做什么。
     * 代价是提示比另外三层慢一截才出现 —— 实测这一问一次约 1ms（见 back :: 那几行的时刻差），肉眼看不出。
     * 兜底那 800ms：页面被系统冻住时回调可能永远不来，那返回键就死在这层了，所以到点直接飘提示。
     */
    private void closeOverlayOrHint() {
        final boolean[] answered = { false };
        final Runnable fallback = new Runnable() {
            @Override public void run() {
                if (answered[0]) return;
                answered[0] = true;
                L("back", "问页面 800ms 没回音 ⇒ 不等了，直接飘退出提示");
                showExitHint();
            }
        };
        ui.postDelayed(fallback, 800);
        try {
            web.evaluateJavascript(OVERLAY_JS, new ValueCallback<String>() {
                @Override public void onReceiveValue(String v) {
                    if (answered[0]) return;                 // 兜底已经做过了，这一发迟到的回音不再做事
                    answered[0] = true;
                    ui.removeCallbacks(fallback);
                    String closed = parseJsString(v);
                    if (closed != null && closed.length() > 0 && !"none".equals(closed)) {
                        L("back", "页面上「" + closed + "」这一层开着 ⇒ 已在页面里替关掉，这一次返回到此为止");
                        return;
                    }
                    if (web.canGoBack()) {                     // 0.4 那层保留，只是挪到"盖着的层"后面
                        web.goBack();
                        L("back", "页面上没有盖着的层，但浏览器历史还能退 ⇒ 已在 WebView 里退一层");
                        return;
                    }
                    L("back", "页面上没有盖着的层、历史也退不动 ⇒ 飘退出提示，不直接退");
                    showExitHint();
                }
            });
        } catch (Exception e) {
            if (answered[0]) return;
            answered[0] = true;
            ui.removeCallbacks(fallback);
            L("back", "问页面失败（" + e.getClass().getSimpleName() + "）⇒ 直接飘退出提示");
            showExitHint();
        }
    }

    /** evaluateJavascript 给回来的是 JSON 字面量（字符串带引号），这里只把外层引号摘掉。 */
    private static String parseJsString(String v) {
        if (v == null) return null;
        String s = v.trim();
        if (s.length() >= 2 && s.startsWith("\"") && s.endsWith("\"")) s = s.substring(1, s.length() - 1);
        return s.replace("\\\"", "\"");
    }

    // 三层"盖着"的状态，按该先关谁排的序：消息全屏在最上层，其次右侧边栏，最后才是左边那一列。
    private static final String OVERLAY_JS =
            "(function(){"
          + "var NAMES=['退出全屏','收起右侧边栏','收起侧边栏'];"
          + "function vis(e){var r=e.getBoundingClientRect();var s=window.getComputedStyle(e);"
          + "return r.width>2&&r.height>2&&s.visibility!=='hidden'&&s.display!=='none';}"
          + "var bs=Array.prototype.filter.call(document.querySelectorAll('button[aria-label]'),vis);"
          + "for(var i=0;i<NAMES.length;i++){for(var j=0;j<bs.length;j++){"
          + "if(bs[j].getAttribute('aria-label')===NAMES[i]){bs[j].click();return NAMES[i];}}}"
          + "return 'none';})()";

    // ── 那枚"再按一次返回退出"的浮层（0.5 换掉 0.4 那张 AlertDialog）─────────────
    /**
     * 他 2026-10-20 的原话：0.4 那张确认屏"太丑了，而且字体太小"，而且**不该要我去点"留下/退出"** ——
     * 别的 App 都是按一下返回浮出一条提示，一两秒自己消散，这期间再按一次才真退。这里照这个做。
     *
     * 几个细节是有意选的：字号 15sp（那张 AlertDialog 的正文默认 14sp、标题 20sp，他嫌小的正是正文那行）；
     * 浮层不吃点击（没设 clickable），提示飘着的这 1.8 秒里页面照常能点、能滚；
     * 位置贴底部中间、离底 40dp（这条是目测让开底部那根手势条，没量过那根条多宽 —— 算选择，不算读数）：
     * 第一版放 96dp，装上在屏幕上量了一眼（downloads/dsh-shot-05-hint.png），正好压在输入框那半截上，改成 40dp 落到框下面。
     * 淡入 120ms、停 1500ms、淡出 300ms，"算第二下"的窗口取 1800ms（比淡出结束稍长一点：淡出到一半再按也算退，
     * 那时候人已经看清那行字了，不该再把他留在页面里）。
     */
    private static final long HINT_HOLD_MS = 1500;
    private static final long HINT_FADE_IN_MS = 120;
    private static final long HINT_FADE_OUT_MS = 300;
    private static final long HINT_WINDOW_MS = 1800;

    private final Runnable fadeHintOut = new Runnable() {
        @Override public void run() {
            if (hint == null) return;
            hint.animate().alpha(0f).setDuration(HINT_FADE_OUT_MS).start();
        }
    };

    private boolean hintShowing() {
        return hint != null && hint.getVisibility() == View.VISIBLE
                && System.currentTimeMillis() < hintUntil;
    }

    private void showExitHint() {
        if (root == null) { L("back", "root 还没建，提示没处放 ⇒ 直接退"); finish(); return; }
        if (hint == null) hint = makeHint();
        hint.animate().cancel();
        hint.setAlpha(0f);
        hint.setVisibility(View.VISIBLE);
        hint.animate().alpha(1f).setDuration(HINT_FADE_IN_MS).start();
        ui.removeCallbacks(fadeHintOut);
        ui.postDelayed(fadeHintOut, HINT_HOLD_MS);
        hintUntil = System.currentTimeMillis() + HINT_WINDOW_MS;
        L("back", "已飘出「再按一次返回，退出工作台」，" + HINT_WINDOW_MS + "ms 内再按一下才退");
    }

    private void hideHint() {
        ui.removeCallbacks(fadeHintOut);
        if (hint != null) { hint.animate().cancel(); hint.setVisibility(View.GONE); }
    }

    private TextView makeHint() {
        float d = getResources().getDisplayMetrics().density;
        TextView t = new TextView(this);
        t.setText("再按一次返回，退出工作台");
        t.setTextColor(Color.parseColor("#F3F5F7"));
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        t.setLetterSpacing(0.02f);
        t.setSingleLine(true);
        t.setGravity(Gravity.CENTER);
        t.setElevation(6 * d);
        t.setPadding(dp(20), dp(11), dp(20), dp(11));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.parseColor("#E620262F"));      // 跟页面那套深色底同族，不透明度 90%
        bg.setCornerRadius(dp(21));
        bg.setStroke(Math.max(1, (int) (1 * d)), Color.parseColor("#2EFFFFFF"));
        t.setBackground(bg);
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT);
        lp.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
        lp.bottomMargin = dp(40);
        t.setLayoutParams(lp);
        t.setClickable(false);
        t.setFocusable(false);
        t.setVisibility(View.GONE);
        root.addView(t);
        return t;
    }

    private int dp(float v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }


    // ── 地址与口令 ───────────────────────────────────────────────────────────
    String entryUrl() {
        String u = prefs.getString(KEY_URL, null);
        if (empty(u) && !BAKED_URL.startsWith("__")) u = BAKED_URL;
        return empty(u) ? DEFAULT_URL : u;
    }

    String entryKey() {
        String k = prefs.getString(KEY_SECRET, null);
        if (empty(k) && !BAKED_KEY.startsWith("__")) k = BAKED_KEY;
        return empty(k) ? "" : k;
    }

    private static boolean empty(String x) {
        return x == null || x.trim().length() == 0;
    }

    private String fromIntent() {
        Intent it = getIntent();
        if (it == null) return null;
        String u = it.getStringExtra("url");
        if (empty(u)) u = it.getDataString();       // am start -d "http://127.0.0.1:3080/?token=..."
        return (u != null && u.startsWith("http://127.0.0.1")) ? u : null;
    }

    /** 同一个入口？按 origin（scheme://host:port）比，不比整条 URL。 */
    boolean sameEntry(Uri u) {
        try {
            return originOf(u.toString()).equals(originOf(entryUrl()));
        } catch (Exception e) {
            return false;
        }
    }

    static String originOf(String url) {
        try {
            Uri u = Uri.parse(url);
            String scheme = u.getScheme() == null ? "http" : u.getScheme();
            String host = u.getHost();
            if (host == null) return url;
            int p = u.getPort();
            return p > 0 ? scheme + "://" + host + ":" + p : scheme + "://" + host;
        } catch (Exception e) {
            return url;
        }
    }

    // ── 三条加载路径 ─────────────────────────────────────────────────────────
    /** 主路径：种入口口令的 cookie → 回调里 flush → 才 loadUrl（DSHA :692-706 那个次序）。 */
    void openEntry() {
        final String target = entryUrl();
        final String key = entryKey();
        L("open-entry", target + "｜口令 " + key.length() + " 字符（值不打印）");
        if (key.isEmpty()) {
            showPanel("nokey", "");
            return;
        }
        CookieManager cm = CookieManager.getInstance();
        cm.setCookie(originOf(target), COOKIE + "=" + key + "; path=/; max-age=2592000",
                new ValueCallback<Boolean>() {
                    @Override
                    public void onReceiveValue(Boolean accepted) {
                        L("cookie", "setCookie(" + originOf(target) + ") accepted=" + accepted);
                        cm.flush();
                        runOnUiThread(new Runnable() {
                            @Override
                            public void run() {
                                panel = false;
                                retryLeft = 2;
                                startLoad(target);
                            }
                        });
                    }
                });
    }

    /**
     * 真正把地址交给 WebView 的那一句，外加一个看门狗。
     * 为什么要有：他 2026-10-20 报"退出重进之后先黑屏十几秒"，壳的日志把这件事量出来了 ——
     * 21:32:39.226 已经在 cookie 回调里调了 loadUrl，可 page-start 到 21:33:16.853 才来，
     * 中间 37.6 秒，而那段时间服务端**一条请求都没收到**（入口流水里 GET / 只有 2ms）⇒
     * 卡的是 WebView 内部"按下到真的开始导航"那一段，我们这一侧使不上劲。
     * 同一段路 21:40:22 干净冷启再量一次是 40ms 到 page-start、639ms 到 page-finish，所以这是**偶发**，
     * 不是每次都慢。看门狗做的事：按下 5 秒还没等到 page-start 就自己再按一次（最多两次），
     * 并把每一次都记进 shell.log —— 下次再黑屏，日志里就有"到底是没开始、还是开始了但很慢"这一条。
     */
    private void startLoad(final String url) {
        navStarted = false;
        loadAt = System.currentTimeMillis();
        web.loadUrl(url);
        web.postDelayed(new Runnable() {
            @Override public void run() {
                if (navStarted) return;
                long waited = System.currentTimeMillis() - loadAt;
                if (retryLeft > 0) {
                    retryLeft--;
                    L("stall", "loadUrl 之后 " + waited + "ms 还没开始导航 ⇒ 自己重试（还剩 " + retryLeft + " 次额度）");
                    web.clearCache(true);
                    startLoad(url);
                } else {
                    L("stall", "loadUrl 之后 " + waited + "ms 仍没开始导航，重试额度用完 ⇒ 交回那屏说明");
                    showPanel("netdown", "工作台没有响应（导航一直没开始）");
                }
            }
        }, 5000);
    }

    /** 兜底路径：控制台菜单递进来一条带 token 的裸引擎地址时照它走一次（入口没起时也能进）。 */
    void loadDirect(String url) {
        L("load-direct", url == null ? "(null)" : url.replaceAll("token=[A-Za-z0-9_-]+", "token=<redacted>"));
        panel = false;
        retryLeft = 2;
        startLoad(url);
    }

    // ── 说明屏与那一个通道 ───────────────────────────────────────────────────
    private void showPanel(String kind, String detail) {
        L("panel", kind + "｜" + detail);
        panel = true;
        panelKind = kind;
        panelDetail = detail == null ? "" : detail;
        statusText = "";
        web.loadDataWithBaseURL(PANEL_BASE, panelHtml(), "text/html", "utf-8", PANEL_BASE);
        fetchStatus();
    }

    private void handle(String url) {
        Uri u = Uri.parse(url);
        String what = u.getHost() == null ? "" : u.getHost();
        // 「重载」连缓存一起清：入口那边换了兼容脚本、或首页字节变了，光 loadUrl 有可能直接吃
        // WebView 里那份缓存的旧 HTML（2026-10-20 实测：入口重启后 App 一条 HTML 请求都没发出去，
        // 只有 /assets/*.js 进来了）。入口现在对改过的 HTML 回 no-store，这一句是双保险。
        if ("retry".equals(what)) { web.clearCache(true); openEntry(); }
        else if ("diag".equals(what)) showPanel(panelKind, panelDetail);
        else if ("clear".equals(what)) {
            CookieManager cm = CookieManager.getInstance();
            cm.removeAllCookies(null);
            cm.flush();
            web.clearCache(true);
            prefs.edit().remove(KEY_URL).remove(KEY_SECRET).apply();
            showPanel("cleared", "");
        } else if ("set".equals(what)) {
            String n = u.getQueryParameter("url");
            if (n != null && n.startsWith("http://127.0.0.1")) loadDirect(n);
            else showPanel("badurl", n == null ? "" : n);
        }
    }

    private void fromPanel(String what, String value) {
        if ("retry".equals(what)) { openEntry(); return; }
        if ("diag".equals(what)) { showPanel(panelKind, panelDetail); return; }
        if ("clear".equals(what)) {
            CookieManager cm = CookieManager.getInstance();
            cm.removeAllCookies(null);
            cm.flush();
            web.clearCache(true);
            prefs.edit().remove(KEY_URL).remove(KEY_SECRET).apply();
            showPanel("cleared", "");
            return;
        }
        if ("apply".equals(what) && value != null) {
            String[] parts = value.split("\n", 2);
            String url = parts[0].trim();
            String key = parts.length > 1 ? parts[1].trim() : entryKey();
            if (url.startsWith("http://127.0.0.1") || url.startsWith("http://localhost")) {
                SharedPreferences.Editor ed = prefs.edit();
                ed.putString(KEY_URL, url);
                if (!key.isEmpty()) ed.putString(KEY_SECRET, key);
                ed.apply();
                openEntry();
            } else {
                showPanel("badurl", url);
            }
            return;
        }
        if ("open".equals(what) && value != null && value.startsWith("http://127.0.0.1")) {
            loadDirect(value.trim());
        }
    }

    /** 入口的自述页：node dsh-entry.js --status 那份读数，同一个东西在 App 里也看得见。 */
    private void fetchStatus() {
        final String target = originOf(entryUrl()) + "/__entry_status";
        final String key = entryKey();
        new Thread(new Runnable() {
            @Override
            public void run() {
                String got;
                try {
                    HttpURLConnection c = (HttpURLConnection) new URL(target).openConnection();
                    c.setConnectTimeout(2500);
                    c.setReadTimeout(2500);
                    c.setRequestProperty("Cookie", COOKIE + "=" + key);
                    int code = c.getResponseCode();
                    L("status", "http=" + code + "（自述页里没有口令与 token 的值）");
                    BufferedReader r = new BufferedReader(new InputStreamReader(
                            code >= 400 ? c.getErrorStream() : c.getInputStream(), "UTF-8"));
                    StringBuilder sb = new StringBuilder();
                    String line;
                    while ((line = r.readLine()) != null) sb.append(line).append('\n');
                    r.close();
                    got = "打这页时实测 http=" + code + "\n" + sb;
                } catch (Exception e) {
                    L("status-fail", target + "：" + e.getClass().getSimpleName());
                    got = "打不开 " + target + "：" + e.getClass().getSimpleName()
                            + " —— 入口这个 node 进程没在跑（Termux 图标选 2）";
                }
                statusText = got;
                if (panel) {
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            if (panel) web.loadDataWithBaseURL(PANEL_BASE, panelHtml(),
                                    "text/html", "utf-8", PANEL_BASE);
                        }
                    });
                }
            }
        }).start();
    }

    /** 临时 WebView 用完就销毁（它从没进过 view 树，所以 stopLoading + destroy 就够）。 */
    private static void kill(WebView v) {
        try { v.stopLoading(); } catch (Exception ignored) { }
        try { v.destroy(); } catch (Exception ignored) { }
    }

    private void openExternal(Uri u) {
        String s = u == null ? null : u.toString();
        if (s == null || !(s.startsWith("http://") || s.startsWith("https://"))) return;
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, u));
        } catch (Exception ignored) {
            // 没有浏览器能接：不弹 toast 打断正在输入的人，说明屏里本来就有"贴地址"这条路
        }
    }

    /**
     * WebView 内核身份照 DSHA 的做法写进说明屏（WebPreviewActivity.java:665-670）。
     * 返回类型按 android-35 的 android.jar 实测读数写：javap 给的是
     * `public static android.content.pm.PackageInfo getCurrentWebViewPackage()` —— 不是文档里常见的
     * WebViewProviderInfo（那个类名在这份 jar 里根本不存在，第一版照记忆写就直接编译不过）。
     */
    private String webviewVersion() {
        try {
            android.content.pm.PackageInfo pi = WebView.getCurrentWebViewPackage();
            if (pi == null) return "读不到（系统没报告 provider）";
            return pi.packageName + " " + (pi.versionName == null ? "?" : pi.versionName);
        } catch (Throwable t) {
            return "读不到（" + t.getClass().getSimpleName() + "）";
        }
    }

    private static String describeNet(int code) {
        // 常量名与数值都从 android-35 android.jar 里 javap 读出来的，不靠记忆
        if (code == WebViewClient.ERROR_HOST_LOOKUP) return "主机解析不了（ERROR_HOST_LOOKUP）";
        if (code == WebViewClient.ERROR_CONNECT) return "连不上（ERROR_CONNECT）";
        if (code == WebViewClient.ERROR_IO) return "读写中断（ERROR_IO）";
        if (code == WebViewClient.ERROR_TIMEOUT) return "超时（ERROR_TIMEOUT）";
        if (code == WebViewClient.ERROR_BAD_URL) return "地址非法（ERROR_BAD_URL）";
        if (code == WebViewClient.ERROR_UNSUPPORTED_SCHEME) return "这个 scheme 不支持（ERROR_UNSUPPORTED_SCHEME）";
        if (code == WebViewClient.ERROR_UNSAFE_RESOURCE) return "资源被拦（ERROR_UNSAFE_RESOURCE）";
        if (code == WebViewClient.ERROR_UNKNOWN) return "没人应答（ERROR_UNKNOWN，最常见就是端口上空着）";
        return "加载失败（errno=" + code + "）";
    }

    // ── 那一屏长什么样 ───────────────────────────────────────────────────────
    private String panelHtml() {
        String url = esc(entryUrl());
        String keyState = entryKey().isEmpty() ? "没设置" : "已设置（" + entryKey().length() + " 位）";
        String head;
        String body;
        if ("denied".equals(panelKind)) {
            head = "口令没被入口认";
            body = "<p>入口在听，但它判定这个请求不该进来。三种可能：这个 App 里的口令和 chroot 里"
                    + "<code>/root/.dsh/entry.key</code> 不一致；请求是从别的 App 跳过来的（它没这个 cookie）；"
                    + "或者 Host 头不是 127.0.0.1。最常见是第一种 —— 换过口令但没重装包、也没在这里重填。</p>";
        } else if ("engine".equals(panelKind)) {
            head = "入口活着，引擎没接上";
            body = "<p>" + esc(panelDetail) + "。这屏只可能是入口给的两个码：<code>503</code> 是它还没从"
                    + "引擎 stdout 那条启动行里认到端口，<code>502</code> 是端口认到了但 3080 打不开。"
                    + "入口会自己重拉引擎并退避（2s 起、翻倍、上限 30s），下面自述的 <code>gen</code> 与 "
                    + "<code>engine</code> 两行分得清是谁的问题。</p>";
        } else if ("nokey".equals(panelKind)) {
            head = "还没有入口口令";
            body = "<p>这个包里没烤口令，本机也还没填过。在 Termux 里跑 "
                    + "<code>sh /data/local/sh/dsh-chroot.sh --entry</code> 造一份并起入口，"
                    + "再重装 App；或者直接在这里填一次（填了就以此为准，包那份作废）。</p>";
        } else if ("cleared".equals(panelKind)) {
            head = "已清干净";
            body = "<p>cookie、缓存、本机设置都清了。现在可以重新填地址与口令。</p>";
        } else if ("badurl".equals(panelKind)) {
            head = "地址不收";
            body = "<p><code>" + esc(panelDetail) + "</code> —— 只收 127.0.0.1 / localhost。"
                    + "这台机的会话不往外送（入口本身也只绑回环，不学 DSHA 那份 0.0.0.0 的 LAN 代理）。</p>";
        } else if ("http".equals(panelKind)) {
            head = "入口给了个没见过的状态码";
            body = "<p>" + esc(panelDetail) + "</p>";
        } else {
            head = "连不上工作台";
            body = "<p>这个地址后面没人应答：<code>" + esc(panelDetail) + "</code></p>"
                    + "<p>入口是 chroot 里一个 node 进程。它没起来时这一屏是预期行为 —— 打开 <b>Terminal</b> "
                    + "图标选 <b>2)</b>（起服务 + 起入口），回来点重试。引擎起来了但入口没起来，症状是这条；"
                    + "反过来（入口在、引擎没在）是 503 那一屏。</p>";
        }
        return "<!doctype html><html lang=\"zh\"><head><meta charset=\"utf-8\">"
                + "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
                + "<style>" + css() + "</style></head><body>"
                + "<div class=\"card\"><h1>" + head + "</h1>"
                + "<div class=\"u\">" + url + "</div>" + body
                + "<div class=\"row\">"
                + "<button class=\"btn\" onclick=\"prompt('dsh:retry')\">重试</button>"
                + "<button class=\"btn ghost\" onclick=\"prompt('dsh:diag')\">重新拉自述</button>"
                + "<button class=\"btn ghost\" onclick=\"prompt('dsh:clear')\">清登录状态</button>"
                + "</div></div>"
                + "<div class=\"card\"><h2>入口自述 <small>GET /__entry_status</small></h2><pre>"
                + esc(empty(statusText) ? "（正在拉…点\u201c重新拉自述\u201d可再试）" : statusText) + "</pre></div>"
                + "<div class=\"card\"><h2>填地址与口令</h2>"
                + "<input id=\"u\" type=\"url\" value=\"" + url + "\">"
                + "<input id=\"k\" type=\"password\" placeholder=\"入口口令（当前：" + keyState + "）\">"
                + "<div class=\"row\"><button class=\"btn\" onclick=\"apply()\">保存并打开</button></div>"
                + "<p><small>口令不进 URL、不进浏览历史：它走 prompt() 的第二个参数递给壳，只落在这台机"
                + "App 私有目录的 SharedPreferences 里。包里烤的那份："
                + (BAKED_KEY.startsWith("__") ? "没烤" : "已烤") + "。</small></p></div>"
                + "<div class=\"card\"><h2>还有兜底那条路</h2>"
                + "<p>引擎自己的 3080 还在原样跑，入口只是替你把一次性 token 换成了长期 cookie。"
                + "入口起不来时，把 Termux 里 <code>--url</code> 打出来的那条带 token 的地址贴进来照样能进"
                + "（这条 token 用过就废，别拿去探测）。</p>"
                + "<input id=\"t\" type=\"url\" placeholder=\"http://127.0.0.1:3080/?token=...\">"
                + "<div class=\"row\"><button class=\"btn ghost\" onclick=\"openTok()\">按这条走一次</button></div>"
                + "<p><small>WebView 内核：" + esc(webviewVersion())
                + "（这行照 DSHA WebPreviewActivity.java:665-670 放进来 —— 页面白屏时先怀疑内核版本）"
                + "</small></p></div>"
                + "<script>function apply(){var u=document.getElementById('u').value,"
                + "k=document.getElementById('k').value;prompt('dsh:apply',u+'\\n'+k);}"
                + "function openTok(){var t=document.getElementById('t').value;"
                + "if(t.indexOf('http://127.0.0.1')===0)prompt('dsh:open',t);}</script>"
                + "</body></html>";
    }

    private static String css() {
        return "body{margin:0;padding:24px 16px;background:#0b0d12;color:#e8ecf3;"
                + "font:16px/1.6 system-ui,sans-serif}"
                + "h1{font-size:19px;margin:0 0 10px}h2{font-size:16px;margin:0 0 8px}"
                + ".card{background:#141926;border:1px solid #232c40;border-radius:14px;"
                + "padding:16px;margin-bottom:14px}"
                + ".u{font-family:monospace;font-size:12px;color:#8fa3c8;word-break:break-all;margin-bottom:8px}"
                + ".row{margin-top:10px}"
                + "button{display:inline-block;margin:4px 8px 0 0;padding:10px 16px;border-radius:10px;"
                + "border:0;background:#2b6cff;color:#fff;font-size:15px}"
                + "button.ghost{background:transparent;border:1px solid #33405e;color:#c6d2e6}"
                + "input{width:100%;box-sizing:border-box;padding:11px 12px;border-radius:10px;"
                + "border:1px solid #33405e;background:#0e1320;color:#e8ecf3;font-family:monospace;"
                + "font-size:13px;margin-top:8px}"
                + "pre{background:#0e1320;border:1px solid #232c40;border-radius:10px;padding:10px;"
                + "font-size:12px;white-space:pre-wrap;word-break:break-all;color:#b9c8e2;margin:0}"
                + "p{color:#a9b7cf;font-size:14px;margin:8px 0 0}small{color:#7f8ea8;font-size:12px}"
                + "code{font-family:monospace;color:#c6d2e6}";
    }

    private static String esc(String x) {
        if (x == null) return "";
        return x.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace("\"", "&quot;");
    }
}
