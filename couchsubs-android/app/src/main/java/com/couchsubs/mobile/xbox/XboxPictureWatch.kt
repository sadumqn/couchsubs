// SPDX-License-Identifier: AGPL-3.0-only
// İlk kareden sonra Xbox görüntüsünün kesilip kesilmediği (PS5'teki PictureWatchdog'un Xbox karşılığı). Eskiden yayın
// yalnız WebRTC bağlantısı FAILED/CLOSED olunca ya da input kanalı kapanınca bitiyordu: ICE DISCONNECTED'da takılı
// kalan ya da kare göndermeyi bırakan yayında ana ekran "bağlı" diyor, altyazı donuyor ve bir daha gelmiyordu (X'te
// kullanıcı bildirimi, iPhone + Xbox Series S). Kare [WARN_AFTER_MS] gelmezse (ICE DISCONNECTED iken 1 sn) uyarı
// gösterilir; [STALL_AFTER_MS] gelmezse ya da ICE FAILED olursa oturum kapatılıp XboxSessionMachine'in aralıklarıyla
// (bir kez, 5 sn sonra) yeniden kurulur. İlk kareden sonraki [STARTUP_GRACE_MS] içinde yalnız ICE FAILED oturumu
// kapatır: yayının başında Xbox görüntüyü birkaç saniye bekletebiliyor (yükleme, "uzaktan yürütme başlatıldı"
// bildirimi); eskiden bu boşlukta oturum kapatılıp yeniden açılıyor, Xbox'ta başladı/durdu döngüsü oluyordu (Play,
// Android beta.85). CouchSubsCore XboxPictureWatch (iPhone, Mac) ve Windows'taki CouchSubs.Shell/XboxPictureWatch ile birebir.
package com.couchsubs.mobile.xbox

/** Görüntü bekçisinin bir saat adımındaki kararı. */
sealed class XboxPictureVerdict {
    data object Fine : XboxPictureVerdict()
    /** Görüntü kesildi ya da ICE takıldı: ana ekranda "bağlı" yerine uyarı (bir kez). */
    data object Warn : XboxPictureVerdict()
    /** Uyarıdan sonra görüntü yeniden geliyor. */
    data object Recovered : XboxPictureVerdict()
    /** Oturum kapatılıp yeniden kurulmalı; [reason] günlükteki neden. */
    data class Stalled(val reason: String) : XboxPictureVerdict()
}

class XboxPictureWatch {
    companion object {
        const val WARN_AFTER_MS = 5000L
        const val STALL_AFTER_MS = 12_000L
        /** ICE DISCONNECTED iken uyarı için yeterli boşluk (bağlantı takılınca kareler hemen kesilir). */
        const val ICE_WARN_AFTER_MS = 1000L
        /** İlk kareden sonra bu süre içinde kare boşluğu oturumu kapatmaz (yalnız uyarı); ICE FAILED yine kapatır. */
        const val STARTUP_GRACE_MS = 30_000L
    }

    /** IceConnectionState'in bekçiyi ilgilendiren kısmı. */
    enum class Ice { CONNECTED, DISCONNECTED, FAILED, OTHER }

    private var firstFrameMs: Long? = null
    private var lastFrameMs: Long? = null
    private var iceLostSinceMs: Long? = null
    private var iceFailed = false
    /** Uyarı gösteriliyor. */
    var warned = false
        private set

    @Synchronized fun frameArrived(atMs: Long) {
        if (firstFrameMs == null) firstFrameMs = atMs
        lastFrameMs = atMs
    }

    /**
     * Görüntü akıyor mu: son kare [WARN_AFTER_MS]'den yeni. Akan yayın canlı tutma hatasıyla kapatılmaz (bkz.
     * [XboxKeepalive.shouldEnd]).
     */
    @Synchronized fun isFlowing(atMs: Long): Boolean = lastFrameMs?.let { atMs - it < WARN_AFTER_MS } == true

    @Synchronized fun iceChanged(state: Ice, atMs: Long) {
        when (state) {
            Ice.CONNECTED -> iceLostSinceMs = null
            Ice.DISCONNECTED -> if (iceLostSinceMs == null) iceLostSinceMs = atMs
            Ice.FAILED -> iceFailed = true
            Ice.OTHER -> {}
        }
    }

    /** Saniyede bir çağrılır. İlk kare gelmeden karar verilmez (ilk kare sınırı ayrı). */
    @Synchronized fun tick(atMs: Long): XboxPictureVerdict {
        val last = lastFrameMs ?: return XboxPictureVerdict.Fine
        val iceLost = iceLostSinceMs != null
        if (iceFailed) return XboxPictureVerdict.Stalled("Xbox ICE bağlantısı koptu (failed)")
        val gap = atMs - last
        val starting = firstFrameMs?.let { atMs - it < STARTUP_GRACE_MS } == true
        if (gap >= STALL_AFTER_MS && !starting) {
            return XboxPictureVerdict.Stalled("Xbox'tan ${gap / 1000} sn'dir görüntü gelmiyor (${if (iceLost) "ICE disconnected" else "bağlantı açık görünüyor"})")
        }
        val trouble = gap >= WARN_AFTER_MS || (iceLost && gap >= ICE_WARN_AFTER_MS)
        if (trouble && !warned) {
            warned = true
            return XboxPictureVerdict.Warn
        }
        if (!trouble && warned) {
            warned = false
            return XboxPictureVerdict.Recovered
        }
        return XboxPictureVerdict.Fine
    }
}
