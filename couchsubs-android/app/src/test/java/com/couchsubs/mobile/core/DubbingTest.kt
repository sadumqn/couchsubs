// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import com.couchsubs.mobile.service.PhoneDubber
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Telefonda Türkçe dublaj: ses dağıtımı Swift VoiceCast ile, sesin tonu Windows "Hızlı" dublajıyla aynı. */
class DubbingTest {
    @Test
    fun systemTonesMatchTheDesktop() {
        // Windows WindowsVoiceModel.Tone ve Swift DubbingVoice.systemTone.
        assertEquals(listOf(1.55f to 1.1f, 1.4f to 1.0f, 1.48f to 1.05f, 0.85f to 0.95f, 1.05f to 1.15f, 0.95f to 1.05f),
            DubbingVoice.entries.map { it.pitch to it.rate })
        assertEquals(listOf("female_1", "female_2", "female_3", "male_1", "male_2", "male_3"), DubbingVoice.entries.map { it.id })
    }

    @Test
    fun speakersKeepTheirVoiceAndGenderIsGuessed() {
        val cast = VoiceCast()
        val kratos = cast.voiceFor(SpokenLine("KRATOS: Boy.", "Evlat.", "KRATOS"))
        val freya = cast.voiceFor(SpokenLine("FREYA: No.", "Hayır.", "FREYA"))
        assertTrue(!kratos.female && kratos != cast.narrator)
        assertTrue(freya.female)
        assertEquals(kratos, cast.voiceFor(SpokenLine("Kratos: Again.", "Yine.", "Kratos")))
        assertEquals(kratos, VoiceCast.fromJson(cast.toJson()).assignments["KRATOS"])
    }

    @Test
    fun dialogueDashesAlternateNarratorAndPartner() {
        val cast = VoiceCast()
        assertEquals(cast.narrator, cast.voiceFor(SpokenLine("Go.", "Git.")))
        assertEquals(cast.partner, cast.voiceFor(SpokenLine("- Wait!", "Bekle!", newTurn = true)))
        assertEquals(cast.narrator, cast.voiceFor(SpokenLine("- Now.", "Şimdi.", newTurn = true)))
    }

    @Test
    fun spokenLinesDropTheSpeakerNameAndSplitDashes() {
        assertEquals(listOf(SpokenLine("ARTHUR: We need to go.", "Gitmeliyiz.", "ARTHUR")),
            SpokenLine.of("ARTHUR: We need to go.", "ARTHUR: Gitmeliyiz."))
        val dialogue = SpokenLine.of("- Go.\n- Wait!", "- Git.\n- Bekle!")
        assertEquals(listOf("Git.", "Bekle!"), dialogue.map { it.turkish })
        assertTrue(dialogue.all { it.newTurn && it.speaker == null })
    }

    @Test
    fun wavDurationIsReadFromTheHeader() {
        // 16 kHz, 16 bit, tek kanal: saniyede 32000 bayt; 16000 bayt = 500 ms.
        val wav = SpeechWav.pcm16(ShortArray(8000), 16000)
        assertEquals(500, PhoneDubber.wavDurationMs(wav))
        assertNull(PhoneDubber.wavDurationMs(ByteArray(10)))
    }
}

/** Denemeler için en küçük PCM WAV. */
object SpeechWav {
    fun pcm16(samples: ShortArray, rate: Int): ByteArray {
        val data = samples.size * 2
        val out = java.nio.ByteBuffer.allocate(44 + data).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        out.put("RIFF".toByteArray()).putInt(36 + data).put("WAVE".toByteArray())
        out.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1).putInt(rate).putInt(rate * 2).putShort(2).putShort(16)
        out.put("data".toByteArray()).putInt(data)
        samples.forEach { out.putShort(it) }
        return out.array()
    }
}
