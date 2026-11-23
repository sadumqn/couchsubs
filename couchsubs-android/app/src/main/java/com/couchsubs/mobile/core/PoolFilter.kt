// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.text.Normalizer
import java.util.Locale

/**
 * Ortak havuza gidecek satırın süzgeci: havuz yalnız pakette olmayan İngilizce oyun konuşmalarını toplamalı. Sunucudaki
 * havuzda (Kasım 2026) en çok görülen "satırlar" PS5'in Türkçe arayüzü ve onun yazı tanıma bozmaları ("Oturum Açtı",
 * "Oturum Aqtl", "Sifirlama Seqenekleri"), yarım okumalar ("GO to the", "it Auto V's Story Mode.") ve oyun arayüzü
 * ("PHOTO MODE SELECT") idi. Mac/iPhone'daki PoolFilter.swift, Windows'taki PoolFilter.cs ve sunucudaki
 * server/pool/src/filter.js ile aynı kurallar.
 */
object PoolFilter {
    /** Bundan kısa ya da daha az sözcüklü satır ancak cümle noktalamasıyla bitiyorsa alınır ("Get down!"). */
    const val MIN_SHORT_LENGTH = 15
    const val MIN_SHORT_WORDS = 3
    /** Tümü büyük harfli, noktalamasız ve bu kadar ya da daha az sözcüklü satır arayüz yazısıdır ("FREE MONTH OF GTA+"). */
    const val MAX_CAPS_UI_WORDS = 6

    /** Satır İngilizce oyun konuşmasına benziyor mu (Türkçe, sistem yazısı ya da yarım okuma değil). */
    fun accepts(text: String): Boolean = !isFragment(text) && !looksTurkish(text) && !looksLikeSystemText(text)

    /** Sonu bu sözcükle biten (noktalamasız) satır cümlenin ortasında kesilmiştir ("Take out the"). */
    private val danglingWords = setOf(
        "the", "a", "an", "to", "of", "and", "or", "but", "with", "for", "from", "my", "your", "his", "her", "their", "our",
        "at", "in", "on", "by", "into", "than", "that", "if", "as", "is", "are", "was", "were",
    )

    /**
     * Yarım ya da arayüz okuması: kısa ve noktalamasız, küçük harfle başlayan ("it Auto V's Story Mode."), bağlaçla ya da
     * tanımlıkla biten, ya da tümü büyük harfli kısa ve noktalamasız ("PHOTO MODE SELECT").
     */
    fun isFragment(raw: String): Boolean {
        val text = raw.trim()
        val words = text.split(Regex("\\s+")).filter { word -> word.any { it.isLetter() } }
        val ends = SubtitleStabilizer.endsSentence(text)
        if (!ends && (words.size < MIN_SHORT_WORDS || text.length < MIN_SHORT_LENGTH)) return true
        val first = text.firstOrNull()
        if (first != null && first.isLetter() && first.isLowerCase()) return true
        if (ends) return false
        words.lastOrNull()?.let { last ->
            if (last.lowercase(Locale.ROOT).filter { it.isLetter() } in danglingWords) return true
        }
        val letters = text.filter { it.isLetter() }
        return letters.isNotEmpty() && letters.none { it.isLowerCase() } && words.size <= MAX_CAPS_UI_WORDS
    }

    /** Yalnız Türkçede (ve yakın dillerde) geçen harfler. */
    private val turkishOnly = setOf('ğ', 'Ğ', 'ş', 'Ş', 'ı', 'İ')
    /** Türkçede sık, İngilizce oyun metninde yalnız yabancı adlarda ("Müller", "façade") geçen harfler. */
    private val turkishShared = setOf('ü', 'Ü', 'ö', 'Ö', 'ç', 'Ç')

    /** PS5'in Türkçe arayüzünde sık geçen, İngilizcede olmayan sözcükler ("ile" yok: katlanınca İngilizce "lie" olur). */
    internal val turkishWords = listOf(
        "icin", "lutfen", "bekleyin", "oyunu", "oyun", "oyunlar", "kapat", "ekran", "ekranda", "ekrani", "sistemini",
        "yeniden", "baslat", "ayarlar", "ayarlari", "kupalar", "kupa", "oturum", "acti", "kapatti", "secenekleri",
        "sifirlama", "tut", "kesfet", "ilgili", "takip", "edin", "ilerlemenizi", "cikanlar", "goruntusu", "kaydedildi",
        "bildirimler", "arkadaslar", "medya", "galerisi", "indiriliyor", "guncelleme", "kitaplik", "denetleyici",
    ).map { fold(it).joinToString("") }

    /**
     * Türkçe görünen satır: Türkçeye özgü harf (ğ, ş, ı, İ), iki ve daha çok ü/ö/ç ("Ekran görüntüsü"), ya da harfleri
     * yazı tanımada bozulmuş Türkçe arayüz sözcüklerinden en az ikisi ("Sifirlama Seqenekleri", "Oturum Aqtl").
     */
    fun looksTurkish(text: String): Boolean {
        if (text.any { it in turkishOnly }) return true
        if (text.count { it in turkishShared } >= 2) return true
        return fold(text).count { word -> turkishWords.any { isClose(word, it) } } >= 2
    }

    /** PS5'in kendi bildirim ve arayüz yazıları (İngilizce ve Türkçe); katlanmış satırda tam sözcük olarak aranır. */
    private val systemPhrases = listOf(
        "signed in", "signed out", "earned a trophy", "trophy earned", "trophy unlocked", "screenshot saved",
        "video clip saved", "media gallery", "is now online", "joined the party", "left the party", "remote play",
        "controller battery", "controller is disconnected", "controller disconnected", "press the ps button",
        "playstation network", "download complete", "installation complete", "update available", "turn off your console",
        "cloud save", "do not quit", "photo mode", "story mode", "press any button",
        "oturum acti", "oturum kapatti", "ekran ve video", "oyunu kapat", "ana ekranda tut", "yeniden baslat",
        "sifirlama secenekleri", "lutfen bekleyin", "ilerlemenizi takip",
    ).map { fold(it).joinToString(" ") }

    fun looksLikeSystemText(text: String): Boolean {
        val padded = " " + fold(text).joinToString(" ") + " "
        return systemPhrases.any { padded.contains(" $it ") }
    }

    /**
     * Karşılaştırma için sadeleştirilmiş sözcükler: küçük harf, aksansız (ç→c, ş→s, ğ→g, ö→o, ü→u, ı/İ→i) ve yazı
     * tanımanın sık karıştırdığı harfler birleşik (q→c, l ve 1→i). Yalnız eşleştirme içindir.
     */
    internal fun fold(text: String): List<String> {
        val lower = text.lowercase(Locale.ROOT).replace("ı", "i")
        val plain = Normalizer.normalize(lower, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")
        val mapped = plain.map { c ->
            when (c) {
                'q' -> 'c'
                'l', '1' -> 'i'
                else -> c
            }
        }.joinToString("")
        return mapped.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
    }

    /** Aynı sözcük mü: altı ve daha uzun harflide bir harf farkına (ekleme, silme, değiştirme) izin verilir. */
    internal fun isClose(a: String, b: String): Boolean {
        if (a == b) return true
        if (a.length < 6 || b.length < 6 || kotlin.math.abs(a.length - b.length) > 1) return false
        var i = 0
        var j = 0
        var edits = 0
        while (i < a.length && j < b.length) {
            if (a[i] == b[j]) {
                i++; j++
                continue
            }
            edits++
            if (edits > 1) return false
            when {
                a.length > b.length -> i++
                b.length > a.length -> j++
                else -> { i++; j++ }
            }
        }
        return edits + (a.length - i) + (b.length - j) <= 1
    }
}
