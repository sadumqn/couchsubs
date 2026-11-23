// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Perde (iPhone PerdeTests ile aynı kurallar): belirteçler tasarim.json'dan, hata metni ayrıştırma, kapak rengi, hareket kapısı. */
class PerdeTest {
    @Test
    fun tokensComeFromTasarimJson() {
        // DesignTokens derlemede tasarim.json'dan üretilir; koyu varsayılan ve Perde v2 değerleri.
        val json = File(System.getProperty("user.dir")).let { dir ->
            generateSequence(dir) { it.parentFile }.map { File(it, "design/yeni-arayuz/tasarim.json") }.first { it.exists() }
        }.readText()
        val tokens = org.json.JSONObject(json)
        assertEquals(tokens.getInt("version"), DesignTokens.VERSION)
        assertEquals(tokens.getString("defaultTheme") == "dark", DesignTokens.DEFAULT_DARK)
        // #RRGGBB → 0xFFRRGGBB, #RRGGBBAA → 0xAARRGGBB (dosyadaki değerle birebir).
        fun argb(hex: String): Long {
            val h = hex.removePrefix("#")
            return (if (h.length == 6) "FF$h" else h.substring(6) + h.substring(0, 6)).toLong(16)
        }
        val colors = tokens.getJSONObject("color")
        assertEquals(argb(colors.getJSONObject("background").getString("dark")), DesignTokens.Dark.background)
        assertEquals(argb(colors.getJSONObject("background").getString("light")), DesignTokens.Light.background)
        assertEquals(argb(colors.getJSONObject("amberSoft").getString("dark")), DesignTokens.Dark.amberSoft)
        assertEquals(0x24F5B83DL, DesignTokens.Dark.amberSoft)
        assertEquals(16f, DesignTokens.Space.screenEdgeIOS)
        assertEquals(1600, DesignTokens.Motion.livePulse)
    }

    @Test
    fun errorTextSplitsIntoTitleStepsAndDetails() {
        val (title, steps, extra) = InstallErrorText.parse("TV yanıt vermedi. TV'yi açın. Aynı Wi-Fi'a bağlayın.\n\nAyrıntı: 192.168.1.5 sürüm 0.9.81")
        assertEquals("TV yanıt vermedi.", title)
        assertEquals(listOf("TV'yi açın.", "Aynı Wi-Fi'a bağlayın."), steps)
        assertEquals(listOf("Ayrıntı: 192.168.1.5 sürüm 0.9.81"), extra)
    }

    @Test
    fun coverPaletteMatchesIphoneHash() {
        // iPhone DSCoverArt.paletteIndex: 7 tohum, ×31 + karakter, 32 bit taşma, 8 palet.
        assertEquals(1, coverPaletteIndex("Grand Theft Auto V"))
        assertEquals(3, coverPaletteIndex("Death Stranding 2"))
        // Kısaltma yalnız harf (en çok 3), sıra numarası ayrı (iPhone DSCoverArt.monogram / numeral).
        assertEquals("GTA", monogram("Grand Theft Auto V"))
        assertEquals("GTA", monogram("Grand Theft Auto VI"))
        assertEquals("VI", coverNumeral("Grand Theft Auto VI"))
        assertEquals("RDR", monogram("Red Dead Redemption 2"))
        assertEquals("2", coverNumeral("Red Dead Redemption 2"))
        assertEquals("Ma", monogram("Mafia"))
        assertEquals(null, coverNumeral("Mafia"))
        assertEquals("ACS", monogram("Assassin's Creed Shadows"))
        assertEquals("GTA", monogram("GTA V"))
    }

    @Test
    fun motionGateStopsAmbientWhileTranslating() {
        assertTrue(MotionGate(reduced = false, translating = false, active = true).ambient)
        assertEquals(false, MotionGate(reduced = false, translating = true, active = true).ambient)
        assertTrue(MotionGate(reduced = false, translating = true, active = true).live)
        assertEquals(false, MotionGate(reduced = true, translating = false, active = true).live)
        assertEquals(false, MotionGate(reduced = false, translating = false, active = false).ambient)
    }
}
