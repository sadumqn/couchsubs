// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * "Ekranı çevir" yerleşimi ([ScreenFit]): kutu simgeye taşmaz, eş öğeler aynı boyda, sütun/şerit hizası. Ortak deneme
 * dosyası fixtures/screen-fit.json (Mac ScreenFitTests.swift ve Windows ScreenFitTests.cs aynı vakalar).
 */
class ScreenFitTest {
    private val fixture = JSONObject(Fixtures.text("screen-fit.json"))

    private fun doubles(array: JSONArray) = (0 until array.length()).map { array.getDouble(it) }

    @Test
    fun sharedVectors() {
        val width = fixture.getInt("width")
        val height = fixture.getInt("height")
        val tolerance = fixture.getDouble("tolerance")
        val background = fixture.getString("background")
        val ink = fixture.getString("ink")
        val ground = background.substring(1).toInt(16)
        val inkColor = ink.substring(1).toInt(16)
        val cases = fixture.getJSONArray("cases")
        for (c in 0 until cases.length()) {
            val vector = cases.getJSONObject(c)
            val rgb = IntArray(width * height) { ground }
            val rects = vector.getJSONArray("rects")
            for (r in 0 until rects.length()) {
                val v = doubles(rects.getJSONArray(r))
                for (y in (v[1] * height).roundToInt() until (v[3] * height).roundToInt())
                    for (x in (v[0] * width).roundToInt() until (v[2] * width).roundToInt()) rgb[y * width + x] = inkColor
            }
            val luma = ByteArray(rgb.size) { i ->
                val p = rgb[i]
                ((299 * ((p shr 16) and 255) + 587 * ((p shr 8) and 255) + 114 * (p and 255)) / 1000).toByte()
            }
            val frame = GrayFrame(luma, width, height)
            val raw = vector.getJSONArray("items")
            val items = (0 until raw.length()).map { k ->
                val entry = raw.getJSONObject(k)
                val b = doubles(entry.getJSONArray("box"))
                ScreenTranslation.Item(entry.getString("name"), entry.getString("name"), TextBox(b[0], b[1], b[2], b[3]),
                    entry.getDouble("line"), surface = TextSurface(background, ink, true), look = TextLook(true, false, "left", true))
            }
            val fitted = ScreenFit.fitted(items, frame) { x, y -> rgb[y * width + x] }
            val expect = vector.getJSONArray("expect")
            assertEquals(expect.length(), fitted.size)
            for (k in 0 until expect.length()) {
                val want = expect.getJSONObject(k)
                val have = fitted[k]
                val name = "${vector.getString("id")} ${raw.getJSONObject(k).getString("name")}"
                assertEquals(name, want.getString("align"), have.look!!.align)
                assertEquals(name, want.getDouble("line"), have.lineHeight, tolerance)
                close("$name kutu", doubles(want.getJSONArray("box")), have.box)
                assertNotNull("$name alan yok", have.room)
                close("$name alan", doubles(want.getJSONArray("room")), have.room!!)
            }
        }
    }

    private fun close(name: String, want: List<Double>, have: TextBox) {
        val h = listOf(have.left, have.top, have.right, have.bottom)
        for (i in 0 until 4) assertTrue("$name: $h ≠ $want", abs(want[i] - h[i]) <= fixture.getDouble("tolerance"))
    }

    /**
     * Önbellekteki yazı anında: menü başlığı önceki oturumdan önbellekte, görev açıklaması yeni. Önbellekteki grup çeviri
     * isteği gitmeden çizilir; çevirmene yalnız yeni yazı gider (Mac ScreenFitTests, Windows ScreenFitTests ile aynı).
     */
    @Test
    fun cachedScreenTextIsDrawnBeforeTheRequest() {
        val reading = Reading(listOf(
            TextLine("ISLAND DREAMS", TextBox(0.18, 0.19, 0.35, 0.24)),
            TextLine("Keep an eye on the bachelor party while searching for treasure.", TextBox(0.14, 0.27, 0.46, 0.31)),
        ))
        var latest: List<ScreenTranslation.Item> = emptyList()
        var drawnWhileAsking: List<ScreenTranslation.Item> = emptyList()
        val asked = mutableListOf<String>()
        val translator = object : TextTranslator {
            override fun translate(text: String) = "yeni gelen çeviri"
            override val translatesTogether: Boolean get() = true
            override fun cachedTranslation(text: String) = if (text == "ISLAND DREAMS") "ADA HAYALLERİ" else null
            override fun translateAll(texts: List<String>): List<String> {
                asked += texts
                drawnWhileAsking = latest
                return texts.map { "yeni gelen çeviri" }
            }
        }
        val final = ScreenTranslation.translate(reading, translator, progress = { latest = it })
        assertTrue(drawnWhileAsking.any { it.translation == "ADA HAYALLERİ" })
        assertTrue("ISLAND DREAMS" !in asked)
        assertTrue(final.any { it.translation == "yeni gelen çeviri" })
        assertTrue(final.any { it.translation == "ADA HAYALLERİ" })
    }

    /** Çizicilerin ortak satır yerleşimi (fixtures/screen-fit.json → lines; Mac ve Windows aynı vakalar). */
    @Test
    fun sharedLineVectors() {
        val list = fixture.getJSONArray("lines")
        for (k in 0 until list.length()) {
            val vector = list.getJSONObject(k)
            val room = vector.optJSONArray("room")?.let { it.getDouble(0) to it.getDouble(1) }
            val got = ScreenFit.lines(vector.getString("text"), vector.getDouble("left"), vector.getDouble("width"), room,
                vector.getInt("rows"), vector.getString("align")) { it.length * 10.0 }
            val want = vector.getJSONObject("expect")
            val name = vector.getString("id")
            val lines = want.getJSONArray("lines")
            assertEquals(name, (0 until lines.length()).map { lines.getString(it) }, got.lines)
            assertEquals(name, want.getDouble("squeeze"), got.squeeze, 0.001)
            assertEquals(name, want.getDouble("left"), got.left, 0.01)
            assertEquals(name, want.getDouble("width"), got.width, 0.01)
        }
    }
}
