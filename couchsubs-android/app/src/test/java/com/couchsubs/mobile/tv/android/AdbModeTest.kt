// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** GitHub #478: TV'de 5555 kapalıyken kurulum ekranı kablosuz hata ayıklamaya yönlendirmeli. */
class AdbModeTest {
    @Test
    fun closedLegacyPortSelectsWireless() {
        assertTrue(AdbMode.prefersWireless(legacyAdbReachable = false))
        assertFalse(AdbMode.prefersWireless(legacyAdbReachable = true))
    }

    @Test
    fun unreachableOnNetworkModeOffersWireless() {
        assertTrue(AdbMode.offersWireless(wireless = false, error = AndroidInstallError.UNREACHABLE))
        assertFalse(AdbMode.offersWireless(wireless = true, error = AndroidInstallError.UNREACHABLE))
        assertFalse(AdbMode.offersWireless(wireless = false, error = AndroidInstallError.NOT_APPROVED))
        assertFalse(AdbMode.offersWireless(wireless = false, error = null))
    }

    @Test
    fun switchingKeepsOnlyTheHost() {
        assertEquals("192.168.1.40", AdbMode.hostOnly("192.168.1.40:5555"))
        assertEquals("192.168.1.40", AdbMode.hostOnly(" 192.168.1.40 "))
        assertEquals("tv.local", AdbMode.hostOnly("tv.local:37000"))
    }
}
