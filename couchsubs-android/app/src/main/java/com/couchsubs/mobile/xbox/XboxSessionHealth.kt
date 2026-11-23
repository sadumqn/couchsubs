// SPDX-License-Identifier: AGPL-3.0-only
// Xbox yayınının sağlamlığı: canlı tutma sayacı, bağlantının kurulma süresi ve kapanma nedeni. Kurallar iPhone/Mac'teki
// CouchSubsCore XboxSessionHealth.swift ve Windows'taki CouchSubs.Shell/XboxSessionHealth.cs ile birebir.
package com.couchsubs.mobile.xbox

/**
 * Canlı tutma isteği (30 sn'de bir). Tek başarısız istek yayını bitirmez; yalnız [MAX_FAILURES] ardışık hata (yaklaşık
 * 90 sn yanıt yok) bitirir, arada başarılı bir istek sayacı sıfırlar. Eskiden telefonda hata yalnız günlüğe yazılıyor,
 * Xbox oturumu kapatsa da yayın açık sanılıyordu.
 */
class XboxKeepalive {
    companion object {
        const val INTERVAL_MS = 30_000L
        const val MAX_FAILURES = 3

        /** Yanıt oturumun Xbox hizmetinde artık olmadığını söylüyor (HTTP 404/410): beklenmez, oturum biter. */
        fun sessionGone(message: String?): Boolean = message.orEmpty().let { it.contains("HTTP 404") || it.contains("HTTP 410") }

        /**
         * Başarısız canlı tutma isteğinden sonra yayın bitirilmeli mi. Görüntü akarken ([pictureFlowing]) hayır: Xbox
         * yayını sürdürüyor, canlı tutma yanıtı (404 dahil) yanıltıcı olabiliyor. Android beta.85'te 404 ya da üç hata
         * görüntü akarken de yayını kapatıyordu; ilk istek bağlantıdan 30 sn sonra gittiği için Xbox'ta "uzaktan yürütme
         * başlatıldı / durduruldu" döngüsü oluyordu (beta.65'te hata yalnız günlüğe yazılıyordu). Görüntü durmuşsa
         * eskisi gibi: oturum Xbox hizmetinde yoksa ([gone]) ya da hatalar [MAX_FAILURES]'a vardıysa ([exhausted]) biter.
         */
        fun shouldEnd(gone: Boolean, exhausted: Boolean, pictureFlowing: Boolean): Boolean = !pictureFlowing && (gone || exhausted)
    }

    var failures = 0
        private set

    fun succeeded() {
        failures = 0
    }

    /** Oturum bitirilmeli mi. */
    fun failed(): Boolean = ++failures >= MAX_FAILURES
}

/** Bir bağlantının neden bittiği: günlükte açıkça yazılır, yeniden bağlanırken ekrandaki kısa metni seçer. */
enum class XboxEndCause(val text: String) {
    /** Xbox (ya da Xbox hizmeti) yayını kapattı: görüntü kanalı karşı taraftan kapandı, oturum bulunamadı, yayın reddedildi. */
    SERVER("sunucu kapattı"),
    /** Beklenen yanıt ya da görüntü süresinde gelmedi. */
    TIMEOUT("zaman aşımı"),
    /** Ağ bağlantısı koptu ya da kurulamadı (ICE, Wi-Fi, internet). */
    NETWORK("ağ");

    companion object {
        fun of(kind: XboxError): XboxEndCause = when (kind) {
            XboxError.TIMEOUT, XboxError.NO_FIRST_FRAME -> TIMEOUT
            XboxError.NETWORK, XboxError.NO_PICTURE -> NETWORK
            else -> SERVER
        }

        /** Günlük satırı, ör. `kapanma nedeni: ağ (Xbox ICE bağlantısı koptu (failed))`. */
        fun line(kind: XboxError, detail: String?): String =
            "kapanma nedeni: ${of(kind).text} (${XboxSessionMachine.shortReason(detail, "?")})"
    }
}

/**
 * ICE adayları değişildikten sonra görüntü kanalı (input) bu sürede açılmazsa bağlantı zaman aşımıyla kapatılır. İlk
 * kare sınırı ([XboxFirstFrameWatch.FIRST_FRAME_LIMIT_MS]) kanal açılınca başlar: Wi-Fi'daki yavaş ICE kurulumu ilk kare
 * süresinden yemez.
 */
object XboxConnectWatch {
    const val CONNECT_LIMIT_MS = 30_000L
}
