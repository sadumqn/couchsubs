// SPDX-License-Identifier: AGPL-3.0-only
// Altyazı Görünümü'nün değerleri Mac/iPhone SubtitlePalette ve TranslationPace ile aynı.
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SubtitlePaletteTest {
    @Test
    fun speedPresetsMatchTheWaits() {
        assertEquals(TranslationPace.FAST, TranslationPace.of(400, 0))
        assertEquals(TranslationPace.BALANCED, TranslationPace.of(800, 300))
        assertEquals(TranslationPace.ACCURATE, TranslationPace.of(1000, 800))
        // Kaydırıcıyla başka değer verildiyse hiçbiri seçili değil.
        assertNull(TranslationPace.of(600, 300))
    }

    @Test
    fun textSizeMapsBothWays() {
        assertEquals(30, SubtitlePalette.display(46))
        assertEquals(16, SubtitlePalette.display(10))
        assertEquals(50, SubtitlePalette.display(90))
        assertEquals(90, SubtitlePalette.fontSize(50))
        assertEquals(16, SubtitlePalette.fontSize(16))
    }

    @Test
    fun darknessAndTextColor() {
        assertNull(SubtitlePalette.darknessLevel(0))
        assertEquals(100, SubtitlePalette.darknessLevel(90))
        assertEquals(75, SubtitlePalette.darknessLevel(70))
        assertEquals("#FFE066", SubtitlePalette.textHex(SubtitleStyle(textColor = SubtitleTextColor.YELLOW)))
        assertEquals("#BFE3FF", SubtitlePalette.textHex(SubtitleStyle(textHex = "#bfe3ff")))
        assertTrue(SubtitlePalette.lowContrast(SubtitleStyle(backgroundColor = "#FFFFFF", background = 100, textHex = "#F3EEE4")))
        assertFalse(SubtitlePalette.lowContrast(SubtitleStyle()))
    }

    @Test
    fun characterNameModes() {
        val book = SpeakerColorBook()
        // Tek Renk: herkes aynı renkte.
        book.configure(fixed = "#4FD1C5", overrides = emptyMap())
        assertEquals("#4FD1C5", book.color("Jason"))
        assertEquals("#4FD1C5", book.color("Lucia"))
        // Karaktere Göre: seçilen renk önce, öbürlerine palet sırasıyla.
        book.reset()
        book.configure(fixed = null, overrides = mapOf("Lucia" to "#FF8FAB"))
        assertEquals("#FF8FAB", book.color("Lucia"))
        assertEquals("#FF8FAB", book.color("Lucia."))
        val jason = book.color("Jason")
        assertTrue(jason in SpeakerColors.palette)
        assertEquals(listOf("lucia", "jason"), book.known.map { it.first })
        // Seçim yoksa eski davranış (palet sırası).
        val plain = SpeakerColorBook()
        assertEquals(SpeakerColorBook().color("Jason"), plain.color("Jason"))
    }

    @Test
    fun styleFrameConfiguresNameColors() {
        val server = SubtitleServer(port = 0)
        SpeakerColors.session.reset()
        server.sendStyle(SubtitleStyle(nameColorMode = NameColorMode.SINGLE, nameHex = "#63B3ED"))
        assertEquals("#63B3ED", SpeakerColors.session.color("Cal"))
        server.sendStyle(SubtitleStyle(nameColorMode = NameColorMode.SINGLE))
        assertEquals(SubtitlePalette.names[0].hex, SpeakerColors.session.color("Cal"))
        server.sendStyle(SubtitleStyle())
        SpeakerColors.session.reset()
    }
}
