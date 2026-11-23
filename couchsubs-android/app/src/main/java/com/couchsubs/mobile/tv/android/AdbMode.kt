// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv.android

/**
 * Android TV kurulumunda hangi bağlantı yolunun seçileceği (iPhone'daki AdbMode ile aynı kural, GitHub #478).
 *
 * Yeni Android TV ve Google TV'lerde eski ADB portu 5555 kapalıdır; bunlara yalnız "Kablosuz hata ayıklama" (eşleme kodu
 * ve her açılışta değişen port) ile bağlanılır. Eskiden ekran hep "USB/ağ hata ayıklama" sekmesinde açılıyor, 5555'e
 * bağlanılamayınca yalnız küçük bir notta "kablosuz hata ayıklama ayrı port kullanır" yazıyordu; kullanıcılar fark etmiyordu.
 */
object AdbMode {
    /** Seçilen TV'de 5555 açık değilse kablosuz hata ayıklama sekmesi seçilir. */
    fun prefersWireless(legacyAdbReachable: Boolean): Boolean = !legacyAdbReachable

    /** Ağ hata ayıklamasıyla (5555) TV'ye bağlanılamadı: belirgin "Kablosuz hata ayıklamayla dene" düğmesi gösterilir. */
    fun offersWireless(wireless: Boolean, error: AndroidInstallError?): Boolean =
        !wireless && error == AndroidInstallError.UNREACHABLE

    /** Kablosuz sekmeye geçerken adresteki port bırakılır (kablosuz hata ayıklamanın portu farklıdır, TV'den yazılır). */
    fun hostOnly(address: String): String {
        val trimmed = address.trim()
        val colon = trimmed.lastIndexOf(':')
        if (colon <= 0 || trimmed.count { it == ':' } != 1) return trimmed
        return if (trimmed.substring(colon + 1).all { it.isDigit() }) trimmed.substring(0, colon) else trimmed
    }
}
