// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core
import org.junit.Assert.*
import org.junit.Test
import org.json.JSONArray
class SubtitlePairingTest {
    @Test fun sharedLifecycleVectors() {
        val scenarios = JSONArray(Fixtures.text("subtitle-pairing.json"))
        for (i in 0 until scenarios.length()) {
            var time = 1000L
            val pairing = SubtitlePairing { time }
            var id = ""
            var previous = ""
            val name = scenarios.getJSONObject(i).getString("name")
            val steps = scenarios.getJSONObject(i).getJSONArray("steps")
            for (j in 0 until steps.length()) {
                val step = steps.getJSONObject(j)
                val who = if (step.optBoolean("wrong")) "not-the-request-secret" else if (step.optBoolean("previous")) previous else id
                when (val op = step.getString("op")) {
                    "session" -> pairing.setSession(step.getBoolean("value"))
                    "open" -> pairing.open()
                    "reset" -> pairing.reset()
                    "advance" -> time += step.getLong("ms")
                    "begin" -> { val ticket = pairing.begin(); assertEquals(name, step.getBoolean("ok"), ticket != null)
                        if (ticket != null) { assertEquals(22, ticket.id.length); assertEquals(6, ticket.code.length); previous = id; id = ticket.id } }
                    "resolve" -> assertEquals(name, step.getBoolean("ok"), pairing.resolve(who, step.getBoolean("accept")))
                    "poll" -> assertEquals(name, step.getString("state"), pairing.poll(who))
                    "pending" -> assertEquals(name, if (step.getString("state") == "current") id else null, pairing.pending?.id)
                    "isOpen" -> assertEquals(name, step.getBoolean("value"), pairing.isOpen)
                    else -> fail("Bilinmeyen adım: $op")
                }
            }
        }
    }

    @Test fun wireApprovalAndRotation() {
        val server = SubtitleServer(0, allowLegacy = false)
        val port = server.start()
        fun call(method: String, path: String, origin: String? = null): String = java.net.Socket("127.0.0.1", port).use { socket ->
            socket.soTimeout = 5000
            socket.getOutputStream().write(("$method $path HTTP/1.1\r\nHost: localhost:$port\r\n" + (origin?.let { "Origin: $it\r\n" } ?: "") + "\r\n").toByteArray())
            socket.getInputStream().readBytes().toString(Charsets.UTF_8)
        }
        try {
            assertTrue(call("POST", "/pair").startsWith("HTTP/1.1 409"))
            server.pairing.open()
            assertTrue(call("POST", "/pair", "https://foreign.example").startsWith("HTTP/1.1 403"))
            val ticket = org.json.JSONObject(call("POST", "/pair").substringAfter("\r\n\r\n"))
            val id = ticket.getString("id")
            assertFalse(call("GET", "/pair?id=$id").contains(server.accessKey))
            assertTrue(server.pairing.resolve(id, true))
            assertTrue(call("GET", "/pair?id=$id").contains(server.accessKey))
            assertFalse(call("GET", "/pair?id=wrong").contains(server.accessKey))
            server.rotateKey(SubtitleAccess.createKey())
            assertFalse(call("GET", "/pair?id=$id").contains(server.accessKey))
            assertTrue(call("GET", "/pair?id=$id").contains("expired"))
        } finally { server.stop() }
    }

    private fun call(port: Int, method: String, path: String): String = java.net.Socket("127.0.0.1", port).use { socket ->
        socket.soTimeout = 5000
        socket.getOutputStream().write("$method $path HTTP/1.1\r\nHost: localhost:$port\r\n\r\n".toByteArray())
        socket.getInputStream().readBytes().toString(Charsets.UTF_8)
    }

    /**
     * Sunucu yeni örnekle yeniden kurulunca (port değişti) eşleştirme durumu ve anahtar taşınır: TV'nin bekleyen isteği
     * onaylanabilir, anahtar TV'ye döner (Mac/iPhone: testReplacementServerSharesPairingAndKey). Sıradan kapanış
     * eşleştirmeyi kapatır.
     */
    @Test fun replacementServerKeepsPendingRequestAndKey() {
        val first = SubtitleServer(0, allowLegacy = false)
        val firstPort = first.start()
        first.pairing.open()
        val id = org.json.JSONObject(call(firstPort, "POST", "/pair").substringAfter("\r\n\r\n")).getString("id")
        first.stop(keepPairing = true)
        assertEquals(id, first.pairing.pending?.id)
        val second = SubtitleServer(0, key = first.accessKey, allowLegacy = false, pairing = first.pairing)
        val port = second.start()
        try {
            assertTrue(call(port, "GET", "/pair?id=$id").contains("pending"))
            assertTrue(second.pairing.resolve(id, true))
            assertTrue(call(port, "GET", "/pair?id=$id").contains(first.accessKey))
            // "TV eşleştir"in iki dakikası da taşındı: yeni TV isteği kabul edilir.
            assertTrue(call(port, "POST", "/pair").startsWith("HTTP/1.1 200"))
        } finally { second.stop() }
        assertFalse(second.pairing.isOpen)
        assertNull(second.pairing.pending)
    }

    @Test fun obsPageIsPublicButItsEventsNeedTheKeyOutsideTransition() {
        val html = "<html>Türkçe altyazı</html>"
        val server = SubtitleServer(0, allowLegacy = false, obsOverlay = html)
        val port = server.start()
        try {
            java.net.Socket("127.0.0.1", port).use { socket ->
                socket.getOutputStream().write("GET /obs HTTP/1.1\r\nHost: localhost\r\n\r\n".toByteArray())
                val reply = socket.getInputStream().readBytes().toString(Charsets.UTF_8)
                assertTrue(reply.startsWith("HTTP/1.1 200"))
                assertTrue(reply.contains("Content-Type: text/html; charset=utf-8"))
                assertTrue(reply.contains("Content-Length: ${html.toByteArray(Charsets.UTF_8).size}"))
                assertTrue(reply.endsWith(html)); assertFalse(reply.contains(server.accessKey))
            }
            java.net.Socket("127.0.0.1", port).use { socket ->
                socket.getOutputStream().write("GET /events?viewer=obs HTTP/1.1\r\nHost: localhost\r\n\r\n".toByteArray())
                assertTrue(socket.getInputStream().readBytes().toString(Charsets.UTF_8).startsWith("HTTP/1.1 401"))
            }
        } finally { server.stop() }
    }
}
