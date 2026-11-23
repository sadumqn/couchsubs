// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.packs

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.couchsubs.mobile.R
import com.couchsubs.mobile.ui.MainActivity

/**
 * "Yeni bir paket geldiğinde" (Profil): arka plandaki paket yenilemesinde yeni ya da güncellenen oyun paketi inince
 * bildirim gösterilir (iPhone PackNotice ile aynı kural). Uygulamanın ilk paket indirmesi bildirilmez; uygulama ekrandayken
 * ("Paketleri şimdi güncelle" sonucu zaten görünür) bildirim çıkmaz. Eskiden anahtar vardı ama hiçbir şey okumuyordu.
 */
object PackNotice {
    private const val CHANNEL = "packs"
    private const val ID = 3
    /** Bildirimde en çok bu kadar paket adı yazılır; fazlası "+N". */
    const val MAX_TITLES = 3

    fun shouldNotify(enabled: Boolean, firstCheck: Boolean, downloaded: Int, appVisible: Boolean): Boolean =
        enabled && !firstCheck && downloaded > 0 && !appVisible

    /** "GTA 6, Mafia, RDR 2 +2" */
    fun titles(titles: List<String>): String {
        val shown = titles.take(MAX_TITLES).joinToString(", ")
        return if (titles.size > MAX_TITLES) "$shown +${titles.size - MAX_TITLES}" else shown
    }

    fun post(context: Context, titles: List<String>) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(NotificationChannel(CHANNEL, context.getString(R.string.channel_packs), NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(context, 3, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.packs_notice_title))
            .setContentText(context.getString(R.string.packs_notice_body, titles(titles)))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { manager.notify(ID, notification) }
    }
}
