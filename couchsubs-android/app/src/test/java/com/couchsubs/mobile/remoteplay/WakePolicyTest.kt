// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.remoteplay

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Kullanıcı PS5'i kapatınca (dinlenme modu) yeniden bağlanma döngüsü PS5'i yeniden açmamalı; eskiden açıyordu ve ana
 * ekran PS5 kapatılmış görünürken "PS5 bağlı" diyordu (Mac/iPhone WakePolicyTests ile aynı).
 */
class WakePolicyTest {
    @Test
    fun wakesOnlyBeforeFirstConnection() {
        val policy = WakePolicy()
        assertEquals(WakePolicy.Action.WAKE, policy.action(false))
        assertEquals(WakePolicy.Action.CONNECT, policy.action(true))
        assertEquals(WakePolicy.Action.CONNECT, policy.action(null))
        policy.streamed()
        assertEquals(WakePolicy.Action.WAIT_UNTIL_ON, policy.action(false))
        assertEquals(WakePolicy.Action.CONNECT, policy.action(true))
        assertEquals(WakePolicy.Action.CONNECT, policy.action(null))
    }

    @Test
    fun newStartWakesAgain() {
        val policy = WakePolicy()
        policy.streamed()
        policy.reset()
        assertEquals(WakePolicy.Action.WAKE, policy.action(false))
    }
}
