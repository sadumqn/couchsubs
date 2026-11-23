// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Test

/** "Bozuk okunan satır için bekleme" ve "Yarım okunan satır için bekleme" (Windows, Mac ve iPhone ile aynı sınırlar). */
class ReadingWaitSettingsTest {
    private val pipeline = SubtitlePipeline(
        object : TextTranslator { override fun translate(text: String) = text },
        object : SubtitleSender {
            override fun sendSubtitle(text: String, durationMs: Int, box: TextBox?, replaces: Boolean) {}
            override fun clear() {}
        },
    )

    @Test
    fun defaultsMatchTheOtherPlatforms() {
        assertEquals(800, pipeline.packWait)
        assertEquals(300, pipeline.cleanWait)
        assertEquals(1000, SubtitlePipeline.WAIT_SLIDER_MAX_MS)
    }

    @Test
    fun waitsAreAppliedWithinLimits() {
        pipeline.applyWaits(600, 100)
        assertEquals(600, pipeline.packWait)
        assertEquals(100, pipeline.cleanWait)
        pipeline.applyWaits(-5, 99_000)
        assertEquals(0, pipeline.packWait)
        assertEquals(SubtitlePipeline.MAX_WAIT_MS, pipeline.cleanWait)
    }
}
