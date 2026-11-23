// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import org.junit.Assert.assertEquals
import org.junit.Test
import java.net.InetAddress

class TvInstallNetworkTest {
    @Test
    fun selectsWifiIpv4WhenVpnOrCellularIsTheDefaultNetwork() {
        val networks = listOf(
            NetworkAddressCandidate(isWifi = true, isEthernet = false, isVpn = true, addresses = listOf(InetAddress.getByName("10.8.0.2"))),
            NetworkAddressCandidate(isWifi = false, isEthernet = false, isVpn = false, addresses = listOf(InetAddress.getByName("10.0.0.4"))),
            NetworkAddressCandidate(isWifi = false, isEthernet = true, isVpn = false, addresses = listOf(InetAddress.getByName("192.168.1.45"))),
            NetworkAddressCandidate(isWifi = true, isEthernet = false, isVpn = false, addresses = listOf(InetAddress.getByName("192.168.1.23"))),
        )

        assertEquals("192.168.1.23", phoneIpv4Address(networks))
    }

    @Test
    fun fallsBackToEthernetIpv4WhenWifiIsUnavailable() {
        val networks = listOf(
            NetworkAddressCandidate(isWifi = false, isEthernet = false, isVpn = true, addresses = listOf(InetAddress.getByName("10.8.0.2"))),
            NetworkAddressCandidate(isWifi = false, isEthernet = true, isVpn = false, addresses = listOf(InetAddress.getByName("192.168.1.45"))),
        )

        assertEquals("192.168.1.45", phoneIpv4Address(networks))
    }
}
