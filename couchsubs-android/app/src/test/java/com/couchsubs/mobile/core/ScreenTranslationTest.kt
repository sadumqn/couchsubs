// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import com.couchsubs.mobile.translation.AiModel
import com.couchsubs.mobile.translation.AiProvider
import com.couchsubs.mobile.translation.AiRequest
import com.couchsubs.mobile.translation.AiTranslator
import com.couchsubs.mobile.translation.Http
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** "Ekranı çevir": ekranın tamamındaki yazılar yerlerine göre gruplanır (Mac/iPhone ScreenTranslationTests.swift ile aynı). */
class ScreenTranslationTest {
    private fun line(text: String, left: Double, top: Double, right: Double, height: Double = 0.03) =
        TextLine(text, TextBox(left, top, right, top + height))

    @Test
    fun linesFarApartBecomeSeparateGroups() {
        val groups = ScreenTranslation.groups(Reading(listOf(
            line("Find the blacksmith in", 0.05, 0.10, 0.30),
            line("the village square", 0.05, 0.135, 0.25),
            line("Press the lever to open the gate.", 0.40, 0.85, 0.60),
            line("New item unlocked", 0.75, 0.60, 0.95),
        )))
        assertEquals(
            listOf(listOf("Find the blacksmith in the village square"), listOf("New item unlocked"), listOf("Press the lever to open the gate.")),
            groups.map { it.paragraphs },
        )
        assertEquals(0.165, groups[0].box.bottom, 1e-6)
        assertEquals(0.03, groups[0].lineHeight, 1e-6)
    }

    @Test
    fun linesOnTheSameRowButFarApartAreSeparate() {
        assertEquals(2, ScreenTranslation.groups(Reading(listOf(line("Settings", 0.05, 0.05, 0.15), line("Back to menu", 0.80, 0.05, 0.95)))).size)
    }

    @Test
    fun menuLinesAreTranslatedOneByOne() {
        val groups = ScreenTranslation.groups(Reading(listOf(
            line("Map", 0.05, 0.30, 0.15), line("Inventory", 0.05, 0.34, 0.20), line("Settings", 0.05, 0.38, 0.18),
        )))
        assertEquals(listOf(listOf("Map", "Inventory", "Settings")), groups.map { it.paragraphs })
    }

    @Test
    fun titleInBigLettersIsNotMergedWithTheSmallTextBelow() {
        val groups = ScreenTranslation.groups(Reading(listOf(
            line("Chapter One", 0.30, 0.20, 0.70, height = 0.08),
            line("The journey begins in the north.", 0.30, 0.29, 0.70),
        )))
        assertEquals(2, groups.size)
    }

    @Test fun fullWidthHeadingDoesNotAbsorbOneOfTwoColumns() {
        for (reversed in listOf(false, true)) {
            val lines = listOf(line("Available missions", 0.05, 0.10, 0.95),
                line("Find the blacksmith in", 0.05, 0.14, 0.43), line("Bring the medicine to", 0.57, 0.14, 0.95),
                line("the village square.", 0.05, 0.18, 0.40), line("the northern camp.", 0.57, 0.18, 0.92))
            val groups = ScreenTranslation.groups(Reading(if (reversed) lines.reversed() else lines))
            assertEquals(3, groups.size)
            assertTrue(groups.any { it.paragraphs == listOf("Available missions") && kotlin.math.abs(it.box.bottom - 0.13) < 1e-6 })
            assertTrue(groups.any { it.paragraphs == listOf("Find the blacksmith in the village square.") && it.box.right < 0.5 })
            assertTrue(groups.any { it.paragraphs == listOf("Bring the medicine to the northern camp.") && it.box.left > 0.5 })
        }
    }

    @Test fun fullWidthFooterDoesNotJoinEitherColumn() {
        for (reversed in listOf(false, true)) {
            val lines = listOf(line("Find the blacksmith in", 0.05, 0.14, 0.43), line("Bring the medicine to", 0.57, 0.14, 0.95),
                line("the village square.", 0.05, 0.18, 0.40), line("the northern camp.", 0.57, 0.18, 0.92),
                line("Choose a destination", 0.05, 0.22, 0.95))
            val groups = ScreenTranslation.groups(Reading(if (reversed) lines.reversed() else lines))
            assertEquals(3, groups.size)
            assertTrue(groups.any { it.paragraphs == listOf("Choose a destination") && kotlin.math.abs(it.box.top - 0.22) < 1e-6 })
            assertTrue(groups.any { it.paragraphs == listOf("Find the blacksmith in the village square.") })
            assertTrue(groups.any { it.paragraphs == listOf("Bring the medicine to the northern camp.") })
        }
    }

    @Test fun wrappedParagraphKeepsNarrowOrIndentedContinuation() {
        for ((left, right) in listOf(0.05 to 0.4, 0.30 to 0.70, 0.60 to 0.95)) {
            val groups = ScreenTranslation.groups(Reading(listOf(line("Find the blacksmith in", 0.05, 0.10, 0.95),
                line("the village square.", left, 0.14, right))))
            assertEquals(listOf(listOf("Find the blacksmith in the village square.")), groups.map { it.paragraphs })
        }
    }

    @Test fun nearbyUnrelatedColumnDoesNotDetachTheLocalHeading() {
        val groups = ScreenTranslation.groups(Reading(listOf(line("Current objective", 0.05, 0.10, 0.43),
            line("Find the blacksmith in", 0.05, 0.14, 0.43), line("Bring the medicine to", 0.57, 0.14, 0.95),
            line("the village square.", 0.05, 0.18, 0.40), line("the northern camp.", 0.57, 0.18, 0.92))))
        assertEquals(2, groups.size)
        assertTrue(groups.any { it.paragraphs == listOf("Current objective", "Find the blacksmith in the village square.") })
    }

    @Test fun filteredControllerPromptDoesNotCreateAColumnBoundary() {
        val groups = ScreenTranslation.groups(Reading(listOf(line("Find the blacksmith in", 0.05, 0.10, 0.95),
            line("the village square.", 0.05, 0.14, 0.43), line("R2 Swing", 0.57, 0.14, 0.95))))
        assertEquals(listOf(listOf("Find the blacksmith in the village square.")), groups.map { it.paragraphs })
    }

    @Test fun separatingTheHeadingKeepsTranslationInputsAndText() {
        val requested = mutableListOf<String>()
        val items = ScreenTranslation.translateGroups(Reading(listOf(line("Available missions", 0.05, 0.10, 0.95),
            line("Find the blacksmith in", 0.05, 0.14, 0.43), line("Bring the medicine to", 0.57, 0.14, 0.95),
            line("the village square.", 0.05, 0.18, 0.40), line("the northern camp.", 0.57, 0.18, 0.92))),
            { requested.add(it); "Türkçe sonuç ${requested.size}" })
        assertEquals(listOf("Available missions", "Find the blacksmith in the village square.", "Bring the medicine to the northern camp."), items.map { it.source })
        assertEquals(items.map { it.source }, requested)
        assertEquals(listOf("Türkçe sonuç 1", "Türkçe sonuç 2", "Türkçe sonuç 3"), items.map { it.translation })
    }

    /**
     * Silah menüsü: iki sütunda aralıklı etiketler, altta bilgi kutusu. Son satır, üstteki satırın altındaki boşluk satır
     * yüksekliğinin %90'ı olunca ayrı grup oluyor, 31. grup olduğu için de hiç çevrilmiyordu (Windows: LoadoutMenu).
     */
    private fun loadoutMenu(labels: Int): List<TextLine> {
        val lines = (0 until labels).map { i ->
            val (left, right) = if (i % 2 == 0) 0.05 to 0.20 else 0.78 to 0.95
            line("Weapon slot ${'A' + i % 26}$i", left, 0.04 + (i / 2) * 0.045, right, 0.02)
        }.toMutableList()
        lines += line("Weapons lost during a mission can be", 0.30, 0.75, 0.70, 0.025)
        lines += line("recovered from a weapon locker.", 0.30, 0.7975, 0.62, 0.025)
        return lines
    }

    @Test
    fun lastLineOfAnInfoBoxIsNotLeftOut() {
        val groups = ScreenTranslation.groups(Reading(loadoutMenu(29)))
        assertTrue(groups.any { it.paragraphs == listOf("Weapons lost during a mission can be recovered from a weapon locker.") })
        assertFalse(groups.any { "recovered from a weapon locker." in it.paragraphs })
    }

    @Test
    fun crowdedScreenKeepsTheGroupsWithTheMostText() {
        val groups = ScreenTranslation.groups(Reading(loadoutMenu(40)))
        assertEquals(ScreenTranslation.MAX_GROUPS, groups.size)
        assertEquals(listOf("Weapons lost during a mission can be recovered from a weapon locker."), groups.last().paragraphs)
        assertEquals(groups.map { it.box.top }.sorted(), groups.map { it.box.top })
    }

    @Test
    fun lowercaseLineAfterAFinishedSentenceFarBelowStaysSeparate() {
        val groups = ScreenTranslation.groups(Reading(listOf(
            line("Weapons can be recovered.", 0.30, 0.75, 0.70, 0.025),
            line("then continue on later", 0.30, 0.7975, 0.62, 0.025),
            line("and this one is far below", 0.30, 0.88, 0.62, 0.025),
        )))
        assertEquals(3, groups.size)
    }

    @Test
    fun numbersAndPromptsAreNotTranslated() {
        val groups = ScreenTranslation.groups(Reading(listOf(
            line("23m", 0.50, 0.05, 0.55), line("9", 0.90, 0.05, 0.92), line("R2 Swing", 0.80, 0.90, 0.95), line("HP 120/300", 0.05, 0.90, 0.20),
        )))
        assertEquals(listOf(listOf("HP 120/300")), groups.map { it.paragraphs })
    }

    @Test
    fun everyGroupIsTranslatedAndProgressIsReported() {
        val reported = mutableListOf<Int>()
        val items = ScreenTranslation.translateGroups(Reading(listOf(
            line("Find the blacksmith.", 0.05, 0.10, 0.30),
            line("Bring him three iron bars.", 0.05, 0.135, 0.30),
            line("KRATOS", 0.60, 0.50, 0.70),
            line("Leave the camp", 0.60, 0.80, 0.90),
        )), { if (it == "KRATOS") it else "TR: $it" }, progress = { reported.add(it.size) })
        assertEquals(listOf("TR: Find the blacksmith.\nTR: Bring him three iron bars.", "TR: Leave the camp"), items.map { it.translation })
        assertTrue(items[0].paragraphs)
        assertFalse(items[1].paragraphs)
        assertEquals(listOf(1, 2), reported)
    }

    @Test
    fun displayTimeGrowsWithTextButIsBounded() {
        val item = { length: Int -> ScreenTranslation.Item("a", "a".repeat(length), TextBox(0.0, 0.0, 1.0, 1.0), 0.03) }
        assertEquals(12000, ScreenTranslation.displayMilliseconds(listOf(item(0))))
        assertEquals(18000, ScreenTranslation.displayMilliseconds(listOf(item(200))))
        assertEquals(60000, ScreenTranslation.displayMilliseconds(listOf(item(5000))))
    }

    @Test
    fun screenEventIsSentToTheTvWithBoxLineAndParagraphs() {
        val items = listOf(
            ScreenTranslation.Item("Map\nInventory", "Harita\nEnvanter", TextBox(0.05, 0.30, 0.20, 0.42), 0.03),
            ScreenTranslation.Item("Leave", "Ayrıl", TextBox(0.6, 0.8, 0.9, 0.83), 0.03),
        )
        val json = JSONObject(SubtitleServer.screenFrame(items, 12000).substringAfter("data: ").trim())
        assertEquals(12000, json.getInt("duration"))
        val list = json.getJSONArray("items")
        assertEquals("Harita\nEnvanter", list.getJSONObject(0).getString("text"))
        assertTrue(list.getJSONObject(0).getBoolean("paragraphs"))
        assertEquals(0.03, list.getJSONObject(0).getDouble("line"), 1e-9)
        assertEquals(0.05, list.getJSONObject(0).getJSONObject("box").getDouble("left"), 1e-9)
        assertFalse(list.getJSONObject(1).has("paragraphs"))
        assertTrue(SubtitleServer.screenFrame(items, 12000).startsWith("event: screen\n"))
    }

    // --- Yapay zekâda tek istek ---

    /** Gelen JSON dizisindeki her yazıya "[tr] " ekleyerek Gemini biçiminde yanıtlayan sahte hizmet. */
    private class FakeGemini(var status: Int = 200) : Http {
        val requests = mutableListOf<JSONObject>()
        override fun send(method: String, url: String, headers: Map<String, String>, body: String?, timeoutMs: Int): Pair<Int, String> {
            val json = JSONObject(body!!)
            requests.add(json)
            if (status != 200) return status to "{}"
            val user = json.getJSONArray("contents").getJSONObject(0).getJSONArray("parts").getJSONObject(0).getString("text")
            val sources = JSONArray(user.substring(user.indexOf('[')))
            val reply = JSONArray((0 until sources.length()).map { "[tr] " + sources.getString(it) })
            val text = JSONObject().put("text", reply.toString())
            return 200 to JSONObject().put("candidates", JSONArray().put(JSONObject().put("content",
                JSONObject().put("parts", JSONArray().put(text))))).toString()
        }
    }

    private val texts = listOf(
        "Find the blacksmith.", "Open the world map", "Collect three iron bars", "Talk to the old hunter", "Leave the camp quietly",
        "Upgrade your shield", "Rest at the campfire", "Follow the river north", "Climb the broken tower", "Defeat the wolf pack",
    )

    private fun screen(count: Int) = Reading((0 until count).map { index ->
        // İki sütun, satırlar arası boşluk geniş: her satır ayrı grup.
        val top = 0.02 + (index / 2) * 0.09
        val left = if (index % 2 == 0) 0.05 else 0.55
        TextLine(texts[index], TextBox(left, top, left + 0.35, top + 0.03))
    })

    private fun translator(http: Http, local: ((String) -> String)? = null) =
        AiTranslator(AiProvider.GEMINI, "key", AiModel("gemini-x", "Hızlı"), local?.let { fn -> com.couchsubs.mobile.core.TextTranslator { fn(it) } }, http)

    @Test
    fun screenIsTranslatedInOneRequestAndCached() {
        val http = FakeGemini()
        val translator = translator(http)
        assertTrue(translator.translatesTogether)
        val reported = mutableListOf<Int>()
        val items = ScreenTranslation.translate(screen(10), translator, progress = { reported.add(it.size) })
        assertEquals(1, http.requests.size)
        assertEquals(10, items.size)
        assertEquals(texts.map { "[tr] $it" }.toSet(), items.map { it.translation }.toSet())
        assertEquals(listOf(10), reported)
        assertEquals(AiRequest.SCREEN_OUTPUT_TOKENS, http.requests[0].getJSONObject("generationConfig").getInt("maxOutputTokens"))
        // Çevrilenler önbelleğe girer: yeniden basınca istek gitmez.
        ScreenTranslation.translate(screen(10), translator)
        assertEquals(1, http.requests.size)
    }

    @Test
    fun crowdedScreenIsSplitIntoBatchesInOrder() {
        val http = FakeGemini()
        val many = (0 until AiTranslator.SCREEN_BATCH + 5).map { "Line $it of the menu" }
        assertEquals(many.map { "[tr] $it" }, translator(http).translateAll(many))
        assertEquals(2, http.requests.size)
    }

    @Test
    fun failureFallsBackToTheLocalEngineOrThrows() {
        val http = FakeGemini(status = 500)
        val withLocal = translator(http) { "yerel: $it" }
        assertEquals(listOf("yerel: Open the map", "yerel: Leave the camp"), withLocal.translateAll(listOf("Open the map", "Leave the camp")))
        // Hata sonrası bir dakika hizmet denenmez: ikinci çağrıda istek gitmez.
        val before = http.requests.size
        withLocal.translateAll(listOf("Another line"))
        assertEquals(before, http.requests.size)
        var thrown = false
        try {
            translator(FakeGemini(status = 500)).translateAll(listOf("Open the map"))
        } catch (error: java.io.IOException) {
            thrown = true
        }
        assertTrue(thrown)
    }
}
