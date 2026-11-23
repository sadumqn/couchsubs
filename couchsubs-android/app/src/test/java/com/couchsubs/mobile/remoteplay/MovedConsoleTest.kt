// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.remoteplay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MovedConsoleTest {
    /** Adresi değişen PS5 yalnız adı tutarsa seçilir; ağda tek PS5 olsa bile başka evin/odanın PS5'i seçilmez (GitHub #425; Mac ve Windows ile aynı). */
    @Test
    fun movedConsoleIsPickedOnlyWhenCertain() {
        val a = ConsoleInfo("192.168.1.20", "PS5-A", true)
        val b = ConsoleInfo("192.168.1.21", "PS5-B", true)
        assertNull(ConsoleDiscovery.pickMoved(listOf(a), "other"))
        assertEquals(a, ConsoleDiscovery.pickMoved(listOf(a), "PS5-A"))
        assertEquals(b, ConsoleDiscovery.pickMoved(listOf(a, b), "PS5-B"))
        assertNull(ConsoleDiscovery.pickMoved(listOf(a, b), "other"))
        assertNull(ConsoleDiscovery.pickMoved(emptyList(), "PS5-A"))
    }

    @Test
    fun otherConsoleAtSavedAddressIsNotTheRegisteredOne() {
        val a = ConsoleInfo("192.168.1.20", "PS5-A", true)
        assertTrue(ConsoleDiscovery.isRegistered(a, "PS5-A"))
        assertFalse(ConsoleDiscovery.isRegistered(a, "PS5-B"))
        assertTrue(ConsoleDiscovery.isRegistered(a, ""))
    }
}
