// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.translation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Gemini'nin dakikalık sınırı (Windows: AiTranslatorTests, Mac/iPhone: AITranslationTests ile aynı kurallar). */
class RateLimitTest {
    private class Clock(var now: Long = 1_000_000L) {
        fun read() = now
    }

    /** Sırayla verilen yanıtları döner; bitince son yanıt tekrar eder. */
    private class ScriptedHttp(vararg replies: Pair<Int, String>) : Http {
        private val replies = replies.toMutableList()
        var count = 0
        override fun send(method: String, url: String, headers: Map<String, String>, body: String?, timeoutMs: Int): Pair<Int, String> {
            count++
            return if (replies.size > 1) replies.removeAt(0) else replies.first()
        }
    }

    private val ok = 200 to """{"candidates":[{"content":{"parts":[{"text":"[\"Koş!\"]"}]}}]}"""
    private val perMinute = 429 to """{"error":{"code":429,"details":[
        {"@type":"type.googleapis.com/google.rpc.QuotaFailure","violations":[
            {"quotaId":"GenerateRequestsPerMinutePerProjectPerModel-FreeTier","quotaValue":"5"}]},
        {"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"7s"}]}}"""
    private val perDay = 429 to """{"error":{"code":429,"details":[
        {"@type":"type.googleapis.com/google.rpc.QuotaFailure","violations":[
            {"quotaId":"GenerateRequestsPerDayPerProjectPerModel-FreeTier","quotaValue":"20"}]}]}}"""

    private val model = AiModel("gemini-x", "Hızlı")

    /**
     * Anahtar denemesinde Gemini yoğunsa (503, zaman aşımı, dakikalık sınır) anahtar reddedilmez, kaydedilir; bağlantı
     * kurulamadıysa kaydedilmez. Günlük sınır kota hatasıdır.
     */
    @Test
    fun busyServiceDoesNotRejectTheKey() {
        val overloaded = 503 to """{"error":{"code":503,"message":"The model is overloaded. Please try again later.","status":"UNAVAILABLE"}}"""
        for ((reply, expected) in listOf(overloaded to OnlineKeyState.BUSY, perMinute to OnlineKeyState.BUSY,
                                         perDay to OnlineKeyState.QUOTA_EXCEEDED, ok to OnlineKeyState.VALID)) {
            val state = KeyCheck.ai(AiProvider.GEMINI, "key", model, ScriptedHttp(reply))
            assertEquals(reply.first.toString(), expected, state)
            assertTrue(KeyCheck.accepted(state))
        }
        val slow = object : Http {
            override fun send(method: String, url: String, headers: Map<String, String>, body: String?, timeoutMs: Int): Pair<Int, String> =
                throw java.net.SocketTimeoutException("timeout")
        }
        assertEquals(OnlineKeyState.BUSY, KeyCheck.ai(AiProvider.GEMINI, "key", model, slow))
        val offline = object : Http {
            override fun send(method: String, url: String, headers: Map<String, String>, body: String?, timeoutMs: Int): Pair<Int, String> =
                throw java.net.UnknownHostException("generativelanguage.googleapis.com")
        }
        val state = KeyCheck.ai(AiProvider.GEMINI, "key", model, offline)
        assertEquals(OnlineKeyState.UNREACHABLE, state)
        assertFalse(KeyCheck.accepted(state))
    }

    @Test
    fun perMinuteLimitIsParsed() {
        assertEquals(AiRateLimit(7_000L, 5), AiRequest.rateLimit(perMinute.first, perMinute.second))
        assertNull(AiRequest.rateLimit(perDay.first, perDay.second))
        assertNull(AiRequest.rateLimit(429, "{}"))
        assertNull(AiRequest.rateLimit(500, perMinute.second))
    }

    @Test
    fun budgetSlidesOverOneMinute() {
        val clock = Clock()
        val budget = RequestBudget(2, clock::read)
        assertTrue(budget.take())
        assertTrue(budget.take())
        assertFalse(budget.take())
        clock.now += RequestBudget.WINDOW_MS
        assertTrue(budget.take())
        budget.lower(1)
        assertEquals(1, budget.perMinute)
        budget.lower(10)
        assertEquals(1, budget.perMinute)
    }

    @Test
    fun perMinuteLimitFallsBackSilentlyAndRetriesSoon() {
        val clock = Clock()
        val http = ScriptedHttp(perMinute, ok)
        val budget = RequestBudget(15, clock::read)
        val translator = AiTranslator(AiProvider.GEMINI, "key", model, { "yerel: $it" }, http, clock = clock::read, budget = budget)
        assertEquals("yerel: Run!", translator.translate("Run!"))
        // Dakikalık sınır hata değildir: ana ekranda uyarı çıkmaz, hizmetin bildirdiği sınıra inilir.
        assertNull(translator.lastError)
        assertEquals(5, budget.perMinute)
        // Hizmetin önerdiği 7 saniye dolmadan istek gitmez, dolunca gider (eskiden bir dakika beklenirdi).
        clock.now += 6_000
        assertEquals("yerel: Go!", translator.translate("Go!"))
        assertEquals(1, http.count)
        clock.now += 1_000
        assertEquals("Koş!", translator.translate("Run!"))
        assertEquals(2, http.count)
    }

    /**
     * Model cümleyi çevirmeden geri verirse cümle yerel çeviriyle yeniden denenir ve yanıt önbelleğe yazılmaz (#245:
     * qwen2.5:3b "You think I'm on the run?" cümlesini olduğu gibi döndürdü, hat onu Türkçe sanıp göstermedi). Yerel
     * çeviri de aynı kalırsa (ad) modelin yanıtı kalır ve önbelleğe yazılır.
     */
    @Test
    fun echoedSentenceIsRetriedLocallyAndNotCached() {
        val echo = 200 to """{"candidates":[{"content":{"parts":[{"text":"[\"You think I'm on the run?\"]"}]}}]}"""
        val http = ScriptedHttp(echo)
        val asked = mutableListOf<String>()
        val translator = AiTranslator(AiProvider.GEMINI, "key", model, { asked.add(it); "yerel: $it" }, http,
            budget = RequestBudget(1000))
        assertEquals("Tommy: yerel: You think I'm on the run?", translator.translate("Tommy: You think I'm on the run?"))
        assertEquals(listOf("You think I'm on the run?"), asked)
        translator.translate("Tommy: You think I'm on the run?")
        assertEquals(2, http.count)

        val name = 200 to """{"candidates":[{"content":{"parts":[{"text":"[\"Thomas Angelo.\"]"}]}}]}"""
        val names = ScriptedHttp(name)
        val same = AiTranslator(AiProvider.GEMINI, "key", model, { it }, names, budget = RequestBudget(1000))
        assertEquals("Thomas Angelo.", same.translate("Thomas Angelo."))
        same.translate("Thomas Angelo.")
        assertEquals(1, names.count)
    }

    /**
     * Model dizide cümleyi boş bırakırsa (#296) cümle yerel çeviriyle denenir; yerel çeviri de boşsa cümle olduğu gibi
     * kalır. İki durumda da boş yanıt önbelleğe yazılmaz (Windows: EmptyItemIsRetriedLocallyAndNotCached).
     */
    @Test
    fun emptyItemIsRetriedLocallyAndNotCached() {
        val empty = 200 to """{"candidates":[{"content":{"parts":[{"text":"[\"\"]"}]}}]}"""
        val http = ScriptedHttp(empty)
        val asked = mutableListOf<String>()
        val translator = AiTranslator(AiProvider.GEMINI, "key", model, { asked.add(it); "yerel: $it" }, http,
            budget = RequestBudget(1000))
        assertEquals("yerel: Doesn't 00k good.", translator.translate("Doesn't 00k good."))
        assertEquals(listOf("Doesn't 00k good."), asked)
        translator.translate("Doesn't 00k good.")
        assertEquals(2, http.count)

        val blankHttp = ScriptedHttp(empty)
        val blank = AiTranslator(AiProvider.GEMINI, "key", model, { "" }, blankHttp, budget = RequestBudget(1000))
        assertEquals("Doesn't 00k good.", blank.translate("Doesn't 00k good."))
        blank.translate("Doesn't 00k good.")
        assertEquals(2, blankHttp.count)
    }

    @Test
    fun perMinutePauseIsAtMostTwentySeconds() {
        val clock = Clock()
        val slow = 429 to perMinute.second.replace("\"7s\"", "\"45s\"")
        val http = ScriptedHttp(slow, ok)
        val translator = AiTranslator(AiProvider.GEMINI, "key", model, { "yerel: $it" }, http, clock = clock::read,
            budget = RequestBudget(15, clock::read))
        translator.translate("Run!")
        clock.now += SentenceTranslator.RATE_LIMIT_PAUSE_MS
        assertEquals("Koş!", translator.translate("Run!"))
    }

    @Test
    fun spentBudgetSendsNoRequest() {
        val clock = Clock()
        val http = ScriptedHttp(ok)
        val translator = AiTranslator(AiProvider.GEMINI, "key", model, { "yerel: $it" }, http, clock = clock::read,
            budget = RequestBudget(1, clock::read))
        assertEquals("Koş!", translator.translate("Run!"))
        assertEquals("yerel: Go!", translator.translate("Go!"))
        assertEquals(1, http.count)
        assertNull(translator.lastError)
        clock.now += RequestBudget.WINDOW_MS
        translator.translate("Stop!")
        assertEquals(2, http.count)
    }

    @Test
    fun cachedSentencesSurviveServicePauseWithoutLocalWork() {
        for (failure in listOf("server", "timeout", "invalid-reply", "daily-quota", "minute-quota")) {
            val clock = Clock()
            var requests = 0
            val http = object : Http {
                override fun send(method: String, url: String, headers: Map<String, String>, body: String?, timeoutMs: Int): Pair<Int, String> {
                    requests++
                    return when (failure) {
                        "timeout" -> throw java.net.SocketTimeoutException("timeout")
                        "invalid-reply" -> 200 to "{}"
                        "daily-quota" -> perDay
                        "minute-quota" -> perMinute
                        else -> 503 to "{}"
                    }
                }
            }
            val cache = TranslationCache()
            cache.store("Run!", "Koş!")
            cache.store("Hide!", "Saklan!")
            val calls = mutableListOf<String>()
            val translator = AiTranslator(AiProvider.GEMINI, "key", model,
                { calls.add(it); "yerel: $it" }, http, cache, clock = clock::read, budget = RequestBudget(15, clock::read))
            assertEquals("yerel: Wait!", translator.translate("Wait!"))
            val error = translator.lastError
            assertEquals(failure, "KRATOS: Koş! Saklan!", translator.translate("KRATOS: Run! Hide!"))
            assertEquals(failure, 1, requests)
            assertEquals(failure, listOf("Wait!"), calls)
            assertEquals(failure, error, translator.lastError)
            // Eksik parçada hata sonrası yerel yol ve HTTP beklemesi korunur.
            assertEquals("yerel: Run! Jump!", translator.translate("Run! Jump!"))
            assertEquals(listOf("Wait!", "Run! Jump!"), calls)
            assertEquals(1, requests)
            assertNull(cache.get("Run! Jump!"))
        }
    }

    @Test
    fun dailyLimitIsShownAndPausesAMinute() {
        val clock = Clock()
        val http = ScriptedHttp(perDay, ok)
        val translator = AiTranslator(AiProvider.GEMINI, "key", model, { "yerel: $it" }, http, clock = clock::read,
            budget = RequestBudget(15, clock::read))
        assertEquals("yerel: Run!", translator.translate("Run!"))
        assertEquals(OnlineKeyState.QUOTA_EXCEEDED, translator.lastError)
        clock.now += SentenceTranslator.RATE_LIMIT_PAUSE_MS
        translator.translate("Go!")
        assertEquals(1, http.count)
        clock.now += SentenceTranslator.RETRY_AFTER_MS
        translator.translate("Run!")
        assertEquals(2, http.count)
    }

    @Test
    fun modelLimitComesFromTheCatalog() {
        val limited = AiModel("gemini-rpm-test", "Hızlı", requestsPerMinute = 3)
        assertEquals(3, RequestBudget.shared(AiProvider.GEMINI, limited)?.perMinute)
        assertNull(RequestBudget.shared(AiProvider.GEMINI, model))
    }

    // --- Yerel çeviri yokken (Windows: AiTranslatorTests, DeepLTranslatorTests; Mac/iPhone: AITranslationTests) ---

    private fun failsWithoutLocal(block: () -> Unit) {
        try { block(); throw AssertionError("yerel çeviri yokken hata beklenirdi") } catch (_: java.io.IOException) {}
    }

    /**
     * Dakikalık hak uygulamanın temkinli tahminidir. Yerel çeviri yokken hak bitince satır denenmeden düşüyordu; ara
     * sahnede satırların yarısı hiç çevrilmiyordu. İstek yine gönderilmeli.
     */
    @Test
    fun overBudgetWithoutLocalStillSendsRequest() {
        val clock = Clock()
        val http = ScriptedHttp(ok)
        val translator = AiTranslator(AiProvider.GEMINI, "key", model, null, http, clock = clock::read,
            budget = RequestBudget(1, clock::read))
        assertEquals("Koş!", translator.translate("Run!"))
        assertEquals("Koş!", translator.translate("Go!"))
        assertEquals(2, http.count)
    }

    /** Yerel çeviri hata verirse de (motor açılamadı) hak bitince istek gönderilir. */
    @Test
    fun overBudgetWithFailingLocalStillSendsRequest() {
        val clock = Clock()
        val http = ScriptedHttp(ok)
        val translator = AiTranslator(AiProvider.GEMINI, "key", model, { throw IllegalStateException("model yok") }, http,
            clock = clock::read, budget = RequestBudget(1, clock::read))
        assertEquals("Koş!", translator.translate("Run!"))
        assertEquals("Koş!", translator.translate("Go!"))
        assertEquals(2, http.count)
    }

    /** Hata sonrası bir dakikalık beklemede yerel çeviri yoksa hizmet yine denenir; satır düşmez. */
    @Test
    fun errorPauseWithoutLocalStillTriesService() {
        val clock = Clock()
        val http = ScriptedHttp(503 to "{}", ok)
        val translator = AiTranslator(AiProvider.GEMINI, "key", model, null, http, clock = clock::read,
            budget = RequestBudget(1000, clock::read))
        failsWithoutLocal { translator.translate("Run!") }
        assertEquals("Koş!", translator.translate("Go!"))
        assertEquals(2, http.count)
    }

    /** Hizmetin dakikalık 429'undan sonraki kısa bekleme yerel çeviri olmasa da korunur. */
    @Test
    fun perMinutePauseHoldsWithoutLocal() {
        val clock = Clock()
        val http = ScriptedHttp(perMinute, ok)
        val translator = AiTranslator(AiProvider.GEMINI, "key", model, null, http, clock = clock::read,
            budget = RequestBudget(1000, clock::read))
        failsWithoutLocal { translator.translate("Run!") }
        failsWithoutLocal { translator.translate("Go!") }
        assertEquals(1, http.count)
    }

    private val deepLOk = 200 to """{"translations":[{"text":"Koş!"}]}"""

    /** DeepL'de de hata sonrası beklemede yerel çeviri yoksa DeepL yine denenir. */
    @Test
    fun deepLErrorPauseWithoutLocalStillTriesDeepL() {
        val http = ScriptedHttp(503 to "{}", deepLOk)
        val translator = DeepLTranslator("abc:fx", null, http)
        failsWithoutLocal { translator.translate("Run!") }
        assertEquals("Koş!", translator.translate("Go!"))
        assertEquals(2, http.count)
    }

    /** DeepL 429 (çok sık istek) sonrası bekleme yerel çeviri olmasa da korunur. */
    @Test
    fun deepLTooManyRequestsPauseHoldsWithoutLocal() {
        val http = ScriptedHttp(429 to "{}", deepLOk)
        val translator = DeepLTranslator("abc:fx", null, http)
        failsWithoutLocal { translator.translate("Run!") }
        failsWithoutLocal { translator.translate("Go!") }
        assertEquals(1, http.count)
    }
}
