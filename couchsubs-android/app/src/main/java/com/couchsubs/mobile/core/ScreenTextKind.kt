// SPDX-License-Identifier: AGPL-3.0-only

package com.couchsubs.mobile.core

/**
 * Otomatik ekran yazısının türleri; Ayarlar'da her biri ayrı açılıp kapanır (kullanıcı isteği, X: "telefon, eylemler
 * çevirisini kullanmak istiyorum, menülerde olmasını istemiyorum"). Sıra ve adlar dört platformda aynıdır (Mac/iPhone:
 * ScreenTextKind.swift, Windows: ScreenTextKind.cs). "Ekranı çevir" (elle) türlerden etkilenmez, her şeyi çevirir.
 */
enum class ScreenTextKind {
    /** GTA 6 telefonu (telefon okuyucusu) ve hazır mesaj kartı alanı. */
    PHONE,
    /**
     * Görev ve hedef yazısı (altyazıdan ayrılan görev satırı, [MissionLine]) ve haritada basılan görevin/konumun bilgi
     * kartı ([MissionCard]; menüde açılsa da bu türdendir, ayrı anahtarı yoktur).
     */
    MISSION,
    /** Yardım ve ipucu kutuları, eylemler: tuş ipuçları, etkileşim istemleri; hazır yardım kutusu alanı. */
    HELP,
    /** Menüler (duraklatma, harita, ayarlar): bulucunun menü durumunda bulduğu alanlar. */
    MENU,
    /** Diğer ekran yazıları (kısa başlık, yer adı, bildirim). */
    OTHER;

    companion object {
        /**
         * Pas turunda alan okunur mu: türü açık ya da yerinden belli değil. Menüler kapalıyken de kart boyundaki menü
         * alanı (en çok [MissionCard.MAX_WIDTH] genişlik, ekranın yarısı yükseklik) "Görev ve hedef yazısı" açıksa okunur:
         * haritada açılan görev kartı menü sayılan ekranda durur; kart değilse çizilmez (bkz. [RegionWatcher.kind]).
         */
        fun reads(area: ExtraArea, allows: (ScreenTextKind) -> Boolean): Boolean {
            val kind = of(area) ?: return true
            if (allows(kind)) return true
            val region = area.region
            return kind == MENU && allows(MISSION) &&
                region.right - region.left <= MissionCard.MAX_WIDTH && region.bottom - region.top <= 0.5
        }

        /** Kısa etiketten uzun sayılan yazı (yardım kutusu cümlesi) en az bu kadar sözcük. */
        const val HELP_WORDS = 8

        /**
         * Alanın türü yerinden belli mi: hazır alanlar, görev satırı ve menü alanları. Kullanıcının kendi ek alanı null
         * (her zaman okunur); menü dışındaki otomatik alanın türü okunan yazıdan çıkar ([ofParagraphs]).
         */
        fun of(area: ExtraArea): ScreenTextKind? = when (area.id) {
            GameAreaPresets.PHONE_ID -> PHONE
            GameAreaPresets.HELP_ID -> HELP
            MissionLine.AREA_ID -> MISSION
            else -> if (area.auto && area.menu) MENU else null
        }

        /**
         * Menü dışındaki otomatik alanın türü: tuş simgesi ya da tuş ipucu ("Press ✕ to jump", "R2 Aim") taşıyan, birden
         * çok parçalı ya da uzun (en az [HELP_WORDS] sözcük) yazı yardım/eylemdir; noktalama ile biten kısa tek cümle
         * görevdir; kısa tek satır (yer adı, başlık) diğerdir.
         */
        fun ofParagraphs(paragraphs: List<String>): ScreenTextKind {
            if (paragraphs.any { it.contains(ButtonIcons.MARKER) || ButtonPrompts.isPrompt(IconText.plain(it)) }) return HELP
            val words = paragraphs.sumOf { p -> IconText.plain(p).split(Regex("\\s+")).count { it.isNotEmpty() } }
            if (paragraphs.size >= 2 || words >= HELP_WORDS) return HELP
            // Tek, en az iki sözcüklü, noktalama ile biten cümle görev/hedef yazısıdır ("Follow Paulie to the car.").
            val sentence = paragraphs.singleOrNull()?.let { IconText.plain(it).trim().trim('"', '\'', '“', '”', '‘', '’', ' ') }
            if (sentence != null && words >= 2 && sentence.lastOrNull() in setOf('.', '!', '?')) return MISSION
            return OTHER
        }
    }
}

/**
 * Otomatik ekran yazısında hangi türler çevrilir; yalnız "Ekran yazılarını otomatik çevir" açıkken geçerli. Eski
 * kurulumda kayıt yoktur, varsayılanla gelir: telefon, görev, yardım/eylemler açık; menüler ve diğerleri kapalı.
 */
data class ScreenTextKinds(
    val phone: Boolean = true,
    val mission: Boolean = true,
    val help: Boolean = true,
    val menus: Boolean = false,
    val other: Boolean = false,
) {
    /** Bu tür çevrilir mi. Ana ayar kapalıyken türler uygulanmaz (hazır alanlar ve telefon kendi ayarlarıyla çalışır). */
    fun allows(autoScreenText: Boolean, kind: ScreenTextKind): Boolean = !autoScreenText || when (kind) {
        ScreenTextKind.PHONE -> phone
        ScreenTextKind.MISSION -> mission
        ScreenTextKind.HELP -> help
        ScreenTextKind.MENU -> menus
        ScreenTextKind.OTHER -> other
    }

    /** GTA 6 telefonu okunur mu: kendi ayarı ya da otomatik ekran yazısında Telefon türü açık (Mac: readsGamePhone). */
    fun readsGamePhone(autoReadGamePhone: Boolean, autoScreenText: Boolean): Boolean = autoReadGamePhone || (autoScreenText && phone)
}
