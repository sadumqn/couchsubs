// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Otomatik ekran yazısının türleri Ayarlar'dan ayrı açılıp kapanır (Mac/iPhone: ScreenTextKindTests.swift, Windows:
 * ScreenTextKindTests.cs).
 */
class ScreenTextKindTest {
    private val order = listOf(ScreenTextKind.PHONE, ScreenTextKind.MISSION, ScreenTextKind.HELP, ScreenTextKind.MENU, ScreenTextKind.OTHER)

    @Test
    fun defaultsForOldInstallsAndOrder() {
        // Eski kurulumda kayıt yok: varsayılanlar (telefon, görev, yardım açık; menüler ve diğerleri kapalı).
        val kinds = ScreenTextKinds()
        assertEquals(order, ScreenTextKind.values().toList())
        assertEquals(listOf(true, true, true, false, false), order.map { kinds.allows(true, it) })
        val changed = kinds.copy(menus = true, phone = false)
        assertEquals(listOf(false, true, true, true, false), order.map { changed.allows(true, it) })
    }

    @Test
    fun kindsApplyOnlyWhileAutoScreenTextIsOn() {
        val kinds = ScreenTextKinds(help = false)
        assertTrue(order.all { kinds.allows(false, it) })
        assertFalse(kinds.allows(true, ScreenTextKind.HELP))
        assertFalse(kinds.allows(true, ScreenTextKind.MENU))
    }

    @Test
    fun phoneIsReadWithItsOwnSettingOrThePhoneKind() {
        assertFalse(ScreenTextKinds().readsGamePhone(autoReadGamePhone = false, autoScreenText = false))
        assertTrue(ScreenTextKinds().readsGamePhone(autoReadGamePhone = false, autoScreenText = true))
        assertFalse(ScreenTextKinds(phone = false).readsGamePhone(autoReadGamePhone = false, autoScreenText = true))
        assertTrue(ScreenTextKinds(phone = false).readsGamePhone(autoReadGamePhone = true, autoScreenText = true))
    }

    @Test
    fun kindOfAnArea() {
        assertEquals(listOf(ScreenTextKind.HELP, ScreenTextKind.PHONE), GameAreaPresets.areas("GTA 6").map { ScreenTextKind.of(it) })
        assertEquals(ScreenTextKind.MISSION, ScreenTextKind.of(ExtraArea(MissionLine.AREA_ID, "Mission", CropRegion(), auto = true)))
        val auto = ExtraArea("auto-1", ScreenTextDetector.NAME, CropRegion(), auto = true)
        assertNull("menü dışındaki otomatik alanın türü yazısından çıkar", ScreenTextKind.of(auto))
        assertEquals(ScreenTextKind.MENU, ScreenTextKind.of(auto.copy(menu = true)))
        assertNull("kullanıcının kendi alanı", ScreenTextKind.of(ExtraArea("q", "Quest", CropRegion())))
    }

    @Test
    fun kindOfAutoText() {
        assertEquals(ScreenTextKind.HELP, ScreenTextKind.ofParagraphs(listOf("Press ${ButtonIcons.MARKER} to open the phone")))
        assertEquals(ScreenTextKind.HELP, ScreenTextKind.ofParagraphs(listOf("R2 Aim")))
        assertEquals(ScreenTextKind.HELP, ScreenTextKind.ofParagraphs(listOf("You can buy properties from the website on your phone.")))
        assertEquals("birden çok parça: kutu", ScreenTextKind.HELP, ScreenTextKind.ofParagraphs(listOf("VICE CITY", "Leonida Keys")))
        assertEquals(ScreenTextKind.MISSION, ScreenTextKind.ofParagraphs(listOf("Follow Paulie to the car.")))
        assertEquals(ScreenTextKind.OTHER, ScreenTextKind.ofParagraphs(listOf("Ocean Drive")))
    }

    // RegionWatcher

    private class Recorder : RegionSender {
        val sent = mutableListOf<Pair<String, String>>()
        override fun sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?) = sendRegion(id, text, box, lineHeight, null, null)
        override fun sendRegion(
            id: String, text: String, box: TextBox?, lineHeight: Double?, icons: List<IconPlacement>?,
            blocks: List<ScreenTranslation.Item>?,
        ) {
            sent.add(id to text)
        }
        override fun clearRegions() {}
        val shown get() = sent.filter { it.second.isNotEmpty() }
    }

    /** Koyu kutuda beyaz yazı çizgileri: alanın okunan karesi. */
    private val crop: GrayFrame = run {
        val width = 256
        val height = 108
        GrayFrame(ByteArray(width * height) { index ->
            val x = index % width
            val y = index / width
            (if (y in 20..60 && y % 10 < 2 && x in 20..230 && x % 4 != 0) 230 else 25).toByte()
        }, width, height)
    }

    private fun signature() = ByteArray(RegionSignature.WIDTH * RegionSignature.HEIGHT) { 1 }

    private fun line(text: String, top: Double = 0.3) = TextLine(text, TextBox(0.1, top, 0.9, top + 0.2))

    private fun run(kinds: ScreenTextKinds, area: ExtraArea, lines: List<TextLine>, rejected: MutableList<String>? = null): Recorder {
        val recorder = Recorder()
        val watcher = RegionWatcher({ Reading(lines) }, { "çeviri ${it.length}" }, recorder)
        watcher.allows = { kinds.allows(true, it) }
        rejected?.let { list -> watcher.onAutoRejected = { list.add(it) } }
        repeat(2) { watcher.pass(setOf(area.id), listOf(area to RegionWatcher.Crop(Unit, signature(), crop))) }
        return recorder
    }

    /** Menüler kapalıyken (varsayılan) menü alanı okunmaz; açılınca çevrilir. */
    @Test
    fun menuAreaIsTranslatedOnlyWhenMenusAreOn() {
        val area = ExtraArea("auto-1", ScreenTextDetector.NAME, CropRegion(top = 0.2, bottom = 0.4, left = 0.1, right = 0.5), auto = true, menu = true)
        val lines = listOf(line("Story Mode"), line("Online Settings", top = 0.6))
        assertTrue(run(ScreenTextKinds(), area, lines).sent.isEmpty())
        assertTrue(run(ScreenTextKinds(menus = true), area, lines).shown.isNotEmpty())
    }

    /** Kısa tek satır "diğer" türdür (varsayılan kapalı); tuş ipucu yardım/eylemdir (varsayılan açık). */
    @Test
    fun autoAreaKindComesFromItsText() {
        val area = ExtraArea("auto-1", ScreenTextDetector.NAME, CropRegion(top = 0.2, bottom = 0.4, left = 0.1, right = 0.5), auto = true)
        val rejected = mutableListOf<String>()
        assertTrue(run(ScreenTextKinds(), area, listOf(line("Welcome to Ocean Drive Beach")), rejected).shown.isEmpty())
        assertTrue("kapalı tür bulucuya bildirilir", rejected.contains("auto-1"))
        assertTrue(run(ScreenTextKinds(other = true), area, listOf(line("Welcome to Ocean Drive Beach"))).shown.isNotEmpty())
        assertEquals(1, run(ScreenTextKinds(), area, listOf(line("Press ${ButtonIcons.MARKER} to open the phone menu now"))).shown.size)
    }

    /** Görev kapalıyken görev satırının alanı okunmaz. */
    @Test
    fun missionAreaFollowsItsKind() {
        val mission = ExtraArea(MissionLine.AREA_ID, "Mission", CropRegion(top = 0.85, bottom = 0.92, left = 0.3, right = 0.7), auto = true)
        val lines = listOf(line("Get in the sea plane and fly to the island"))
        assertTrue(run(ScreenTextKinds(mission = false), mission, lines).sent.isEmpty())
        assertEquals(listOf(MissionLine.AREA_ID), run(ScreenTextKinds(), mission, lines).shown.map { it.first })
    }
}
