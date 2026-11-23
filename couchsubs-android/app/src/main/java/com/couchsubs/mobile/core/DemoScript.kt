// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * Deneme modu (iPhone/Mac `DemoScript` ile aynı): konsol olmadan uygulamanın bütün hattını gösteren örnek altyazılar.
 * Satırlar özgündür (oyun, marka ya da logo yok); kareler [com.couchsubs.mobile.remoteplay.SampleFrameSource]'ta çizilir.
 */
object DemoScript {
    data class Line(val english: String, val turkish: String)

    val lines = listOf(
        Line("We should reach the lighthouse before dark.", "Hava kararmadan deniz fenerine varmalıyız."),
        Line("The bridge is gone. We need another way across.", "Köprü yıkılmış. Karşıya geçmek için başka bir yol lazım."),
        Line("Stay close to me and keep your voice down.", "Yanımdan ayrılma ve sesini alçak tut."),
        Line("I found a map in the old captain's cabin.", "Yaşlı kaptanın kamarasında bir harita buldum."),
        Line("Do you hear that? Something is moving in the fog.", "Duydun mu? Siste bir şey hareket ediyor."),
        Line("Light the lantern. We can't see a thing out here.", "Feneri yak. Burada hiçbir şey göremiyoruz."),
        Line("The storm will reach the harbor within an hour.", "Fırtına bir saat içinde limana ulaşacak."),
        Line("If we take the boat, we can be there by morning.", "Tekneyi alırsak sabaha orada olabiliriz."),
        Line("Thank you for coming back for me.", "Benim için geri döndüğün için teşekkürler."),
        Line("Keep the key safe. We will need it at the gate.", "Anahtarı sakla. Kapıda ona ihtiyacımız olacak."),
        Line("Follow the river north until you see the tower.", "Kuleyi görene kadar nehri kuzeye doğru takip et."),
        Line("Rest now. Tomorrow will be a long day.", "Şimdi dinlen. Yarın uzun bir gün olacak."),
    )

    /** Karenin sol üstündeki görev yazısı ("Ekranı çevir" ve ek alanlar bunu da çevirir). */
    val objective = Line("Objective: Reach the lighthouse", "Görev: Deniz fenerine ulaş")

    /** Her satırın görünme süresi ve aradaki altyazısız süre (ms). */
    const val LINE_MS = 3600L
    const val GAP_MS = 900L

    /** Başlangıçtan [elapsedMs] sonra gösterilen satırın sırası (altyazısız aralıkta null); ilk satır kısa boşluktan sonra. */
    fun lineIndex(elapsedMs: Long, lineMs: Long = LINE_MS, gapMs: Long = GAP_MS): Int? {
        val shifted = elapsedMs - gapMs
        if (shifted < 0) return null
        val cycle = lineMs + gapMs
        if (shifted % cycle >= lineMs) return null
        return ((shifted / cycle) % lines.size).toInt()
    }

    /** Gömülü hazır çeviri: okunan metin örnek satırlardan birine benziyorsa Türkçesi (ağ ve anahtar gerekmez). */
    fun translation(text: String): String? {
        val wanted = TextMatch.normalize(text)
        if (wanted.isEmpty()) return null
        val all = lines + objective
        all.firstOrNull { TextMatch.normalize(it.english) == wanted }?.let { return it.turkish }
        return all.firstOrNull { TextMatch.isSimilar(TextMatch.normalize(it.english), wanted, 0.8) }?.turkish
    }
}

/**
 * Deneme modunun çevirmeni: seçili motor (varsayılanı cihazdaki ücretsiz çeviri) çevirir; motor çeviremezse (model
 * inmemiş, ağ ya da anahtar yok) örnek satırların gömülü hazır çevirisi gösterilir.
 */
class DemoTranslator(private val base: TextTranslator?) : TextTranslator {
    override fun translate(text: String): String {
        if (base != null) {
            try {
                val result = base.translate(text)
                if (result.isNotBlank()) return result
            } catch (error: InterruptedException) {
                throw error
            } catch (error: Exception) {
                // Hazır çeviriye düşülür.
            }
        }
        return DemoScript.translation(text) ?: text
    }

    override fun translateAll(texts: List<String>): List<String> {
        if (base != null) {
            try {
                val results = base.translateAll(texts)
                if (results.size == texts.size) return results
            } catch (error: InterruptedException) {
                throw error
            } catch (error: Exception) {
                // Hazır çeviriye düşülür.
            }
        }
        return texts.map { DemoScript.translation(it) ?: it }
    }

    override val translatesTogether: Boolean get() = base?.translatesTogether ?: false

    override fun noteSpeaker(name: String) {
        base?.noteSpeaker(name)
    }
}
