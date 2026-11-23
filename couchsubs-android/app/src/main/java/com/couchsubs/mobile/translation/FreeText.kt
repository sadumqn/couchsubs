// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.translation

import java.util.Locale

/**
 * Oyunlarda sık geçen, cihaz üstü çevirinin kelime kelime çevirdiği ifadeler ("I've got your six" → "Altını aldım")
 * çeviriden önce aynı anlamdaki düz İngilizceye çevrilir (Mac/iPhone ve Windows'taki GameEnglish ile aynı liste).
 */
object GameEnglish {
    private val phrases = listOf(
        "friendlies" to "allies",
        "(?:I've|I) got your six" to "I've got your back",
        "check your six" to "watch behind you",
        "heads up" to "watch out",
        "took you long enough" to "you're late",
        "we've got company" to "enemies are coming",
        "lock and load" to "get ready",
        "sitting ducks" to "easy targets",
        "moving in" to "going in",
    ).map { (pattern, plain) -> Regex("\\b$pattern\\b", RegexOption.IGNORE_CASE) to plain }

    /** Bilinen ifadeler düz İngilizceye çevrilir; cümle başındaki büyük harf korunur. */
    fun plain(sentence: String): String {
        var text = sentence
        for ((pattern, plain) in phrases) {
            text = pattern.replace(text) { match ->
                if (match.value.firstOrNull()?.isUpperCase() == true) plain.replaceFirstChar { it.uppercaseChar() } else plain
            }
        }
        return text
    }
}

/**
 * Cihaz üstü çevirinin Türkçesine yapılan güvenli düzeltmeler (Mac/iPhone: TurkishPostEdit.swift, Windows:
 * TurkishPostEdit.cs, aynı kurallar): noktalamadan önceki boşluk silinir, kaynağın "!", "?", "…" sonu korunur, tırnaklar
 * kaynaktaki gibi olur; aynı satırda "sen" ile konuşulurken model emri "siz"li verdiyse bilinen emirler "sen"li olur.
 */
object TurkishPostEdit {
    private val turkish = Locale("tr", "TR")
    private val spaceBeforePunctuation = Regex("[ \\t\u00A0]+(?=[,.!?;:…])")
    private val repeatedSpaces = Regex("[ \\t\u00A0]{2,}")

    /** Tek cümlenin çevirisini düzeltir; [source] İngilizce cümledir. */
    fun apply(source: String, translation: String): String {
        if (translation.none { it.isLetter() }) return translation
        var text = quotes(source, translation)
        text = spaceBeforePunctuation.replace(text, "")
        text = repeatedSpaces.replace(text, " ").trim()
        return ending(source, text)
    }

    /** Kaynağın ünlem/soru/üç nokta sonu çeviride başka bir sonla bittiyse kaynağınki konur. */
    internal fun ending(source: String, translation: String): String {
        val (_, sourceEnd, sourceClosers) = splitEnd(source)
        if (!isExpressive(sourceEnd)) return translation
        val (body, end, closers) = splitEnd(translation)
        // Kaynakta son noktalama tırnağın içindeyse (He said "Run!") çeviride tırnak sonda olmayabilir; dokunulmaz.
        if (sourceClosers.isEmpty() != closers.isEmpty()) return translation
        if (end == sourceEnd || !(end.isEmpty() || end == "." || isExpressive(end)) || body.none { it.isLetter() }) return translation
        return body + sourceEnd + closers
    }

    private fun isExpressive(end: String) = end.isNotEmpty() && ("!" in end || "?" in end || "…" in end || end == "...")

    /** Metin = gövde + son noktalama (. ! ? …) + kapanış tırnak/parantezleri. */
    private fun splitEnd(text: String): Triple<String, String, String> {
        val chars = text.trimEnd()
        var closerStart = chars.length
        while (closerStart > 0 && chars[closerStart - 1] in "\"'”’)]»") closerStart--
        var endStart = closerStart
        while (endStart > 0 && chars[endStart - 1] in ".!?…") endStart--
        return Triple(chars.substring(0, endStart), chars.substring(endStart, closerStart), chars.substring(closerStart))
    }

    /** Kaynak kıvrık tırnak kullanıyorsa çeviri de kullanır; yoksa düz tırnak. */
    internal fun quotes(source: String, translation: String): String {
        val curlyDouble = "“" in source || "”" in source
        val curlySingle = "’" in source || "‘" in source
        val out = StringBuilder()
        var previous: Char? = null
        for (c in translation) {
            val opening = previous == null || previous.isWhitespace() || previous in "([-–—"
            when {
                c in "“”„‟" && !curlyDouble -> out.append('"')
                c == '"' && curlyDouble -> out.append(if (opening) '“' else '”')
                c in "’‘" && !curlySingle -> out.append('\'')
                c == '\'' && curlySingle -> out.append(if (opening) '‘' else '’')
                else -> out.append(c)
            }
            previous = c
        }
        return out.toString()
    }

    private val senWords = setOf("sen", "seni", "sana", "senin", "sende", "senden", "seninle", "senle")
    private val sizWords = setOf("siz", "sizi", "size", "sizin", "sizde", "sizden", "sizinle", "sizler")

    /** "Siz"li emir → "sen"li emir; çoğul ya da kibar anlamı da olabilen sözcükler bilerek yok ("Alın" = alın). */
    private val imperatives = listOf(
        "dikkat edin" to "dikkat et", "acele edin" to "acele et", "ateş edin" to "ateş et", "yardım edin" to "yardım et",
        "takip edin" to "takip et", "sessiz olun" to "sessiz ol", "hazır olun" to "hazır ol", "sakin olun" to "sakin ol",
        "bekleyin" to "bekle", "durun" to "dur", "gelin" to "gel", "koşun" to "koş", "gidin" to "git", "bakın" to "bak",
        "dinleyin" to "dinle", "saklanın" to "saklan", "kaçın" to "kaç", "savaşın" to "savaş", "dövüşün" to "dövüş",
        "durdurun" to "durdur", "çekilin" to "çekil", "eğilin" to "eğil", "atlayın" to "atla", "tutun" to "tut",
        "bırakın" to "bırak", "söyleyin" to "söyle", "gösterin" to "göster", "getirin" to "getir", "kalkın" to "kalk",
        "odaklanın" to "odaklan", "yaklaşın" to "yaklaş", "uzaklaşın" to "uzaklaş",
    ).map { (polite, informal) ->
        Regex("(?<!\\p{L})" + Regex.escape(polite) + "(?=\\s*[!.,?…]|\\s*$)", setOf(RegexOption.IGNORE_CASE)) to informal
    }

    /**
     * Bir altyazının cümle çevirileri: herhangi birinde "sen" geçiyorsa (seni, sana…), "siz" geçmeyen cümlelerdeki
     * bilinen "siz"li emirler "sen"li olur. Başka hiçbir şeye dokunulmaz.
     */
    fun register(translations: List<String?>): List<String?> {
        if (translations.none { it != null && containsWord(it, senWords) }) return translations
        return translations.map { sentence -> if (sentence == null || containsWord(sentence, sizWords)) sentence else informal(sentence) }
    }

    private fun informal(sentence: String): String {
        var text = sentence
        for ((pattern, informal) in imperatives) {
            text = pattern.replace(text) { match ->
                if (match.value.first().isUpperCase()) informal.substring(0, 1).uppercase(turkish) + informal.substring(1) else informal
            }
        }
        return text
    }

    private fun containsWord(text: String, words: Set<String>) =
        text.lowercase(turkish).split(Regex("[^\\p{L}]+")).any { it in words }
}
