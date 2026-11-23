// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.xbox

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * İlk kareden sonra Xbox görüntüsü kesilince uyarı ve yeniden kurma. Sahte saat: anlar ms olarak verilir.
 * CouchSubsCore XboxPictureWatchTests ve Windows'taki XboxPictureWatchTests ile aynı durumlar.
 */
class XboxPictureWatchTest {
    private val fine = XboxPictureVerdict.Fine

    @Test fun nothingIsDecidedBeforeTheFirstFrame() {
        val watch = XboxPictureWatch()
        watch.iceChanged(XboxPictureWatch.Ice.DISCONNECTED, 0)
        assertEquals(fine, watch.tick(60_000))
    }

    @Test fun flowingPictureIsFine() {
        val watch = XboxPictureWatch()
        for (second in 0L until 120L) {
            watch.frameArrived(second * 1000)
            assertEquals(fine, watch.tick(second * 1000 + 500))
        }
    }

    @Test fun warnsOnceThenReconnectsWhenFramesStopWhileTheConnectionLooksOpen() {
        val watch = XboxPictureWatch()
        watch.frameArrived(0)
        watch.frameArrived(40_000)
        assertEquals(fine, watch.tick(44_000))
        assertEquals(XboxPictureVerdict.Warn, watch.tick(45_000))
        assertTrue(watch.warned)
        assertEquals(fine, watch.tick(46_000))
        assertEquals(fine, watch.tick(51_000))
        assertEquals(XboxPictureVerdict.Stalled("Xbox'tan 12 sn'dir görüntü gelmiyor (bağlantı açık görünüyor)"), watch.tick(52_000))
    }

    /** Yayının ilk 30 sn'sinde kare boşluğu oturumu kapatmaz (yalnız uyarı); sınırdan sonra kapatır. */
    @Test fun gapsInTheFirstThirtySecondsDoNotEndTheSession() {
        val watch = XboxPictureWatch()
        watch.frameArrived(1000)
        assertEquals(XboxPictureVerdict.Warn, watch.tick(6000))
        for (at in 7000L..30_000L step 1000) assertEquals(fine, watch.tick(at))
        assertEquals(XboxPictureVerdict.Stalled("Xbox'tan 30 sn'dir görüntü gelmiyor (bağlantı açık görünüyor)"), watch.tick(31_000))
    }

    @Test fun flowingMeansARecentFrame() {
        val watch = XboxPictureWatch()
        assertFalse(watch.isFlowing(0))
        watch.frameArrived(1000)
        assertTrue(watch.isFlowing(5999))
        assertFalse(watch.isFlowing(6000))
    }

    @Test fun recoversWhenFramesComeBackBeforeTheLimit() {
        val watch = XboxPictureWatch()
        watch.frameArrived(0)
        assertEquals(XboxPictureVerdict.Warn, watch.tick(6000))
        watch.frameArrived(8000)
        assertEquals(XboxPictureVerdict.Recovered, watch.tick(8500))
        assertFalse(watch.warned)
        assertEquals(fine, watch.tick(9500))
    }

    @Test fun iceDisconnectedWarnsAfterOneSecondWithoutFrames() {
        val watch = XboxPictureWatch()
        watch.frameArrived(0)
        watch.iceChanged(XboxPictureWatch.Ice.DISCONNECTED, 200)
        assertEquals(fine, watch.tick(500))
        assertEquals(XboxPictureVerdict.Warn, watch.tick(1200))
        watch.iceChanged(XboxPictureWatch.Ice.CONNECTED, 3000)
        watch.frameArrived(3100)
        assertEquals(XboxPictureVerdict.Recovered, watch.tick(3500))
    }

    @Test fun iceStuckInDisconnectedEndsTheSessionAtTheLimit() {
        val watch = XboxPictureWatch()
        watch.frameArrived(0)
        watch.frameArrived(40_000)
        watch.iceChanged(XboxPictureWatch.Ice.DISCONNECTED, 40_100)
        assertEquals(XboxPictureVerdict.Warn, watch.tick(41_000))
        assertEquals(XboxPictureVerdict.Stalled("Xbox'tan 12 sn'dir görüntü gelmiyor (ICE disconnected)"), watch.tick(52_000))
    }

    @Test fun iceFailedEndsTheSessionAtOnce() {
        val watch = XboxPictureWatch()
        watch.frameArrived(0)
        watch.iceChanged(XboxPictureWatch.Ice.FAILED, 500)
        assertEquals(XboxPictureVerdict.Stalled("Xbox ICE bağlantısı koptu (failed)"), watch.tick(600))
    }

    @Test fun framesWhileIceSaysDisconnectedDoNotWarn() {
        val watch = XboxPictureWatch()
        watch.iceChanged(XboxPictureWatch.Ice.DISCONNECTED, 0)
        for (second in 0L until 20L) {
            watch.frameArrived(second * 1000)
            assertEquals(fine, watch.tick(second * 1000 + 300))
        }
    }

    @Test fun stalledSessionRetriesThroughTheMachine() {
        var clock = 0L
        val machine = XboxSessionMachine(clock = { clock })
        machine.start()
        machine.played()
        machine.status("Provisioned", null)
        assertTrue(machine.streaming())
        clock = 30_000
        assertEquals(XboxSessionMachine.Action.Retry(5000), machine.fail(XboxError.NO_PICTURE, "Xbox'tan 12 sn'dir görüntü gelmiyor"))
    }

    /**
     * Sahte Xbox oturumu (bekçiler XboxStreamSession'daki gibi saniyede bir; canlı tutma 30 sn'de bir). Play'deki
     * bildirim (Android beta.85): "uzaktan yürütme başlatıldı, hemen ardından durdu, tekrar başladı/durdu". Yayın
     * başında görüntü birkaç saniye bekliyor, canlı tutma 404 dönüyor: ilk 30 sn'de (ve görüntü akarken sonrasında da)
     * oturum kapatılmıyor, yeniden açılmıyor. Sonra gerçek kopma: en çok bir kez, 5 sn sonra yeniden bağlanılıyor.
     */
    @Test fun fakeXboxSessionDoesNotLoopAndReconnectsAtMostOnce() {
        val session = FakeXboxSession()
        session.connect()
        session.frames(1000L..3000L)
        // 3–20 sn: Xbox görüntüyü bekletiyor (yükleme, bildirim); 20 sn'den sonra yine akıyor.
        session.frames(20_000L..70_000L)
        session.keepaliveFails = "Xbox service HTTP 404: "
        for (at in 0L..70_000L step 1000) session.tick(at)
        assertEquals("ilk 30 sn'de ve görüntü akarken kapatma yok", emptyList<String>(), session.ends)
        assertEquals(1, session.plays)

        // Gerçek kopma: Wi-Fi gitti, ICE disconnected, kare yok.
        session.iceLost(70_500)
        for (at in 71_000L..82_000L step 1000) session.tick(at)
        assertEquals(1, session.ends.size)
        assertEquals(listOf(5000L), session.retries)
        assertEquals(2, session.plays)
        // Yeniden bağlanma da kısa sürede kopuyor: ikinci deneme yok, yayın durur ("Yeniden bağlan" düğmesi).
        session.frames(96_000L..100_000L)
        session.iceLost(100_500)
        for (at in 96_000L..160_000L step 1000) session.tick(at)
        assertEquals(listOf(5000L, null), session.retries)
        assertEquals(2, session.plays)
    }

    /** XboxStreamSession'ın bekçi döngüsünün ağsız kopyası (oturum makinesi, görüntü bekçisi, canlı tutma). */
    private class FakeXboxSession {
        private var now = 0L
        private val machine = XboxSessionMachine(clock = { now })
        private var watch = XboxPictureWatch()
        private var keepalive = XboxKeepalive()
        private val frameTimes = sortedSetOf<Long>()
        private var connectedAt = 0L
        private var stopped = false
        var keepaliveFails: String? = null
        var plays = 0
        val ends = ArrayList<String>()
        val retries = ArrayList<Long?>()

        fun connect() {
            machine.start(); machine.played(); machine.status("Provisioned", null)
            plays++
            connectedAt = now
            watch = XboxPictureWatch()
            keepalive = XboxKeepalive()
        }

        /** Xbox bu aralıkta ~60 kare/sn gönderir. */
        fun frames(range: LongRange) = range.step(16).forEach { frameTimes += it }

        fun iceLost(at: Long) {
            frameTimes.removeAll { it >= at }
            watch.iceChanged(XboxPictureWatch.Ice.DISCONNECTED, at)
        }

        fun tick(at: Long) {
            if (stopped) return
            now = at
            frameTimes.filter { it in (at - 1000) until at + 1 }.forEach {
                if (machine.phase == XboxSessionMachine.Phase.Negotiating) machine.streaming()
                watch.frameArrived(it)
            }
            val since = at - connectedAt
            if (since > 0 && since % XboxKeepalive.INTERVAL_MS == 0L) {
                val error = keepaliveFails
                if (error == null) keepalive.succeeded()
                else if (XboxKeepalive.shouldEnd(XboxKeepalive.sessionGone(error), keepalive.failed(), watch.isFlowing(at))) return end("canlı tutma", XboxError.SERVER_CLOSED)
            }
            val verdict = watch.tick(at)
            if (verdict is XboxPictureVerdict.Stalled) end(verdict.reason, XboxError.NO_PICTURE)
        }

        private fun end(reason: String, kind: XboxError) {
            ends += reason
            val delay = (machine.fail(kind, reason) as XboxSessionMachine.Action.Retry).delayMs
            retries += delay
            if (delay == null) {
                stopped = true
                return
            }
            now += delay
            connect()
        }
    }
}
