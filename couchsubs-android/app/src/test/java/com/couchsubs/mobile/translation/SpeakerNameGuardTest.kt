// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.translation

import com.couchsubs.mobile.core.TextTranslator
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #287: konuşan etiketinden öğrenilen adlar cümle içinde çeviriden korunur (Mac/iPhone: FreeLineTranslatorTests,
 * AITranslationTests, SubtitleTextTests; Windows: MarianTranslatorTests, AiTranslatorTests, GlossaryTests).
 */
class SpeakerNameGuardTest {
    private class Engine(private val map: (String) -> String) : (String) -> String {
        val calls = mutableListOf<String>()
        override fun invoke(input: String): String = map(input).also { calls.add(input) }
    }

    @Test
    fun speakerNamesAreKeptOnlyWhenWrittenAsNames() {
        val names = SpeakerNameGuard()
        names.learn("OLD MAN")
        names.learn("Freya")
        assertEquals(setOf("Freya"), names.protected)
        names.learn("CAPTAIN PRICE")
        names.learn("Ghost")
        names.learn("RADIO")
        assertEquals(setOf("Freya", "Ghost", "Price"), names.protected)
        assertEquals(listOf("Ghost", "Price"), SpeakerNameGuard.occurring(names.protected, "Ghost, ghostly ghost. Price!", exact = true))
        assertEquals(emptyList<String>(), SpeakerNameGuard.occurring(listOf("Ghost"), "a ghostly ghost", exact = true))

        val base = Glossary.parse("""{ "keep": ["Kratos"] }""")
        val glossary = base.keepingNames(names.protected, "Price, get down! The price is high.")
        assertEquals(listOf("Price"), glossary.find("Price, get down! The price is high. Pricey.").map { it.english })
        assertTrue(base.fingerprint != glossary.fingerprint)
        // Satırda geçmeyen ad eklenmez; sözlük aynı kalır.
        assertSame(base, base.keepingNames(names.protected, "Nothing here."))
    }

    @Test
    fun learnedSpeakerNameIsKeptInsideSentences() {
        val engine = Engine {
            when (it) {
                "Move." -> "Hareket et."
                "Zarmon, get down right now!" -> "Zarmon, hemen yere yat!"
                "The price is Pricey." -> "Fiyat pahalı."
                "Soldier, get down right now!" -> "Asker, hemen yere yat!"
                else -> "?"
            }
        }
        val translator = FreeLineTranslator(engine = engine)
        translator.translate("PRICE: Move.")
        assertEquals("Price, hemen yere yat!", translator.translate("Price, get down right now!"))
        assertEquals("Fiyat pahalı.", translator.translate("The price is Pricey."))
        translator.translate("SOLDIER: Move.")
        assertEquals("Asker, hemen yere yat!", translator.translate("Soldier, get down right now!"))
        assertEquals(listOf("Move.", "Zarmon, get down right now!", "The price is Pricey.",
            "The price is Pricey. *** Move.", "Move.", "Soldier, get down right now!"), engine.calls)

        // Hat satır başındaki adı ayırıp yalnız cümleyi verir ("Price: Get down right now!"); ad ayrıca bildirilir.
        val separated: TextTranslator = FreeLineTranslator(engine = engine)
        separated.noteSpeaker("Price")
        assertEquals("Price, hemen yere yat!", separated.translate("Price, get down right now!"))
    }

    /** Gelen istemleri saklar, her cümleyi "[tr] cümle" diye çevirir. */
    private class PromptHttp : Http {
        val prompts = mutableListOf<String>()
        override fun send(method: String, url: String, headers: Map<String, String>, body: String?, timeoutMs: Int): Pair<Int, String> {
            val user = JSONObject(body!!).getJSONArray("contents").getJSONObject(0).getJSONArray("parts").getJSONObject(0).getString("text")
            prompts.add(user)
            val sentences = org.json.JSONArray(user.substringAfterLast('\n'))
            val reply = org.json.JSONArray((0 until sentences.length()).map { "[tr] " + sentences.getString(it) }).toString()
            val parts = org.json.JSONArray().put(JSONObject().put("text", reply))
            return 200 to JSONObject().put("candidates", org.json.JSONArray().put(JSONObject().put("content", JSONObject().put("parts", parts)))).toString()
        }
    }

    @Test
    fun learnedSpeakerNamesAreNamedInThePrompt() {
        val http = PromptHttp()
        val translator = AiTranslator(AiProvider.GEMINI, "key", AiModel("gemini-x", "Hızlı"), { "yerel: $it" }, http,
            budget = RequestBudget(1000))
        translator.translate("PRICE: Move.")
        assertFalse("Character names" in http.prompts[0])
        translator.translate("SOLDIER: Price, get down!")
        assertTrue("Character names (keep them exactly as written, do not translate them): Price\n" in http.prompts[1])
        assertFalse("Soldier" in http.prompts[1])
        translator.translate("It looks ghostly, price is high.")
        assertFalse("Character names" in http.prompts[2])
    }
}
