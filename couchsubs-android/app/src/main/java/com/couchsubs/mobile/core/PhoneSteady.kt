// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.abs

/**
 * Otomatik telefon okumasında çevirinin kararlılığı. Aynı mesajın OCR'la bir iki harfi farklı okunuşu yeni mesaj
 * sayılıyor, balon bir an özgün diline dönüp yeniden çevriliyor, çeviri her seferinde biraz değişiyordu; telefon tek
 * karede bulunamayınca da bütün çeviriler silinip geri geliyordu ("sürekli git gel yapıyor", X'teki bildirim). Mac/iPhone
 * (PhoneSteady.swift) ve Windows (PhoneSteady.cs) aynı eşikleri kullanır.
 */
object PhoneSteady {
    /** Okuma art arda bu kadar turda doğrulanamazsa çeviriler silinir. */
    const val MISS_TURNS = 3
    /** Tek turluk OCR sapması (düşen balon, yan yana bozuk harfler) en çok bu kadar tur bekletilir. */
    const val HOLD_TURNS = 2
    /** Aynı mesaj sayılmak için sadeleştirilmiş iki okumanın benzerliği (Levenshtein oranı) en az bu. */
    const val SAME_MESSAGE = 0.9
    /** Kısa satırda bir harf anlamı değiştirir ("Ok" / "On"): benzer okuma yalnız bu kadar harften uzun mesajda kullanılır. */
    const val MINIMUM_LETTERS = 8

    /**
     * Mesajın bilinen çevirisi: birebir aynı okunuşunki, yoksa aynı mesajın OCR'la biraz farklı okunuşununki. Sayı ya da
     * olumsuzluk ekleyen/düşüren okuma ("at 5" / "at 6", "can" / "can't") aynı mesaj sayılmaz. Birden çok aday varsa
     * uzunluğu en yakın olan, eşitlikte sıralamada önce gelen (her platformda aynı sonuç).
     */
    fun translation(source: String, known: Map<String, String>): String? {
        known[source]?.let { return it }
        val text = TextMatch.normalize(source)
        var bestDistance = Int.MAX_VALUE
        var bestSource: String? = null
        var best: String? = null
        for ((old, translation) in known) {
            if (!sameReading(source, old)) continue
            val distance = abs(text.length - TextMatch.normalize(old).length)
            if (distance < bestDistance || (distance == bestDistance && old < bestSource!!)) {
                bestDistance = distance
                bestSource = old
                best = translation
            }
        }
        return best
    }

    /**
     * İki okuma aynı mesaj mı: birebir aynı, sadeleştirilmiş hali aynı (soru işareti ikisinde de ya da hiçbirinde; "Ok." /
     * "ok" kısa satırda da aynı mesaj) ya da (en az [MINIMUM_LETTERS] harfli iki uzun mesajda, "rn" / "m" birleştirilerek)
     * Levenshtein oranı en az [SAME_MESSAGE]; sayı ya da olumsuzluk ekleyen/düşüren okuma aynı sayılmaz (Mac ile aynı).
     */
    fun sameReading(a: String, b: String): Boolean {
        if (a == b) return true
        val x = TextMatch.normalize(a)
        val y = TextMatch.normalize(b)
        if (x.isEmpty() || y.isEmpty() || TextMatch.addsMeaning(a, b) || TextMatch.addsMeaning(b, a)) return false
        if (x == y) return a.contains('?') == b.contains('?')
        return x.count { it.isLetter() } >= MINIMUM_LETTERS && y.count { it.isLetter() } >= MINIMUM_LETTERS &&
            TextMatch.isSimilar(x.replace("rn", "m"), y.replace("rn", "m"), SAME_MESSAGE)
    }

    // Ekrandaki balonların kararlılığı (X, 22 Kas, GTA 6 telefonu: "yazılar sürekli oynuyor okumak çok zor, balonların
    // içinde de aynı hata var"). Her OCR turunda balon kutuları birkaç piksel oynuyor, telefonun bulunan yeri titriyordu;
    // her turda yeni kutular gönderiliyor, TV paneli ve balonları yeniden diziyordu. Mac/iPhone ve Windows aynı kural.

    /** Aynı balonun yeri, satır yüksekliğinin bu payından az oynadıysa son çizilen yerde kalır (histerezis). */
    const val POSITION_SHARE = 0.25
    /** Yanda Panel'in dayandığı telefon yeri, kutusunun her kenarı bu kadardan (kareye oranla) az oynadıysa sabit kalır. */
    const val POSE_SLACK = 0.015

    /**
     * Balonların yeri: önceki gönderiyle eşleşen balonlar ([match]) küçük oynamada (satır yüksekliğinin [POSITION_SHARE]'i;
     * yatayda kare oranıyla) son çizilen yerde kalır. Eşleşenlerin yarısından çoğu eşiği aşarsa (telefon kıpırdadı, sohbet
     * kaydı) hepsi birlikte, tek seferde yeni yerine geçer; tek başına eşiği aşan balon kendi yerine geçer. Boyu değişmeyen
     * balonun kutusu birebir öncekidir. [aspect]: karenin eni / boyu.
     */
    fun steadyPositions(items: List<ScreenTranslation.Item>, previous: List<ScreenTranslation.Item>,
                        aspect: Double): List<ScreenTranslation.Item> {
        val ratio = maxOf(0.1, aspect)
        fun still(box: TextBox, old: ScreenTranslation.Item): Boolean {
            val limit = POSITION_SHARE * old.lineHeight
            return abs(box.top - old.box.top) <= limit && abs(box.left - old.box.left) <= limit / ratio
        }
        val pairs = items.mapIndexedNotNull { index, item -> match(item, previous)?.let { index to it } }
        val moved = pairs.count { (index, old) -> !still(items[index].box, old) }
        if (pairs.isEmpty() || 2 * moved > pairs.size) return items
        val result = items.toMutableList()
        for ((index, old) in pairs) {
            val box = items[index].box
            if (!still(box, old)) continue
            val width = box.right - box.left
            val height = box.bottom - box.top
            val oldWidth = old.box.right - old.box.left
            val oldHeight = old.box.bottom - old.box.top
            result[index] = items[index].copy(box = TextBox(old.box.left, old.box.top,
                if (abs(width - oldWidth) < 1e-9) old.box.right else minOf(1.0, old.box.left + width),
                if (abs(height - oldHeight) < 1e-9) old.box.bottom else minOf(1.0, old.box.top + height)))
        }
        return result
    }

    /** İki yazı rengi zeminin aynı yanında mı (ikisi de zeminden koyu ya da ikisi de açık; algılanan parlaklıkla). */
    fun sameInk(a: String, b: String, background: String): Boolean {
        fun brightness(hex: String): Int? {
            if (hex.length != 7 || !hex.startsWith("#")) return null
            val value = hex.substring(1).toIntOrNull(16) ?: return null
            return (((value shr 16) and 0xFF) * 299 + ((value shr 8) and 0xFF) * 587 + (value and 0xFF) * 114) / 1000
        }
        val x = brightness(a) ?: return false
        val y = brightness(b) ?: return false
        val z = brightness(background) ?: return false
        return (x < z) == (y < z)
    }

    /** Önceki gönderide bu balonun eşi: aynı çeviri ve parça, aynı okuma ([sameReading]), sol üst köşesi 0,05 içinde; aynı yerde iki eş varsa null. */
    fun match(item: ScreenTranslation.Item, previous: List<ScreenTranslation.Item>): ScreenTranslation.Item? {
        var found: ScreenTranslation.Item? = null
        for (old in previous) {
            if (old.translation != item.translation || old.panel != item.panel || abs(old.box.left - item.box.left) > 0.05 ||
                abs(old.box.top - item.box.top) > 0.05 || !sameReading(old.source, item.source)) continue
            if (found != null) return null
            found = old
        }
        return found
    }

    /** Yanda Panel'in dayandığı telefon: yeni yerin kutusu öncekinden her kenarda [POSE_SLACK]'ten az oynadıysa önceki yer. */
    fun steadyPose(pose: GamePhoneGeometry.Pose, anchor: GamePhoneGeometry.Pose?): GamePhoneGeometry.Pose {
        if (anchor == null) return pose
        val a = pose.bounds
        val b = anchor.bounds
        val still = abs(a.left - b.left) <= POSE_SLACK && abs(a.right - b.right) <= POSE_SLACK &&
            abs(a.top - b.top) <= POSE_SLACK && abs(a.bottom - b.bottom) <= POSE_SLACK
        return if (still) anchor else pose
    }

    /**
     * İki gönderi TV'de ve ekranda aynı görünür mü. Panelin mesajları, kişi adı ve notları akışla çizilir: yalnız sırası,
     * yazısı ve rengi önemlidir; panelin zemini ve panel dışındaki her öğe yeriyle aynı olmalıdır.
     */
    fun samePicture(a: List<ScreenTranslation.Item>, b: List<ScreenTranslation.Item>): Boolean {
        if (a.size != b.size) return false
        return a.zip(b).all { (x, y) ->
            x.panel == y.panel && x.translation == y.translation && x.surface == y.surface && x.look == y.look &&
                x.icons == y.icons && x.bubble == y.bubble && x.lineHeight == y.lineHeight &&
                ((x.panel != null && x.panel != ScreenPhoneCard.PanelPart.CARD) || x.box == y.box)
        }
    }
}
