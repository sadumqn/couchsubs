// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Çevrilen altyazılar, en yenisi başta: bu oturumun ve önceki oturumların son [limit] satırı ("Geçmiş" ekranı). Hızlı
 * geçen bir satır sonradan yeniden okunabilsin diye tutulur. Mac/iPhone'daki SubtitleHistory.swift ve Windows'taki
 * SubtitleHistory.cs ile aynı kurallar ve aynı dosya biçimi (history.json).
 */
class SubtitleHistory(limit: Int = DEFAULT_LIMIT) {
    /** [origin]: "pack" (oyun paketi) ya da "engine" (çeviri motoru). [date]: duvar saati, ms. */
    data class Entry(val id: Int, val date: Long, val source: String, val translation: String, val origin: String)

    companion object {
        const val DEFAULT_LIMIT = 200
        /** Bir satırın kaydedilen en uzun hâli (dosya şişmesin). */
        const val MAX_TEXT_LENGTH = 500
        const val PACK = "pack"
        const val ENGINE = "engine"

        private fun iso() = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.ROOT).apply { timeZone = TimeZone.getTimeZone("UTC") }

        /** Satırlar düz metin olarak (kopyalamak için): her satırda saat, Türkçe ve İngilizcesi. */
        fun plainText(entries: List<Entry>, timeZone: TimeZone = TimeZone.getDefault()): String {
            val format = SimpleDateFormat("HH:mm:ss", Locale.ROOT).apply { this.timeZone = timeZone }
            return entries.joinToString("\n\n") { "[${format.format(Date(it.date))}] ${it.translation}\n${it.source}" }
        }

        /** Dosyadaki geçmiş; dosya yoksa ya da bozuksa boş geçmiş. */
        fun load(file: File, limit: Int = DEFAULT_LIMIT): SubtitleHistory {
            val history = SubtitleHistory(limit)
            try {
                val array = JSONObject(file.readText()).getJSONArray("entries")
                val parser = iso()
                for (i in 0 until minOf(array.length(), history.limit)) {
                    val item = array.getJSONObject(i)
                    val date = parser.parse(item.getString("date"))?.time ?: continue
                    history.items.add(Entry(item.getInt("id"), date, item.getString("source"), item.getString("translation"),
                        if (item.optString("origin") == PACK) PACK else ENGINE))
                }
            } catch (error: Exception) {
                history.items.clear()
            }
            history.nextId = (history.items.maxOfOrNull { it.id } ?: -1) + 1
            return history
        }

        private fun clip(text: String) = if (text.length > MAX_TEXT_LENGTH) text.take(MAX_TEXT_LENGTH) else text
    }

    val limit = maxOf(1, limit)
    private val items = mutableListOf<Entry>()
    private var nextId = 0

    val entries: List<Entry> get() = synchronized(items) { items.toList() }

    /** Yeni çeviriyi başa ekler. Aynı satırın yeniden okuması (benzer kaynak metin) yeni kayıt açmaz, son kaydı günceller. */
    fun add(source: String, translation: String, origin: String = ENGINE, date: Long = System.currentTimeMillis()) = synchronized(items) {
        val text = clip(translation.trim())
        val from = clip(source)
        if (text.isEmpty()) return@synchronized
        val last = items.firstOrNull()
        if (last != null && TextMatch.isSimilar(TextMatch.normalize(last.source), TextMatch.normalize(from))) {
            items[0] = Entry(last.id, date, from, text, origin)
            return@synchronized
        }
        items.add(0, Entry(nextId++, date, from, text, origin))
        while (items.size > limit) items.removeAt(items.size - 1)
    }

    fun clear() = synchronized(items) { items.clear() }

    /** Geçmişi dosyaya yazar (geçici dosyadan yerine koyarak; yarım dosya kalmaz). */
    fun save(file: File) {
        val format = iso()
        val array = JSONArray()
        for (entry in entries) array.put(JSONObject().put("id", entry.id).put("date", format.format(Date(entry.date)))
            .put("source", entry.source).put("translation", entry.translation).put("origin", entry.origin))
        file.parentFile?.mkdirs()
        val temporary = File(file.path + ".tmp")
        temporary.writeText(JSONObject().put("version", 1).put("entries", array).toString())
        if (!temporary.renameTo(file)) {
            file.delete()
            temporary.renameTo(file)
        }
    }
}
