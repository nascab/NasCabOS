package com.nascabos.mobile

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.os.Build

/**
 * 在应用启动时预创建音乐播放通知渠道，并强制迁移为静默渠道。
 * Android 8+ 的通知渠道一旦创建，重要级别和声音设置就不会被后续更新覆盖，
 * 因此这里会先删除旧渠道，再按静默配置重建。
 */
class NascabApplication : Application() {

    override fun onCreate() {
        super.onCreate()
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
