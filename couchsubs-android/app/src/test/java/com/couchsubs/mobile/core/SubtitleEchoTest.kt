// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Altyazı ekran yazısı olarak ikinci kez çizilmez (kullanıcı bildirimi, beta.65/66: çeviri hem seçilen altyazı konumunda
 * hem oyunun altyazısının üstünde görünüyordu). Mac/iPhone: SubtitleEchoTests.swift, Windows: SubtitleEchoTests.cs.
 */
class SubtitleEchoTest {
    private var time = 0L
    private val echo = SubtitleEcho { time }
    /** Varsayılan altyazı alanı (0,14–0,86 x 0,62–0,97). */
    private val region = CropRegion().box

    /** Altyazı alanına oranla kutu: karedeki yerden. */
    private fun inRegion(text: String, left: Double, top: Double, right: Double, bottom: Double): TextLine {
        val w = region.right - region.left
        val h = region.bottom - region.top
        return TextLine(text, TextBox((left - region.left) / w, (top - region.top) / h, (right - region.left) / w, (bottom - region.top) / h))
    }

    private fun at(text: String, left: Double, top: Double, right: Double, bottom: Double) = TextLine(text, TextBox(left, top, right, bottom))

    @Test
    fun linesInTheSubtitleAreaAreNotScreenText() {
        echo.record(Reading(listOf(inRegion("Thought I was flying solo. Come on.", 0.30, 0.80, 0.70, 0.84))), region)
        // Altyazının yerine düşen satır (aynı altyazının bozuk okunuşu ya da yeni altyazı) metin tutmasa da atılır.
        val reading = Reading(listOf(at("Thought I was fiying soio. C0me on.", 0.31, 0.80, 0.69, 0.84),
            at("Okay, let's go then, right now.", 0.28, 0.80, 0.72, 0.845),
            at("Press up to open the phone", 0.02, 0.05, 0.30, 0.09)))
        assertEquals(listOf("Press up to open the phone"), echo.filter(reading).lines.map { it.text })
    }

    /**
     * Kullanıcı bildirimi (X, beta.69, GTA 6): "Ekranı çevir" altyazıyı çeviriyor, telefon mesajlarını çevirmiyordu. Sağ
     * alttaki telefon kartı (0,72–0,99 x 0,45–0,80) varsayılan altyazı alanıyla kesişiyor; altyazı okunurken kartın
     * 0,62'nin altındaki satırlarının merkezi alanın içinde kaldığı için hepsi atılıyordu ("Ekranı çevir" de bu süzgeci
     * kullanır: TranslationService `echo.filter(read, geometry = echo.hasRecent)`).
     */
    @Test
    fun phoneMessagesInsideTheSubtitleAreaAreScreenText() {
        echo.record(Reading(listOf(inRegion("Yeah, I'll stop by.", 0.42, 0.86, 0.58, 0.90))), region)
        assertTrue(echo.hasRecent)
        val phone = listOf(at("Jason", 0.76, 0.47, 0.84, 0.50),
            at("Where are you? We need to talk.", 0.74, 0.55, 0.95, 0.58),
            at("Come to the marina after dark", 0.74, 0.64, 0.94, 0.67),
            at("Bring the cash", 0.74, 0.70, 0.84, 0.73),
            at("Don't be late this time", 0.80, 0.76, 0.97, 0.79))
        val reading = Reading(phone + at("Yeah, I'll stop by.", 0.42, 0.86, 0.58, 0.90))
        assertEquals(phone.map { it.text }, echo.filter(reading, geometry = echo.hasRecent).lines.map { it.text })
        // Geniş altyazıyla aynı sıradaki mesaj satırı da kalır (yalnız ucu örtüşür); altyazının alana düşen parçası atılır.
        echo.record(Reading(listOf(inRegion("You better get to the docks before the cops do", 0.15, 0.76, 0.85, 0.80))), region)
        val wide = Reading(listOf(at("Don't be late this time", 0.80, 0.76, 0.97, 0.79), at("before the cops do", 0.73, 0.76, 0.85, 0.80)))
        assertEquals(listOf("Don't be late this time"), echo.filter(wide).lines.map { it.text })
    }

    /**
     * İki satırlı altyazının üst satırı alanın dışında: altyazı hattı yalnız alt satırı okur, üst satır bitişik ve aynı
     * boyda olduğu için o da altyazıdır.
     */
    @Test
    fun subtitleLineOverflowingTheAreaEdgeIsNotScreenText() {
        echo.record(Reading(listOf(inRegion("and you still owe me for the boat.", 0.32, 0.63, 0.68, 0.67))), region)
        val reading = Reading(listOf(at("Lucia, I told you twice already", 0.30, 0.585, 0.70, 0.625),
            at("Find a vehicle", 0.80, 0.30, 0.95, 0.34)))
        assertEquals(listOf("Find a vehicle"), echo.filter(reading).lines.map { it.text })
        // Altyazı kalkınca bitişik satır kuralı da kalkar.
        time += SubtitleEcho.ADJACENT_MS + 1
        assertEquals(2, echo.filter(reading).lines.size)
    }

    /** Alandan geniş altyazının ucu ya da hazır mesaj alanına düşen parçası metinle tanınır. */
    @Test
    fun textReadByTheSubtitleLineIsNotScreenTextAnywhere() {
        echo.record(Reading(listOf(inRegion("You better get to the docks before the cops do", 0.15, 0.80, 0.85, 0.84))), region)
        assertTrue(echo.isEcho("YOU BETTER GET TO THE DOCKS BEFORE THE COPS DO"))
        assertTrue("parça", echo.isEcho("the docks before the cops do"))
        assertFalse("kısa ve farklı görev yazısı", echo.isEcho("Get to the docks"))
        // Görev alanında (yer kuralı kapalı) da metinle atılır.
        val mission = Reading(listOf(at("You better get to the docks before the cops do", 0.2, 0.2, 0.8, 0.6)))
        assertTrue(echo.filter(mission, geometry = false).lines.isEmpty())
        time += SubtitleEcho.WINDOW_MS + 1
        assertFalse(echo.isEcho("You better get to the docks before the cops do"))
    }

    @Test
    fun fullScreenSubtitleAreaDoesNotHideEverything() {
        echo.record(Reading.Empty, TextBox(0.0, 0.0, 1.0, 1.0))
        val reading = Reading(listOf(at("Press up to open the phone", 0.4, 0.5, 0.6, 0.55)))
        assertEquals(1, echo.filter(reading).lines.size)
    }

    // RegionWatcher

    private class Recorder : RegionSender {
        val sent = mutableListOf<String>()
        override fun sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?) = sendRegion(id, text, box, lineHeight, null, null)
        override fun sendRegion(
            id: String, text: String, box: TextBox?, lineHeight: Double?, icons: List<IconPlacement>?,
            blocks: List<ScreenTranslation.Item>?,
        ) {
            sent.add(text)
        }
        override fun clearRegions() {}
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

    /** Dedektörün altyazı alanının kenarında bulduğu (yarım karo genişletilmiş) otomatik alan altyazıyı okur: çizilmez. */
    @Test
    fun autoAreaReadingTheSubtitleSendsNothing() {
        echo.record(Reading(listOf(inRegion("and you still owe me for the boat.", 0.32, 0.63, 0.68, 0.67))), region)
        // Alan 0,25–0,75 x 0,55–0,70: üst satır alanın dışında, alt satır içinde.
        val area = ExtraArea("auto-1", ScreenTextDetector.NAME, CropRegion(top = 0.55, bottom = 0.70, left = 0.25, right = 0.75), auto = true)
        fun local(text: String, top: Double, bottom: Double) = TextLine(text, TextBox(0.1, (top - 0.55) / 0.15, 0.9, (bottom - 0.55) / 0.15))
        val lines = listOf(local("Lucia, I told you twice already", 0.585, 0.625), local("and you still owe me for the boat.", 0.63, 0.67))
        val recorder = Recorder()
        val watcher = RegionWatcher({ Reading(lines) }, { "çeviri ${it.length}" }, recorder)
        watcher.subtitleEcho = echo
        repeat(2) { watcher.pass(setOf(area.id), listOf(area to RegionWatcher.Crop(Unit, signature(), crop))) }
        assertTrue(recorder.sent.toString(), recorder.sent.all { it.isEmpty() })
    }

    /** Hazır mesaj alanı altyazı alanıyla kesişir: kesişen yerdeki altyazı parçası çizilmez, mesaj kartı çizilir. */
    @Test
    fun presetAreaDropsTheSubtitlePartButKeepsItsOwnText() {
        // Altyazı alanın sağ kenarına dek geniş: sağ ucu hazır mesaj alanına düşüyor.
        echo.record(Reading(listOf(inRegion("You better get to the docks before the cops do", 0.15, 0.76, 0.86, 0.795))), region)
        val messages = GameAreaPresets.areas("GTA 6").first { it.id == GameAreaPresets.PHONE_ID }
        val r = messages.region
        fun local(text: String, top: Double, bottom: Double) =
            TextLine(text, TextBox(0.05, (top - r.top) / (r.bottom - r.top), 0.5, (bottom - r.top) / (r.bottom - r.top)))
        // Kartın altyazı alanına (0,62'den aşağısı) düşen mesaj satırı da kartın yazısıdır.
        val lines = listOf(local("Meet me at the marina tonight, Jason", 0.50, 0.54), local("Bring the boat keys", 0.66, 0.70),
            local("before the cops do", 0.76, 0.795))
        val recorder = Recorder()
        val watcher = RegionWatcher({ Reading(lines) }, { "çeviri ${it.length}" }, recorder)
        watcher.subtitleEcho = echo
        // Kare verilmez: arayüz kutusu denetimi atlanır (yalnız satır elemesi sınanır).
        repeat(2) { watcher.pass(setOf(messages.id), listOf(messages to RegionWatcher.Crop(Unit, signature(), null))) }
        // Yalnız mesaj kartı (36 + 19 harf) çevrilip çizilir; altyazı parçası metne katılmaz.
        assertEquals(recorder.sent.toString(), 1, recorder.sent.size)
        assertTrue(recorder.sent.toString(), recorder.sent[0].contains("çeviri 36") && recorder.sent[0].contains("çeviri 19"))
    }
}
