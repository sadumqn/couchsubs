// SPDX-License-Identifier: AGPL-3.0-only
// Kendi ürünlerimizin tanıtımı (house ad): sitedeki promo.json'daki popup, günde en çok bir kez, yalnız boştaki ana
// ekranda. Reklam SDK'sı, reklam kimliği ya da izleme yok; yalnız görsel ve bağlantı. iPhone'daki Promo.swift ile birebir.
package com.couchsubs.mobile.promo

import org.json.JSONObject

/** promo.json'daki popup (biçim: site/public/promo.json). */
data class PromoPopup(
    val id: String,
    val active: Boolean,
    val image: String,
    val link: String,
    val alt: String,
    val everyHours: Int,
    val targets: Set<String>,
    /**
     * Uygulamayla gelen reklam (design/yeni-arayuz/reklamlar.json › popups[0]; promo.json indirilemezse). [image] o
     * zaman uygulamanın içindeki görselin adıdır (reklam/ altında), adres değil.
     */
    val bundled: Boolean = false,
)

/** Şu anki ekran: popup yalnız ana ekranda ve kullanıcı boştayken açılır. */
data class PromoMoment(
    /** Ana ekran en üstte (Ayarlar, Profil, eşleme, TV kurulumu gibi bir ekran açık değil). */
    val onHome: Boolean,
    /** Altyazı/çeviri oturumu çalışıyor ya da konsola bağlanılıyor. */
    val sessionActive: Boolean,
    val demo: Boolean,
    /** Karşılama ya da kurulum adımları sürüyor. */
    val onboarding: Boolean,
    /** Ana ekranın ilk açılış turu görünüyor. */
    val tour: Boolean,
    /** Uygulama ön plana geleli geçen süre: popup girişten [PromoPolicy.SHOW_DELAY_MS] sonra açılır. */
    val inAppMs: Long,
)

/** Son gösterim (popup kimliği başına; yeni kimlik hiç gösterilmemiş sayılır). */
data class PromoRecord(val id: String?, val shownAtMs: Long)

object PromoPolicy {
    const val PLATFORM = "android"
    const val DEFAULT_EVERY_HOURS = 24
    /** Uygulamaya girdikten bu kadar sonra (kullanıcı boştaysa) açılır. */
    const val SHOW_DELAY_MS = 10_000L
    /** promo.json ve görsel için üst sınırlar: yavaş ağda uygulamayı bekletmez, büyük dosya inmez. */
    const val TIMEOUT_MS = 5_000
    const val MAX_CONFIG_BYTES = 64 * 1024
    const val MAX_IMAGE_BYTES = 2 * 1024 * 1024
    /** Uygulama açık kaldıkça promo.json en çok bu kadar sıklıkla yeniden çekilir (soğuk açılışta her zaman). */
    const val REFETCH_MS = 24L * 60 * 60 * 1000

    /** promo.json'dan mobil popup ("popup"; sitenin "sitePopup" alanı okunmaz); yoksa ya da bozuksa null. */
    fun parse(json: String): PromoPopup? = try {
        val popup = JSONObject(json).optJSONObject("popup")
        popup?.let {
            val targets = it.optJSONArray("targets")
            PromoPopup(
                id = it.optString("id").trim(),
                active = it.optBoolean("active", false),
                image = it.optString("image").trim(),
                link = it.optString("link").trim(),
                alt = it.optString("alt").trim(),
                everyHours = it.optInt("everyHours", DEFAULT_EVERY_HOURS),
                targets = (0 until (targets?.length() ?: 0)).mapNotNull { i -> targets?.optString(i)?.trim()?.lowercase() }.toSet(),
            )
        }
    } catch (error: org.json.JSONException) {
        null
    }

    /**
     * Uygulamayla gelen açılır reklam (Mac ve Windows'un okuduğu reklamlar.json › popups[0]; iPhone ile aynı kural): görsel
     * adı boşsa ya da '/' içeriyorsa, bağlantı https değilse ya da kimlik yoksa null. Günde en çok bir kez, yalnız Android'de.
     */
    fun parseBundled(json: String): PromoPopup? = try {
        JSONObject(json).optJSONArray("popups")?.optJSONObject(0)?.let {
            val id = it.optString("id").trim()
            val image = it.optString("image").trim()
            val link = it.optString("link").trim()
            if (id.isEmpty() || image.isEmpty() || '/' in image || '\\' in image || !isHttps(link)) null
            else PromoPopup(id = id, active = true, image = image, link = link, alt = it.optString("alt").trim(),
                everyHours = DEFAULT_EVERY_HOURS, targets = setOf(PLATFORM), bundled = true)
        }
    } catch (error: org.json.JSONException) {
        null
    }

    /** Görsel ve bağlantı yalnız https (görsel) ve http/https (bağlantı); başka şema (intent:, javascript:) açılmaz. */
    fun isHttps(url: String) = url.startsWith("https://", ignoreCase = true) && url.length > "https://".length
    fun isWebLink(url: String) = isHttps(url) || (url.startsWith("http://", ignoreCase = true) && url.length > "http://".length)

    /** Popup açık, bu platform hedefte ve son gösterimden [PromoPopup.everyHours] saat geçtiyse true (ekrandan bağımsız). */
    fun due(popup: PromoPopup?, record: PromoRecord, nowMs: Long, platform: String = PLATFORM): Boolean {
        if (popup == null || !popup.active || popup.id.isEmpty()) return false
        if (platform !in popup.targets) return false
        // Uygulamayla gelen reklamın görseli adres değil, paketteki dosyanın adıdır.
        if ((!popup.bundled && !isHttps(popup.image)) || !isWebLink(popup.link)) return false
        if (record.id != popup.id) return true
        val hours = if (popup.everyHours > 0) popup.everyHours else DEFAULT_EVERY_HOURS
        // Saat geri alındıysa (gösterim gelecekte görünüyor) yeniden gösterilir; sonsuza dek susmaz.
        val elapsed = nowMs - record.shownAtMs
        return elapsed < 0 || elapsed >= hours * 60L * 60 * 1000
    }

    /** Popup'ın şu an açılabileceği an: girişten 10 sn sonra, yalnız ana ekranda, oturum, deneme, kurulum ve tur yokken. */
    fun idle(moment: PromoMoment) = moment.onHome && !moment.sessionActive && !moment.demo && !moment.onboarding &&
        !moment.tour && moment.inAppMs >= SHOW_DELAY_MS

    fun shouldShow(popup: PromoPopup?, record: PromoRecord, nowMs: Long, moment: PromoMoment, platform: String = PLATFORM) =
        idle(moment) && due(popup, record, nowMs, platform)
}
