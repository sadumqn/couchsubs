// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class QueuedRevisionTest {
    private val blocker = "Hold the gate."
    private val full = "Huh? Jumping out of airplanes, flying like birds? Fuck, that is crazy."
    private val short = "Huh? Jumping out of airplanes, flying like birds?"
    private fun replay(readings: List<String>): List<String> {
        val executor = Executors.newSingleThreadExecutor()
        val release = CountDownLatch(1)
        val started = CountDownLatch(1)
        val requested = Collections.synchronizedList(mutableListOf<String>())
        val sent = Collections.synchronizedList(mutableListOf<String>())
        val translator = object : TextTranslator {
            override fun translate(text: String): String {
                requested.add(text); started.countDown()
                check(release.await(5, TimeUnit.SECONDS))
                return "Çeviri: ${requested.size}"
            }
        }
        val sender = object : SubtitleSender {
            override fun sendSubtitle(text: String, durationMs: Int, box: TextBox?, replaces: Boolean) { sent.add(text) }
            override fun clear() {}
        }
        var time = 0L
        val pipeline = SubtitlePipeline(translator, sender, { time }, executor).apply {
            holdReadings = true; packWait = 0; cleanWait = 0
        }
        try {
            (listOf(blocker) + readings).forEachIndexed { index, text ->
                pipeline.process(Reading.fromText(text), CropRegion().box)
                if (index == 0) assertTrue(started.await(5, TimeUnit.SECONDS))
                time += 100
            }
            release.countDown(); executor.submit {}.get(5, TimeUnit.SECONDS)
            assertEquals(requested.size, sent.size)
            return requested.toList()
        } finally { release.countDown(); executor.shutdownNow() }
    }
    @Test fun shorterReadingDoesNotEraseQueuedFullLine() {
        assertEquals(listOf(blocker, full, short), replay(listOf(full, short)))
        assertEquals(listOf(blocker, full), replay(listOf(full, short, full)))
    }
    @Test fun genuineShortLineKeepsBothQueuedUtterances() {
        for ((full, short) in listOf("Run! Wait here." to "Run!",
            "I swear to God, you kill me!" to "You kill me!",
            "Hold your fire until I return." to "Get down!")) {
            assertEquals(listOf(blocker, full, short), replay(listOf(full, short)))
        }
    }
    @Test fun correctedReadingReplacesOlderQueuedReading() {
        for ((old, corrected) in listOf("We have 5 minutes left." to "We have 1 minute left.",
            "Meet me at 06:40." to "Meet me at 06:50.",
            "I can do that for you right now." to "I can't do that for you right now.",
            "We have time to wait." to "We have no time to wait.",
            "We do not have..." to "We do not have time.")) {
            assertEquals(listOf(blocker, corrected), replay(listOf(old, corrected)))
        }
    }
    @Test fun fullReadingReturningAfterRestoreWindowStillCoalescesTheQueue() {
        assertEquals(listOf(blocker, full), replay(listOf(full) + List(18) { short } + full))
    }
    @Test fun confirmedBlankKeepsTheInterveningShortUtterance() {
        assertEquals(listOf(blocker, full, short), replay(listOf(full, short) + List(12) { "" } + full))
    }
}
