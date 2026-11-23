// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException

/** Mac/iPhone TVReachTests ve Windows TvReachTests ile aynı senaryolar. */
class TvReachTest {
    private val saved = FoundTv("LG TV", "192.168.1.238", TvBrand.LG)

    /** beta.89: TV 192.168.1.238'den .156'ya geçmişti; eski adres sessiz, TV ağda yeni adreste bulunur. */
    @Test
    fun silentAddressFindsSameTvAtNewAddress() {
        val moved = FoundTv("LG TV", "192.168.1.156", TvBrand.LG)
        val location = TvReach.locate(saved, { false }) { listOf(moved, FoundTv("Salon", "192.168.1.40", TvBrand.SAMSUNG)) }
        assertEquals(TvReach.Location.Moved(moved), location)
    }

    @Test
    fun respondingAddressIsNotSearched() {
        var searched = false
        val location = TvReach.locate(saved, { true }) { searched = true; emptyList() }
        assertEquals(TvReach.Location.Here, location)
        assertFalse(searched)
    }

    @Test
    fun silentAndNotFoundIsSilent() {
        assertEquals(TvReach.Location.Silent, TvReach.locate(saved, { false }) { emptyList() })
    }

    /** Ağda iki tanınmayan LG varsa tahmin edilmez (başka odadaki TV'ye geçilmez). */
    @Test
    fun doesNotGuessBetweenTwoUnknownTvs() {
        val location = TvReach.locate(saved, { false }) {
            listOf(FoundTv("Yatak odası", "192.168.1.20", TvBrand.LG), FoundTv("Mutfak", "192.168.1.21", TvBrand.LG))
        }
        assertEquals(TvReach.Location.Silent, location)
    }

    @Test
    fun sameNamePicksAmongSeveral() {
        val moved = FoundTv("LG TV", "192.168.1.156", TvBrand.LG)
        assertEquals(moved, TvReach.relocated(saved, listOf(FoundTv("Mutfak", "192.168.1.21", TvBrand.LG), moved)))
    }

    @Test
    fun savedAddressStillListedIsNotAMove() {
        assertEquals(null, TvReach.relocated(saved, listOf(saved, FoundTv("LG TV", "192.168.1.156", TvBrand.LG))))
    }

    @Test
    fun refusedConnectionCountsAsAnswer() {
        assertTrue(TvReach.isRefusal(ConnectException("Connection refused")))
        assertTrue(TvReach.isRefusal(ConnectException("failed to connect to /192.168.1.5 (port 9991): connect failed: ECONNREFUSED (Connection refused)")))
        assertFalse(TvReach.isRefusal(SocketTimeoutException("connect timed out")))
        assertFalse(TvReach.isRefusal(NoRouteToHostException("No route to host")))
        assertFalse(TvReach.isRefusal(ConnectException("Host is down")))
        assertFalse(TvReach.isRefusal(IOException("Network is unreachable")))
    }

    /** Yerel makinede kapalı kapı hemen reddeder: "yanıt veriyor" sayılır (TV açık ama o kapı kapalı). */
    @Test
    fun localRefusalIsAnAnswer() {
        assertTrue(TvReach.answers("127.0.0.1", 9, 2_000))
    }

    @Test
    fun anyAnsweringPortMeansResponds() {
        assertTrue(TvReach.responds("192.168.1.238", TvBrand.LG) { _, port, _ -> port == 9991 })
        assertFalse(TvReach.responds("192.168.1.238", TvBrand.LG) { _, _, _ -> false })
        assertFalse(TvReach.responds("", TvBrand.LG) { _, _, _ -> true })
    }

    @Test
    fun portsCoverEveryBrand() {
        assertTrue(9991 in TvReach.ports(TvBrand.LG) && 3000 in TvReach.ports(TvBrand.LG))
        assertTrue(8001 in TvReach.ports(TvBrand.SAMSUNG))
        assertTrue(6466 in TvReach.ports(TvBrand.ANDROID_TV))
    }

    @Test
    fun texts() {
        assertEquals("TV bu adreste yanıt vermiyor (açık ve aynı ağda mı?)", TvReach.NOT_RESPONDING_LINE)
        assertEquals("TV'nin adresi değişmiş: 192.168.1.238 → 192.168.1.156", TvReach.movedLine("192.168.1.238", "192.168.1.156"))
    }
}
