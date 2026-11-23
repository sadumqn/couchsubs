// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.remoteplay

/**
 * Çeviri sürerken ana ekranda "Yeniden bağlan" düğmesi ne zaman görünür (Mac/iPhone: ReconnectOffer ile aynı kural).
 *
 * Konsol bağlantısı koparsa oturum kendiliğinden kademeli olarak yeniden bağlanır ([ReconnectPolicy]: 2, 4, 8 … en çok
 * 60 sn). Ama oturum yeniden denemeyi bırakabilir (görüntü hiç gelmiyor, PS5'te Uzaktan Oynatma çöktü, kayıt ya da giriş
 * şifresi geçersiz) ya da uzun süre bağlanamayabilir. Eskiden ekranda yalnız "yeniden bağlanılıyor" ya da "çeviriyi
 * yeniden başlatın" yazıyordu; kullanıcılar uygulamayı kapatıp açıyordu (TestFlight, iPhone: "çok kopuyor, sürekli
 * uygulamayı açıp kapatmak zorunda kalıyorum"). Düğme, bırakılan oturumda hemen, süren denemelerde [AFTER_MS] sonra görünür.
 */
class ReconnectOffer {
    companion object {
        /** Bu kadar süredir bağlı değilse (bağlanıyor ya da kopmuş) düğme görünür. */
        const val AFTER_MS = 45_000L

        /** [notLiveSince]: bağlantının gittiği an (ms; bağlıyken null). [gaveUp]: oturum yeniden denemeyi bıraktı. */
        fun shows(notLiveSince: Long?, gaveUp: Boolean, now: Long): Boolean =
            gaveUp || (notLiveSince != null && now - notLiveSince >= AFTER_MS)
    }

    /** Bağlantının gittiği an (ms); bağlıyken null. */
    var notLiveSince: Long? = null
        private set

    /** Oturum durumu değişti. [live]: görüntü akıyor. Ara durumlar (bağlanıyor ↔ koptu) süreyi baştan başlatmaz. */
    fun update(live: Boolean, now: Long) {
        if (live) notLiveSince = null else if (notLiveSince == null) notLiveSince = now
    }

    /** Çeviri durdu ya da yeni oturum açıldı: süre [now]'dan (null: hiç) sayılır. */
    fun reset(now: Long? = null) {
        notLiveSince = now
    }

    fun shows(gaveUp: Boolean, now: Long): Boolean = shows(notLiveSince, gaveUp, now)
}
