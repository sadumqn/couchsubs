// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * Hattın karara bağladığı (atılan ya da gösterilen) satırlar, ekranda durdukları sürece. PS5'in Türkçe ana ekranında
 * (beta.89, Mac) alandaki satırlar her karede okunuyor, seçilen blok ise her iki üç saniyede bir değişiyordu ("One [Ikan
 * Ipufl", "Yakin zamanda olu...", "e [Ikan Ipuflari Yakin zamanda olu..."): doğru okunan Türkçe satır "zaten hedef
 * dilde" diye atılıyor, bozuk okunan parçası İngilizce sanılıp çevriliyor ve TV'de altyazı olarak beliriyordu; aynı
 * döngü ekran değişmeden her 2,5 sn'de bir yineleniyordu. Üç kural:
 *  1. Kaynağı zaten hedef dilde olan bloğun (target) aynı yerdeki bozuk okunmuş parçası ([isTargetFragment]) altyazı
 *     adayı değildir.
 *  2. Karara bağlanmış satır ([isSettled]) ekranda durdukça yeniden işlenmez, günlüğe de yeniden yazılmaz.
 *  3. Satır karenin okunan yazısında artık yoksa unutulur: atılan satır [DROPPED_ABSENT_MS] sonra, gösterilen satır ilk
 *     yokluğunda (aynı satır gerçekten yeniden gelirse her zamanki gibi çevrilir).
 * Windows (SettledText.cs) ve Mac/iPhone (SettledText.swift) aynı kuralları uygular; ortak deneme dosyası settled-text.json.
 */
class SettledText {
    /**
     * [loose]: altyazı adayı sayılmadan atıldı (Türkçe, Türkçe bloğun parçası, çöp okuma): yazı tanıma farkı kadar değişmiş
     * okuması da aynı satırdır. Çevirisi aslıyla aynı çıkan satırda yalnız aynı metin sayılır (düzelen okuma, ör.
     * "I can do" → "I can't do", yeniden çevrilir).
     */
    private class Entry(val text: String, val top: Double?, val bottom: Double?, val target: Boolean, val shown: Boolean,
                        val loose: Boolean, var seenAt: Long)

    private val entries = mutableListOf<Entry>()

    /** Karenin bütün okunan satırları: ekranda duran kayıtların görüldüğü an yenilenir, ekrandan kalkanlar unutulur. */
    fun observe(lines: List<String>, time: Long) {
        if (entries.isEmpty()) return
        val frame = TextMatch.normalize(lines.joinToString(" "))
        for (entry in entries) if (covered(entry.text, frame)) entry.seenAt = time
        entries.removeAll { time - it.seenAt > (if (it.shown) 0 else DROPPED_ABSENT_MS) }
    }

    /** Satır karara bağlandı (atıldı ya da gösterildi). */
    fun settle(source: String, box: TextBox?, target: Boolean, shown: Boolean, time: Long, loose: Boolean = false) {
        val text = TextMatch.normalize(source)
        if (text.length < MIN_LENGTH) return
        entries.removeAll { it.text == text }
        entries.add(Entry(text, box?.top, box?.bottom, target, shown, loose && !shown, time))
        while (entries.size > CAPACITY) entries.removeAt(0)
    }

    /**
     * Satır karara bağlanmış ve hâlâ ekranda. Altyazı adayı sayılmadan atılan satırın (loose) yazı tanıma farkı kadar
     * değişmiş okuması da sayılır; öbürlerinde yalnız aynı metin (uzamış ya da düzelmiş okuması her zamanki gibi gider).
     */
    fun isSettled(source: String): Boolean {
        val text = TextMatch.normalize(source)
        if (text.length < MIN_LENGTH) return false
        return entries.any { it.text == text || (it.loose && TextMatch.isSimilar(text, it.text, SIMILARITY)) }
    }

    /**
     * Satır, aynı yerde duran ve kaynağı zaten hedef dilde olan bir bloğun bozuk okunmuş parçası mı ("One [Ikan Ipufl"
     * ⊂ "e [Ikan Ipuflari Yakin zamanda olu..."). Yerler biliniyorsa dikeyde örtüşmeleri gerekir. Türkçe olduğu burada
     * anlaşılan (loose) bloğun parçası okuma farkıyla biraz uzun da olabilir; çevirmenin aslıyla aynı döndürdüğü bloğun
     * parçası ondan kısa olmalı ve cümle gibi bitmemeli (tam cümle, ör. "I said that I would help you.", altyazıdır).
     */
    fun isTargetFragment(source: String, box: TextBox?): Boolean {
        val text = TextMatch.normalize(source)
        if (text.length < MIN_LENGTH) return false
        val sentence = SubtitleStabilizer.endsSentence(source)
        return entries.any { entry ->
            val fits = if (entry.loose) text.length <= entry.text.length + 2 else text.length < entry.text.length && !sentence
            if (!entry.target || !fits || !covered(text, entry.text)) return@any false
            val top = entry.top
            val bottom = entry.bottom
            if (box == null || top == null || bottom == null) true else box.top < bottom && top < box.bottom
        }
    }

    fun reset() = entries.clear()

    companion object {
        /** Atılan satır bu süre boyunca karede okunmazsa unutulur (yazı tanımanın tek tük kaçırdığı kareler sayılmaz). */
        const val DROPPED_ABSENT_MS = 1500L
        /** Parçanın büyük yazıda kesintisiz geçen en uzun bölümü, parçanın en az bu oranı olmalı. */
        const val COVERAGE = 0.7
        /** Aynı satırın yeniden okuması sayılan benzerlik (Levenshtein oranı). */
        const val SIMILARITY = 0.8
        /** Bundan kısa (sadeleştirilmiş) satır akılda tutulmaz ("No.", "Go!" yeniden söylenebilir). */
        const val MIN_LENGTH = 6
        const val CAPACITY = 16

        /** [part]'ın [whole] içinde kesintisiz geçen en uzun bölümü, kendisinin en az [COVERAGE] oranı mı. */
        fun covered(part: String, whole: String): Boolean {
            if (part.isEmpty() || whole.isEmpty()) return false
            return longestRun(part, whole) >= COVERAGE * part.length
        }

        /** İki metnin ortak en uzun kesintisiz bölümünün uzunluğu (karakter). */
        fun longestRun(a: String, b: String): Int {
            var previous = IntArray(b.length + 1)
            var best = 0
            for (i in 1..a.length) {
                val row = IntArray(b.length + 1)
                for (j in 1..b.length) {
                    if (a[i - 1] != b[j - 1]) continue
                    row[j] = previous[j - 1] + 1
                    if (row[j] > best) best = row[j]
                }
                previous = row
            }
            return best
        }
    }
}
