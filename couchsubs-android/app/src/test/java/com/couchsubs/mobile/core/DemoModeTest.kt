// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.util.Collections
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

/** Deneme modu (iPhone/Mac DemoModeTests ile aynı): satırlar, zamanlama, hazır çeviri ve hattan geçiş. */
class DemoModeTest {
    private val missingModel = TextTranslator { throw IllegalStateException("model yok") }

    @Test
    fun scriptHasEnoughLinesWithoutBrands() {
        assertTrue(DemoScript.lines.size in 10..15)
        for (line in DemoScript.lines + DemoScript.objective) {
            assertTrue(line.turkish.isNotBlank())
            for (brand in listOf("PS5", "PlayStation", "Sony")) assertFalse(line.english.contains(brand))
        }
    }

    @Test
    fun scheduleShowsLinesInTurnWithGaps() {
        assertNull(DemoScript.lineIndex(500, 3000, 1000))
        assertEquals(0, DemoScript.lineIndex(1500, 3000, 1000))
        assertNull(DemoScript.lineIndex(4500, 3000, 1000))
        assertEquals(1, DemoScript.lineIndex(5500, 3000, 1000))
        assertEquals(0, DemoScript.lineIndex(1000L + 4000L * DemoScript.lines.size + 500, 3000, 1000))
    }

    @Test
    fun tableTranslatesReadingsWithOcrSlips() {
        val first = DemoScript.lines[0]
        assertEquals(first.turkish, DemoScript.translation(first.english))
        assertEquals(first.turkish, DemoScript.translation("We shou1d reach the lighthouse before dark"))
        assertNull(DemoScript.translation("Completely different text"))
    }

    @Test
    fun translatorUsesEngineAndFallsBackToTable() {
        val line = DemoScript.lines[3]
        assertEquals("motor: ${line.english}", DemoTranslator(TextTranslator { "motor: $it" }).translate(line.english))
        assertEquals(line.turkish, DemoTranslator(missingModel).translate(line.english))
        assertEquals(listOf(DemoScript.objective.turkish), DemoTranslator(missingModel).translateAll(listOf(DemoScript.objective.english)))
    }

    @Test
    fun pipelineTranslatesAndSendsADemoLine() {
        val line = DemoScript.lines[1]
        val sent = Collections.synchronizedList(mutableListOf<String>())
        val sender = object : SubtitleSender {
            override fun sendSubtitle(text: String, durationMs: Int, box: TextBox?, replaces: Boolean) { sent.add(text) }
            override fun clear() {}
        }
        val executor = Executors.newSingleThreadExecutor()
        var time = 0L
        val pipeline = SubtitlePipeline(DemoTranslator(missingModel), sender, { time }, executor).apply {
            holdReadings = true; packWait = 0; cleanWait = 0
        }
        repeat(8) {
            pipeline.process(Reading.fromText(line.english), CropRegion().box)
            time += 200
        }
        try {
            executor.submit {}.get(5, TimeUnit.SECONDS)
            assertTrue(sent.toString(), sent.any { it.contains(line.turkish) })
        } finally { executor.shutdownNow() }
    }
}
