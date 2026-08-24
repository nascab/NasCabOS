package com.nascabos.mobile

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.os.Build
import java.io.IOException
import java.net.Proxy
import java.net.ProxySelector
import java.net.SocketAddress
import java.net.URI

/**
 * 在应用启动时预创建音乐播放通知渠道，并强制迁移为静默渠道。
 * Android 8+ 的通知渠道一旦创建，重要级别和声音设置就不会被后续更新覆盖，
 * 因此这里会先删除旧渠道，再按静默配置重建。
 */
class NascabApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        // Media3(ExoPlayer) 等基于 HttpURLConnection 的原生请求默认跟随系统 Wi-Fi 代理；
        // 代理工具对流式视频 Range 响应处理异常（返回 500 或声明 gzip 却未压缩），
        // 会导致视频播放直接报错。这里统一禁用系统 HTTP 代理。
        // 影响范围：仅原生 HttpURLConnection 系请求；WebView 走 Chromium 独立代理栈、
        // Dio/dart:io 本就不读系统代理，均不受影响。
        ProxySelector.setDefault(
            object : ProxySelector() {
                override fun select(uri: URI?): List<Proxy> = listOf(Proxy.NO_PROXY)

                override fun connectFailed(uri: URI?, sa: SocketAddress?, ioe: IOException?) {}
            }
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager =
                getSystemService(Application.NOTIFICATION_SERVICE) as? NotificationManager
                    ?: return
            val channelId = "nascab.music.playback"
            val existing = notificationManager.getNotificationChannel(channelId)
            val needsMigration =
                existing == null ||
                    existing.importance != NotificationManager.IMPORTANCE_LOW ||
                    existing.shouldVibrate() ||
                    existing.sound != null
            if (!needsMigration) return
            if (existing != null) {
                notificationManager.deleteNotificationChannel(channelId)
            }
            val channel = NotificationChannel(
                channelId,
                "Music Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background music playback controls"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null as AudioAttributes?)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }
}
