// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * Uzun çevirinin ekranda tek uzun satır olarak sağa sola taşmaması: satır başına en çok [MAX_CHARS] karakter,
 * en çok 3 satır, kelime sınırından ve dengeli bölünür. 3 satıra sığmayacak kadar uzunsa yazı biraz küçülür
 * ([Result.scale], en çok [MIN_SCALE]'e kadar). Konuşan adı ("ARTHUR: ...") bölünmez, hep ilk satırdadır.
 * Mac/iPhone (SubtitleWrap.swift), Windows (SubtitleWrap.cs), TV ve OBS sayfaları aynı kuralları uygular.
 */
object SubtitleWrap {
    const val MAX_CHARS = 42
    const val MAX_LINES = 3
    const val MIN_SCALE = 0.75

    data class Result(val text: String, val scale: Float)

    fun fit(text: String): Result {
        val length = text.codePointCount(0, text.length)
        if (length <= MAX_CHARS || text.contains('\n')) return Result(text, 1f)
        val words = tokens(text)
        if (words.size < 2) return Result(text, 1f)
        val scale = (MAX_CHARS * MAX_LINES).toDouble().div(length).coerceIn(MIN_SCALE, 1.0)
        val cap = Math.floor(MAX_CHARS / scale).toInt()
        val lines = minOf(MAX_LINES, maxOf(2, Math.ceil(length.toDouble() / cap).toInt()))
        return Result(balance(words, minOf(lines, words.size)), scale.toFloat())
    }

    /** Sözcükler; konuşan adı ("ARTHUR:") sonraki sözcükle birleşik tutulur, ad satır sonunda tek kalmaz. */
    internal fun tokens(text: String): List<String> {
        val words = text.split(Regex("\\s+")).filter { it.isNotEmpty() }.toMutableList()
        val colon = words.take(3).indexOfFirst { it.endsWith(":") || it.endsWith("：") }
        if (colon >= 0 && colon + 1 < words.size) {
            val joined = words.take(colon + 2).joinToString(" ")
            repeat(colon + 2) { words.removeAt(0) }
            words.add(0, joined)
        }
        return words
    }

    /** En uzun satırı en kısa yapan bölme; eşitlikte uzunlukların kareleri toplamı küçük olan seçilir. */
    internal fun balance(words: List<String>, lines: Int): String {
        val count = words.size
        fun width(from: Int, to: Int) = words.subList(from, to).sumOf { it.length } + (to - from - 1)
        var best: List<Int>? = null
        var bestLongest = Int.MAX_VALUE
        var bestSpread = Int.MAX_VALUE
        fun consider(cuts: List<Int>) {
            val edges = listOf(0) + cuts + count
            val widths = (0 until edges.size - 1).map { width(edges[it], edges[it + 1]) }
            val longest = widths.max()
            val spread = widths.sumOf { it * it }
            if (best == null || longest < bestLongest || (longest == bestLongest && spread < bestSpread)) {
                best = cuts; bestLongest = longest; bestSpread = spread
            }
        }
        if (lines == 2 || count < 3) {
            for (a in 1 until count) consider(listOf(a))
        } else {
            for (a in 1 until count - 1) for (b in a + 1 until count) consider(listOf(a, b))
        }
        val cuts = best ?: return words.joinToString(" ")
        val edges = listOf(0) + cuts + count
        return (0 until edges.size - 1).joinToString("\n") { words.subList(edges[it], edges[it + 1]).joinToString(" ") }
    }
}
