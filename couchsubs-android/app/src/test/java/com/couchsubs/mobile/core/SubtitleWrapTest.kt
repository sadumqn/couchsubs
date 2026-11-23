// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mac ve Windows ile aynı kurallar (SubtitleWrapTests.swift, SubtitleWrapTests.cs). */
class SubtitleWrapTest {
    @Test fun shortTextIsUntouched() {
        assertEquals(SubtitleWrap.Result("Gitmeliyiz, hemen.", 1f), SubtitleWrap.fit("Gitmeliyiz, hemen."))
    }

    @Test fun longTextSplitsIntoTwoBalancedLines() {
        val text = "Bu işin sonunda hepimiz için bir çıkış yolu bulmamız gerekiyor artık"
        val result = SubtitleWrap.fit(text)
        val lines = result.text.split("\n")
        assertEquals(2, lines.size)
        assertEquals(1f, result.scale)
        assertTrue(Math.abs(lines[0].length - lines[1].length) <= 12)
        assertEquals(text, lines.joinToString(" "))
    }

    @Test fun veryLongTextUsesAtMostThreeLinesAndShrinks() {
        val result = SubtitleWrap.fit(List(30) { "kelime" }.joinToString(" "))
        assertEquals(3, result.text.split("\n").size)
        assertTrue(result.scale < 1f && result.scale >= SubtitleWrap.MIN_SCALE.toFloat())
    }

    @Test fun speakerNameStaysOnFirstLineWithText() {
        val result = SubtitleWrap.fit("ARTHUR: We need to leave before they find us here in the middle of the night, understand?")
        val first = result.text.split("\n")[0]
        assertTrue(first, first.startsWith("ARTHUR: "))
        assertTrue(first.length > "ARTHUR:".length)
    }

    @Test fun existingBreaksAreKept() {
        val text = "Birinci satır uzun uzun uzun uzun\nİkinci satır da oldukça uzun bir satır"
        assertEquals(text, SubtitleWrap.fit(text).text)
    }
}
