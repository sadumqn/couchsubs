// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.translation

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Telefonda yerel model (aynı ağdaki Ollama / LM Studio): Mac/iPhone LocalAIServer ve AIRequest ile aynı kurallar. */
class LocalAiTest {
    private val model = AiModel("qwen2.5:7b", "qwen2.5:7b")

    @Test
    fun addressesAreNormalizedLikeTheDesktop() {
        assertEquals("http://192.168.1.20:11434/v1", LocalAiServer.normalize("192.168.1.20:11434"))
        assertEquals("http://192.168.1.20:11434/v1", LocalAiServer.normalize(" http://192.168.1.20:11434/v1/chat/completions/ "))
        assertEquals("http://10.0.0.5:1234/v1", LocalAiServer.normalize("http://10.0.0.5:1234/v1/"))
        assertEquals("https://pc.local:8080/api", LocalAiServer.normalize("https://pc.local:8080/api"))
        assertNull(LocalAiServer.normalize(""))
        assertNull(LocalAiServer.normalize("ftp://pc:11434"))
        assertNull(LocalAiServer.normalize("192.168.1 .20"))
        assertNull(LocalAiServer.of("192.168.1.20:11434", " "))
    }

    @Test
    fun serverKindComesFromThePort() {
        assertEquals(LocalAiServer.Kind.OLLAMA, LocalAiServer.of("192.168.1.20:11434", "m")!!.kind)
        assertEquals(LocalAiServer.Kind.LM_STUDIO, LocalAiServer.of("192.168.1.20:1234", "m")!!.kind)
        assertEquals(LocalAiServer.Kind.OTHER, LocalAiServer.of("192.168.1.20:8000", "m")!!.kind)
        assertEquals("http://192.168.1.20:11434", LocalAiServer.of("192.168.1.20:11434/v1", "m")!!.address)
    }

    @Test
    fun ollamaRequestTurnsThinkingOffAndSendsNoKeyWhenEmpty() {
        val server = LocalAiServer.of("192.168.1.20:11434", model.id)!!
        val request = AiRequest.build(AiProvider.LOCAL, "", model, listOf("Hello."), emptyList(), server = server, instruction = "Keep swear words.")
        assertEquals("http://192.168.1.20:11434/v1/chat/completions", request.url)
        assertFalse(request.headers.containsKey("Authorization"))
        val body = JSONObject(request.body)
        assertEquals(false, body.getBoolean("think"))
        assertEquals("none", body.getString("reasoning_effort"))
        assertEquals("24h", body.getString("keep_alive"))
        assertEquals(false, body.getBoolean("stream"))
        assertEquals("system", body.getJSONArray("messages").getJSONObject(0).getString("role"))
        assertTrue(body.getJSONArray("messages").getJSONObject(0).getString("content").endsWith("Keep swear words."))
        val lmStudio = AiRequest.build(AiProvider.LOCAL, "secret", model, listOf("Hi."), emptyList(),
            server = LocalAiServer.of("192.168.1.20:1234", model.id))
        assertEquals("Bearer secret", lmStudio.headers["Authorization"])
        assertFalse(JSONObject(lmStudio.body).has("think"))
        assertFalse(JSONObject(lmStudio.body).has("keep_alive"))
    }

    @Test
    fun testConnectionRetriesOldOllamaWithoutThinkingFields() {
        val server = LocalAiServer.of("192.168.1.20:11434", model.id)!!
        val bodies = mutableListOf<String>()
        val http = Http { _, _, _, body, _ ->
            bodies.add(body!!)
            if (JSONObject(body).has("think")) 400 to "{\"error\":\"unknown field think\"}"
            else 200 to "{\"choices\":[{\"message\":{\"content\":\"[\\\"KRATOS: Şimdi gidiyoruz.\\\"]\"}}]}"
        }
        val (state, sample) = KeyCheck.aiSample(AiProvider.LOCAL, "", model, http, server)
        assertEquals(OnlineKeyState.VALID, state)
        assertEquals("KRATOS: Şimdi gidiyoruz.", sample)
        assertEquals(2, bodies.size)
    }

    @Test
    fun unreachableAndMissingModelAreReported() {
        val server = LocalAiServer.of("192.168.1.20:11434", model.id)!!
        assertEquals(OnlineKeyState.UNREACHABLE, KeyCheck.aiSample(AiProvider.LOCAL, "", model, { _, _, _, _, _ -> throw java.io.IOException("refused") }, server).first)
        assertEquals(OnlineKeyState.MODEL_REJECTED, KeyCheck.aiSample(AiProvider.LOCAL, "", model, { _, _, _, _, _ -> 404 to "{}" }, server).first)
        assertEquals(OnlineKeyState.UNREACHABLE, KeyCheck.aiSample(AiProvider.LOCAL, "", model, Http.Default, null).first)
    }
}
