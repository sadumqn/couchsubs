// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NumericGlyphTest {
    @Test
    fun numberChangesAreNotHiddenByLettersElsewhere() {
        for ((reread, sent) in listOf(
            "I have 1 bullet left." to "I have 5 bullets left.",
            "I have 1 bullet left." to "I have 5 bullet left.",
            "1 have 1 bullet left." to "I have 5 bullets left.",
            "I need 1 more key." to "I need more keys.",
            "I have 1 and 1 left." to "I have 1 left.",
            "I have 1 and 1 left." to "I have 1 and 5 left.",
            "O, we have 0 keys left." to "O, we have 5 keys left.",
            "I have 10 keys left." to "I have 5 keys left.",
            "I have 1 key left." to "I have\n5 keys left.",
        )) {
            assertTrue(reread, TextMatch.addsMeaning(reread, sent))
            assertFalse(reread, TextMatch.isSameSubtitle(TextMatch.normalize(reread), TextMatch.normalizeRows(sent)))
            assertFalse(reread, TextMatch.isWorseReread(reread, sent))
        }
    }

    @Test
    fun alignedLetterDigitNoiseDoesNotAddANumber() {
        for ((reread, sent) in listOf(
            "1 can do that." to "I can do that.",
            "0, we should leave now." to "O, we should leave now.",
            "Now 1 can do that." to "Now I can do that.",
            "Ycs 1 can do thal." to "Yes I can do that.",
            "Yes 1 can do that." to "Well I can do that.",
            "1 can do that now." to "I can do that.",
            "Now 1 can do that." to "I can do that.",
            "1 have 1 key left." to "I have 1 key left.",
            "1 said 1 can do that." to "I said I can do that.",
            "1 have 5 keys left." to "I have 5 keys left.",
        )) assertFalse(reread, TextMatch.addsMeaning(reread, sent))
    }

    @Test
    fun stabilizerSendsNumericCorrectionButNotLetterNoise() {
        val s = SubtitleStabilizer()
        val first = "I have 5 bullets left."
        val corrected = "I have 1 bullet left."
        assertEquals(StabilizerAction.translate(first), s.feed(first))
        assertEquals(StabilizerAction.None, s.feed("1 have 5 bullets left."))
        assertEquals(StabilizerAction.translate(corrected), s.feed(corrected))
        assertEquals(StabilizerAction.None, s.feed("1 have 1 bullet left."))
    }
}
