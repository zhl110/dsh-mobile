package com.zhl.dsh;

import android.net.LocalSocket;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/**
 * 走 chroot 里的 dsh-uinput 守护进程，从 /dev/uinput 注入（事件走 evdev → InputReader，deviceId 是真实设备号，
 * 与无障碍 dispatchGesture 的 deviceId=-1 不是一条路）。
 *
 * 方向是 **守护连我们**：SELinux 只放行 root→app 的 connectto；app(untrusted_app) 反过来连 su 的 socket 是 denied。
 * 所以 TreeService 起一个 @dsh-inject 的服务端，守护连上来后保持这条连接，我们在这条连接上发请求。
 * 守护不在（引擎没起 / 没部署）就回 false，调用方退回无障碍手势。
 */
final class Uinput {
    private static final int TIMEOUT_MS = 1500;

    private static LocalSocket sock;
    private static BufferedReader in;
    private static OutputStream out;

    static synchronized void attach(LocalSocket s) {
        close();
        try {
            s.setSoTimeout(TIMEOUT_MS);
            sock = s;
            in = new BufferedReader(new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
            out = s.getOutputStream();
        } catch (Exception e) {
            close();
        }
    }

    static synchronized void close() {
        try { if (sock != null) sock.close(); } catch (Exception ignored) {}
        sock = null; in = null; out = null;
    }

    static boolean tap(float nx, float ny, int holdMs) {
        JSONObject o = new JSONObject();
        try {
            o.put("op", "tap");
            o.put("nx", nx);
            o.put("ny", ny);
            if (holdMs > 0) o.put("ms", holdMs);
        } catch (Exception e) {
            return false;
        }
        return call(o);
    }

    static boolean swipe(float nx1, float ny1, float nx2, float ny2, int ms) {
        JSONObject o = new JSONObject();
        try {
            o.put("op", "swipe");
            o.put("nx1", nx1);
            o.put("ny1", ny1);
            o.put("nx2", nx2);
            o.put("ny2", ny2);
            o.put("ms", ms);
        } catch (Exception e) {
            return false;
        }
        return call(o);
    }

    static boolean key(int code) {
        JSONObject o = new JSONObject();
        try {
            o.put("op", "key");
            o.put("code", code);
        } catch (Exception e) {
            return false;
        }
        return call(o);
    }

    private static synchronized boolean call(JSONObject req) {
        if (sock == null || in == null || out == null) return false;
        try {
            out.write((req.toString() + "\n").getBytes(StandardCharsets.UTF_8));
            out.flush();
            String line = in.readLine();
            if (line == null) { close(); return false; }
            return new JSONObject(line).optBoolean("ok", false);
        } catch (Exception e) {
            close();
            return false;
        }
    }
}
