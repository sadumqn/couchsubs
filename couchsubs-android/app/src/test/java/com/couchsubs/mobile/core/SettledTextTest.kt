// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.util.Collections
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * PS5'in Türkçe ana ekranı (beta.89, Mac): Türkçe harfleri düz okunan menü satırı çevrilmez ve paketle eşleşmez, bozuk
 * okunmuş parçası ("One [Ikan Ipufl") altyazı sayılmaz, değişmeyen ekranda aynı satır yeniden işlenmez. Ortak deneme
 * dosyası fixtures/settled-text.json (core/Tests/CouchSubsCoreTests/Fixtures kopyası; Mac SettledTextTests.swift ve
 * Windows SettledTextTests.cs aynı dosyayı okur).
 */
class SettledTextTest {
    private val root = JSONObject(Fixtures.text("settled-text.json"))

    private fun objects(array: JSONArray) = (0 until array.length()).map { array.getJSONObject(it) }

    private fun box(item: JSONObject, key: String): TextBox? {
        val values = item.optJSONArray(key) ?: return null
        return TextBox(values.getDouble(0), values.getDouble(1), values.getDouble(2), values.getDouble(3))
    }

    @Test fun turkishMenuLines() {
        for (vector in objects(root.getJSONArray("turkish"))) {
            val text = vector.getString("text")
            assertEquals(text, vector.getBoolean("turkish"), TurkishText.looksTurkish(text))
        }
    }

    @Test fun bracketGarbledReadings() {
        for (vector in objects(root.getJSONArray("bracket"))) {
            val text = vector.getString("text")
            assertEquals(text, vector.getBoolean("garbled"), OcrNoise.looksBracketGarbled(text))
        }
    }

    @Test fun fragmentsOfTargetLanguageBlock() {
        for (vector in objects(root.getJSONArray("fragment"))) {
            val settled = SettledText()
            settled.settle(vector.getString("target"), box(vector, "box"), target = true, shown = false, time = 0)
            for (item in objects(vector.getJSONArray("cases"))) {
                val text = item.getString("text")
                assertEquals(text, item.getBoolean("fragment"), settled.isTargetFragment(text, box(item, "box")))
            }
        }
    }

    @Test fun settledLinesStayQuietWhileOnScreen() {
        for (vector in objects(root.getJSONArray("settle"))) {
            val name = vector.getString("name")
            val settled = SettledText()
            for (step in objects(vector.getJSONArray("steps"))) {
                val time = step.getLong("time")
                step.optJSONArray("observe")?.let { lines -> settled.observe((0 until lines.length()).map { lines.getString(it) }, time) }
                if (step.has("settle")) {
                    settled.settle(step.getString("settle"), null, step.getBoolean("target"), step.getBoolean("shown"), time,
                        step.getBoolean("loose"))
                }
                if (step.has("ask")) {
                    val asked = step.getString("ask")
                    assertEquals("$name: $asked", step.getBoolean("settled"), settled.isSettled(asked))
                }
            }
        }
    }

    private class Sender : SubtitleSender {
        val sent: MutableList<String> = Collections.synchronizedList(mutableListOf())
        override fun sendSubtitle(text: String, durationMs: Int, box: TextBox?, replaces: Boolean) { sent.add(text) }
        override fun clear() {}
    }

    /**
     * Mac altyazi.log'undaki döngü: menü satırları sırayla seçilir, hiçbiri çevirmene ya da TV'ye gitmez, paketteki bozuk
     * parça gösterilmez, her satır günlüğe en çok bir kez düşer.
     */
    @Test fun turkishMenuLoopStaysQuiet() {
        val vector = root.getJSONObject("pipeline")
        val pack = vector.getString("pack")
        val packText = vector.getString("packText")
        val shown = objects(vector.getJSONArray("frames")).map { it.getString("text") to it.getInt("count") }
        val frames = mutableListOf<String>()
        repeat(vector.getInt("cycles")) { for ((text, count) in shown) repeat(count) { frames += text } }
        val requested = Collections.synchronizedList(mutableListOf<String>())
        val log = Collections.synchronizedList(mutableListOf<String>())
        val sender = Sender()
        val executor = Executors.newSingleThreadExecutor()
        var now = 0L
        val pipeline = SubtitlePipeline({ requested.add(it); "TR: $it" }, sender, { now }, executor)
        pipeline.packLookup = { if (it == pack) PackMatch(packText) else null }
        pipeline.onLog = { log.add(it) }
        for (frame in frames) {
            pipeline.process(Reading.fromText(frame), CropRegion().box)
            now += 100
        }
        executor.shutdown()
        assertTrue(executor.awaitTermination(30, TimeUnit.SECONDS))
        assertEquals(emptyList<String>(), requested.toList())
        assertEquals(emptyList<String>(), sender.sent.toList())
        assertFalse(log.any { it.contains("→ paket") })
        for ((text, _) in shown) {
            val excerpt = "\"$text\""
            assertTrue(text + "\n" + log.joinToString("\n"), log.count { it.contains(excerpt) && it.contains("çevrilmedi") } <= 1)
        }
    }
}
