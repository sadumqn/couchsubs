// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.util.concurrent.Executors
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Kullanıcı bildirimi (GTA 6): oyun altta "x yere git" gibi bir görev yazısı gösterirken o sırada gelen altyazıların hiçbiri
 * çevrilmiyordu. Görev satırı sabit dururken üstünde ya da altında değişen altyazıların hepsi çevrilmeli, görev hiçbir
 * altyazıya karışmamalı (Windows: ObjectiveWithDialogueTests.cs, Mac: ObjectiveWithDialogueTests.swift).
 */
class ObjectiveWithDialogueTest {
    private val objective = "Go to the bank."
    private val dialogue = listOf(
        listOf("We have to move before the cops show up."),
        listOf("I told you this was a bad idea,", "but you never listen to me."),
        listOf("Lucia: Just drive the car and stay calm."),
        listOf("Where did they take all the money?"),
        listOf("Nobody saw us leave the place.", "Keep your head down for a while."),
    )
    private val line = 0.08

    private fun row(text: String, top: Double, width: Double = 0.6) =
        TextLine(text, TextBox(0.5 - width / 2, top, 0.5 + width / 2, top + line))

    /** Görev önce tek başına ([objectiveFirst] kare), sonra her altyazı 4 kare (2 sn) görevle birlikte. */
    private fun frames(below: Boolean, gap: Double, objectiveFirst: Int): List<Reading> {
        val alone = Reading(listOf(row(objective, if (below) 0.8 else 0.2, 0.3)))
        val frames = MutableList(objectiveFirst) { alone }
        for (lines in dialogue) {
            val height = lines.size * line
            val rows = mutableListOf<TextLine>()
            if (below) {
                val top = 0.8 - gap * line - height
                lines.forEachIndexed { i, text -> rows.add(row(text, top + i * line)) }
                rows.add(row(objective, 0.8, 0.3))
            } else {
                rows.add(row(objective, 0.2, 0.3))
                val top = 0.2 + line + gap * line
                lines.forEachIndexed { i, text -> rows.add(row(text, top + i * line)) }
            }
            repeat(4) { frames.add(Reading(rows)) }
        }
        repeat(4) { frames.add(alone) }
        return frames
    }

    private class Silent : SubtitleSender {
        override fun sendSubtitle(text: String, durationMs: Int, box: TextBox?, replaces: Boolean) {}
        override fun clear() {}
    }

    private class Recording : TextTranslator {
        val requested = java.util.Collections.synchronizedList(mutableListOf<String>())
        override fun translate(text: String): String {
            requested.add(text)
            return "TR: $text"
        }
    }

    private fun run(below: Boolean, gap: Double, objectiveFirst: Int) {
        val executor = Executors.newSingleThreadExecutor { Thread(it, "test translate").apply { isDaemon = true } }
        try {
            var now = 0L
            val translator = Recording()
            val pipeline = SubtitlePipeline(translator, Silent(), { now }, executor).apply { packWait = 0; cleanWait = 0 }
            val area = TextBox(0.0, 0.0, 1.0, 1.0)
            for (reading in frames(below, gap, objectiveFirst)) {
                pipeline.process(reading, area)
                executor.submit {}.get()
                now += 500
            }
            val requested = translator.requested.toList()
            val label = "below: $below gap: $gap first: $objectiveFirst — istekler: $requested"
            // Görev ilk altyazıyla aynı anda belirince de ilk altyazı çevrilir (kısa görev satırı altyazının altında; beta.69).
            val missing = dialogue.flatten().map { it.removePrefix("Lucia: ") }.filter { text -> requested.none { it.contains(text) } }
            assertEquals("çevrilmedi — $label", emptyList<String>(), missing)
            val mixed = requested.filter { it.contains("Go to the bank") && it.trim() != objective }
                .filter { objectiveFirst != 0 || !it.contains(dialogue[0][0]) }
            assertEquals("görev karıştı — $label", emptyList<String>(), mixed)
        } finally {
            executor.shutdownNow()
        }
    }

    @Test fun everyDialogueIsTranslatedWhileObjectiveStays() {
        for ((below, gap, first) in listOf(Triple(true, 0.1, 4), Triple(true, 1.5, 4), Triple(false, 0.1, 4),
            Triple(false, 1.5, 4), Triple(true, 0.1, 20), Triple(true, 1.5, 20), Triple(false, 0.1, 20),
            Triple(true, 0.1, 0), Triple(true, 1.5, 0))) {
            run(below, gap, first)
        }
    }

    /**
     * Kullanıcı bildirimi (X, beta.69, GTA 6): konuşma sürerken altta "Follow John" görevi belirdi, o konuşma çevrilmedi.
     * Görev konuşmayla aynı anda ya da konuşma başladıktan 0,5–2 sn sonra gelir; görev altyazıdan ayrı blok ya da bitişik.
     * Konuşma çevrilir, görev altyazının yerine geçmez, görev kendi yerinde gösterilir.
     */
    @Test fun objectiveArrivingDuringDialogueDoesNotReplaceIt() {
        val goal = "Follow John"
        val spoken = listOf("I can't believe he's still alive after all that.", "We need to keep moving before they find us.")
        val goalTop = 0.8
        for ((after, gap) in listOf(0 to 1.5, 1 to 1.5, 2 to 1.5, 4 to 1.5, 0 to 0.1, 2 to 0.1, 4 to 0.1)) {
            val top = goalTop - gap * line - line
            val frames = List(8) { i ->
                Reading(if (i < after) listOf(row(spoken[0], top)) else listOf(row(spoken[0], top), row(goal, goalTop, 0.25)))
            } + List(8) { Reading(listOf(row(spoken[1], top), row(goal, goalTop, 0.25))) }
            val executor = Executors.newSingleThreadExecutor { Thread(it, "test translate").apply { isDaemon = true } }
            try {
                var now = 0L
                val translator = Recording()
                val pipeline = SubtitlePipeline(translator, Silent(), { now }, executor).apply { packWait = 0; cleanWait = 0 }
                val regions = java.util.Collections.synchronizedList(mutableListOf<CropRegion?>())
                pipeline.onMissionChanged = { regions.add(it) }
                for (reading in frames) {
                    pipeline.process(reading, TextBox(0.0, 0.0, 1.0, 1.0))
                    executor.submit {}.get()
                    now += 500
                }
                val requested = translator.requested.toList()
                val label = "after: $after gap: $gap — istekler: $requested"
                for (text in spoken) assertTrue("çevrilmedi: $text — $label", requested.any { it.contains(text) })
                // Görev tek başına altyazı olarak çevrilmedi (konuşmanın yerine geçmedi).
                assertFalse(label, requested.any { it.trim() == goal })
                // Görev kendi yerinde.
                assertTrue("görev alanı yok — $label", regions.toList().any { it != null && it.top <= goalTop && it.bottom >= goalTop + line })
            } finally {
                executor.shutdownNow()
            }
        }
    }
}
