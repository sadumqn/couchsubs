// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class PackedRereadTest {
    private class Recorder : SubtitleSender {
        val sent = Collections.synchronizedList(mutableListOf<String>())
        override fun sendSubtitle(text: String, durationMs: Int, box: TextBox?, replaces: Boolean) { sent.add(text) }
        override fun clear() {}
    }
    @Test fun recordedFragmentsDoNotReplaceSlowFullTranslation() {
        for ((full, fragment) in listOf("I'm king of the world." to "world.",
            "That he fucking passed out." to "passed", "Yo Jason, get in, get in!" to "get in!")) {
            val executor = Executors.newSingleThreadExecutor()
            val release = CountDownLatch(1)
            val started = CountDownLatch(1)
            val requested = Collections.synchronizedList(mutableListOf<String>())
            val translator = object : TextTranslator {
                override fun translate(text: String): String {
                    requested.add(text); started.countDown()
                    check(release.await(10, TimeUnit.SECONDS))
                    return "TR: $text"
                }
            }
            val sender = Recorder()
            var time = 0L
            val pipeline = SubtitlePipeline(translator, sender, { time }, executor).apply {
                holdReadings = true; packWait = 0; cleanWait = 0
                packLookup = { if (it == fragment) PackMatch("Paket parçası") else null }
            }
            try {
                repeat(4) { pipeline.process(Reading.fromText(full), CropRegion().box); time += 100 }
                assertTrue(started.await(5, TimeUnit.SECONDS))
                repeat(4) { pipeline.process(Reading.fromText(fragment), CropRegion().box); time += 100 }
                assertTrue(fragment, sender.sent.isEmpty())
                time += 3000
                release.countDown(); executor.submit {}.get(5, TimeUnit.SECONDS)
                assertEquals(fragment, listOf("TR: $full"), sender.sent)
                assertEquals(listOf(full), requested)
            } finally { release.countDown(); executor.shutdownNow() }
        }
    }
    @Test fun heldFullLineKeepsOriginalDeadline() {
        val full = "we are king of the world"
        val executor = Executors.newSingleThreadExecutor()
        val requested = Collections.synchronizedList(mutableListOf<String>())
        val translator = object : TextTranslator {
            override fun translate(text: String): String { requested.add(text); return "TR: $text" }
        }
        val sender = Recorder()
        var time = 0L
        val pipeline = SubtitlePipeline(translator, sender, { time }, executor).apply {
            holdReadings = true
            packLookup = { if (it == "world") PackMatch("Dünya") else null }
        }
        try {
            (List(2) { full } + List(6) { "world" }).forEachIndexed { index, text ->
                pipeline.process(Reading.fromText(text), CropRegion().box)
                executor.submit {}.get(5, TimeUnit.SECONDS)
                if (index == 4) assertEquals(listOf(full), requested)
                time += 100
            }
            assertEquals(listOf(full), requested)
            assertEquals(listOf("TR: $full"), sender.sent)
        } finally { executor.shutdownNow() }
    }

    @Test fun genuineShortLinesAndClearedRegionKeepImmediatePackPath() {
        for ((full, next, blank) in listOf(Triple("I swear to God, you kill me!", "You kill me!", false),
            Triple("I'm king of the world.", "world.", true),
            Triple("That he fucking passed out.", "Get down!", false),
            Triple("I have five bullets.", "I have one bullet.", false))) {
            val executor = Executors.newSingleThreadExecutor()
            val requested = Collections.synchronizedList(mutableListOf<String>())
            val translator = object : TextTranslator {
                override fun translate(text: String): String { requested.add(text); return "TR: $text" }
            }
            val sender = Recorder()
            var time = 0L
            val pipeline = SubtitlePipeline(translator, sender, { time }, executor).apply {
                holdReadings = true
                packLookup = { if (it == next) PackMatch("Yeni replik") else null }
            }
            val frames = List(4) { full } + (if (blank) List(12) { "" } else emptyList()) + List(4) { next }
            try {
                frames.forEachIndexed { index, text ->
                    pipeline.process(Reading.fromText(text), CropRegion().box)
                    executor.submit {}.get(5, TimeUnit.SECONDS)
                    if (index == frames.size - 3) assertTrue(next, sender.sent.contains("Yeni replik"))
                    time += 100
                }
                assertEquals(next, "Yeni replik", sender.sent.last())
                assertFalse(requested.contains(next))
            } finally { executor.shutdownNow() }
        }
    }

    /**
     * Temiz ama yarım görünen satır bekletilirken gelen bozuk okumalı yeni satır yok sayılıyordu; kararlayıcı onu
     * gönderilmiş saydığı için ekranda kaldığı sürece bir daha hiç çevrilmiyordu. Bekleme bitince o da çevrilmeli.
     */
    @Test fun misreadLineArrivingDuringCleanHoldIsTranslatedLater() {
        val held = "I told you to stay close"
        val next = "Where is the bóat?"
        val executor = Executors.newSingleThreadExecutor()
        val requested = Collections.synchronizedList(mutableListOf<String>())
        val translator = object : TextTranslator {
            override fun translate(text: String): String { requested.add(text); return "TR: $text" }
        }
        val sender = Recorder()
        var time = 0L
        val pipeline = SubtitlePipeline(translator, sender, { time }, executor).apply {
            holdReadings = true
            packLookup = { null }
        }
        try {
            (List(2) { held } + List(20) { next }).forEach { text ->
                pipeline.process(Reading.fromText(text), CropRegion().box)
                executor.submit {}.get(5, TimeUnit.SECONDS)
                time += 100
            }
            assertEquals(listOf(held, next), requested)
            assertEquals("TR: $next", sender.sent.last())
        } finally { executor.shutdownNow() }
    }
}
