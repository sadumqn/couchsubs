// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Konuşana göre renk: Mac/iPhone, Windows ve TV uygulamasıyla aynı palet ve aynı renkler. */
class SpeakerColorsTest {
    @Test
    fun colorsMatchOtherPlatforms() {
        assertEquals("#90CAF9", SpeakerColors.color("Mattia"))
        assertEquals("#90CAF9", SpeakerColors.color("MATTIA"))
        assertEquals("#90CAF9", SpeakerColors.color("  Mattia "))
        assertEquals("#F06292", SpeakerColors.color("Lucia"))
        assertEquals("#4DD0E1", SpeakerColors.color("Jason"))
        assertEquals("#4FC3F7", SpeakerColors.color("Cal"))
    }

    @Test
    fun speakersComeFromEachLineOnce() {
        val speakers = SpeakerColors.speakers("Lucia: Gidelim.\nJason: Tamam.\nLucia: Hemen.", SpeakerColorBook())
        assertEquals(listOf(SpeakerColors.Speaker("Lucia", "#F06292"), SpeakerColors.Speaker("Jason", "#4DD0E1")), speakers)
        assertTrue(SpeakerColors.speakers("Hedef: Arabaya bin.").isEmpty())
        assertTrue(SpeakerColors.speakers("Saat 10:30 oldu.").isEmpty())
    }

    /** Yalnız "Ad:" konuşanın renginde; cümle ve bölünmüş devam satırı renksiz (Yazı rengi ayarında) kalır. */
    @Test
    fun onlyTheSpeakerNameIsColored() {
        val source = "Mattia: Bu çok uzun bir cümle ve bölünüyor. Lucia: Evet."
        val display = "Mattia: Bu çok uzun bir\ncümle ve bölünüyor."
        assertEquals(
            listOf(SpeakerColors.Segment(0, 7, "#90CAF9"), SpeakerColors.Segment(7, display.length, null)),
            SpeakerColors.segments(display, source, SpeakerColorBook()),
        )
        val two = "Lucia: Gidelim.\nJason : Tamam."
        assertEquals(
            listOf(
                SpeakerColors.Segment(0, 6, "#F06292"), SpeakerColors.Segment(6, 16, null),
                SpeakerColors.Segment(16, 23, "#4DD0E1"), SpeakerColors.Segment(23, two.length, null),
            ),
            SpeakerColors.segments(two, book = SpeakerColorBook()),
        )
        assertEquals("Jason :", two.substring(16, 23))
        assertTrue(SpeakerColors.segments("Sadece cümle.").isEmpty())
    }

    /** Telefon ekranındaki altyazı: ad renkli span, cümleye span yok (Text'in Yazı rengi geçerli). */
    @Test
    fun phoneSubtitleKeepsTheTextColorOnTheLine() {
        SpeakerColors.session.reset()
        val text = com.couchsubs.mobile.ui.PhoneSubtitleActivity.speakerText("Mattia: Gidelim.", "Mattia: Gidelim.", enabled = true)
        assertEquals(listOf(0 to 7), text.spanStyles.map { it.start to it.end })
        assertTrue(com.couchsubs.mobile.ui.PhoneSubtitleActivity.speakerText("Mattia: Gidelim.", "Mattia: Gidelim.", enabled = false).spanStyles.isEmpty())
    }

    @Test
    fun subtitleFrameCarriesSpeakerNamesOnlyWhenOn() {
        SpeakerColors.session.reset()
        val on = SubtitleServer.subtitleFrame("Mattia: Merhaba", 4000, null, at = 1, speakerColors = true)
        assertEquals(
            "event: subtitle\ndata: {\"at\":1,\"duration\":4000,\"speakerNames\":[{\"color\":\"#90CAF9\",\"name\":\"Mattia\"}]," +
                "\"text\":\"Mattia: Merhaba\"}\n\n",
            on,
        )
        // Eski alan hiç gitmez: 0.9.79'dan eski TV uygulamaları onunla bütün satırı boyuyordu.
        assertFalse(on.contains("\"speakers\""))
        assertFalse(SubtitleServer.subtitleFrame("Mattia: Merhaba", 4000, null, at = 1).contains("speaker"))
        assertFalse(SubtitleServer.subtitleFrame("Merhaba", 4000, null, at = 1, speakerColors = true).contains("speaker"))
    }

    /** Konuşana göre renk v2: dört platformun ortak vektörü (docs/speaker-colors-vectors.json) birebir. */
    @Test
    fun colorBookMatchesTheSharedVector() {
        val file = generateSequence(java.io.File("").absoluteFile) { it.parentFile }
            .map { java.io.File(it, "docs/speaker-colors-vectors.json") }.first { it.exists() }
        val json = org.json.JSONObject(file.readText())
        val palette = json.getJSONArray("palette")
        assertEquals((0 until palette.length()).map { palette.getString(it) }, SpeakerColors.palette)
        val families = json.getJSONObject("families")
        SpeakerColors.palette.forEach { assertEquals(families.getString(it).single(), SpeakerColorBook.families[it]) }
        val book = SpeakerColorBook()
        val sequence = json.getJSONArray("sequence")
        for (i in 0 until sequence.length()) {
            val item = sequence.getJSONObject(i)
            assertEquals(item.getString("name"), item.getString("color"), book.color(item.getString("name")))
        }
    }

    @Test
    fun headingsTimesAndRatiosAreNotSpeakers() {
        listOf("Hedef: Arabaya bin.", "Görev: Eve dön.", "Not: Kaydet.", "İpucu: Koş.", "Uyarı: Dikkat et.", "Bilgi: Yeni.",
            "Ödül: Para.", "Konum: Liman.", "Bölüm: Bir.", "Durum: İyi.", "Soru: Neden?", "Cevap: Evet.",
            "Saat 12:30 oldu.", "Oran 3:1 oldu.").forEach {
            assertTrue(it, SpeakerColors.speakers(it, SpeakerColorBook()).isEmpty())
        }
    }
}
