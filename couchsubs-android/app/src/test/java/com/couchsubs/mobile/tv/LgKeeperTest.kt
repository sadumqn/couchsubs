// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import com.couchsubs.mobile.core.SubtitleServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Windows TvKeeperTests ve Mac/iPhone TVKeeperTests ile aynı senaryolar. */
class LgKeeperTest {
    private class FakeControl(vararg foreground: String) : LgControl {
        val queue = ArrayDeque(foreground.toList())
        var launches = 0
        var closes = 0
        override fun foregroundAppId() = queue.removeFirstOrNull() ?: LgKeeperRule.APP_ID
        override fun launch() { launches++ }
        override fun close() { closes++ }
    }

    @Test fun psButtonOnTheConsoleInputIsNeverCountedAsInsisting() {
        // X (Kas 2026): oyunda PS tuşu TV'yi PS5'in girişine (CEC) geçiriyor; her basışta geri getirilir.
        var time = 0L
        val rule = LgKeeperRule { time }
        repeat(8) {
            time += 5_000
            assertEquals(LgKeeperRule.Action.LAUNCH, rule.decide("com.webos.app.hdmi2", 2))
            time += 3_000
            assertEquals(LgKeeperRule.Action.NONE, rule.decide(LgKeeperRule.APP_ID, 2))
        }
        assertFalse(rule.stoodDown)
    }

    @Test fun anotherHdmiNumberIsStillRespected() {
        var time = 0L
        val rule = LgKeeperRule { time }
        repeat(LgKeeperRule.STAND_DOWN_AFTER) {
            time += 10_000
            assertEquals(LgKeeperRule.Action.LAUNCH, rule.decide("com.webos.app.hdmi1", 2))
        }
        time += 10_000
        assertEquals(LgKeeperRule.Action.NONE, rule.decide("com.webos.app.hdmi1", 2))
        assertTrue(rule.stoodDown)
        assertEquals(LgKeeperRule.Action.NONE, rule.decide("com.webos.app.hdmi2", 2)) // çekilmişken hiçbir girişten zorlanmaz
        rule.decide(LgKeeperRule.APP_ID, 2) // kullanıcı CouchSubs'ı kendisi açtı
        assertFalse(rule.stoodDown)
    }

    @Test fun otherAppsAreLeftAlone() {
        val rule = LgKeeperRule { 0L }
        assertEquals(LgKeeperRule.Action.NONE, rule.decide("netflix", 2))
        assertEquals(LgKeeperRule.Action.LAUNCH, rule.decide("com.webos.app.livetv", 2))
    }

    @Test fun endlessConsoleBounceStandsDown() {
        var time = 0L
        val rule = LgKeeperRule { time }
        var launches = 0
        repeat(20) {
            time += 3_000
            if (rule.decide("com.webos.app.hdmi3", 3) == LgKeeperRule.Action.LAUNCH) launches++
        }
        assertTrue(rule.stoodDown)
        assertEquals(LgKeeperRule.CONSOLE_LOOP_LIMIT, launches)
    }

    @Test fun keeperBringsTheAppBackWithinTwoSecondsOfThePsButton() {
        // Telefon eskiden LG'de bekçi çalıştırmıyordu: uygulama bir kez açılıp bırakılıyordu.
        val control = FakeControl(LgKeeperRule.APP_ID, "com.webos.app.hdmi2", LgKeeperRule.APP_ID)
        var clock = 0L
        var elapsedAtLaunch = -1L
        var lastSeenInFront = -1L
        val wrapped = object : LgControl by control {
            override fun foregroundAppId() = control.foregroundAppId().also { if (it == LgKeeperRule.APP_ID && elapsedAtLaunch < 0) lastSeenInFront = clock }
            override fun launch() { control.launch(); if (elapsedAtLaunch < 0) elapsedAtLaunch = clock }
        }
        var steps = 0
        LgKeeper.keep(open = { wrapped }, active = { steps++ < 8 }, consolePort = { 2 }, rule = LgKeeperRule { clock },
            sleep = { clock += it })
        // İlk bağlantıda yeni açılmış uygulama yeniden açılmaz; PS tuşundan (ikinci soru) sonra bir kez açılır.
        assertEquals(1, control.launches)
        // Uygulama en son öndeyken görüldükten sonra TV girişe geçti; geri getirme bir sonraki soruda (≤ 2 sn).
        assertTrue("geri getirme ${elapsedAtLaunch - lastSeenInFront} ms", lastSeenInFront >= 0 && elapsedAtLaunch - lastSeenInFront in 1..2_000)
        assertEquals(1, control.closes)
    }

    @Test fun keeperReconnectsAndRelaunchesAfterTheTvWasOff() {
        // Bağlantı koptu (TV kapandı): yeniden bağlanınca uygulama açılır.
        val broken = object : LgControl {
            var closes = 0
            override fun foregroundAppId(): String = throw java.io.IOException("koptu")
            override fun launch() {}
            override fun close() { closes++ }
        }
        val second = FakeControl()
        val controls = ArrayDeque(listOf<LgControl?>(broken, null, second))
        var steps = 0
        LgKeeper.keep(open = { controls.removeFirstOrNull() }, active = { steps++ < 5 }, consolePort = { null }, sleep = { })
        assertEquals(1, broken.closes)
        assertEquals(1, second.launches)
    }

    /**
     * #1055 (LG OLED C4, beta.86): her yeni bağlantı ve alındı kesintisi ("Otomatik açmayı dene" yolu) açık ve bağlı
     * uygulamaya da açma komutu gönderiyordu; webOS HDMI görüntüsünü yeniden kuruyor, ekran kararıyordu. 30 dk boyunca
     * bağlantı 20 sn'de bir kopup her dakika yeniden açma istense de açık ve bağlı uygulamaya tek açma komutu gitmez.
     */
    @Test fun openConnectedAppGetsNoLaunchFor30MinutesEvenWhenSsapKeepsReconnecting() {
        var clock = 0L
        var launches = 0
        var second = 0
        var retry = false
        fun control() = object : LgControl {
            override fun foregroundAppId(): String {
                if (second % 20 == 0) throw java.io.IOException("koptu")
                return LgKeeperRule.APP_ID
            }
            override fun launch() { launches++ }
            override fun close() {}
        }
        LgKeeper.keep(open = { control() }, active = { second < 30 * 60 }, consolePort = { 2 }, rule = LgKeeperRule { clock },
            sleep = { clock += it; second = (clock / 1000).toInt(); if (second % 60 == 30) retry = true },
            retry = { retry.also { retry = false } }, connected = { true })
        assertEquals(0, launches)
    }

    /** Uygulama bağlı değil (yanıtsız): yeniden kurulan bağlantıda geri çekilerek açılır (30 sn, 1, 2, 5 dk), her kopuşta değil. */
    @Test fun unresponsiveAppIsReopenedWithBackoff() {
        var clock = 0L
        var launches = 0
        fun control() = object : LgControl {
            override fun foregroundAppId(): String = throw java.io.IOException("koptu")
            override fun launch() { launches++ }
            override fun close() {}
        }
        LgKeeper.keep(open = { control() }, active = { clock < 10 * 60_000 }, consolePort = { null }, rule = LgKeeperRule { clock },
            sleep = { clock += it }, connected = { false })
        // İlk bağlantı açmaz (uygulama launch() ile açıldı); 10 dk'da: hemen, +30 sn, +60 sn, +120 sn, sonra 5 dk'da bir.
        assertTrue("açma sayısı $launches", launches in 4..6)
    }

    @Test fun serverParsesTheReportedHdmiInput() {
        assertEquals(4, SubtitleServer.hdmiPort("4"))
        assertNull(SubtitleServer.hdmiPort("9"))
        assertNull(SubtitleServer.hdmiPort("12"))
        assertNull(SubtitleServer.hdmiPort(null))
        assertTrue(LgKeeperRule.isConsoleInput("com.webos.app.hdmi2", 2))
        assertFalse(LgKeeperRule.isConsoleInput("com.webos.app.hdmi2", null))
    }
}
