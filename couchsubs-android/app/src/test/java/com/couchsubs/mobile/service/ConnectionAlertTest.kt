// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.service

import com.couchsubs.mobile.remoteplay.DisconnectKind
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** "PS5 bağlantısı koptuğunda bildir": iPhone ConnectionAlert ile aynı kural. */
class ConnectionAlertTest {
    @Test
    fun postsWhenAStreamDropsInTheBackground() {
        assertTrue(ConnectionAlert.shouldPost(wasStreaming = true, kind = DisconnectKind.NETWORK, demo = false, enabled = true, appVisible = false))
    }

    @Test
    fun staysQuietOtherwise() {
        assertFalse(ConnectionAlert.shouldPost(true, DisconnectKind.STOPPED, demo = false, enabled = true, appVisible = false))
        assertFalse(ConnectionAlert.shouldPost(false, DisconnectKind.NETWORK, demo = false, enabled = true, appVisible = false))
        assertFalse(ConnectionAlert.shouldPost(true, null, demo = false, enabled = true, appVisible = false))
        assertFalse(ConnectionAlert.shouldPost(true, DisconnectKind.NETWORK, demo = true, enabled = true, appVisible = false))
        assertFalse(ConnectionAlert.shouldPost(true, DisconnectKind.NETWORK, demo = false, enabled = false, appVisible = false))
        assertFalse(ConnectionAlert.shouldPost(true, DisconnectKind.NETWORK, demo = false, enabled = true, appVisible = true))
    }
}
