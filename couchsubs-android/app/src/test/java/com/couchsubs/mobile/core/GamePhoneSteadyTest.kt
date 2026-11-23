// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.ceil
import kotlin.math.floor

/**
 * Otomatik telefon okumasında mesaj kaybı ve titreme: balon ayrımı, liste önizlemeleri, OCR sapmaları, soluk satırın
 * kurtarılması ve gönderilen balonun görünüşünün sabit kalması (Windows GamePhoneTextTests.cs, GamePhoneReaderTests.cs,
 * RegionWatcherTests.PhoneAppearance.cs ile aynı vektörler).
 */
class GamePhoneSteadyTest {
    private fun line(text: String, y: Double, left: Double = 0.2, right: Double = 0.8) =
        TextLine(text, TextBox(left, y, right, y + 0.031))

    @Test
    fun previewEllipsisHasOneSpellingWithoutCompletingTheLastWord() {
        for ((preview, expected) in listOf("Meet me there .." to "Meet me there...", "Meet me there ..." to "Meet me there...",
            "Meet me there..." to "Meet me there...", "Meet me at 6." to "Meet me at 6.")) {
            val reading = Reading(listOf(line("Suggested", 0.02), line("Jordan", 0.10), line(preview, 0.14),
                line("Chase", 0.22), line("Call me back.", 0.26), line("Messages", 0.40),
                line("Robin", 0.50), line("On my way.", 0.54)))
            assertTrue(preview, GamePhoneText.forTranslation(reading).lines.any { it.text == expected })
        }
    }

    @Test
    fun shortRepliesAndMeaningChangesDoNotWaitForOcrConfirmation() {
        for ((old, next) in listOf("Go" to "No",
            "Meet me at the back gate with 24 red bags." to "Meet me at the back gate with 25 bed bags.",
            "We can do it now if you bring the truck." to "We can not do it now if you bring the truck.",
            "I heard they all went to the left door." to "I heard they all went to the rear door.",
            "That was all I needed to hear from your friend." to "The next message just came in from the office.")) {
            assertFalse(old, GamePhoneText.hasAdjacentOcrEdits(old, next))
        }
        assertTrue(GamePhoneText.hasAdjacentOcrEdits("Cool. I'll check it out. Would be nice to clear my head for a second.",
            "Cool. I'll check ct ocut. Would be nice to clear my head for a second."))
    }

    @Test
    fun singleWordPreviewInAConfirmedListIsNotMistakenForAnotherContact() {
        for (message in listOf("Okay", "No", "Thanks")) {
            val rows = Reading(listOf(line("Suggestions", 0.02), line("Chase", 0.09), line("call me soon", 0.13),
                line("May", 0.21), line("Don't leave yet.", 0.25), line("Messages", 0.34),
                line("Rose", 0.42), line("Meet me here.", 0.46), line("Jason", 0.56), line(message, 0.60),
                line("Martin", 0.73), line("Lucia", 0.85)))
            assertEquals(listOf("Suggestions", "call me soon", "Don't leave yet.", "Messages", "Meet me here.", message),
                GamePhoneText.forTranslation(rows).lines.map { it.text })
        }
    }

    @Test
    fun sameSideRepliesRemainSeparateAsThePhoneMoves() {
        for (spacing in listOf(0.72, 1.03)) {
            val h = 0.04
            fun flat(text: String, y: Double, x: Double): TextLine {
                val box = TextBox(x, y, 0.8, y + h)
                return TextLine(text, box, phoneBox = box)
            }
            val y = 0.12 + h * (1 + spacing)
            val next = y + h * (2.1 + spacing)
            val reading = Reading(listOf(flat("Jason.", 0.12, 0.10), flat("Kirk is paying.", y, 0.15),
                flat("He is on his way.", y + h * 1.10, 0.15), flat("Meet me outside.", next, 0.10)))
            assertEquals(listOf("Jason.", "Kirk is paying. He is on his way.", "Meet me outside."),
                GamePhoneText.groups(reading).flatMap { it.paragraphs })
        }
    }

    // MARK: soluk satırın kurtarılması

    private fun flat(width: Int, height: Int, ink: Boolean): GamePhoneReader.Flat {
        val out = ByteArray(width * height * 3 / 2)
        java.util.Arrays.fill(out, 0, width * height, 0)
        java.util.Arrays.fill(out, width * height, out.size, 128.toByte())
        if (ink) for (y in 244 until 266) for (x in 40 until 150) out[y * width + x] = ((x / 3 % 2) * 180).toByte()
        return GamePhoneReader.Flat(out, width, height)
    }

    private fun rescue(hasInk: Boolean, complete: Boolean, anchorMatches: Boolean, calls: Int, recovered: Boolean, partial: Boolean = false) {
        val image = flat(200, 300, hasInk)
        val anchor = TextLine("around. Be good", TextBox(0.20, 0.88, 0.67, 0.94), confidence = 0.98f)
        val upper = TextLine("Just passing through", TextBox(0.20, 0.83, 0.85, 0.89), confidence = 0.96f)
        val lines = mutableListOf(TextLine("Friends", TextBox(0.1, 0.12, 0.3, 0.18)), TextLine("See you soon.", TextBox(0.1, 0.49, 0.6, 0.54)), anchor)
        if (complete) lines.add(upper)
        if (partial) lines.add(TextLine("passing through", TextBox(0.41, 0.83, 0.85, 0.89)))
        var count = 0
        val start = floor((0.88 - 1.6 * (0.94 - 0.88)) * 300).toInt()
        var end = ceil((0.94 + 0.35 * (0.94 - 0.88)) * 300).toInt()
        if ((end - start) % 2 == 1) end++
        fun local(b: TextBox) = b.copy(top = (b.top * 300 - start) / (end - start), bottom = (b.bottom * 300 - start) / (end - start))
        val reader: (GamePhoneReader.Flat) -> Reading = { crop ->
            count++
            if (crop.height == 300) Reading(lines) else {
                assertTrue(crop.height < 300)
                assertEquals(end - start, crop.height)
                val box = local(upper.box!!)
                Reading(listOf(upper.copy(box = box, words = listOf(TextWord("passing", box))),
                    anchor.copy(text = if (anchorMatches) anchor.text else "around the corner", box = local(anchor.box!!))))
            }
        }
        val phone = TailRescue(clock = { 0L })
        val result = phone.read(image, reader)
        assertEquals(calls, count)
        assertEquals(1, result.lines.count { it.text == anchor.text })
        val found = result.lines.filter { it.text == upper.text }
        assertEquals(if (complete || recovered) 1 else 0, found.size)
        if (calls == 2 && !anchorMatches) {
            // Başarısız kurtarma aynı sohbete her uğrayışta yeni bir okuma başlatmaz.
            assertEquals(result.lines, phone.read(image, reader).lines)
            assertEquals(3, count)
        }
        if (recovered) {
            val line = found.single()
            assertEquals(upper.box!!.top, line.box!!.top, 1e-5)
            assertEquals(line.box, line.words!!.single().box)
        }
    }

    @Test
    fun recoversTheFaintLineAboveAConfirmedTail() = rescue(hasInk = true, complete = false, anchorMatches = true, calls = 2, recovered = true)

    @Test
    fun partialFirstReadingIsNotDoubled() =
        rescue(hasInk = true, complete = false, anchorMatches = true, calls = 2, recovered = false, partial = true)

    @Test
    fun differentTailInTheStripRecoversNothingAndIsNotRetried() =
        rescue(hasInk = true, complete = false, anchorMatches = false, calls = 2, recovered = false)

    @Test
    fun noInkAboveTheTailNeedsNoSecondRead() = rescue(hasInk = false, complete = false, anchorMatches = true, calls = 1, recovered = false)

    @Test
    fun completeReadingNeedsNoSecondRead() = rescue(hasInk = true, complete = true, anchorMatches = true, calls = 1, recovered = false)

    // MARK: balonun görünüşü

    private fun item(source: String, translation: String, box: TextBox, line: Double, surface: TextSurface) =
        ScreenTranslation.Item(source, translation, box, line, surface = surface)

    @Test
    fun selectionKeepsReadableContrastWhenOnlyTheSurfaceColorLooksStable() {
        val before = item("Call me.", "Beni ara.", TextBox(0.1, 0.2, 0.4, 0.28), 0.06, TextSurface("#686868", "#FFFFFF"))
        val selected = before.copy(surface = TextSurface("#787878", "#000000"))
        assertEquals(selected.surface, PhoneRegionSession.steady(listOf(selected), listOf(before)).single().surface)
    }

    @Test
    fun phoneAppearanceFollowsNewSourceTranslationWidthAndSelectionColor() {
        val first = item("Meet May.", "May ile buluş.", TextBox(0.1, 0.2, 0.4, 0.28), 0.06, TextSurface("#B8C0D0", "#000000"))
        val jiggled = first.copy(box = TextBox(0.11, 0.21, 0.42, 0.296), lineHeight = 0.064, surface = TextSurface("#B0B8C8", "#000000"))
        val steady = PhoneRegionSession.steady(listOf(jiggled), listOf(first)).single()
        assertEquals(jiggled.box.left, steady.box.left, 0.0)
        assertEquals(first.box.right - first.box.left, steady.box.right - steady.box.left, 1e-6)
        assertEquals(first.surface, steady.surface)
        assertEquals(first.lineHeight, steady.lineHeight, 0.0)
        val selection = jiggled.copy(surface = TextSurface("#B0B8C8", "#FFFFFF"), box = jiggled.box.copy(right = 0.49))
        val selected = PhoneRegionSession.steady(listOf(selection), listOf(steady)).single()
        assertEquals("#FFFFFF", selected.surface!!.foreground)
        assertEquals(selection.box.right, selected.box.right, 0.0)
        for (replaced in listOf(jiggled.copy(source = "Meet Chase."), jiggled.copy(translation = "May’i gör."))) {
            assertEquals(replaced, PhoneRegionSession.steady(listOf(replaced), listOf(first)).single())
        }
        assertNotEquals(first.box, jiggled.box)
    }
}
