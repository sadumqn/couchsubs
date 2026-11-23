// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.abs

/**
 * Oyun telefonundaki yazının kuralları: kullanıcı adları ve etiketler çevrilmez, mesaj listesindeki kişi adları oyunda
 * kalır, balonlar düz ekran koordinatlarıyla gruplanır (Mac/iPhone GamePhoneText.swift, Windows GamePhoneText.cs).
 */
object GamePhoneText {
    private val identifier = Regex("(?<![\\p{L}\\p{N}_])[@#][\\p{L}\\p{N}_]+(?:[.-][\\p{L}\\p{N}_]+)*")
    private val chatWord = Regex("(?<![\\p{L}\\p{N}_@#.-])(?:2gether|4u)(?![\\p{L}\\p{N}_])")
    private val misreadTen = Regex("(?<![\\p{L}\\p{N}_@#])(?:IO|I0|lO|l0)(?=\\s+min(?:s|utes?)?\\b)")
    private val sections = setOf("Messages", "Suggested", "Suggestions", "Öneriler", "Mesajlar")

    /**
     * Aynı uzun mesajda (en az dokuz sözcük) yan yana iki kısa sözcükte birer harf oynamış ("it out" → "ct ocut"): yazı
     * tanıma sapmasıdır, çeviri hemen yenilenmez. Tek sözcüklük yanıtlar, eklenen/silinen sözcükler, sayılar ve
     * olumsuzluklar doğrudan işlenir (Windows GamePhoneText.HasAdjacentOcrEdits).
     */
    fun hasAdjacentOcrEdits(shown: String, next: String): Boolean {
        val before = TextMatch.normalize(shown).split(' ')
        val after = TextMatch.normalize(next).split(' ')
        if (before.size < 9 || before.size != after.size) return false
        var first = 0
        var last = before.size - 1
        while (first <= last && before[first] == after[first]) first++
        while (last > first && before[last] == after[last]) last--
        if (last != first + 1) return false
        for (i in first..last) {
            val a = before[i]
            val b = after[i]
            val length = maxOf(a.length, b.length)
            if (minOf(a.length, b.length) < 2 || length > 6 || !a.all { it.isLetter() } || !b.all { it.isLetter() } ||
                !TextMatch.isSimilar(a, b, 1.0 - 1.0 / length)) return false
        }
        return !TextMatch.addsMeaning(next, shown) && !TextMatch.addsMeaning(shown, next)
    }

    fun containsIdentifier(text: String): Boolean =
        (text.contains('@') || text.contains('#')) && identifier.containsMatchIn(text)

    fun isWrittenChatWord(token: String): Boolean =
        (token.contains('2') || token.contains('4')) && chatWord.containsMatchIn(token)

    /** İngilizce modele giden yazı: "IO min" → "10 min", "2gether" → "together", "4u" → "for you". */
    fun englishModelInput(text: String): String {
        val value = if (text.contains("min")) misreadTen.replace(text, "10") else text
        if (!isWrittenChatWord(value)) return value
        return chatWord.replace(value) { if (it.value == "2gether") "together" else "for you" }
    }

    /** Çevirideki kullanıcı adları ve etiketler özgün yazımına döner; biri kaybolmuş ya da değişmişse çeviri kullanılmaz (null). */
    fun keepIdentifiers(source: String, translation: String?): String? {
        if (translation.isNullOrEmpty() || !containsIdentifier(source)) return translation
        val names = identifier.findAll(source).map { it.value }.toMutableList()
        val result = StringBuilder(translation)
        for (match in identifier.findAll(translation).toList().reversed()) {
            val index = names.indexOfLast { it.equals(match.value, ignoreCase = true) }
            if (index < 0) return null
            result.replace(match.range.first, match.range.last + 1, names.removeAt(index))
        }
        return if (names.isEmpty()) result.toString() else null
    }

    private fun isTag(token: String): Boolean =
        (token.startsWith('@') || token.startsWith('#')) && identifier.matchEntire(token) != null

    private fun section(text: String): String? {
        val value = text.dropWhile { !it.isLetter() }.trim()
        return value.takeIf { it in sections }
    }

    private fun looksLikeName(text: String): Boolean {
        val label = text.takeWhile { it != '(' }.trim()
        val words = label.split(' ').filter { it.isNotEmpty() }
        if (section(label) != null || words.size !in 1..4 || !words[0][0].isUpperCase()) return false
        return words.all { word ->
            (word[0].isUpperCase() || word in setOf("de", "du", "of")) && word.all { it.isLetter() || it == '-' || it == '\'' }
        }
    }

    fun isMessagePreview(text: String): Boolean =
        text.any { it.isWhitespace() } && section(text) == null && !looksLikeName(text)

    private fun layout(line: TextLine): TextBox? = line.phoneBox ?: line.box

    private fun isContactPair(name: TextLine, preview: TextLine): Boolean {
        val label = name.text.trim()
        val lowerName = label.length in 2..18 && label.all { it.isLowerCase() }
        if (!(looksLikeName(label) || lowerName)) return false
        val a = layout(name) ?: return false
        val b = layout(preview) ?: return false
        val h = a.bottom - a.top
        return a.left > 0.1 && a.left < 0.48 && abs(a.left - b.left) <= 0.06 &&
            b.top > a.top && b.top - a.bottom < h * 0.7 && b.bottom - b.top < h * 1.8
    }

    /**
     * Sağ kenara dayanan önizlemenin kesik sonu ("after .,", "there ...") tek yazımla üç nokta olur; son sözcük
     * tamamlanmaz, yalnız noktalama düzelir.
     */
    private fun previewPunctuation(line: TextLine): TextLine {
        val box = layout(line) ?: return line
        if (box.right < 0.76) return line
        val text = line.text
        var start = text.length
        while (start > 0 && text[start - 1] in ".,„") start--
        if (text.length - start !in 2..3 || text[start] != '.') return line
        var wordEnd = start
        while (wordEnd > 0 && text[wordEnd - 1].isWhitespace()) wordEnd--
        if (wordEnd == 0 || !text[wordEnd - 1].isLetter()) return line
        if (wordEnd == start && text.endsWith("...")) return line
        return line.copy(text = text.substring(0, wordEnd) + "...")
    }

    /** Çevrilecek satırlar: yalnız etiketten oluşan satırlar ve tanınan mesaj listesindeki kişi adları çıkarılır. */
    fun forTranslation(reading: Reading): Reading {
        val lines = reading.lines.filter { line ->
            val words = line.text.split(Regex("\\s+")).filter { it.isNotEmpty() }
            !(words.any(::isTag) && words.all { word -> isTag(word) || word.none { it.isLetterOrDigit() } })
        }.toMutableList()
        val headings = lines.mapNotNull { section(it.text) }.toSet()
        if (headings.none { it in setOf("Suggested", "Suggestions", "Öneriler") } ||
            headings.none { it in setOf("Messages", "Mesajlar") }) return Reading(lines)
        for (i in lines.indices) section(lines[i].text)?.let { lines[i] = lines[i].copy(text = it) }
        val order = lines.indices.filter { layout(lines[it]) != null }.sortedBy { layout(lines[it])!!.top }
        val names = mutableListOf<Int>()
        val previews = mutableSetOf<Int>()
        var i = 0
        while (i + 1 < order.size) {
            val name = order[i]
            val preview = order[i + 1]
            if (lines[preview].text.trim().contains(' ') && isContactPair(lines[name], lines[preview])) {
                names.add(name)
                previews.add(preview)
                i += 2
            } else {
                i += 1
            }
        }
        if (names.size < 3) return Reading(lines)
        val first = layout(lines[names.first()]) ?: return Reading(lines)
        val last = layout(lines[names.last()]) ?: return Reading(lines)
        if (last.top <= first.top) return Reading(lines)
        val slope = (last.left - first.left) / (last.top - first.top)
        fun inColumn(line: TextLine): Boolean {
            val box = layout(line) ?: return false
            return abs(box.left - (first.left + slope * (box.top - first.top))) <= 0.06
        }
        if (!names.all { inColumn(lines[it]) }) return Reading(lines)
        // Listeyi uzun önizlemeler doğruladı: aynı satır düzenindeki "Okay" gibi tek sözcüklük yanıt da önizlemedir, ad
        // gibi göründüğü için atılmaz. Önizlemesi olmayan ad yine atılır.
        i = 0
        while (i + 1 < order.size) {
            val name = order[i]
            val preview = order[i + 1]
            if (inColumn(lines[name]) && name !in previews && preview !in names && !lines[preview].text.trim().contains(' ') &&
                looksLikeName(lines[preview].text) && isContactPair(lines[name], lines[preview])) {
                names.add(name)
                previews.add(preview)
                i += 2
            } else {
                i += 1
            }
        }
        return Reading(lines.indices.mapNotNull { index ->
            val line = lines[index]
            when {
                index in previews -> previewPunctuation(line)
                inColumn(line) && (index in names || looksLikeName(line.text)) -> null
                else -> line
            }
        })
    }

    /** Balonlar: düzleştirilmiş ekranda ([TextLine.phoneBox]) alt alta ve hizalı satırlar tek balondur. */
    /**
     * Telefon ekranının blokları, kendi yerlerinde. Ana ekranda uygulama adları (WhatUp, simge etiketleri) çevrilmez
     * ([PhoneChat.withoutAppNames]); saat ve hava harfsiz satır olarak zaten atılır.
     */
    fun groups(source: Reading): List<ScreenTranslation.Group> {
        val home = PhoneChat.isHomeScreen(source.lines)
        val reading = Reading(PhoneChat.withoutAppNames(source.lines))
        val flat = reading.lines.all { it.phoneBox != null }
        fun box(line: TextLine): TextBox = (if (flat) line.phoneBox else line.box)!!
        val groups = mutableListOf<ScreenTranslation.Group>()
        val run = mutableListOf<TextLine>()
        fun finish() {
            if (run.isEmpty()) return
            try {
                if (!flat) {
                    groups += ScreenTranslation.groups(Reading(run.toList()), keepIdentifiers = true)
                    return
                }
                val clean = Reading(run.toList()).withButtonIcons().withoutButtonPrompts().withoutOcrNoise(keepIdentifiers = true)
                    .lines.filter { it.box != null && ScreenText.isWords(it.text) }
                val first = clean.firstOrNull()?.box ?: return
                val place = clean.drop(1).fold(first) { total, line -> total.union(line.box!!) }
                val heights = run.map { box(it).bottom - box(it).top }.sorted()
                val icons = clean.flatMap { it.icons ?: emptyList() }
                // Düz ekrandaki yeri: sohbet panelinde tarafı (sol/sağ) ve sırası bundan çıkar ([roles]).
                val spot = run.drop(1).fold(box(run[0])) { total, line -> total.union(box(line)) }
                groups += ScreenTranslation.Group(listOf(clean.joinToString(" ") { it.text }), place, heights[heights.size / 2],
                    if (icons.isEmpty()) null else listOf(icons), ScreenPhoneCard.Placement(ScreenPhoneCard.Role.MESSAGE, spot))
            } finally {
                run.clear()
            }
        }
        for (line in reading.lines.filter { it.box != null }.sortedBy { box(it).top }) {
            run.lastOrNull()?.let { if (breaksBlock(box(it), box(line), flat && endsSentence(it.text))) finish() }
            run.add(line)
        }
        finish()
        return roles(groups.take(ScreenTranslation.MAX_GROUPS), home)
    }

    /**
     * Sohbet panelinde her grubun rolü ("Ekranı çevir"in [PhoneChat] kuralları, düz ekrandaki yerinden): en üstteki kısa
     * ad satırı kişinin adıdır (çevrilmez), ortalı kısa satır not, sağa yaslı balon oyuncunun, sola yaslı karşı tarafın
     * mesajı. Sohbet listesinde önizlemeler, ana ekranda bütün yazılar kendi yerinde kalır. Mac ile aynı.
     */
    internal fun roles(groups: List<ScreenTranslation.Group>, home: Boolean): List<ScreenTranslation.Group> {
        if (groups.any { it.phone == null }) return groups.map { it.copy(phone = null) }
        val list = groups.any { section(it.paragraphs.joinToString("")) != null }
        val first = groups.indices.minByOrNull { groups[it].phone!!.spot.top }
        return groups.mapIndexed { index, group ->
            val text = group.paragraphs.joinToString(" ")
            val spot = group.phone!!.spot
            val row = PhoneChat.Row(emptyList(), spot, text)
            val role = when {
                home -> ScreenPhoneCard.Role.HOME
                index == first && !list && PhoneChat.isHeader(row) -> ScreenPhoneCard.Role.HEADER
                list -> if (section(text) != null) ScreenPhoneCard.Role.HEADING else ScreenPhoneCard.Role.PREVIEW
                else -> PhoneChat.role(listOf(row))
            }
            group.copy(phone = ScreenPhoneCard.Placement(role, spot))
        }
    }

    private fun endsSentence(text: String): Boolean = text.trimEnd().lastOrNull()?.let { it in ".!?" } ?: false

    /**
     * Düzeltilmiş telefon ekranında satır arası dar, aynı taraftaki ardışık balonların arası daha geniştir: cümle sonundan
     * sonra satır yüksekliğinin 0,65'inden geniş boşluk yeni balondur; aynı balonda alt satıra geçen ikinci cümle birlikte kalır.
     */
    private fun breaksBlock(previous: TextBox, next: TextBox, afterFlatSentence: Boolean): Boolean {
        val lineHeight = maxOf(previous.bottom - previous.top, next.bottom - next.top)
        if (next.top - previous.bottom > lineHeight * (if (afterFlatSentence) 0.65 else 1.0)) return true
        val alignedLeft = abs(previous.left - next.left) <= 0.08
        val alignedRight = minOf(previous.left, next.left) > 0.25 && abs(previous.right - next.right) <= 0.045
        return !alignedLeft && !alignedRight
    }
}
