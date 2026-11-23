// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.translation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.net.SocketException
import java.net.SocketTimeoutException

/** DeepL bağlantısının sıcak tutulması ve kopan bağlantıda tek yeniden deneme (Windows #433, Mac/iPhone ile aynı). */
class DeepLConnectionTest {
    /** İlk istekte [firstError]'ı atar, sonra [status] ile yanıtlar. */
    private class FlakyHttp(private val firstError: IOException?, private val status: Int = 200) : Http {
        var count = 0
        override fun send(method: String, url: String, headers: Map<String, String>, body: String?, timeoutMs: Int): Pair<Int, String> {
            count++
            if (count == 1 && firstError != null) throw firstError
            return status to """{"translations":[{"text":"Kapıyı aç."}]}"""
        }
    }

    private class RecordingLocal : com.couchsubs.mobile.core.TextTranslator {
        val calls = mutableListOf<String>()
        override fun translate(text: String): String = "yerel: $text".also { calls += text }
    }

    /** Açık tutulan bağlantıyı sunucu sessizce kapatmışsa satır yedek çeviriye düşmeden bir kez daha denenir. */
    @Test
    fun droppedKeepAliveConnectionIsRetriedOnce() {
        val http = FlakyHttp(SocketException("Connection reset"))
        val local = RecordingLocal()
        val translator = DeepLTranslator("abc:fx", local, http)
        assertEquals("Kapıyı aç.", translator.translate("Open the door."))
        assertEquals(2, http.count)
        assertTrue(local.calls.isEmpty())
        assertNull(translator.lastError)
    }

    /** Zaman aşımında satır zaten bekledi: yeniden denenmez, yerel çeviriye düşer. */
    @Test
    fun timeoutIsNotRetried() {
        val http = FlakyHttp(SocketTimeoutException("timeout"))
        val translator = DeepLTranslator("abc:fx", RecordingLocal(), http)
        assertEquals("yerel: Open the door.", translator.translate("Open the door."))
        assertEquals(1, http.count)
    }

    /** DeepL'in yanıtladığı hatalar (çok sık istek, kota, anahtar) yeniden denenmez. */
    @Test
    fun serviceErrorsAreNotRetried() {
        for (status in listOf(429, 456, 403)) {
            val http = FlakyHttp(null, status)
            val translator = DeepLTranslator("abc:fx", RecordingLocal(), http)
            assertEquals("$status", "yerel: Run!", translator.translate("Run!"))
            assertEquals("$status", 1, http.count)
        }
    }

    /** İki kez kopan bağlantı yedek çeviriye düşer (sonsuz deneme yok). */
    @Test
    fun secondFailureFallsBack() {
        val http = object : Http {
            var count = 0
            override fun send(method: String, url: String, headers: Map<String, String>, body: String?, timeoutMs: Int): Pair<Int, String> {
                count++
                throw SocketException("Connection reset")
            }
        }
        val translator = DeepLTranslator("abc:fx", RecordingLocal(), http)
        assertEquals("yerel: Run!", translator.translate("Run!"))
        assertEquals(2, http.count)
    }

    /** Hata sonrası bekleme 15 sn; sıcak tutma 40 sn'de bir, son çeviriden sonra 10 dk (Windows ve Mac/iPhone ile aynı). */
    @Test
    fun timings() {
        assertEquals(15_000L, DeepLTranslator.RETRY_AFTER_MS)
        assertEquals(40_000L, DeepLConnectionWarmer.KEEP_WARM_EVERY_MS)
        assertEquals(600_000L, DeepLConnectionWarmer.KEEP_WARM_FOR_MS)
    }

    /** Son çeviriden sonra 10 dk sıcak tutulur, sonra durur; yeni çeviri yeniden başlatır. */
    @Test
    fun warmerStopsAfterIdleWindow() {
        var now = 1_000_000L
        val warmer = DeepLConnectionWarmer(clock = { now }) {}
        assertNull(warmer.nextPing())
        warmer.touch("abc:fx")
        assertEquals("abc:fx", warmer.nextPing())
        now += DeepLConnectionWarmer.KEEP_WARM_FOR_MS
        assertEquals("abc:fx", warmer.nextPing())
        now += 1
        assertNull(warmer.nextPing())
        warmer.touch("abc:fx")
        assertEquals("abc:fx", warmer.nextPing())
    }
}
