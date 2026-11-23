// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * "Ekranı çevir": fiyatlar, sayılar ve tuş çubukları. Fiyat kuralları ortak deneme dosyasından (fixtures/price-text.json,
 * core/Tests/CouchSubsCoreTests/Fixtures kopyası; Mac PriceTextTests.swift ve Windows PriceTextTests.cs aynı dosyayı okur).
 */
class PriceTextTest {
    @Test
    fun sharedVectors() {
        val root = JSONObject(Fixtures.text("price-text.json"))
        val repair = root.getJSONArray("repair")
        for (i in 0 until repair.length()) {
            val pair = repair.getJSONArray(i)
            assertEquals(pair.getString(0), pair.getString(1), PriceText.repair(pair.getString(0)))
        }
        val money = root.getJSONArray("money")
        for (i in 0 until money.length()) {
            val pair = money.getJSONArray(i)
            assertEquals(pair.getString(0), pair.getBoolean(1), PriceText.isMoney(pair.getString(0)))
        }
        val protect = root.getJSONArray("protect")
        for (i in 0 until protect.length()) {
            val vector = protect.getJSONObject(i)
            val result = PriceText.protect(vector.getString("text"))
            fun fill(template: String) = result.values.foldIndexed(template) { k, all, value -> all.replace("{$k}", value.name) }
            assertEquals(fill(vector.getString("sent")), result.text)
            assertEquals(vector.getString("result"), PriceText.restore(fill(vector.getString("reply")), result.values))
        }
    }

    private fun line(text: String, left: Double, top: Double, right: Double, vararg words: Triple<String, Double, Double>) =
        TextLine(text, TextBox(left, top, right, top + 0.03),
            words.map { TextWord(it.first, TextBox(it.second, top, it.third, top + 0.03)) }.takeIf { it.isNotEmpty() })

    /**
     * Sağ alttaki tuş çubuğu: "SCROLL R3 SEND ✕ BACK ○" atılmıyor; tuşlar çeviriye girmeden yerinde kalıyor, her etiket
     * kendi kutusunda sözlükten çevriliyor (çeviriler üst üste binmiyor).
     */
    @Test
    fun promptBarLabelsAreTranslatedOneByOneAndButtonsStay() {
        val bar = line("SCROLL R3 SEND ✕ BACK ○", 0.70, 0.92, 0.98, Triple("SCROLL", 0.70, 0.76), Triple("R3", 0.77, 0.79),
            Triple("SEND", 0.81, 0.85), Triple("✕", 0.86, 0.87), Triple("BACK", 0.89, 0.93), Triple("○", 0.94, 0.95))
        val asked = mutableListOf<String>()
        val items = ScreenTranslation.translateGroups(Reading(listOf(bar)), { asked.add(it); it })
        assertEquals(emptyList<String>(), asked)
        assertEquals(listOf("KAYDIR", "GÖNDER", "GERİ"), items.map { it.translation })
        assertEquals(listOf(0.70, 0.81, 0.89), items.map { it.box.left })
        assertEquals(listOf(0.76, 0.85, 0.93), items.map { it.box.right })
    }

    /** Bar menüsü: aynı satıra düşmüş seçenekler geniş boşluktan ayrılır; fiyat çeviriye girmez ve bozulmaz. */
    @Test
    fun optionsOnOneRowBecomeSeparateBoxesAndPricesStay() {
        val row = line("TIP S10 ORDER BARTENDER", 0.30, 0.80, 0.80, Triple("TIP", 0.30, 0.34), Triple("S10", 0.35, 0.39),
            Triple("ORDER", 0.50, 0.57), Triple("BARTENDER", 0.68, 0.80))
        val items = ScreenTranslation.translate(Reading(listOf(row)), { it })
        assertEquals(listOf("BAHŞİŞ VER", "SİPARİŞ VER", "BARMEN"), items.map { it.translation })
        assertEquals(0.34, items[0].box.right, 0.0)
    }

    /** Dükkân: "SSSS" (yazı tanımanın okuduğu "$$$$") artık yazı sayılıp çevrilmiyor; cümledeki fiyat korunuyor. */
    @Test
    fun misreadPricesAreNotTranslatedAndPricesInSentencesSurvive() {
        val asked = mutableListOf<String>()
        val items = ScreenTranslation.translateGroups(Reading(listOf(line("SSSS", 0.10, 0.10, 0.16), line("Buy the jacket for S200", 0.10, 0.50, 0.50))),
            { asked.add(it); it.replace("Buy the jacket for ", "Ceketi şu fiyata al: ") })
        assertEquals(1, asked.size)
        assertFalse(asked[0], '$' in asked[0] || "S200" in asked[0])
        assertEquals(listOf("Ceketi şu fiyata al: $200"), items.map { it.translation })
    }

    /** "Ekranı çevir"de tuş ipucu atılmaz: etiketi kendi kutusunda çevrilir, tuş ("R2") çeviriye girmez. */
    @Test
    fun promptLabelIsTranslatedAndTheButtonStays() {
        val items = ScreenTranslation.translateGroups(
            Reading(listOf(line("R2 Swing", 0.05, 0.10, 0.28, Triple("R2", 0.05, 0.11), Triple("Swing", 0.13, 0.28)))), { "TR: $it" })
        assertEquals(listOf("TR: Swing"), items.map { it.translation })
        assertTrue(items[0].box.left == 0.13)
    }
}
