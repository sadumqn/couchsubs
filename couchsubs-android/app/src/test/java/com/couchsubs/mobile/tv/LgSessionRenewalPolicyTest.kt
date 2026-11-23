// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LgSessionRenewalPolicyTest {
    @Test
    fun renewalThrottleIsPerHostAndStillSkipsRepeatedChecks() {
        val renewedAt = mutableMapOf<String, Long>()
        val renewedHosts = mutableListOf<String>()
        val t0 = 1_000_000_000L

        fun renew(host: String, now: Long): Int? {
            val key = LgSessionRenewalPolicy.storageKey(host)
            return LgSessionRenewalPolicy.renewIfDue(
                now = now,
                lastRenewedAt = renewedAt[key],
                saveRenewedAt = { renewedAt[key] = it },
                renew = { renewedHosts.add(host); 1000 },
            )
        }

        assertEquals(1000, renew("192.168.1.10", t0))
        assertEquals(1000, renew("192.168.1.20", t0 + 60 * 60 * 1000L))
        assertNull(renew("192.168.1.20", t0 + 2 * 60 * 60 * 1000L))

        assertEquals(listOf("192.168.1.10", "192.168.1.20"), renewedHosts)
        assertEquals(t0, renewedAt[LgSessionRenewalPolicy.storageKey("192.168.1.10")])
        assertEquals(t0 + 60 * 60 * 1000L, renewedAt[LgSessionRenewalPolicy.storageKey("192.168.1.20")])
    }

    @Test
    fun storageKeyNormalizesHostWhitespaceAndCase() {
        assertEquals(LgSessionRenewalPolicy.storageKey("tv.example"), LgSessionRenewalPolicy.storageKey(" TV.Example "))
    }
}
