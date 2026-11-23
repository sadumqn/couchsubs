// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.translation

import com.couchsubs.mobile.core.SubtitleSegmenter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Oyun terimleri örnek seti (Mac/iPhone: GameTermsTests, Windows: GameTermsTests; aynı satırlar). Ortak sözlük
 * (core/Sources/CouchSubsCore/Resources/glossary-en-tr.json) depodaki yerinden okunur. Gerçek ML Kit çağrılmaz.
 */
class GameTermsTest {
    private val builtIn: Glossary = Glossary.parse(File(System.getProperty("couchsubs.glossary")!!).readText(Charsets.UTF_8))

    private fun translate(sentence: String, engine: (String) -> String): String =
        FreeTranslation.translate(sentence, null, builtIn, { SubtitleSegmenter.normalizeCase(it, builtIn.capitalWords) }, engine)

    @Test
    fun calloutsUseTheirTurkishLine() {
        val samples = listOf(
            "Toss a smoke!" to "Sis bombası at!",
            "Reloading!" to "Şarjör değiştiriyorum!",
            "RELOADING!" to "Şarjör değiştiriyorum!",
            "Frag out!" to "Bomba atıyorum!",
            "Cover me, I’m reloading!" to "Şarjör değiştiriyorum, koru beni!",
            "Man down!" to "Yaralı var!",
            "Get down!" to "Yere yat!",
            "Move up." to "İlerleyin.",
            "- Contact!" to "Düşman var!",
        )
        for ((english, turkish) in samples) {
            val calls = mutableListOf<String>()
            assertEquals(english, turkish, translate(english) { calls.add(it); "?" })
            assertEquals(english, emptyList<String>(), calls)
        }
    }

    @Test
    fun slangAndWeaponTermsInLongerLines() {
        val samples = listOf(
            listOf("Toss a smoke and move up.", "Throw a Zarmon and move up.", "Bir Zarmon at ve ilerle.", "Bir sis bombası at ve ilerle."),
            listOf("THROW A FLASHBANG IN THERE!", "Throw a Zarmon in there!", "Oraya bir Zarmon at!", "Oraya bir flaş bombası at!"),
            listOf("Pop smoke, we're leaving.", "Throw a Zarmon, we're leaving.", "Bir Zarmon at, gidiyoruz.", "Bir sis bombası at, gidiyoruz."),
            listOf("Hostiles on the bridge.", "Enemies on the bridge.", "Köprüde düşmanlar.", "Köprüde düşmanlar."),
            listOf("Grab the medkit before you go.", "Grab the Zarmon before you go.", "Gitmeden Zarmon'u al.", "Gitmeden ilk yardım çantasını al."),
        )
        for ((english, sent, engineSays, turkish) in samples) {
            val calls = mutableListOf<String>()
            val result = translate(english) { calls.add(it); engineSays }
            assertEquals(english, sent, calls.first())
            assertEquals(english, turkish, result)
        }
    }

    @Test
    fun ordinarySentencesAreUnchanged() {
        for (english in listOf("I smell smoke.", "Turn on your flashlight.", "Where is the grenade launcher?", "I'm covering you.")) {
            val calls = mutableListOf<String>()
            translate(english) { calls.add(it); it }
            assertEquals(english, listOf(english), calls)
        }
    }

    @Test
    fun userGlossaryCanAddLinesAndPhrases() {
        val user = Glossary.parse("""{ "phrases": { "nerf": "weaken" }, "lines": { "GG!": "İyi oyundu" } }""")
        val merged = Glossary.merge(listOf(builtIn, user))
        assertEquals("İyi oyundu", merged.line("gg"))
        assertEquals("Weaken the boss", merged.plain("Nerf the boss"))
        assertNotEquals(builtIn.fingerprint, merged.fingerprint)
        assertTrue(merged.rewrites("They nerf it."))
        assertFalse(merged.rewrites("Nerfed."))
        // Bozuk düzenli ifade alınmaz.
        assertEquals("( a", Glossary.parse("""{ "phrases": { "(": "x" } }""").plain("( a"))
    }

    @Test
    fun cacheKeyFollowsLinesAndPhrases() {
        assertTrue(FreeTranslation.cacheKey("Reloading!", null, builtIn).startsWith(builtIn.fingerprint))
        assertTrue(FreeTranslation.cacheKey("Toss a smoke and go.", null, builtIn).startsWith(builtIn.fingerprint))
        assertEquals("I smell it.", FreeTranslation.cacheKey("I smell it.", null, builtIn))
    }

    /** Mac/iPhone ve Windows'la aynı iz: üç platformun önbellek anahtarları aynı kalır. */
    @Test
    fun fingerprintMatchesTheOtherPlatforms() {
        assertEquals(EXPECTED_FINGERPRINT, builtIn.fingerprint)
    }

    private companion object {
        const val EXPECTED_FINGERPRINT = "g978a414e"
    }
}
