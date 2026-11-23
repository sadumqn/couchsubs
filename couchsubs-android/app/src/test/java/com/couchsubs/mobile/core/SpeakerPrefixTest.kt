// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Mac'teki SpeakerPrefixTests ve Windows SpeakerPrefixTests ile aynı örnekler. */
class SpeakerPrefixTest {
    @Test
    fun nameIsSplitFromTheSentence() {
        assertEquals(SpeakerPrefix.Split("ARTHUR", "We need to go."), SpeakerPrefix.split("ARTHUR: We need to go."))
        assertEquals(SpeakerPrefix.Split("Dutch", "I have a plan."), SpeakerPrefix.split("Dutch: I have a plan."))
        assertEquals(SpeakerPrefix.Split("Mrs. Adler", "Leave me."), SpeakerPrefix.split("Mrs. Adler：Leave me."))
        assertEquals("OLD MAN", SpeakerPrefix.split("OLD MAN : Hm.")?.name)
        assertEquals("We go.", SpeakerPrefix.split("ARTHUR:We go.")?.body)
        assertEquals("We need to go.", SpeakerPrefix.split("Arthur:\nWe need to go.")?.body)
    }

    @Test
    fun falseMatchesAreLeftAlone() {
        for (text in listOf("10:30 at the station.", "Meet me at 10:30.", "HTTPS://example.com", "Ratio 16:9",
            "Note: the gate is shut.", "I told you: get out!", "Very Long Name Of Four: words",
            "Bartholomew Montgomeryson: Hi.", "ARTHUR:")) {
            assertNull(text, SpeakerPrefix.split(text))
        }
    }

    @Test
    fun presentAddsOrHidesTheName() {
        val source = "ARTHUR: We need to go."
        assertEquals("ARTHUR: Gitmeliyiz.", SpeakerPrefix.present("Gitmeliyiz.", source, true))
        assertEquals("Gitmeliyiz.", SpeakerPrefix.present("Gitmeliyiz.", source, false))
        assertEquals("ARTHUR: Gitmeliyiz.", SpeakerPrefix.present("ARTHUR: Gitmeliyiz.", source, true))
        assertEquals("Evet.\nHayır.", SpeakerPrefix.present("ARTHUR: Evet.\nDUTCH: Hayır.", "ARTHUR: Yes.\nDUTCH: No.", false))
        assertEquals("Hedef: Kampa dön.", SpeakerPrefix.present("Hedef: Kampa dön.", "Objective: Return to camp.", false))
    }

    /** Renkli ad cümleden ayrı okunsa da satır soldan sağa birleşir; ad sona düşmez. */
    @Test
    fun nameReadApartJoinsItsRow() {
        val reading = Reading(listOf(
            TextLine("We need to go.", TextBox(0.40, 0.501, 0.70, 0.60)),
            TextLine("ARTHUR:", TextBox(0.30, 0.50, 0.385, 0.60)),
            TextLine("9", TextBox(0.95, 0.50, 0.97, 0.60)),
        )).joiningRows()
        assertEquals(listOf("9", "ARTHUR: We need to go."), reading.lines.map { it.text }.sorted())
    }

    private class Recorder : SubtitleSender {
        val sent = mutableListOf<String>()
        override fun sendSubtitle(text: String, durationMs: Int, box: TextBox?, replaces: Boolean) {
            sent.add(text)
        }
        override fun clear() {}
    }

    private val direct = object : java.util.concurrent.AbstractExecutorService() {
        override fun execute(command: Runnable) = command.run()
        override fun shutdown() {}
        override fun shutdownNow() = mutableListOf<Runnable>()
        override fun isShutdown() = false
        override fun isTerminated() = false
        override fun awaitTermination(timeout: Long, unit: java.util.concurrent.TimeUnit) = true
    }

    /** Motora yalnız cümle gider; paket adsız anahtarla da bulunur; ayar kapalıysa ad TV'ye gitmez. */
    @Test
    fun pipelineKeepsTheNameOutOfTranslation() {
        val recorder = Recorder()
        val engine = mutableListOf<String>()
        var now = 0L
        var show = true
        val pipeline = SubtitlePipeline({ engine.add(it); "çeviri" }, recorder, { now }, direct)
        pipeline.packLookup = { if (it == "Get down!") PackMatch("Yere yat!", "rdr2") else null }
        pipeline.showSpeakerNames = { show }
        val area = CropRegion().box
        pipeline.process(Reading.fromText("ARTHUR: We need to go."), area)
        now += 100
        pipeline.process(Reading.fromText("Dutch: Get down!"), area)
        now += 100
        show = false
        pipeline.process(Reading.fromText("ARTHUR: Who goes there?"), area)
        assertEquals(listOf("We need to go.", "Who goes there?"), engine)
        assertEquals(listOf("ARTHUR: çeviri", "Dutch: Yere yat!", "çeviri"), recorder.sent)
    }
}
