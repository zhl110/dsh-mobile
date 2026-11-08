package com.zhl.dsh;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

/**
 * 壳 0.13：前台保活服务。
 *
 * 为什么要有这个：TreeService（无障碍）活在 App 主进程里，而 OOS 的 cached-app 冻结会在 App
 * 退到后台约几十秒后把整个进程冻住（wchan=do_freezer_trap，实测量于 downloads/p94e/f/g）——
 * 冻住后 abstract socket 还在听，但没人 accept，引擎调工具就超时。doze 白名单 + standby active
 * 都挡不住（同样实测）。前台服务让进程停在 FOREGROUND_SERVICE 档（不是 cached）⇒ 不进冻结队列。
 *
 * 触发点放在 MainActivity.onCreate（用户点开 App 那一刻在前台，Android 12+ 才允许起前台服务）；
 * 不请求 POST_NOTIFICATIONS 运行权限，通知在 13+ 可能不显示在抽屉里，但前台服务身份照算、进程照保。
 * 关闭无障碍开关不会停这个服务（它只保进程，不碰屏幕）；App 彻底退出时系统自会回收。
 */
public class PhoneKeepAlive extends Service {
    private static final String CHANNEL = "dsh-phone-keepalive";
    private static final int NOTIF_ID = 0x4453; // 固定 id，重复 startForeground 只更新同一条

    @Override
    public void onCreate() {
        super.onCreate();
        NotificationManager nm = getSystemService(NotificationManager.class);
        Notification n;
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel c = new NotificationChannel(CHANNEL, "DSH 手机控制", NotificationManager.IMPORTANCE_LOW);
            c.setShowBadge(false);
            if (nm != null) nm.createNotificationChannel(c);
            n = new Notification.Builder(this, CHANNEL)
                    .setSmallIcon(android.R.drawable.stat_notify_sync)
                    .setContentTitle("DSH 手机控制")
                    .setContentText("保持后台应答引擎")
                    .setOngoing(true)
                    .build();
        } else {
            n = new Notification.Builder(this)
                    .setSmallIcon(android.R.drawable.stat_notify_sync)
                    .setContentTitle("DSH 手机控制")
                    .setOngoing(true)
                    .build();
        }
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTIF_ID, n);
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}