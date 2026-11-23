// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.xbox

/**
 * Xbox ICE adaylarındaki Teredo adresi (2001:0::/32): istemcinin IPv4 adresi ve UDP bağlantı noktası adresin içinde
 * ters çevrilmiş (bit bit tümleyen) durur. Windows köprüsü (ip-address `inspectTeredo`) bunlardan IPv4 adayı türetir.
 */
object Teredo {
    class Info(val client4: String, val udpPort: Int)

    /** [address] IPv6 değilse null. */
    fun inspect(address: String): Info? {
        val groups = parseIpv6(address) ?: return null
        val port = groups[5].inv() and 0xffff
        val client = ((groups[6] shl 16) or groups[7]).inv()
        val ip = listOf(24, 16, 8, 0).joinToString(".") { ((client ushr it) and 0xff).toString() }
        return Info(ip, port)
    }

    /** Sekiz 16 bitlik grup; "::" kısaltması açılır. Geçersizse null. */
    fun parseIpv6(address: String): IntArray? {
        val text = address.trim().removePrefix("[").removeSuffix("]").substringBefore('%')
        if (text.isEmpty() || text.count { it == ':' } < 2) return null
        val halves = text.split("::")
        if (halves.size > 2) return null
        fun groups(part: String): List<Int>? =
            if (part.isEmpty()) emptyList()
            else part.split(':').map { g -> if (g.length in 1..4) g.toIntOrNull(16) ?: return null else return null }
        val head = groups(halves[0]) ?: return null
        val tail = if (halves.size == 2) groups(halves[1]) ?: return null else emptyList()
        val missing = 8 - head.size - tail.size
        if (halves.size == 1 && missing != 0) return null
        if (halves.size == 2 && missing < 1) return null
        return (head + List(missing.coerceAtLeast(0)) { 0 } + tail).toIntArray()
    }
}
