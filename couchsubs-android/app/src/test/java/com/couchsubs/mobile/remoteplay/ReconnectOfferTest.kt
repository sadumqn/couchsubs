// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.remoteplay

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Bağlantı kopunca kullanıcı uygulamayı kapatıp açıyordu (TestFlight, iPhone): "Yeniden bağlan" düğmesi bırakılan
 * oturumda hemen, süren denemelerde 45 sn sonra görünür (Mac/iPhone ReconnectOfferTests ile aynı).
 */
class ReconnectOfferTest {
    private val start = 1_000_000L

    @Test
    fun hiddenWhileStreaming() {
        val offer = ReconnectOffer()
        offer.update(live = true, now = start)
        assertFalse(offer.shows(gaveUp = false, now = start + 600_000))
    }

    @Test
    fun showsAfterLongReconnecting() {
        val offer = ReconnectOffer()
        offer.update(live = false, now = start)
        offer.update(live = false, now = start + 20_000)
        assertFalse(offer.shows(gaveUp = false, now = start + 44_000))
        assertTrue(offer.shows(gaveUp = false, now = start + ReconnectOffer.AFTER_MS))
        offer.update(live = true, now = start + 50_000)
        assertFalse(offer.shows(gaveUp = false, now = start + 60_000))
    }

    @Test
    fun showsAtOnceWhenTheSessionGaveUp() {
        val offer = ReconnectOffer()
        offer.update(live = false, now = start)
        assertTrue(offer.shows(gaveUp = true, now = start))
    }

    @Test
    fun resetRestartsTheClock() {
        val offer = ReconnectOffer()
        offer.update(live = false, now = start)
        offer.reset(start + 100_000)
        assertFalse(offer.shows(gaveUp = false, now = start + 120_000))
        assertTrue(offer.shows(gaveUp = false, now = start + 145_000))
        offer.reset()
        assertFalse(offer.shows(gaveUp = false, now = start + 1_000_000))
    }
}
