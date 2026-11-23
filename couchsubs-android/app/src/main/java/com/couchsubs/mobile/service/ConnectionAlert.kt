// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.service

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.couchsubs.mobile.R
import com.couchsubs.mobile.remoteplay.DisconnectKind
import com.couchsubs.mobile.ui.MainActivity

/**
 * "PS5 bağlantısı koptuğunda bildir" (Profil): görüntü gelirken bağlantı kendiliğinden koparsa ve uygulama ekranda
 * değilse bildirim gösterilir; bağlantı geri gelince kalkar (iPhone ConnectionAlert ile aynı kural ve metin). Eskiden
 * Android'de anahtar vardı ama hiçbir şey onu okumuyordu.
 */
object ConnectionAlert {
    private const val CHANNEL = "connection"
    private const val ID = 2

    /** Bildirim gösterilsin mi: akış sürüyordu, kullanıcı durdurmadı, deneme modu değil, tercih açık, uygulama ekranda değil. */
    fun shouldPost(wasStreaming: Boolean, kind: DisconnectKind?, demo: Boolean, enabled: Boolean, appVisible: Boolean): Boolean =
        wasStreaming && kind != null && kind != DisconnectKind.STOPPED && !demo && enabled && !appVisible

    /** Uygulamanın bir ekranı şu an görünüyor mu (ön plan hizmeti tek başına görünür sayılmaz). */
    fun appVisible(): Boolean {
        val state = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(state)
        return state.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
    }

    fun post(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(NotificationChannel(CHANNEL, context.getString(R.string.channel_connection),
            NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(context, 2, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.connection_lost_title))
            .setContentText(context.getString(R.string.connection_lost_body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { manager.notify(ID, notification) }
    }

    fun cancel(context: Context) {
        context.getSystemService(NotificationManager::class.java)?.cancel(ID)
    }
}
